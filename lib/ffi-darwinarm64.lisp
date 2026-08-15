;;;; -*- Mode: Lisp; Package: CCL -*-
;;;;
;;;; SPDX-License-Identifier: Apache-2.0

(in-package "CCL")

;;; Darwin varies from the standard 64-ARM ABI in a few small ways.
;;; https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms
;;;
;;; The calling convention is AAPCS64 (identical to Linux/arm64), so the
;;; FFI backend is a verbatim port of ffi-linuxarm64.lisp with the
;;; interface-package name changed to ARM64-DARWIN.  Darwin-specific
;;; differences (:signed-char t, va_list as char*, Mach-O underscore
;;; prefix) live in the foreign-type database, not in the ABI backend.
;;;
;;; AAPCS64 reference summary (per IHI 0055C, 5-6):
;;;   - X0..X7   : integer/pointer args (8 GPR slots); return in X0..X1
;;;   - V0..V7   : SIMD&FP args (8 VFP slots); return in V0..V1
;;;   - X8       : indirect-result-area pointer (caller-allocated buffer
;;;                when return is a composite > 16 bytes)
;;;   - Composite size <= 16 bytes (128 bits): passed in GPRs (split
;;;     across X0..X7 as 1-2 doublewords, left-justified).
;;;   - Composite size > 16 bytes: passed by reference to a
;;;     caller-allocated copy (single :address slot).
;;;
;;; Composite return rules (AAPCS64 6.9):
;;;   - Size <= 16 bytes (and not HFA): returned in X0/X1.
;;;   - Size > 16 bytes (or HFA): caller allocates buffer, passes
;;;     pointer in X8; function writes through X8 and returns void.

(defun arm64-darwin::record-type-returns-structure-as-first-arg (rtype)
  (arm64::record-type-returns-structure-as-first-arg rtype))

;;; Return 7 values:
;;; A list of RLET bindings
;;; A list of LET* bindings
;;; A list of DYNAMIC-EXTENT declarations for the LET* bindings
;;; A list of initializaton forms for (some) structure args
;;; A FOREIGN-TYPE representing the "actual" return type.
;;; A form which can be used to initialize FP-ARGS-PTR, relative
;;;  to STACK-PTR. (This unused on some platforms.)
;;; The byte offset of the foreign return address, relative to STACK-PTR
(defun arm64-darwin::expand-ff-call (callform args &key (arg-coerce #'null-coerce-foreign-arg) (result-coerce #'null-coerce-foreign-result))
  (let* ((result-type-spec (or (car (last args)) :void)))
    (multiple-value-bind (result-type error)
        (ignore-errors (parse-foreign-type result-type-spec))
      (if error
        (setq result-type-spec :void result-type *void-foreign-type*)
        (setq args (butlast args)))
      (collect ((argforms))
        (when (eq (car args) :monitor-exception-ports)
          (argforms (pop args)))
        (when (typep result-type 'foreign-record-type)
          ;; Reached only for > 128-bit returns (per AAPCS64 6.9).
          ;; Caller-allocated result buffer is passed as the first
          ;; :address arg; AAPCS64 wiring puts it in X8.
          (setq result-type *void-foreign-type*
                result-type-spec :void)
          (argforms :address)
          (argforms (pop args)))
        (unless (evenp (length args))
          (error "~s should be an even-length list of alternating foreign types and values" args))
        (do* ((args args (cddr args)))
             ((null args))
          (let* ((arg-type-spec (car args))
                 (arg-value-form (cadr args)))
            (if (or (member arg-type-spec *foreign-representation-type-keywords*
                            :test #'eq)
                    (typep arg-type-spec 'unsigned-byte))
              (progn
                (argforms arg-type-spec)
                (argforms arg-value-form))
              (let* ((ftype (parse-foreign-type arg-type-spec)))
                (if (typep ftype 'foreign-record-type)
                  (let* ((bits (ensure-foreign-type-bits ftype)))
                    (cond
                      ;; <=64 bit struct passed left-justified.
                      ((<= bits 64)
                       (argforms :unsigned-doubleword)
                       (argforms `(%%get-unsigned-longlong ,arg-value-form 0)))
                      ;; 65-128 bit struct passed as 2 doublewords.
                      ((<= bits 128)
                       (argforms (ceiling bits 64))
                       (argforms arg-value-form))
                      ;; > 128 bit struct passed by reference.
                      (t
                       (argforms :address)
                       (argforms arg-value-form))))
                  (progn
                    (argforms (foreign-type-to-representation-type ftype))
                    (argforms (funcall arg-coerce arg-type-spec arg-value-form))))))))
        (argforms (foreign-type-to-representation-type result-type))
        (funcall result-coerce result-type-spec `(,@callform ,@(argforms)))))))

(defun arm64-darwin::generate-callback-bindings (stack-ptr fp-args-ptr argvars argspecs result-spec struct-result-name)
  (collect ((lets)
            (rlets)
            (inits)
            (dynamic-extent-names))
    (let* ((rtype (parse-foreign-type result-spec))
           (fp-regs-form nil))
      (flet ((set-fp-regs-form ()
               (unless fp-regs-form
                 (setq fp-regs-form `(%inc-ptr ,stack-ptr ,arm64::callback-frame.fp-save-offset)))))
        (when (typep rtype 'foreign-record-type)
          (setq argvars (cons struct-result-name argvars)
                argspecs (cons :address argspecs)
                rtype *void-foreign-type*))
        (when (typep rtype 'foreign-float-type)
          (set-fp-regs-form))
        (do* ((argvars argvars (cdr argvars))
              (argspecs argspecs (cdr argspecs))
              (fp-arg-num 0)
              (offset 0 (+ offset delta))
              (delta 8 8)
              (bias 0 0)
              (use-fp-args nil nil))
             ((null argvars)
              (values (rlets) (lets) (dynamic-extent-names) (inits) rtype fp-regs-form
                      arm64::callback-frame.savelr-offset))
          (let* ((name (car argvars))
                 (spec (car argspecs))
                 (argtype (parse-foreign-type spec))
                 (bits (ensure-foreign-type-bits argtype)))
            (if (and (typep argtype 'foreign-record-type)
                     (<= bits 64))
              (progn
                (when name (rlets (list name (foreign-record-type-name argtype))))
                ;; little-endian: value is low-justified in its doubleword.
                (when name (inits `(setf (%%get-unsigned-longlong ,name 0)
                                    (%%get-unsigned-longlong ,stack-ptr ,offset)))))
              (let* ((access-form
                      `(,(cond
                          ((typep argtype 'foreign-single-float-type)
                           (when (< (incf fp-arg-num) 9)
                             (setq use-fp-args t
                                   delta 0))
                           '%get-single-float)
                          ((typep argtype 'foreign-double-float-type)
                           (when (< (incf fp-arg-num) 9)
                             (setq use-fp-args t
                                   delta 0))
                           '%get-double-float)
                          ((and (typep argtype 'foreign-integer-type)
                                (= (foreign-integer-type-bits argtype) 64)
                                (foreign-integer-type-signed argtype))
                           '%%get-signed-longlong)
                          ((and (typep argtype 'foreign-integer-type)
                                (= (foreign-integer-type-bits argtype) 64)
                                (not (foreign-integer-type-signed argtype)))
                           '%%get-unsigned-longlong)
                          ((or (typep argtype 'foreign-pointer-type)
                               (typep argtype 'foreign-array-type))
                           '%get-ptr)
                          ((typep argtype 'foreign-record-type)
                           (if (<= bits 128)
                             (progn
                               (setq delta 16)
                               '%inc-ptr)
                             ;; >128-bit records arrive by reference.
                             '%get-ptr))
                          (t
                           (cond ((typep argtype 'foreign-integer-type)
                                  (let* ((bits (foreign-integer-type-bits argtype))
                                         (signed (foreign-integer-type-signed argtype)))
                                    (cond ((<= bits 8)
                                           (if signed
                                             '%get-signed-byte
                                             '%get-unsigned-byte))
                                          ((<= bits 16)
                                           (if signed
                                             '%get-signed-word
                                             '%get-unsigned-word))
                                          ((<= bits 32)
                                           (if signed
                                             '%get-signed-long
                                             '%get-unsigned-long))
                                          (t
                                           (error "Don't know how to access foreign argument of type ~s" (unparse-foreign-type argtype))))))
                                 (t
                                  (error "Don't know how to access foreign argument of type ~s" (unparse-foreign-type argtype))))))
                        ,(if use-fp-args fp-args-ptr stack-ptr)
                        ,(if use-fp-args (* 8 (1- fp-arg-num))
                             `(+ ,offset ,bias)))))
                (when name (lets (list name access-form)))
                (when use-fp-args (set-fp-regs-form))))))))))

(defun arm64-darwin::generate-callback-return-value (stack-ptr fp-args-ptr result return-type struct-return-arg)
  (declare (ignore struct-return-arg))
  (unless (eq return-type *void-foreign-type*)
    (let* ((return-type-keyword (foreign-type-to-representation-type return-type)))
      (case return-type-keyword
        (:single-float
         `(setf (%get-single-float ,fp-args-ptr 0) ,result))
        (:double-float
         `(setf (%get-double-float ,fp-args-ptr 0) ,result))
        (:address
         `(setf (%get-ptr ,stack-ptr 0) ,result))
        (:signed-doubleword
         `(setf (%%get-signed-longlong ,stack-ptr 0) ,result))
        (:unsigned-doubleword
         `(setf (%%get-unsigned-longlong ,stack-ptr 0) ,result))
        (t
         `(setf (%%get-signed-longlong ,stack-ptr 0) ,result))))))
