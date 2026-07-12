#!/usr/bin/env bash
#
# fast_qr/mayhem/test.sh — RUN erwanvivien/fast_qr's own test suite (`cargo test
# --features svg,image`, the same invocation as upstream's CI workflow rust.yml) and emit
# a CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: fast_qr ships a real unit suite under src/tests/ (bytes, compact,
# datamasking, default, encode, error_correction, polynomials, score, structure, svg,
# version) that asserts VALUE-EXACT behaviour — golden module matrices, encoded bit
# strings, Reed-Solomon polynomial coefficients, mask patterns, penalty scores and exact
# SVG output strings — plus the crate's doc-tests. A no-op / exit(0) / output-altering
# patch cannot pass these. This script only RUNS the suite build.sh pre-built; it never
# builds fuzz targets. --features svg,image mirrors upstream CI (`cargo test --verbose
# -F svg,image`) so the SVG and image golden tests + all doc-tests are included.
#
# Run with the crate's NORMAL flags (no sanitizer RUSTFLAGS) to keep the oracle honest.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

echo "=== running cargo test --features svg,image (fast_qr unit + doc tests) ==="
# Image-default toolchain (no `+toolchain` override — rustup would try to install another
# channel into the shared /opt prefix). --no-fail-fast so every test is counted; RUSTFLAGS
# cleared so nothing leaks in from the sanitizer fuzz build.
out="$(RUSTFLAGS="" cargo test --features svg,image --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"

# libtest prints one line per test binary / doc-test run:
#   test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; ...
# Sum across all of them.
PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n' "$out" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

# No parseable result lines (e.g. compile error) — fall back to cargo's exit code.
if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse any 'test result:' lines; using cargo exit code $rc" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
