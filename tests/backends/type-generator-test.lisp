;;;; tests/backends/type-generator-test.lisp

(defpackage #:cl-spec/tests/backends/type-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/main
                #:*registry* #:defproperty #:make-hash-table-registry
                #:generator-unavailable #:generator-unavailable-kind #:generator-unavailable-reason
                #:normalize-spec-form #:property-result-counterexample
                #:property-result-shrunk-counterexample #:property-result-status
                #:replay-property #:run-property #:sample #:validp)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/backends/type-generator-test)

(deftest standard-types-draw-reproducible-admitted-values
  (dolist (form '(keyword symbol float short-float single-float double-float long-float
                  rational list vector fixnum))
    (testing (format nil "~S varies and reproduces under the same seed" form)
      (let* ((spec (normalize-spec-form form))
             (draws (sample spec :count 50 :seed 143)))
        (ok (= 50 (length draws)))
        (ok (every (lambda (value) (validp spec value)) draws))
        (ok (equalp draws (sample spec :count 50 :seed 143)))
        (ok (not (every (lambda (value) (equalp (first draws) value)) (rest draws))))
        (case form
          (symbol (ok (some (lambda (value) (not (keywordp value))) draws)))
          (rational (ok (some (lambda (value) (not (integerp value))) draws)))
          ((list vector) (ok (every (lambda (value) (<= (length value) 20)) draws)))
          ((float fixnum) (ok (every (lambda (value) (<= (abs value) 100)) draws)))))))
  (testing "a neighbouring wide integer range does not make a default fixnum or float invalid"
    (let* ((spec (normalize-spec-form
                  `(tuple (range integer 0 ,(expt 10 100)) fixnum float)))
           (draws (sample spec :count 12 :seed 26)))
      (ok (every (lambda (value) (validp spec value)) draws))
      (ok (every (lambda (value) (<= (abs (second value)) 100)) draws))
      (ok (every (lambda (value) (<= (abs (third value)) 100)) draws)))))

(deftest interval-types-fold-their-bounds
  (dolist (form '((type (integer 20 25))
                  (type (integer (20) (25)))
                  (type (integer * -70))
                  (type (integer (70)))
                  (type (float (0.0) (1.0)))
                  (type (float 1f0 1f0))
                  (type (short-float (3s0) 5s0))
                  (type (single-float * (-1f20)))
                  (type (double-float (1d100) 2d100))
                  (type (long-float -3l0 (0l0)))
                  (and (type (integer (20) *)) (range 21/1 26) (type (integer * (25))))
                  (and (type (float (0.0) 1.0)) (range 0 1/10))
                  (and (type (double-float (0d0) 1d0)) (range 1/10 1/5))
                  (and fixnum (type (integer (100) 105)))))
    (testing (format nil "~S generates straight from its interval" form)
      (let* ((spec (normalize-spec-form form))
             (draws (sample spec :count 30 :seed 145 :generation-budget 0)))
        (ok (= 30 (length draws)))
        (ok (every (lambda (value) (validp spec value)) draws))
        (unless (equal form '(type (float 1f0 1f0)))
          (ok (not (every (lambda (value) (eql (first draws) value)) (rest draws)))))))))

(defun unavailable-for (form)
  "Return the generator refusal signalled by FORM, if it has one."
  (handler-case (progn (sample (normalize-spec-form form) :count 1 :seed 143) nil)
    (generator-unavailable (condition) condition)))

#+sbcl
(deftest typed-float-intervals-honor-subnormal-bounds-with-underflow-traps
  (let* ((unit (rational least-positive-single-float))
         (spec (normalize-spec-form
                `(and single-float (range real ,(* 61/2 unit) ,(* 97/2 unit)))))
         (modes (sb-int:get-floating-point-modes)))
    (unwind-protect
         (progn
           (sb-int:set-floating-point-modes :traps (adjoin :underflow (getf modes :traps)))
           (let ((draws (sample spec :count 50 :seed 15)))
             (ok (= 50 (length draws)))
             (ok (every (lambda (value) (validp spec value)) draws))
             (ok (> (length (remove-duplicates draws)) 1))))
      (apply #'sb-int:set-floating-point-modes modes))))

(deftest interval-types-refuse-empty-domains
  (let ((next (+ 1f0 single-float-epsilon)))
    (dolist (form `((type (integer (1) (2)))
                    (type (double-float (0d0) 0d0))
                    (type (single-float (1f0) (,next)))
                    (and (type (integer 1 4)) (type (integer (4) 8)))
                    (and fixnum (type (integer ,(1+ most-positive-fixnum) *)))))
      (testing (format nil "~S has no admissible generated value" form)
        (let ((condition (unavailable-for form)))
          (ok (and condition (eq :empty-domain (generator-unavailable-kind condition))))))))
  (let* ((next (+ 1f0 single-float-epsilon))
         (spec (normalize-spec-form `(type (single-float (1f0) ,next)))))
    (ok (every (lambda (value) (and (= value next) (validp spec value)))
               (sample spec :count 12 :seed 143)))))

(deftest unsupported-types-are-named
  (dolist (type '(number cons (vector integer 2) (complex float)))
    (let ((condition (unavailable-for (list 'type type))))
      (ok (and condition (eq :unsupported-type (generator-unavailable-kind condition))))
      (ok (and condition
               (search (prin1-to-string type) (generator-unavailable-reason condition)
                       :test #'char-equal))))))

(deftest structured-and-sources-keep-their-declared-values
  (dolist (form '((and list (list-of (member :required) :min-length 2 :max-length 2))
                  (and vector (vector-of (member :required) :min-length 2 :max-length 2))
                  (and symbol (member :application-status))
                  (and keyword (member :application-status))))
    (let* ((spec (normalize-spec-form form))
           (draws (sample spec :count 4 :seed 143 :generation-budget 4)))
      (ok (= 4 (length draws)))
      (ok (every (lambda (value) (validp spec value)) draws)))))

(deftest numbers-shrink-to-small-counterexamples-and-replay
  (let ((*registry* (make-hash-table-registry)))
    (defproperty wanted-integer ((value rational))
      (:trials (:normal 30))
      (or (zerop value) (integerp value)))
    (defproperty avoids-middle ((value (range real 1/10 9/10)))
      (:trials (:normal 30))
      (or (<= value 1/4) (>= value 3/4)))
    (defproperty only-zero ((value float))
      (:trials (:normal 30))
      (zerop value))
    (dolist (example '((wanted-integer rational nil)
                       (avoids-middle real 1/2)
                       (only-zero float nil)))
      (destructuring-bind (name type minimum) example
        (testing (format nil "~S saves and replays a simpler ~S counterexample" name type)
          (let ((reductions
                  (loop for seed from 1 to 8
                        for result = (run-property name :seed seed)
                        for shrunk = (property-result-shrunk-counterexample result)
                        when shrunk collect (list result shrunk))))
            (ok reductions)
            (dolist (reduction reductions)
              (destructuring-bind (result shrunk) reduction
                (let ((value (second shrunk))
                      (replay (replay-property name result)))
                  (ok (eq :failed (property-result-status result)))
                  (ok (typep value type))
                  (ok (equalp shrunk (property-result-shrunk-counterexample replay)))
                  (case name
                    (wanted-integer
                     (ok (= 1 (abs (numerator value)))))
                    (avoids-middle (ok (= value minimum)))
                    (only-zero
                     (ok (= 1 (abs value)))
                     (ok (/= value (second (property-result-counterexample result)))))))))))))))

(deftest compound-integer-ranges-support-finite-distinct-sampling
  (dolist (form '((list-of (type (integer (20) 23)) :unique t :min-length 3 :max-length 3)
                  (alist-of (type (integer (20) 23)) null :min-count 3 :max-count 3)))
    (let* ((spec (normalize-spec-form form))
           (draws (sample spec :count 5 :seed 143 :generation-budget 0)))
      (ok (= 5 (length draws)))
      (ok (every (lambda (value) (validp spec value)) draws)))))

(deftest default-types-shrink-to-simple-admitted-values
  (let ((*registry* (make-hash-table-registry)))
    (defproperty needs-application-status ((items (tuple keyword symbol fixnum list vector)))
      (eq :application-status (first items)))
    (let* ((result (run-property 'needs-application-status :seed 143))
           (items (second (property-result-shrunk-counterexample result))))
      (ok (eq :failed (property-result-status result)))
      (ok (equalp (list :a (find-symbol "VALUE-A" "CL-SPEC/SRC/BACKENDS/GENERATED-SYMBOLS")
                          0 nil #())
                  items)))))

(deftest vector-keys-remain-distinct-when-shrunk-under-equal
  (let ((*registry* (make-hash-table-registry)))
    (defproperty never-four-entries
        ((entries (alist-of vector fixnum :test equal :min-count 4 :max-count 4)))
      (:trials (:normal 1))
      (< (length entries) 4))
    (let* ((result (run-property 'never-four-entries :seed 143))
           (entries (second (property-result-shrunk-counterexample result)))
           (keys (mapcar #'car entries)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 4 (length keys)))
      (ok (every (lambda (key) (zerop (length key))) keys))
      (ok (= 4 (length (remove-duplicates keys :test #'equal)))))))

(deftest default-symbol-vocabularies-are-finite-domains
  (dolist (form '((list-of keyword :unique t :min-length 26)
                  (list-of symbol :unique t :min-length 34)
                  (hash-table-of keyword integer :test eq :min-count 26)
                  (hash-table-of symbol integer :test eq :min-count 34)))
    (let* ((spec (normalize-spec-form form))
           (draws (sample spec :count 2 :seed 173 :generation-budget 0)))
      (ok (= 2 (length draws)))
      (ok (every (lambda (value) (validp spec value)) draws))))
  (dolist (form '((hash-table-of keyword integer :test eq :min-count 27)
                  (hash-table-of symbol integer :test eq :min-count 35)))
    (let ((condition (unavailable-for form)))
      (ok (and condition (eq :empty-domain (generator-unavailable-kind condition)))))))

(deftest default-symbol-generator-uses-writable-ordinary-symbols
  (let* ((draws (sample (normalize-spec-form 'symbol) :count 200 :seed 173))
         (ordinary (remove-if #'keywordp draws)))
    (ok ordinary)
    (ok (some #'keywordp draws))
    (ok (every (lambda (name)
                 (and (symbol-package name)
                      (not (eq (symbol-package name) (find-package :common-lisp)))
                      (not (constantp name))))
               ordinary))
    (let ((name (first ordinary)))
      (when (and name (not (constantp name))
                 (not (eq (symbol-package name) (find-package :common-lisp))))
        (progv (list name) (list nil)
          (set name :writable)
          (ok (eq :writable (symbol-value name))))))))
