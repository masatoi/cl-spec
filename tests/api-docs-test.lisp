;;;; tests/api-docs-test.lisp

(defpackage #:cl-spec/tests/api-docs-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/api-docs
                #:api-doc-files
                #:collect-public-api
                #:public-api-packages
                #:undocumented-public-symbols))

(in-package #:cl-spec/tests/api-docs-test)

(deftest every-public-symbol-is-documented
  (testing "the generated reference has no blank entry to render"
    (ok (null (undocumented-public-symbols)))))

(deftest every-public-package-is-loaded
  (testing "each documented package resolves through its designator"
    (dolist (package (public-api-packages))
      (ok (find-package (getf package :package))))))

(deftest every-collected-symbol-is-classified
  (testing "no entry falls through to the catch-all kind"
    (dolist (package (collect-public-api))
      (dolist (entry (getf package :symbols))
        (ok (not (eq (getf entry :kind) :unknown)))))))

(deftest reference-covers-every-public-package
  (testing "the file list pairs one reference file with each public package"
    (let ((files (api-doc-files)))
      (ok (equal "docs/api/README.md" (caar files)))
      (ok (= (length files) (1+ (length (public-api-packages))))))))
