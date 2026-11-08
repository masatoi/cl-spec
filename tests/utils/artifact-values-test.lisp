;;;; tests/utils/artifact-values-test.lisp
(defpackage #:cl-spec/tests/utils/artifact-values-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
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

(defun reason-of (thunk)
  "Return the ARTIFACT-VALUE-ERROR reason THUNK signals, or (:RETURNED VALUE)."
  (handler-case (list :returned (funcall thunk))
    (artifact-value-error (condition)
      (cl-spec/src/utils/artifact-values:artifact-value-error-reason condition))))

(deftest symbols-decode-the-same-under-any-package
  ;; A package-local nickname of *PACKAGE* that spells a global package name
  ;; used to redirect the decoded symbols, so one artifact named different
  ;; definitions depending on the caller's package.
  (let ((host (make-package (symbol-name (gensym "AV-HOST")) :use '()))
        (view (make-package (symbol-name (gensym "AV-VIEW")) :use '()))
        (wire (serialize-artifact-value 'cl-user::av-probe)))
    (unwind-protect
         (progn
           (intern "AV-PROBE" host)
           (sb-ext:add-package-local-nickname "COMMON-LISP-USER" host view)
           (let ((*package* view))
             (ok (eq 'cl-user::av-probe (deserialize-artifact-value wire)))))
      (delete-package view)
      (delete-package host)))
  (testing "a nickname is not a package's name, so it does not decode"
    (ok (eq :missing-package
            (reason-of (lambda () (decode-artifact-value '(2 "CL" "CAR"))))))))

(deftest integers-decode-in-bounded-space
  (let* ((digits (make-string 3900 :initial-element #\9))
         (before (sb-ext:get-bytes-consed))
         (value (decode-artifact-value (list 4 digits)))
         (allocated (- (sb-ext:get-bytes-consed) before)))
    (ok (= value (parse-integer digits)))
    ;; Digit-by-digit parsing allocated about 7 MB for 4096 digits.
    (ok (< allocated (* 512 1024)) (format nil "~D bytes" allocated)))
  (testing "the decoder accepts no integer the encoder would refuse"
    (ok (eq :integer-limit
            (reason-of (lambda ()
                         (decode-artifact-value
                          (list 4 (format nil "~D" (ash 1 13000)))))))))
  (testing "negative values and the bound itself still round-trip"
    (dolist (value (list (- (1- (ash 1 13000))) (1- (ash 1 13000)) -7 0 -1/3))
      (ok (= value (deserialize-artifact-value (serialize-artifact-value value)))))))

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

(deftest nonfinite-floats-use-artifact-condition
  #+sbcl
  (dolist (bits '(#x7ff00000 -1048576 #x7ff80000 #x7f800000 -8388608 #x7fc00000))
    (let ((value
            (if (member bits '(#x7ff00000 -1048576 #x7ff80000))
                (funcall (symbol-function 'sb-kernel:make-double-float) bits 0)
                (funcall (symbol-function 'sb-kernel:make-single-float) bits))))
      (ok (rejected-p (lambda () (encode-artifact-value value))))
      (ok (rejected-p (lambda () (serialize-artifact-value value)))))))

(deftest flat-lists-use-node-budget-instead-of-nesting-budget
  (dolist (length '(500 4999 10000))
    (let* ((value (loop for i below length collect i))
           (budget (1+ (* 2 length)))
           (data (encode-artifact-value value :max-nodes budget :max-depth 1))
           (wire (serialize-artifact-value value :max-nodes budget :max-depth 1)))
      (ok (equal value (decode-artifact-value data :max-nodes budget :max-depth 1)))
      (ok (equal value (deserialize-artifact-value wire :max-nodes budget :max-depth 1)))
      (ok (rejected-p (lambda () (encode-artifact-value value :max-nodes (1- budget)))))
      (ok (rejected-p (lambda () (decode-artifact-value data :max-nodes (1- budget)))))
      (ok (rejected-p (lambda () (deserialize-artifact-value wire :max-nodes (1- budget)))))))
  (let ((value (loop for i below 500 collect i)))
    (ok (equal value (deserialize-artifact-value (serialize-artifact-value value))))))

(deftest dotted-spines-and-nested-values-keep-logical-depth
  (let ((value (loop for i below 500 collect i)))
    (setf (cdr (last value)) :tail)
    (ok (equal value (deserialize-artifact-value
                      (serialize-artifact-value value :max-depth 1) :max-depth 1))))
  (let ((nested 1))
    (dotimes (i 129) (setf nested (list nested)))
    (ok (rejected-p (lambda () (encode-artifact-value nested))))
    (let ((wire (serialize-artifact-value nested :max-depth 129)))
      (ok (rejected-p (lambda () (deserialize-artifact-value wire))))
      (ok (equal nested (deserialize-artifact-value wire :max-depth 129))))))

(deftest malicious-wire-depth-is-bounded-before-reconstruction
  (let ((wire (with-output-to-string (stream)
                (write-string "AV1 " stream)
                (dotimes (i 10000) (write-string "(8 " stream))
                (write-string "(0)" stream)
                (dotimes (i 10000) (write-string " (0))" stream)))))
    (ok (rejected-p (lambda () (deserialize-artifact-value wire)))))
  (ok (rejected-p (lambda () (deserialize-artifact-value "AV1 (((((((0)))))))")))))

(defun rejected-p (thunk)
  (handler-case (progn (funcall thunk) nil)
    (artifact-value-error () t)))
