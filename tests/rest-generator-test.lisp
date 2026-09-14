;;;; tests/rest-generator-test.lisp

(defpackage #:cl-spec/tests/rest-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/rest-generator-test)

(defvar *seen* nil)

(defvar *draws* 0)

(defvar *validations* 0)

(defun counted-rest-p (value)
  (declare (ignore value))
  (incf *validations*)
  t)

(defun summed-rest (&rest items)
  (push (copy-list items) *seen*)
  (reduce #'+ items :initial-value 0))

(deftest generated-rest-lists-cover-empty-and-nonempty-calls
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*seen* nil))
    (cl-spec:defspec-function summed-rest
      (:args &rest (items (list-of (range integer 0 30))))
      (:returns integer)
      (:post (= result (reduce #'+ items :initial-value 0))))
    (let ((result (cl-spec:check-function 'summed-rest :trials 200 :seed 42)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (= 200 (length *seen*)))
      (ok (member nil *seen*))
      (ok (some (lambda (items) (> (length items) 1)) *seen*))
      (ok (every (lambda (items) (<= (length items) 20)) *seen*)))))

(deftest rest-driven-calls-validate-only-once
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*seen* nil) (*validations* 0))
    (cl-spec:defgenerator fixed-rest () (list 1))
    (cl-spec:defspec counted-rest
      (and (list-of integer) (satisfies counted-rest-p))
      (:generator fixed-rest))
    (cl-spec:defspec-function summed-rest
      (:args &rest (items counted-rest))
      (:returns integer))
    (let ((result (cl-spec:check-function 'summed-rest :trials 1 :seed 42)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (= 1 *validations*))
      (ok (equal '((1)) *seen*)))))

(defun failed-rest (&rest items)
  (declare (ignore items))
  nil)

(deftest rest-value-shrinking-preserves-fixed-tuple-length
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function failed-rest
      (:args &rest (items (tuple (range integer 20 40) (range integer 20 40))))
      (:returns (member t)))
    (let* ((result (cl-spec:check-function 'failed-rest :trials 1 :seed 42))
           (original (cl-spec:trial-observation-arguments
                      (cl-spec:property-result-failure-evidence result)))
           (shrunk (cl-spec:property-result-shrunk-evidence result)))
      (ok (some (lambda (value) (> value 20)) original))
      (ok shrunk)
      (when shrunk
        (ok (equal '(20 20) (cl-spec:trial-observation-arguments shrunk)))
        (ok (eq :same-failure
                (getf (cl-spec:recheck-counterexample
                       (cl-spec:make-counterexample-artifact result) :state-policy :stateless)
                      :status)))))))

(defun combined-rest (&rest raw &key (limit 42))
  (push (copy-list raw) *seen*)
  limit)

;; The target's lambda list deliberately mixes &OPTIONAL, &REST and &KEY, which
;; SBCL reports as a style warning.  That shape is what this file tests, so the
;; warning is muffled for this one definition.
#+sbcl
(declaim (sb-ext:muffle-conditions sb-kernel:&optional-and-&key-in-lambda-list))

(defun optional-rest-key (&optional option &rest raw &key limit)
  (push (list option (copy-list raw) limit) *seen*)
  nil)

#+sbcl
(declaim (sb-ext:unmuffle-conditions sb-kernel:&optional-and-&key-in-lambda-list))

(deftest generation-combines-unconstrained-rest-and-declared-keys
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*seen* nil))
    (cl-spec:defspec-function combined-rest
      (:args &rest (raw (list-of t)) &key ((:limit limit) integer supplied))
      (:returns integer)
      (:post (equal (getf raw :limit 42) result)))
    (let ((result (cl-spec:check-function 'combined-rest :trials 100 :seed 42)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (member nil *seen*))
      (ok (some #'consp *seen*)))))

(deftest constrained-rest-and-key-intersection-generates-and-shrinks-valid-calls
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*seen* nil))
    (cl-spec:defspec-function combined-rest
      (:args &rest (raw (tuple (member :limit) (range integer 20 40)))
             &key ((:limit limit) (range integer 30 40)))
      (:returns (member :never)))
    (let* ((result (cl-spec:check-function 'combined-rest :trials 1 :seed 42))
           (shrunk (cl-spec:property-result-shrunk-evidence result)))
      (ok (eq :failed (cl-spec:property-result-status result)))
      (ok (every (lambda (raw)
                   (and (= 2 (length raw)) (eq :limit (first raw))
                        (<= 30 (second raw) 40)))
                 *seen*))
      (ok shrunk)
      (when shrunk
        (ok (equal '(:limit 30) (cl-spec:trial-observation-arguments shrunk)))))))

(deftest impossible-rest-key-intersection-stops-after-bounded-draws
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*seen* nil) (*draws* 0))
    (cl-spec:defgenerator impossible-tail-generator ()
      (incf *draws*)
      (list :limit -1))
    (cl-spec:defspec impossible-tail
      (tuple (member :limit) (member -1))
      (:generator impossible-tail-generator))
    (cl-spec:defspec-function combined-rest
      (:args &rest (raw impossible-tail) &key ((:limit limit) (range integer 0 10)))
      (:returns integer))
    (let ((condition (handler-case
                         (progn (cl-spec:check-function 'combined-rest :trials 1 :seed 42) nil)
                       (cl-spec:generator-unavailable (condition) condition))))
      (ok condition)
      (ok (= 100 *draws*))
      (ok (null *seen*)))))

(deftest shrinking-preserves-optional-prefix-before-constrained-rest-key-tail
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*seen* nil))
    (cl-spec:defspec-function optional-rest-key
      (:args &optional (option (range integer 10 20))
             &rest (raw (tuple (member :limit) (range integer 30 40)))
             &key ((:limit limit) (range integer 30 40)))
      (:returns (member t)))
    (let* ((result (cl-spec:check-function 'optional-rest-key :trials 1 :seed 42))
           (shrunk (cl-spec:property-result-shrunk-evidence result)))
      (ok (every (lambda (entry)
                   (destructuring-bind (option raw limit) entry
                     (and (<= 10 option 20) (equal raw (list :limit limit))
                          (<= 30 limit 40))))
                 *seen*))
      (ok shrunk)
      (when shrunk
        (ok (equal '(10 :limit 30) (cl-spec:trial-observation-arguments shrunk)))))))

(deftest constrained-universal-rest-is-not-the-keyword-shortcut
  (testing "a length or uniqueness constraint keeps the rest list out of the shortcut"
    (ok (cl-spec/src/backends/call-generators::unconstrained-rest-list-p
         (cl-spec:normalize-spec-form '(list-of t))))
    (ok (not (cl-spec/src/backends/call-generators::unconstrained-rest-list-p
              (cl-spec:normalize-spec-form '(list-of t :min-length 4)))))
    (ok (not (cl-spec/src/backends/call-generators::unconstrained-rest-list-p
              (cl-spec:normalize-spec-form '(list-of t :max-length 3)))))
    (ok (not (cl-spec/src/backends/call-generators::unconstrained-rest-list-p
              (cl-spec:normalize-spec-form '(list-of t :unique t))))))
  (testing "the constrained rest child is generated instead of omitted"
    (let* ((contract (make-instance 'cl-spec:function-spec
                                    :name 'constrained-rest-probe
                                    :argument-specs
                                    '(&rest (raw (list-of integer :min-length 4))
                                      &key ((:limit limit) integer supplied))))
           (schema (cl-spec:function-spec-argument-schema contract))
           (generator (cl-spec/src/backends/check-it-generators:spec-generator
                       schema (list :registry cl-spec:*registry*))))
      (ok (typep generator 'cl-spec/src/backends/call-generators:call-arguments-generator))
      (ok (cl-spec/src/backends/call-generators:call-generator-rest-driven-p generator)))))

(defvar *keyword-rest-tails* nil
  "Raw rest tails observed by KEYWORD-REST-TARGET.")

(defun keyword-rest-target (&rest raw &key a b c)
  "Collect the raw rest tail; it must satisfy the rest length and the keyword rules."
  (declare (ignore a b c))
  (push (copy-list raw) *keyword-rest-tails*)
  (list raw))

(deftest constrained-universal-rest-generates-keyword-tails
  (testing "a universal length-constrained rest is filled with keyword pairs"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*keyword-rest-tails* nil))
      (cl-spec:defspec-function keyword-rest-target
        (:args &rest (raw (list-of t :min-length 4 :max-length 6))
               &key ((:a a) integer) ((:b b) integer) ((:c c) integer))
        (:returns list))
      (let ((result (cl-spec:check-function 'keyword-rest-target :trials 20 :seed 42)))
        (ok (eq :passed (cl-spec:property-result-status result)))
        (ok (zerop (cl-spec:property-result-rejected result)))
        (ok (= 20 (length *keyword-rest-tails*)))
        (ok (every (lambda (tail)
                     (and (evenp (length tail))
                          (<= 4 (length tail) 6)))
                   *keyword-rest-tails*))))))

(defvar *reused-keyword-tails* nil
  "Raw rest tails observed by REUSED-KEYWORD-TARGET.")

(defun reused-keyword-target (&rest raw &key a)
  "Collect the raw rest tail, which must reuse :A to reach the declared minimum."
  (declare (ignore a))
  (push (copy-list raw) *reused-keyword-tails*)
  (list raw))

(deftest constrained-universal-rest-reuses-declared-keywords
  (testing "a minimum longer than the distinct keyword count repeats a declared key"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*reused-keyword-tails* nil))
      (cl-spec:defspec-function reused-keyword-target
        (:args &rest (raw (list-of t :min-length 4))
               &key ((:a a) integer))
        (:returns list))
      (let ((result (cl-spec:check-function 'reused-keyword-target :trials 20 :seed 7)))
        (ok (eq :passed (cl-spec:property-result-status result)))
        (ok (zerop (cl-spec:property-result-rejected result)))
        (ok (= 20 (length *reused-keyword-tails*)))
        (ok (every (lambda (tail)
                     (and (evenp (length tail))
                          (<= 4 (length tail))
                          (>= (count :a tail) 2)))
                   *reused-keyword-tails*))))))

(defvar *control-keyword-tails* nil
  "Raw rest tails observed by CONTROL-KEYWORD-TARGET.")

(defun control-keyword-target (&rest raw &key)
  "Collect a raw rest tail filled from the :ALLOW-OTHER-KEYS control pair."
  (push (copy-list raw) *control-keyword-tails*)
  (list raw))

(deftest constrained-universal-rest-fills-a-bare-keyword-section
  (testing "an empty &key section still admits the :ALLOW-OTHER-KEYS control pair"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*control-keyword-tails* nil))
      (cl-spec:defspec-function control-keyword-target
        (:args &rest (raw (list-of t :min-length 4))
               &key)
        (:returns list))
      (let ((result (cl-spec:check-function 'control-keyword-target :trials 20 :seed 11)))
        (ok (eq :passed (cl-spec:property-result-status result)))
        (ok (zerop (cl-spec:property-result-rejected result)))
        (ok (= 20 (length *control-keyword-tails*)))
        (ok (every (lambda (tail)
                     (and (evenp (length tail))
                          (<= 4 (length tail))
                          (loop for (key value) on tail by #'cddr
                                always (and (eq key :allow-other-keys) (eq value t)))))
                   *control-keyword-tails*))))))
