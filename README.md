# Clozure CL

This is the source code for Clozure CL.

Because CCL is written in itself, you need an already-working version
of CCL to compile it.

See https://github.com/Clozure/ccl/releases/latest for instructions
on how to get a copy of CCL for your system.

To report a bug or request an enhancement, please make an issue at
https://github.com/Clozure/ccl/issues.

If you have questions or run into problems, send mail to
ccl-devel@clozure.com (see https://lists.clozure.com for instructions
on how to subscribe), ask on #ccl on libera.chat, or create an
issue here, especially if you think you have found a bug.

## macOS/arm64 port (this repository)

This fork of `cyclistmass/ccl-linux-arm64` ports CCL's ARM64 backend to
macOS (Darwin/arm64, AAPCS64): a native `darmcl64` kernel, an
`arm64-boot.image`, and target fasls that run the full ANSI test suite.

Highlights of the port work:

- Kernel: arm64 GC (EGC weak-vector/population reap for the missing
  write-barrier path, csf object header fix), W^X/MAP_JIT code area,
  mach exception handling, 16 KB page support.
- Compiler (`compiler/ARM64/`): native arm64 codegen fixes
  (complex-single-float boxing header, svref offsets, fake-stack-frame
  istruct class, subprim call plumbing).
- The official ANSI test suite runs clean: **21920/21920 tests pass,
  0 failures** (measured on Apple Silicon).

Build and run:

```sh
# rebuild the kernel
cd lisp-kernel/darwinarm64 && make

# run arm64 Lisp
./darmcl64 -I arm64-boot.image --batch --no-init
```

The ARM64 backend was cross-compiled from a host CCL; see the commit
history (`fea2fdd`, `f0a69b9`, and earlier ARM64-PORT commits) for the
detailed fixes.
