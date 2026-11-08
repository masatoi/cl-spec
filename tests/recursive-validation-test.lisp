;;;; tests/recursive-validation-test.lisp
;;;;
;;;; Termination and cost of validating against specs that refer to themselves
;;;; (issues #58 and #59).

(defpackage #:cl-spec/tests/recursive-validation-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:invalid-spec-form
                #:invalid-spec-form-form
                #:invalid-spec-form-reason)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/validator
                #:validp))

(in-package #:cl-spec/tests/recursive-validation-test)

(defun registry-with (&rest definitions)
  "Return a fresh registry holding DEFINITIONS, a list of (NAME FORM) pairs."
  (let ((registry (make-hash-table-registry)))
    (loop for (name form) in definitions
          do (registry-register-spec registry name (normalize-spec-form form :name name)))
    registry))

(defmacro within-seconds ((seconds) &body body)
  "Evaluate BODY, returning (:RETURNED VALUE), or :TIMED-OUT after SECONDS.

A regression in these tests is non-termination, so each check is bounded rather
than left to hang the suite."
  #+sbcl
  `(handler-case (sb-ext:with-timeout ,seconds (list :returned (progn ,@body)))
     (sb-ext:timeout () :timed-out))
  #-sbcl
  `(progn ,seconds (list :returned (progn ,@body))))

(defun refusal-of (thunk)
  "Return the CL-SPEC-ERROR THUNK signals within two seconds, :TIMED-OUT, or :NONE."
  (let ((outcome (within-seconds (2)
                   (handler-case (progn (funcall thunk) :none)
                     (cl-spec-error (condition) condition)))))
    (if (consp outcome) (second outcome) outcome)))

(defun self-containing-pair ()
  "Return the list (1 X) whose second element is the list itself."
  (let ((value (list 1 nil)))
    (setf (second value) value)
    value))

(defun add-chain (depth)
  "Return (:ADD (:ADD ... 1 1) 1) nested DEPTH times."
  (let ((value 1))
    (dotimes (index depth value)
      (setf value (list :add value 1)))))

(deftest a-reference-cycle-that-consumes-nothing-is-refused
  (let ((registry (registry-with '(alias-a alias-b) '(alias-b alias-a)
                                 '(self-and (and integer self-and)))))
    (testing "two aliases naming each other signal INVALID-SPEC-FORM instead of looping"
      (let ((condition (refusal-of (lambda () (validp 'alias-a 1 :registry registry)))))
        (ok (typep condition 'invalid-spec-form))
        (ok (and (typep condition 'invalid-spec-form)
                 (search "cycle" (invalid-spec-form-reason condition))))))
    (testing "a spec that reaches itself through AND on the same value is refused"
      (ok (typep (refusal-of (lambda () (validp 'self-and 1 :registry registry)))
                 'invalid-spec-form)))
    (testing "EXPLAIN-DATA refuses the same cycle"
      (ok (typep (refusal-of (lambda () (explain-data 'alias-a 1 :registry registry)))
                 'invalid-spec-form)))
    (testing "the refusal names the reference that closed the cycle"
      (let ((condition (refusal-of (lambda () (validp 'alias-a 1 :registry registry)))))
        (ok (and (typep condition 'invalid-spec-form)
                 (member (invalid-spec-form-form condition) '(alias-a alias-b))))))))

(deftest a-value-that-contains-itself-is-reported-not-followed
  (let ((registry (registry-with '(pair-tree (or null (tuple integer pair-tree))))))
    (testing "VALIDP answers NIL for a value reachable from itself"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (validp 'pair-tree (self-containing-pair) :registry registry)))))
    (testing "EXPLAIN-DATA names the cycle with a :CYCLIC-VALUE datum"
      (let* ((outcome (within-seconds (2)
                        (explain-data 'pair-tree (self-containing-pair) :registry registry)))
             (data (and (consp outcome) (second outcome))))
        (ok data)
        (ok (labels ((mentions-cycle-p (datums)
                       (some (lambda (datum)
                               (or (eq :cyclic-value (getf datum :kind))
                                   (mentions-cycle-p (getf datum :errors))
                                   (some (lambda (branch)
                                           (mentions-cycle-p (getf branch :errors)))
                                         (getf datum :branches))))
                             datums)))
              (mentions-cycle-p (getf data :errors))))))
    (testing "a finite value of the same shape is still admitted"
      (ok (validp 'pair-tree '(1 (2 (3 nil))) :registry registry)))))

(deftest recursive-disjunctions-validate-in-linear-time
  (let ((registry (registry-with '(ast (or integer
                                           (tuple (member :add) ast ast)
                                           (tuple (member :mul) ast ast))))))
    (testing "a 200-deep valid expression is checked within a second"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (and (validp 'ast (add-chain 200) :registry registry) t)))))
    (testing "EXPLAIN-DATA on the same value is just as fast"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (getf (explain-data 'ast (add-chain 200) :registry registry) :valid)))))
    (testing "an invalid leaf deep in the expression is still found and located"
      (let ((value (add-chain 200)))
        (setf (third value) "x")
        (let ((outcome (within-seconds (1)
                         (explain-data 'ast value :registry registry))))
          (ok (consp outcome))
          (ok (and (consp outcome) (null (getf (second outcome) :valid)))))))))

(defun shared-dag (depth)
  "Return a binary DAG DEPTH levels deep whose two children are the same object."
  (let ((node 1))
    (dotimes (index depth node)
      (setf node (list node node)))))

(deftest shared-objects-validate-in-linear-time
  ;; Issue #85: memoized reference results were scanned linearly per value, so a
  ;; value reached at N positions cost N^2.
  (let ((registry (registry-with '(leaf (or string real null))
                                 '(tree (or integer (tuple tree tree))))))
    (testing "a list of one shared string under a named spec is checked within a second"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (and (validp (normalize-spec-form '(list-of leaf))
                                (make-list 40000 :initial-element "x")
                                :registry registry)
                        t)))))
    (testing "a shared binary DAG 16 levels deep is checked within a second"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (and (validp 'tree (shared-dag 16) :registry registry) t)))))
    (testing "an invalid shared leaf is still found at every position"
      (let ((dag (shared-dag 3)))
        (setf (first (first (first dag))) "bad"
              (second (first (first dag))) "bad")
        (ok (not (validp 'tree dag :registry registry)))))))

(defun nested-chain (depth)
  "Return (DEPTH-1 (DEPTH-2 ... (0 NIL))), a linked chain DEPTH nodes deep."
  (let ((value nil))
    (dotimes (index depth value)
      (setf value (list index value)))))

(defun last-node (chain)
  "Return the innermost (INDEX NIL) node of CHAIN."
  (loop while (second chain)
        do (setf chain (second chain)))
  chain)

(defun bytes-allocated-by (thunk)
  "Call THUNK and return the bytes it allocated, or 0 where that is not measurable."
  #+sbcl
  (let ((before (sb-ext:get-bytes-consed)))
    (funcall thunk)
    (- (sb-ext:get-bytes-consed) before))
  #-sbcl
  (progn (funcall thunk) 0))

(deftest deep-recursive-values-validate-in-linear-space
  ;; The path trie of #85 made one chain of trie nodes per value, as long as the
  ;; value's depth, so a linked structure N deep allocated N^2 nodes: 769 MB at
  ;; 2000.  900 levels, under the reference depth limit, now cost well under 4 MB.
  (let ((registry (registry-with '(chain (or null (tuple integer chain))))))
    (testing "a chain 900 nodes deep is checked within a second"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (and (validp 'chain (nested-chain 900) :registry registry) t)))))
    (testing "checking it allocates a bounded amount per node"
      (let ((value (nested-chain 900)))
        (ok (< (bytes-allocated-by (lambda () (validp 'chain value :registry registry)))
               (* 4 1024 1024)))
        (ok (< (bytes-allocated-by (lambda () (explain-data 'chain value :registry registry)))
               (* 4 1024 1024)))))
    (testing "an invalid leaf at the bottom is still found"
      (let ((value (nested-chain 300)))
        (setf (first (last-node value)) "bad")
        (ok (not (validp 'chain value :registry registry)))))))

(deftest atoms-reached-through-a-name-cost-no-bookkeeping
  ;; Interning the position of every reference visit, atoms included, made a
  ;; list of a million digits under a named spec allocate 300 MB.
  (let ((registry (registry-with '(digit (range integer 0 9))))
        (value (make-list 200000 :initial-element 5)))
    (ok (< (bytes-allocated-by
            (lambda () (validp (normalize-spec-form '(list-of digit)) value
                               :registry registry)))
           ;; One active-frame cons pair per visit, which the cycle check needs,
           ;; and nothing retained: about 50 bytes an element, not 270.
           (* 16 1024 1024)))))

(deftest a-value-nested-past-the-reference-limit-is-refused
  ;; Each nested reference descends the control stack, so a chain tens of
  ;; thousands deep exhausted it and could end the process.
  (let ((registry (registry-with '(chain (or null (tuple integer chain)))))
        (deep (nested-chain 20000)))
    (dolist (check (list (lambda () (validp 'chain deep :registry registry))
                         (lambda () (explain-data 'chain deep :registry registry))
                         (lambda () (cl-spec/src/validator:validate 'chain deep
                                                                    :registry registry))))
      (let ((outcome (refusal-of check)))
        (ok (typep outcome 'cl-spec/src/conditions:validation-depth-exceeded))
        (ok (and (typep outcome 'cl-spec/src/conditions:validation-depth-exceeded)
                 (eq 'chain (cl-spec/src/conditions:validation-depth-exceeded-spec outcome))))))
    (testing "a chain just inside the limit is still admitted"
      (ok (validp 'chain (nested-chain 990) :registry registry)))))

(defvar *predicate-calls* 0
  "How many times COUNTED-ODD-P and COUNTED-POSITIVE-P were called.")

(defun counted-odd-p (value)
  "Count the call and return whether VALUE is an odd integer."
  (incf *predicate-calls*)
  (and (integerp value) (oddp value)))

(defun counted-positive-p (value)
  "Count the call and return whether VALUE is a positive integer."
  (incf *predicate-calls*)
  (and (integerp value) (plusp value)))

(deftest a-refused-disjunction-runs-each-branch-once
  ;; Explaining a refusal must not re-run the predicates that refused it.
  (let ((spec (normalize-spec-form '(or (satisfies counted-odd-p)
                                       (or (satisfies counted-positive-p)
                                           (satisfies counted-odd-p))))))
    (let ((*predicate-calls* 0))
      (explain-data spec -4)
      (ok (= 3 *predicate-calls*)))
    (testing "and the explanation still locates the refusal from the root"
      (let* ((registry (registry-with '(pair (or null (tuple integer pair)))))
             (data (explain-data 'pair '(1 (2 ("x" nil))) :registry registry)))
        (ok (not (getf data :valid)))
        (ok (labels ((paths (errors)
                       (loop for datum in errors
                             append (cons (getf datum :path)
                                          (append (paths (getf datum :errors))
                                                  (loop for branch in (getf datum :branches)
                                                        append (paths (getf branch :errors))))))))
              (member '(1 1 0) (paths (getf data :errors)) :test #'equal)))))))

(defun self-containing-singleton ()
  "Return the list (X) whose only element is the list itself."
  (let ((value (list nil)))
    (setf (car value) value)
    value))

(deftest negation-does-not-admit-a-cyclic-value
  ;; Issue #87: the cut of a cycle landed at a different depth through an alias,
  ;; and a NOT flipped the cut, so an alias disagreed with its own target.
  (let ((registry (registry-with '(negated (not (list-of negated)))
                                 '(negated-alias negated))))
    (testing "the target and its alias agree, and neither admits the cyclic value"
      (ok (equal '(:returned (nil nil nil))
                 (within-seconds (2)
                   (list (validp 'negated (self-containing-singleton) :registry registry)
                         (validp 'negated-alias (self-containing-singleton)
                                 :registry registry)
                         (validp (normalize-spec-form '(and negated (list-of negated)))
                                 (self-containing-singleton) :registry registry))))))
    (testing "a finite value is still judged by the negation"
      (ok (validp 'negated 5 :registry registry))
      (ok (not (validp 'negated '() :registry registry))))))

(defun circular-list (&rest items)
  "Return a fresh list of ITEMS whose last cons points back at the first."
  (let ((list (copy-list items)))
    (setf (cdr (last list)) list)
    list))

(defstruct (looping-node (:constructor make-looping-node ()))
  "A structure instance whose NEXT slot is set to the instance itself."
  (next nil))

(defun self-referencing-node ()
  "Return a LOOPING-NODE whose NEXT slot is the node itself."
  (let ((node (make-looping-node)))
    (setf (looping-node-next node) node)
    node))

(defun exploding-reader (object)
  "Signal an error whose report prints OBJECT."
  (error "cannot read ~S" object))

(defstruct (unprintable (:constructor make-unprintable ()))
  "A structure instance whose printer signals.")

(defmethod print-object ((object unprintable) stream)
  (declare (ignore stream))
  (error "printer broken"))

(deftest a-signalling-check-on-a-cyclic-value-terminates
  (let ((registry (make-hash-table-registry))
        (*print-circle* nil))
    (testing "a predicate signalling on a circular list answers NIL"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (validp (normalize-spec-form '(or integer (satisfies evenp)))
                           (circular-list 1 2 3) :registry registry)))))
    (testing "a tag reader signalling on a circular list answers NIL"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (validp (normalize-spec-form '(tagged-by 1+ (:a integer)))
                           (circular-list 1 2 3) :registry registry)))))
    (testing "an object reader signalling on a self-referencing instance answers NIL"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (validp (normalize-spec-form
                            '(object-of looping-node (:required (exploding-reader t))))
                           (self-referencing-node) :registry registry)))))
    (testing "EXPLAIN-DATA records a bounded report for the signalling predicate"
      (let* ((outcome (within-seconds (2)
                        (explain-data (normalize-spec-form '(satisfies evenp))
                                      (circular-list 1 2 3) :registry registry)))
             (datum (and (consp outcome) (first (getf (second outcome) :errors)))))
        (ok (eq :predicate-errored (getf datum :kind)))
        (ok (stringp (getf datum :condition-report)))))
    (testing "a value whose printer signals is still answered, not unwound"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (handler-case
                       (validp (normalize-spec-form '(satisfies plusp)) (make-unprintable)
                               :registry registry)
                     (error (condition) (type-of condition)))))))))

(deftest equal-keyed-alists-with-cyclic-keys-terminate
  (let ((registry (make-hash-table-registry)))
    (dolist (test '(equal equalp))
      (testing (format nil "two circular keys under :TEST ~(~A~) are refused, not compared forever"
                       test)
        (ok (equal '(:returned nil)
                   (within-seconds (2)
                     (validp (normalize-spec-form `(alist-of t integer :test ,test))
                             (list (cons (circular-list 1) 1) (cons (circular-list 1) 2))
                             :registry registry))))))
    (testing "the alist field spec with :TEST EQUAL terminates on circular keys too"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (validp (normalize-spec-form '(alist (:test equal) (:optional ("a" integer))))
                           (list (cons (circular-list 1) 1) (cons (circular-list 1) 2))
                           :registry registry)))))
    (testing "finite EQUAL keys are still compared by EQUAL"
      (ok (not (validp (normalize-spec-form '(alist-of t integer :test equal))
                       (list (cons (list 1 2) 1) (cons (list 1 2) 2))
                       :registry registry)))
      (ok (validp (normalize-spec-form '(alist-of t integer :test equal))
                  (list (cons (list 1 2) 1) (cons (list 1 3) 2))
                  :registry registry)))))
