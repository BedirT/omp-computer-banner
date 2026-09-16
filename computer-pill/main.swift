import Cocoa
import Darwin

// omp-computer-pill: tiny system-wide banner for OMP computer use.
// Non-interactive pill below the menu bar. Clicks pass through, screenshots
// skip it (sharingType .none), no dock icon (accessory policy).
// --status-file points at a "title\nstep" file the pill re-reads live, so the
// pill shows what the agent is doing right now, not just that it is busy.
// Exits when killed, or when --ppid parent dies (watchdog).

func argValue(_ name: String) -> String? {
  let args = CommandLine.arguments
  var i = 1
  while i < args.count {
    if args[i] == name, i + 1 < args.count { return args[i + 1] }
    i += 1
  }
  return nil
}

let defaultTitle = argValue("--title") ?? "OMP using computer"
let defaultDetail = argValue("--detail") ?? "Working…"
let statusPath = argValue("--status-file")
let ppid: Int32 = {
  if let s = argValue("--ppid"), let n = Int32(s) { return n }
  return 0
}()

var liveTitle = defaultTitle
var liveDetail = defaultDetail
var lastSeen = ""
var statusChanged = true

func readStatus() {
  guard let p = statusPath else { return }
  guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return }
  if s == lastSeen { return }
  lastSeen = s
  var lines = s.components(separatedBy: "\n")
  let t = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  lines.removeFirst()
  let d = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  liveTitle = t.isEmpty ? defaultTitle : String(t.prefix(48))
  liveDetail = d.isEmpty ? defaultDetail : String(d.prefix(72))
  statusChanged = true
}

let noGlow = CommandLine.arguments.contains("--no-glow")
// --capturable: keep the overlay in screenshots (for README shots). Default
// hides from captures so agent screenshots stay clean.
let sharing: NSWindow.SharingType = CommandLine.arguments.contains("--capturable") ? .readOnly : .none

// Screen-edge glow: light spilling in from outside the screen edges.
// No lines anywhere: four edge gradients plus corner radials, all fading to
// transparent toward the middle. Drawn once; breathing animates opacity.
final class GlowView: NSView {
 let edge = NSColor(red: 0.62, green: 0.36, blue: 1.0, alpha: 0.55)
 let clear = NSColor(red: 0.62, green: 0.36, blue: 1.0, alpha: 0.0)
 let depth: CGFloat = 110
 func wash(_ rect: NSRect, angle: CGFloat) {
 NSGradient(starting: edge, ending: clear)?.draw(in: rect, angle: angle)
 }
 override func draw(_ dirtyRect: NSRect) {
 let w = bounds.width, h = bounds.height, d = depth
 wash(NSRect(x: 0, y: h - d, width: w, height: d), angle: 270)
 wash(NSRect(x: 0, y: 0, width: w, height: d), angle: 90)
 wash(NSRect(x: 0, y: 0, width: d, height: h), angle: 0)
 wash(NSRect(x: w - d, y: 0, width: d, height: h), angle: 180)
 let corners: [NSPoint] = [
 NSPoint(x: 0, y: 0), NSPoint(x: w, y: 0),
 NSPoint(x: 0, y: h), NSPoint(x: w, y: h),
 ]
 for c in corners {
 NSGradient(starting: edge, ending: clear)?.draw(
 fromCenter: c, radius: 0, toCenter: c, radius: d * 1.4,
 options: [.drawsAfterEndingLocation])
 }
 }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main ?? NSScreen.screens.first else { exit(1) }
// --flash: Mac-style camera blink for agent screenshots. One short-lived
// process per capture, spawned on the eval result so it never lands in the shot.
if CommandLine.arguments.contains("--flash") {
 let blink = NSPanel(
 contentRect: screen.frame,
 styleMask: [.borderless, .nonactivatingPanel],
 backing: .buffered,
 defer: false
 )
 blink.level = .screenSaver
 blink.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
 blink.isOpaque = false
 blink.backgroundColor = .white
 blink.hasShadow = false
 blink.ignoresMouseEvents = true
 blink.hidesOnDeactivate = false
 blink.sharingType = sharing
 blink.alphaValue = 0
 blink.orderFrontRegardless()
 NSAnimationContext.runAnimationGroup({ ctx in
 ctx.duration = 0.07
 blink.animator().alphaValue = 0.5
 }, completionHandler: {
 NSAnimationContext.runAnimationGroup({ ctx in
 ctx.duration = 0.22
 blink.animator().alphaValue = 0
 }, completionHandler: {
 NSApp.terminate(nil)
 })
 })
 app.run()
 exit(0)
}

let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
let detailFont = NSFont.systemFont(ofSize: 12, weight: .light)
let midFont = NSFont.systemFont(ofSize: 12, weight: .regular)
let pillH: CGFloat = 38
let margin: CGFloat = 16
let iconW: CGFloat = 16
let iconGap: CGFloat = 8
let breath: CGFloat = 8

func pillText() -> NSAttributedString {
  let a = NSMutableAttributedString()
  a.append(NSAttributedString(string: liveTitle, attributes: [.font: titleFont, .foregroundColor: NSColor.white]))
  a.append(NSAttributedString(string: "   ·   ", attributes: [.font: midFont, .foregroundColor: NSColor(white: 1.0, alpha: 0.55)]))
  a.append(NSAttributedString(string: liveDetail, attributes: [.font: detailFont, .foregroundColor: NSColor(white: 1.0, alpha: 0.85)]))
  return a
}

func measure() -> (w: CGFloat, h: CGFloat) {
  let probe = NSTextField(labelWithString: "")
  probe.attributedStringValue = pillText()
  probe.frame = NSRect(x: 0, y: 0, width: 2000, height: pillH)
  probe.sizeToFit()
  return (probe.frame.width, probe.frame.height)
}

let iconImg = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "computer")
let hasIcon = iconImg != nil
let labelX: CGFloat = margin + (hasIcon ? iconW + iconGap : 0)

let menuH = NSStatusBar.system.thickness
let baseY = screen.frame.maxY - menuH - 30 - pillH

let panel = NSPanel(
  contentRect: NSRect(x: 0, y: baseY, width: 220, height: pillH),
  styleMask: [.borderless, .nonactivatingPanel],
  backing: .buffered,
  defer: false
)
panel.level = .screenSaver
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.ignoresMouseEvents = true
panel.hidesOnDeactivate = false
panel.sharingType = sharing
panel.alphaValue = 0.78

let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 220, height: pillH))
effect.material = .hudWindow
effect.state = .active
effect.wantsLayer = true
effect.layer?.cornerRadius = pillH / 2
effect.layer?.masksToBounds = true
panel.contentView = effect

if let img = iconImg {
  let icon = NSImageView(frame: NSRect(x: margin, y: (pillH - iconW) / 2, width: iconW, height: iconW))
  icon.image = img
  icon.contentTintColor = .white
  icon.imageScaling = .scaleProportionallyUpOrDown
  effect.addSubview(icon)
}

let label = NSTextField(labelWithString: "")
label.alignment = .center
label.lineBreakMode = .byTruncatingTail
effect.addSubview(label)

func layout() {
  let (tw, th) = measure()
  let contentW = tw + (hasIcon ? iconW + iconGap : 0)
  let pillW = min(max(contentW + margin * 2 + breath, 220), screen.frame.width - 80)
  panel.setFrame(NSRect(x: screen.frame.midX - pillW / 2, y: baseY, width: pillW, height: pillH), display: true)
  effect.frame = NSRect(x: 0, y: 0, width: pillW, height: pillH)
  label.attributedStringValue = pillText()
  label.frame = NSRect(x: labelX, y: (pillH - th) / 2, width: pillW - labelX - margin, height: th)
}

readStatus()
statusChanged = false
layout()
// Entrance: a small circle drops from the menu bar, then opens to full width
// and reveals the text. Later text updates reuse layout() and never replay this.
let endFrame = panel.frame
let endEffect = effect.frame
let dotSize: CGFloat = 38
panel.setFrame(NSRect(x: screen.frame.midX - dotSize / 2, y: baseY + pillH - dotSize, width: dotSize, height: dotSize), display: true)
effect.frame = NSRect(x: 0, y: 0, width: dotSize, height: dotSize)
label.isHidden = true
panel.alphaValue = 0
panel.orderFrontRegardless()
NSAnimationContext.runAnimationGroup({ ctx in
 ctx.duration = 0.55
 ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
 panel.animator().setFrame(endFrame, display: true)
 effect.animator().frame = endEffect
 panel.animator().alphaValue = 0.78
}, completionHandler: {
 label.isHidden = false
})
var goodbyeFrom: Date? = nil
var glowPanel: NSPanel? = nil
// Screen-edge glow: same lifecycle as the pill (main screen only).
if !noGlow {
 let glow = NSPanel(
 contentRect: screen.frame,
 styleMask: [.borderless, .nonactivatingPanel],
 backing: .buffered,
 defer: false
 )
 glow.level = .screenSaver
 glow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
 glow.isOpaque = false
 glow.backgroundColor = .clear
 glow.hasShadow = false
 glow.ignoresMouseEvents = true
 glow.hidesOnDeactivate = false
 glow.sharingType = sharing
 let glowView = GlowView(frame: NSRect(origin: .zero, size: screen.frame.size))
 glowView.autoresizingMask = [.width, .height]
 glow.contentView = glowView
 glow.orderFrontRegardless()
 glowPanel = glow
 var phase: CGFloat = 0
 let born = Date()
 _ = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
 phase += (1.0 / 30.0) * 2.0 * .pi / 3.0
 let fade = min(1.0, Date().timeIntervalSince(born) / 1.0)
 let out = goodbyeFrom.map { min(1.0, Date().timeIntervalSince($0) / 0.7) } ?? 0
 glow.alphaValue = (0.45 + 0.40 * (0.5 - 0.5 * cos(phase))) * fade * (1 - out)
 }
}

// Live step updates: re-read the status file, re-layout on change.
_ = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
  readStatus()
  if statusChanged {
    statusChanged = false
    layout()
  }
}

// Goodbye beat: the extension writes "Done" on real end. Show it, fade out,
// exit on our own (plus a delayed backstop terminate if anything sticks).
var sayingGoodbye = false
func goodbye() {
 if sayingGoodbye { return }
 sayingGoodbye = true
 goodbyeFrom = Date()
 NSAnimationContext.runAnimationGroup({ ctx in
 ctx.duration = 0.7
 panel.animator().alphaValue = 0
 }, completionHandler: {
 NSApp.terminate(nil)
 })
 _ = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
 NSApp.terminate(nil)
 }
}
_ = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
 if !sayingGoodbye && liveDetail == "Done" { layout(); goodbye() }
}

// Watchdog: exit if the parent omp process is gone (stale-pill safety).
if ppid > 0 {
  _ = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    if Darwin.kill(ppid, 0) != 0 && errno == ESRCH {
      NSApp.terminate(nil)
    }
  }
}

app.run()
