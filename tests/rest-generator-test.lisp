;;;; tests/rest-generator-test.lisp

(defpackage #:cl-spec/tests/rest-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/rest-generator-test)

(defvar *seen* nil)

(defvar *draws* 0)

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

(defun optional-rest-key (&optional option &rest raw &key limit)
  (push (list option (copy-list raw) limit) *seen*)
  nil)

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
