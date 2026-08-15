;;; -*- Mode: Lisp; Package: CCL -*-
;;; ARM64-SPECIFIC — a callback trampoline is raw machine code, so the
;;; body is inherently per-ISA; no PPC64 or Clozure-WIP analog encoding
;;; exists (PPC64 `ba' / ARM32 `ldr pc,[pc,#-4]` — see below).
;;;
;;; arm64-callback-support.lisp — callback trampoline generator for Matt
;;; Emerson's upstream ARM64 (low-tag) design.
;;;
;;; ISA-specific by nature (the body is raw machine code): the LOGIC
;;; mirrors arm-callback-support.lisp:19 and x86-callback-support.lisp:21
;;; (allocate a callback pointer, stamp the callback index into the
;;; register the kernel's _SPcallback reads, jump there, make the stub
;;; executable, return the pointer).  PPC64 reaches the subprim with a
;;; `ba' absolute branch and ARM32 with an `ldr pc,[pc,#-4]' literal
;;; jump; neither encoding exists on AArch64, hence the x16 literal jump.
;;;
;;; Trampoline layout (32 bytes, entered by FOREIGN code under AAPCS64;
;;; x8 (indirect-result reg, caller-saved for our purposes — _SPcallback
;;; consumes it immediately) and x16 (IP0 scratch) are safe to clobber):
;;;
;;;    0: movz x8, #lo16(index)         ; unboxed callback index
;;;    4: movk x8, #hi16(index), lsl 16
;;;    8: ldr  x16, .+16                ; load _SPcallback address
;;;   12: br   x16                      ;   from the literal at +24
;;;   16: nop                           ; pad literal to 8-byte alignment
;;;   20: nop
;;;   24: .quad <_SPcallback kernel address>
;;;
;;; MATCHED PAIR: _SPcallback (upstream-port/lisp-kernel/spentry-E-ffi.s)
;;; reads the index from arg_w = x8 (`mov save0, arg_w`).  Change this
;;; generator and that entry together.

(in-package "CCL")

(defun make-callback-trampoline (index &optional info)
  (declare (ignorable info))
  (let* ((p (%allocate-callback-pointer 32)))
    ;; W^X: the trampoline write + RW->RX toggle happen in one atomic kernel
    ;; entry (level-0 %make-callback-trampoline -> .SPmake_callback_trampoline
    ;; -> C make_callback_trampoline), which computes the 6 instructions from
    ;; `index', stores the .SPcallback address, flushes the I-cache and flips
    ;; the MAP_JIT region to executable — so the caller's own code area is
    ;; never left non-executable mid-run.
    (%make-callback-trampoline p index)
    p))
