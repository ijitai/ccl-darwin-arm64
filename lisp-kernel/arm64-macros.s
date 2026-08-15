/* SPDX-License-Identifier: Apache-2.0 */

#include "arm64-constants.h"
#include "arm64-uuo.s"
#include "arm64-asm.h"
#include "arm64-lisp-globals.s"

        .macro note_function_start name
#if !defined(__APPLE__)
        /* mark the symbol as a function for ELF platforms */
        .type \name, %function
#endif
        .endm

        .macro note_function_end name
#if !defined(__APPLE__)
        /* record function size for ELF platforms */
        .size \name, . - \name
#endif
        .endm

        .macro spentry name
        .text
        .p2align 2
        .global _SP\name
        note_function_start _SP\name
_SP\name:
        .endm

        .macro endsp name
        note_function_end _SP\name
        .endm

        .macro clear_allocptr_tag
        bic allocptr, allocptr, #fulltagmask
        .endm

        .macro Cons dest, car, cdr
        sub allocptr, allocptr, #(cons.size - fulltag_cons)
        cmp allocptr, allocbase
        b.hi .Lcons\@
        uuo_alloc
.Lcons\@:
        str \cdr, [allocptr, #cons.cdr]
        str \car, [allocptr, #cons.car]
        mov \dest, allocptr
        clear_allocptr_tag
        .endm

        // dest: a node register for the newly allocated object
        // header: an unboxed register with the desired header
        // size: an unboxed register with desired size in bytes
        .macro Misc_Alloc dest, header, size
        sub \size, \size, #fulltag_misc
        sub allocptr, allocptr, \size
        cmp allocptr, allocbase
        b.hi .Lmalloc\@
        uuo_alloc
.Lmalloc\@:
        str \header, [allocptr, #misc_header_offset]
        mov \dest, allocptr
        clear_allocptr_tag
        .endm

        .macro Misc_Alloc_Fixed dest, header, sizeconst
        sub allocptr, allocptr, #(\sizeconst - fulltag_misc)
        cmp allocptr, allocbase
        b.hi .Lmaf\@
        uuo_alloc
.Lmaf\@:
        str \header, [allocptr, #misc_header_offset]
        mov \dest, allocptr
        clear_allocptr_tag
        .endm

        .macro extract_header dest, miscobj
        ldur \dest, [\miscobj, #misc_header_offset]
        .endm

#if defined(DARWIN) && defined(ARM64)
        // Like Misc_Alloc, but allocates from the MAP_JIT code area
        // (code_area_allocptr/code_area_limit globals) instead of the
        // dynamic heap.  First flips the JIT pages writable.  The C call
        // clobbers x0/x1 (header/size) and x30, so all are saved on the
        // C stack (16-byte aligned for the AAPCS64 call).  temp2/temp3
        // are clobbered.
        .macro Misc_Alloc_Code dest, header, size
        stp  x0, x1, [sp, #-32]!
        stp  x29, x30, [sp, #16]
        bl   C(xMakeDataWritable)
        ldp  x29, x30, [sp, #16]
        ldp  x0, x1, [sp], #32
        sub \size, \size, #fulltag_misc
        adrp temp3, C(code_area_allocptr)@PAGE
        ldr  temp3, [temp3, C(code_area_allocptr)@PAGEOFF]
        sub  temp3, temp3, \size
        adrp temp2, C(code_area_limit)@PAGE
        ldr  temp2, [temp2, C(code_area_limit)@PAGEOFF]
        cmp  temp3, temp2
        b.hi .Lmcode\@
        uuo_alloc
.Lmcode\@:
        str  \header, [temp3, #misc_header_offset]
        mov  \dest, temp3
        bic  temp3, temp3, #fulltagmask
        adrp temp2, C(code_area_allocptr)@PAGE
        str  temp3, [temp2, C(code_area_allocptr)@PAGEOFF]
        .endm
#endif
