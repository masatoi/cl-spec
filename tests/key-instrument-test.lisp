;;;; tests/key-instrument-test.lisp

(defpackage #:cl-spec/tests/key-instrument-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/instrument))

(in-package #:cl-spec/tests/key-instrument-test)

(defvar *calls* nil)
(defun keyed-guard (&rest arguments &key (limit 42 supplied) &allow-other-keys)
  (push (copy-list arguments) *calls*)
  (values limit supplied))

(deftest guards-bind-effective-key-values-and-preserve-raw-order
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*calls* nil))
    (cl-spec:defspec-function keyed-guard
      (:args &key ((:limit limit) (nullable integer) supplied))
      (:returns (nullable integer))
      (:post (if supplied (eql result limit) (= result 42))))
    (unwind-protect
         (progn
           (cl-spec/instrument:instrument-function 'keyed-guard)
           (ok (equal '(42 nil) (multiple-value-list (keyed-guard))))
           (ok (equal '(nil t) (multiple-value-list (keyed-guard :limit nil))))
           (ok (equal '(7 t)
                      (multiple-value-list
                       (keyed-guard :limit 7 :limit "ignored" :allow-other-keys t :other 4))))
           (ok (equal '(:limit 7 :limit "ignored" :allow-other-keys t :other 4) (first *calls*)))
           (ok (signals (keyed-guard :unknown 3)
                        'cl-spec/instrument:instrumentation-violation))
           (ok (signals (keyed-guard :limit "wrong")
                        'cl-spec/instrument:instrumentation-violation))
           (ok (= 3 (length *calls*))))
      (cl-spec/instrument:uninstrument-function 'keyed-guard))))

(deftest keyword-introspection-and-global-allowance-are-visible
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function keyed-guard
      (:args &key ((:limit limit) integer supplied) &allow-other-keys)
      (:returns t))
    (let* ((data (cl-spec:function-spec-data 'keyed-guard))
           (entry (first (getf data :arguments)))
           (schema (getf data :argument-schema)))
      (ok (getf data :definition-digest-complete))
      (ok (eq :key (getf entry :kind)))
      (ok (eq :limit (getf entry :keyword)))
      (ok (getf schema :allow-other-keys)))))
