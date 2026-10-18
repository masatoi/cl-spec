;;;; self-generation-fixtures.lisp

(defpackage #:cl-spec/self-generation-fixtures
  (:use #:cl)
  (:import-from #:cl-spec/main)
  (:export #:structured-generation-forms #:tagged-generation-form
           #:structured-counterexample-contracts #:retained-counterexample-valid-p
           #:generation-exhaustion-observations))

(in-package #:cl-spec/self-generation-fixtures)

(defun tagged-generation-form ()
  "Return a two-branch domain whose alternatives both have reducible payloads."
  '(tagged-by :kind
     (:left (plist (:required (:kind (member :left))
                              (:payload (list-of integer :min-length 1 :max-length 3)))
                   (:closed t)))
     (:right (plist (:required (:kind (member :right))
                               (:payload (alist-of (member :a :b) integer
                                                   :min-count 1 :max-count 2)))
                    (:closed t)))))

(defun structured-generation-forms (&key recheck-p)
  "Return a finite corpus visiting every declared representation and key test.
EQ uses symbol identity. EQUAL and EQUALP include equivalent string keys.
Exact counts, empty maps, drawn keys and nested values exercise distinct paths.
RECHECK-P replaces identity-sensitive string MEMBER domains with STRING: recorded
cons/array snapshots copy strings and cannot preserve EQL membership identity."
  (append
   (loop for kind in '(alist-of hash-table-of)
         append
         (loop for (test keys) in '((eq (member :a :b))
                                   (eql (member 1 1.0))
                                   (equal (member "a" "a" "b"))
                                   (equalp (member "a" "A" "b")))
               collect `(,kind ,(if (and recheck-p (member test '(equal equalp)))
                                    'string keys)
                               (range integer 10 30)
                               :test ,test :min-count 2 :max-count 2)))
   '((alist-of integer (range integer 10 30) :min-count 1 :max-count 3)
     (hash-table-of string (range integer 10 30)
                    :test equalp :min-count 1 :max-count 3)
     (alist-of (satisfies consp) (satisfies consp) :max-count 0)
     (hash-table-of (satisfies consp) (satisfies consp) :test equal :max-count 0)
     (alist-of (member) integer)
     (hash-table-of (member) integer)
     (alist-of (member :a :b) (list-of integer :min-length 1 :max-length 2)
               :min-count 1 :max-count 2)
     (hash-table-of (member :a :b)
                    (alist-of (member :x :y) integer :min-count 1 :max-count 2)
                    :min-count 1 :max-count 2)
     (alist (:test equal) (:required ("id" integer))
            (:optional ("note" (nullable string))) (:closed t))
     (hash-table (:test equalp) (:required ("ID" integer))
                 (:optional ("note" (nullable string))) (:closed t))
     (and integer (range 10 30))
     (and (range integer 10 30) (satisfies evenp))
     (and (alist-of (member :a :b) integer :min-count 1 :max-count 2)
          (satisfies consp))
     (alist-of (and (range integer 0 10) (satisfies evenp)) integer
               :min-count 1 :max-count 3))
   (let ((tagged (tagged-generation-form)))
     ;; The full union tests dispatch; singleton unions make both branch
     ;; shrink paths mandatory in every law iteration.
     (list tagged
           (list (first tagged) (second tagged) (third tagged))
           (list (first tagged) (second tagged) (fourth tagged))))))

(defun structured-counterexample-target (value)
  "Return VALUE unchanged so an impossible return spec supplies a stable failure."
  value)

(defun structured-counterexample-contracts ()
  "Build anonymous contracts for every structured, snapshot-stable generation domain.
These contracts deliberately fail and never register definitions or mutate inputs."
  (mapcar (lambda (form)
            (make-instance 'cl-spec:function-spec
                           :name 'structured-counterexample-target
                           :argument-specs (list (list 'value form))
                           :return-spec '(member :impossible-return)))
          (structured-generation-forms :recheck-p t)))

(defun retained-counterexample-valid-p (contract result &key require-reduction)
  "Check original and retained shrink evidence against CONTRACT and one-shot rechecks.
A missing original, invalid input, changed failure or false claim of a used shrink
is refused. Absence of a shrink is allowed for domains such as an empty map.
This does not serialize values and therefore also covers hash tables.
REQUIRE-REDUCTION additionally demands changed arguments under EQUALP, including
hash-table contents, for the fixed-seed acceptance fixtures. The general law
permits an unchanged accepted candidate: a generated input can already be minimal."
  (let ((original (cl-spec:property-result-failure-evidence result))
        (shrunk (cl-spec:property-result-shrunk-evidence result)))
    (and (eq :failed (cl-spec:property-result-status result))
         original
         (or (not require-reduction)
             (and shrunk
                  (not (equalp (cl-spec:trial-observation-arguments original)
                               (cl-spec:trial-observation-arguments shrunk)))))
         (eq (not (null shrunk))
             (eq :used (cl-spec:property-result-shrunk-outcome result)))
         (every
          (lambda (observation)
            (let ((arguments (cl-spec:trial-observation-arguments observation)))
              (and (eq :failed (cl-spec:trial-observation-status observation))
                   (cl-spec:validp (cl-spec:function-spec-argument-schema contract) arguments)
                   (cl-spec:failure-identities-match-p
                    (cl-spec:trial-observation-signature original)
                    (cl-spec:trial-observation-signature observation))
                   (let* ((recheck (cl-spec:check-call contract arguments))
                          (checked (cl-spec:call-check-result-observation recheck)))
                     (and (eq :failed (cl-spec:call-check-result-status recheck))
                          (cl-spec:failure-identities-match-p
                           (cl-spec:trial-observation-signature original)
                           (cl-spec:trial-observation-signature checked)))))))
          (if shrunk (list original shrunk) (list original))))))

(defun generation-exhaustion-observations (budget)
  "Return saved exhaustion reports for a refusing filter and colliding map keys.
Each request owns BUDGET reservations. A private registry keeps the constant key
generator independent of the caller's definitions. NIL means an unexpected success."
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defgenerator constant-key () 0)
    (cl-spec:defspec collision-key integer (:generator constant-key))
    (mapcar
     (lambda (form)
       (handler-case
           (progn
             (cl-spec:sample (cl-spec:normalize-spec-form form)
                             :count 1 :seed 1 :generation-budget budget)
             nil)
         (cl-spec:generation-budget-exhausted (condition)
           (cl-spec:generation-budget-exhausted-report condition))))
     '((and (member 0) (satisfies plusp))
       (alist-of collision-key null :min-count 2 :max-count 2)
       (hash-table-of collision-key null :min-count 2 :max-count 2)))))
