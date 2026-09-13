;;;; tests/utils/artifact-values-test.lisp
(defpackage #:cl-spec/tests/utils/artifact-values-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:encode-artifact-value #:decode-artifact-value
                #:serialize-artifact-value #:deserialize-artifact-value
                #:artifact-value-error))
(in-package #:cl-spec/tests/utils/artifact-values-test)

(deftest values-round-trip
  (dolist (value (list nil t :hello 'car #\Newline 123 -42 2/3
                      1.25f0 -0.0f0 1.25d0 -0.0d0 "a\"b"
                      '(a . b) #(1 2 "x")))
    (let ((copy (deserialize-artifact-value (serialize-artifact-value value))))
      (ok (equalp value copy))
      (when (floatp value)
        (ok (eq (type-of value) (type-of copy)))
        (ok (= (float-sign value) (float-sign copy)))))))

(deftest limits-total-string-storage
  (ok (rejected-p
        (lambda ()
          (encode-artifact-value
            (list (make-string 600000 :initial-element #\a)
                  (make-string 600000 :initial-element #\b)))))))

(deftest limits-decoded-string-storage
  (ok (rejected-p
        (lambda ()
          (decode-artifact-value
            (list 9 (list 7 (make-string 600000 :initial-element #\a))
                    (list 7 (make-string 600000 :initial-element #\b))))))))

(deftest direct-tagged-round-trip
  (ok (equal '(nil nil t t) (decode-artifact-value (encode-artifact-value '(nil nil t t))))))

(deftest rejects-malformed-wire
  (dolist (text '("#.(error \"reader ran\")" "AV2 (0)" "AV1 #.(error \"reader ran\")"
                  "AV1 (999)" "AV1 (4 1:x)" "AV1 (0) (0)"
                  "AV1 (2 12:NO-SUCH-PACK 1:X)" "AV1 (8 (0))" "AV1 (9 -1)" "AV1 (0"
                  "AV1 (4 999999999999999999999999999999:1)"
                  "AV1 (6 0 1:1 4:9999 1:1)" "AV1 (5 1:1 1:0)"
                  "AV1 (3 2:-1)" "AV1 (2 7:KEYWORD 29:ARTIFACT-SHOULD-NOT-BE-INTERNED)"))
    (ok (rejected-p (lambda () (deserialize-artifact-value text)))))
  (ok (null (find-symbol "ARTIFACT-SHOULD-NOT-BE-INTERNED" "KEYWORD")))
  (ok (rejected-p (lambda () (decode-artifact-value '(8 (0))))))
  (let ((cycle (list 9)))
    (setf (cdr cycle) cycle)
    (ok (rejected-p (lambda () (decode-artifact-value cycle)))))
  (ok (rejected-p (lambda () (deserialize-artifact-value "AV1 (0)" :max-chars 2))))
  (ok (rejected-p (lambda () (deserialize-artifact-value
                              (format nil "AV1 (4 4097:~A)" (make-string 4097 :initial-element #\1))))))
  (ok (rejected-p (lambda () (deserialize-artifact-value
                              "AV1 (8 (8 (0) (0)) (0))" :max-depth 1)))))

(deftest rejects-unsupported-and-excessive-values
  (dolist (value (list (make-hash-table) #'car #p"/tmp/x" (make-symbol "X")
                      (make-array 2 :element-type 'bit)))
    (ok (rejected-p (lambda () (serialize-artifact-value value)))))
  (let ((cycle (list 1)) (shared (copy-seq "x")))
    (setf (cdr cycle) cycle)
    (ok (rejected-p (lambda () (encode-artifact-value cycle))))
    (ok (rejected-p (lambda () (encode-artifact-value (list shared shared))))))
  (ok (rejected-p (lambda () (encode-artifact-value '(1 2) :max-nodes 1))))
  (ok (rejected-p (lambda () (encode-artifact-value '((1)) :max-depth 1))))
  (ok (rejected-p (lambda () (serialize-artifact-value "abcdef" :max-chars 3)))))

(defun rejected-p (thunk)
  (handler-case (progn (funcall thunk) nil)
    (artifact-value-error () t)))
