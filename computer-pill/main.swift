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
 let stops: [(CGFloat, CGFloat)] = [(0.0, 0.55), (0.2, 0.49), (0.4, 0.36), (0.6, 0.19), (0.8, 0.06), (0.9, 0.015), (1.0, 0.0)]
 NSGradient(colors: stops.map { edge.withAlphaComponent($0.1) }, atLocations: stops.map { $0.0 }, colorSpace: .deviceRGB)?.draw(in: rect, angle: angle)
 }
 override func draw(_ dirtyRect: NSRect) {
 let w = bounds.width, h = bounds.height, d = depth
 wash(NSRect(x: 0, y: h - d, width: w, height: d), angle: 270)
 wash(NSRect(x: 0, y: 0, width: w, height: d), angle: 90)
 wash(NSRect(x: 0, y: 0, width: d, height: h), angle: 0)
 wash(NSRect(x: w - d, y: 0, width: d, height: h), angle: 180)
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

// --stage: README staging only. Full-bleed gradient backdrop drawn by the
// binary itself, so shots have no foreign windows, seams, or personal data.
final class BackdropView: NSView {
 override func draw(_ dirtyRect: NSRect) {
 let top = NSColor(red: 0.17, green: 0.17, blue: 0.28, alpha: 1.0)
 let bottom = NSColor(red: 0.25, green: 0.22, blue: 0.36, alpha: 1.0)
 NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: 270)
 // soft wallpaper-like color fields, so the glow reads as ambient light
 let w = bounds.width, h = bounds.height
 func blob(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: NSColor) {
 NSGradient(starting: c, ending: c.withAlphaComponent(0))?.draw(
 fromCenter: NSPoint(x: cx, y: cy), radius: 0,
 toCenter: NSPoint(x: cx, y: cy), radius: r,
 options: [.drawsAfterEndingLocation])
 }
 blob(w * 0.18, h * 0.72, w * 0.45, NSColor(red: 0.35, green: 0.42, blue: 0.9, alpha: 0.12))
 blob(w * 0.85, h * 0.25, w * 0.5, NSColor(red: 0.2, green: 0.7, blue: 0.75, alpha: 0.07))
 // faint deterministic grain: breaks Mach bands on flat fields, like real
 // desktop texture does, so the shot reads the way the glow looks live
 var seed: UInt64 = 0x9E3779B97F4A7C15
 let dots = Int(bounds.width * bounds.height / 700)
 var i = 0
 while i < dots {
 seed = seed &* 6364136223846793005 &+ 1442695040888963407
 let x = CGFloat((seed >> 33) % UInt64(max(1, Int(bounds.width))))
 seed = seed &* 6364136223846793005 &+ 1442695040888963407
 let y = CGFloat((seed >> 33) % UInt64(max(1, Int(bounds.height))))
 ((i & 1) == 0 ? NSColor.white : NSColor.black).withAlphaComponent(0.03).setFill()
 NSRect(x: x, y: y, width: 1, height: 1).fill()
 i += 1
 }
 }
}
if CommandLine.arguments.contains("--stage") {
 let back = NSPanel(
 contentRect: screen.frame,
 styleMask: [.borderless, .nonactivatingPanel],
 backing: .buffered,
 defer: false
 )
 back.level = .screenSaver
 back.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
 back.isOpaque = false
 back.backgroundColor = .clear
 back.hasShadow = false
 back.ignoresMouseEvents = true
 back.hidesOnDeactivate = false
 back.sharingType = sharing
 back.contentView = BackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
 back.orderFrontRegardless()
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
 // --stage freezes the breath at its mean so README shots are deterministic.
 let breath = CommandLine.arguments.contains("--stage") ? 0.65 : (0.45 + 0.40 * (0.5 - 0.5 * cos(phase)))
 glow.alphaValue = breath * fade * (1 - out)
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
