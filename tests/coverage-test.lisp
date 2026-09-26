;;;; tests/coverage-test.lisp
(defpackage #:cl-spec/tests/coverage-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/coverage
                #:normalize-coverage-options #:invalid-coverage-options)
  (:import-from #:cl-spec/src/coverage-plist #:plist-coverage-schema #:observe-dimension))
(in-package #:cl-spec/tests/coverage-test)

(defun schema (form &rest options)
  (plist-coverage-schema
   (list (list 'payload (cl-spec:normalize-spec-form form)))
   cl-spec:*registry* (or (getf options :limit) 1024) (or (getf options :depth) 32)))

(deftest coverage-options-are-bounded-and-closed
  (ok (null (normalize-coverage-options nil)))
  (ok (eq :observe (getf (normalize-coverage-options '(:mode :observe)) :mode)))
  (ok (equal '(:coverage-extra :probe-extra)
             (getf (normalize-coverage-options '(:mode :exercise)) :extra-keys)))
  (let ((cycle (list :mode :observe)))
    (setf (cddr cycle) cycle)
    (dolist (bad (list cycle '(:mode :bad) '(:mode :observe :extra-keys nil)
                      '(:mode :observe :mode :observe) '(:mode :observe :depth-limit 257)
                      '(:mode :exercise :extra-keys (:a :a))))
      (ok (handler-case (progn (normalize-coverage-options bad) nil)
            (invalid-coverage-options () t))))))

(deftest plist-dimensions-distinguish-presence-and-nil
  (let* ((data (schema '(plist (:optional (:memo t)))))
         (dims (getf data :dimensions))
         (presence (find :field-presence dims :key (lambda (d) (getf d :kind))))
         (extra (find :extra-key-presence dims :key (lambda (d) (getf d :kind)))))
    (ok (= 2 (length dims)))
    (ok (equal '(:present) (observe-dimension presence (list 'payload '(:memo nil)))))
    (ok (equal '(:absent) (observe-dimension presence (list 'payload '(:x :memo)))))
    (ok (equal '(:present) (observe-dimension extra (list 'payload '(:x :memo)))))
    (ok (eq :unknown (observe-dimension presence (list 'payload '(:memo 1 :memo 2)))))))

(deftest nested-coverage-has-stable-paths-and-applicability
  (let* ((data (schema '(plist (:optional (:child (plist (:optional (:memo t))))))))
         (inner (find-if (lambda (d) (equal '(:child :memo) (getf d :field-path)))
                         (getf data :dimensions))))
    (ok inner)
    (ok (eq :not-applicable (observe-dimension inner (list 'payload nil))))
    (ok (equal '(:present) (observe-dimension inner (list 'payload '(:child (:memo nil))))))))

(deftest coverage-boundaries-and-limits-are-explicit
  (let* ((data (schema '(plist (:required (:n (range integer 1 1))) (:closed t))))
         (dimension (first (getf data :dimensions))))
    (ok (= 1 (length (getf data :dimensions))))
    (ok (equal '(:lower :upper) (observe-dimension dimension (list 'payload '(:n 1)))))
    (ok (member :interior (getf dimension :inapplicable-buckets))))
  (ok (eq :partial (getf (schema '(plist (:optional (:a t) (:b t))) :limit 1) :discovery)))
  (ok (getf (schema '(list-of (plist (:optional (:a t))))) :unexpanded)))
