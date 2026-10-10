;;;; tests/error-message-test.lisp
;;;;
;;;; A condition's REASON is printed with ~A, so a reason string is plain text,
;;;; not a FORMAT control string.  A literal written with ~<newline> line
;;;; continuation, as a FORMAT control would be, prints the tilde, the newline
;;;; and the next line's indentation.  Each case below reaches one such reason
;;;; and checks that its report reads as one sentence.

(defpackage #:cl-spec/tests/error-message-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/function-spec
                #:function-case #:function-spec)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/generator
                #:sample)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/error-message-test)

(defstruct message-point
  "A structure an OBJECT-OF spec can observe but cl-spec cannot construct."
  x)

(defun report-of (thunk)
  "Return the printed report of the error THUNK signals, or NIL when it returns."
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (princ-to-string condition))))

(defun plain-sentence-p (report phrase)
  "True when REPORT contains PHRASE and no unprocessed FORMAT continuation."
  (and report
       (null (find #\~ report))
       (null (find #\Newline report :start (or (search "is not a valid" report) 0)))
       (search phrase report)))

(deftest reasons-print-as-plain-sentences
  (testing "DEFSPEC-FUNCTION refusing :cases beside a top-level outcome"
    (ok (plain-sentence-p
         (report-of (lambda ()
                      (macroexpand-1 '(cl-spec:defspec-function f
                                       (:args (x integer))
                                       (:returns integer)
                                       (:cases (:a (:when t) (:returns integer)))))))
         ":post, :post-values or :state-post; each case rules its own outcome")))
  (testing "a FUNCTION-SPEC built with :cases beside its own outcome"
    (ok (plain-sentence-p
         (report-of (lambda ()
                      (make-instance
                       'function-spec
                       :name 'f :argument-specs '((x integer)) :return-spec 'integer
                       :cases (list (make-instance
                                     'function-case
                                     :name :a :when-forms '(t)
                                     :when-function (lambda (x) (declare (ignore x)) t)
                                     :outcome-kind :returns :outcome-spec 'integer
                                     :source-form '(:a (:when t) (:returns integer)))))))
         ":post, :post-values or :state-post; there is no inherited common outcome")))
  (testing "an unknown spec head"
    (ok (plain-sentence-p
         (report-of (lambda () (normalize-spec-form '(no-such-head 1))))
         "write (type ...) or (instance-of ...) for a user-defined type, or reference")))
  (testing "generating an OBJECT-OF spec without a custom generator"
    (ok (plain-sentence-p
         (report-of (lambda ()
                      (sample (normalize-spec-form
                               '(object-of message-point
                                 (:required (message-point-x integer))))
                              :count 1)))
         "cannot be constructed; declare a (:GENERATOR NAME) to draw instances"))))
