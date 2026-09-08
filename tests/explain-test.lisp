;;;; tests/explain-test.lisp

(defpackage #:cl-spec/tests/explain-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain)
  (:import-from #:cl-spec/src/conditions
                #:unknown-spec)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec))

(in-package #:cl-spec/tests/explain-test)

(defun errors-for (form value)
  "Compile FORM and return the structured errors it reports for VALUE."
  (funcall (compile-explainer (normalize-spec-form form)) value nil))

(deftest valid-values-produce-no-errors
  (testing "a satisfied leaf reports nothing"
    (ok (null (errors-for 'integer 10)))
    (ok (null (errors-for '(satisfies plusp) 10)))
    (ok (null (errors-for '(member :a :b) :a)))
    (ok (null (errors-for '(range 1 100) 50)))
    (ok (null (errors-for '(range 1 *) 10000)))))

(deftest type-failures
  (testing "a failed type check names the expected type"
    (let ((datum (first (errors-for 'integer "foo"))))
      (ok (eq :type-failed (getf datum :kind)))
      (ok (equal '(:type integer) (getf datum :expected)))
      (ok (equal "foo" (getf datum :actual)))
      (ok (null (getf datum :path))))))

(deftest predicate-failures
  (testing "a predicate returning NIL is reported as :PREDICATE-FAILED"
    (let ((datum (first (errors-for '(satisfies plusp) -1))))
      (ok (eq :predicate-failed (getf datum :kind)))
      (ok (eq 'plusp (getf datum :predicate)))
      (ok (equal '(:satisfies plusp) (getf datum :expected)))))
  (testing "a predicate signalling on a wrong-typed value is :PREDICATE-ERRORED, not propagated"
    (let ((datum (first (errors-for '(satisfies plusp) "foo"))))
      (ok (eq :predicate-errored (getf datum :kind)))
      (ok (getf datum :condition-type))
      (ok (stringp (getf datum :condition-report)))))
  (testing "an undefined predicate propagates instead of being reported as a bad value"
    ;; A typo'd predicate name is a bug in the spec, not a fact about the
    ;; value: rendering it as :PREDICATE-ERRORED would send the reader after
    ;; the wrong thing.
    (ok (handler-case (progn (errors-for '(satisfies plusspp) 1) nil)
          (undefined-function () t))))
  (testing "a predicate called with the wrong number of arguments also propagates"
    (ok (handler-case (progn (errors-for '(satisfies cons) 1) nil)
          (program-error () t)))))

(deftest member-and-range-failures
  (testing "MEMBER reports the admissible values"
    (let ((datum (first (errors-for '(member :a :b) :c))))
      (ok (eq :not-member (getf datum :kind)))
      (ok (equal '(:member :a :b) (getf datum :expected)))))
  (testing "RANGE says which bound was violated"
    (ok (eq :minimum (getf (first (errors-for '(range 1 100) 0)) :violated-bound)))
    (ok (eq :maximum (getf (first (errors-for '(range 1 100) 101)) :violated-bound))))
  (testing "RANGE rejects a value of the wrong type before comparing"
    (ok (eq :type-failed (getf (first (errors-for '(range 1 100) "x")) :kind)))))

(deftest instance-of-failures
  (testing "an unrelated value is not an instance"
    (let ((datum (first (errors-for '(instance-of standard-object) 10))))
      (ok (eq :not-an-instance (getf datum :kind))))))

(deftest explain-data-shape
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive
                            (normalize-spec-form '(satisfies plusp) :name 'positive))
    (testing "a failing value produces the section 22 shape"
      (let ((data (explain-data 'positive -100 :registry registry)))
        (ok (null (getf data :valid)))
        (ok (eq 'positive (getf data :spec)))
        (ok (eql -100 (getf data :value)))
        (ok (null (getf data :path)))
        (ok (= 1 (length (getf data :errors))))))
    (testing "a passing value reports :VALID T and no errors"
      (let ((data (explain-data 'positive 1 :registry registry)))
        (ok (eq t (getf data :valid)))
        (ok (null (getf data :errors)))))
    (testing "an unregistered name signals UNKNOWN-SPEC"
      (ok (signals (explain-data 'absent 1 :registry registry) 'unknown-spec)))
    (testing "an anonymous spec object reports its source form as :SPEC, not NIL"
      ;; (RANGE 1 10) has no registered name, so :SPEC used to fall back to
      ;; NIL and EXPLAIN would print literally "does not satisfy NIL."
      (let ((data (explain-data (normalize-spec-form '(range 1 10)) 99)))
        (ok (equal '(range 1 10) (getf data :spec)))))))

(deftest and-short-circuits-and-reports-the-checklist
  (testing "a conjunction that holds reports nothing"
    (ok (null (errors-for '(and integer (satisfies plusp)) 10))))
  (testing "the first failing conjunct stops the walk"
    (let* ((datum (first (errors-for '(and integer (satisfies plusp)) "foo")))
           (conjuncts (getf datum :conjuncts)))
      (ok (eq :conjunct-failed (getf datum :kind)))
      (ok (equal '(:failed :unchecked) (mapcar (lambda (c) (getf c :status)) conjuncts)))
      (ok (equal '(:type integer) (getf (first conjuncts) :expected)))))
  (testing "conjuncts before the failure are marked satisfied"
    (let ((conjuncts (getf (first (errors-for '(and integer (satisfies plusp)) -1)) :conjuncts)))
      (ok (equal '(:satisfied :failed) (mapcar (lambda (c) (getf c :status)) conjuncts)))))
  (testing "the failing child's own errors are carried under :ERRORS"
    (let ((datum (first (errors-for '(and integer (satisfies plusp)) -1))))
      (ok (eq :predicate-failed (getf (first (getf datum :errors)) :kind)))))
  (testing "the empty conjunction admits everything"
    (ok (null (errors-for '(and) :anything)))))

(deftest or-collects-every-branch
  (testing "one matching branch is enough"
    (ok (null (errors-for '(or integer string) "x"))))
  (testing "when all branches fail their errors are kept"
    (let ((datum (first (errors-for '(or integer string) :keyword))))
      (ok (eq :no-branch-matched (getf datum :kind)))
      (ok (= 2 (length (getf datum :branches))))
      (ok (every (lambda (branch) (getf branch :errors)) (getf datum :branches)))))
  (testing "the empty disjunction admits nothing"
    (ok (errors-for '(or) :anything))))

(deftest not-and-nullable
  (testing "NOT fails exactly when its child holds"
    (ok (null (errors-for '(not integer) "x")))
    (ok (eq :negation-failed (getf (first (errors-for '(not integer) 1)) :kind))))
  (testing "NULLABLE admits NIL and delegates otherwise"
    (ok (null (errors-for '(nullable integer) nil)))
    (ok (null (errors-for '(nullable integer) 1)))
    (ok (errors-for '(nullable integer) "x"))))

(deftest collections-report-the-failing-position
  (testing "LIST-OF rejects a non list"
    (ok (eq :not-a-list (getf (first (errors-for '(list-of integer) 5)) :kind))))
  (testing "LIST-OF reports the index of every bad element"
    (let ((errors (errors-for '(list-of integer) '(1 "x" 3 "y"))))
      (ok (= 2 (length errors)))
      (ok (equal '((1) (3)) (mapcar (lambda (e) (getf e :path)) errors)))))
  (testing "VECTOR-OF rejects a non vector and reports indices"
    (ok (eq :not-a-vector (getf (first (errors-for '(vector-of integer) '(1 2))) :kind)))
    (ok (equal '((1)) (mapcar (lambda (e) (getf e :path))
                              (errors-for '(vector-of integer) #(1 "x"))))))
  (testing "TUPLE checks the length before the positions"
    (ok (eq :wrong-length (getf (first (errors-for '(tuple integer string) '(1))) :kind)))
    (ok (null (errors-for '(tuple integer string) '(1 "x"))))
    (ok (equal '((0)) (mapcar (lambda (e) (getf e :path))
                              (errors-for '(tuple integer string) '("a" "x"))))))
  (testing "nested collections accumulate the path root first"
    (ok (equal '((1 0))
               (mapcar (lambda (e) (getf e :path))
                       (errors-for '(list-of (list-of integer)) '((1) ("x"))))))))

(deftest references-resolve-at-call-time
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'target (normalize-spec-form 'integer :name 'target))
    (let ((explainer (compile-explainer (normalize-spec-form 'target)
                                        :context (list :registry registry))))
      (testing "the reference resolves through the registry"
        (ok (null (funcall explainer 1 nil)))
        (ok (funcall explainer "x" nil)))
      (testing "redefining the target changes what an existing explainer accepts"
        (registry-register-spec registry 'target (normalize-spec-form 'string :name 'target))
        (ok (funcall explainer 1 nil))
        (ok (null (funcall explainer "x" nil))))
      (testing "an unregistered target signals UNKNOWN-SPEC when checked"
        (let ((other (compile-explainer (normalize-spec-form 'absent)
                                        :context (list :registry registry))))
          (ok (signals (funcall other 1 nil) 'unknown-spec)))))))

(deftest recursive-specs-can-be-checked
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'int-tree
                            (normalize-spec-form '(or integer (tuple int-tree int-tree))
                                                 :name 'int-tree))
    (testing "a self referential spec terminates on well founded values"
      (let ((explainer (compile-explainer (normalize-spec-form 'int-tree)
                                          :context (list :registry registry))))
        (ok (null (funcall explainer 1 nil)))
        (ok (null (funcall explainer '(1 (2 3)) nil)))
        (ok (funcall explainer '(1 "x") nil))))))

(deftest explain-renders-the-checklist
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-money
                            (normalize-spec-form '(and integer (satisfies plusp))
                                                 :name 'positive-money))
    (testing "a failing conjunction prints exactly one line per conjunct, no duplicate"
      ;; Pinned to the exact text, not just SEARCH: PRINT-EXPLAIN-ERROR used to
      ;; recurse into the failing conjunct's own :ERRORS after the checklist
      ;; already printed its line, rendering the failing conjunct twice. A
      ;; SEARCH-only assertion cannot see an extra line, so this checks the
      ;; full rendering instead.
      (let ((text (with-output-to-string (stream)
                    (explain 'positive-money -100 :stream stream :registry registry))))
        (ok (string= (format nil "-100 does not satisfy POSITIVE-MONEY~%  ✓ INTEGER~%  ✗ PLUSP~%")
                     text))))
    (testing "an unchecked conjunct is marked as such rather than as passing, no duplicate"
      (let ((text (with-output-to-string (stream)
                    (explain 'positive-money "foo" :stream stream :registry registry))))
        (ok (string= (format nil "~S does not satisfy POSITIVE-MONEY~%  ✗ INTEGER~%  · PLUSP~%"
                            "foo")
                     text))))
    (testing "a passing value says so and returns NIL"
      (let ((text (with-output-to-string (stream)
                    (ok (null (explain 'positive-money 1 :stream stream :registry registry))))))
        (ok (string= (format nil "1 satisfies POSITIVE-MONEY~%") text))))))
