(in-package #:sys.int)

;;; The base stream class. All other stream classes should
;;; inherit from this to get basic functionallity.
(defclass stream-object (stream standard-object)
  ((unread-char :initform nil)))

(defstruct (synonym-stream
             (:constructor make-synonym-stream (symbol)))
  symbol)
(defclass synonym-stream (stream) ()) ; ick

(defvar *terminal-io* :terminal-io-is-uninitialized
  "A bi-directional stream connected to the user's console.")
(defparameter *debug-io* (make-synonym-stream '*terminal-io*)
  "Interactive debugging stream.")
(defparameter *error-output* (make-synonym-stream '*terminal-io*)
  "Warning and non-interactive error stream.")
(defparameter *query-io* (make-synonym-stream '*terminal-io*)
  "User interaction stream.")
(defparameter *standard-input* (make-synonym-stream '*terminal-io*)
  "Default input stream.")
(defparameter *standard-output* (make-synonym-stream '*terminal-io*)
  "Default output stream.")

(defun streamp (object)
  (or (synonym-stream-p object)
      (cold-stream-p object)
      (typep object 'stream-object)))

(setf (get 'stream 'type-symbol) 'streamp)

(defgeneric stream-read-char (stream))
(defgeneric stream-write-char (character stream))
(defgeneric stream-close (stream abort))
(defgeneric stream-listen (stream))
(defgeneric stream-clear-input (stream))
(defgeneric stream-start-line-p (stream))
(defgeneric stream-with-edit (stream fn))
(defgeneric stream-cursor-pos (stream))
(defgeneric stream-character-width (stream character))
(defgeneric stream-compute-motion (stream string &optional start end initial-x initial-y))
(defgeneric stream-clear-between (stream start-x start-y end-x end-y))
(defgeneric stream-move-to (stream x y))

(defun frob-stream (stream &optional (default :bad-stream))
  (cond ((synonym-stream-p stream)
         (frob-stream (symbol-value (synonym-stream-symbol stream)) default))
        ((eql stream 'nil)
         (frob-stream default default))
        ((eql stream 't)
         (frob-stream *terminal-io* default))
        ;; TODO: check that the stream is open.
        (t (check-type stream stream)
           stream)))

(defun frob-input-stream (stream)
  (frob-stream stream *standard-input*))

(defun frob-output-stream (stream)
  (frob-stream stream *standard-output*))

(defmacro with-stream-editor ((stream recursive-p) &body body)
  "Activate the stream editor functionality for STREAM."
  `(%with-stream-editor ,stream ,recursive-p (lambda () (progn ,@body))))

(defun %with-stream-editor (stream recursive-p fn)
  (cond ((synonym-stream-p stream)
         (%with-stream-editor (symbol-value (synonym-stream-symbol stream)) recursive-p fn))
        ((or (cold-stream-p stream) recursive-p)
         (funcall fn))
        (t (stream-with-edit stream fn))))

(defmethod stream-with-edit ((stream stream-object) fn)
  (funcall fn))

(defun read-char (&optional (stream *standard-input*) (eof-error-p t) eof-value recursive-p)
  (declare (ignore recursive-p))
  (let ((s (frob-input-stream stream)))
    (cond ((cold-stream-p s)
           (or (cold-read-char s)
               (when eof-error-p
                 (error 'end-of-file :stream s))
               eof-value))
          ((slot-value s 'unread-char)
           (prog1 (slot-value s 'unread-char)
             (setf (slot-value s 'unread-char) nil)))
          (t (or (stream-read-char s)
                 (when eof-error-p
                   (error 'end-of-file :stream s))
                 eof-value)))))

(defun read-line (&optional (input-stream *standard-input*) (eof-error-p t) eof-value recursive-p)
  (with-stream-editor (input-stream recursive-p)
    (do ((result (make-array 16 :element-type 'character :adjustable t :fill-pointer 0))
         (c (read-char input-stream eof-error-p nil recursive-p)
            (read-char input-stream eof-error-p nil recursive-p)))
        ((or (null c)
             (eql c #\Newline))
         (if (and (null c) (eql (length result) 0))
             (values eof-value t)
             (values result (null c))))
      (vector-push-extend c result))))

(defun unread-char (character &optional (stream *standard-input*))
  (let ((s (frob-input-stream stream)))
    (check-type character character)
    (cond ((cold-stream-p s)
           (cold-unread-char character stream))
          ((slot-value s 'unread-char)
           (error "Multiple unread-char!"))
          (t (setf (slot-value s 'unread-char) character)))
    nil))

(defun peek-char (&optional peek-type (stream *standard-input*) (eof-error-p t) eof-value recursive-p)
  (let ((s (frob-input-stream stream)))
    (cond ((eql peek-type nil)
           (let ((ch (read-char s eof-error-p eof-value recursive-p)))
             (unread-char ch s)
             ch))
          ((eql peek-type t)
           (do ((ch (read-char s eof-error-p eof-value recursive-p)
                    (read-char s eof-error-p eof-value recursive-p)))
               ((not (sys.int::whitespace[2]p ch))
                (unread-char ch s)
                ch)))
          ((characterp peek-type)
           (error "TODO: character peek."))
          (t (error "Bad peek type ~S." peek-type)))))

(defun clear-input (&optional (stream *standard-input*))
  (let ((s (frob-input-stream stream)))
    (cond ((cold-stream-p s)
           (cold-clear-input s))
          (t (setf (slot-value s 'unread-char) nil)
             (stream-clear-input s))))
  nil)

(defmethod stream-clear-input ((stream stream-object)))

(defun write-char (character &optional (stream *standard-output*))
  (let ((s (frob-output-stream stream)))
    (check-type character character)
    (cond ((cold-stream-p s)
           (cold-write-char character s))
          (t (stream-write-char character s)))
    character))

(defun start-line-p (&optional (stream *standard-output*))
  (let ((s (frob-output-stream stream)))
    (cond ((cold-stream-p s)
           (cold-start-line-p s))
          (t (stream-start-line-p s)))))

(defmethod stream-start-line-p ((stream stream-object))
  nil)

(defun close (stream &key abort)
  (let ((s (frob-stream stream)))
    (cond ((cold-stream-p s)
           (cold-close s abort))
          (t (stream-close s abort)))
    t))

(defmethod stream-close ((stream stream-object) abort)
  t)

(defun listen (&optional (input-stream *standard-input*))
  (let ((s (frob-input-stream input-stream)))
    (cond ((cold-stream-p s)
           (cold-listen s))
          ((slot-value s 'unread-char)
           t)
          (t (stream-listen s)))))

(defmethod stream-listen ((stream stream-object))
  t)

(defmethod print-object ((object synonym-stream) stream)
  (print-unreadable-object (object stream :type t)
    (format stream "for ~S" (synonym-stream-symbol object))))

(defclass string-output-stream (stream-object)
  ((element-type :initarg :element-type)
   (string :initform nil)))

(defun make-string-output-stream (&key (element-type 'character))
  (make-instance 'string-output-stream :element-type element-type))

(defun get-output-stream-string (string-output-stream)
  (check-type string-output-stream string-output-stream)
  (prog1 (or (slot-value string-output-stream 'string)
             (make-array 0 :element-type (slot-value stream 'element-type)))
    (setf (slot-value string-output-stream 'string) nil)))

(defun string-output-stream-write-char (character stream)
  (unless (slot-value stream 'string)
    (setf (slot-value stream 'string) (make-array 8
                                                  :element-type (slot-value stream 'element-type)
                                                  :adjustable t
                                                  :fill-pointer 0)))
  (vector-push-extend character (slot-value stream 'string)))

(defmethod stream-write-char (character (stream string-output-stream))
  (string-output-stream-write-char character stream))

;; TODO: declares and other stuff.
(defmacro with-output-to-string ((var) &body body)
  `(let ((,var (make-string-output-stream)))
     (unwind-protect (progn ,@body)
       (close ,var))
     (get-output-stream-string ,var)))

(defclass broadcast-stream (stream-object)
  ((streams :initarg :streams :reader broadcast-stream-streams)))

(defun make-broadcast-stream (&rest streams)
  (make-instance 'broadcast-stream :streams streams))

(defun %broadcast-stream-write-char (character stream)
  (dolist (s (broadcast-stream-streams stream))
    (write-char character s)))

(defmethod stream-write-char (character (stream broadcast-stream))
  (%broadcast-stream-write-char character stream))

(defclass echo-stream (stream-object)
  ((input-stream :initarg :input-stream
                 :reader echo-stream-input-stream)
   (output-stream :initarg :output-stream
                  :reader echo-stream-output-stream)))

(defun make-echo-stream (input-stream output-stream)
  (make-instance 'echo-stream
                 :input-stream input-stream
                 :output-stream output-stream))

(defmethod stream-write-char (character (stream echo-stream))
  (write-char character (echo-stream-output-stream stream)))

(defmethod stream-read-char ((stream echo-stream))
  (let ((c (read-char (echo-stream-input-stream stream) nil)))
    (when c
      (write-char c (echo-stream-output-stream stream)))))

(defclass two-way-stream (stream-object)
  ((input-stream :initarg :input-stream
                 :reader two-way-stream-input-stream)
   (output-stream :initarg :output-stream
                  :reader two-way-stream-output-stream)))

(defun make-two-way-stream (input-stream output-stream)
  (make-instance 'two-way-stream
                 :input-stream input-stream
                 :output-stream output-stream))

(defmethod stream-write-char (character (stream two-way-stream))
  (write-char character (two-way-stream-output-stream stream)))

(defmethod stream-read-char ((stream two-way-stream))
  (read-char (two-way-stream-input-stream stream) nil))

(defclass case-correcting-stream (stream-object)
  ((stream :initarg :stream)
   (case :initarg :case)
   (position :initform :initial))
  (:documentation "Convert all output to the specified case.
CASE may be one of:
:UPCASE - Convert to uppercase.
:DOWNCASE - Convert to lowercase.
:INVERT - Invert the case.
:TITLECASE - Capitalise the start of each word, downcase the remaining letters.
:SENTENCECASE - Capitalise the start of the first word."))

(defun make-case-correcting-stream (stream case)
  (make-instance 'case-correcting-stream
                 :stream stream
                 :case case))

(defun case-correcting-write (character stream)
  (ecase (slot-value stream 'case)
    (:upcase (write-char (char-upcase character) (slot-value stream 'stream)))
    (:downcase (write-char (char-downcase character) (slot-value stream 'stream)))
    (:invert (write-char (if (upper-case-p character)
			     (char-downcase character)
			     (char-upcase character))
			 (slot-value stream 'stream)))
    (:titlecase
     (ecase (slot-value stream 'position)
       ((:initial :after-word)
	(if (alphanumericp character)
	    (progn
	      (setf (slot-value stream 'position) :mid-word)
	      (write-char (char-upcase character) (slot-value stream 'stream)))
	    (write-char character (slot-value stream 'stream))))
       (:mid-word
	(unless (alphanumericp character)
	  (setf (slot-value stream 'position) :after-word))
	(write-char (char-downcase character) (slot-value stream 'stream)))))
    (:sentencecase
     (if (eql (slot-value stream 'position) :initial)
	 (if (alphanumericp character)
	     (progn
	       (setf (slot-value stream 'position) nil)
	       (write-char (char-upcase character) (slot-value stream 'stream)))
	     (write-char character (slot-value stream 'stream)))
	 (write-char (char-downcase character) (slot-value stream 'stream))))))

(defmethod stream-write-char (character (stream case-correcting-stream))
  (case-correcting-write character stream))

(defclass edit-stream (stream-object)
  ((edit-buffer :initform nil)
   (edit-offset :initform nil)
   (edit-handler :initform nil)))

(defun edit-stream-read (stream reader-function-kludge)
  (let ((buffer (slot-value stream 'edit-buffer))
	(offset (slot-value stream 'edit-offset)))
    (if (and buffer (< offset (fill-pointer buffer)))
	(prog1 (aref buffer offset)
	  (incf (slot-value stream 'edit-offset)))
	(do () (nil)
	  (let ((ch (funcall reader-function-kludge)))
	    (when ch
	      (cond ((or (graphic-char-p ch) (eql #\Newline ch))
		     (when buffer
		       (vector-push-extend ch buffer)
		       (incf (slot-value stream 'edit-offset)))
		     (return (write-char ch stream)))
		    ((eql #\Backspace ch)
		     (funcall (slot-value stream 'edit-handler) ch)))))))))

(defmethod stream-read-char :around ((stream edit-stream))
  (edit-stream-read stream #'call-next-method))

(defmethod stream-clear-input :before ((stream edit-stream))
  (when (slot-value stream 'buffer)
    (setf (fill-pointer (slot-value stream 'edit-buffer)) 0
	  (slot-value stream 'edit-offset) 0)))

(defun edit-stream-edit (stream fn)
  (let ((old-buffer (slot-value stream 'edit-buffer))
	(old-offset (slot-value stream 'edit-offset))
	(old-handler (slot-value stream 'edit-handler))
	(buffer (make-array 100
			    :element-type 'character
			    :adjustable t
			    :fill-pointer 0)))
    (unwind-protect
         (multiple-value-bind (start-x start-y)
             (stream-cursor-pos stream)
           (setf (slot-value stream 'edit-buffer) buffer)
           (do () (nil)
            again
             (flet ((handler (ch)
                      (when (> (fill-pointer buffer) 0)
                        (decf (fill-pointer buffer))
                        (multiple-value-bind (x y)
                            (stream-compute-motion stream
                                                   buffer
                                                   0 nil
                                                   start-x start-y)
                          (multiple-value-bind (cx cy) (stream-cursor-pos stream)
                            (stream-clear-between stream x y cx cy))
                          (stream-move-to stream x y)))
                      (go again)))
               (setf (slot-value stream 'edit-offset) 0
                     (slot-value stream 'edit-handler) #'handler)
               (return (funcall fn)))))
      (setf (slot-value stream 'edit-buffer) old-buffer
            (slot-value stream 'edit-offset) old-offset
            (slot-value stream 'edit-handler) old-handler))))

(defmethod stream-with-edit ((stream edit-stream) fn)
  (edit-stream-edit stream fn))

(defun y-or-n-p (&optional control &rest arguments)
  (declare (dynamic-extent arguments))
  (when control
    (fresh-line *query-io*)
    (apply 'format *query-io* control arguments)
    (write-char #\Space *query-io*))
  (format *query-io* "(Y or N) ")
  (loop
     (clear-input *query-io*)
     (let ((c (read-char *query-io*)))
       (when (char-equal c #\Y)
         (return t))
       (when (char-equal c #\N)
         (return nil)))
     (fresh-line *query-io*)
     (format *query-io* "Please respond with \"y\" or \"n\". ")))

(defun yes-or-no-p (&optional control &rest arguments)
  (declare (dynamic-extent arguments))
  (when control
    (fresh-line *query-io*)
    (apply 'format *query-io* control arguments)
    (write-char #\Space *query-io*))
  (format *query-io* "(Yes or No) ")
  (loop
     (clear-input *query-io*)
     (let ((line (read-line *query-io*)))
       (when (string-equal line "yes")
         (return t))
       (when (string-equal line "no")
         (return nil)))
     (fresh-line *query-io*)
     (format *query-io* "Please respond with \"yes\" or \"no\". ")))
