import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

type BannerUI = {
  setStatus: (key: string, text: string) => void;
  notify?: (message: string, level?: string) => void;
  setWorkingMessage?: (message: string | undefined) => void;
  setTitle?: (title: string) => void;
  setWidget?: (id: string, content: unknown, options?: unknown) => void;
};

function getUI(ctx: unknown): BannerUI | undefined {
  if (typeof ctx !== "object" || ctx === null) return undefined;
  if (!("ui" in ctx)) return undefined;
  const ui = ctx.ui;
  if (typeof ui !== "object" || ui === null) return undefined;
  if (!("setStatus" in ui)) return undefined;
  const status = ui.setStatus;
  if (typeof status !== "function") return undefined;
  return ui as BannerUI;
}

function readEvalCall(event: unknown): { code: string; title?: string } | undefined {
 if (typeof event !== "object" || event === null) return undefined;
 if (!("toolName" in event) || event.toolName !== "eval") return undefined;
 if (!("input" in event)) return undefined;
 const input = event.input;
 if (typeof input !== "object" || input === null) return undefined;
 if (!("code" in input)) return undefined;
 const code = input.code;
 if (typeof code !== "string") return undefined;
 const title = "title" in input && typeof input.title === "string" ? input.title : undefined;
 return { code, title };
}

function isEvalResult(event: unknown): boolean {
  return (
    typeof event === "object" &&
    event !== null &&
    "toolName" in event &&
    event.toolName === "eval"
  );
}

// Codex-style banner whenever Eval runs computer.* code.
// Eval prelude calls are host-bridge calls, not AgentTools, so we hook the
// parent `eval` tool which DOES emit events. Surfaces: system pill above the
// menu bar (visible even when the terminal is hidden) + editor widget +
// status/working-message/title. The banner stays up for the whole turn
// (cleared on turn_end), not per single eval call, so it does not flash away.
declare const Bun:
 | {
 spawn: (cmd: string[], opts?: Record<string, unknown>) => PillProc;
 write: (path: string, content: string) => Promise<unknown>;
 }
 | undefined;

declare const process:
  | { pid: number; env: Record<string, string | undefined> }
  | undefined;

type PillProc = {
  kill: (sig?: number | string) => void;
};

let pill: PillProc | undefined;

function pillCandidates(): string[] {
  const out: string[] = [];
  if (typeof process !== "undefined") {
    const agentDir = process.env["PI_CODING_AGENT_DIR"];
    if (agentDir) out.push(`${agentDir}/computer-pill/omp-computer-pill`);
    const home = process.env["HOME"];
    if (home) out.push(`${home}/.omp/agent/computer-pill/omp-computer-pill`);
  }
  return out;
}

function spawnPill() {
  if (pill) return;
  if (typeof Bun === "undefined" || typeof process === "undefined") return;
 const pid = String(process.pid);
 const sp = statusPath();
 for (const bin of pillCandidates()) {
 try {
 pill = Bun.spawn(sp ? [bin, "--ppid", pid, "--status-file", sp] : [bin, "--ppid", pid], {
        stdout: "ignore",
        stderr: "ignore",
        stdin: "ignore",
      });
      return;
    } catch {
      // missing binary here — try the next candidate path
    }
  }
}

function killPill() {
  if (!pill) return;
  const p = pill;
  pill = undefined;
  try {
    p.kill(15);
  } catch {
    // already gone
  }
}
function flashScreen() {
 if (typeof Bun === "undefined" || typeof process === "undefined") return;
 const pid = String(process.pid);
 for (const bin of pillCandidates()) {
 try {
 Bun.spawn([bin, "--flash", "--ppid", pid], { stdout: "ignore", stderr: "ignore", stdin: "ignore" });
 return;
 } catch {
 // missing binary here — try the next candidate path
 }
 }
}
function statusPath(): string | undefined {
 if (typeof process === "undefined") return undefined;
 const agentDir = process.env["PI_CODING_AGENT_DIR"];
 if (agentDir) return `${agentDir}/computer-pill/status.txt`;
 const home = process.env["HOME"];
 if (home) return `${home}/.omp/agent/computer-pill/status.txt`;
 return undefined;
}

// Short human line for the pill, e.g. "Clicking in Safari…".
// The agent's eval `title` wins when set (rules require it on computer calls);
// otherwise the verb is guessed from the code so the pill never lies.
function describeStep(code: string, title?: string): string {
 const clean = (title ?? "").trim();
 if (clean) return clean.slice(0, 72);
 const app =
 code.match(/window\(\s*\{\s*app\s*:\s*"([^"]+)"/)?.[1] ??
 code.match(/windows\(\s*\{\s*app\s*:\s*"([^"]+)"/)?.[1];
 const where = app ? ` in ${app}` : "";
 if (/screenshot/i.test(code)) return `Looking at the screen${where}…`;
 if (/\bdoubleClick\b/i.test(code)) return `Double-clicking${where}…`;
 if (/\bclick\b/i.test(code)) return `Clicking${where}…`;
 if (/\bsetValue\b/i.test(code)) return `Entering text${where}…`;
 if (/\btype\b/i.test(code)) return `Typing${where}…`;
 if (/\bpress\b/i.test(code)) return `Pressing keys${where}…`;
 if (/\bdrag\b/i.test(code)) return `Dragging${where}…`;
 if (/\bscroll\b/i.test(code)) return `Scrolling${where}…`;
 if (/clipboard/i.test(code)) return `Using the clipboard…`;
 if (/\b(ax|find|elementAt|focusedElement|bounds|attributes)\b/i.test(code)) return `Reading the window${where}…`;
 return `Working${where}…`;
}

async function writeStatusFile(step: string): Promise<void> {
 try {
 const path = statusPath();
 if (!path) return;
 if (typeof Bun === "undefined") return;
 await Bun.write(path, `OMP using computer\n${step}`);
 } catch {
 // the pill keeps its last line; never break a run over a label
 }
}

export default function (pi: ExtensionAPI) {
  pi.setLabel("Computer banner");

  const KEY = "computer-banner";
  let active = false;
 let pendingFlash = false;

 function show(ctx: unknown, detail: string, step?: string) {
 clearTimeout(hideTimer); hideTimer = undefined;
 const ui = getUI(ctx);
 if (!ui) return;
 active = true;
    const line = `OMP using computer · Esc to cancel ${detail}`;
    try {
 ui.setWidget?.(KEY, [line, step || "Your mouse and keys may move on their own."], {
        placement: "aboveEditor",
      });
    } catch {}
    try {
      spawnPill();
    } catch {}
    try {
      ui.setStatus(KEY, line);
    } catch {}
    try {
      ui.setWorkingMessage?.(`Using computer · Esc to cancel`);
    } catch {}
    try {
      ui.notify?.(`OMP is using your computer · Esc to cancel`, "warning");
    } catch {}
    try {
      ui.setTitle?.(`OMP using computer`);
    } catch {}
  }

let hideTimer: Timer | undefined;
 const QUIET_MS = 60000;

 function clearBanner(ui: BannerUI) {
 try {
 ui.setWidget?.(KEY, undefined);
 } catch {}
 try {
 ui.setStatus(KEY, "");
 } catch {}
 try {
 ui.setWorkingMessage?.(undefined);
 } catch {}
 }

 function hideNow(ctx: unknown) {
 if (hideTimer) { clearTimeout(hideTimer); hideTimer = undefined; }
 try {
 killPill();
 } catch {}
 if (!active) return;
 active = false;
 const ui = getUI(ctx);
 if (!ui) return;
 clearBanner(ui);
 }

 // Real end: let the pill say Done and fade itself out. The pill exits on
 // its own; the delayed kill below is only a backstop (reuses hideTimer so
 // any new computer call cancels it in show()).
 async function goodbye(ctx: unknown) {
 clearTimeout(hideTimer);
 const ui = getUI(ctx);
 if (ui) clearBanner(ui);
 if (!active) { try { killPill(); } catch {} return; }
 active = false;
 try { await writeStatusFile("Done"); } catch {}
 hideTimer = setTimeout(() => { hideTimer = undefined; try { killPill(); } catch {} }, 8000);
 }

 // turn_end fires between agent steps too, so wait for quiet before hiding:
 // a new computer call inside the window cancels the hide and keeps the pill.
 function hideAfterQuiet(ctx: unknown) {
 if (!active) { try { killPill(); } catch {} return; }
 const ui = getUI(ctx);
 clearTimeout(hideTimer);
 hideTimer = setTimeout(() => {
 hideTimer = undefined;
 try { killPill(); } catch {}
 active = false;
 if (ui) clearBanner(ui);
 }, QUIET_MS);
 }

 pi.on("tool_call", async (event, ctx) => {
 const call = readEvalCall(event);
 if (!call) return;
 if (!call.code.includes("computer.")) { pendingFlash = false; return; }
 if (/\bscreenshot\s*\(/i.test(call.code)) pendingFlash = true;
 const fg = call.code.includes("foreground") ? "(foreground)" : "(background/AX)";
 const step = describeStep(call.code, call.title);
 await writeStatusFile(step);
 show(ctx, fg, step);
 });

  // NOTE: intentionally no hide on tool_result — one turn often runs several
  // eval calls; hiding per call makes the banner flash and disappear.
 pi.on("tool_result", async (event, ctx) => {
 if (!isEvalResult(event)) return;
 void ctx;
 if (!pendingFlash) return;
 pendingFlash = false;
 try { flashScreen(); } catch {}
 });

 pi.on("turn_end", async (_event, ctx) => hideAfterQuiet(ctx));
 pi.on("agent_end", async (_event, ctx) => goodbye(ctx));
 pi.on("session_shutdown", async (_event, ctx) => goodbye(ctx));

  pi.registerCommand("computer-banner", {
 description: "Preview the computer-use banner (hides after idle)",
    handler: async (_args, ctx) => {
 await writeStatusFile("Previewing the banner…");
 show(ctx, "(manual test)", "Previewing the banner…");
 getUI(ctx)?.notify?.("Banner preview on — hides after idle.", "info");
    },
  });

  pi.registerCommand("computer-banner-hide", {
    description: "Hide the computer-use banner now",
    handler: async (_args, ctx) => {
 hideNow(ctx);
    },
  });
}
