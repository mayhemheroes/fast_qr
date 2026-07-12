#!/usr/bin/env bash
#
# fast_qr/mayhem/build.sh — build erwanvivien/fast_qr's cargo-fuzz target as a sanitized
# libFuzzer binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), then pre-build
# the crate's own test suite so mayhem/test.sh only RUNS it.
#
# fast_qr is a pure-Rust QR code generator. Upstream ships NO fuzz/ crate, so the
# cargo-fuzz crate lives additively at mayhem/fuzz/ (--fuzz-dir).
#
# Target:
#   fastqr_fuzz — full QRBuilder pipeline (encode, ECC, placement, masking, scoring)
#                 plus Unicode + SVG conversion over arbitrary bytes.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): this first (online) build populates the cargo
# registry under $CARGO_HOME (/opt/toolchains/rust/cargo, pinned by the Dockerfile);
# the PATCH tier re-runs this script OFFLINE with CARGO_NET_OFFLINE=true and resolves
# crates from that cache — so no `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10). Force DWARF 2 so Mayhem triage / gdb can
# resolve project source lines. The rlenv runtime may export RUST_DEBUG_FLAGS before the
# offline re-run; the := default only applies when unset/empty.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# ── DWARF < 4 enforcement (§6.2 item 10) ─────────────────────────────────────────────
# The Rust ASan runtime (librustc-nightly_rt.asan.a) is compiled with the nightly's
# bundled LLVM, which defaults to DWARF 5, and is linked BEFORE project code. Strip its
# debug sections so our DWARF-2 CUs lead .debug_info. Idempotent; the stripped .a is
# baked into the image so the offline re-run sees the same file.
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 for those CUs
# too (cc respects CFLAGS/CXXFLAGS; same flags on the re-run keep the fingerprint stable).
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

# The additive cargo-fuzz crate (upstream has no fuzz/).
FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(fastqr_fuzz)
TRIPLE="x86_64-unknown-linux-gnu"

# OSS-Fuzz Rust libFuzzer+ASan flags. Rust instrumentation goes through RUSTFLAGS, NOT
# clang's $SANITIZER_FLAGS / CFLAGS (rustc ignores those): -Zsanitizer=address is the
# RUSTFLAGS equivalent of the base's $SANITIZER_FLAGS ASan half. cargo-fuzz sets the ASan
# flag itself, but pin it explicitly; --cfg fuzzing matches libfuzzer-sys;
# RUST_DEBUG_FLAGS keeps DWARF < 4.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# Use the image's DEFAULT toolchain (the Dockerfile pins the nightly); a `+toolchain`
# override would make rustup try to install another channel into the shared /opt prefix.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# ── Pre-build the crate's OWN test suite (normal flags, no sanitizer) ────────────────
# mayhem/test.sh only RUNS `cargo test --features svg,image` (the same invocation as
# upstream's CI, .github/workflows/rust.yml); compiling it here caches every
# dev-dependency + test binary so the oracle run (and any offline re-run) never fetches.
echo "=== pre-building the fast_qr test suite (cargo test --no-run --features svg,image) ==="
RUSTFLAGS="" cargo test --no-run --features svg,image --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/fastqr_fuzz
