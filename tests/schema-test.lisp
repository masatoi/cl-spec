;;;; tests/schema-test.lisp

(defpackage #:cl-spec/tests/schema-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/src/dsl #:defspec #:defproperty #:defgenerator #:defspec-function)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/introspection #:spec-data #:property-data #:function-spec-data)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/schema
                #:definition-digest #:definition-description #:definition-constraints)
  (:import-from #:cl-spec/src/property-runner #:run-property #:result-data)
  (:import-from #:cl-spec/src/function-spec #:check-function)
  (:import-from #:cl-spec/src/generator #:*generator-backend*)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/schema-test)

#+sbcl
(deftest nonfinite-floats-have-an-incomplete-digest
  (let ((spec (make-instance 'cl-spec/src/ir:member-spec
                             :values (list sb-ext:double-float-positive-infinity))))
    (multiple-value-bind (digest complete) (definition-digest spec)
      (ok (null digest))
      (ok (null complete)))))

(deftest result-capabilities-use-the-pre-run-shrink-setting
  (let ((*registry* (make-hash-table-registry)))
    (defproperty changing-law ((x (range integer 1 10))) (:trials (:normal 1))
      (reinitialize-instance (cl-spec/src/registry:find-property 'changing-law)
                             :metadata '(:shrink nil))
      (< x 0))
    (let ((data (result-data (run-property 'changing-law :seed 42))))
      (ok (eq :available (getf (getf data :capabilities) :shrinking)))
      (ok (eq :none (getf (getf (property-data 'changing-law) :capabilities) :shrinking))))))

(deftest backend-capability-reports-must-match-the-schema
  (dolist (capabilities '((:generation :invented :shrinking :available)
                          (:generation :available)
                          (:generation :available :shrinking :none :shrinking :available)))
    (ok (handler-case
            (progn
              (cl-spec/src/generator::validate-backend-outcome
               (list :status :passed :trials 0 :capabilities capabilities) nil 0)
              nil)
          (cl-spec/src/conditions:invalid-backend-result () t)))))

(deftest result-data-copies-protect-retained-evidence
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator draw () (list 1 2))
    (defspec input (list-of integer) (:generator draw))
    (defproperty failure ((x input)) (:shrink nil) (null x))
    (let* ((result (run-property 'failure :seed 42))
           (data (result-data result)))
      (setf (car (getf (getf data :counterexample) 'x)) 99)
      (ok (equal '(1 2) (getf (getf (result-data result) :counterexample) 'x))))))

(defvar *schema-compilations* 0
  "Number of generator compilations during the measured operation.")

(defclass broken-description () ()
  (:documentation "A fixture representing a programming error in an extension."))

(defclass counted-backend (cl-spec/src/backends/check-it:check-it-backend) ()
  (:documentation "Count top-level generator compilations in schema regressions."))

(deftest introspection-and-execution-compile-only-the-root-once
  (let ((*registry* (make-hash-table-registry))
        (*generator-backend* (make-instance 'counted-backend)))
    (defspec input (tuple integer integer integer integer integer integer integer integer
                         integer integer integer integer integer integer integer integer integer))
    (defproperty law ((x integer)) (:trials (:normal 1)) (integerp x))
    (let ((*schema-compilations* 0))
      (spec-data 'input)
      (ok (= 1 *schema-compilations*)))
    (let ((*schema-compilations* 0))
      (let ((data (result-data (run-property 'law :seed 42))))
        (ok (= 1 *schema-compilations*))
        (ok (eq :available (getf (getf data :capabilities) :generation)))))))

(defmethod cl-spec/src/generator:compile-generator :around
    ((backend counted-backend) spec &key context options)
  (declare (ignore context options))
  (incf *schema-compilations*)
  (call-next-method))

(deftest metadata-rejects-unsupported-entity-types-explicitly
  (ok (handler-case
          (progn (cl-spec/src/schema:definition-metadata
                  (make-instance 'cl-spec/src/generator-definition:custom-generator
                                 :name 'unsupported :function (constantly nil))) nil)
        (type-error () t))))

(deftest digest-errors-are-not-confused-with-opaque-definitions
  (ok (handler-case (progn (definition-digest 'identity) nil) (type-error () t)))
  (ok (handler-case (progn (definition-digest (make-instance 'broken-description)) nil)
        (simple-error () t)))
  (let ((*registry* (make-hash-table-registry)))
    (ok (null (definition-digest 'absent :entity-kind :spec)))))

(defmethod cl-spec/src/schema:definition-description ((definition broken-description))
  (declare (ignore definition))
  (error "broken declaration method"))

(deftest tuples-of-custom-generators-have-no-shrink-strategy
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator draw () 1)
    (defspec input integer (:generator draw))
    (defproperty all-custom ((x input) (y input)) (= x y))
    (defproperty mixed ((x input) (y integer)) (= x y))
    (defspec-function identity (:args (x input)) (:returns integer))
    (ok (eq :none (getf (getf (property-data 'all-custom) :capabilities) :shrinking)))
    (ok (eq :none (getf (getf (function-spec-data 'identity) :capabilities) :shrinking)))
    (ok (eq :available (getf (getf (property-data 'mixed) :capabilities) :shrinking)))))

(deftest graph-traversal-preserves-version-one-digests
  (let ((*registry* (make-hash-table-registry)))
    (defspec digest-leaf (range integer 0 10))
    (defspec digest-root (tuple digest-leaf (nullable digest-leaf)))
    (ok (equal "fnv1a64-v1:f123648fe7d686f0"
               (definition-digest 'digest-root :entity-kind :spec)))
    (ok (equal "fnv1a64-v1:c30ab4af3e1875c2"
               (definition-digest 'digest-leaf :entity-kind :spec)))))

(deftest unconstrained-collections-keep-their-version-one-digest
  (let ((*registry* (make-hash-table-registry)))
    (defspec digest-collection (list-of integer))
    (ok (equal "fnv1a64-v1:34cd9f98f3185457"
               (definition-digest 'digest-collection :entity-kind :spec)))))

(deftest digests-include-clos-description-fields
  (flet ((spec (text)
           (make-instance 'cl-spec/src/ir:type-spec :type-specifier 'integer :description text))
         (contract (text)
           (make-instance 'cl-spec/src/function-spec:function-spec :name 'identity
                          :documentation text)))
    (ok (nth-value 1 (definition-digest (spec "first"))))
    (ok (not (equal (definition-digest (spec "first")) (definition-digest (spec "second")))))
    (ok (not (equal (definition-digest (contract "first"))
                    (definition-digest (contract "second")))))))

(defclass extended-type-spec (cl-spec/src/ir:type-spec)
  ((extra :initarg :extra :reader extended-type-spec-extra))
  (:documentation "Test an extension whose semantic fields are not built-in."))

(deftest unknown-subclasses-require-an-explicit-description
  (dolist (extra '(1 2))
    (multiple-value-bind (digest complete)
        (definition-digest (make-instance 'extended-type-spec
                                          :type-specifier 'integer :extra extra))
      (ok (null digest))
      (ok (null complete)))))

(defclass described-extension (cl-spec/src/ir:spec)
  ((extra :initarg :extra :reader described-extension-extra))
  (:documentation "An extension that declares its fields and its completeness."))

(defmethod cl-spec/src/ir:spec-kind ((spec described-extension))
  :described-extension)

(defmethod cl-spec/src/schema:definition-constraints ((definition described-extension))
  (list :extra (described-extension-extra definition)))

(defmethod cl-spec/src/schema:definition-description-complete-p
    ((definition described-extension))
  t)

(deftest extension-methods-produce-complete-digests
  (testing "a subclass that declares both halves gets a real digest"
    (let ((first (make-instance 'described-extension :extra 1))
          (second (make-instance 'described-extension :extra 2)))
      (ok (stringp (definition-digest first)))
      (ok (nth-value 1 (definition-digest first)))
      (ok (not (equal (definition-digest first) (definition-digest second)))))))

(deftest definition-constraints-feed-the-digest-fields
  (testing "node-specific attributes project through DEFINITION-CONSTRAINTS"
    (let ((range (normalize-spec-form '(range integer 0 10)))
          (record (normalize-spec-form '(plist (:required (:id integer)) (:closed t)))))
      (ok (equal '(:base integer :minimum 0 :maximum 10)
                 (definition-constraints range)))
      (ok (equal (definition-constraints record)
                 (getf (definition-description record) :fields))))))

(deftest canonical-digest-does-not-invoke-user-printers
  (let ((expected (cl-spec/src/schema::canonical-digest '(1 2 3)))
        (calls 0)
        (actual nil))
    (let ((*print-pretty* t)
          (*print-pprint-dispatch* (copy-pprint-dispatch nil)))
      (set-pprint-dispatch 'integer
                          (lambda (stream value)
                            (declare (ignore value))
                            (incf calls)
                            (write-string "changed" stream)))
      (setf actual (cl-spec/src/schema::canonical-digest '(1 2 3))))
    (ok (equal expected actual))
    (ok (zerop calls))))

(deftest definition-namespaces-and-envelope-keys-are-unambiguous
  (let ((*registry* (make-hash-table-registry)))
    (defspec identity integer)
    (defproperty identity ((x integer)) (integerp x))
    (defspec-function identity (:args (x integer)) (:returns integer))
    (let ((digests nil))
      (loop for kind in '(:spec :property :function-spec)
            for data in (list (spec-data 'identity) (property-data 'identity)
                              (function-spec-data 'identity))
            do (ok (eq kind (getf data :entity-kind)))
               (ok (= 1 (loop for key in data by #'cddr count (eq key :entity-kind))))
               (ok (equal (getf data :definition-digest)
                          (definition-digest 'identity :entity-kind kind)))
               (push (getf data :definition-digest) digests))
      (ok (= 3 (length (remove-duplicates digests :test #'equal)))))))

(deftest canonical-digests-refuse-opaque-or-oversized-values
  (ok (null (cl-spec/src/schema::canonical-digest (make-hash-table))))
  (ok (null (cl-spec/src/schema::canonical-digest (make-symbol "UNKNOWN"))))
  (ok (null (cl-spec/src/schema::canonical-digest (make-list 60000))))
  (ok (null (cl-spec/src/schema::canonical-digest
             (loop repeat 150 for value = '(0) then (list value) finally (return value))))))

(deftest canonical-digests-handle-graphs-and-printer-settings
  (flet ((graph ()
           (let* ((tail (list 1/3 2.5d0 #\Space #(1 2)))
                  (head (cons tail tail)))
             (setf (cdddr tail) head)
             head)))
    (let ((expected (cl-spec/src/schema::canonical-digest (graph)))
          (*print-readably* nil) (*print-pretty* t) (*print-base* 16)
          (*print-case* :downcase) (*print-circle* nil))
      (ok (stringp expected))
      (ok (equal expected (cl-spec/src/schema::canonical-digest (graph))))
      (ok (not (equal (cl-spec/src/schema::canonical-digest #(1 2))
                      (cl-spec/src/schema::canonical-digest #(1 3))))))))

(deftest referenced-custom-generators-do-not-advertise-shrinking
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator draw () 1)
    (defspec leaf integer (:generator draw))
    (defspec input leaf)
    (ok (eq :none (getf (getf (spec-data 'input) :capabilities) :shrinking)))))

(deftest definitions-carry-a-common-schema-envelope
  (let ((*registry* (make-hash-table-registry)))
    (defspec input integer)
    (defproperty law ((x input)) (integerp x))
    (defspec-function identity (:args (x input)) (:returns input))
    (dolist (data (list (spec-data 'input) (property-data 'law)
                       (function-spec-data 'identity)))
      (ok (eql 1 (getf data :schema-version)))
      (ok (eq :definition (getf data :record-kind)))
      (ok (stringp (getf data :definition-digest)))
      (ok (getf data :definition-digest-complete))
      (ok (getf data :capabilities)))))

(deftest digests-follow-registered-generators
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator draw () 1)
    (defspec input integer (:generator draw))
    (let ((first (getf (spec-data 'input) :definition-digest)))
      (defgenerator draw () 2)
      (ok (not (equal first (getf (spec-data 'input) :definition-digest)))))))

(deftest digest-is-independent-of-printer-and-backend
  (let ((*registry* (make-hash-table-registry)))
    (defspec input (range integer 0 100))
    (let ((original (getf (spec-data 'input) :definition-digest))
          (*print-case* :downcase) (*print-base* 16) (*print-length* 1)
          (*generator-backend* nil))
      (ok (equal original (getf (spec-data 'input) :definition-digest)))
      (ok (eq :unavailable (getf (getf (spec-data 'input) :capabilities) :generation))))))

(deftest unknown-definition-parts-never-have-complete-digests
  (let ((*registry* (make-hash-table-registry)))
    (defspec input missing)
    (let ((data (spec-data 'input)))
      (ok (null (getf data :definition-digest)))
      (ok (null (getf data :definition-digest-complete))))
    (defspec missing integer)
    (ok (getf (spec-data 'input) :definition-digest-complete))
    (let ((property (make-instance 'cl-spec/src/property:property
                                  :name 'opaque-property :function (lambda () t))))
      (ok (null (nth-value 1 (definition-digest property)))))))

(deftest capabilities-do-not-draw-or-call-targets
  (let ((*registry* (make-hash-table-registry))
        (draws 0))
    (defgenerator arguments () (incf draws) '(1))
    (defspec-function identity (:args (x integer)) (:args-generator arguments) (:returns integer))
    (let ((capabilities (getf (function-spec-data 'identity) :capabilities)))
      (ok (eq :available (getf capabilities :generation)))
      (ok (eq :none (getf capabilities :shrinking)))
      (ok (eq :unavailable (getf capabilities :instrumentation)))
      (ok (zerop draws)))))

(deftest results-keep-the-definition-they-actually-checked
  (let ((*registry* (make-hash-table-registry)))
    (defspec input integer)
    (defproperty law ((x input)) (:trials (:normal 1)) (integerp x))
    (let ((before (property-data 'law))
           (result (run-property 'law :seed 42)))
      (defspec input string)
      (let ((data (result-data result)))
        (ok (eq :result (getf data :record-kind)))
        (ok (equal (getf before :definition-digest) (getf data :definition-digest)))
        (ok (not (equal (getf (property-data 'law) :definition-digest)
                        (getf data :definition-digest))))
        (ok (eql 1 (getf data :trials)))
        (ok (eq :property (getf data :entity-kind)))))))

(deftest function-results-use-contract-metadata
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator arguments () '(1))
    (defspec-function identity (:args (x integer)) (:args-generator arguments) (:returns integer))
    (let ((before (function-spec-data 'identity))
          (result (check-function 'identity :trials 1 :seed 42)))
      (defgenerator arguments () '(2))
      (let ((data (result-data result)))
        (ok (eq :function-spec (getf data :entity-kind)))
        (ok (equal (getf before :definition-digest) (getf data :definition-digest)))
        (ok (not (equal (getf (function-spec-data 'identity) :definition-digest)
                        (getf data :definition-digest))))))))

(deftest digests-follow-transitive-references
  (let ((*registry* (make-hash-table-registry)))
    (defspec leaf integer)
    (defspec input leaf)
    (defproperty law ((x input)) (integerp x))
    (let ((first (getf (property-data 'law) :definition-digest)))
      (defspec leaf string)
      (ok (not (equal first (getf (property-data 'law) :definition-digest)))))))
