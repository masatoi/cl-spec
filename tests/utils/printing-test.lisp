;;;; tests/utils/printing-test.lisp
;;;;
;;;; Reports and explanations print the values they are about.  The printer's
;;;; *PRINT-LENGTH* and *PRINT-LEVEL* bound a list or a vector but not a string or
;;;; an integer, so a value of any size must still produce bounded text.

(defpackage #:cl-spec/tests/utils/printing-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/utils/printing
                #:with-bounded-printing #:abbreviate-for-print #:condition-report-text)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validate)
  (:import-from #:cl-spec/src/explain #:explain)
  (:import-from #:cl-spec/src/conditions #:spec-violation)
  (:import-from #:cl-spec/src/registry)
  (:import-from #:cl-spec/src/dsl)
  (:import-from #:cl-spec/src/property-runner)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/utils/printing-test)

(defun printed (value)
  "Return VALUE as WITH-BOUNDED-PRINTING and ABBREVIATE-FOR-PRINT print it."
  (with-bounded-printing (:one-line t)
    (prin1-to-string (abbreviate-for-print value))))

(defun violation-report (spec value)
  "Return the report of the SPEC-VIOLATION that validating VALUE against SPEC signals."
  (handler-case (progn (validate (normalize-spec-form spec) value) nil)
    (spec-violation (condition) (princ-to-string condition))))

(defun explanation (spec value)
  "Return the text EXPLAIN prints for VALUE against SPEC."
  (with-output-to-string (stream)
    (explain (normalize-spec-form spec) value :stream stream)))

(deftest small-values-print-unchanged
  (testing "ordinary values print exactly as the printer prints them"
    (dolist (value (list "abc" 12345 '(1 "two" (3 4)) #(1 2 3) :key nil 1.5d0))
      (ok (string= (printed value)
                   (with-bounded-printing (:one-line t) (prin1-to-string value))))))
  (testing "a circular list keeps its #N= labels"
    (let ((value (list 1 2)))
      (setf (cdr (last value)) value)
      (ok (search "#1=" (printed value)))))
  (testing "a list longer than *PRINT-LENGTH* still ends in ..."
    (ok (search "..." (printed (make-list 100 :initial-element 1))))))

(deftest large-strings-and-integers-print-bounded
  (let ((string (make-string 1000000 :initial-element #\x))
        (integer (ash 1 100000)))
    (testing "a long string prints as a bounded summary naming its length"
      (let ((text (printed string)))
        (ok (< (length text) 2000))
        (ok (search "1000000" text))))
    (testing "a long string inside a list is bounded too"
      (ok (< (length (printed (list 1 string))) 2000)))
    (testing "a huge integer prints as a summary naming its size"
      (let ((text (printed integer)))
        (ok (< (length text) 2000))
        (ok (search "100001" text))))))

(deftest other-atoms-the-printer-prints-whole-are-bounded
  ;; Ratios, complexes, bit vectors and symbol names are printed whole whatever
  ;; *PRINT-LENGTH* says, as strings and integers are.
  (dolist (value (list (/ (ash 1 100000) 3)
                       (/ 1 (1+ (ash 1 100000)))
                       (complex (ash 1 100000) 1)
                       (make-array 100000 :element-type 'bit :initial-element 1)
                       (make-symbol (make-string 100000 :initial-element #\y))))
    (testing (format nil "a ~S prints as a bounded summary" (type-of value))
      (ok (< (length (printed value)) 2000))))
  (testing "small ones print unchanged"
    (dolist (value (list 2/3 #c(1 2) #*0101 'small-symbol))
      (ok (string= (printed value)
                   (with-bounded-printing (:one-line t) (prin1-to-string value)))))))

(deftest reports-and-explanations-of-large-values-are-bounded
  (let ((string (make-string 1000000 :initial-element #\x)))
    (testing "a SPEC-VIOLATION report"
      (ok (< (length (violation-report '(list-of integer) (list string))) 2000)))
    (testing "EXPLAIN's text"
      (ok (< (length (explanation '(list-of integer) string)) 2000)))
    (testing "EXPLAIN of a huge integer out of range returns promptly with short text"
      (let ((start (get-internal-real-time))
            (text (explanation '(range integer 0 10) (ash 1 1000000))))
        (ok (< (length text) 2000))
        (ok (< (- (get-internal-real-time) start)
               (* 2 internal-time-units-per-second)))))
    (testing "a condition report quoting a huge argument"
      (let ((condition (make-condition 'simple-error :format-control "boom ~A"
                                                     :format-arguments (list string))))
        (ok (< (length (condition-report-text condition)) 20000))))))

(defun loud-failure (x)
  "Signal an error whose report quotes a million characters."
  (declare (ignore x))
  (error "boom ~A" (make-string 1000000 :initial-element #\x)))

(deftest a-trial-records-a-bounded-condition-report
  ;; The report a trial observation keeps was rendered unbounded, so one failing
  ;; trial put a megabyte into every result record and artifact.
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty loud-property ((x integer)) (loud-failure x)))
    (let* ((data (cl-spec/src/property-runner:result-data
                  (cl-spec/src/property-runner:run-property 'loud-property :seed 1)))
           (report (getf (getf data :failure) :condition-report)))
      (ok (stringp report))
      (ok (and (stringp report) (< (length report) 20000)))
      (ok (and (stringp report) (search "boom xxx" report))))))
