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
                #:validp #:explain-data #:sample
                #:defproperty #:defspec-function
                #:run-property #:check-function #:properties-for
                #:property-result-status #:property-result-failure-reason
                #:property-result-trials #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-shrunk-outcome #:property-result-seed)
  ;; This example is an ASDF package-inferred subsystem, so this bare
  ;; :IMPORT-FROM declares its check-it generator backend dependency without
  ;; importing a symbol.  See examples/structured-data.lisp for the same note.
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:make-example-registry #:register-example!
           #:demo-value-specs #:demo-structured-data
           #:cart-subtotal #:broken-cart-subtotal #:demo-property #:demo-find-bug
           #:demo-function-contract))

(in-package #:cl-spec/examples/tutorial-cart)

(defun cart-subtotal (cart)
  "Return the sum of price times quantity over CART's line items.  Pure."
  (loop for item in cart
        sum (* (getf item :price) (getf item :qty))))

(defun broken-cart-subtotal (cart)
  "A deliberately wrong subtotal: it skips the first line item."
  (loop for item in (rest cart)
        sum (* (getf item :price) (getf item :qty))))

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
    ;; Chapter 3: a property.
    (defproperty subtotal-is-additive ((a cart) (b cart))
      (:about cart-subtotal)
      (= (cart-subtotal (append a b))
         (+ (cart-subtotal a) (cart-subtotal b))))
    ;; Chapter 4: the same property about a deliberately wrong implementation.
    (defproperty broken-subtotal-is-additive ((a cart) (b cart))
      (:about broken-cart-subtotal)
      (= (broken-cart-subtotal (append a b))
         (+ (broken-cart-subtotal a) (broken-cart-subtotal b))))
    ;; Chapter 5: function contracts.
    (defspec-function cart-subtotal
      (:args (cart cart))
      (:returns (range integer 0 *))
      (:post (>= result (length cart))))
    (defspec-function broken-cart-subtotal
      (:args (cart cart))
      (:returns (range integer 0 *))
      (:post (>= result (length cart))))
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

(defun demo-property (&optional (registry (register-example!)))
  "Chapter 3: run the additivity property with seed 42.

Returns its :STATUS, the number of :TRIALS run, and the properties :RELATED to
CART-SUBTOTAL through :ABOUT."
  (let ((result (run-property 'subtotal-is-additive :seed 42 :registry registry)))
    (list :status (property-result-status result)
          :trials (property-result-trials result)
          :related (properties-for 'cart-subtotal registry))))

(defun demo-find-bug (&optional (registry (register-example!)))
  "Chapter 4: let the property find the bug, shrink it, and replay it.

The replay passes the first result as :SEED, so it reuses the recorded seed,
profile and options.  The shrunk arguments are returned as :SHRUNK-A and
:SHRUNK-B; no particular minimum is promised."
  (let* ((original (run-property 'broken-subtotal-is-additive :seed 42
                                 :registry registry))
         (replay (run-property 'broken-subtotal-is-additive :seed original
                               :registry registry))
         (shrunk (property-result-shrunk-counterexample original)))
    (list :status (property-result-status original)
          :failure-reason (property-result-failure-reason original)
          :trials (property-result-trials original)
          :counterexample (property-result-counterexample original)
          :shrunk-a (getf shrunk 'a)
          :shrunk-b (getf shrunk 'b)
          :shrunk-outcome (property-result-shrunk-outcome original)
          :replay-status (property-result-status replay)
          :replay-seed (property-result-seed replay)
          :same-counterexample (equal (property-result-counterexample original)
                                      (property-result-counterexample replay)))))

(defun demo-function-contract (&optional (registry (register-example!)))
  "Chapter 5: check the subtotal contracts with seed 42.

Returns the correct contract's :STATUS, and the broken one's :BROKEN-STATUS,
:BROKEN-FAILURE-REASON and shrunk :BROKEN-SHRUNK-CART."
  (let ((good (check-function 'cart-subtotal :seed 42 :registry registry))
        (bad (check-function 'broken-cart-subtotal :seed 42 :registry registry)))
    (list :status (property-result-status good)
          :broken-status (property-result-status bad)
          :broken-failure-reason (property-result-failure-reason bad)
          :broken-shrunk-cart (getf (property-result-shrunk-counterexample bad) 'cart))))
