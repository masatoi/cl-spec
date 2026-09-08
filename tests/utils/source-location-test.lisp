;;;; tests/utils/source-location-test.lisp

(defpackage #:cl-spec/tests/utils/source-location-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/utils/source-location
                #:current-source-location
                #:source-location-file
                #:source-location-package))

(in-package #:cl-spec/tests/utils/source-location-test)

(deftest current-source-location-shape
  (testing "returns a plist carrying :FILE and :PACKAGE"
    (let ((location (current-source-location)))
      (ok (listp location))
      (ok (evenp (length location)))
      (ok (equal (package-name *package*) (getf location :package))))))

(deftest source-location-readers
  (testing "readers project the plist without knowing its layout"
    (let ((location (list :file "/tmp/example.lisp" :package "EXAMPLE")))
      (ok (equal "/tmp/example.lisp" (source-location-file location)))
      (ok (equal "EXAMPLE" (source-location-package location))))))

(deftest source-location-readers-tolerate-nil
  (testing "a missing location reads as NIL rather than signalling"
    (ok (null (source-location-file nil)))
    (ok (null (source-location-package nil)))))

(deftest current-source-location-file-outside-a-file
  (testing "evaluated outside COMPILE-FILE and LOAD the file entry is NIL"
    (let ((*compile-file-truename* nil)
          (*load-truename* nil))
      (ok (null (source-location-file (current-source-location)))))))
