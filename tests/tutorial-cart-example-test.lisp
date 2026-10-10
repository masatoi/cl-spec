;;;; tests/tutorial-cart-example-test.lisp
;;;;
;;;; Runs the executable example in examples/tutorial-cart.lisp.  The tests call
;;;; the example's own demo entry points rather than copying their logic, so a
;;;; change that breaks a result the tutorial shows fails the normal suite.
;;;; Values a seed draws are checked by shape, not by their exact contents.

(defpackage #:cl-spec/tests/tutorial-cart-example-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:list-specs)
  (:import-from #:cl-spec/examples/tutorial-cart
                #:make-example-registry #:register-example!
                #:demo-value-specs #:demo-structured-data
                #:cart-subtotal #:broken-cart-subtotal #:demo-property
                #:demo-find-bug #:demo-function-contract))

(in-package #:cl-spec/tests/tutorial-cart-example-test)

(defun first-error (errors)
  "Return the first structured error of an EXPLAIN-DATA :ERRORS list."
  (first errors))

(deftest tutorial-registration-leaves-the-user-registry-untouched
  (let ((*registry* (make-hash-table-registry))
        (example (make-example-registry)))
    (register-example! example)
    (testing "the example registers into the registry it is given"
      (ok (member 'cl-spec/examples/tutorial-cart::cart (list-specs example))))
    (testing "the caller's registry is neither read nor written"
      (ok (null (list-specs *registry*))))))

(deftest tutorial-chapter-1-value-specs
  (let ((summary (demo-value-specs)))
    (testing "a price inside the range is valid and zero is not"
      (ok (eq t (getf summary :valid-price)))
      (ok (null (getf summary :zero-price))))
    (testing "the explanation names the violated range"
      (let ((err (first-error (getf summary :zero-price-errors))))
        (ok (eq :out-of-range (getf err :kind)))
        (ok (null (getf err :path)))
        (ok (eql 0 (getf err :actual)))
        (ok (equal '(:range :min 1 :max 10000) (getf err :expected)))))
    (testing "sampling draws five valid prices"
      (ok (= 5 (length (getf summary :prices))))
      (ok (getf summary :prices-valid)))))

(deftest tutorial-chapter-2-structured-data
  (let ((summary (demo-structured-data)))
    (testing "a complete line item is valid"
      (ok (eq t (getf summary :item-valid))))
    (testing "a field error carries the field's path"
      (let ((err (first-error (getf summary :zero-qty-errors))))
        (ok (eq :out-of-range (getf err :kind)))
        (ok (equal '(:qty) (getf err :path)))))
    (testing "a missing required key and an unknown key are structural errors"
      (let ((missing (first-error (getf summary :missing-qty-errors)))
            (unknown (first-error (getf summary :unknown-key-errors))))
        (ok (eq :missing-key (getf missing :kind)))
        (ok (equal '(:qty) (getf missing :path)))
        (ok (eq :unknown-key (getf unknown :kind)))
        (ok (equal '(:memo) (getf unknown :path)))))
    (testing "sampled carts are valid carts"
      (ok (= 2 (length (getf summary :carts))))
      (ok (getf summary :carts-valid)))))

(defun additive-p (subtotal a b)
  "Return true when SUBTOTAL of A followed by B is the sum of their subtotals."
  (= (funcall subtotal (append a b))
     (+ (funcall subtotal a) (funcall subtotal b))))

(deftest tutorial-chapter-3-property
  (let ((summary (demo-property)))
    (testing "the additivity property passes over the default trial budget"
      (ok (eq :passed (getf summary :status)))
      (ok (= 100 (getf summary :trials))))
    (testing "the property is found from the function it is about"
      (ok (member 'cl-spec/examples/tutorial-cart::subtotal-is-additive
                  (getf summary :related))))))

(deftest tutorial-chapter-4-find-bug
  (let ((summary (demo-find-bug)))
    (testing "the broken subtotal violates additivity"
      (ok (eq :failed (getf summary :status)))
      (ok (eq :predicate-false (getf summary :failure-reason))))
    (testing "the shrunk counterexample is small and still a counterexample"
      (let ((a (getf summary :shrunk-a))
            (b (getf summary :shrunk-b)))
        (ok (eq :used (getf summary :shrunk-outcome)))
        (ok (<= (+ (length a) (length b)) 2))
        (ok (not (additive-p #'broken-cart-subtotal a b)))
        (ok (additive-p #'cart-subtotal a b))))
    (testing "replaying from the result reproduces the same failure"
      (ok (eq :failed (getf summary :replay-status)))
      (ok (eql 42 (getf summary :replay-seed)))
      (ok (getf summary :same-counterexample)))))

(deftest tutorial-chapter-5-function-contract
  (let ((summary (demo-function-contract)))
    (testing "the correct subtotal satisfies its contract"
      (ok (eq :passed (getf summary :status))))
    (testing "the broken subtotal breaks the postcondition on a one-item cart"
      (ok (eq :failed (getf summary :broken-status)))
      (ok (eq :postcondition (getf summary :broken-failure-reason)))
      (ok (= 1 (length (getf summary :broken-shrunk-cart)))))))
