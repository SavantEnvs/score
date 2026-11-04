#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer assertions over score's in-tree parsers (probes built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

passed=0; failed=0
check() { # <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed+1)); echo "ok   $1"
  else failed=$((failed+1)); echo "FAIL $1"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | head -20; fi
}

# Probes are unconditional: a missing binary or fixture is a failure, never a skip.
for b in kat_isf kat_glsl kat_dxv; do
  [ -x "$SRC/$b" ] || { echo "FAIL missing probe $b (build.sh must produce it)"; failed=$((failed+1)); }
done

# libisf: the ISF "radial slice" fragment shader (libisf/tests/glsl450.cpp) -> parsed descriptor.
check isf_fragment_descriptor 'description=Repllcates a radial slice of an image
credits=VIDVOX
categories=2: [Geometry Adjustment] [Tile Effect]
inputs=6
image inputImage
float postRotateAngle "Post Rotate Angle" min=0 max=360 def=0
float numberOfDivisions "Number Of Divisions" min=1 max=360 def=12
float preRotateAngle "Pre Rotate Angle" min=-180 max=180 def=0
float centerRadiusStart "Radius Start" min=0 max=1 def=0
float centerRadiusEnd "Radius End" min=0 max=2 def=1
has_main=1' "$("$SRC/kat_isf" frag "$SRC/mayhem/kat/radial_slice.fs" 2>&1)"

# libisf CSF mode: a compute shader from score's own shader corpus.
check isf_csf_descriptor 'mode=2
description_len=183
passes=1
local_size=64,1,1
has_main=1' "$("$SRC/kat_isf" csf "$SRC/tests/gfx/corpus/1d-stride-x2.cs" 2>&1)"

# 3rdparty/glsl-parser: function definitions found in a small shader, and a syntax error reported.
check glsl_parser_functions 'error=0
fn sq
fn rot
fn main
function_definitions=3
syntax_error_detected=1' "$("$SRC/kat_glsl" 2>&1)"

# 3rdparty/dxv: LZF literal run, back-reference, and output-overflow rejection.
check dxv_lzf 'lzf_literal n=5 out=hello
lzf_backref n=6 out=ababab
lzf_overflow n=-1' "$("$SRC/kat_dxv" 2>&1)"

emit_ctrf "score-kat" "$passed" "$failed" 0
