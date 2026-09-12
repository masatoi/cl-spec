;;;; tests/registry-test.lisp

(defpackage #:cl-spec/tests/registry-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/registry
                #:hash-table-registry
                #:make-hash-table-registry
                #:registry-find-spec
                #:registry-register-spec
                #:registry-list-specs
                #:registry-find-function-spec
                #:registry-register-function-spec
                #:registry-list-function-specs
                #:registry-find-generator
                #:registry-register-generator
                #:registry-list-generators
                #:registry-find-property
                #:registry-register-property
                #:registry-list-properties
                #:registry-properties-for
                #:registry-properties-with-tag
                #:registry-clear
                #:*registry*
                #:find-spec
                #:list-specs
                #:register-spec
                #:find-property
                #:properties-for
                #:clear-registry))

(in-package #:cl-spec/tests/registry-test)

(deftest spec-round-trip
  (testing "a registered spec is found again, unregistered names are not"
    (let ((registry (make-hash-table-registry)))
      (ok (typep registry 'hash-table-registry))
      (registry-register-spec registry 'positive-money :spec-object)
      (multiple-value-bind (spec foundp) (registry-find-spec registry 'positive-money)
        (ok (eq :spec-object spec))
        (ok (eq t foundp)))
      (multiple-value-bind (spec foundp) (registry-find-spec registry 'nothing-here)
        (ok (null spec))
        (ok (null foundp))))))

(deftest registering-a-spec-returns-it
  (testing "REGISTRY-REGISTER-SPEC returns the spec so it can be used inline"
    (let ((registry (make-hash-table-registry)))
      (ok (eq :spec-object (registry-register-spec registry 'money :spec-object))))))

(deftest re-registering-a-spec-replaces-it
  (testing "the second definition wins and the name is listed once"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'money :first)
      (registry-register-spec registry 'money :second)
      (ok (eq :second (registry-find-spec registry 'money)))
      (ok (equal '(money) (registry-list-specs registry))))))

(deftest listing-specs-is-deterministic
  (testing "REGISTRY-LIST-SPECS sorts by symbol name so output is stable"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'zebra :z)
      (registry-register-spec registry 'apple :a)
      (registry-register-spec registry 'mango :m)
      (ok (equal '(apple mango zebra) (registry-list-specs registry))))))

(deftest function-specs-have-their-own-index
  (testing "function specs do not collide with value specs of the same name"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'transfer :value-spec)
      (registry-register-function-spec registry 'transfer :function-spec)
      (ok (eq :value-spec (registry-find-spec registry 'transfer)))
      (ok (eq :function-spec (registry-find-function-spec registry 'transfer)))
      (ok (equal '(transfer) (registry-list-function-specs registry))))))

(deftest found-p-distinguishes-a-nil-value-from-absence
  (testing "REGISTRY-FIND-SPEC reports found-p T for a name registered with value NIL"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'nil-valued-spec nil)
      (multiple-value-bind (spec foundp) (registry-find-spec registry 'nil-valued-spec)
        (ok (null spec))
        (ok (eq t foundp)))
      (multiple-value-bind (spec foundp) (registry-find-spec registry 'never-registered-spec)
        (ok (null spec))
        (ok (null foundp)))))
  (testing "REGISTRY-FIND-FUNCTION-SPEC reports found-p T for a name registered with value NIL"
    (let ((registry (make-hash-table-registry)))
      (registry-register-function-spec registry 'nil-valued-function-spec nil)
      (multiple-value-bind (function-spec foundp)
          (registry-find-function-spec registry 'nil-valued-function-spec)
        (ok (null function-spec))
        (ok (eq t foundp)))
      (multiple-value-bind (function-spec foundp)
          (registry-find-function-spec registry 'never-registered-function-spec)
        (ok (null function-spec))
        (ok (null foundp)))))
  (testing "REGISTRY-FIND-PROPERTY reports found-p T for a name registered with value NIL"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'nil-valued-property nil)
      (multiple-value-bind (property foundp)
          (registry-find-property registry 'nil-valued-property)
        (ok (null property))
        (ok (eq t foundp)))
      (multiple-value-bind (property foundp)
          (registry-find-property registry 'never-registered-property)
        (ok (null property))
        (ok (null foundp))))))

(deftest properties-are-indexed-by-target-and-tag
  (testing "a property is reachable by name, by target symbol and by tag"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'transfer-preserves-balance :property
                                  :targets '(transfer)
                                  :tags '(:money :invariant))
      (ok (eq :property (registry-find-property registry 'transfer-preserves-balance)))
      (ok (equal '(transfer-preserves-balance)
                 (registry-properties-for registry 'transfer)))
      (ok (equal '(transfer-preserves-balance)
                 (registry-properties-with-tag registry :money)))
      (ok (equal '(transfer-preserves-balance)
                 (registry-properties-with-tag registry :invariant)))
      (ok (null (registry-properties-for registry 'withdraw))))))

(deftest re-registering-a-property-drops-stale-index-entries
  (testing "changing targets and tags removes the old reverse index entries"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'balance-property :first
                                  :targets '(transfer) :tags '(:money))
      (registry-register-property registry 'balance-property :second
                                  :targets '(withdraw) :tags '(:audit))
      (ok (eq :second (registry-find-property registry 'balance-property)))
      (ok (null (registry-properties-for registry 'transfer)))
      (ok (null (registry-properties-with-tag registry :money)))
      (ok (equal '(balance-property) (registry-properties-for registry 'withdraw)))
      (ok (equal '(balance-property)
                 (registry-properties-with-tag registry :audit)))
      (ok (equal '(balance-property) (registry-list-properties registry))))))

(deftest several-properties-share-one-target
  (testing "the reverse index accumulates and stays sorted"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'zulu :p1 :targets '(transfer))
      (registry-register-property registry 'alpha :p2 :targets '(transfer))
      (ok (equal '(alpha zulu) (registry-properties-for registry 'transfer))))))

(deftest clearing-empties-every-index
  (testing "REGISTRY-CLEAR removes specs, function specs and properties"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'money :spec)
      (registry-register-function-spec registry 'transfer :function-spec)
      (registry-register-property registry 'invariant :property
                                  :targets '(transfer) :tags '(:money))
      (ok (eq registry (registry-clear registry)))
      (ok (null (registry-list-specs registry)))
      (ok (null (registry-list-function-specs registry)))
      (ok (null (registry-list-properties registry)))
      (ok (null (registry-properties-for registry 'transfer)))
      (ok (null (registry-properties-with-tag registry :money))))))

(deftest default-registry-front-end
  (testing "the front-end functions operate on *REGISTRY* and accept an override"
    (let ((*registry* (make-hash-table-registry)))
      (register-spec 'money :spec-object)
      (ok (eq :spec-object (find-spec 'money)))
      (ok (equal '(money) (list-specs)))
      (registry-register-property *registry* 'invariant :property
                                  :targets '(transfer))
      (ok (eq :property (find-property 'invariant)))
      (ok (equal '(invariant) (properties-for 'transfer)))
      (clear-registry)
      (ok (null (list-specs)))))
  (testing "an explicit registry argument overrides *REGISTRY*"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry)))
      (register-spec 'money :in-other other)
      (ok (null (find-spec 'money)))
      (ok (eq :in-other (find-spec 'money other))))))

(deftest default-registry-exists-at-load-time
  (testing "*REGISTRY* is bound to a usable registry without any setup"
    (ok (typep *registry* 'hash-table-registry))))

#+sbcl
(deftest concurrent-registration-keeps-the-reverse-index-complete
  (testing "every name registered from every thread is in the reverse index"
    ;; The measurement §73.4 #8 records: 8 threads registering 3000 properties
    ;; left PROPERTIES-FOR answering with 1146 of them.  INDEX-PROPERTY pushes
    ;; onto a list it has just read, so a lost update leaves the names table
    ;; whole and only the reverse index short -- and nothing said so.
    (let ((registry (make-hash-table-registry))
          (threads 8)
          (per-thread 500))
      ;; The names are interned here, on one thread.  Interning from eight
      ;; threads at once is a second race, and this test is about the registry's:
      ;; with one binding shared by every closure, all eight workers registered
      ;; the same names.
      (let ((work (loop for thread below threads
                        collect (loop for index below per-thread
                                      collect (intern (format nil "CONCURRENT-~D-~D"
                                                              thread index))))))
        (let ((gate (sb-thread:make-semaphore :count 0)))
          (let ((workers (mapcar (lambda (names)
                                   (sb-thread:make-thread
                                    (lambda ()
                                      (sb-thread:wait-on-semaphore gate)
                                      (dolist (name names)
                                        (registry-register-property
                                         registry name :property-object
                                         :targets (list 'shared-target)
                                         :tags (list :shared-tag))))))
                                 work)))
            ;; Release every worker at once.  The lost update needs two threads
            ;; inside PUSHNEW together, and eight threads started one after
            ;; another never are: measured here, 4000 registrations lost 2789 of
            ;; them with a gate and none without one.
            (loop repeat threads do (sb-thread:signal-semaphore gate))
            (mapc #'sb-thread:join-thread workers))))
      (let ((expected (* threads per-thread)))
        (testing "the names table holds them all, so the threads did register"
          (ok (= expected (length (registry-list-properties registry)))))
        (testing "so the reverse index must hold them all too"
          (ok (= expected (length (registry-properties-for registry 'shared-target)))))
        (testing "and so must the tag index"
          (ok (= expected
                 (length (registry-properties-with-tag registry :shared-tag)))))))))

(deftest generator-round-trip
  (testing "a registered generator is found again, unregistered names are not"
    (let ((registry (make-hash-table-registry)))
      (registry-register-generator registry 'even-only :generator-object)
      (multiple-value-bind (generator foundp)
          (registry-find-generator registry 'even-only)
        (ok (eq :generator-object generator))
        (ok (eq t foundp)))
      (multiple-value-bind (generator foundp)
          (registry-find-generator registry 'nothing-here)
        (ok (null generator))
        (ok (null foundp)))
      (ok (equal '(even-only) (registry-list-generators registry)))
      (testing "and REGISTRY-CLEAR drops it with the other entity kinds"
        (registry-clear registry)
        (ok (null (registry-list-generators registry)))))))
