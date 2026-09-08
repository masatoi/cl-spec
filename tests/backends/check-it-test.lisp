;;;; tests/backends/check-it-test.lisp

(defpackage #:cl-spec/tests/backends/check-it-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend
                #:install-check-it-backend
                #:default-trials)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/backends/check-it-generators
                #:spec-generator
                #:compile-spec-generator)
  (:import-from #:cl-spec/src/validator
                #:validp)
  (:import-from #:check-it
                #:generate)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec))

(in-package #:cl-spec/tests/backends/check-it-test)

(deftest loading-installs-the-backend
  (testing "loading this system leaves a CHECK-IT-BACKEND in *GENERATOR-BACKEND*"
    (ok (typep *generator-backend* 'check-it-backend))
    (ok (typep (current-generator-backend) 'check-it-backend))))

(deftest install-is-idempotent-and-returns-the-backend
  (testing "INSTALL-CHECK-IT-BACKEND can be called again safely"
    (let ((backend (install-check-it-backend)))
      (ok (typep backend 'check-it-backend))
      (ok (eq backend *generator-backend*)))))

(deftest default-trials-comes-from-check-it
  (testing "the default trial count is taken from CHECK-IT:*NUM-TRIALS*"
    (ok (integerp (default-trials)))
    (ok (plusp (default-trials)))))

(defun draws-for (form &key (count 30) (registry (make-hash-table-registry)))
  "Generate COUNT values from FORM's generator, honouring the size its bounds need."
  (multiple-value-bind (generator size)
      (compile-spec-generator (normalize-spec-form form) (list :registry registry))
    (let ((check-it:*size* (max check-it:*size* size)))
      (loop repeat count collect (generate generator)))))

(deftest generated-values-satisfy-their-leaf-spec
  (dolist (form '(integer real character string (member :a :b :c)
                  (range 1 100) (range integer 1 100) (range integer 1 *)))
    (testing (format nil "~S generates values it admits" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value)) (draws-for form)))))))

(deftest null-and-boolean-types
  (testing "NULL generates NIL"
    (ok (every #'null (draws-for 'null :count 5))))
  (testing "BOOLEAN generates only T and NIL"
    (ok (every (lambda (value) (member value '(t nil))) (draws-for 'boolean)))))

(deftest generated-values-satisfy-their-composite-spec
  (dolist (form '((or integer string) (nullable integer)
                  (tuple integer string) (list-of integer) (vector-of integer)))
    (testing (format nil "~S generates values it admits" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value)) (draws-for form)))))))

(deftest ranges-wider-than-check-its-default-size-are-honoured
  ;; check-it clamps every numeric limit to CHECK-IT:*SIZE*, which is 10 by
  ;; default.  Without the required-size accounting these two draw 10 and -10,
  ;; both outside the range that was asked for.
  (testing "a positive range that does not straddle zero stays inside itself"
    (ok (every (lambda (value) (<= 20 value 100))
               (draws-for '(range integer 20 100)))))
  (testing "a negative range stays inside itself"
    (ok (every (lambda (value) (<= -100 value -50))
               (draws-for '(range integer -100 -50)))))
  (testing "the widened size does not leak out of the draw"
    (draws-for '(range integer 20 100) :count 1)
    (ok (= 10 check-it:*size*))))

(deftest a-straddling-real-range-draws-from-both-halves
  ;; REAL-RANGE-GENERATOR shifts a finite/finite real range to start at zero
  ;; before handing it to check-it, to work around a bug in check-it's
  ;; REAL-GENERATOR-FUNCTION (see the docstring).  BOUNDED-GENERATOR has to
  ;; size *REQUIRED-SIZE* for that shifted, wider interval or the upper half
  ;; of a range straddling zero never gets drawn.
  (let ((values (draws-for '(range real -10 10) :count 200)))
    (testing "every value stays inside the declared range"
      (ok (every (lambda (value) (<= -10 value 10)) values)))
    (testing "values are drawn from above zero"
      (ok (some (lambda (value) (> value 0)) values)))
    (testing "values are drawn from below zero"
      (ok (some (lambda (value) (< value 0)) values)))))

(deftest a-degenerate-real-range-yields-its-single-value
  (testing "every draw from (range real 5 5) is 5, and it does not signal"
    (ok (every (lambda (value) (= value 5)) (draws-for '(range real 5 5))))))

(deftest references-are-followed
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'small
                            (normalize-spec-form '(range integer 1 10) :name 'small))
    (testing "a reference generates through its target"
      (ok (every (lambda (value) (and (integerp value) (<= 1 value 10)))
                 (draws-for 'small :registry registry))))))

(deftest specs-without-a-generation-strategy-say-so
  (dolist (form '((not integer) (satisfies plusp) (instance-of standard-object)
                  (member) (or) (type hash-table)))
    (testing (format nil "~S signals GENERATOR-UNAVAILABLE" form)
      (ok (handler-case (progn (draws-for form :count 1) nil)
            (generator-unavailable () t))))))

(deftest recursive-specs-are-refused-rather-than-hanging
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'int-tree
                            (normalize-spec-form '(or integer (tuple int-tree int-tree))
                                                 :name 'int-tree))
    (testing "a self referential spec signals instead of recursing forever"
      (ok (handler-case (progn (draws-for 'int-tree :count 1 :registry registry) nil)
            (generator-unavailable () t))))))

(deftest and-folds-its-constraints-into-one-generator
  (testing "a type and a range collapse into a bounded generator"
    (let ((values (draws-for '(and integer (range 1 100)))))
      (ok (every (lambda (value) (and (integerp value) (<= 1 value 100))) values))))
  (testing "the section 67 example generates without a rejection loop"
    (ok (every (lambda (value) (and (integerp value) (>= value 1)))
               (draws-for '(and integer (range 1 *))))))
  (testing "overlapping ranges intersect"
    (ok (every (lambda (value) (<= 10 value 20))
               (draws-for '(and integer (range 1 20) (range 10 100))))))
  (testing "a leftover predicate becomes a guard, not a lost constraint"
    (ok (every #'oddp (draws-for '(and integer (range 1 100) (satisfies oddp))))))
  (testing "an AND with nothing to generate from is refused"
    (ok (handler-case (progn (draws-for '(and (satisfies oddp) (satisfies plusp)) :count 1) nil)
          (generator-unavailable () t))))
  (testing "an empty interval is refused rather than looping"
    (ok (handler-case (progn (draws-for '(and integer (range 10 20) (range 30 40)) :count 1) nil)
          (generator-unavailable () t)))))

(deftest and-folds-through-references-and-nested-ands
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'my-range
                            (normalize-spec-form '(and integer (range 1 10))
                                                 :name 'my-range))
    (testing "a reference conjunct folds its target's own type and range"
      (let ((values (draws-for '(and my-range (satisfies oddp)) :registry registry)))
        (ok (every (lambda (value) (and (oddp value) (<= 1 value 10))) values)))))
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'my-range
                            (normalize-spec-form '(and integer (range 1000000 1000010))
                                                 :name 'my-range))
    (testing "a reference conjunct is folded rather than left for the guard to reject forever"
      (ok (every (lambda (value) (<= 1000000 value 1000010))
                 (draws-for '(and integer my-range) :registry registry)))))
  (testing "a nested AND folds the same as its flattened equivalent"
    (ok (every (lambda (value) (<= 10 value 20))
               (draws-for '(and integer (and (range 1 20) (range 10 100))))))))
