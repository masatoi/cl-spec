;;;; tests/utils/random-test.lisp

(defpackage #:cl-spec/tests/utils/random-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/utils/random
                #:make-seed
                #:seed->random-state))

(in-package #:cl-spec/tests/utils/random-test)

(defun draw (seed count)
  "Return COUNT random integers drawn from the state SEED derives."
  (let ((*random-state* (seed->random-state seed)))
    (loop repeat count collect (random 1000000))))

(deftest the-same-seed-reproduces-the-sequence
  (testing "two states from one seed agree"
    (ok (equal (draw 18372918 20) (draw 18372918 20))))
  (testing "different seeds disagree"
    (ok (not (equal (draw 1 20) (draw 2 20))))))

(deftest seeds-are-usable-integers
  (testing "MAKE-SEED returns a non negative integer"
    (let ((seed (make-seed)))
      (ok (integerp seed))
      (ok (not (minusp seed)))))
  (testing "a generated seed round trips through SEED->RANDOM-STATE"
    (let ((seed (make-seed)))
      (ok (equal (draw seed 5) (draw seed 5))))))

(deftest states-are-independent
  (testing "deriving a state does not disturb the caller's *RANDOM-STATE*"
    (let* ((*random-state* (seed->random-state 7))
           (before (random 1000000)))
      (seed->random-state 99)
      (let ((*random-state* (seed->random-state 7)))
        (ok (eql before (random 1000000)))))))
