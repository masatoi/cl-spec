# cl-spec introductory tutorial

日本語版: [tutorial.ja.md](tutorial.ja.md)

This tutorial is a single-path introduction for people who can write Common Lisp
but are new to both cl-spec and property-based testing (PBT). If you read it from
top to bottom, typing the expressions into a REPL as you go, one pass takes about
an hour.

The subject is pricing a shopping cart. We start with specs for small values, the
price and quantity of an item, and grow the same cart a little in each chapter:
the structure of line items and carts, a property of the subtotal, a function
contract, a promise about errors, and promises that depend on conditions. Along
the way we also write deliberately broken implementations and watch how cl-spec
finds and reports their bugs.

The code shown here has the same definitions as the executable example
[`examples/tutorial-cart.lisp`](../examples/tutorial-cart.lisp). The deterministic
results its `demo-*` functions return (statuses, failure reasons, the contents of
errors and so on) are checked by the normal test suite
(`tests/tutorial-cart-example-test.lisp`), so a change to them fails
`rove cl-spec.asd`. Generated values and the concrete contents of counterexamples
are checked only by their shape. Note that nothing mechanically checks that the
code in this text matches the definitions in the example.

## 0. Introduction

### What cl-spec is

cl-spec is a library for writing "promises" about values and functions as
executable data. A promise you write once can be reused as is: to validate values,
to explain violations as structured data, to generate values that satisfy it, and
to check properties and function contracts. Promises are registered as data in a
registry, so programs (including LLM agents) can read them as well as people.

### What property-based testing is

An ordinary unit test states a concrete example, such as "for inputs `2` and `3`
the result is `5`". In property-based testing you state, instead of examples, a
property that should hold for any input. The testing tool tries that property many
times on random inputs, looking for an input that breaks it (a counterexample).
When it finds one, it makes the input smaller and simpler for as long as the
property stays broken. This is called shrinking. A large random input makes the
cause hard to see, so a shrunk counterexample is the better clue.

### Prerequisites and loading

- SBCL
- cl-spec visible to ASDF (for example, placed in Quicklisp's `local-projects`)
- check-it (available from Quicklisp)

Evaluate the following in the REPL.

```lisp
(asdf:load-system :cl-spec/check-it)
```

`cl-spec` itself does not depend on check-it. The generator backend that value
generation and property execution need is installed when you load
`cl-spec/check-it`.

The code that follows assumes you type it in the `cl-user` package. cl-spec's
operators get a `cl-spec:` prefix, but operators written inside a spec, such as
`range` and `plist`, do not. The specs and properties you define are registered in
the default registry (`cl-spec:*registry*`).

### Running the file version

The same definitions are also provided as a file. Load it and call a demo to
check the results of each chapter in one go.

```lisp
(asdf:load-system "cl-spec/examples/tutorial-cart")
(cl-spec/examples/tutorial-cart:demo-find-bug)
```

The file version registers into its own registry, so it does not mix with the
definitions you type in the REPL. You can run it after following the text in the
REPL, or before.

> **Chapter summary**: cl-spec is a library for writing promises as executable
> data, and PBT is a technique that tries properties on random inputs, looks for
> counterexamples and shrinks them. Loading `cl-spec/check-it` is all the setup you
> need.

## 1. Writing value specs

First, write specs for the price and the quantity. A price is an integer from 1 to
10000 yen, and a quantity is an integer from 1 to 99.

```lisp
(cl-spec:defspec price (range integer 1 10000))
(cl-spec:defspec quantity (range integer 1 99))
```

`defspec` registers a pair of a name and a spec in the registry.
`(range integer 1 10000)` is the spec "an integer from 1 to 10000 inclusive".

Use `validp` to find out whether a value satisfies a spec.

```lisp
(cl-spec:validp 'price 500)
;; => T
(cl-spec:validp 'price 0)
;; => NIL
```

`validp` returns only true or false. When you want to know why a value does not
satisfy a spec, use `explain-data`.

```lisp
(cl-spec:explain-data 'price 0)
;; => (:VALID NIL :SPEC PRICE :VALUE 0 :PATH NIL :ERRORS
;;     ((:KIND :OUT-OF-RANGE :PATH NIL :ACTUAL 0 :EXPECTED (:RANGE :MIN 1 :MAX 10000)
;;       :VIOLATED-BOUND :MINIMUM)))
```

The result is a plist, not a message string. `:errors` lists the violations, one
plist each, whose keys mean the following.

| Key | Meaning |
|---|---|
| `:kind` | The kind of violation; here, out of range (`:out-of-range`) |
| `:path` | Where in the value the violation is. `NIL` means the value itself. This starts to matter with structured data in the next chapter |
| `:actual` | The actual value |
| `:expected` | What was expected; here, the range 1 to 10000 |

This example also carries `:violated-bound :minimum` (the lower bound was
broken). Because the result comes back as data, a program can branch on the kind
or location of a violation.

A spec is not only for checking values; it can also generate them.

```lisp
(cl-spec:sample 'price :count 5 :seed 42)
;; => (7271 861 5391 5192 5735)   ; for example
```

`sample` makes `:count` values that satisfy the spec. With `:seed`, the same seed
gives the same values. The values themselves, however, may differ with the
generator backend's implementation and the environment, so read the values above
as one example. Whatever they are, every one of them satisfies `price`.

`sample` also returns a generation report (a plist of attempt counts, rejection
counts and so on) as its second value, so the REPL prints that plist too. It is
omitted above, and you can ignore it for now.

> **Chapter summary**: `defspec` registers a named promise about values; `validp`
> checks a value, `explain-data` reads a violation as structured data, and `sample`
> makes values that satisfy the promise.

## 2. Structured data

Next, write specs for a cart's line items and for the cart itself. A line item is a
plist such as `(:sku "A-1" :price 100 :qty 2)`.

```lisp
(cl-spec:defspec line-item
  (plist (:required (:sku string) (:price price) (:qty quantity))
         (:closed t)))
(cl-spec:defspec cart (list-of line-item :max-length 5))
```

- `plist` assigns a spec to each key of a plist. The keys listed under `:required`
  must be present.
- The `string` in `(:sku string)` is a CL type. The `price` in `(:price price)` is
  the spec name registered in the previous chapter. Inside a spec, a symbol you
  defined yourself is treated as a registered spec name.
- `(:closed t)` means "allow no keys other than the ones listed here".
- `list-of` is a list whose elements all satisfy `line-item`. `:max-length 5` caps
  its length at 5. With a cap, generated carts do not grow too large, and checking
  and shrinking run faster.

A correct line item passes.

```lisp
(cl-spec:validp 'line-item '(:sku "A-1" :price 100 :qty 2))
;; => T
```

Let us look at three kinds of violation. First, a line item whose quantity is 0.

```lisp
(cl-spec:explain-data 'line-item '(:sku "A-1" :price 100 :qty 0))
;; => (:VALID NIL :SPEC LINE-ITEM :VALUE (:SKU "A-1" :PRICE 100 :QTY 0) :PATH NIL
;;     :ERRORS
;;     ((:FIELD-PATH (:QTY) :KIND :OUT-OF-RANGE :PATH (:QTY) :ACTUAL 0 :EXPECTED
;;       (:RANGE :MIN 1 :MAX 99) :VIOLATED-BOUND :MINIMUM)))
```

`:path (:qty)` points at the line item's `:qty` field as the violation. `:kind`
and `:expected` read as in the previous chapter: the value is outside
`quantity`'s range of 1 to 99.

Next, a line item missing `:qty`.

```lisp
(cl-spec:explain-data 'line-item '(:sku "A-1" :price 100))
;; => (:VALID NIL :SPEC LINE-ITEM :VALUE (:SKU "A-1" :PRICE 100) :PATH NIL :ERRORS
;;     ((:FIELD-PATH (:QTY) :KIND :MISSING-KEY :PATH (:QTY) :ACTUAL NIL :EXPECTED
;;       (:SPEC QUANTITY))))
```

This time it is `:kind :missing-key`. `:path (:qty)` again points at `:qty`, and
`:expected` shows that a value satisfying `quantity` was needed there.

Last, a line item with an extra `:memo` key that the spec does not list.

```lisp
(cl-spec:explain-data 'line-item '(:sku "A-1" :price 100 :qty 2 :memo "gift"))
;; => (:VALID NIL :SPEC LINE-ITEM :VALUE (:SKU "A-1" :PRICE 100 :QTY 2 :MEMO "gift")
;;     :PATH NIL :ERRORS
;;     ((:KIND :UNKNOWN-KEY :PATH (:MEMO) :ACTUAL "gift" :EXPECTED
;;       (:KIND :PLIST :CLOSED T :FIELDS
;;        ((:KEY :SKU :REQUIRED T :EXPECTED (:TYPE STRING))
;;         (:KEY :PRICE :REQUIRED T :EXPECTED (:SPEC PRICE))
;;         (:KEY :QTY :REQUIRED T :EXPECTED (:SPEC QUANTITY)))))))
```

Because the spec has `(:closed t)`, `:memo` is reported as `:kind :unknown-key`.
`:path (:memo)` points at the extra key, and `:expected` holds the list of allowed
fields.

In all three, `:path` tells you at a glance which field is at fault. Even in deeply
nested data, `:path` shows the way from the top of the value. The `:field-path`
on the first two is the sequence of keys through the fields the spec declares. The
violation for the undeclared `:memo` does not carry one; it has only `:path`. Also,
the `:actual NIL` of a missing key means "there was no value", not "the value was
NIL"; `:kind` tells the two apart.

Carts can be generated too.

```lisp
(cl-spec:sample 'cart :count 2 :seed 42)
;; => (((:SKU "4skdcB5UzLJP2t" :PRICE 1529 :QTY 3) (:SKU "u11z" :PRICE 2613 :QTY 2)
;;      (:SKU "6hNrb5VRBdpN84rXmoy" :PRICE 8007 :QTY 9))
;;     NIL)   ; for example (the generation report, the second return value, is omitted)
```

Every generated cart has at most 5 line items, and each line item satisfies
`line-item`. Because `list-of` has no lower bound, an empty list also satisfies
`cart`, and as in the example above, an empty cart (`NIL`) can come out. As in
the previous chapter, the concrete values may differ by environment.

> **Chapter summary**: `plist` and `list-of` describe structured data. A violation
> is reported through `:kind` and `:path` as what went wrong and where, and
> generated values satisfy the spec.

## 3. Writing properties

Write a function that computes a cart's subtotal.

```lisp
(defun cart-subtotal (cart)
  "Return the sum of price times quantity over CART's line items.  Pure."
  (loop for item in cart
        sum (* (getf item :price) (getf item :qty))))
```

Think of one property this function should satisfy. The subtotal of two carts
joined together should equal the sum of their subtotals. Write the property down as
it stands, without fixing any particular carts.

```lisp
(cl-spec:defproperty subtotal-is-additive ((a cart) (b cart))
  (:about cart-subtotal)
  (= (cart-subtotal (append a b))
     (+ (cart-subtotal a) (cart-subtotal b))))
```

- `((a cart) (b cart))` means "bind `a` and `b` to values generated from the
  `cart` spec". Each trial makes two new carts.
- `(:about cart-subtotal)` records which function this property is about. Later
  you can look up the related properties from the function's side.
- The last form is the body of the property. True means it holds; false means it
  is violated.

Run it.

```lisp
(defparameter *additive* (cl-spec:run-property 'subtotal-is-additive :seed 42))
(cl-spec:property-result-status *additive*)
;; => :PASSED
(cl-spec:property-result-trials *additive*)
;; => 100
```

In 100 trials, no input that breaks the property was found. Because `:seed` is
fixed, evaluating the same forms in the same environment reruns the same sequence
of inputs.

The relation recorded with `:about` can be looked up by function name.

```lisp
(cl-spec:properties-for 'cart-subtotal)
;; => (SUBTOTAL-IS-ADDITIVE)
```

One caution here. `:passed` means "no violation was observed in the 100 trials
that ran"; it is not a proof that the property always holds. Depending on the
number of trials and the bias of the generated values, a run can end without
drawing a violating input (chapter 8 shows a real example).

> **Chapter summary**: `defproperty` states a property that should hold for any
> input, and `run-property` tries it on random inputs. `:passed` is a result over
> what was observed, not a proof.

## 4. Finding a bug

Now prepare a deliberately broken implementation: a subtotal that skips the first
line item.

```lisp
(defun broken-cart-subtotal (cart)
  "A deliberately wrong subtotal: it skips the first line item."
  (loop for item in (rest cart)
        sum (* (getf item :price) (getf item :qty))))
```

Write the same property as in the previous chapter, this time about this function.

```lisp
(cl-spec:defproperty broken-subtotal-is-additive ((a cart) (b cart))
  (:about broken-cart-subtotal)
  (= (broken-cart-subtotal (append a b))
     (+ (broken-cart-subtotal a) (broken-cart-subtotal b))))
```

Run it.

```lisp
(defparameter *broken* (cl-spec:run-property 'broken-subtotal-is-additive :seed 42))
(cl-spec:property-result-status *broken*)
;; => :FAILED
(cl-spec:property-result-failure-reason *broken*)
;; => :PREDICATE-FALSE
```

`:predicate-false` means the body of the property returned false. The input that
broke it is recorded as a counterexample. First, the counterexample as it was
found.

```lisp
(cl-spec:property-result-counterexample *broken*)
;; => (A
;;     ((:SKU "K70jiib" :PRICE 3105 :QTY 48) (:SKU "7C42" :PRICE 3841 :QTY 5)
;;      (:SKU "89M63woD6VjYl" :PRICE 3628 :QTY 84))
;;     B
;;     ((:SKU "Wga8IFI0l5" :PRICE 1496 :QTY 52) (:SKU "Z60xQ5AbZ675t5PI" :PRICE 9340 :QTY 59)
;;      (:SKU "2dCTt" :PRICE 8681 :QTY 33) (:SKU "rky9PYQ" :PRICE 2050 :QTY 1)
;;      (:SKU "4wc2vXqf2yrr2i3" :PRICE 6945 :QTY 14)))   ; for example
```

The counterexample is a plist of the property's variable names and their values.
With carts this size, following what went wrong by eye is hard work. So look at
the shrunk counterexample instead.

```lisp
(cl-spec:property-result-shrunk-counterexample *broken*)
;; => (A ((:SKU "89M63woD6VjYl" :PRICE 1 :QTY 1))
;;     B ((:SKU "4wc2vXqf2yrr2i3" :PRICE 1 :QTY 1)))   ; for example
```

Both `a` and `b` are down to one line item, with price and quantity down to 1.
Working the property out by hand on this input:

- The joined cart has two line items, so `broken-cart-subtotal` skips the first
  and returns 1.
- `a` and `b` each have one line item, so each skips it and returns 0; their sum
  is 0.

1 and 0 do not match. A one-item cart whose subtotal is 0 is plainly wrong, which
tells you that the first line item is being ignored.

The concrete values of the counterexample may differ by environment, but the
purpose of shrinking is the same. Note also that shrinking is a procedure that
looks for smaller inputs that still break the property; it does not promise that
the counterexample it returns is minimal.

To reproduce a failure, pass the result object itself as `:seed`.

```lisp
(defparameter *replay* (cl-spec:run-property 'broken-subtotal-is-additive :seed *broken*))
(cl-spec:property-result-status *replay*)
;; => :FAILED
(cl-spec:property-result-seed *replay*)
;; => 42
(equal (cl-spec:property-result-counterexample *broken*)
       (cl-spec:property-result-counterexample *replay*))
;; => T
```

Passing a result object reruns with its recorded seed, profile and options, so
the same counterexample comes out. This is handy for confirming, after a fix, that
the same input now passes.

> **Chapter summary**: When a property breaks, the counterexample and the shrunk
> counterexample are reported. Read the cause from the shrunk counterexample, and
> pass the result object as `:seed` to reproduce the same failure.

## 5. Writing a function contract

A property can state its property as any expression, but a promise of the form
"this function takes these arguments and returns this kind of value" is more
naturally written as a function contract. Write the contract for `cart-subtotal`.

```lisp
(cl-spec:defspec-function cart-subtotal
  (:args (cart cart))
  (:returns (range integer 0 *))
  (:post (>= result (length cart))))
```

- `:args` pairs each argument name with a spec. Here the argument `cart` satisfies
  the `cart` spec. During checking, arguments are generated from this spec.
- `:returns` is the spec of the return value. `(range integer 0 *)` is an integer
  of 0 or more (no upper bound).
- `:post` is the postcondition. `result` refers to the return value, and argument
  names (here `cart`) can be used too. Price and quantity are both at least 1, so
  each line item contributes at least 1 to the subtotal. The subtotal should
  therefore be at least the number of line items, which is what
  `(>= result (length cart))` says.

Check it.

```lisp
(defparameter *subtotal-check* (cl-spec:check-function 'cart-subtotal :seed 42))
(cl-spec:property-result-status *subtotal-check*)
;; => :PASSED
```

Write the same contract for the broken implementation and check it.

```lisp
(cl-spec:defspec-function broken-cart-subtotal
  (:args (cart cart))
  (:returns (range integer 0 *))
  (:post (>= result (length cart))))

(defparameter *broken-subtotal-check*
  (cl-spec:check-function 'broken-cart-subtotal :seed 42))
(cl-spec:property-result-status *broken-subtotal-check*)
;; => :FAILED
(cl-spec:property-result-failure-reason *broken-subtotal-check*)
;; => :POSTCONDITION
(cl-spec:property-result-shrunk-counterexample *broken-subtotal-check*)
;; => (CART ((:SKU "Qs6Z64Zb5" :PRICE 1 :QTY 1)))   ; for example
```

`:postcondition` says the postcondition was broken. The shrunk counterexample is a
one-item cart: the correct subtotal is 1, but `broken-cart-subtotal` returns 0, so
`(>= 0 1)` is false. As with properties, you read a function contract's
counterexamples, shrinking and replay in the same way.

Use properties and function contracts for different things:

- Function contract: a promise about the inputs and output of one function on its
  own. The argument specs, the return value spec, and the relation between
  arguments and return value.
- Property: a law that spans several calls or several functions. The property in
  chapter 3 calls `cart-subtotal` three times and compares the results, so it
  cannot be written as a contract on a single call.

> **Chapter summary**: `defspec-function` writes the arguments, return value and
> postcondition as a contract, and `check-function` checks it. A promise about one
> function on its own is a contract; a law across calls is a property.

## 6. Promising an error

Signalling a specific error for invalid input is also part of a function's
promise. Write a line item constructor that signals `invalid-quantity` when the
quantity is below 1.

```lisp
(define-condition invalid-quantity (error)
  ((qty :initarg :qty :reader invalid-quantity-qty))
  (:report (lambda (condition stream)
             (format stream "Quantity ~D is less than 1."
                     (invalid-quantity-qty condition))))
  (:documentation "Signalled by MAKE-LINE-ITEM for a quantity below 1."))

(defun make-line-item (sku price qty)
  "Return a line item plist, or signal INVALID-QUANTITY when QTY is below 1."
  (when (< qty 1)
    (error 'invalid-quantity :qty qty))
  (list :sku sku :price price :qty qty))
```

Write this error promise as a contract.

```lisp
(cl-spec:defspec-function make-line-item
  (:args (sku string) (price price) (qty (range integer -10 0)))
  (:signals (type invalid-quantity)))
```

- `:signals` is the promise "this function must end by signalling an error that
  satisfies this spec". Returning a value normally is a violation.
- The `qty` spec is `(range integer -10 0)` because this contract is a promise
  about invalid quantities. Every generated quantity is below 1, so every trial
  expects the error. The next chapter's `:cases` shows how to put the normal and
  the error behaviour in one contract.
- The `type` in `(type invalid-quantity)` matters. Inside a spec, a bare symbol
  you defined yourself (one that is not a CL type name) is read as a registered
  spec name. So writing `(:signals invalid-quantity)` looks for a spec named
  `invalid-quantity`, does not find one, and fails as a contract-side error. Wrap
  your own condition classes in `type`, as in `(type invalid-quantity)`.

Check it.

```lisp
(defparameter *item-check* (cl-spec:check-function 'make-line-item :seed 42))
(cl-spec:property-result-status *item-check*)
;; => :PASSED
```

For comparison, prepare an implementation that silently corrects an invalid
quantity to 1.

```lisp
(defun broken-make-line-item (sku price qty)
  "A deliberately wrong constructor: it silently raises a bad quantity to 1."
  (list :sku sku :price price :qty (max qty 1)))

(cl-spec:defspec-function broken-make-line-item
  (:args (sku string) (price price) (qty (range integer -10 0)))
  (:signals (type invalid-quantity)))

(defparameter *broken-item-check* (cl-spec:check-function 'broken-make-line-item :seed 42))
(cl-spec:property-result-status *broken-item-check*)
;; => :FAILED
(cl-spec:property-result-failure-reason *broken-item-check*)
;; => :MISSING-CONDITION
```

`:missing-condition` says that an error was expected but the function returned a
value normally. The counterexample can be read with
`property-result-shrunk-counterexample` as before (for example
`(SKU "O4skdc" PRICE 1 QTY 0)`: passing a quantity of 0 returned a line item
instead of an error).

> **Chapter summary**: `:signals` states the promise "end by signalling this
> error". Refer to a condition you defined yourself with `(type ...)`; returning
> normally fails with `:missing-condition`.

## 7. Splitting promises by condition

Write a function that discounts by subtotal. Below 5000 there is no discount; at
5000 or more it takes 10% off, rounding the discount amount down.

```lisp
(defun discounted-total (subtotal)
  "Return SUBTOTAL, less 10% rounded down when SUBTOTAL is 5000 or more."
  (if (< subtotal 5000)
      subtotal
      (- subtotal (floor subtotal 10))))
```

This function's promise changes with the range of its input. So use `:cases` to
write a named promise for each condition.

```lisp
(cl-spec:defspec-function discounted-total
  (:args (subtotal (range integer 0 20000)))
  (:cases
    (:no-discount
      (:when (< subtotal 5000))
      (:returns (range integer 0 *))
      (:post (= result subtotal)))
    (:ten-percent-off
      (:when (>= subtotal 5000))
      (:returns (range integer 0 *))
      (:post (and (< result subtotal)
                  (<= (* 9 subtotal) (* 10 result)))))))
```

- Each case has a name (`:no-discount`, `:ten-percent-off`), one condition
  `:when`, and one outcome promise, `:returns` or `:signals`. A `:returns` case can
  also have a `:post`.
- Case selection is exclusive. For each input every `:when` is evaluated, and
  exactly one must be true. When none is true or several are, it is reported as a
  contract-side error, not a fault in the function, and the function is not
  called.
- The `:post` of `:ten-percent-off` does not copy the implementation's expression
  (`(- subtotal (floor subtotal 10))`). It states a property instead: after the
  discount the total is less than the original and at least 90% of it. Copying the
  implementation risks writing the implementation's mistake into the contract as
  well.

Check it.

```lisp
(defparameter *discount-check* (cl-spec:check-function 'discounted-total :seed 42))
(cl-spec:property-result-status *discount-check*)
;; => :PASSED
```

The result of a contract with `:cases` carries a per-case tally.

```lisp
(getf (cl-spec:function-check-result-case-report *discount-check*) :cases)
;; => ((:NAME :NO-DISCOUNT :DOCUMENTATION NIL :CALLED 27 :PASSED 27 :FAILED 0 :ERROR 0)
;;     (:NAME :TEN-PERCENT-OFF :DOCUMENTATION NIL :CALLED 73 :PASSED 73 :FAILED 0 :ERROR 0))
(getf (cl-spec:function-check-result-case-report *discount-check*) :never-called)
;; => NIL
```

`:called` is the number of times the case was selected and the function called.
Each case's count depends on the generated values, so it comes out as, for
example, 27 and 73 as above (the total is the 100 trials). `:never-called` lists
the cases that were never called; here it is empty.

What happens with a single trial?

```lisp
(defparameter *one-trial-check*
  (cl-spec:check-function 'discounted-total :trials 1 :seed 42))
(cl-spec:property-result-status *one-trial-check*)
;; => :PASSED
(getf (cl-spec:function-check-result-case-report *one-trial-check*) :never-called)
;; => (:NO-DISCOUNT)   ; for example
```

With only one try, only one of the cases was called (which one is left over
depends on the drawn value). The result is still `:passed`. `:passed` means "no
violation in the cases that were called"; it does not mean every case was tried.
When you use `:cases`, make a habit of reading `:never-called` along with the
status.

> **Chapter summary**: `:cases` writes a named promise for each condition.
> Selection is exclusive, and the result carries a per-case tally. Even with
> `:passed`, `:never-called` is not necessarily empty.

## 8. Checking just once

Prepare an implementation that gets the discount boundary wrong. `<` became `<=`,
so a subtotal of exactly 5000 gets no discount.

```lisp
(defun broken-discounted-total (subtotal)
  "A deliberately wrong total: it starts the discount above 5000, not at it."
  (if (<= subtotal 5000)
      subtotal
      (- subtotal (floor subtotal 10))))

(cl-spec:defspec-function broken-discounted-total
  (:args (subtotal (range integer 0 20000)))
  (:cases
    (:no-discount
      (:when (< subtotal 5000))
      (:returns (range integer 0 *))
      (:post (= result subtotal)))
    (:ten-percent-off
      (:when (>= subtotal 5000))
      (:returns (range integer 0 *))
      (:post (and (< result subtotal)
                  (<= (* 9 subtotal) (* 10 result)))))))
```

Check it at random.

```lisp
(cl-spec:property-result-status
 (cl-spec:check-function 'broken-discounted-total :seed 42))
;; => :PASSED
```

There is a bug, yet the result is `:passed`. The bug shows only when the subtotal
is exactly 5000, and 100 draws from the range 0 to 20000 will almost never hit
exactly 5000. As chapter 3 cautioned, `:passed` is not a proof.

When you know the input you want to try, such as a boundary value, use
`check-call`. `check-call` takes one argument list and checks the contract once on
that input.

```lisp
(cl-spec:call-check-result-status
 (cl-spec:check-call 'broken-discounted-total '(4999)))
;; => :PASSED
(cl-spec:call-check-result-status
 (cl-spec:check-call 'broken-discounted-total '(5000)))
;; => :FAILED
(cl-spec:call-check-result-status
 (cl-spec:check-call 'broken-discounted-total '(5001)))
;; => :PASSED
```

Only 5000 failed. Look at the observation from that one call.

```lisp
(defparameter *at-5000* (cl-spec:check-call 'broken-discounted-total '(5000)))
(cl-spec:trial-observation-case (cl-spec:call-check-result-observation *at-5000*))
;; => :TEN-PERCENT-OFF
(cl-spec:trial-observation-reason (cl-spec:call-check-result-observation *at-5000*))
;; => :POSTCONDITION
```

At 5000 the `:ten-percent-off` case is selected, and its postcondition (the
discounted total is less than the original) is broken, because the implementation
returned 5000 unchanged.

`check-call` does no argument generation, no shrinking and no replay from a past
result. With the arguments you give, it only checks the arguments, selects the
case, makes one call and checks the outcome. That is why it works in the
`cl-spec` core alone, without loading check-it. It suits checking boundary values,
or an input from a bug report, directly.

> **Chapter summary**: Random checking can miss one specific point. When you know
> the input you want to try, use `check-call` to check the contract once on that
> input.

## 9. Further reading

By now you have used value specs, structured data, properties, function contracts,
error contracts, cases and one-shot checks. The following documents go into more
detail.

- [Structured data walkthrough](guides/structured-data-walkthrough.md):
  structured data beyond plists, such as alists, hash tables, `object-of`,
  `tagged-by` and AND generation.
- [Cases walkthrough](guides/function-spec-cases-walkthrough.md):
  the selection rules of `:cases`, and the details of selection errors and the
  per-case tally.
- [State observation walkthrough](guides/state-observation-walkthrough.md):
  contracts that observe state before the call with `:capture` and check it after
  the call with `:state-post`.
- [Reproducible stateful contracts](guides/reproducible-stateful-contracts.md):
  rebuilding state with `:fixture` so a stateful contract can be checked
  repeatedly.
- [Coverage](guides/coverage.md): an opt-in mechanism that records what a check
  tried, separately from whether it passed.
- [Evidence sufficiency](guides/evidence-sufficiency.md):
  a mechanism that evaluates, separately from a run's status, whether the evidence
  gathered meets explicitly stated requirements.
- [Self-specification](guides/self-specification-guide.md):
  a bundle that describes cl-spec's own API with cl-spec contracts and laws.
- [API reference](api/README.md): the list of public functions and macros.
- [Specification](cl-spec-specification-v0.2-draft.md): cl-spec's design and
  normative definitions.
- The [Runtime instrumentation](../README.md#runtime-instrumentation) section of the
  README: how to check function contracts against calls at run time.
