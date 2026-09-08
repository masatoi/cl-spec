;;;; tests/instrument-test.lisp

(defpackage #:cl-spec/tests/instrument-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/instrument
                #:*instrumented-functions*
                #:instrumented-function-p
                #:instrument-function
                #:uninstrument-function))

(in-package #:cl-spec/tests/instrument-test)

(deftest instrumentation-table-starts-empty
  (testing "*INSTRUMENTED-FUNCTIONS* is a hash table with nothing in it"
    (ok (hash-table-p *instrumented-functions*))
    (ok (zerop (hash-table-count *instrumented-functions*)))))

(deftest unknown-functions-are-not-instrumented
  (testing "INSTRUMENTED-FUNCTION-P is false for a function nobody touched"
    (ok (null (instrumented-function-p 'transfer)))))

(deftest instrumentation-tracks-the-table
  (testing "INSTRUMENTED-FUNCTION-P reads the table rather than the fdefinition"
    (let ((*instrumented-functions* (make-hash-table :test #'eq)))
      (setf (gethash 'transfer *instrumented-functions*) #'identity)
      (ok (instrumented-function-p 'transfer)))))

(deftest instrumentation-tracks-presence-not-truthiness
  (testing "INSTRUMENTED-FUNCTION-P is true for a present key even when its value is NIL"
    (let ((*instrumented-functions* (make-hash-table :test #'eq)))
      (setf (gethash 'transfer *instrumented-functions*) nil)
      (ok (instrumented-function-p 'transfer)))))

(deftest instrumentation-entry-points-are-stubs
  (testing "INSTRUMENT-FUNCTION and UNINSTRUMENT-FUNCTION signal NOT-IMPLEMENTED"
    (ok (signals (instrument-function 'transfer) 'not-implemented))
    (ok (signals (uninstrument-function 'transfer) 'not-implemented))))
