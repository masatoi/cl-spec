;;;; tests/multiple-values-instrument-test.lisp

(defpackage #:cl-spec/tests/multiple-values-instrument-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/main #:*registry* #:make-hash-table-registry #:defspec-function)
  (:import-from #:cl-spec/instrument #:instrument-function #:uninstrument-function
                #:instrumentation-violation #:instrumentation-violation-scope))

(in-package #:cl-spec/tests/multiple-values-instrument-test)

(defvar *calls* 0)

(defun returned-values (values)
  (incf *calls*)
  (values-list values))

(defun restartable-values ()
  (incf *calls*)
  (restart-case (error "recoverable")
    (recover () (values 10 :resumed))))

(deftest fixed-values-wrapper-preserves-count-order-and-primary-post
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defspec-function returned-values
      (:args (items (list-of t)))
      (:returns (values integer boolean))
      (:post (= result (first items))))
    (unwind-protect
         (progn
           (instrument-function 'returned-values)
           (ok (equal '(10 nil) (multiple-value-list (returned-values '(10 nil)))))
           (ok (= 1 *calls*))
           (dolist (bad '(nil (nil) (10) (10 t :extra) (10 :wrong) (:wrong t)))
             (ok (signals (returned-values bad) 'instrumentation-violation)))
           (ok (= 7 *calls*)))
      (uninstrument-function 'returned-values))))

(deftest zero-values-contract-distinguishes-one-nil
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defspec-function returned-values (:args (items (list-of t))) (:returns (values)))
    (unwind-protect
         (progn
           (instrument-function 'returned-values)
           (ok (null (multiple-value-list (returned-values nil))))
           (ok (signals (returned-values '(nil)) 'instrumentation-violation))
           (ok (= 2 *calls*)))
      (uninstrument-function 'returned-values))))

(deftest explicit-post-values-checks-relations-and-respects-scopes
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function returned-values
      (:args (items (list-of t)))
      (:returns (values integer integer))
      (:post-values (low high) (and (= result low) (< low high))))
    (unwind-protect
         (progn
           (instrument-function 'returned-values)
           (ok (equal '(1 2) (multiple-value-list (returned-values '(1 2)))))
           (let ((condition (handler-case (returned-values '(2 1))
                              (instrumentation-violation (condition) condition))))
             (ok (typep condition 'instrumentation-violation))
             (ok (eq :post (instrumentation-violation-scope condition))))
           (uninstrument-function 'returned-values)
           (instrument-function 'returned-values :scopes '(:output))
           (ok (equal '(2 1) (multiple-value-list (returned-values '(2 1))))))
      (uninstrument-function 'returned-values))))

(deftest post-only-scope-binds-available-values-without-enforcing-return-count
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function returned-values
      (:args (items (list-of t)))
      (:returns (values integer integer))
      (:post-values (low high)
        (and (= low (first items)) (eql high (second items)))))
    (unwind-protect
         (progn
           (instrument-function 'returned-values :scopes '(:post))
           (ok (equal '(1) (multiple-value-list (returned-values '(1)))))
           (ok (equal '(1 2 :extra)
                      (multiple-value-list (returned-values '(1 2 :extra))))))
      (uninstrument-function 'returned-values))))

(deftest fixed-values-wrapper-preserves-active-restarts
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defspec-function restartable-values
      (:args) (:returns (values integer (member :resumed))))
    (unwind-protect
         (progn
           (instrument-function 'restartable-values)
           (let ((result
                   (handler-bind ((simple-error
                                    (lambda (condition)
                                      (declare (ignore condition))
                                      (invoke-restart 'recover))))
                     (multiple-value-list (restartable-values)))))
             (ok (equal '(10 :resumed) result))
             (ok (= 1 *calls*))))
      (uninstrument-function 'restartable-values))))

(deftest fixed-values-wrapper-preserves-return-object-identity
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function returned-values
      (:args (items (list-of t)))
      (:returns (values cons cons))
      (:post-values (first second)
        (and (eq first (first items)) (eq second (second items)))))
    (let* ((shared (list :original))
           (raw (list shared shared)))
      (unwind-protect
           (progn
             (instrument-function 'returned-values)
             (let ((observed (multiple-value-list (returned-values raw))))
               (ok (eq shared (first observed)))
               (ok (eq shared (second observed)))))
        (uninstrument-function 'returned-values)))))
