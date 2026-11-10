#!/bin/bash
# The engine's core tests on arm64 Linux, run under qemu: a check of translator changes without a Mac.
#   sudo apt-get install qemu-user-static gcc-aarch64-linux-gnu libc6-dev-arm64-cross
#   tools/qemu/run.sh [OUT]        (OUT: build folder, default build/qemu; HV_* knobs pass through)
# Runs test_jit, test_mem, test_mmu and test_bench. Expected differences from a Mac: test_mem's dczva program
# fails in every mode (qemu's DC ZVA block size is not Apple's), and test_exc can't run (its native reference
# executes SVC and BRK, which Linux takes as a system call and a trap). Times are qemu's, which overstates
# taken branches and block transitions: compare runs with each other, never with a device.
set -e
Q=$(dirname "$(readlink -f "$0")"); R=$(cd "$Q/../.." && pwd); O=${1:-$R/build/qemu}
mkdir -p $O/obj $O/asm
for f in host/enter.S tests/harness.S tests/jit_programs.S tests/mem_programs.S tests/exc_programs.S tests/bench_programs.S; do
    $Q/macho2elf.sh $R/$f > $O/asm/$(basename $f)
done
$Q/macho2elf.sh $R/tests/harness.h > $O/asm/harness.h
CC="aarch64-linux-gnu-gcc -std=gnu11 -O2 -g -ffixed-x18 -march=armv8.5-a -I$Q/inc -include $Q/inc/compat.h -I$R/core -I$R/host -I$R/devices -w"
for f in $R/core/*.c $R/host/jit_region.c; do
    b=$(basename $f .c)
    if [ $b = mmu ]; then $CC -mgeneral-regs-only -c $f -o $O/obj/$b.o; else $CC -c $f -o $O/obj/$b.o; fi
done
for f in $O/asm/*.S; do aarch64-linux-gnu-gcc -march=armv8.5-a -c -I$O/asm $f -o $O/obj/$(basename $f .S).S.o; done
aarch64-linux-gnu-gcc -O2 -c $Q/ulock.c -o $O/obj/ulock.o
ENG="$O/obj/classify.o $O/obj/operands.o $O/obj/translate.o $O/obj/dispatch.o $O/obj/mmu.o $O/obj/memop.o $O/obj/exception.o $O/obj/sysreg.o $O/obj/machine.o $O/obj/jit_region.o $O/obj/enter.S.o $O/obj/ulock.o"
for t in jit mem bench; do $CC -static -I$R/tests $R/tests/test_$t.c $O/obj/${t}_programs.S.o $O/obj/harness.S.o $ENG -o $O/test_$t -lpthread -latomic 2>&1 | grep -v warning || true; done
$CC -static -I$R/tests $R/tests/test_mmu.c $ENG -o $O/test_mmu -lpthread -latomic 2>&1 | grep -v warning || true
ulimit -s 65520 # a test keeps a whole HvCpu on its stack
for t in test_jit test_mem test_mmu test_bench; do echo "== $t"; qemu-aarch64-static -cpu max $O/$t || true; done
