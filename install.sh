#!/bin/bash
# Installer for omp-computer-banner. Codex-style overlay for OMP computer use.
set -euo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
SRC="$(cd "$(dirname "$0")" && pwd)"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: macOS only (uses AppKit)." >&2; exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install Xcode Command Line Tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

mkdir -p "$AGENT_DIR/computer-pill" "$AGENT_DIR/extensions"
cp "$SRC/computer-pill/main.swift" "$AGENT_DIR/computer-pill/main.swift"
cp "$SRC/extensions/computer-banner.ts" "$AGENT_DIR/extensions/computer-banner.ts"
swiftc -O -o "$AGENT_DIR/computer-pill/omp-computer-pill" \
  "$AGENT_DIR/computer-pill/main.swift" -framework Cocoa

if ! grep -q "omp-computer-banner\|computer-banner.*overlay" "$AGENT_DIR/AGENTS.md" 2>/dev/null; then
  cat >> "$AGENT_DIR/AGENTS.md" <<'EOF'

<!-- omp-computer-banner -->
- `computer-banner` overlay is enabled: on any `computer.*` eval a system pill, a breathing purple screen-edge glow, and an editor widget (`OMP using computer · Esc to cancel`) appear; the pill stays across gaps in computer work and hides ~60s after the last computer step, or at once on `/computer-banner-hide`.
EOF
fi

if ! grep -q "omp-computer-banner\|Computer-use narration" "$AGENT_DIR/RULES.md" 2>/dev/null; then
  cat >> "$AGENT_DIR/RULES.md" <<'EOF'

<!-- omp-computer-banner -->
## Computer-use narration
- Every `computer.*` eval call MUST set a short `title` naming the step, verb first (e.g. `title: "Clicking Save in Safari"`). Keep it under ~70 chars.
- The banner extension reads that title and shows it live in the on-screen pill, so the user sees what you are doing as you do it.
- Never write the pill status file yourself; the extension owns it.
- Stopping a run: the user focuses the terminal and presses Esc (the on-screen pill is click-through and cannot receive keys. Signals must never be sent to the session. SIGINT kills it).
EOF
fi

cat <<EOF
Installed to $AGENT_DIR.
- Give your terminal Accessibility + Screen Recording (macOS Settings) for computer use.
- Restart your omp session so the extension loads.
- Preview: /computer-banner    Hide now: /computer-banner-hide
EOF
