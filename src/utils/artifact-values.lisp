;;;; src/utils/artifact-values.lisp
(defpackage #:cl-spec/src/utils/artifact-values
  (:use #:cl)
  (:export #:encode-artifact-value #:decode-artifact-value
           #:serialize-artifact-value #:deserialize-artifact-value
           #:artifact-value-error #:artifact-value-error-reason))
(in-package #:cl-spec/src/utils/artifact-values)

(define-condition artifact-value-error (error)
  ((reason :initarg :reason :reader artifact-value-error-reason
           :documentation "The reason the artifact value was rejected."))
  (:documentation "An unsupported, malformed, or excessive artifact value."))

(defun value-error (reason)
  (error 'artifact-value-error :reason reason))

(defun check-bounds (max-nodes max-depth)
  (unless (and (typep max-nodes '(integer 1 1000000))
               (typep max-depth '(integer 1 256)))
    (value-error :invalid-bounds)))

(defun integer-text (value)
  (when (> (integer-length value) 13000) (value-error :integer-limit))
  (format nil "~D" value))

(defun text-integer (text)
  (unless (and (stringp text) (<= 1 (length text) 4096)
               (let ((start (if (char= (char text 0) #\-) 1 0)))
                 (and (< start (length text))
                      (loop for i from start below (length text)
                            always (digit-char-p (char text i) 10)))))
    (value-error :invalid-integer))
  (parse-integer text :radix 10))

(defun encode-artifact-value (value &key (max-nodes 10000) (max-depth 128))
  "Encode VALUE into a bounded tagged tree; reject sharing and cycles.
Depth counts nested elements, not the length of a list spine. Integers are
limited to 13000 bits. Traversal uses bounded work lists rather than recursion."
  (check-bounds max-nodes max-depth)
  (let* ((seen (make-hash-table :test #'eq)) (nodes 0) (queued 1) (text-size 0)
         (result (list nil)) (pending (list (list value 0 result))))
    (loop while pending
          do (destructuring-bind (object depth destination) (pop pending)
               (decf queued)
               (when (or (> (incf nodes) max-nodes) (> depth max-depth))
                 (value-error :structure-limit))
               (when (or (consp object) (vectorp object))
                 (when (gethash object seen) (value-error :sharing-or-cycle))
                 (setf (gethash object seen) t))
               (incf text-size
                     (typecase object
                       (string (length object))
                       (symbol (+ (length (symbol-name object))
                                  (if (symbol-package object)
                                      (length (package-name (symbol-package object))) 0)))
                       (integer (integer-length object))
                       (ratio (+ (integer-length (numerator object))
                                 (integer-length (denominator object))))
                       (float 128)
                       (t 0)))
               (when (> text-size 1000000) (value-error :text-limit))
               (setf
                (car destination)
                (typecase object
                  (null (list 0))
                  (symbol
                   (if (eq object t) (list 1)
                       (let ((package (symbol-package object)))
                         (unless (and package
                                      (eq object (find-symbol (symbol-name object) package)))
                           (value-error :unsupported-symbol))
                         (list 2 (copy-seq (package-name package))
                               (copy-seq (symbol-name object))))))
                  (character (list 3 (integer-text (char-code object))))
                  (integer (list 4 (integer-text object)))
                  (ratio (list 5 (integer-text (numerator object))
                               (integer-text (denominator object))))
                  (float
                   (unless (or (typep object 'single-float) (typep object 'double-float))
                     (value-error :unsupported-float))
                   (multiple-value-bind (significand exponent sign)
                       (handler-case (integer-decode-float object)
                         (error () (value-error :unsupported-float)))
                     (list 6 (if (typep object 'double-float) 1 0)
                           (integer-text significand) (integer-text exponent)
                           (integer-text sign))))
                  (simple-string
                   (when (> (length object) 1000000) (value-error :string-limit))
                   (list 7 (copy-seq object)))
                  (cons
                   (when (> 2 (- max-nodes nodes queued)) (value-error :structure-limit))
                   (incf queued 2)
                   (let ((record (list 8 nil nil)))
                     (push (list (cdr object) depth (cddr record)) pending)
                     (push (list (car object) (1+ depth) (cdr record)) pending)
                     record))
                  (simple-vector
                   (when (> (length object) (- max-nodes nodes queued))
                     (value-error :structure-limit))
                   (incf queued (length object))
                   (let ((record (cons 9 (make-list (length object)))))
                     (loop for element across object
                           for destination on (cdr record)
                           do (push (list element (1+ depth) destination) pending))
                     record))
                  (t (value-error :unsupported-value))))))
    (car result)))

(defun decode-artifact-value (data &key (max-nodes 10000) (max-depth 128))
  "Restore a bounded tagged tree without interning symbols or invoking the reader.
Depth counts nested elements; flat and dotted list spines do not consume depth."
  (check-bounds max-nodes max-depth)
  (let* ((seen (make-hash-table :test #'eq)) (nodes 0) (queued 1) (cells 0) (text-size 0)
         (result (list nil)) (pending (list (list data 0 result 0))))
    (labels ((record-fields (record)
               (unless (consp record) (value-error :invalid-record))
               (loop for tail = record then (cdr tail)
                     while tail
                     do (unless (and (consp tail) (not (gethash tail seen))
                                     (<= (incf cells) (* 8 max-nodes)))
                          (value-error :invalid-record))
                        (setf (gethash tail seen) t)
                     collect (car tail))))
      (loop while pending
            do (destructuring-bind (record depth destination index) (pop pending)
                 (decf queued)
                 (when (or (> (incf nodes) max-nodes) (> depth max-depth))
                   (value-error :structure-limit))
                 (let* ((fields (record-fields record)) (tag (first fields))
                        (args (rest fields)) (arity (length args)))
                   (unless (and (typep tag '(integer 0 9))
                                (or (= tag 9)
                                    (= arity (nth tag '(0 0 2 1 1 2 4 1 2)))))
                     (value-error :invalid-record))
                   (dolist (argument args)
                     (when (stringp argument) (incf text-size (length argument))))
                   (when (> text-size 1000000) (value-error :text-limit))
                   (let ((value
                           (case tag
                             (0 nil)
                             (1 t)
                             (2
                              (unless (every #'stringp args) (value-error :invalid-symbol))
                              (let ((package (find-package (first args))))
                                (unless package (value-error :missing-package))
                                (multiple-value-bind (symbol status)
                                    (find-symbol (second args) package)
                                  (unless status (value-error :missing-symbol))
                                  symbol)))
                             (3
                              (let* ((code (text-integer (first args)))
                                     (character (and (<= 0 code) (< code char-code-limit)
                                                     (code-char code))))
                                (or character (value-error :invalid-character))))
                             (4 (text-integer (first args)))
                             (5
                              (let ((n (text-integer (first args)))
                                    (d (text-integer (second args))))
                                (unless (> d 1) (value-error :invalid-ratio))
                                (let ((ratio (/ n d)))
                                  (unless (typep ratio 'ratio) (value-error :invalid-ratio))
                                  ratio)))
                             (6
                              (unless (member (first args) '(0 1)) (value-error :invalid-float))
                              (let ((prototype (if (= (first args) 1) 1d0 1f0))
                                    (significand (text-integer (second args)))
                                    (exponent (text-integer (third args)))
                                    (sign (text-integer (fourth args))))
                                (unless (and (<= 0 significand
                                                (1- (ash 1 (float-digits prototype))))
                                             (<= -1200 exponent 1200) (member sign '(-1 1)))
                                  (value-error :invalid-float))
                                (let ((number
                                        (handler-case
                                            (* (float sign prototype)
                                               (scale-float (float significand prototype) exponent))
                                          (error () (value-error :invalid-float)))))
                                  (multiple-value-bind (s e sign-value)
                                      (handler-case (integer-decode-float number)
                                        (error () (value-error :invalid-float)))
                                    (unless (and (= s significand) (= e exponent)
                                                 (= sign sign-value))
                                      (value-error :invalid-float)))
                                  number)))
                             (7
                              (let ((string (first args)))
                                (unless (and (typep string 'simple-string)
                                             (<= (length string) 1000000))
                                  (value-error :invalid-string))
                                (copy-seq string)))
                             (8
                              (when (> 2 (- max-nodes nodes queued))
                                (value-error :structure-limit))
                              (incf queued 2)
                              (let ((pair (cons nil nil)))
                                (push (list (second args) depth pair 1) pending)
                                (push (list (first args) (1+ depth) pair 0) pending)
                                pair))
                             (9
                              (when (> arity (- max-nodes nodes queued))
                                (value-error :structure-limit))
                              (incf queued arity)
                              (let ((vector (make-array arity)))
                                (loop for item in args for index from 0
                                      do (push (list item (1+ depth) vector index) pending))
                                vector)))))
                     (if (consp destination)
                         (if (zerop index)
                             (setf (car destination) value)
                             (setf (cdr destination) value))
                         (setf (aref destination index) value)))))))
    (car result)))

(defun serialize-artifact-value (value &key (max-chars 1000000)
                                          (max-nodes 10000) (max-depth 128))
  "Serialize VALUE to the AV1 wire format with bounded output and iterative traversal."
  (unless (typep max-chars '(integer 1 10000000)) (value-error :invalid-bounds))
  (let ((data (encode-artifact-value value :max-nodes max-nodes :max-depth max-depth))
        (count 0))
    (with-output-to-string (stream)
      (flet ((emit (text)
               (when (> (incf count (length text)) max-chars) (value-error :character-limit))
               (write-string text stream)))
        (emit "AV1 ")
        (let ((pending (list (cons :value data))))
          (loop while pending
                do (destructuring-bind (action . item) (pop pending)
                     (ecase action
                       (:value
                        (typecase item
                          (string (emit (format nil "~D:" (length item))) (emit item))
                          (integer (emit (integer-text item)))
                          (cons (emit "(") (push (cons :list item) pending))))
                       (:list
                        (push (cons :more (cdr item)) pending)
                        (push (cons :value (car item)) pending))
                       (:more
                        (if item
                            (progn (emit " ") (push (cons :list item) pending))
                            (emit ")")))))))))))

(defun deserialize-artifact-value (string &key (max-chars 1000000)
                                            (max-nodes 10000) (max-depth 128))
  "Parse AV1 without the Lisp reader, bounding semantic depth before allocating frames."
  (check-bounds max-nodes max-depth)
  (unless (and (typep max-chars '(integer 1 10000000)) (stringp string)
               (<= 4 (length string) max-chars) (string= string "AV1 " :end1 4))
    (value-error :invalid-wire))
  (let ((position 4) (size (length string)) (nodes 0) (items 0) (text-size 0)
        (frames nil) (result nil) (complete nil))
    ;; A frame stores logical depth, reversed fields, field count and the numeric tag.
    (labels ((peek () (and (< position size) (char string position)))
             (spaces () (loop while (eql (peek) #\Space) do (incf position)))
             (count-item ()
               (when (> (incf items) (* 8 max-nodes)) (value-error :structure-limit)))
             (child-depth ()
               (if (null frames) 0
                   (let* ((frame (first frames)) (depth (aref frame 0))
                          (count (aref frame 2)) (tag (aref frame 3)))
                     (cond
                       ((and (eql tag 8) (= count 1)) (1+ depth))
                       ((and (eql tag 8) (= count 2)) depth)
                       ((and (eql tag 9) (plusp count)) (1+ depth))
                       (t (value-error :invalid-record))))))
             (add-item (item record-p)
               (if frames
                   (let* ((frame (first frames)) (count (aref frame 2))
                          (tag (aref frame 3)))
                     (cond
                       ((zerop count)
                        (unless (and (not record-p) (typep item '(integer 0 9)))
                          (value-error :invalid-record))
                        (setf (aref frame 3) item))
                       (record-p
                        (unless (or (eql tag 9) (and (eql tag 8) (<= count 2)))
                          (value-error :invalid-record)))
                       (t
                        (unless (and (<= 2 tag 7)
                                     (<= count (nth tag '(0 0 2 1 1 2 4 1 2))))
                          (value-error :invalid-record))))
                     (push item (aref frame 1))
                     (incf (aref frame 2)))
                   (progn
                     (unless (and record-p (not complete)) (value-error :invalid-wire))
                     (setf result item complete t))))
             (parse-scalar ()
               (let ((number 0) (digits 0))
                 (count-item)
                 (loop while (and (peek) (digit-char-p (peek) 10))
                       do (when (> (incf digits) 8) (value-error :invalid-wire))
                          (setf number (+ (* number 10) (digit-char-p (peek) 10)))
                          (incf position))
                 (if (eql (peek) #\:)
                     (progn
                       (incf position)
                       (unless (<= number (- size position)) (value-error :invalid-wire))
                       (when (> (incf text-size number) 1000000) (value-error :text-limit))
                       (prog1 (subseq string position (+ position number))
                         (incf position number)))
                     (progn
                       (unless (or (null (peek)) (find (peek) " )"))
                         (value-error :invalid-wire))
                       number)))))
      (loop
        (spaces)
        (unless (peek) (return))
        (when complete (value-error :trailing-data))
        (cond
          ((eql (peek) #\()
           (let ((depth (child-depth)))
             (when (or (> depth max-depth) (> (incf nodes) max-nodes))
               (value-error :structure-limit))
             (count-item)
             (push (vector depth nil 0 nil) frames)
             (incf position)))
          ((eql (peek) #\))
           (unless frames (value-error :invalid-wire))
           (let* ((frame (pop frames)) (count (aref frame 2)) (tag (aref frame 3)))
             (unless (and (plusp count)
                          (or (eql tag 9)
                              (= count (1+ (nth tag '(0 0 2 1 1 2 4 1 2))))))
               (value-error :invalid-record))
             (incf position)
             (add-item (nreverse (aref frame 1)) t)))
          ((digit-char-p (peek) 10) (add-item (parse-scalar) nil))
          (t (value-error :invalid-wire))))
      (unless (and complete (null frames)) (value-error :invalid-wire))
      (decode-artifact-value result :max-nodes max-nodes :max-depth max-depth))))
