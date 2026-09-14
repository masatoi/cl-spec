;;;; tests/tagged-union-test.lisp

(defpackage #:cl-spec/tests/tagged-union-test
  (:use #:cl)
  (:import-from #:cl-spec/src/tagged-union
                #:tagged-union-spec #:tagged-union-tag-reader #:tagged-union-branches
                #:make-branch-definition
                #:tagged-union-branch)
  (:import-from #:cl-spec/src/function-spec #:failure-signature)
  (:import-from #:cl-spec/src/explain #:expected-descriptor)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:validp #:explain-data #:spec-data
                #:definition-digest #:spec-kind))

(in-package #:cl-spec/tests/tagged-union-test)

(defun outcome-kind (value)
  "A function tag reader for the canonical plist discriminator."
  (getf value :kind))

(defun accepts-p (form value)
  "Check a DSL form, treating an unsupported declaration as a failed expectation."
  (handler-case (validp (normalize-spec-form form) value)
    (invalid-spec-form () nil)))

(defun refuses-form-p (form)
  "Recognize declaration refusal without catching unrelated errors."
  (handler-case (progn (normalize-spec-form form) nil)
    (invalid-spec-form () t)))

(defun outcome-union-form (&optional (tag-reader :kind))
  "The canonical returned-or-signaled union used across these tests."
  `(tagged-by ,tag-reader
     (:returned (plist (:required (:kind (member :returned)) (:values (list-of t)))
                       (:closed t)))
     (:signaled (plist (:required (:kind (member :signaled))
                                  (:condition-type (member simple-error))
                                  (:condition-report (nullable string)))
                       (:closed t)))))

(deftest tagged-by-dispatches-on-the-tag
  (let ((spec (normalize-spec-form (outcome-union-form))))
    (ok (validp spec '(:kind :returned :values (1 2))))
    (ok (validp spec '(:kind :signaled :condition-type simple-error :condition-report "x")))
    (ok (not (validp spec '(:kind :returned :values 1))))
    (ok (not (validp spec '(:kind :signaled :condition-type other-error :condition-report "x"))))
    (ok (not (validp spec '(:kind :other :values (1 2))))))
  (testing "a function tag reader is accepted and solved at validation time"
    (let ((spec (normalize-spec-form (outcome-union-form 'outcome-kind))))
      (ok (validp spec '(:kind :returned :values (1 2))))
      (ok (not (validp spec '(:kind :other :values (1 2))))))))

(deftest tagged-by-narrows-errors-to-one-branch
  (let* ((returned '(plist (:required (:kind (member :returned)) (:value integer))
                           (:closed t)))
         (signaled '(plist (:required (:kind (member :signaled)) (:value string))
                           (:closed t)))
         (union (normalize-spec-form `(tagged-by :kind
                                        (:returned ,returned)
                                        (:signaled ,signaled))))
         (disjunction (normalize-spec-form `(or ,returned ,signaled)))
         (value '(:kind :returned :value "bad")))
    (let ((union-errors (getf (explain-data union value) :errors)))
      (ok (plusp (length union-errors)))
      (ok (every (lambda (datum) (eq :returned (getf datum :branch))) union-errors))
      (ok (not (some (lambda (datum) (eq :signaled (getf datum :branch))) union-errors))))
    (testing "OR reports every alternative instead of the one the tag selected"
      (let ((or-errors (getf (explain-data disjunction value) :errors)))
        (ok (eq :no-branch-matched (getf (first or-errors) :kind)))))))

(deftest tagged-by-no-branch-lists-known-tags
  (let* ((spec (normalize-spec-form (outcome-union-form)))
         (datum (first (getf (explain-data spec '(:kind :other :values (1 2))) :errors))))
    (ok (eq :no-branch (getf datum :kind)))
    (ok (eq :other (getf datum :observed-tag)))
    (ok (equal '(:returned :signaled) (getf datum :known-tags)))))

(deftest tagged-by-returns-branch-names
  (let* ((spec (normalize-spec-form (outcome-union-form)))
         (descriptor (expected-descriptor spec))
         (data (spec-data spec)))
    (ok (eq :tagged-union (getf descriptor :kind)))
    (ok (eq :kind (getf descriptor :tag-reader)))
    (ok (equal '(:returned :signaled)
               (mapcar (lambda (branch) (getf branch :name)) (getf descriptor :branches))))
    (ok (eq :tagged-union (getf data :kind)))
    (ok (eq :kind (getf data :tag-reader)))
    (ok (equal '((:name :returned :child-index 0) (:name :signaled :child-index 1))
               (getf data :branches)))
    (ok (equal (outcome-union-form) (getf data :source-form)))))

(deftest tagged-by-reader-failure-is-structured
  (let ((spec (normalize-spec-form (outcome-union-form))))
    (let ((datum (first (getf (explain-data spec 42) :errors))))
      (ok (eq :reader-errored (getf datum :kind)))
      (ok (getf datum :condition-type))))
  (testing "an undefined tag reader is an authoring error and still propagates"
    (let ((spec (normalize-spec-form (outcome-union-form 'tagged-undefined-reader))))
      (ok (handler-case (progn (validp spec '(:kind :returned :values ())) nil)
            (undefined-function () t))))))

(deftest tagged-by-refuses-malformed-declarations
  (dolist (form '((tagged-by)
                  (tagged-by :kind)
                  (tagged-by 42 (:a integer))
                  (tagged-by :kind (:a))
                  (tagged-by :kind (:a integer extra))
                  (tagged-by :kind (nil integer))
                  (tagged-by :kind (:a integer) (:a string))
                  (tagged-by :kind (:a integer . string))
                  (tagged-by . :kind)))
    (ok (refuses-form-p form) (format nil "~S must be refused" form))))

(deftest tagged-by-introspection-and-digest
  (let* ((form (outcome-union-form))
         (data (spec-data (normalize-spec-form form))))
    (ok (getf data :definition-digest-complete))
    (let ((digest (getf data :definition-digest)))
      (dolist (other (list (outcome-union-form 'outcome-kind)
                           `(tagged-by :kind
                              (:returned (plist (:required (:kind (member :returned))
                                                          (:values (list-of t)))
                                                (:closed t)))
                              (:signaled (plist (:required (:kind (member :signaled))
                                                          (:condition-type t))
                                                (:closed t))))
                           `(tagged-by :kind
                              (:signaled (plist (:required (:kind (member :signaled))
                                                          (:condition-type (member simple-error))
                                                          (:condition-report (nullable string)))
                                                (:closed t)))
                              (:returned (plist (:required (:kind (member :returned))
                                                          (:values (list-of t)))
                                                (:closed t))))))
        (ok (not (equal digest (definition-digest (normalize-spec-form other))))
            (format nil "digest must cover ~S" other))))))

(deftest tagged-by-branch-lookup
  (let* ((spec (normalize-spec-form (outcome-union-form)))
         (branch (tagged-union-branch spec :signaled)))
    (ok (eq :plist (spec-kind branch)))
    (ok (equal '(:kind :condition-type :condition-report)
               (mapcar (lambda (field) (getf field :key)) (getf (spec-data branch) :fields))))
    (ok (handler-case (progn (tagged-union-branch spec :missing) nil)
          (invalid-spec-form () t)))
    (testing "a non-union designator is refused"
      (ok (handler-case (progn (tagged-union-branch (normalize-spec-form 'integer) :a) nil)
            (invalid-spec-form () t))))))

(deftest tagged-by-failure-identity
  (let* ((spec (normalize-spec-form
                `(tagged-by :kind
                   (:left (plist (:required (:kind (member :left)) (:value integer))
                                 (:closed t)))
                   (:right (plist (:required (:kind (member :right)) (:value string))
                                  (:closed t))))))
         (signature (lambda (value)
                      (failure-signature :return-spec (explain-data spec value) nil))))
    (ok (not (equal (funcall signature '(:kind :left :value "bad"))
                    (funcall signature '(:kind :right :value 1)))))
    (ok (equal (funcall signature '(:kind :left :value "bad"))
               (funcall signature '(:kind :left :value "worse"))))
    (ok (equal (funcall signature '(:kind :other :value 1))
               (funcall signature '(:kind :another :value 2))))
    (ok (not (equal (funcall signature '(:kind :other :value 1))
                    (funcall signature '(:kind :left :value "bad")))))))

(deftest programmatic-tagged-union-invariants
  (let* ((child (normalize-spec-form 'integer))
         (branch (make-branch-definition :name :a :spec child))
         (spec (make-instance 'tagged-union-spec :tag-reader :kind
                                                :branches (list branch))))
    (ok (eq :tagged-union (spec-kind spec)))
    (ok (eq :kind (tagged-union-tag-reader spec)))
    (dolist (initargs (list (list :tag-reader :kind :branches nil)
                            (list :tag-reader :kind :branches (list branch branch))
                            (list :tag-reader :kind :branches (list :not-a-branch))
                            (list :tag-reader 42 :branches (list branch))
                            (list :tag-reader nil :branches (list branch))
                            (list :tag-reader :kind
                                  :branches (list (make-branch-definition
                                                   :name nil :spec child)))))
      (ok (handler-case (progn (apply #'make-instance 'tagged-union-spec initargs) nil)
            (invalid-spec-form () t))
          (format nil "~S must be refused" initargs)))
    (ok (equal (list branch) (tagged-union-branches spec)))
    (ok (handler-case (progn (reinitialize-instance spec :tag-reader 42) nil)
          (invalid-spec-form () t)))
    (ok (eq :kind (tagged-union-tag-reader spec)))
    (ok (handler-case (progn (reinitialize-instance spec :branches (list branch branch)) nil)
          (invalid-spec-form () t)))
    (ok (equal (list branch) (tagged-union-branches spec)))))
