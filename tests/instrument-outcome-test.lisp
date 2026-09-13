;;;; tests/instrument-outcome-test.lisp

(defpackage #:cl-spec/tests/instrument-outcome-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main #:*registry* #:make-hash-table-registry
                #:defspec-function)
  (:import-from #:cl-spec/instrument #:instrument-function #:uninstrument-function))

(in-package #:cl-spec/tests/instrument-outcome-test)

(defun restartable-target ()
  (restart-case (error "recoverable")
    (recover () (values 10 :resumed))))

(deftest instrumentation-preserves-active-target-restarts
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function restartable-target (:args) (:returns integer))
    (unwind-protect
         (progn
           (instrument-function 'restartable-target)
           (let* ((seen nil)
                  (results
                    (handler-bind ((simple-error
                                     (lambda (condition)
                                       (declare (ignore condition))
                                       (setf seen (not (null (find-restart 'recover))))
                                       (invoke-restart 'recover))))
                      (multiple-value-list (restartable-target)))))
             (ok (equal '(10 :resumed) results))
             (ok seen)))
      (uninstrument-function 'restartable-target))))
