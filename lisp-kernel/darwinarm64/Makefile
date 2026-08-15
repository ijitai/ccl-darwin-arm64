#
# Copyright 2010 Clozure Associates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Darwin/arm64 (Apple Silicon) kernel.  Structure mirrors linuxarm64/Makefile
# (the .s/.c build) plus the mach_exc_server rules from darwinx8664/Makefile.

VC_REVISION := "$(shell git describe --dirty 2>/dev/null || echo unknown)"

OSVERSION = 11.0

VPATH = ../
RM = /bin/rm
CC = cc
AS = as
M4 = m4

ASFLAGS = -arch arm64
M4FLAGS = -DDARWIN -DARM64
CDEFINES = -DDARWIN -DARM64 -D_REENTRANT -DVC_REVISION=$(VC_REVISION)
CDEBUG = -g
COPT = -O2
# Once in a while, -Wformat says something useful.  The odds are against that,
# however.
WFORMAT = -Wno-format
PLATFORM_H = platform-darwinarm64.h

.s.o:
	$(CC) -c -x assembler-with-cpp -arch arm64 -I../ $< $(CDEFINES) -o $@
.c.o:
	$(CC) -include ../$(PLATFORM_H) -c $< -arch arm64 $(CDEFINES) \
	$(CDEBUG) $(COPT) $(WFORMAT) -I. -o $@

SPOBJ = pad.o  arm64-spentry.o spentry-A-alloc-numbers.o spentry-B-vectors-misc.o spentry-C-bind-catch-throw.o spentry-D-call-builtins.o spentry-E-ffi.o
ASMOBJ = arm64-asmutils.o imports.o

COBJ  = pmcl-kernel.o gc-common.o arm64-gc.o bits.o  arm64-exceptions.o \
	image.o thread_manager.o lisp-debug.o memory.o unix-calls.o

DEBUGOBJ = lispdcmd.o plprint.o plsym.o albt.o arm64-print.o
KERNELOBJ= $(COBJ) arm64-asmutils.o  imports.o

SPINC =	lisp.s m4macros.m4 arm64-constants.h arm64-macros.s errors.s arm64-uuo.s \
	lisp_globals.s

CHEADERS = area.h bits.h arm64-constants.h lisp-errors.h gc.h lisp.h \
	lisp-exceptions.h lisp_globals.h macros.h memprotect.h image.h \
	threads.h arm64-exceptions.h $(PLATFORM_H)

KSPOBJ = $(SPOBJ)
all:	../../darmcl64

../../darmcl64:	$(KSPOBJ) $(KERNELOBJ) $(DEBUGOBJ) mach_exc_server.o
	$(CC) -arch arm64 -o $@ $(KSPOBJ) $(KERNELOBJ) $(DEBUGOBJ) mach_exc_server.o

$(SPOBJ): $(SPINC)
$(ASMOBJ): $(SPINC)
$(COBJ): $(CHEADERS)
$(DEBUGOBJ): $(CHEADERS) lispdcmd.h

imports.o: ../imports.s ../m4macros.m4
	$(M4) $(M4FLAGS) -I../ ../imports.s | $(AS) $(ASFLAGS) -o $@ -

mach_exc_server.o: mach_exc_server.c mach_exc.h

# mig generates the server that dispatches Mach exception messages to
# catch_mach_exception_raise{,_state,_state_identity}.
mach_exc_server.c: mach_exc.defs
	mig -arch arm64 -header /dev/null -user /dev/null \
		-sheader mach_exc.h -server mach_exc_server.c \
		../mach_exc.defs

mach_exc.h: mach_exc_server.c

cclean:
	$(RM) -f $(KERNELOBJ) $(DEBUGOBJ) mach_exc_server.o ../../darmcl64 \
		mach_exc.h mach_exc_server.c

clean:	cclean
	$(RM) -f $(SPOBJ)

strip:	../../darmcl64
	strip -s retain ../../darmcl64
