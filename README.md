# omp-computer-banner

A Codex-style system overlay for [OMP](https://github.com/oh-my-pi) computer use — so you can see what the agent is doing to your Mac while it does it.

![Pill with live step text](assets/pill.png)

![Full screen with breathing purple edge glow](assets/glow.png)

![Goodbye beat](assets/done.png)

## What it does

- **Pill** — a small floating banner below the menu bar showing the agent's current step, live (e.g. `OMP using computer · Clicking Save in Safari…`). Grows from a circle, click-through, never blocks input.
- **Glow** — a breathing purple wash bleeding in from the screen edges while computer use is active. Light from outside the screen, not a drawn line.
- **Camera blink** — a Mac-style white flash every time the agent takes a screenshot, fired after the capture so it never lands in the agent's own shot.
- **Goodbye beat** — on real finish the pill flips to `Done`, holds, and fades out with the glow. No focus stealing, ever.
- **Stays for the whole job** — the overlay survives gaps between steps (60s grace) instead of flashing per call, and hides when work truly ends.

Everything is invisible to the agent: the overlay opts out of screenshots and accessibility trees stay clean.

## Credits — read this first

**Human-directed, agent-written.** [BedirT](https://github.com/BedirT) designed and engineered every behavior in this repo: each interaction was specified by him, tested live on his screen, and tuned to his taste over many iterations. He did not write the code and never read it line by line — all implementation was written by an NAI coding agent.

This is not untouched vibe-code. Nothing here shipped without his eyes on its behavior.

## Requirements

- macOS (uses AppKit) + [OMP](https://github.com/oh-my-pi) installed
- Xcode Command Line Tools (`swiftc`): `xcode-select --install`
- Your terminal needs **Accessibility** + **Screen Recording** permission (macOS Settings) — that is for computer use itself, not this overlay

## Install

```bash
git clone https://github.com/BedirT/omp-computer-banner.git
cd omp-computer-banner
./install.sh
```

The installer copies the pill source and the banner extension into your agent dir
(`$PI_CODING_AGENT_DIR`, default `~/.omp/agent`), builds the overlay binary, and
appends the needed lines to `AGENTS.md` / `RULES.md` (skipped if already present).

Then:

1. Restart your omp session so the extension loads.
2. Run any computer step with a `title`, e.g. eval `computer.displays()` titled `Checking displays`.
3. Preview anytime: `/computer-banner` — hide: `/computer-banner-hide`.

## How it works

- `extensions/computer-banner.ts` — an OMP extension. It watches `eval` tool calls containing `computer.*`, writes the current step into a tiny status file, and manages the overlay process lifecycle (spawn on first use, 60s grace across gaps, `Done` beat + backstop kill on real end).
- `computer-pill/main.swift` — one small AppKit binary that draws everything: the pill, the edge glow, the camera blink (`--flash`), and the goodbye fade. Click-through (`ignoresMouseEvents`), hidden from screenshots (`.none` sharing), no dock icon, dies with its parent.
- The agent never touches overlay plumbing. It only sets the existing eval `title` field (enforced by the `RULES.md` addition); a verb guesser covers missing titles.

## Configure

- Grace period: `QUIET_MS` in `extensions/computer-banner.ts` (default 60000ms).
- Disable the glow: the extension spawns the pill without flags today — add `--no-glow` to the spawn args, or run the binary with `--no-glow` manually.
- `--capturable` keeps the overlay in screenshots (used for the shots above). Default hides it.

## Uninstall

```bash
rm -rf ~/.omp/agent/computer-pill ~/.omp/agent/extensions/computer-banner.ts
# then delete the `<!-- omp-computer-banner -->` blocks from
# ~/.omp/agent/AGENTS.md and ~/.omp/agent/RULES.md
```

## License

MIT — see [LICENSE](LICENSE).
