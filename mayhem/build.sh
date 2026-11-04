#!/usr/bin/env bash
#
# mayhem/build.sh — fuzz harnesses + known-answer probes for score's self-contained shader/video parsers.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/savantenvs/base) already exports the build contract — use these, don't redefine:
#   CC, CXX             stock clang / clang++
#   LIB_FUZZING_ENGINE  -fsanitize=fuzzer   (link into each harness that has a LLVMFuzzer entry)
#   SANITIZER_FLAGS     -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
#                       (ASan + UBSan, both set to HALT — so Mayhem catches memory AND UB defects)
#   DEBUG_FLAGS         -g -gdwarf-3   (DWARF debug info — always on for fuzz/standalone builds,
#                       independent of the sanitizer off-switch; DWARF version must be < 4)
#   RUST_DEBUG_FLAGS    -C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3
#                       (thread through RUSTFLAGS on every cargo-fuzz build)
#   GO_DEBUG_FLAGS      -gcflags=all=-N -l
#                       (thread through go build / go-fuzz-build so the linked ELF keeps symbols)
#   SRC                 /mayhem (the repo source)
#
# Contract: build EVERYTHING here — one runnable binary per fuzz harness, AND the project's test
# suite (so mayhem/test.sh only has to RUN it, never compile). Keep it ADDITIVE (build upstream as
# upstream documents; don't edit upstream files). IMPORTANT: build the PROJECT ITSELF with
# $SANITIZER_FLAGS and $DEBUG_FLAGS (not just the harness) so the fuzzed code is instrumented
# AND carries DWARF < 4 symbols — otherwise ASan/UBSan only see the harness, not the library
# you're trying to find bugs in, and backtraces won't resolve project source lines. Build the TEST
# suite with the project's NORMAL flags (a clean, independent build) so test.sh stays an honest
# functional oracle and won't false-fail on benign UB. Leave the test binary/runner where test.sh
# expects it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# plain `wait` hides a failed background compile, so reap each pid.
pids=()
par() { "$@" & pids+=($!); }
join() { local p; for p in "${pids[@]}"; do wait "$p" || exit 1; done; pids=(); }

# score itself is a Qt/RHI application whose full build is not air-gappable or fuzzable; this builds the
# parsers it ships in-tree as plain C/C++ sources: libisf (ISF/CSF/VSA shader front end), 3rdparty/glsl-parser
# (bison/flex GLSL grammar) and 3rdparty/dxv (DXV texture decompression). Header-only deps (libossia's
# detail headers, ctre, unordered_dense, rapidhash) are baked into /opt/deps by the Dockerfile.
DEPS=/opt/deps
GFX="$SRC/src/plugins/score-plugin-gfx/3rdparty/libisf/src"
GLSL="$SRC/3rdparty/glsl-parser"
DXV="$SRC/3rdparty/dxv"
INCS="-I$SRC/mayhem/stub -I$GFX -I$SRC/3rdparty -I$DXV -I$DEPS/libossia/src -I$DEPS/ctre/include -I$DEPS/unordered_dense/include -I$DEPS/rapidhash"
CXXSTD="-std=c++23"
LIBS="-lfmt -lboost_regex"
B="$SRC/build-mayhem"
rm -rf "$B"; mkdir -p "$B/fuzz" "$B/plain"

# libFuzzer SanCov must be on the library compile, or the fuzzed code reports 0 edges (kept even when
# SANITIZER_FLAGS is empty).
FUZZ_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1"

# 1) the project's parsers, sanitized + SanCov-instrumented
par $CXX $FUZZ_FLAGS $CXXSTD $INCS -c "$GFX/isf.cpp" -o "$B/fuzz/isf.o"
par $CC  $FUZZ_FLAGS $INCS -c "$GLSL/glsl_ast.c"     -o "$B/fuzz/glsl_ast.o"
par $CC  $FUZZ_FLAGS $INCS -c "$GLSL/glsl.parser.c"  -o "$B/fuzz/glsl_parser.o"
par $CC  $FUZZ_FLAGS $INCS -c "$GLSL/glsl.lexer.c"   -o "$B/fuzz/glsl_lexer.o"
par $CC  $FUZZ_FLAGS $INCS -c "$DXV/dxv.c"           -o "$B/fuzz/dxv.o"
par $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/fuzz/lsan_off.o"
par $CC  $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$B/fuzz/standalone_main.o"
join

GLSL_OBJS="$B/fuzz/glsl_ast.o $B/fuzz/glsl_parser.o $B/fuzz/glsl_lexer.o"

# 2) one fuzzer + one standalone reproducer per harness
build_target() { # <name> <objects...>
  local name="$1"; shift
  $CXX $FUZZ_FLAGS $CXXSTD $INCS "$SRC/mayhem/harness/$name.cc" "$@" "$B/fuzz/lsan_off.o" \
      $LIB_FUZZING_ENGINE $LIBS -o "$SRC/$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 $CXXSTD $INCS "$SRC/mayhem/harness/$name.cc" "$@" "$B/fuzz/lsan_off.o" \
      "$B/fuzz/standalone_main.o" $LIBS -o "$SRC/$name-standalone"
}
par build_target fuzz_isf_fragment "$B/fuzz/isf.o" $GLSL_OBJS
par build_target fuzz_isf_csf      "$B/fuzz/isf.o" $GLSL_OBJS
par build_target fuzz_isf_vsa      "$B/fuzz/isf.o" $GLSL_OBJS
par build_target fuzz_glsl_parser  $GLSL_OBJS
par build_target fuzz_dxv          "$B/fuzz/dxv.o"
join

# 3) known-answer probes for test.sh: the NORMAL flags (no sanitizer, no -gdwarf-3), dynamically linked
P="-O1 $COVERAGE_FLAGS"
par $CXX $P $CXXSTD $INCS -c "$GFX/isf.cpp" -o "$B/plain/isf.o"
par $CC  $P $INCS -c "$GLSL/glsl_ast.c"     -o "$B/plain/glsl_ast.o"
par $CC  $P $INCS -c "$GLSL/glsl.parser.c"  -o "$B/plain/glsl_parser.o"
par $CC  $P $INCS -c "$GLSL/glsl.lexer.c"   -o "$B/plain/glsl_lexer.o"
par $CC  $P $INCS -c "$DXV/dxv.c"           -o "$B/plain/dxv.o"
join
PLAIN_GLSL="$B/plain/glsl_ast.o $B/plain/glsl_parser.o $B/plain/glsl_lexer.o"
par $CXX $P $CXXSTD $INCS "$SRC/mayhem/kat/kat_isf.cc"  "$B/plain/isf.o" $PLAIN_GLSL $LIBS -o "$SRC/kat_isf"
par $CXX $P $CXXSTD $INCS "$SRC/mayhem/kat/kat_glsl.cc" $PLAIN_GLSL -o "$SRC/kat_glsl"
par $CC  $P $INCS "$SRC/mayhem/kat/kat_dxv.c" "$B/plain/dxv.o" -o "$SRC/kat_dxv"
join
file "$SRC/kat_isf" "$SRC/kat_glsl" "$SRC/kat_dxv" | grep -c 'dynamically linked' | grep -qx 3
