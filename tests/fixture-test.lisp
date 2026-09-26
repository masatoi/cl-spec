;;;; tests/fixture-test.lisp
(defpackage #:cl-spec/tests/fixture-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/fixture)
  (:import-from #:cl-spec/src/fixture-execution))
(in-package #:cl-spec/tests/fixture-test)

(defun fixture-symbol (name)
  (or (find-symbol name (or (find-package "CL-SPEC/SRC/FIXTURE")
                           (error "Fixture implementation is missing")))
      (error "Missing fixture symbol ~A" name)))

(defun make-test-fixture (setup cleanup)
  (make-instance (fixture-symbol "TRIAL-FIXTURE")
                 :recipe-name 'recipe :recipe-spec 'integer :version 1
                 :setup-function setup :cleanup-function cleanup
                 :setup-forms '((list recipe)) :cleanup-forms '(nil)))

(defun execute-fixture (fixture recipe callback)
  (funcall (or (find-symbol "CALL-WITH-FIXTURE"
                           (or (find-package "CL-SPEC/SRC/FIXTURE-EXECUTION")
                               (error "Fixture lifecycle is missing")))
              (error "Missing fixture lifecycle"))
           fixture recipe callback))

(deftest independent-contexts-and-cleanup
  (let ((contexts nil) (calls nil))
    (let ((fixture (make-test-fixture
                    (lambda (recipe context)
                      (push context contexts)
                      (setf (gethash :value context) (list recipe))
                      (gethash :value context))
                    (lambda (recipe context)
                      (declare (ignore recipe))
                      (push (gethash :value context) calls)
                      (clrhash context)))))
      (dotimes (i 2)
        (declare (ignore i))
        (let ((result (execute-fixture fixture 10
                                      (lambda (arguments) (incf (car arguments))))))
          (ok (= 11 (getf result :value)))
          (ok (eq :released (getf (getf result :lifecycle) :state)))))
      (ok (= 2 (length calls)))
      (ok (not (eq (first contexts) (second contexts)))))))

(deftest cleanup-after-partial-setup
  (let ((cleaned nil) (called nil))
    (let* ((fixture (make-test-fixture
                     (lambda (recipe context)
                       (setf (gethash :partial context) recipe)
                       (error "setup failed"))
                     (lambda (recipe context)
                       (setf cleaned (= recipe (gethash :partial context))))))
           (result (execute-fixture fixture 7 (lambda (args)
                                                (declare (ignore args)) (setf called t)))))
      (ok cleaned)
      (ok (not called))
      (ok (eq :fixture-setup-error (getf result :reason)))
      (ok (eq :released (getf (getf result :lifecycle) :state))))))

(deftest cleanup-error-preserves-evaluation
  (let* ((fixture (make-test-fixture
                   (lambda (recipe context) (declare (ignore context)) (list recipe))
                   (lambda (recipe context)
                     (declare (ignore recipe context)) (error "cleanup failed"))))
         (result (execute-fixture fixture 3 (lambda (args)
                                              (declare (ignore args)) :violation))))
    (ok (eq :violation (getf result :value)))
    (ok (eq :fixture-cleanup-error (getf result :reason)))
    (ok (eq :unknown (getf (getf result :lifecycle) :state)))))

(deftest cleanup-on-outward-throw
  (let ((cleaned 0))
    (let ((fixture (make-test-fixture
                    (lambda (recipe context) (declare (ignore context)) (list recipe))
                    (lambda (recipe context)
                      (declare (ignore recipe context)) (incf cleaned)))))
      (ok (eq :escaped
              (catch 'escape
                (execute-fixture fixture 1
                                 (lambda (args) (declare (ignore args))
                                   (throw 'escape :escaped))))))
      (ok (= cleaned 1)))))

(deftest invalid-recipe-never-starts-fixture
  (let ((calls 0))
    (let* ((fixture (make-test-fixture
                     (lambda (recipe context)
                       (declare (ignore recipe context)) (incf calls))
                     (lambda (recipe context)
                       (declare (ignore recipe context)) (incf calls))))
           (result (execute-fixture fixture (make-hash-table) #'identity)))
      (ok (eq :fixture-recipe-invalid (getf result :reason)))
      (ok (zerop calls)))))

(deftest fixture-hook-update-requires-matching-source
  (let ((fixture (make-test-fixture
                  (lambda (recipe context) (declare (ignore context)) (list recipe))
                  (lambda (recipe context) (declare (ignore recipe context)) nil))))
    (ok (handler-case
            (progn (reinitialize-instance fixture :setup-function #'identity) nil)
          (error () t)))
    (ok (handler-case
            (progn (reinitialize-instance fixture :recipe-name 'different-name) nil)
          (error () t)))))

(deftest cleanup-hook-is-captured-before-setup
  (let ((fixture nil) (old-cleanups 0) (new-cleanups 0))
    (setf fixture
          (make-test-fixture
           (lambda (recipe context)
             (declare (ignore context))
             (reinitialize-instance fixture
                                    :cleanup-forms '(nil)
                                    :cleanup-function
                                    (lambda (recipe context)
                                      (declare (ignore recipe context))
                                      (incf new-cleanups)))
             (list recipe))
           (lambda (recipe context) (declare (ignore recipe context))
             (incf old-cleanups))))
    (execute-fixture fixture 1 #'identity)
    (ok (= 1 old-cleanups))
    (ok (zerop new-cleanups))))

(deftest fixture-update-rolls-back
  (let ((fixture (make-test-fixture
                  (lambda (recipe context) (declare (ignore context)) (list recipe))
                  (lambda (recipe context) (declare (ignore recipe context)) nil))))
    (ok (handler-case (progn (reinitialize-instance fixture :version 0) nil)
          (error () t)))
    (ok (= 1 (funcall (fixture-symbol "FIXTURE-VERSION") fixture)))))