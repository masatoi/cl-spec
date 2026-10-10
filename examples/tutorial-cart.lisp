;;;; examples/tutorial-cart.lisp
;;;;
;;;; Executable example for the Japanese introductory tutorial in
;;;; docs/tutorial.ja.md: a shopping cart grown one chapter at a time.
;;;;
;;;; Loading this file defines a condition and some pure functions only.  It does
;;;; not register a spec, draw a value or run a demo, so it never changes the
;;;; caller's *REGISTRY*.  Call REGISTER-EXAMPLE! to register the tutorial's
;;;; specs, properties and contracts in a dedicated registry, and the DEMO-*
;;;; entry points to reproduce what each chapter shows.

(defpackage #:cl-spec/examples/tutorial-cart
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry*
                #:make-hash-table-registry
                #:defspec
                #:validp #:explain-data #:sample)
  ;; This example is an ASDF package-inferred subsystem, so this bare
  ;; :IMPORT-FROM declares its check-it generator backend dependency without
  ;; importing a symbol.  See examples/structured-data.lisp for the same note.
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:make-example-registry #:register-example!
           #:demo-value-specs #:demo-structured-data))

(in-package #:cl-spec/examples/tutorial-cart)

(defun make-example-registry ()
  "Return a fresh registry for this example.  Nothing is registered yet."
  (make-hash-table-registry))

(defun register-example! (&optional (registry (make-example-registry)))
  "Register the tutorial's specs, properties and contracts in REGISTRY and return it.

Each form is the one the tutorial has the reader type at the REPL.  The caller's
*REGISTRY* is neither read nor written."
  (let ((*registry* registry))
    ;; Chapter 1: value specs.
    (defspec price (range integer 1 10000))
    (defspec quantity (range integer 1 99))
    ;; Chapter 2: structured data.
    (defspec line-item
      (plist (:required (:sku string) (:price price) (:qty quantity))
             (:closed t)))
    (defspec cart (list-of line-item :max-length 5))
    registry))

(defun demo-value-specs (&optional (registry (register-example!)))
  "Chapter 1: validate, explain and sample the PRICE spec.

Returns :VALID-PRICE and :ZERO-PRICE from VALIDP, :ZERO-PRICE-ERRORS from
EXPLAIN-DATA, and :PRICES, five prices drawn with seed 42, with :PRICES-VALID."
  (let ((prices (sample 'price :count 5 :seed 42 :registry registry)))
    (list :valid-price (validp 'price 500 :registry registry)
          :zero-price (validp 'price 0 :registry registry)
          :zero-price-errors (getf (explain-data 'price 0 :registry registry) :errors)
          :prices prices
          :prices-valid (every (lambda (price) (validp 'price price :registry registry))
                               prices))))

(defun demo-structured-data (&optional (registry (register-example!)))
  "Chapter 2: validate line items and draw carts.

Returns :ITEM-VALID for a complete line item, the EXPLAIN-DATA errors of a zero
quantity, a missing quantity and an unknown :MEMO key, and :CARTS, two carts drawn
with seed 42, with :CARTS-VALID."
  (flet ((errors (value)
           (getf (explain-data 'line-item value :registry registry) :errors)))
    (let ((carts (sample 'cart :count 2 :seed 42 :registry registry)))
      (list :item-valid (validp 'line-item '(:sku "A-1" :price 100 :qty 2)
                                :registry registry)
            :zero-qty-errors (errors '(:sku "A-1" :price 100 :qty 0))
            :missing-qty-errors (errors '(:sku "A-1" :price 100))
            :unknown-key-errors (errors '(:sku "A-1" :price 100 :qty 2 :memo "gift"))
            :carts carts
            :carts-valid (every (lambda (cart) (validp 'cart cart :registry registry))
                                carts)))))
