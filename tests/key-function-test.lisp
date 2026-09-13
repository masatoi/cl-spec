;;;; tests/key-function-test.lisp

(defpackage #:cl-spec/tests/key-function-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/dsl #:defspec-function #:defproperty)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:function-spec-argument-specs #:function-spec-source-form
                #:make-function-check-property)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:make-hash-table-registry #:find-function-spec)
  (:import-from #:cl-spec/src/property #:property-named-arguments #:property-call-arguments-p)
  (:import-from #:cl-spec/src/schema #:definition-digest)
  (:import-from #:cl-spec/src/execution #:evaluate-trial)
  (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form #:invalid-property-form))

(in-package #:cl-spec/tests/key-function-test)

(defvar *calls* 0)
(defvar *defaults* 0)
(defvar *raw* nil)

(defun key-target (&rest arguments &key ((:size size) (progn (incf *defaults*) 10)))
  (incf *calls*)
  (setf *raw* arguments)
  size)

(deftest explicit-key-declarations-construct-and-preserve-raw-call
  (let* ((*calls* 0) (*defaults* 0) (*raw* nil)
         (contract (make-instance 'function-spec :name 'key-target
                                 :argument-specs '(&key ((:size amount) integer present-p))
                                 :return-spec 'integer
                                 :preconditions '(t)
                                 :precondition-function
                                 (lambda (amount present-p) (and (= amount 2) present-p))))
         (property (make-function-check-property contract)))
    (ok (eq :passed (evaluate-trial property '(:size 2 :size 99))))
    (ok (equal '(:size 2 :size 99) *raw*))
    (ok (equal '(amount 2 present-p t)
               (property-named-arguments property '(:size 2 :size 99))))
    (ok (= 1 *calls*))
    (ok (zerop *defaults*))))

(deftest key-dsl-expands-with-explicit-mappings
  (ok (macroexpand-1
       '(defspec-function key-target
          (:args &key ((:size amount) integer present-p))
          (:pre (or (not present-p) (integerp amount)))
          (:returns integer))))
  (ok (signals
       (macroexpand-1 '(defproperty invalid (&key ((:size amount) integer)) t))
       'invalid-property-form)))

(deftest key-dsl-predicates-bind-presence-and-target-defaults-run-only-at-invocation
  (let ((*registry* (make-hash-table-registry)) (*calls* 0) (*defaults* 0) (*raw* nil))
    (defspec-function key-target
      (:args &key ((:size amount) (or null integer) present-p))
      (:pre (or (not present-p) (null amount)))
      (:returns (or null integer))
      (:post (if present-p (null result) (= result 10))))
    (let* ((contract (find-function-spec 'key-target))
           (property (make-function-check-property contract)))
      (ok (consp (function-spec-source-form contract)))
      (ok (zerop *defaults*))
      (ok (eq :passed (evaluate-trial property nil)))
      (ok (eq :passed (evaluate-trial property '(:size nil))))
      (ok (equal '(amount nil present-p nil) (property-named-arguments property nil)))
      (ok (equal '(amount nil present-p t)
                 (property-named-arguments property '(:size nil))))
      (ok (= 1 *defaults*))
      (ok (= 2 *calls*))
      (ok (eq :rejected (evaluate-trial property '(:size 3))))
      (ok (= 2 *calls*)))))

(deftest key-declaration-reinitialization-refusal-restores-previous-state
  (let* ((contract (make-instance 'function-spec :name 'key-target))
         (before (function-spec-argument-specs contract)))
    (ok (signals
         (reinitialize-instance contract
                                :argument-specs '(&key ((:size amount) integer amount)))
         'invalid-function-spec-form))
    (ok (eq before (function-spec-argument-specs contract)))))

(deftest implicit-and-reserved-key-declarations-stay-rejected
  (dolist (args '((&key (amount integer))
                 (&key ((:allow-other-keys permission) boolean))
                 (&key ((:size amount) integer) &allow-other-keys ((:more more) integer))
                 (&aux (aux list))))
    (ok (signals (make-instance 'function-spec :name 'key-target :argument-specs args)
                 'invalid-function-spec-form))))

(deftest keyword-control-shape-uses-the-first-occurrence
  (let* ((contract (make-instance 'function-spec :name 'key-target
                                 :argument-specs '(&key ((:size amount) integer))))
         (property (make-function-check-property contract)))
    (ok (not (property-call-arguments-p property '(:unknown 1))))
    (ok (property-call-arguments-p property '(:unknown 1 :allow-other-keys t)))
    (ok (not (property-call-arguments-p
              property '(:unknown 1 :allow-other-keys nil :allow-other-keys t))))
    (ok (property-call-arguments-p
         property '(:unknown 1 :allow-other-keys t :allow-other-keys nil)))
    (ok (not (property-call-arguments-p property '(:size))))
    (reinitialize-instance contract
                           :argument-specs '(&key ((:size amount) integer) &allow-other-keys))
    (ok (property-call-arguments-p property '(:unknown 1 :allow-other-keys nil)))))

(deftest external-key-and-allow-other-keys-are-digest-semantics
  (flet ((digest (args)
           (definition-digest
            (make-instance 'function-spec :name 'key-target :argument-specs args))))
    (ok (not (equal (digest '(&key ((:size amount) integer)))
                    (digest '(&key ((:length amount) integer))))))
    (ok (not (equal (digest '(&key ((:size amount) integer)))
                    (digest '(&key ((:size amount) integer) &allow-other-keys)))))
    (ok (not (equal (digest '(&key ((:size amount) integer given-p)))
                    (digest '(&key ((:size amount) integer present-p))))))))

(deftest optional-prefix-consumes-before-keyword-tail
  (let* ((contract (make-instance 'function-spec :name 'key-target
                                 :argument-specs
                                 '((required integer) &optional (optional t optional-p)
                                   &key ((:size amount) integer present-p))))
         (property (make-function-check-property contract)))
    (ok (equal '(required 1 optional :size optional-p t amount nil present-p nil)
               (property-named-arguments property '(1 :size))))
    (ok (equal '(required 1 optional nil optional-p t amount 2 present-p t)
               (property-named-arguments property '(1 nil :size 2))))
    (ok (not (property-call-arguments-p property '(1 :size 2))))))
