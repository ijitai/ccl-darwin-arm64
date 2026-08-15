/* SPDX-License-Identifier: Apache-2.0 */

/*
 * Darwin / arm64 (Apple Silicon) platform header.
 *
 * The arch-level (ARM64) portion mirrors platform-linuxarm64.h; the
 * OS-level portion (Mach exception plumbing, pseudo-sigreturn, mcontext
 * accessors) mirrors platform-darwinx8664.h.  See PORT-NOTE blocks in
 * arm64-exceptions.c for the origin of each deviation.
 */

#define WORD_SIZE 64
#define PLATFORM_OS PLATFORM_OS_DARWIN
#define PLATFORM_CPU PLATFORM_CPU_ARM64
#define PLATFORM_WORD_SIZE PLATFORM_WORD_SIZE_64

#define _DARWIN_C_SOURCE

#include <sys/signal.h>
#include <sys/ucontext.h>

/* ucontext/mcontext stuff.  On arm64, mcontext_t is struct __darwin_mcontext64:
 *     __es  (arm_exception_state64_t : __far, __esr, __exception)
 *     __ss  (arm_thread_state64_t    : __x[29], __fp, __lr, __sp, __pc, __cpsr)
 *     __ns  (arm_neon_state64_t      : __v[32], __fpsr, __fpcr)
 *
 * N.B.: this assumes the non-opaque (legacy) arm_thread_state64_t layout,
 * which is what the default SDK headers provide (__DARWIN_OPAQUE_ARM_THREAD_STATE64
 * is 0 for plain -arch arm64 with pointer-auth off).  If that changes, the
 * __darwin_arm_thread_state64 accessor macros (get_pc/set_pc etc.) must be
 * used instead.
 */
typedef mcontext_t MCONTEXT_T;
typedef ucontext_t ExceptionInformation;
#define UC_MCONTEXT(UC) UC->uc_mcontext

#define MAXIMUM_MAPPABLE_MEMORY (512L<<30L)
// this will end up being some random address
#define IMAGE_BASE_ADDRESS 0x300000000000L

#include "lisptypes.h"
#include "arm64-constants.h"

/* ------------------------------------------------------------------ */
/* sigreturn machinery (platform-darwinx8664.h:59-82 shape) */

extern void darwin_sigreturn(ExceptionInformation *, unsigned);
extern natural os_major_version;

#define DarwinSigReturn(context) do {                \
    darwin_sigreturn(context, 0x1e);                 \
    Bug(context,"sigreturn returned");               \
  } while (0)

#define SIGRETURN(context) DarwinSigReturn(context)
#define DARWIN_USE_PSEUDO_SIGRETURN 1

/* ------------------------------------------------------------------ */
/* xp accessors.  aarch64-darwin mcontext: GPRs x0..x28 in __ss.__x[29];
 * x29(fp), x30(lr), sp, pc, cpsr are separate fields of __ss; the fault
 * address lives in __es.__far. */

#define xpGPRvector(x) ((natural *)(&(UC_MCONTEXT(x)->__ss.__x[0])))
#define xpGPR(x,gprno) (xpGPRvector(x)[gprno])
#define set_xpGPR(x,gpr,new) (xpGPR((x),(gpr)) = (natural)(new))
#define xpSP(x) (UC_MCONTEXT(x)->__ss.__sp)
#define xpPC(x) (*(pc *)&(UC_MCONTEXT(x)->__ss.__pc))
#define set_xpPC(x,new) (xpPC(x) = (pc)(new))
#define xpLR(x) (UC_MCONTEXT(x)->__ss.__lr)
#define xpFP(x) (UC_MCONTEXT(x)->__ss.__fp)
#define xpPSR(x) (UC_MCONTEXT(x)->__ss.__cpsr)
#define xpFaultAddress(x) (UC_MCONTEXT(x)->__es.__far)

/* ------------------------------------------------------------------ */
/* arch-level (ARM64) macros shared with the linux port.  These are the
 * subset platform-linuxarm64.h actually defines (the rest -- TCR_BIAS,
 * heap_segment_size, STATIC_BASE_ADDRESS, fixnum_bitmask, unbound,
 * slot_unbound, NSAVEREGS-via-constants -- already come from
 * arm64-constants.h). */

#ifndef stack_alloc_marker
#define stack_alloc_marker SUBTAG(fulltag_imm_1, 6)
#endif

/* Image ABI version (image.c): must match the value the compiler stamps
 * into image headers (see arm64-backend.lisp). */
#ifndef ABI_VERSION_CURRENT
#define ABI_VERSION_MIN 1046
#define ABI_VERSION_CURRENT 1046
#define ABI_VERSION_MAX 1046
#endif

#ifndef lisp_frame_size
#define lisp_frame_size sizeof(lisp_frame)
#endif

#ifndef NSAVEREGS
#define NSAVEREGS 4
#endif

/* single-floats are IMMEDIATE (fulltag_single_float) in this low-tag
 * design; the "convert box" subtag is vestigial.  Alias for the compile. */
#ifndef subtag_single_float
#define subtag_single_float fulltag_single_float
#endif

#ifndef is_node_fulltag
#define is_node_fulltag(f)  ((1<<(f))&((1<<fulltag_cons) | (1<<fulltag_misc) | (1<<fulltag_symbol)))
#endif

#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/machine/thread_state.h>
#include <mach/machine/thread_status.h>
#include <mach/thread_act.h>

#include "os-darwin.h"
