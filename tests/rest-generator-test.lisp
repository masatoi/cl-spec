;;;; tests/rest-generator-test.lisp

(defpackage #:cl-spec/tests/rest-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing #:signals)
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

(defvar *keyword-value-observations* nil
  "Raw rest tail and effective :A binding observed by KEYWORD-VALUE-TARGET.")

(defun keyword-value-target (&rest raw &key a)
  "Collect the raw rest tail and the effective first-occurrence :A binding."
  (push (list (copy-list raw) a) *keyword-value-observations*)
  (list raw))

(defun keyword-value-contract (rest-spec value-spec)
  "A contract over REST-SPEC whose sole declared keyword :A takes VALUE-SPEC."
  (make-instance 'cl-spec:function-spec
                 :name 'keyword-value-target
                 :argument-specs `(&rest (raw ,rest-spec)
                                  &key ((:a a) ,value-spec))
                 :return-spec 'list))

(deftest constrained-keyword-values-follow-their-value-spec
  (testing "a constant value spec reaches the call as its constant, not as T"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec:defspec nothing null)
      (dolist (entry '((null nil) ((member nil) nil) (nothing nil) ((member t) t)))
        (destructuring-bind (value-spec expected) entry
          (let ((*keyword-value-observations* nil))
            (testing (format nil "value spec ~S" value-spec)
              (let ((result (cl-spec:check-function
                             (keyword-value-contract
                              '(list-of t :min-length 2 :max-length 2) value-spec)
                             :trials 10 :seed 3)))
                (ok (eq :passed (cl-spec:property-result-status result)))
                (ok (zerop (cl-spec:property-result-rejected result)))
                (ok (= 10 (length *keyword-value-observations*)))
                (ok (every (lambda (observation)
                             (and (equal (list :a expected) (first observation))
                                  (eq expected (second observation))))
                           *keyword-value-observations*))))))))))

(deftest constrained-keyword-tails-repeat-keys-with-their-values
  (testing "a reused keyword repeats both the key and its generated value"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*keyword-value-observations* nil))
      (cl-spec:defspec nothing null)
      (let ((result (cl-spec:check-function
                     (keyword-value-contract '(list-of t :min-length 4) 'nothing)
                     :trials 10 :seed 5)))
        (ok (eq :passed (cl-spec:property-result-status result)))
        (ok (zerop (cl-spec:property-result-rejected result)))
        (ok (= 10 (length *keyword-value-observations*)))
        (ok (every (lambda (observation)
                     (equal '(:a nil :a nil) (first observation)))
                   *keyword-value-observations*))
        (ok (every (lambda (observation) (null (second observation)))
                   *keyword-value-observations*))))))

(defun bare-keyword-call-generator (rest-spec)
  "Compile the call generator for an empty &key section over REST-SPEC."
  (cl-spec/src/backends/check-it-generators:spec-generator
   (cl-spec:function-spec-argument-schema
    (make-instance 'cl-spec:function-spec
                   :name 'keyword-value-target
                   :argument-specs `(&rest (raw ,rest-spec) &key)
                   :return-spec 'list))
   (list :registry cl-spec:*registry*)))

(deftest bare-keyword-tails-report-and-propose-pair-removal
  (testing "an empty &key tail is removable exactly when removal is proposed"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (testing "a bounded control tail can grow, so a pair is removable"
        (let ((generator (bare-keyword-call-generator
                          '(list-of t :min-length 0 :max-length 2))))
          (ok (cl-spec/src/backends/call-generators:call-generator-removable-p generator))
          (setf (check-it:cached-value generator) '(:allow-other-keys t))
          (ok (null (check-it:shrink generator
                                     (lambda (candidate)
                                       (declare (ignore candidate))
                                       nil))))))
      (testing "a fixed-length control tail advertises no removal"
        (ok (not (cl-spec/src/backends/call-generators:call-generator-removable-p
                  (bare-keyword-call-generator
                   '(list-of t :min-length 2 :max-length 2)))))))))

(defun bare-keyword-fixed-target (&rest raw &key)
  "Return the raw tail; its contract's postcondition always fails."
  raw)

(defun bare-keyword-flexible-target (&rest raw &key)
  "Return the raw tail; its contract's postcondition always fails."
  raw)

(deftest fixed-control-keyword-tails-keep-a-valid-counterexample
  (testing "a fixed-length control tail cannot shrink out of its schema"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec:defspec-function bare-keyword-fixed-target
        (:args &rest (raw (list-of t :min-length 2 :max-length 2)) &key)
        (:returns list)
        (:post (and result (not result))))
      (let* ((result (cl-spec:check-function 'bare-keyword-fixed-target :trials 10 :seed 2))
             (evidence (or (cl-spec:property-result-shrunk-evidence result)
                           (cl-spec:property-result-failure-evidence result)))
             (arguments (cl-spec:trial-observation-arguments evidence)))
        (ok (eq :failed (cl-spec:property-result-status result)))
        (ok (eq :none (cl-spec:property-result-shrunk-outcome result)))
        (ok (= 2 (length arguments)))
        (ok (eq :allow-other-keys (first arguments)))
        (ok (eq t (second arguments)))
        (ok (eq :same-failure
                (getf (cl-spec:recheck-counterexample
                       (cl-spec:make-counterexample-artifact result)
                       :state-policy :stateless)
                      :status)))))))

(deftest bounded-control-keyword-tails-stay-schema-valid
  (testing "shrinking a bounded control tail never leaves the declared schema"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec:defspec-function bare-keyword-flexible-target
        (:args &rest (raw (list-of t :min-length 0 :max-length 2)) &key)
        (:returns list)
        (:post (and result (not result))))
      (let* ((contract (cl-spec:find-function-spec 'bare-keyword-flexible-target))
             (result (cl-spec:check-function 'bare-keyword-flexible-target
                                             :trials 10 :seed 2))
             (evidence (or (cl-spec:property-result-shrunk-evidence result)
                           (cl-spec:property-result-failure-evidence result)))
             (arguments (cl-spec:trial-observation-arguments evidence)))
        (ok (eq :failed (cl-spec:property-result-status result)))
        (ok (cl-spec:validp (cl-spec:function-spec-argument-schema contract) arguments))
        (ok (evenp (length arguments)))
        (ok (<= (length arguments) 2))
        (ok (eq :same-failure
                (getf (cl-spec:recheck-counterexample
                       (cl-spec:make-counterexample-artifact result)
                       :state-policy :stateless)
                      :status)))))))

(defvar *unsatisfiable-keyword-calls* 0
  "Number of times UNSATISFIABLE-KEYWORD-TARGET was called.")

(defun unsatisfiable-keyword-target (&rest raw &key a)
  "Count calls; an unsatisfiable keyword tail must never reach it."
  (declare (ignore raw a))
  (incf *unsatisfiable-keyword-calls*)
  t)

(deftest unsatisfiable-keyword-lengths-refuse-without-calling-the-target
  (testing "an odd fixed tail length is refused before the target runs"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*unsatisfiable-keyword-calls* 0))
      (cl-spec:defspec-function unsatisfiable-keyword-target
        (:args &rest (raw (list-of t :min-length 3 :max-length 3))
               &key ((:a a) integer))
        (:returns t))
      (ok (signals (cl-spec:check-function 'unsatisfiable-keyword-target
                                           :trials 5 :seed 1)
                   'cl-spec:generator-unavailable))
      (ok (zerop *unsatisfiable-keyword-calls*)))))

(deftest repeated-keyword-binds-the-first-occurrence
  (testing "the raw rest keeps both pairs and the binding takes the first value"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*keyword-value-observations* nil))
      (let ((result (cl-spec:check-function
                     (keyword-value-contract '(list-of t :min-length 4) '(member 1 2))
                     :trials 20 :seed 8)))
        (ok (eq :passed (cl-spec:property-result-status result)))
        (ok (zerop (cl-spec:property-result-rejected result)))
        (ok (= 20 (length *keyword-value-observations*)))
        (ok (every (lambda (observation)
                     (let ((raw (first observation)))
                       (and (equal '(:a :a)
                                   (loop for tail on raw by #'cddr collect (car tail)))
                            (member (second raw) '(1 2))
                            (eql (second observation) (second raw)))))
                   *keyword-value-observations*))))))

(defvar *named-rest-tails* nil
  "Raw rest tails observed by NAMED-REST-TARGET.")

(defun named-rest-target (&rest raw &key a)
  "Collect the raw rest tail; its spec is always registered under a name."
  (declare (ignore a))
  (push (copy-list raw) *named-rest-tails*)
  (list raw))

(deftest named-universal-rests-use-the-keyword-shortcut
  (testing "a rest spec registered under a name is classified like its inline form"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec:defspec bounded-tail (list-of t :min-length 2))
      (cl-spec:defspec alias-tail bounded-tail)
      (cl-spec:defspec plain-tail (list-of t))
      (dolist (entry '((bounded-tail 2 . 2) (alias-tail 2 . 2) (plain-tail 0 . 2)))
        (destructuring-bind (rest-spec minimum . maximum) entry
          (let ((*named-rest-tails* nil))
            (testing (format nil "rest spec ~S" rest-spec)
              (let ((result (cl-spec:check-function
                             (make-instance 'cl-spec:function-spec
                                            :name 'named-rest-target
                                            :argument-specs `(&rest (raw ,rest-spec)
                                                             &key ((:a a) integer))
                                            :return-spec 'list)
                             :trials 10 :seed 6)))
                (ok (eq :passed (cl-spec:property-result-status result)))
                (ok (zerop (cl-spec:property-result-rejected result)))
                (ok (= 10 (length *named-rest-tails*)))
                (ok (every (lambda (tail)
                             (and (evenp (length tail))
                                  (<= minimum (length tail) maximum)
                                  (loop for rest on tail by #'cddr
                                        always (eq (car rest) :a))))
                           *named-rest-tails*))))))))))

(defvar *custom-rest-tails* nil
  "Raw rest tails observed by CUSTOM-REST-TARGET.")

(defun custom-rest-target (&rest raw &key a)
  "Collect the raw rest tail drawn by the rest spec's custom generator."
  (declare (ignore a))
  (push (copy-list raw) *custom-rest-tails*)
  (list raw))

(deftest generator-annotated-named-rests-keep-their-owner
  (testing "a custom generator on the named rest spec is not replaced by keyword pairs"
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
          (*custom-rest-tails* nil))
      (cl-spec:defgenerator fixed-tail () '(:a 7))
      (cl-spec:defspec owned-tail (list-of t :min-length 2) (:generator fixed-tail))
      (let ((result (cl-spec:check-function
                     (make-instance 'cl-spec:function-spec
                                    :name 'custom-rest-target
                                    :argument-specs '(&rest (raw owned-tail)
                                                     &key ((:a a) integer))
                                    :return-spec 'list)
                     :trials 10 :seed 4)))
        (ok (eq :passed (cl-spec:property-result-status result)))
        (ok (= 10 (length *custom-rest-tails*)))
        (ok (every (lambda (tail) (equal '(:a 7) tail)) *custom-rest-tails*))))))
