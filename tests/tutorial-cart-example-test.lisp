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
                #:demo-value-specs #:demo-structured-data))

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
