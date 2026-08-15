(in-package "CCL")

(defpackage "ARM64-DARWIN" (:use))

;;; Host-side macro shim for the port's level-1 reader additions.
;;; with-token-buffer and the token.* accessors live in level-1/l1-reader.lisp,
;;; but the cross-compiling HOST runs stock CCL 1.12.2 level-1, which lacks
;;; them.  When nfcomp cross-compiles lib/read.lisp, unknown macros expand as
;;; ordinary function calls, so `(with-token-buffer (tb) ...)' compiles
;;; `(tb)' as a call to symbol TB ("Undefined function TB called with ()").
;;; Defining them here (compile- and load-time on the host) makes the
;;; expansion identical to the target's.  Slot order must match
;;; level-1/l1-reader.lisp (token.string token.ipos token.opos token.len).
(eval-when (:compile-toplevel :load-toplevel :execute)
  (def-accessors %svref
    token.string
    token.ipos
    token.opos
    token.len)

  (defmacro with-token-buffer ((name) &body body &environment env)
    (multiple-value-bind (body decls) (parse-body body env nil)
      `(let* ((,name (vector (%get-token-string 16) 0 0 16 nil)))
         (declare (dynamic-extent ,name))
         (unwind-protect
              (locally ,@decls ,@body)
           (%return-token-string ,name))))))

(defun load-darwinarm64-backend ()
  (in-development-mode
    ;; until updated versions are included in the lisp image
    (load "ccl:lib;systems.lisp")
    (load "ccl:lib;compile-ccl"))
  
  (update-modules '(arm64-arch arm64-asm arm64-lap arm64-backend
                    arm64-vinsns arm642)
                  t)
  (setup-arm64-ftd *darwinarm64-backend*)
  (update-modules '(arm64-lapmacros arm64-disassemble ffi-darwinarm64) t)
  (update-modules *arm64-xload-modules* t))

(load-darwinarm64-backend)
