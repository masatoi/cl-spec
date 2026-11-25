;;;; src/backends/check-it-numbers.lisp
;;;;
;;;; Numeric type intervals and finite shrinking for real-valued generators.

(defpackage #:cl-spec/src/backends/check-it-numbers
  (:use #:cl)
  (:import-from #:check-it #:generator #:generate #:regenerate #:shrink #:cached-value)
  (:import-from #:cl-spec/src/conditions #:generator-unavailable)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/utils/numbers #:finite-real-p)
  (:export #:float-type-p #:compound-numeric-interval #:interval-endpoint
           #:+default-type-size+ #:relative-numeric-bounds #:float-range-generator
           #:rational-range-generator #:make-shrinking-number-generator))

(in-package #:cl-spec/src/backends/check-it-numbers)

(defconstant +default-type-size+ 10
  "Fixed magnitude for the new unconstrained numeric types, independent of other arguments.")

(defun float-type-p (type)
  "Return true for FLOAT and its standard format names."
  (member type '(float short-float single-float double-float long-float)))

(defun interval-endpoint (bound)
  "Return the endpoint of an inclusive or exclusive interval bound."
  (if (consp bound) (first bound) bound))

(defun compound-numeric-interval (type)
  "Return (VALUES BASE LOWER UPPER) for a supported compound Common Lisp numeric type.
An exclusive integer endpoint becomes inclusive. A floating endpoint keeps its
exclusivity until the final sampling format is known."
  (when (and (consp type)
             (or (eq (first type) 'integer) (float-type-p (first type)))
             (finite-list-p type)
             (<= (length type) 3))
    (destructuring-bind (base &optional (lower '*) (upper '*)) type
      (flet ((valid-bound-p (bound)
               (and (or (atom bound) (null (rest bound)))
                    (let ((endpoint (interval-endpoint bound)))
                      (or (eq bound '*)
                          (case base
                            (integer (integerp endpoint))
                            (t (and (finite-real-p endpoint) (typep endpoint base))))))))
             (convert (bound step)
               (cond ((eq bound '*) :unbounded)
                     ((and (eq base 'integer) (consp bound)) (funcall step (first bound)))
                     (t bound))))
        (when (and (valid-bound-p lower) (valid-bound-p upper))
          (values base (convert lower #'1+) (convert upper #'1-)))))))

(defun relative-numeric-bounds (lower upper)
  "Fill missing endpoints near zero or the one given endpoint, using exact arithmetic."
  (values (or lower (if upper (- upper (max (abs upper) +default-type-size+))
                       (- +default-type-size+)))
          (or upper (if lower (+ lower (max (abs lower) +default-type-size+))
                       +default-type-size+))))

(defclass shrinking-number-generator (generator)
  ((draw :initarg :draw :reader draw-number)
   (lower :initarg :lower :reader number-lower-bound)
   (upper :initarg :upper :reader number-upper-bound)
   (encode :initarg :encode :reader encode-number))
  (:documentation "Draw real values and try a finite set of simpler numeric candidates."))

(defun make-shrinking-number-generator (draw lower upper &optional (encode #'identity))
  "Wrap DRAW with finite numeric shrinking between LOWER and UPPER, either of which may be NIL.
ENCODE converts proposed exact rational candidates to the generator's output format."
  (make-instance 'shrinking-number-generator :draw draw :lower lower :upper upper :encode encode))

(defmethod generate ((generator shrinking-number-generator))
  (funcall (draw-number generator)))

(defmethod regenerate ((generator shrinking-number-generator))
  (cached-value generator))

(defun practical-float-exponent-p (number)
  "Return true when NUMBER can be converted to a rational without an enormous shift."
  ;; On CLISP, a long float can encode a shift of more than two billion
  ;; bits. Allow exact arithmetic through the range of binary128.
  (or (not (floatp number)) (<= (abs (nth-value 1 (decode-float number))) 16496)))

(defun rational-complexity (number)
  "Measure the size of the numerator and denominator of NUMBER."
  (+ (abs (numerator number)) (denominator number)))

(defun simple-number-p (candidate original complexity)
  "Return true if CANDIDATE has a simpler rational representation than ORIGINAL."
  (let ((new-complexity (rational-complexity (rationalize candidate))))
    (or (< new-complexity complexity)
        (and (= new-complexity complexity) (rationalp candidate) (floatp original)))))

(defmethod shrink ((generator shrinking-number-generator) test)
  "Try small fractions, then rounded values and endpoints, preserving the observed failure."
  (let ((original (cached-value generator))
        (lower (number-lower-bound generator))
        (upper (number-upper-bound generator))
        (seen (make-hash-table :test #'eql)))
    (unless (practical-float-exponent-p original)
      (return-from shrink original))
    (let ((exact (rational original))
          (direction (if (minusp original) -1 1))
          (complexity (rational-complexity (rationalize original))))
      (labels ((admitted-p (number)
                 (and (or (null lower) (<= lower number))
                      (or (null upper) (<= number upper))))
               (try (number)
                 (when (and number (practical-float-exponent-p number) (admitted-p number))
                   (let ((candidate (funcall (encode-number generator) number)))
                     (unless (gethash candidate seen)
                       (setf (gethash candidate seen) t)
                       (when (and (not (eql candidate original))
                                  (admitted-p candidate)
                                  (practical-float-exponent-p candidate)
                                  (simple-number-p candidate original complexity)
                                  (not (funcall test candidate)))
                         (return-from shrink (setf (cached-value generator) candidate))))))))
        (loop for cost from 1 to 12
              do (loop for denominator from 1 to cost
                       for numerator = (* direction (- cost denominator))
                       do (try (/ numerator denominator))))
        (loop for denominator in '(1 2 3 4 5 8 10 16 32 64 128 256)
              for scaled = (* exact denominator)
              do (try (/ (truncate scaled) denominator))
                 (try (/ (round scaled) denominator)))
        (try lower)
        (try upper)
        original))))

(defun interval-fraction ()
  "Draw an exact random unit step including both endpoints."
  (/ (random (1+ (ash 1 24))) (ash 1 24)))

(defun rational-range-generator (lower upper)
  "Generate exact rationals, using small numerators and denominators by default."
  (if (and lower upper (= lower upper))
      (rational lower)
      (make-shrinking-number-generator
       (if (or lower upper)
           (multiple-value-bind (start end)
               (relative-numeric-bounds (and lower (rational lower)) (and upper (rational upper)))
             (lambda () (+ start (* (interval-fraction) (- end start)))))
           (lambda () (/ (- (random (1+ (* 2 +default-type-size+))) +default-type-size+)
                         (1+ (random +default-type-size+)))))
       lower upper)))

(defun float-format-bounds (type)
  "Return the format's zero, smallest positive, smallest normal and largest positive floats."
  (ecase type
    (short-float
     (values 0s0 least-positive-short-float least-positive-normalized-short-float
             most-positive-short-float))
    ((float single-float)
     (values 0f0 least-positive-single-float least-positive-normalized-single-float
             most-positive-single-float))
    (double-float
     (values 0d0 least-positive-double-float least-positive-normalized-double-float
             most-positive-double-float))
    (long-float
     (values 0l0 least-positive-long-float least-positive-normalized-long-float
             most-positive-long-float))))

(defun float-value (number zero least)
  "Round a finite rational to the format of ZERO, treating underflow as zero."
  (if (< (abs number) least)
      zero
      (handler-case (float number zero)
        (floating-point-underflow () zero))))

(defun float-neighbor (number direction zero least normal greatest)
  "Step one representable value from NUMBER in DIRECTION, or return NIL at the limit."
  (let ((magnitude (abs number))
         (toward-zero-p (= (signum number) (- direction))))
    (cond
      ((zerop number) (* direction least))
      ((and toward-zero-p (= magnitude least)) zero)
      ((and (not toward-zero-p) (= magnitude greatest)) nil)
      (t
       (multiple-value-bind (fraction exponent) (decode-float magnitude)
         (let* ((radix (float-radix number))
                ;; Immediately below a radix power the spacing is smaller by one radix step.
                (power-boundary-p (and toward-zero-p (= fraction (/ radix))))
                (spacing (expt radix (- exponent (float-digits number)
                                        (if power-boundary-p 1 0))))
                (step (if (< least normal) (max (rational least) spacing) spacing)))
           (float-value (+ (rational number) (* direction step)) zero least)))))))

(defun directed-float-endpoint (number open-p direction zero least normal greatest)
  "Round NUMBER inward to this format, stepping once more when an exact endpoint is open."
  (cond
    ((> number greatest) (when (= direction -1) greatest))
    ((< number (- greatest)) (when (= direction 1) (- greatest)))
    (t
     (let ((rounded (float-value number zero least)))
       (if (or (and (= direction 1) (< rounded number))
               (and (= direction -1) (> rounded number))
               (and open-p (= rounded number)))
           (float-neighbor rounded direction zero least normal greatest)
           rounded)))))

(defun exact-float-endpoint (number spec)
  "Convert a declared finite endpoint exactly when the conversion is practical."
  (unless (practical-float-exponent-p number)
    (error 'generator-unavailable :spec spec :kind :range-too-wide
           :reason "the float endpoint exceeds the range of exact interval arithmetic"))
  (rational number))

(defun float-range-generator (type minimum maximum spec)
  "Generate and shrink floats in the requested format and interval."
  ;; Use the widest format for a bounded generic FLOAT. For an unbounded
  ;; generic FLOAT, ordinary single-float values are sufficient.
  (when (and (floatp minimum) (floatp maximum) (= minimum maximum)
             (typep minimum type))
    (return-from float-range-generator minimum))
  (let* ((lower (unless (eq minimum :unbounded)
                  (exact-float-endpoint (interval-endpoint minimum) spec)))
         (upper (unless (eq maximum :unbounded)
                  (exact-float-endpoint (interval-endpoint maximum) spec)))
         (format-type (if (and (eq type 'float) (or lower upper)) 'long-float type)))
    (multiple-value-bind (start end) (relative-numeric-bounds lower upper)
      (multiple-value-bind (zero least normal greatest) (float-format-bounds format-type)
        (let ((low (directed-float-endpoint start (consp minimum) 1 zero least normal greatest))
              (high (directed-float-endpoint end (consp maximum) -1 zero least normal greatest)))
          (cond
            ((or (null low) (null high) (> low high))
             (error 'generator-unavailable :spec spec :kind :empty-domain
                    :reason (format nil "no ~S lies between the type's endpoints" type)))
            ((= low high) low)
            (t
             (let* ((first (if (practical-float-exponent-p low) (rational low) start))
                    (last (if (practical-float-exponent-p high) (rational high) end))
                    (width (- last first))
                    (encode (lambda (number) (float-value number zero least))))
               (make-shrinking-number-generator
                (lambda ()
                  (let ((number (+ first (* (interval-fraction) width))))
                    (cond ((< number low) low)
                          ((> number high) high)
                          (t (min high (max low (funcall encode number)))))))
                low high encode)))))))))
