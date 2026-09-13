;;;; tests/custom-shrinker-definition-test.lisp

(defpackage #:cl-spec/tests/custom-shrinker-definition-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/dsl #:defgenerator)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator #:custom-generator-function #:custom-generator-shrinker
                #:custom-generator-source-form #:custom-generator-documentation)
  (:import-from #:cl-spec/src/conditions #:invalid-generator-form)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:make-hash-table-registry #:find-generator)
  (:import-from #:cl-spec/src/schema #:definition-digest))

(in-package #:cl-spec/tests/custom-shrinker-definition-test)

(defun invalid-generator-p (thunk)
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (typep condition 'invalid-generator-form))))

(deftest shrinker-constructor-contract
  (ok (handler-case
          (typep (make-instance 'custom-generator :name 'draw
                               :function (lambda () 1) :shrinker #'list)
                 'custom-generator)
        (error () nil)))
  (dolist (shrinker '(17 list :wrong))
    (ok (invalid-generator-p
         (lambda () (make-instance 'custom-generator :name 'draw
                                   :function (lambda () 1) :shrinker shrinker)))))
  (multiple-value-bind (reader status) (find-symbol "CUSTOM-GENERATOR-SHRINKER" "CL-SPEC")
    (ok (eq :external status))
    (ok (and reader (fboundp reader)))))

(deftest malformed-shrinker-clauses-are-refused
  (dolist (form
           '((defgenerator draw () (:shrink . 3) 1)
             (defgenerator draw () (:shrink () nil) 1)
             (defgenerator draw () (:shrink (a b) nil) 1)
             (defgenerator draw () (:shrink (:value) nil) 1)
             (defgenerator draw () (:shrink (&rest value) nil) 1)
             (defgenerator draw () (:shrink (t) nil) 1)
             (defgenerator draw () (:shrink (value . tail) nil) 1)
             (defgenerator draw () (:shrink (value)) 1)
             (defgenerator draw () (:shrink (value) nil) (:shrink (value) nil) 1)
             (defgenerator draw () (:shrink (value) . tail) 1)))
    (ok (invalid-generator-p (lambda () (macroexpand-1 form))))))

(deftest cyclic-shrink-clauses-are-refused
  (let ((clause (list :shrink '(value) nil)))
    (setf (cddr clause) clause)
    (ok (invalid-generator-p
         (lambda () (macroexpand-1 (list 'defgenerator 'draw nil clause 1)))))))

(deftest existing-draw-body-semantics-remain
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator single-string () "generated")
    (defgenerator documented () "documentation" (declare (optimize (speed 0))) 17)
    (ok (equal "generated" (funcall (custom-generator-function (find-generator 'single-string)))))
    (ok (null (custom-generator-documentation (find-generator 'single-string))))
    (ok (= 17 (funcall (custom-generator-function (find-generator 'documented)))))
    (ok (equal "documentation" (custom-generator-documentation (find-generator 'documented))))))

(deftest dsl-draw-and-shrinker-functions-are-independent
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator shrinking-draw ()
      "A documented correlated generator."
      (:shrink (value) (declare (type integer value)) (list (1- value) 0))
      (declare (optimize (speed 0)))
      8)
    (let ((generator (find-generator 'shrinking-draw)))
      (ok (= 8 (funcall (custom-generator-function generator))))
      (ok (equal '(7 0) (funcall (custom-generator-shrinker generator) 8)))
      (ok (equal "A documented correlated generator."
                 (custom-generator-documentation generator)))))
  (let ((generator (make-instance 'custom-generator :name 'direct
                                  :function (lambda () 8) :shrinker #'list)))
    (ok (eq #'list (custom-generator-shrinker generator)))
    (ok (null (definition-digest generator)))))

(deftest shrinker-update-rolls-back
  (let* ((draw (lambda () 8))
         (generator (make-instance 'custom-generator :name 'draw :function draw
                                   :source-form '(defgenerator draw () 8))))
    (ok (invalid-generator-p
         (lambda () (reinitialize-instance generator :shrinker #'list))))
    (ok (eq draw (custom-generator-function generator)))
    (ok (equal '(defgenerator draw () 8) (custom-generator-source-form generator)))
    (ok (invalid-generator-p
         (lambda () (reinitialize-instance generator :function #'list
                                   :source-form '(replacement) :shrinker 42))))
    (ok (eq draw (custom-generator-function generator)))))

(deftest shrinker-presence-affects-declaration-digest
  (let* ((source '(defgenerator draw () 8))
         (plain (make-instance 'custom-generator :name 'draw :function (lambda () 8)
                               :source-form source))
         (shrinking (make-instance 'custom-generator :name 'draw :function (lambda () 8)
                                   :source-form source :shrinker #'list)))
    (ok (nth-value 1 (definition-digest plain)))
    (ok (not (equal (definition-digest plain) (definition-digest shrinking))))
    (reinitialize-instance plain :function (lambda () 8) :source-form source :shrinker #'list)
    (ok (equal (definition-digest plain) (definition-digest shrinking)))
    (let ((shrinker (custom-generator-shrinker plain)))
      (ok (invalid-generator-p
           (lambda () (reinitialize-instance plain :function #'list :source-form source
                                                  :shrinker 17))))
      (ok (eq shrinker (custom-generator-shrinker plain))))))
