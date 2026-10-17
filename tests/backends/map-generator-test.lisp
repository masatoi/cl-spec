;;;; tests/backends/map-generator-test.lisp

(defpackage #:cl-spec/tests/backends/map-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/map-spec #:alist-of-spec)
  (:import-from #:cl-spec/src/ir #:member-spec)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/generator #:sample #:backend-capabilities)
  (:import-from #:cl-spec/src/generation-request #:generation-report-p)
  (:import-from #:cl-spec/src/backends/check-it #:check-it-backend)
  (:import-from #:cl-spec/src/backends/check-it-generators #:compile-spec-generator)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable #:generator-unavailable-reason
                #:generation-budget-exhausted
                #:generation-budget-exhausted-attempts
                #:generation-budget-exhausted-rejections
                #:generation-budget-exhausted-path)
  (:import-from #:cl-spec/src/dsl #:defspec #:defgenerator #:defproperty)
  (:import-from #:cl-spec/src/property-runner
                #:run-property #:property-result-status
                #:property-result-shrunk-counterexample))

(in-package #:cl-spec/tests/backends/map-generator-test)

(defvar *key-counter* 0
  "Source of always-fresh keys for the collision-free test.")

(defvar *scripted-keys* nil
  "Keys the scripted generator hands out, in order.")

(defun sample-form (form &rest args)
  "Return (VALUES VALUES REPORT) for the normalized FORM."
  (apply #'sample (normalize-spec-form form) args))

(defun alist-keys (alist)
  "Return the keys of ALIST in order."
  (mapcar #'car alist))

(defun distinct-under-p (keys test)
  "Return true when no two of KEYS are equal under TEST."
  (= (length keys) (length (remove-duplicates keys :test test))))

(deftest generated-maps-satisfy-their-spec
  (dolist (form '((hash-table-of string integer)
                  (hash-table-of string integer :test equal :min-count 1 :max-count 6)
                  (hash-table-of character (list-of integer))
                  (hash-table-of string string :test equalp)
                  (alist-of string integer :test eq)
                  (alist-of (range integer 0 9) string :min-count 2 :max-count 4)
                  (alist-of (member :a :b :c) (nullable integer))
                  (alist-of string (alist-of string integer :test equal)
                            :test equal :max-count 3)))
    (let ((spec (normalize-spec-form form)))
      (ok (every (lambda (value) (validp spec value)) (sample spec :count 50 :seed 11))
          (format nil "samples of ~S satisfy it" form)))))

(deftest generated-tables-carry-the-declared-test
  (ok (every (lambda (table) (eq 'equalp (hash-table-test table)))
             (sample-form '(hash-table-of string integer :test equalp) :count 10 :seed 3))))

(deftest map-generation-is-reproducible-from-a-seed
  (ok (equal (sample-form '(alist-of string integer :test equal) :count 20 :seed 9)
             (sample-form '(alist-of string integer :test equal) :count 20 :seed 9))))

(deftest finite-key-domains-are-sampled-without-repeats
  (let ((alists (sample-form '(alist-of (member :a :b :c) integer :min-count 2)
                             :count 50 :seed 5)))
    (ok (every (lambda (alist) (<= 2 (length alist) 3)) alists))
    (ok (every (lambda (alist) (distinct-under-p (alist-keys alist) #'eql)) alists)))
  (testing "the declared test decides which enumerated keys are distinct"
    (ok (every (lambda (table) (= 1 (hash-table-count table)))
               (sample-form '(hash-table-of (member "a" "A") integer :test equalp :min-count 1)
                            :count 20 :seed 5)))
    (ok (handler-case
            (progn (sample-form '(hash-table-of (member "a" "A") integer
                                  :test equalp :min-count 2)
                                :count 1)
                   nil)
          (generator-unavailable () t))))
  (testing "a finite integer range is sampled, and its width bounds MIN-COUNT"
    (ok (every (lambda (alist)
                 (and (= 5 (length alist)) (distinct-under-p (alist-keys alist) #'eql)))
               (sample-form '(alist-of (range integer 0 4) null :min-count 5) :count 10 :seed 5)))
    (ok (handler-case
            (progn (sample-form '(alist-of (range integer 0 4) null :min-count 6) :count 1) nil)
          (generator-unavailable () t)))))

(deftest drawn-keys-are-distinct-under-the-test
  (ok (every (lambda (alist) (distinct-under-p (alist-keys alist) #'equal))
             (sample-form '(alist-of string integer :test equal) :count 50 :seed 2)))
  (ok (every (lambda (alist) (distinct-under-p (alist-keys alist) #'equalp))
             (sample-form '(alist-of string integer :test equalp) :count 50 :seed 2))))

(deftest custom-key-generators-win-over-enumeration
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator always-z () :z)
    (defspec custom-key (member :a :b) (:generator always-z))
    (flet ((keys-of (spec)
             (loop for alist in (sample spec :count 20 :seed 1) append (alist-keys alist))))
      (ok (every (lambda (key) (eq key :z))
                 (keys-of (normalize-spec-form '(alist-of custom-key null)))))
      (ok (every (lambda (key) (member key '(:z nil)))
                 (keys-of (normalize-spec-form '(alist-of (nullable custom-key) null)))))
      (testing "a generator on a directly constructed member node is honoured"
        (ok (every (lambda (key) (eq key :z))
                   (keys-of (make-instance 'alist-of-spec
                                           :key-spec (make-instance 'member-spec
                                                                    :values '(:a :b)
                                                                    :generator 'always-z)
                                           :value-spec (normalize-spec-form 'null)))))))))

(deftest unavailable-children-name-their-side
  (flet ((reason (form)
           (handler-case (progn (sample-form form :count 1) nil)
             (generator-unavailable (condition) (generator-unavailable-reason condition)))))
    (ok (search "map key spec" (reason '(hash-table-of (satisfies consp) integer))))
    (ok (search "map value spec" (reason '(alist-of string (satisfies consp))))))
  (testing "a map that admits no entry needs no child generator"
    (ok (equal '(nil nil nil)
               (sample-form '(alist-of (satisfies consp) (satisfies consp) :max-count 0)
                            :count 3 :seed 1)))))

(deftest collision-free-maps-consume-no-budget
  (let ((*registry* (make-hash-table-registry))
        (*key-counter* 0))
    (defgenerator fresh-key () (incf *key-counter*))
    (defspec counter-key integer (:generator fresh-key))
    (multiple-value-bind (values report)
        (sample-form '(hash-table-of counter-key (hash-table-of counter-key integer))
                     :count 20 :seed 4)
      (ok (= 20 (length values)))
      (ok (generation-report-p report))
      (ok (zerop (getf report :attempts)))
      (ok (zerop (getf report :rejections)))
      (ok (eq :completed (getf report :termination))))))

(deftest each-redraw-reserves-and-only-colliding-redraws-are-rejected
  (let ((*registry* (make-hash-table-registry))
        (*scripted-keys* (list 1 1 1 2)))
    (defgenerator scripted-key () (pop *scripted-keys*))
    (defspec script-key integer (:generator scripted-key))
    (multiple-value-bind (values report)
        (sample-form '(alist-of script-key null :min-count 2 :max-count 2) :count 1 :seed 4)
      (testing "the first draw of each slot is free; each redraw reserves one candidate"
        (ok (equal '(1 2) (alist-keys (first values))))
        (ok (= 2 (getf report :attempts)))
        (ok (= 1 (getf report :rejections)))
        (ok (eq :completed (getf report :termination)))))))

(deftest a-map-stops-early-once-min-count-holds
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator constant-key () 1)
    (defspec same-key integer (:generator constant-key))
    (testing "eight consecutive collisions end the map; its seven redraws are all rejected"
      (multiple-value-bind (values report)
          (sample-form '(alist-of same-key null :min-count 1 :max-count 3) :count 30 :seed 6)
        (ok (every (lambda (alist) (equal '(1) (alist-keys alist))) values))
        (ok (plusp (getf report :attempts)))
        (ok (= (getf report :attempts) (getf report :rejections)))
        (ok (zerop (mod (getf report :attempts) 7)))
        (ok (eq :completed (getf report :termination)))))
    (testing "with no budget, a map holding MIN-COUNT keys stops without reserving"
      (multiple-value-bind (values report)
          (sample-form '(alist-of same-key null :min-count 1 :max-count 3)
                       :count 30 :seed 6 :generation-budget 0)
        (ok (every (lambda (alist) (equal '(1) (alist-keys alist))) values))
        (ok (zerop (getf report :attempts)))
        (ok (eq :completed (getf report :termination)))))
    (testing "below MIN-COUNT, redraws continue until the budget is exhausted"
      (ok (handler-case
              (progn (sample-form '(alist-of same-key null :min-count 2)
                                  :count 1 :generation-budget 5)
                     nil)
            (generation-budget-exhausted (condition)
              (and (= 5 (generation-budget-exhausted-attempts condition))
                   (= 5 (generation-budget-exhausted-rejections condition))
                   (equal '(:map-key) (generation-budget-exhausted-path condition)))))))))

(deftest key-filters-share-the-request-budget
  (multiple-value-bind (values report)
      (sample-form '(alist-of (and (range integer 0 1) (satisfies evenp)) null :max-count 3)
                   :count 20 :seed 8)
    (ok (every (lambda (alist) (every #'zerop (alist-keys alist))) values))
    (ok (generation-report-p report))
    (ok (plusp (getf report :attempts)))
    (ok (<= (getf report :rejections) (getf report :attempts)))
    ;; The AND filter reserves once per source call in the same request, so every key
    ;; that ended up in a map cost at least one reservation.
    (ok (>= (getf report :attempts) (loop for alist in values sum (length alist))))))

(deftest a-bare-generate-outside-a-request-terminates
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator constant-key () 1)
    (defspec same-key integer (:generator constant-key))
    (let ((generator (compile-spec-generator
                      (normalize-spec-form '(alist-of same-key null :min-count 2))
                      (list :registry *registry*))))
      (ok (handler-case (progn (check-it:generate generator) nil)
            (generation-budget-exhausted () t))))))

(deftest each-draw-returns-a-fresh-container
  (destructuring-bind (first second)
      (sample-form '(hash-table-of (member :a) integer :min-count 1) :count 2 :seed 1)
    (ok (not (eq first second)))
    (setf (gethash :added first) 0)
    (ok (not (nth-value 1 (gethash :added second)))))
  (destructuring-bind (first second)
      (sample-form '(alist-of (member :a) integer :min-count 1) :count 2 :seed 1)
    (ok (not (eq first second)))
    (ok (not (eq (first first) (first second))))))

(deftest map-generation-capabilities
  (let ((backend (make-instance 'check-it-backend)))
    (dolist (entry '(((hash-table-of string integer) :available)
                     ((alist-of (member :a) null :min-count 1 :max-count 1) :none)
                     ((alist-of (member :a :b) null :min-count 1 :max-count 2) :available)
                     ((alist-of (satisfies consp) (satisfies consp) :max-count 0) :none)
                     ((alist-of (member) integer) :none)
                     ((hash-table-of (member) integer :test equal) :none)))
      (ok (equal (list :generation :available :shrinking (second entry))
                 (backend-capabilities backend (normalize-spec-form (first entry))))
          (format nil "Capabilities for ~S" (first entry))))))

(deftest eq-maps-do-not-bound-numeric-keys-by-their-value-count
  (let ((n (expt 2 100)))
    (testing "a numeric range can supply EQ-distinct copies"
      (let ((spec (normalize-spec-form `(alist-of (range integer ,n ,n) null
                                                  :test eq :min-count 2 :max-count 2))))
        (ok (every (lambda (alist) (and (= 2 (length alist)) (validp spec alist)))
                   (sample spec :count 5 :seed 1)))))
    (testing "a member domain is not refused as unsatisfiable under EQ"
      (let ((form `(alist-of (member ,n) null :test eq :min-count 2 :max-count 2)))
        (ok (handler-case (progn (sample-form form :count 1 :generation-budget 50) nil)
              (generation-budget-exhausted () t)
              (generator-unavailable () nil))
            (format nil "~S is not refused as unsatisfiable" form))))
    (testing "an EQ map of numeric keys still generates what it can"
      (ok (every (lambda (alist) (= 1 (length alist)))
                 (sample-form `(alist-of (range integer ,n ,n) null
                                         :test eq :min-count 1 :max-count 1)
                              :count 5 :seed 1)))
      (let ((spec (normalize-spec-form '(alist-of (range integer 0 9) null
                                         :test eq :min-count 3))))
        (ok (every (lambda (value) (validp spec value)) (sample spec :count 20 :seed 2))))))
  (testing "a symbol domain keeps its exact bound under EQ"
    (ok (handler-case
            (progn (sample-form '(alist-of (member :a :b) null :test eq :min-count 3) :count 1)
                   nil)
          (generation-budget-exhausted () nil)
          (generator-unavailable () t)))))

(deftest map-shrinking-removes-entries-and-reduces-values
  (let ((*registry* (make-hash-table-registry)))
    (defproperty small-values
        ((counts (alist-of integer (range integer 0 100))))
      (:trials (:normal 200))
      (every (lambda (entry) (< (cdr entry) 50)) counts))
    (let* ((result (run-property 'small-values :seed 42))
           (shrunk (getf (property-result-shrunk-counterexample result) 'counts)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 1 (length shrunk)))
      (ok (= 50 (cdr (first shrunk))))
      (testing "a drawn key shrinks too"
        (ok (eql 0 (car (first shrunk))))))))

(deftest map-shrinking-keeps-min-count-and-distinct-keys
  (let ((*registry* (make-hash-table-registry)))
    (defproperty never-holds
        ((table (hash-table-of integer (range integer 50 100) :test equal :min-count 2)))
      (:trials (:normal 20))
      (not (hash-table-p table)))
    (defproperty never-holds-alist
        ((pairs (alist-of integer null :min-count 2)))
      (:trials (:normal 20))
      (not (listp pairs)))
    (let* ((result (run-property 'never-holds :seed 7))
           (shrunk (getf (property-result-shrunk-counterexample result) 'table)))
      (ok (eq :failed (property-result-status result)))
      (testing "two keys never shrink into one"
        (ok (= 2 (hash-table-count shrunk))))
      (ok (eq 'equal (hash-table-test shrunk)))
      (testing "value shrinks never leave the value spec"
        (ok (loop for value being the hash-values of shrunk always (<= 50 value 100)))))
    (let* ((result (run-property 'never-holds-alist :seed 7))
           (shrunk (getf (property-result-shrunk-counterexample result) 'pairs)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 2 (length shrunk)))
      (ok (distinct-under-p (alist-keys shrunk) #'eql)))))

(deftest map-shrinking-refuses-colliding-keys
  (let ((*registry* (make-hash-table-registry)))
    (let ((generator (compile-spec-generator
                      (normalize-spec-form '(alist-of integer null :min-count 2))
                      (list :registry *registry*)))
          (offered nil))
      (dotimes (trial 20)
        (check-it:generate generator)
        ;; Every candidate fails the property, so each offered key is adopted unless refused.
        (check-it:shrink generator (lambda (candidate) (push candidate offered) nil)))
      (ok (plusp (length offered)))
      (testing "no offered candidate repeats a key or drops below MIN-COUNT"
        (ok (every (lambda (candidate)
                     (and (<= 2 (length candidate))
                          (distinct-under-p (alist-keys candidate) #'eql)))
                   offered))))))

(deftest drawn-keys-widen-their-range-to-stay-distinct
  (multiple-value-bind (values report)
      (sample-form '(hash-table-of (range integer 0 *) null :min-count 300) :count 1 :seed 1)
    (ok (= 300 (hash-table-count (first values))))
    (ok (eq :completed (getf report :termination)))
    (ok (< (getf report :attempts) 300))))

(deftest drawn-keys-find-room-above-a-high-lower-bound
  (dolist (seed '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19))
    (ok (handler-case
            (= 2 (hash-table-count
                  (first (sample-form '(hash-table-of (range integer 100 *) null
                                        :min-count 2 :max-count 2)
                                      :count 1 :seed seed))))
          (generation-budget-exhausted () nil))
        (format nil "seed ~D draws two distinct keys above 100" seed))))

(deftest map-sizes-ignore-unrelated-numeric-bounds
  (testing "a wide value range does not inflate the entry count"
    (multiple-value-bind (values report)
        (sample-form '(hash-table-of string (range integer 0 100000) :test equal)
                     :count 10 :seed 1)
      (ok (every (lambda (table) (<= (hash-table-count table) 20)) values))
      (ok (< (getf report :attempts) (getf report :budget)))))
  (testing "a declared minimum above the soft cap is still honoured"
    (ok (every (lambda (alist) (= 25 (length alist)))
               (sample-form '(alist-of (range integer 0 *) null :min-count 25 :max-count 25)
                            :count 3 :seed 2)))))

(deftest maps-can-source-an-and
  (dolist (form '((and (alist-of string integer :test equal) (satisfies listp))
                  (and (hash-table-of string integer :test equal :min-count 1)
                       (satisfies hash-table-p))))
    (let ((spec (normalize-spec-form form)))
      (ok (every (lambda (value) (validp spec value)) (sample spec :count 20 :seed 3))
          (format nil "samples of ~S satisfy it" form)))))
