;;;; tests/backends/check-it-test.lisp

(defpackage #:cl-spec/tests/backends/check-it-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable
                #:generator-unavailable-kind
                #:generator-unavailable-argument)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:sample)
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
                #:registry-register-spec)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function)
  (:import-from #:cl-spec/src/function-spec
                #:check-function)
  (:import-from #:cl-spec/src/property-runner
                #:property-result-counterexample))

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

(deftest bounded-collection-elements-stay-in-range
  ;; A bare (list-of integer) never exercises BOUNDED-GENERATOR's clamping
  ;; work, because unbounded integers already draw from the full [-*size*,
  ;; *size*] window. A bounded element does: LIST-OF-SPEC and VECTOR-OF-SPEC
  ;; used to defer the element generator into a closure that only ran at
  ;; generate time, after *REQUIRED-SIZE*'s binding was gone, so the element's
  ;; range never reached CHECK-IT:*SIZE* and got clamped away.
  (testing "every element of a LIST-OF a bounded range stays inside that range"
    (ok (every (lambda (list) (every (lambda (value) (<= 20 value 100)) list))
               (draws-for '(list-of (range integer 20 100))))))
  (testing "every element of a VECTOR-OF a bounded range stays inside that range"
    (ok (every (lambda (vector) (every (lambda (value) (<= 20 value 100)) vector))
               (draws-for '(vector-of (range integer 20 100)))))))

(defun mean-length (form &key (count 60) (seed 1))
  "Return the mean length of COUNT values SAMPLE draws from FORM with SEED."
  (let ((values (sample (normalize-spec-form form) :count count :seed seed)))
    (/ (reduce #'+ values :key #'length) (length values))))

(deftest a-length-constraint-does-not-borrow-its-length-from-a-range-width
  (testing "a wide element range does not stretch a constrained collection"
    (ok (< (mean-length '(list-of (range integer 0 1000) :min-length 1)) 25))
    (ok (< (mean-length '(vector-of (range integer 0 100000) :min-length 1)) 25)))
  (testing "a constrained collection draws its length the way an unconstrained one does"
    (ok (< (abs (- (mean-length '(list-of (range integer 0 1000) :min-length 1))
                   (mean-length '(list-of (range integer 0 10) :min-length 1))))
           5)))
  (testing "a neighbouring argument's range does not change a collection's length"
    (ok (< (mean-length '(tuple (range integer 0 100000) (list-of integer :min-length 1)))
           (+ 2 (mean-length '(tuple (range integer 0 10) (list-of integer :min-length 1))))))
    (ok (< (mean-length '(list-of integer :min-length 1)) 25)))
  (testing "the declared bounds still hold"
    (ok (every (lambda (items) (<= 3 (length items) 5))
               (sample (normalize-spec-form '(list-of (range integer 0 1000)
                                              :min-length 3 :max-length 5))
                       :count 30 :seed 2)))))

(defun distinct-sizes (form size-function &key (count 200) (seed 9))
  "Return the distinct sizes SIZE-FUNCTION reads off COUNT values SAMPLE draws from FORM."
  (remove-duplicates (mapcar size-function
                             (sample (normalize-spec-form form) :count count :seed seed))))

(deftest a-large-minimum-length-still-varies-the-length
  ;; Issue #82: a minimum at or above CHECK-IT:*LIST-SIZE* raised the cap to the
  ;; minimum itself, so every value had exactly the minimum length.
  (testing "a list whose minimum exceeds the list size draws several lengths"
    (let ((lengths (distinct-sizes '(list-of integer :min-length 25 :max-length 40) #'length)))
      (ok (every (lambda (length) (<= 25 length 40)) lengths))
      (ok (< 5 (length lengths)))))
  (testing "an unbounded vector with a large minimum draws above it"
    (let ((lengths (distinct-sizes '(vector-of integer :min-length 30) #'length)))
      (ok (every (lambda (length) (<= 30 length)) lengths))
      (ok (< 5 (length lengths)))))
  (testing "a map whose minimum count exceeds the list size draws several counts"
    (let ((counts (distinct-sizes '(hash-table-of integer integer :min-count 25 :max-count 60)
                                  #'hash-table-count :count 50)))
      (ok (every (lambda (count) (<= 25 count 60)) counts))
      (ok (< 5 (length counts))))))

(deftest a-single-child-member-or-or-does-not-crash-check-it
  ;; CHECK-IT:COMPUTE-WEIGHTS computes (log 1) for a lone sub-generator and
  ;; then divides by the resulting zero, signalling a floating point error
  ;; instead of CL-SPEC's own conditions. A single child needs no weighted
  ;; choice at all.
  (testing "a one-valued MEMBER generates its single value"
    (ok (every (lambda (value) (eq :ok value)) (draws-for '(member :ok)))))
  (testing "a one-child OR generates values admitted by its child"
    (ok (every #'integerp (draws-for '(or integer))))))

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

(deftest one-sided-real-ranges-far-from-zero-generate-inside-themselves
  ;; Issue #60: check-it's one-sided REAL-GENERATOR draws from
  ;; [min(|bound|, *SIZE*), *SIZE*), and *REQUIRED-SIZE* raises *SIZE* to
  ;; |bound|, so a bound of magnitude >= 10 left a zero-width interval and
  ;; (RANDOM 0.0) signalled a TYPE-ERROR.
  (dolist (form '((range real 100 *) (range real 10 *) (range real -50 *)
                  (range real * -100) (range real * 10) (range real * 50)))
    (testing (format nil "every draw from ~S satisfies it" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value))
                   (draws-for form :count 50)))))))

(deftest a-real-range-too-wide-to-measure-is-refused
  (testing "a width that overflows a double-float signals GENERATOR-UNAVAILABLE"
    (ok (handler-case (progn (draws-for '(range real -1d308 1d308) :count 1) nil)
          (generator-unavailable () t)))))

(deftest sample-draws-from-a-one-sided-real-range
  (testing "the public SAMPLE path no longer leaks a TYPE-ERROR"
    (ok (every (lambda (value) (>= value 100))
               (sample (normalize-spec-form '(range real 100 *)) :count 5 :seed 42)))))

(defun outcome-of (thunk)
  "Return THUNK's value, or the type of the error it signals."
  (handler-case (funcall thunk)
    (error (condition) (type-of condition))))

(deftest real-ranges-beyond-single-float-range-do-not-overflow
  ;; Issue #76: check-it's REAL-GENERATOR converts *SIZE* to a single-float, so
  ;; any *SIZE* beyond about 3.4e38 signalled FLOATING-POINT-OVERFLOW.
  (dolist (form '((range real 1d39 *) (range real * -1d39) (range real 0 1d39)
                  (range real -1d300 1d300) (range real 1d307 *)))
    (testing (format nil "every draw from ~S satisfies it" form)
      (let* ((spec (normalize-spec-form form))
             (values (outcome-of (lambda () (sample spec :count 20 :seed 1)))))
        (ok (and (listp values) (every (lambda (value) (validp spec value)) values))))))
  (testing "a bound beyond double-float range is refused as too wide"
    (ok (eq :range-too-wide
            (handler-case (progn (sample (normalize-spec-form `(range real 0 ,(expt 10 400)))
                                         :count 1 :seed 1)
                                 nil)
              (generator-unavailable (condition) (generator-unavailable-kind condition))))))
  (testing "a huge integer bound in a neighbouring position does not break a REAL"
    (let* ((spec (normalize-spec-form `(tuple (range integer 0 ,(expt 10 40)) real)))
           (values (outcome-of (lambda () (sample spec :count 20 :seed 1)))))
      (ok (and (listp values) (every (lambda (value) (validp spec value)) values))))))

(deftest real-ranges-near-the-double-float-limit-cover-their-domain
  ;; The overflow guard limited every step to MOST-POSITIVE-DOUBLE-FLOAT - |ORIGIN|,
  ;; even a step towards zero that cannot overflow, so a range starting near
  ;; -1.8e308 never drew most of itself and a property over it passed falsely.
  (flet ((draws (form)
           (sample (normalize-spec-form form) :count 400 :seed 2026)))
    (testing "(range real -1d308 5d307) draws non-negative values"
      (ok (some (lambda (value) (>= value 0)) (draws '(range real -1d308 5d307)))))
    (testing "(range real -1.7d308 0) draws from its upper half"
      (ok (some (lambda (value) (> value -8.5d307)) (draws '(range real -1.7d308 0)))))
    (testing "(range real * 1.7d308) draws from below its upper half"
      (ok (some (lambda (value) (< value 8.5d307)) (draws '(range real * 1.7d308)))))
    (testing "(range real 1.7d308 *) still stays inside double-float range"
      (ok (every (lambda (value) (and (>= value 1.7d308) (<= value most-positive-double-float)))
                 (draws '(range real 1.7d308 *)))))))

(defvar *one-sided-arguments* '()
  "Distinct arguments ONE-SIDED-TARGET has been called with.")

(defun one-sided-target (n)
  "Record N and return it."
  (pushnew n *one-sided-arguments*)
  n)

(deftest one-sided-integer-ranges-draw-more-than-their-bound
  ;; Issue #77: the bound raised *SIZE* to |N|, so check-it drew from [N, N].
  (dolist (form '((range integer 50 *) (range integer * -50) (range integer 5 *)
                  (range integer 1000000 *)))
    (testing (format nil "~S yields many distinct values inside itself" form)
      (let* ((spec (normalize-spec-form form))
             (values (sample spec :count 50 :seed 1)))
        (ok (every (lambda (value) (validp spec value)) values))
        (ok (< 10 (length (remove-duplicates values)))))))
  (testing "a bound far from zero widens the draw in proportion to it"
    (ok (some (lambda (value) (> value 1000100))
              (sample (normalize-spec-form '(range integer 1000000 *)) :count 50 :seed 1)))
    (ok (some (lambda (value) (< value -1000100))
              (sample (normalize-spec-form '(range integer * -1000000)) :count 50 :seed 1))))
  (testing "a one-sided range does not widen a neighbouring unconstrained integer"
    (ok (every (lambda (pair) (<= (abs (second pair)) 1000))
               (sample (normalize-spec-form '(tuple (range integer 1000000 *) integer))
                       :count 50 :seed 1))))
  (testing "a satisfiable AND over a one-sided integer range is generated"
    (let* ((spec (normalize-spec-form '(and (range integer 50 *) (satisfies oddp))))
           (values (outcome-of (lambda () (sample spec :count 10 :seed 1)))))
      (ok (and (listp values) (every (lambda (value) (validp spec value)) values)))))
  (testing "a function check over a one-sided range reaches more than one argument"
    (let ((cl-spec/src/registry:*registry* (make-hash-table-registry)))
      (setf *one-sided-arguments* '())
      (defspec-function one-sided-target
        (:args (n (range integer 100 *)))
        (:returns integer))
      (check-function 'one-sided-target :trials 50 :seed 20261101)
      (ok (< 10 (length *one-sided-arguments*))))))

(deftest an-infinite-bound-on-an-integer-range-is-an-open-bound
  ;; Issue #86: CEILING of an infinite float signalled a raw SIMPLE-ERROR.
  (let ((plus sb-ext:double-float-positive-infinity)
        (minus sb-ext:double-float-negative-infinity))
    (dolist (form (list `(range integer 0 ,plus)
                        `(range integer ,minus 5)
                        `(and integer (range real ,minus 5))
                        `(range real 0 ,plus)))
      (testing (format nil "every draw from ~S satisfies it" form)
        (let* ((spec (normalize-spec-form form))
               (values (outcome-of (lambda () (sample spec :count 20 :seed 1)))))
          (ok (and (listp values) (every (lambda (value) (validp spec value)) values))))))
    (testing "UNIQUE over an infinite range is refused as it is over an open one"
      (ok (eq :unique-domain
              (handler-case
                  (progn (sample (normalize-spec-form
                                  `(list-of (range integer 0 ,plus) :unique t :min-length 2))
                                 :count 1 :seed 1)
                         nil)
                (generator-unavailable (condition)
                  (generator-unavailable-kind condition))))))))

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

(defun generation-refusal (thunk)
  "Return the GENERATOR-UNAVAILABLE THUNK signals, or NIL when it returns."
  (handler-case (progn (funcall thunk) nil)
    (generator-unavailable (condition) condition)))

(deftest generation-refusals-name-the-spec-the-argument-and-a-remedy
  (let ((cl-spec/src/registry:*registry* (make-hash-table-registry)))
    (eval '(defspec odd-int (satisfies oddp)))
    (eval '(cl-spec/src/dsl:defproperty odd-argument ((count integer) (odd odd-int))
            (oddp odd)))
    (let* ((condition (generation-refusal
                       (lambda ()
                         (cl-spec/src/property-runner:run-property 'odd-argument :seed 1))))
           (message (and condition (princ-to-string condition))))
      (testing "the refusal says which argument needs a generator"
        (ok (eq 'odd (generator-unavailable-argument condition))))
      (testing "the reason is a keyword an agent can dispatch on"
        (ok (eq :no-strategy (generator-unavailable-kind condition))))
      (testing "the message names the spec rather than printing an internal object"
        (ok (search "ODD-INT" message))
        (ok (search "ODD" message))
        (ok (not (search "{" message))))
      (testing "the message points at the remedy"
        (ok (search "DEFGENERATOR" message))
        (ok (search ":GENERATOR" message))))
    (testing "a refusal from SAMPLE has no argument but still a kind"
      (let ((condition (generation-refusal
                        (lambda () (sample (normalize-spec-form '(member)) :count 1)))))
        (ok (null (generator-unavailable-argument condition)))
        (ok (eq :empty-domain (generator-unavailable-kind condition)))))))

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

(defun demo-returns-one (xs)
  "Return 1 whatever the list is, so the first trial always fails."
  (declare (ignore xs))
  1)

(deftest a-run-pins-the-whole-generation-environment
  (testing "the same seed generates the same arguments however check-it is tuned"
    ;; RUN-GENERATED-TEST pinned *SIZE* alone, so an image that had tuned
    ;; CHECK-IT:*LIST-SIZE* or *BIAS-SENSITIVITY* generated different arguments
    ;; from the same seed -- and a replay disagreeing with the result it was
    ;; handed is what §72.3 forbids (§73.4 #7).
    (let ((cl-spec/src/registry:*registry* (make-hash-table-registry)))
      (defspec small-list (list-of (range integer 0 100)))
      (defspec-function demo-returns-one
        (:args (xs small-list))
        (:returns (range integer 0 0)))
      (let ((at-default (check-function 'demo-returns-one :trials 1 :seed 11))
            (at-tuned (let ((check-it:*list-size* 1)
                            (check-it:*list-size-decay* 0.5)
                            (check-it:*bias-sensitivity* 0.2)
                            (check-it:*recursive-bias-decay* 3.0)
                            (check-it:*num-trials* 7))
                        (check-function 'demo-returns-one :trials 1 :seed 11))))
        (ok (property-result-counterexample at-default))
        (ok (equal (property-result-counterexample at-default)
                   (property-result-counterexample at-tuned)))))))

(deftest sample-uses-the-generation-environment-a-run-uses
  (testing "an ambient CHECK-IT:*SIZE* does not reach SAMPLE"
    ;; GENERATE-VALUE read *SIZE* from whatever was ambient and only raised it to
    ;; the generator's own requirement, so a SAMPLE taken in a tuned image showed
    ;; a distribution no run draws (§73.4 #6).  It binds what a run binds now.
    (let ((cl-spec/src/registry:*registry* (make-hash-table-registry)))
      (defspec wide-integer (type integer))
      (let ((at-default (sample 'wide-integer :count 20 :seed 11))
            (at-tuned (let ((check-it:*size* 5000))
                        (sample 'wide-integer :count 20 :seed 11))))
        (ok (equal at-default at-tuned)))))
  (testing "and neither does an ambient CHECK-IT:*LIST-SIZE*"
    (let ((cl-spec/src/registry:*registry* (make-hash-table-registry)))
      (defspec small-list (list-of (range integer 0 100)))
      (let ((at-default (sample 'small-list :count 20 :seed 11))
            (at-tuned (let ((check-it:*list-size* 1)
                            (check-it:*list-size-decay* 0.5))
                        (sample 'small-list :count 20 :seed 11))))
        (ok (every #'listp at-default))
        (ok (equal at-default at-tuned))))))
