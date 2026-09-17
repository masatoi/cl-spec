;;;; eval/detect.lisp
;;;;
;;;; Fresh-process detection driver for the fault-injection checks.  It loads
;;;; cl-spec from the source snapshot named by CL_SPEC_ROOT, registers the
;;;; self-specification bundle, runs one target, and reports the verdict in one
;;;; machine-readable line.  It exits 0 when the verdict matches the expectation
;;;; and 1 otherwise; a load failure, a missing dependency or a timeout never
;;;; prints DETECT-RESULT and is therefore never counted as a detection.
;;;;
;;;; Environment:
;;;;   CL_SPEC_ROOT             source snapshot to load (required)
;;;;   CL_SPEC_DETECT_KIND      contract | property (default contract)
;;;;   CL_SPEC_DETECT_NAME      target name, e.g. CL-SPEC:VALIDATE
;;;;   CL_SPEC_DETECT_EXPECT    pass | fail (default pass)
;;;;   CL_SPEC_DETECT_TRIALS    contract trial budget (default 20)
;;;;   CL_SPEC_DETECT_SCENARIO  optional registration scenario keyword
;;;;   CL_SPEC_DETECT_SEED      integer seed (default 1)

(in-package #:cl-user)

(load (merge-pathnames "snapshot-loader.lisp" *load-truename*))

(defun detect-env (name &optional default)
  (let ((value (uiop:getenv name)))
    (if (and value (plusp (length value))) value default)))

(defun detect-symbol (text)
  (multiple-value-bind (symbol position) (read-from-string text)
    (unless (and (symbolp symbol) (= position (length text)))
      (error "Not a single symbol name: ~S" text))
    symbol))

(defun bind-registration-scenario (trials)
  "Bind the fixtures' scripted registration scenario for a deterministic contract run."
  (let ((scenario (detect-env "CL_SPEC_DETECT_SCENARIO")))
    (when scenario
      (let ((special (find-symbol "*SCRIPTED-REGISTRATION-SCENARIOS*"
                                  "CL-SPEC/SELF-SPEC-FIXTURES")))
        (unless special
          (error "The self-spec fixtures package is not loaded"))
        (set special (loop repeat trials
                           collect (intern (string-upcase scenario) :keyword)))))))

(load-snapshot (snapshot-root))

(let* ((kind (string-downcase (detect-env "CL_SPEC_DETECT_KIND" "contract")))
       (name (detect-symbol (or (detect-env "CL_SPEC_DETECT_NAME")
                                (error "CL_SPEC_DETECT_NAME is not set"))))
       (expect (string-downcase (detect-env "CL_SPEC_DETECT_EXPECT" "pass")))
       (seed (or (parse-integer (detect-env "CL_SPEC_DETECT_SEED" "1") :junk-allowed t) 1))
       (trials (or (parse-integer (detect-env "CL_SPEC_DETECT_TRIALS" "20") :junk-allowed t)
                   20)))
  (bind-registration-scenario trials)
  (let* ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
         (result
           (progn
             (cl-spec/specs:register-specifications)
             (if (string= kind "property")
                 (cl-spec:run-property name :seed seed)
                 (cl-spec:check-function name :trials trials :seed seed))))
         (status (cl-spec:property-result-status result))
         (phase (cl-spec:property-result-failure-phase result))
         (reason (cl-spec:property-result-failure-reason result))
         (non-pass (and (member status '(:failed :error)) t))
         (matched (if (string= expect "fail")
                      non-pass
                      (eq status :passed))))
    (format t "DETECT-RESULT kind=~A name=~A status=~A phase=~A reason=~A expect=~A matched=~A~%"
            kind name status phase reason expect matched)
    (finish-output)
    (uiop:quit (if matched 0 1))))
