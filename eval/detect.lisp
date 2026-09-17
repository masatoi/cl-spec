;;;; eval/detect.lisp
;;;;
;;;; Fresh-process detection driver for the fault-injection checks.  It loads
;;;; cl-spec from the source snapshot named by CL_SPEC_ROOT, registers the
;;;; self-specification bundle, runs one target, and reports the verdict in one
;;;; machine-readable line.  It exits 0 only when the observed status, reason and
;;;; phase match the expectation; a load failure, a missing dependency, a
;;;; timeout or an unhandled error never prints a matching DETECT-RESULT and is
;;;; therefore never counted as a detection.
;;;;
;;;; Environment:
;;;;   CL_SPEC_ROOT                 source snapshot to load (required)
;;;;   CL_SPEC_DETECT_KIND          contract | property (default contract)
;;;;   CL_SPEC_DETECT_NAME          target name, e.g. CL-SPEC:VALIDATE
;;;;   CL_SPEC_DETECT_EXPECT        pass | fail (default pass)
;;;;   CL_SPEC_DETECT_EXPECT_STATUS expected status keyword, or "any"
;;;;   CL_SPEC_DETECT_EXPECT_REASON expected reason keyword, or "any"
;;;;   CL_SPEC_DETECT_EXPECT_PHASE  expected failure phase keyword, or "any"
;;;;   CL_SPEC_DETECT_TRIALS        contract trial budget (default 20)
;;;;   CL_SPEC_DETECT_SCENARIO      optional registration scenario keyword
;;;;   CL_SPEC_DETECT_SEED          integer seed (default 1)

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

(defun detect-optional-symbol (name)
  "Read the expectation named by NAME, or NIL for an unset or \"any\" value."
  (let ((text (detect-env name)))
    (cond ((null text) nil)
          ((string-equal text "any") nil)
          (t (detect-symbol text)))))

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
       (want-status (detect-optional-symbol "CL_SPEC_DETECT_EXPECT_STATUS"))
       (want-reason (detect-optional-symbol "CL_SPEC_DETECT_EXPECT_REASON"))
       (want-phase (detect-optional-symbol "CL_SPEC_DETECT_EXPECT_PHASE"))
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
         ;; The default for a failing run is any non-pass, but a task names the
         ;; status it expects so an unexpected contract evaluation error is not
         ;; mistaken for the intended detection.
         (status-ok (if want-status
                        (eq status want-status)
                        (if (string= expect "fail")
                            (and (member status '(:failed :error)) t)
                            (eq status :passed))))
         (reason-ok (or (null want-reason) (eq reason want-reason)))
         (phase-ok (or (null want-phase) (eq phase want-phase)))
         (matched (and status-ok reason-ok phase-ok)))
    (format t (concatenate 'string
                           "DETECT-RESULT kind=~A name=~A status=~A phase=~A reason=~A "
                           "expect=~A want-status=~A want-reason=~A want-phase=~A matched=~A~%")
            kind name status phase reason expect want-status want-reason want-phase matched)
    (finish-output)
    (uiop:quit (if matched 0 1))))
