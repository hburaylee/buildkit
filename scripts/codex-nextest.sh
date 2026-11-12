#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Run the full codex-rs Rust nextest suite inside the Asterinas NixOS guest.
#
# This script ONLY covers the guest side. Everything it needs must already be
# in the guest, by whatever means you prefer (baked into the image, copied in,
# etc.):
#   - the codex checkout (sources + Cargo.lock) at --src
#   - vendored crates at --vendor-dir, or a populated CARGO_HOME registry cache
#   - rustc / cargo / cargo-nextest / just, gcc, pkg-config and the native dev
#     libraries, supplied by distro/etc_nixos/configuration.nix
#
# The whole run is offline: CARGO_NET_OFFLINE=true is always exported.

set -euo pipefail

SRC=${SRC:-/root/codex}
VENDOR_CONFIG=${VENDOR_CONFIG:-}
VENDOR_DIR=${VENDOR_DIR:-}          # empty means "$SRC/vendor"
STAGE=${STAGE:-all}
JOBS=${CARGO_JOBS:-2}
THREADS=${TEST_THREADS:-2}
SMOKE_CRATE=${SMOKE_CRATE:-codex-ansi-escape}
LOG=${LOG:-/root/nextest.log}
CARGO_HOME=${CARGO_HOME:-/root/.cargo}
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-/root/target}

log() { printf '\n>>> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: run-codex-nextest.sh [options]

Stages (--stage):
  check   verify tools, libcap and offline dependency resolution
  smoke   run one small crate (just test -p codex-ansi-escape)
  build   compile the whole workspace without running (cargo test --no-run)
  test    run the full nextest suite
  all     check -> smoke -> build -> test              (default)

Options:
  --src PATH            codex checkout in the guest       (default: /root/codex)
  --vendor-config PATH  cargo vendor config fragment to merge (optional)
  --vendor-dir PATH     vendored crates directory         (default: <src>/vendor)
  --stage NAME          check|smoke|build|test|all        (default: all)
  --threads N           nextest --test-threads             (default: 2)
  --jobs N              CARGO_BUILD_JOBS                   (default: 2)
  --smoke-crate NAME    crate used by the smoke stage
                        (default: codex-ansi-escape)
  --log PATH            nextest log                       (default: /root/nextest.log)
  -h, --help            show this help

Environment:
  SRC, VENDOR_CONFIG, VENDOR_DIR, STAGE, CARGO_JOBS, TEST_THREADS,
  SMOKE_CRATE, LOG, CARGO_HOME, CARGO_TARGET_DIR

Outputs:
  $LOG, <src>/codex-rs/junit.xml, $CARGO_TARGET_DIR
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --src)          [[ -n "${2:-}" ]] || die "--src needs a value";           SRC=$2;           shift 2 ;;
      --vendor-config) [[ -n "${2:-}" ]] || die "--vendor-config needs a value"; VENDOR_CONFIG=$2; shift 2 ;;
      --vendor-dir)   [[ -n "${2:-}" ]] || die "--vendor-dir needs a value";    VENDOR_DIR=$2;    shift 2 ;;
      --stage)        [[ -n "${2:-}" ]] || die "--stage needs a value";         STAGE=$2;         shift 2 ;;
      --threads)      [[ -n "${2:-}" ]] || die "--threads needs a value";       THREADS=$2;       shift 2 ;;
      --jobs)         [[ -n "${2:-}" ]] || die "--jobs needs a value";          JOBS=$2;          shift 2 ;;
      --smoke-crate)  [[ -n "${2:-}" ]] || die "--smoke-crate needs a value";   SMOKE_CRATE=$2;   shift 2 ;;
      --log)          [[ -n "${2:-}" ]] || die "--log needs a value";           LOG=$2;           shift 2 ;;
      -h|--help)      usage; exit 0 ;;
      *)              die "unknown option: $1" ;;
    esac
  done

  case "$STAGE" in
    check|smoke|build|test|all) ;;
    *) die "unknown stage '$STAGE' (use check|smoke|build|test|all)" ;;
  esac
  [[ -n "$VENDOR_DIR" ]] || VENDOR_DIR="$SRC/vendor"
}

setup_env() {
  export CARGO_HOME CARGO_TARGET_DIR
  export CARGO_NET_OFFLINE=true
  export CARGO_BUILD_JOBS="$JOBS"
  # The incremental cache grew to 17G+ across rebuilds and filled the disk;
  # disable it for this suite (dependencies are unaffected).
  export CARGO_INCREMENTAL=0
  export PATH=/run/current-system/sw/bin:$PATH
  mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR"

  # The v8 crate's build script downloads prebuilt rusty_v8 artifacts.
  # Use Codex's mirror, which publishes the ptrcomp+sandbox artifacts for
  # x86_64 Linux; the upstream denoland release does not have that combo.
  export RUSTY_V8_MIRROR="${RUSTY_V8_MIRROR:-https://github.com/openai/codex/releases/download}"
  export RUSTY_V8_MIRROR_TAG="${RUSTY_V8_MIRROR_TAG:-rusty-v8-v152.2.0}"

  # glib-sys's build script probes glib-2.0 via pkg-config. The NixOS guest
  # ships the glib runtime but not its dev output; point pkg-config at the
  # dev output copied into the guest store.
  export PKG_CONFIG_PATH="/nix/store/ry3k784adgykl9wbi6rj5fms6f71l6gy-glib-2.88.1-dev/lib/pkgconfig:/nix/store/aahpydd9bkl3hf35bh6dls1yi1fhxgiz-gstreamer-1.26.11-dev/lib/pkgconfig:/nix/store/mplv8myjkx09kqy9a5sfp6nr4a7cdayk-gst-plugins-base-1.26.11-dev/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

  # GNU ld has segfaulted while linking the huge codex-core test binary in
  # the Asterinas guest. --no-keep-memory lowers its peak memory usage.
  export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,--no-keep-memory"


  # rustc defaults to `cc` as linker; NixOS may not expose it in PATH.
  if ! command -v cc >/dev/null; then
    log "'cc' not found; using gcc as linker"
    export CC=gcc
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=gcc
  fi
}

setup_vendor() {
  [[ -d "$SRC/codex-rs" ]] \
    || die "codex sources not found at $SRC (use --src)"
  local cfg="$SRC/codex-rs/.cargo/config.toml"
  [[ -f "$cfg" ]] || die "missing $cfg"

  if [[ -n "$VENDOR_CONFIG" ]]; then
    [[ -f "$VENDOR_CONFIG" ]] || die "vendor config not found: $VENDOR_CONFIG"
    if ! grep -q 'vendored-sources' "$cfg"; then
      log "Merging $VENDOR_CONFIG into $cfg"
      sed "s|^directory = .*|directory = \"$VENDOR_DIR\"|" \
        "$VENDOR_CONFIG" >> "$cfg"
    fi
  fi

  # A config produced by `cargo vendor` on the host carries an absolute
  # directory= path that is invalid here. Rewrite it to the guest path.
  if grep -q '^directory = ' "$cfg" && [[ -d "$VENDOR_DIR" ]]; then
    local current
    current=$(sed -n 's|^directory = "\(.*\)"$|\1|p' "$cfg" | head -1)
    if [[ "$current" != "$VENDOR_DIR" ]]; then
      log "Rewriting vendored source directory: $current -> $VENDOR_DIR"
      sed -i "s|^directory = .*|directory = \"$VENDOR_DIR\"|" "$cfg"
    fi
  fi

  if [[ ! -d "$VENDOR_DIR" ]]; then
    log "WARNING: $VENDOR_DIR not found; relying on the CARGO_HOME registry cache"
  fi
}

stage_check() {
  log "Environment check"
  command -v rustc cargo cargo-nextest just python3 pkg-config >/dev/null \
    || die "a required tool is missing (see configuration.nix)"
  rustc --version
  cargo --version
  cargo-nextest --version
  just --version
  python3 --version
  pkg-config --modversion libcap
  ( cd "$SRC/codex-rs" \
    && cargo metadata --format-version 1 >/dev/null ) \
    || die "offline dependency resolution failed (check vendor config and --vendor-dir)"
  log "offline dependency resolution OK"
}

stage_smoke() {
  log "Smoke test: just test -p $SMOKE_CRATE"
  ( cd "$SRC" && just test -p "$SMOKE_CRATE" ) \
    || log "smoke test failed; inspect the output before continuing"
}

stage_build() {
  log "Full workspace compile (no run): cargo test --workspace --no-run"
  ( cd "$SRC/codex-rs" && cargo test --offline --workspace --no-run ) \
    || die "workspace compile failed; fix it before running the full suite"
}

stage_test() {
  log "Full nextest run (log: $LOG)"
  local rc=0
  set +e
  ( cd "$SRC" && just test --test-threads "$THREADS" ) 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[0]}
  set -e
  log "nextest exit=$rc  log=$LOG  junit=$SRC/codex-rs/junit.xml"
  return "$rc"
}

main() {
  parse_args "$@"
  setup_env
  setup_vendor
  stage_check
  case "$STAGE" in
    check) return 0 ;;
    smoke) stage_smoke; return 0 ;;
    build) stage_build; return 0 ;;
    test)  stage_test;  return 0 ;;
    all)   stage_smoke; stage_build; stage_test ;;
  esac
}

main "$@"

