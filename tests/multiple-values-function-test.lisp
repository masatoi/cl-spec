;;;; tests/multiple-values-function-test.lisp

(defpackage #:cl-spec/tests/multiple-values-function-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:make-function-check-property
                #:function-spec-post-value-variables
                #:function-spec-return-spec)
  (:import-from #:cl-spec/src/execution #:evaluate-trial #:failure-identities-match-p)
  (:import-from #:cl-spec/src/dsl #:defspec-function)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry #:find-function-spec)
  (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form))

(in-package #:cl-spec/tests/multiple-values-function-test)

(defvar *returned* nil)
(defvar *calls* 0)

(defun multiple-target ()
  (incf *calls*)
  (values-list *returned*))

(defun classify (returns)
  (let ((contract (make-instance 'function-spec :name 'multiple-target :return-spec returns)))
    (multiple-value-list (evaluate-trial (make-function-check-property contract) nil))))

(deftest fixed-return-counts-distinguish-zero-nil-and-two-values
  (let ((*calls* 0) (*returned* nil))
    (ok (eq :passed (first (classify '(values)))))
    (setf *returned* '(nil))
    (ok (eq :failed (first (classify '(values)))))
    (ok (eq :passed (first (classify '(values null)))))
    (setf *returned* '(1 "two"))
    (let ((evidence (classify '(values integer string))))
      (ok (eq :passed (first evidence)))
      (ok (= 1 (sixth evidence))))
    (ok (= 4 *calls*))))

(deftest explicit-post-values-dsl-is-supported
  (ok (macroexpand-1
       '(defspec-function multiple-target
          (:returns (values integer string))
          (:post-values (number text) (and (= result number) (stringp text)))))))

(deftest malformed-fixed-return-syntax-is-refused-during-expansion
  (dolist (declaration '((values &optional integer) (values &rest integer)
                         (values integer . string)))
    (ok (signals
         (macroexpand-1 `(defspec-function multiple-target (:returns ,declaration)))
         'invalid-function-spec-form))))

(deftest explicit-post-errors-retain-invoked-outcome
  (let* ((*returned* '(1 "two")) (*calls* 0)
         (contract (make-instance 'function-spec :name 'multiple-target
                                 :return-spec '(values integer string)
                                 :post-value-variables '(number text) :postconditions '(t)
                                 :postcondition-function
                                 (lambda (returned)
                                   (declare (ignore returned))
                                   (error "broken post predicate"))))
         (evidence (multiple-value-list
                    (evaluate-trial (make-function-check-property contract) nil))))
    (ok (eq :error (first evidence)))
    (ok (eq :contract-error (second evidence)))
    (ok (typep (fifth evidence) 'simple-error))
    (ok (seventh evidence))
    (ok (= 1 *calls*))))

(deftest untagged-explicit-post-failure-has-unknown-identity
  (let* ((*returned* '(1))
         (contract (make-instance 'function-spec :name 'multiple-target
                                 :return-spec '(values integer) :post-value-variables '(x)
                                 :postconditions '(nil)
                                 :postcondition-function (constantly nil)))
         (evidence (multiple-value-list
                    (evaluate-trial (make-function-check-property contract) nil))))
    (ok (eq :postcondition (second evidence)))
    (ok (not (failure-identities-match-p (third evidence) (third evidence))))))

(deftest malformed-post-values-declarations-and-reinitializations-are-refused
  (dolist (form '((defspec-function multiple-target (:returns integer) (:post-values (x) t))
                  (defspec-function multiple-target (:returns (values integer))
                    (:post-values () t))
                  (defspec-function multiple-target (:returns (values integer))
                    (:post-values (result) t))
                  (defspec-function multiple-target (:args (x integer))
                    (:returns (values integer)) (:post-values (x) t))
                  (defspec-function multiple-target (:returns (values integer))
                    (:post t) (:post-values (x) t))))
    (ok (signals (macroexpand-1 form) 'invalid-function-spec-form)))
  (let* ((contract (make-instance 'function-spec :name 'multiple-target
                                 :return-spec '(values integer)
                                 :post-value-variables '(x) :postconditions '(t)
                                 :postcondition-function (lambda (values)
                                                           (declare (ignore values)) t)))
         (returns (function-spec-return-spec contract)))
    (ok (signals (reinitialize-instance contract :return-spec 'integer)
                 'invalid-function-spec-form))
    (ok (eq returns (function-spec-return-spec contract)))
    (ok (signals (reinitialize-instance contract :post-value-variables '(y))
                 'invalid-function-spec-form))
    (ok (equal '(x) (function-spec-post-value-variables contract)))))

(deftest legacy-post-and-explicit-empty-post-conventions
  (let ((*registry* (make-hash-table-registry)) (*returned* '(3 "secondary")))
    (defspec-function multiple-target
      (:returns (values integer string))
      (:post (= result 3)))
    (ok (eq :passed
            (evaluate-trial
             (make-function-check-property (find-function-spec 'multiple-target)) nil)))
    (setf *returned* nil)
    (defspec-function multiple-target
      (:returns (values))
      (:post-values () (null result)))
    (let ((contract (find-function-spec 'multiple-target)))
      (ok (null (function-spec-post-value-variables contract)))
      (ok (eq :passed (evaluate-trial (make-function-check-property contract) nil))))))

(deftest fixed-return-errors-preserve-count-and-position-identity
  (let ((*returned* '(1)) (*calls* 0))
    (let ((missing (classify '(values integer string))))
      (ok (eq :return-values (first (third missing))))
      (setf *returned* '(1 "two" :extra))
      (let ((extra (classify '(values integer string))))
        (ok (not (equal (third missing) (third extra))))))
    (let ((*returned* '("bad" 1)))
      (let ((first-position (classify '(values integer integer))))
        (setf *returned* '(1 "bad"))
        (ok (not (equal (third first-position)
                        (third (classify '(values integer integer))))))))))

(deftest fixed-return-and-post-failures-do-not-cross-during-shrinking
  (let* ((*registry* (make-hash-table-registry))
         (*returned* '("bad" t))
         (contract (defspec-function multiple-target
                     (:returns (values integer boolean))
                     (:post-values (number flag) (and flag (plusp number)))))
         (property (make-function-check-property contract))
         (return-failure (multiple-value-list (evaluate-trial property nil))))
    (setf *returned* '(-1 t))
    (let ((post-failure (multiple-value-list (evaluate-trial property nil))))
      (ok (eq :return-spec (second return-failure)))
      (ok (eq :postcondition (second post-failure)))
      (ok (not (failure-identities-match-p (third return-failure) (third post-failure))))
      (ok (not (failure-identities-match-p (third post-failure) (third return-failure)))))
    (ok (failure-identities-match-p
         '(:return-value :return-spec ((:kind :type-failed :expected (:type integer))))
         '(:return-value :postcondition (:post-form 0))))))

(deftest explicit-post-values-see-all-values-and-implicit-result-remains-primary
  (let ((*registry* (make-hash-table-registry)) (*returned* '(3 "three")) (*calls* 0))
    (defspec-function multiple-target
      (:returns (values integer string))
      (:post-values (number text) (and (= result number) (= number (length text)))))
    (let* ((property (make-function-check-property (find-function-spec 'multiple-target)))
           (evidence (multiple-value-list (evaluate-trial property nil))))
      (ok (eq :failed (first evidence)))
      (ok (eq :postcondition (second evidence)))
      (ok (eq :return-values (first (third evidence))))
      (ok (= 3 (sixth evidence)))
      (setf *returned* '(5 "three"))
      (ok (eq :passed (evaluate-trial property nil)))
      (ok (= 2 *calls*)))))
