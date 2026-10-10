# 日本語入門チュートリアル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ショッピングカートを題材に cl-spec の基本を一本道で学べる日本語チュートリアル
`docs/tutorial.ja.md` を追加し、本文の結果を実行可能 example とテストで担保する。

**Architecture:** `examples/tutorial-cart.lisp`（inferred subsystem）がチュートリアルの全定義を
専用 registry に登録する `register-example!` と、章ごとの結果を plist で返す `demo-*` を持つ。
`tests/tutorial-cart-example-test.lisp` が `demo-*` を呼んで本文の主張を検証する。
本文は読者が REPL（`cl-user`）に打つ形で同じフォームを示す。

**Tech Stack:** Common Lisp (SBCL)、ASDF package-inferred system、Rove、check-it。

**Spec:** [../specs/2026-10-10-tutorial-ja-design.md](../specs/2026-10-10-tutorial-ja-design.md)

## Global Constraints

- core system `cl-spec` は check-it を読み込まない。example だけが bare
  `(:import-from #:cl-spec/src/backends/check-it)` で backend に依存する。
- `cl-spec.asd` は変更しない。新しいテストファイルは必ず `tests.lisp` に登録する。
- `src/` 外でも `cl-spec` nickname ではなく `cl-spec/main` から `:import-from` する
  （既存 example と同じ）。`(:use #:cl)` のみ。
- example のロードは定義だけを行い、呼び出し側の `*registry*` を読まず書かない。
- seed は固定する。決定的な値（status、failure reason、case 件数の合計、trials）は完全一致、
  check-it 依存で揺れうる値（生成値、反例の具体値）は形で検証する。
- example とテストのコード・コメント・docstring は英語、本文は日本語。
- Google Common Lisp Style Guide、2 スペース、100 桁以内、トップレベルフォーム間に空行、
  ファイル先頭は `;;;; <path>`、公開関数に docstring。
- Lisp ファイルの読み書きは cl-mcp ツールで行う（新規作成は `fs-write-file`、以降は
  `lisp-edit-form` / `lisp-patch-form`）。シェルは git、rove、mallet のみ。
- テストは `run-tests`（system `cl-spec/tests`）または `rove cl-spec.asd` で走らせる。

## File Structure

| ファイル | 責務 |
|---|---|
| `examples/tutorial-cart.lisp`（新規） | 題材の関数・condition、`register-example!`、章ごとの `demo-*` |
| `tests/tutorial-cart-example-test.lisp`（新規） | `demo-*` の結果が本文の主張どおりであることの検証 |
| `tests.lisp`（変更） | 新テストパッケージの登録 |
| `docs/tutorial.ja.md`（新規） | チュートリアル本文 |
| `README.md`（変更） | Documentation 節へのリンク |
| `CLAUDE.md`（変更） | Systems 表への example 行 |

## 試作で確認済みの事実（seed 42、SBCL 2.5.0、現 main の check-it backend）

計画作成時に REPL で同じ定義を評価して得た結果。本文に載せる値の出発点とし、Task 4 で
demo を実行して再確認する。

- `(sample 'price :count 5 :seed 42)` → `(7271 861 5391 5192 5735)`
- `(explain-data 'price 0)` の `:errors` →
  `((:kind :out-of-range :path nil :actual 0 :expected (:range :min 1 :max 10000) :violated-bound :minimum))`
- `line-item` の `:qty 0` → `:field-path (:qty) :kind :out-of-range :path (:qty)`、
  `:qty` 欠落 → `:kind :missing-key :path (:qty)`、`:memo` 追加 → `:kind :unknown-key :path (:memo)`
- `subtotal-is-additive` は `:passed`、trials 100
- `broken-subtotal-is-additive` は `:failed`、reason `:predicate-false`、trials 2。
  shrunk counterexample は
  `(a ((:sku "89M63woD6VjYl" :price 1 :qty 1)) b ((:sku "4wc2vXqf2yrr2i3" :price 1 :qty 1)))`、
  shrunk outcome `:used`。結果を `:seed` に渡した replay は `:failed`、seed 42、同じ counterexample。
- `check-function 'cart-subtotal` は `:passed`。`broken-cart-subtotal` は `:failed`、
  reason `:postcondition`、shrunk は `(cart ((:sku "Qs6Z64Zb5" :price 1 :qty 1)))`。
- `make-line-item` は `:passed`。`broken-make-line-item` は `:failed`、reason
  `:missing-condition`。
- `discounted-total` は `:passed`、`:no-discount` 27 回、`:ten-percent-off` 73 回、
  `:never-called nil`。`:trials 1` では `:passed`、`:never-called (:no-discount)`。
- `broken-discounted-total` のランダム検査は `:passed`（5000 ちょうどを引かない）。
  `check-call` は 4999 → `:passed`、5000 → `:failed`（case `:ten-percent-off`、reason
  `:postcondition`）、5001 → `:passed`。

---

### Task 1: example の骨組みと第 1・2 章（値の仕様、構造化データ）

**Files:**
- Create: `examples/tutorial-cart.lisp`
- Create: `tests/tutorial-cart-example-test.lisp`
- Modify: `tests.lisp`（`function-spec-cases-example-test` の行の直後に 1 行追加）

**Interfaces:**
- Produces: package `cl-spec/examples/tutorial-cart`。
  `(make-example-registry) → registry`、
  `(register-example! &optional registry) → registry`（spec `price`、`quantity`、`line-item`、
  `cart` を登録）、
  `(demo-value-specs &optional registry) → plist`（キー `:valid-price :zero-price
  :zero-price-errors :prices :prices-valid`）、
  `(demo-structured-data &optional registry) → plist`（キー `:item-valid :zero-qty-errors
  :missing-qty-errors :unknown-key-errors :carts :carts-valid`）。

- [ ] **Step 1: 失敗するテストを書く**

`fs-write-file` で `tests/tutorial-cart-example-test.lisp` を作成する:

```lisp
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
```

注: テストで `::` を使うのは登録確認の 1 箇所だけで、既存の
`function-spec-cases-example-test` と同じ書き方である（spec 名は export しない）。

`tests.lisp` の `(:import-from #:cl-spec/tests/function-spec-cases-example-test)` の直後に
`lisp-patch-form`（form_type `defpackage`、form_name `cl-spec/tests`）で追加する:

```lisp
  (:import-from #:cl-spec/tests/tutorial-cart-example-test)
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `run-tests` で `{"system": "cl-spec/tests"}`
Expected: `cl-spec/examples/tutorial-cart` が見つからずロードに失敗する。

- [ ] **Step 3: example を実装する**

`fs-write-file` で `examples/tutorial-cart.lisp` を作成する:

```lisp
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
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `run-tests` で `{"system": "cl-spec/tests", "tests": ["cl-spec/tests/tutorial-cart-example-test::tutorial-registration-leaves-the-user-registry-untouched", "cl-spec/tests/tutorial-cart-example-test::tutorial-chapter-1-value-specs", "cl-spec/tests/tutorial-cart-example-test::tutorial-chapter-2-structured-data"]}`
Expected: 3 件すべて PASS。`NO TESTS RAN` なら名前を確認する。

- [ ] **Step 5: コミット**

```bash
git add examples/tutorial-cart.lisp tests/tutorial-cart-example-test.lisp tests.lisp
git commit -m "examples: add the tutorial cart's value and structured-data chapters"
```

---

### Task 2: 第 3〜5 章（性質、バグの発見、関数契約）

**Files:**
- Modify: `examples/tutorial-cart.lisp`
- Modify: `tests/tutorial-cart-example-test.lisp`

**Interfaces:**
- Consumes: Task 1 の `register-example!` と spec `cart`。
- Produces: `(cart-subtotal cart) → integer`、`(broken-cart-subtotal cart) → integer`、
  property `subtotal-is-additive`、`broken-subtotal-is-additive`、
  function spec `cart-subtotal`、`broken-cart-subtotal`、
  `(demo-property &optional registry) → plist`（`:status :trials :related`）、
  `(demo-find-bug &optional registry) → plist`（`:status :failure-reason :trials
  :counterexample :shrunk-a :shrunk-b :shrunk-outcome :replay-status :replay-seed
  :same-counterexample`）、
  `(demo-function-contract &optional registry) → plist`（`:status :broken-status
  :broken-failure-reason :broken-shrunk-cart`）。

- [ ] **Step 1: 失敗するテストを書く**

テストの `defpackage` の `cl-spec/examples/tutorial-cart` の import に
`#:cart-subtotal #:broken-cart-subtotal #:demo-property #:demo-find-bug
#:demo-function-contract` を加え、末尾に追加する:

```lisp
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
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `run-tests` で `{"system": "cl-spec/tests"}`
Expected: `cart-subtotal` などが export されておらず読み込み時に失敗する。

- [ ] **Step 3: example を実装する**

`defpackage` の `cl-spec/main` import に `#:defproperty #:defspec-function
#:run-property #:check-function #:properties-for #:property-result-status
#:property-result-failure-reason #:property-result-trials
#:property-result-counterexample #:property-result-shrunk-counterexample
#:property-result-shrunk-outcome #:property-result-seed` を加え、`:export` に
`#:cart-subtotal #:broken-cart-subtotal #:demo-property #:demo-find-bug
#:demo-function-contract` を加える。

`(in-package ...)` の直後（`make-example-registry` の前）に追加する:

```lisp
(defun cart-subtotal (cart)
  "Return the sum of price times quantity over CART's line items.  Pure."
  (loop for item in cart
        sum (* (getf item :price) (getf item :qty))))

(defun broken-cart-subtotal (cart)
  "A deliberately wrong subtotal: it skips the first line item."
  (loop for item in (rest cart)
        sum (* (getf item :price) (getf item :qty))))
```

`register-example!` の `(defspec cart ...)` と `registry` の間に追加する:

```lisp
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
```

ファイル末尾に追加する:

```lisp
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
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `run-tests` で `{"system": "cl-spec/tests", "tests": ["cl-spec/tests/tutorial-cart-example-test::tutorial-chapter-3-property", "cl-spec/tests/tutorial-cart-example-test::tutorial-chapter-4-find-bug", "cl-spec/tests/tutorial-cart-example-test::tutorial-chapter-5-function-contract"]}`
Expected: 3 件すべて PASS。Task 1 の 3 件も再実行して PASS のままであること。

- [ ] **Step 5: コミット**

```bash
git add examples/tutorial-cart.lisp tests/tutorial-cart-example-test.lisp
git commit -m "examples: add the tutorial cart's property and contract chapters"
```

---

### Task 3: 第 6〜8 章（エラー契約、条件ごとの契約、1 回だけの確認）

**Files:**
- Modify: `examples/tutorial-cart.lisp`
- Modify: `tests/tutorial-cart-example-test.lisp`

**Interfaces:**
- Consumes: Task 1 の spec `price`、`register-example!`。
- Produces: condition `invalid-quantity`（reader `invalid-quantity-qty`）、
  `(make-line-item sku price qty) → plist`、`(broken-make-line-item sku price qty)`、
  `(discounted-total subtotal) → integer`、`(broken-discounted-total subtotal)`、
  対応する function spec 4 つ、
  `(demo-error-contract &optional registry) → plist`（`:status :broken-status
  :broken-failure-reason :broken-counterexample`）、
  `(demo-cases &optional registry) → plist`（`:status :cases :never-called
  :one-trial-status :one-trial-never-called`）、
  `(demo-check-call &optional registry) → plist`（`:random-status :boundary-statuses
  :boundary-case :boundary-reason :correct-boundary-status`）。

- [ ] **Step 1: 失敗するテストを書く**

テストの import に `#:demo-error-contract #:demo-cases #:demo-check-call` を加え、末尾に
追加する:

```lisp
(defun case-entry (cases name)
  "Return the case report entry in CASES whose :NAME is NAME."
  (find name cases :key (lambda (entry) (getf entry :name))))

(deftest tutorial-chapter-6-error-contract
  (let ((summary (demo-error-contract)))
    (testing "signalling INVALID-QUANTITY satisfies the error contract"
      (ok (eq :passed (getf summary :status))))
    (testing "returning normally instead is a missing condition"
      (ok (eq :failed (getf summary :broken-status)))
      (ok (eq :missing-condition (getf summary :broken-failure-reason))))))

(deftest tutorial-chapter-7-cases
  (let ((summary (demo-cases)))
    (testing "both cases are exercised and pass"
      (let ((cases (getf summary :cases)))
        (ok (eq :passed (getf summary :status)))
        (ok (null (getf summary :never-called)))
        (dolist (name '(:no-discount :ten-percent-off))
          (let ((entry (case-entry cases name)))
            (ok (plusp (getf entry :called)))
            (ok (= (getf entry :called) (getf entry :passed)))))
        (ok (= 100 (reduce #'+ cases :key (lambda (entry) (getf entry :called)))))))
    (testing "a passing run can leave a case unexercised"
      (ok (eq :passed (getf summary :one-trial-status)))
      (ok (= 1 (length (getf summary :one-trial-never-called)))))))

(deftest tutorial-chapter-8-check-call
  (let ((summary (demo-check-call)))
    (testing "random checking misses the boundary bug"
      (ok (eq :passed (getf summary :random-status))))
    (testing "checking the boundary directly catches it"
      (ok (equal '(:passed :failed :passed) (getf summary :boundary-statuses)))
      (ok (eq :ten-percent-off (getf summary :boundary-case)))
      (ok (eq :postcondition (getf summary :boundary-reason))))
    (testing "the correct implementation passes the same boundary"
      (ok (eq :passed (getf summary :correct-boundary-status))))))
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `run-tests` で `{"system": "cl-spec/tests"}`
Expected: `demo-error-contract` などが存在せず読み込み時に失敗する。

- [ ] **Step 3: example を実装する**

`cl-spec/main` import に `#:check-call #:call-check-result-status
#:call-check-result-observation #:trial-observation-case #:trial-observation-reason
#:function-check-result-case-report` を加え、`:export` に `#:invalid-quantity
#:invalid-quantity-qty #:make-line-item #:broken-make-line-item #:discounted-total
#:broken-discounted-total #:demo-error-contract #:demo-cases #:demo-check-call` を加える。

`broken-cart-subtotal` の直後に追加する:

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

(defun broken-make-line-item (sku price qty)
  "A deliberately wrong constructor: it silently raises a bad quantity to 1."
  (list :sku sku :price price :qty (max qty 1)))

(defun discounted-total (subtotal)
  "Return SUBTOTAL, less 10% rounded down when SUBTOTAL is 5000 or more."
  (if (< subtotal 5000)
      subtotal
      (- subtotal (floor subtotal 10))))

(defun broken-discounted-total (subtotal)
  "A deliberately wrong total: it starts the discount above 5000, not at it."
  (if (<= subtotal 5000)
      subtotal
      (- subtotal (floor subtotal 10))))
```

`register-example!` の `broken-cart-subtotal` 契約と `registry` の間に追加する:

```lisp
    ;; Chapter 6: an error contract.
    (defspec-function make-line-item
      (:args (sku string) (price price) (qty (range integer -10 0)))
      (:signals (type invalid-quantity)))
    (defspec-function broken-make-line-item
      (:args (sku string) (price price) (qty (range integer -10 0)))
      (:signals (type invalid-quantity)))
    ;; Chapter 7: per-condition cases.
    (defspec-function discounted-total
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
    (defspec-function broken-discounted-total
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

ファイル末尾に追加する:

```lisp
(defun demo-error-contract (&optional (registry (register-example!)))
  "Chapter 6: check the error contracts with seed 42.

Returns the correct constructor's :STATUS, and the broken one's :BROKEN-STATUS,
:BROKEN-FAILURE-REASON and :BROKEN-COUNTEREXAMPLE."
  (let ((good (check-function 'make-line-item :seed 42 :registry registry))
        (bad (check-function 'broken-make-line-item :seed 42 :registry registry)))
    (list :status (property-result-status good)
          :broken-status (property-result-status bad)
          :broken-failure-reason (property-result-failure-reason bad)
          :broken-counterexample (property-result-shrunk-counterexample bad))))

(defun demo-cases (&optional (registry (register-example!)))
  "Chapter 7: check the per-case discount contract, then with a single trial.

Returns the 100-trial :STATUS, the per-case :CASES report and :NEVER-CALLED, and
the one-trial :ONE-TRIAL-STATUS and :ONE-TRIAL-NEVER-CALLED, which shows that a
passing run need not have reached every case."
  (let* ((full (check-function 'discounted-total :seed 42 :registry registry))
         (one (check-function 'discounted-total :trials 1 :seed 42 :registry registry))
         (report (function-check-result-case-report full)))
    (list :status (property-result-status full)
          :cases (getf report :cases)
          :never-called (getf report :never-called)
          :one-trial-status (property-result-status one)
          :one-trial-never-called
          (getf (function-check-result-case-report one) :never-called))))

(defun demo-check-call (&optional (registry (register-example!)))
  "Chapter 8: random checking misses a boundary bug that CHECK-CALL catches.

Returns the broken total's :RANDOM-STATUS over 100 trials with seed 42, the
CHECK-CALL statuses for 4999, 5000 and 5001 as :BOUNDARY-STATUSES, the selected
:BOUNDARY-CASE and :BOUNDARY-REASON at 5000, and :CORRECT-BOUNDARY-STATUS for the
correct total at 5000."
  (let ((random-run (check-function 'broken-discounted-total :seed 42 :registry registry))
        (boundary (check-call 'broken-discounted-total '(5000) :registry registry)))
    (list :random-status (property-result-status random-run)
          :boundary-statuses
          (mapcar (lambda (subtotal)
                    (call-check-result-status
                     (check-call 'broken-discounted-total (list subtotal)
                                 :registry registry)))
                  '(4999 5000 5001))
          :boundary-case (trial-observation-case
                          (call-check-result-observation boundary))
          :boundary-reason (trial-observation-reason
                            (call-check-result-observation boundary))
          :correct-boundary-status
          (call-check-result-status
           (check-call 'discounted-total '(5000) :registry registry)))))
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `run-tests` で `{"system": "cl-spec/tests"}`（全件）
Expected: 新しい 3 件を含め全件 PASS。

- [ ] **Step 5: コミット**

```bash
git add examples/tutorial-cart.lisp tests/tutorial-cart-example-test.lisp
git commit -m "examples: add the tutorial cart's error, case and one-call chapters"
```

---

### Task 4: 本文 `docs/tutorial.ja.md`

**Files:**
- Create: `docs/tutorial.ja.md`

**Interfaces:**
- Consumes: Task 1〜3 の `register-example!` 内のフォーム（本文のコードブロックはそれと
  同じフォームを `cl-spec:` 接頭辞付きで書く）と `demo-*` の結果。

- [ ] **Step 1: 本文に載せる結果を取得する**

`load-system` で `cl-spec/examples/tutorial-cart` を読み込み、`repl-eval` で
`demo-value-specs` から `demo-check-call` まで 8 つを実行して結果を控える。上の
「試作で確認済みの事実」と食い違う値があれば、本文には実行結果のほうを載せる。

- [ ] **Step 2: 本文を書く**

次の構成で書く。見出しは日本語。コードブロックは読者が `cl-user` で打つ形で、関数定義は
example と同じ本体、spec・property・契約は `register-example!` 内と同じフォームに
`cl-spec:` 接頭辞を付けたもの。出力例は `;; =>` コメントで示す。各章の末尾に 1〜3 行の
「この章のまとめ」を置く。

**冒頭**（見出し前のリード 2〜3 段落）
- 対象読者（CL は書けるが cl-spec も PBT も初めて）、所要時間の目安（1 時間程度）、
  題材（ショッピングカートの金額計算）。
- 本文の結果は `examples/tutorial-cart.lisp` の `demo-*` とテストで検証されていること。

**0. はじめに**
- cl-spec とは: 値や関数の「約束」を実行可能なデータとして書き、検証・説明・生成・
  property テストに使うライブラリ、と 2〜3 文で。
- property-based testing を一段落で: 具体例ではなく「どんな入力でも成り立つ性質」を書き、
  ランダム入力で反例を探し、見つかれば小さく縮める（shrink）。
- 前提: SBCL、ASDF から cl-spec が見えること（Quicklisp の local-projects など）、check-it。
- 読み込み:
  ```lisp
  (asdf:load-system :cl-spec/check-it)
  ```
  `cl-spec` 本体は check-it に依存せず、生成と property 実行に必要な backend は
  `cl-spec/check-it` が入れることを一文で。
- ファイル版の動かし方:
  ```lisp
  (asdf:load-system "cl-spec/examples/tutorial-cart")
  (cl-spec/examples/tutorial-cart:demo-find-bug)
  ```
  ファイル版は専用 registry に登録するので REPL の定義とは混ざらない、と注記。

**1. 値の仕様を書く**
- `cl-spec:defspec` で `price`（1〜10000 の整数）と `quantity`（1〜99）。
- `validp` で 500 → `T`、0 → `NIL`。
- `explain-data 'price 0` の出力全体を示し、`:errors` の各キー（`:kind`、`:path`、
  `:actual`、`:expected`）を表で説明する。
- `(cl-spec:sample 'price :count 5 :seed 42)` と出力例。seed が同じなら同じ値が出ること、
  値そのものは環境によって異なりうることを書く。

**2. 構造化データを扱う**
- `line-item` の plist spec と `cart` の `list-of`。`:required`、`:closed t`、
  `:max-length` の意味。
- `explain-data` を 3 つ: `:qty 0`（`:path (:qty)`、`:out-of-range`）、`:qty` 欠落
  （`:missing-key`）、`:memo` 追加（`:unknown-key`）。`:path` がどのフィールドかを
  指すことを強調する。
- `(cl-spec:sample 'cart :count 2 :seed 42)` で、生成値が spec を満たすカートであること。

**3. 性質を書く**
- `cart-subtotal` の `defun`。
- `subtotal-is-additive` の `defproperty`。`(a cart) (b cart)` が「cart spec から生成した
  値を a、b に束縛する」意味であること、`:about` の役割（`properties-for` で関数から
  引ける）。
- `(cl-spec:run-property 'subtotal-is-additive :seed 42)` と
  `property-result-status` → `:PASSED`、`property-result-trials` → `100`。
- `(cl-spec:properties-for 'cart-subtotal)` → `(SUBTOTAL-IS-ADDITIVE)`。
- 注意書き: `:passed` は「実行した 100 回で違反を観測しなかった」であり証明ではない。

**4. バグを見つける**
- 先頭の明細を落とす `broken-cart-subtotal` と、同じ性質の
  `broken-subtotal-is-additive`。
- 実行して `:FAILED`、`property-result-failure-reason` → `:PREDICATE-FALSE`。
- `property-result-counterexample`（大きい反例）と
  `property-result-shrunk-counterexample`（`a`、`b` が明細 1 件ずつ、価格と数量が 1）を
  並べて示し、縮小後の反例から「先頭の明細が無視されている」と読める流れを書く。
  縮小は最小を約束しないこと。
- replay: `(cl-spec:run-property 'broken-subtotal-is-additive :seed result)` で
  結果オブジェクトを `:seed` に渡すと、記録された seed・profile・オプションで再実行され
  同じ反例が出る。

**5. 関数契約を書く**
- `cl-spec:defspec-function cart-subtotal` の `:args`、`:returns`、`:post`。
  `result` が戻り値を指すこと、`:post (>= result (length cart))` の根拠（価格・数量は
  1 以上）。
- `(cl-spec:check-function 'cart-subtotal :seed 42)` → `:PASSED`。
- `broken-cart-subtotal` の契約 → `:FAILED`、reason `:POSTCONDITION`、
  shrunk は明細 1 件のカート。
- property と関数契約の使い分けを 3〜4 行で: 関数単体の入出力の約束は契約、
  複数の呼び出しや関数にまたがる法則は property。

**6. エラーを約束する**
- `invalid-quantity` condition と `make-line-item`。
- `(:signals (type invalid-quantity))` の契約。`:args` の `qty` を `(range integer -10 0)`
  にしているのは「この契約は不正な数量についての約束」だから、と説明し、
  正常系と異常系を 1 つの契約にまとめるのは次章の `:cases` であると予告する。
  ユーザー定義の condition 名には `type` が必要なこと（裸のシンボルは spec 名と解釈される）。
- 正しい実装 → `:PASSED`、`broken-make-line-item` → `:FAILED` / `:MISSING-CONDITION`。

**7. 条件ごとに約束を分ける**
- `discounted-total`（5000 未満は割引なし、以上は 10% 引き、端数切り捨て）。
- `:cases` の契約。各 case は `:when` 1 つと `:returns` または `:signals` 1 つ。選択は
  排他的で、ちょうど 1 つの `:when` が真でなければならない（どれも真でない、複数真は
  契約側のエラー）。`:post` が実装の写しではなく「割引後は元より小さく 9 割以上」という
  性質になっている点に触れる。
- `check-function` → `:PASSED`、`function-check-result-case-report` の `:cases` 部分
  （`:no-discount` 27 回、`:ten-percent-off` 73 回）と `:never-called NIL`。
- `:trials 1` で実行すると `:PASSED` だが `:never-called` に 1 つ case が残る。
  `:passed` は全 case を試した意味ではないので `:never-called` を読む、と書く。

**8. 1 回だけ確かめる**
- 境界を間違えた `broken-discounted-total`（`<=` にしている）とその契約。
- `check-function` は `:PASSED`: 0〜20000 から 100 回引いても 5000 ちょうどはまず出ない。
- `(cl-spec:check-call 'broken-discounted-total '(4999))`、`'(5000)`、`'(5001)` の
  `call-check-result-status` → `:PASSED`、`:FAILED`、`:PASSED`。5000 の observation の
  case が `:TEN-PERCENT-OFF`、reason が `:POSTCONDITION`。
- `check-call` は生成・縮小・replay を行わず、check-it なしの `cl-spec` だけで動く。
  境界値や不具合報告の入力を直接確かめる用途。

**9. 次に読むもの**
- 箇条書きで、各リンクに 1 行説明:
  - [構造化データ walkthrough](guides/structured-data-walkthrough.md)（alist、hash-table、
    `object-of`、`tagged-by`、AND 生成）
  - [cases walkthrough](guides/function-spec-cases-walkthrough.md)
  - [状態観測 walkthrough](guides/state-observation-walkthrough.md)（`:capture`、`:state-post`）
  - [再現可能な状態付き契約](guides/reproducible-stateful-contracts.md)（`:fixture`）
  - [coverage](guides/coverage.md)、[evidence sufficiency](guides/evidence-sufficiency.md)
  - [self-specification](guides/self-specification-guide.md)
  - [API リファレンス](api/README.md)、[仕様書](cl-spec-specification-v0.2-draft.md)
  - README の Runtime instrumentation 節（`../README.md#runtime-instrumentation`）
- guides は英語であることを一言添える。

- [ ] **Step 3: 本文と example の一致を目視確認する**

本文の各コードブロックを example の対応フォームと突き合わせ、引数・spec・seed が一致する
ことを確認する。リンク先ファイルがすべて存在することを `ls` で確認する
（`docs/guides/*.md`、`docs/api/README.md`、`docs/cl-spec-specification-v0.2-draft.md`）。

- [ ] **Step 4: 新しいイメージで本文を上から実行する**

`pool-kill-worker`（`reset: true`）で worker を作り直し、本文のコードブロックを上から
順に `repl-eval`（package `CL-USER`、1 ブロックずつ）で実行し、`;; =>` に書いた結果と
一致することを確かめる。食い違いは本文を直す。

- [ ] **Step 5: コミット**

```bash
git add docs/tutorial.ja.md
git commit -m "docs: add a Japanese introductory tutorial"
```

---

### Task 5: 導線と最終検証

**Files:**
- Modify: `README.md`（`## Documentation` 節の先頭）
- Modify: `CLAUDE.md`（Systems 表）

- [ ] **Step 1: README にリンクを追加する**

`## Documentation` の箇条書きの先頭に追加する:

```markdown
- [`docs/tutorial.ja.md`](docs/tutorial.ja.md) — introductory tutorial in Japanese:
  value specs, properties, shrinking and replay, function contracts, `:signals`,
  `:cases` and `check-call` on a shopping cart
```

同じ節の examples の箇条書きの末尾に追加する:

```markdown
- [`examples/tutorial-cart.lisp`](examples/tutorial-cart.lisp) — the executable
  example the tutorial runs
```

- [ ] **Step 2: CLAUDE.md の Systems 表に行を追加する**

`cl-spec/examples/stateful-withdraw` の行の直後に追加する:

```markdown
| `cl-spec/examples/tutorial-cart` | executable shopping-cart example behind the Japanese tutorial (inferred subsystem) | `check-it` |
```

- [ ] **Step 3: 新しい Lisp プロセスでコンパイル警告を確認する**

Run:
```bash
ros -e '(progn (asdf:compile-system :cl-spec :force :all) (asdf:compile-system "cl-spec/examples/tutorial-cart" :force :all) (uiop:quit 0))'
```
Expected: 新規ファイルに由来する WARNING がない（check-it.asd 由来の既存警告は無関係）。

- [ ] **Step 4: 全テストを実行する**

Run: `rove cl-spec.asd`
Expected: 全件 PASS。出力に `tutorial-chapter-8-check-call` などの新テストが現れることを確認。

- [ ] **Step 5: mallet を新規ファイルにかける**

Run: `mallet examples/tutorial-cart.lisp tests/tutorial-cart-example-test.lisp`
Expected: 指摘があれば記録する（lint は現在 advisory であり PR をブロックしない）。
新規ファイルの指摘で容易に直せるものは直す。

- [ ] **Step 6: コミット**

```bash
git add README.md CLAUDE.md
git commit -m "docs: link the Japanese tutorial and its example"
```
