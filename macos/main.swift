// ClockClock · macOS 状态栏版
//
// 和网页版同一套字形：一个数字 = 2 列 × 3 行 = 6 个表盘 = 12 根指针，
// 0 = 12 点方向、顺时针。状态栏只有 22pt 高，所以每格表盘 6.65pt、
// 只画指针不画盘面（模板图，自动跟随浅色 / 深色菜单栏）。
//
// 节奏与网页版一致：时:分换字 15 秒慢慢转到位（顺时针兜一圈），
// 秒位每秒转 0.8 秒、停 0.2 秒（可按需关掉，或仅在电池供电时关掉）。

import AppKit
import IOKit.ps

let kBarHeight = NSStatusBar.system.thickness          // 22pt
let kMargin: CGFloat = 0.5
let kGapRatio: CGFloat = 0.08
let kStrokeRatio: CGFloat = 0.22
let kHandRatio: CGFloat = 0.52
let kPadLeft: CGFloat = 4
let kPadRight: CGFloat = 8

let kSepPlain: CGFloat = 0.42          // 组间额外间距（不画冒号）
let kSepColon: CGFloat = 0.90          // 组间额外间距（画冒号）
let kPipRatio: CGFloat = 0.24          // 冒号圆点直径 / 面宽
let kPipOffset: CGFloat = 0.44         // 冒号两点中心到中线的偏移 / 面宽

let kSweepChoices: [Double] = [3, 5, 10, 15, 30]   // 时:分换字时长可选档位（秒）
let kDefaultSweep: Double = 10                     // 默认 10 秒
let kTickDuration: Double = 0.8        // 秒位每格时长（秒）
let kFrameRate: Double = 10            // 动画帧率（这个尺寸下 10fps 已经看不出台阶）

// MARK: - 字形表

let glyphs: [[[CGFloat]]] = [
  [[90, 180], [180, 270], [0, 180], [0, 180], [0, 90], [0, 270]],     // 0
  [[225, 225], [180, 180], [225, 225], [0, 180], [225, 225], [0, 0]], // 1
  [[90, 90], [180, 270], [90, 180], [0, 270], [0, 90], [270, 270]],   // 2
  [[90, 90], [180, 270], [90, 90], [0, 270], [90, 90], [0, 270]],     // 3
  [[180, 180], [180, 180], [0, 90], [180, 270], [225, 225], [0, 0]],  // 4
  [[90, 180], [270, 270], [0, 90], [180, 270], [90, 90], [0, 270]],   // 5
  [[90, 180], [270, 270], [0, 180], [180, 270], [0, 90], [0, 270]],   // 6
  [[90, 90], [180, 270], [225, 225], [0, 180], [225, 225], [0, 0]],   // 7
  [[90, 180], [180, 270], [0, 90], [0, 270], [0, 90], [0, 270]],      // 8
  [[90, 180], [180, 270], [0, 90], [0, 180], [90, 90], [0, 270]]      // 9
]

// MARK: - 旋转动画

enum SpinStyle: Int, CaseIterable {
  case mechanical = 0, linear, inertia, bounce, snappy

  var title: String {
    switch self {
    case .mechanical: return "机械（默认）"
    case .linear: return "匀速"
    case .inertia: return "惯性"
    case .bounce: return "回弹"
    case .snappy: return "急停"
    }
  }

  /// CSS cubic-bezier(x1, y1, x2, y2)
  var curve: (Double, Double, Double, Double) {
    switch self {
    case .mechanical: return (0.62, 0.02, 0.28, 1)
    case .linear: return (0, 0, 1, 1)
    case .inertia: return (0.16, 1, 0.3, 1)
    case .bounce: return (0.34, 1.56, 0.64, 1)
    case .snappy: return (0.9, 0.02, 0.1, 1)
    }
  }
}

struct Hand {
  var from: Double = 0
  var to: Double = 0
  var start: Double = 0
  var dur: Double = 0.001
  var c1x: Double = 0.62
  var c1y: Double = 0.02
  var c2x: Double = 0.28
  var c2y: Double = 1

  func angle(at now: Double) -> Double {
    if dur <= 0.001 { return to }
    let p = min(1, max(0, (now - start) / dur))
    let e = Easing.cubicBezier(p, c1x, c1y, c2x, c2y)
    return from + (to - from) * e
  }
}

enum Easing {
  static func cubic(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
    let m = 1 - t
    return 3 * m * m * t * p1 + 3 * m * t * t * p2 + t * t * t
  }

  /// 先由 x 反解 t，再取 y（y 允许 >1，用来做回弹）
  static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    var lo = 0.0, hi = 1.0, t = x
    for _ in 0..<26 {
      let xt = cubic(t, x1, x2)
      if abs(xt - x) < 1e-6 { break }
      if xt < x { lo = t } else { hi = t }
      t = (lo + hi) / 2
    }
    return cubic(t, y1, y2)
  }
}

// MARK: - 时钟模型 + 绘制

final class ClockClock {
  let handsCount = 36 * 2
  var hands: [Hand]

  // 显示与节奏开关
  var showSeconds = true
  var showColons = true
  var blinkColons = true
  var smooth = true
  var smoothSeconds = false
  var batteryThrottle = true
  var onBattery = false
  var spinStyle: SpinStyle = .mechanical
  var sweepDuration: Double = kDefaultSweep

  private(set) var minute = ""
  private(set) var second = ""
  private(set) var blinkOn = true

  let face: CGFloat
  let pitch: CGFloat

  init() {
    hands = Array(repeating: Hand(), count: handsCount)
    face = (kBarHeight - 2 * kMargin) / 3.16
    pitch = face * (1 + kGapRatio)
  }

  var secondsSmooth: Bool {
    smooth && smoothSeconds && !(onBattery && batteryThrottle)
  }

  struct Layout {
    var xs: [CGFloat] = []        // 每列左边缘
    var colons: [CGFloat] = []    // 每个分隔的中心
    var width: CGFloat = 0
  }

  func layout() -> Layout {
    let faceGap = face * kGapRatio
    let sep = face * (showColons ? kSepColon : kSepPlain)
    let columns = showSeconds ? 12 : 8
    var out = Layout()
    var x: CGFloat = 0
    for i in 0..<columns {
      out.xs.append(x)
      let separator = (i == 3) || (i == 7 && showSeconds)
      if separator {
        out.colons.append(x + face + (faceGap + sep) / 2)
        x += face + faceGap + sep
      } else {
        x += face + faceGap
      }
    }
    out.width = out.xs.last! + face + kPadLeft + kPadRight
    return out
  }

  var imageSize: NSSize {
    NSSize(width: layout().width, height: kBarHeight)
  }

  func faceIndex(digit d: Int, clock k: Int) -> Int {
    let row = k / 2, col = k % 2
    if d < 4 { return row * 8 + d * 2 + col }
    return 24 + row * 4 + (d - 4) * 2 + col
  }

  func currentTime() -> String {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
    return String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
  }

  func apply(_ time: String, at now: Double) {
    guard time.count >= 4 else { return }
    let hhmm = String(time.prefix(4))
    let hasSeconds = time.count >= 6
    if hhmm != minute {
      minute = hhmm
      setDigits(time, from: 0, to: 3, dur: smooth ? sweepDuration : 0.001, spin: smooth, now: now)
    }
    guard hasSeconds else { return }
    let ss = String(time.suffix(2))
    if ss != second {
      second = ss
      setDigits(time, from: 4, to: 5, dur: secondsSmooth ? kTickDuration : 0.001, spin: false, now: now)
    }
    blinkOn = (Int(ss) ?? 0) % 2 == 0
  }

  func setDigits(_ time: String, from: Int, to: Int, dur: Double, spin: Bool, now: Double) {
    let chars = Array(time)
    let curve = spinStyle.curve
    for d in from...to {
      guard let digit = Int(String(chars[d])) else { continue }
      for k in 0..<6 {
        let idx = faceIndex(digit: d, clock: k)
        for h in 0..<2 {
          let slot = idx * 2 + h
          let current = hands[slot].angle(at: now)
          let base = current.truncatingRemainder(dividingBy: 360)
          let from360 = base < 0 ? base + 360 : base
          var delta = Double(glyphs[digit][k][h]) - Double(from360)
          delta = delta.truncatingRemainder(dividingBy: 360)
          if delta < 0 { delta += 360 }
          if spin { delta += 360 }
          if delta <= 0.0005 { continue }
          hands[slot] = Hand(from: current, to: current + delta, start: now, dur: dur,
                             c1x: curve.0, c1y: curve.1, c2x: curve.2, c2y: curve.3)
        }
      }
    }
  }

  /// 当前所有指针角度（量化）+ 冒号相位，用于判断这一帧要不要重绘
  func signature(at now: Double) -> String {
    var out = ""
    out.reserveCapacity(hands.count * 4 + 8)
    for h in hands {
      out += String(Int((h.angle(at: now) / 1.5).rounded()))
      out += ","
    }
    out += blinkOn ? "1" : "0"
    out += showColons ? "c" : "-"
    out += showSeconds ? "s" : "-"
    return out
  }

  func isAnimating(at now: Double) -> Bool {
    hands.contains { $0.start + $0.dur > now }
  }

  func draw(in rect: NSRect, scale: CGFloat) {
    let geo = layout()
    let hpx = rect.height * scale
    let count = showSeconds ? 12 : 8
    let ink = NSColor.black
    ink.setFill()
    ink.setStroke()

    let path = NSBezierPath()                       // 所有指针一次 stroke
    path.lineWidth = max(1.1, kStrokeRatio * face) * scale
    path.lineCapStyle = .butt
    let now = CACurrentMediaTime()
    for col in 0..<count {
      for row in 0..<3 {
        let idx = col < 8 ? row * 8 + col : 24 + row * 4 + (col - 8)
        let cx = (geo.xs[col] + face / 2 + kPadLeft) * scale
        let cyTop = (kMargin + CGFloat(row) * pitch + face / 2) * scale
        for h in 0..<2 {
          let rad = hands[idx * 2 + h].angle(at: now) * .pi / 180
          let ex = cx + sin(rad) * kHandRatio * face * scale
          let eyTop = cyTop - cos(rad) * kHandRatio * face * scale
          path.move(to: NSPoint(x: cx, y: hpx - cyTop))
          path.line(to: NSPoint(x: ex, y: hpx - eyTop))
        }
      }
    }
    path.stroke()

    // 冒号：最后一个跟着秒跳动，前面的常亮
    let midY = (kMargin + pitch + face / 2) * scale
    let pipD = kPipRatio * face * scale
    let offset = kPipOffset * face * scale
    for (i, colonX) in geo.colons.enumerated() {
      let isLast = i == geo.colons.count - 1
      if isLast && blinkColons && !blinkOn { continue }
      let cx = (colonX + kPadLeft) * scale
      for dy in [-offset, offset] {
        let rect = NSRect(x: cx - pipD / 2, y: hpx - (midY + dy) - pipD / 2, width: pipD, height: pipD)
        let pip = NSBezierPath(ovalIn: rect)
        pip.fill()
      }
    }
  }
}

// MARK: - 版本

func versionParts(_ v: String) -> [Int] {
  v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    .split(separator: ".")
    .map { Int($0) ?? 0 }
}

func isVersionNewer(_ remote: String, than local: String) -> Bool {
  let r = versionParts(remote), l = versionParts(local)
  for i in 0..<max(r.count, l.count) {
    let a = i < r.count ? r[i] : 0
    let b = i < l.count ? l[i] : 0
    if a != b { return a > b }
  }
  return false
}

// MARK: - 电源

func currentPowerIsBattery() -> Bool {
  if ProcessInfo.processInfo.environment["CLOCKCLOCK_BATTERY"] == "1" { return true }
  guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
        let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
  return (type as String) == (kIOPSBatteryPowerValue as String)
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var clock = ClockClock()
  private var tickTimer: Timer?
  private var renderTimer: Timer?
  private var signalSources: [DispatchSourceSignal] = []
  private var renderCount = 0

  private var latestTag: String?
  private var latestURL: URL?
  private var hasUpdate = false
  private var updateItem: NSMenuItem?
  private var checkItem: NSMenuItem?
  private var autoCheckTimer: Timer?

  private var localVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
  }

  private let repo = "CooperZhuang/clockclock-24"

  private let defaults = UserDefaults.standard
  private let loginLabel = "com.cooper.clockclock-menubar"
  private var appPath: String { Bundle.main.bundlePath }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let d = defaults
    clock.showSeconds = d.object(forKey: "showSeconds") as? Bool ?? true
    clock.showColons = d.object(forKey: "showColons") as? Bool ?? true
    clock.blinkColons = d.object(forKey: "blinkColons") as? Bool ?? true
    clock.smooth = d.object(forKey: "smooth") as? Bool ?? true
    clock.smoothSeconds = d.object(forKey: "smoothSeconds") as? Bool ?? false
    clock.batteryThrottle = d.object(forKey: "batteryThrottle") as? Bool ?? true
    clock.spinStyle = SpinStyle(rawValue: d.integer(forKey: "spinStyle")) ?? .mechanical
    let sweep = d.integer(forKey: "sweepSeconds")
    clock.sweepDuration = sweep > 0 ? Double(sweep) : kDefaultSweep
    clock.onBattery = currentPowerIsBattery()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.toolTip = "ClockClock"

    buildMenu()
    refreshMenuStates()
    applyStateNow()
    scheduleTick()

    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(wakeUp),
      name: NSWorkspace.didWakeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(powerChanged),
      name: Notification.Name("ClockClockPowerChanged"), object: nil)

    // 电源变化（插拔电源、切换到电池）
    let powerCallback: IOPowerSourceCallbackType = { _ in
      NotificationCenter.default.post(name: Notification.Name("ClockClockPowerChanged"), object: nil)
    }
    if let source = IOPSNotificationCreateRunLoopSource(powerCallback, nil)?.takeRetainedValue() {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    // 调试钩子：kill -USR1 导出当前帧；kill -USR2 切换开机自启
    let src1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    src1.setEventHandler { [weak self] in self?.dumpFrame() }
    src1.resume()
    signal(SIGUSR1, SIG_IGN)
    signalSources.append(src1)

    let src2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
    src2.setEventHandler { [weak self] in
      guard let self else { return }
      self.setLogin(!self.isLoginInstalled)
      self.refreshMenuStates()
      self.appendLog("login=\(self.isLoginInstalled)")
    }
    src2.resume()
    signal(SIGUSR2, SIG_IGN)
    signalSources.append(src2)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.reportFrame() }

    // 自动检查更新（默认开，启动 8 秒后一次，之后每 6 小时）
    if defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true {
      DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkForUpdates(manual: false) }
      autoCheckTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
        self?.checkForUpdates(manual: false)
      }
      if let t = autoCheckTimer { RunLoop.main.add(t, forMode: .common) }
    }
  }

  // MARK: 菜单

  private func buildMenu() {
    let menu = NSMenu()
    menu.addItem(item("显示秒", #selector(toggleSeconds), nil, state: clock.showSeconds))
    menu.addItem(item("显示冒号", #selector(toggleColons), nil, state: clock.showColons))
    menu.addItem(item("冒号跳动", #selector(toggleBlink), nil, state: clock.blinkColons))
    menu.addItem(.separator())
    menu.addItem(item("平滑扫动", #selector(toggleSmooth), nil, state: clock.smooth))
    menu.addItem(item("秒位平滑", #selector(toggleSmoothSeconds), nil, state: clock.smoothSeconds))
    menu.addItem(item("电池时秒位直接跳", #selector(toggleBatteryThrottle), nil, state: clock.batteryThrottle))

    let spin = NSMenuItem(title: "旋转动画", action: nil, keyEquivalent: "")
    let sub = NSMenu()
    for style in SpinStyle.allCases {
      let i = NSMenuItem(title: style.title, action: #selector(pickSpinStyle(_:)), keyEquivalent: "")
      i.target = self
      i.tag = style.rawValue
      i.state = style == clock.spinStyle ? .on : .off
      sub.addItem(i)
    }
    spin.submenu = sub
    menu.addItem(spin)

    let sweepItem = NSMenuItem(title: "换字时长", action: nil, keyEquivalent: "")
    let sweepMenu = NSMenu()
    for secs in kSweepChoices {
      let i = NSMenuItem(title: "\(Int(secs)) 秒", action: #selector(pickSweepDuration(_:)), keyEquivalent: "")
      i.target = self
      i.tag = Int(secs)
      sweepMenu.addItem(i)
    }
    sweepItem.submenu = sweepMenu
    menu.addItem(sweepItem)

    menu.addItem(.separator())
    menu.addItem(item("开机自启", #selector(toggleLogin), nil, state: isLoginInstalled))
    menu.addItem(item("自动检查更新", #selector(toggleAutoCheck), nil,
                      state: defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true))
    let update = item("有新版本", #selector(openReleasePage), nil)
    update.isHidden = true
    updateItem = update
    menu.addItem(update)
    let check = item("检查更新", #selector(checkUpdatesNow), nil)
    checkItem = check
    menu.addItem(check)
    if let web = Bundle.main.object(forInfoDictionaryKey: "ClockClockWebPage") as? String {
      let open = item("打开网页版", #selector(openWebPage), nil)
      open.representedObject = web
      menu.addItem(open)
    }
    menu.addItem(.separator())
    menu.addItem(item("退出", #selector(quit), "q"))
    statusItem.menu = menu
  }

  private func item(_ title: String, _ action: Selector, _ key: String?, state: Bool = false) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: key ?? "")
    i.target = self
    i.state = state ? .on : .off
    return i
  }

  private func refreshMenuStates() {
    guard let menu = statusItem.menu else { return }
    for i in menu.items {
      switch i.action {
      case #selector(toggleSeconds): i.state = clock.showSeconds ? .on : .off
      case #selector(toggleColons):
        i.state = clock.showColons ? .on : .off
      case #selector(toggleBlink):
        i.state = clock.blinkColons ? .on : .off
        i.isEnabled = clock.showColons
      case #selector(toggleSmooth): i.state = clock.smooth ? .on : .off
      case #selector(toggleSmoothSeconds):
        i.state = clock.smoothSeconds ? .on : .off
        i.isEnabled = clock.smooth
      case #selector(toggleBatteryThrottle):
        i.state = clock.batteryThrottle ? .on : .off
        i.isEnabled = clock.smoothSeconds
      default: break
      }
    }
    for i in menu.items {
      if i.title == "旋转动画", let sub = i.submenu {
        for m in sub.items { m.state = m.tag == clock.spinStyle.rawValue ? .on : .off }
      }
      if i.title == "换字时长", let sub = i.submenu {
        i.isEnabled = clock.smooth
        for m in sub.items { m.state = Double(m.tag) == clock.sweepDuration ? .on : .off }
      }
    }
    updateItem?.isHidden = !hasUpdate
    if hasUpdate, let tag = latestTag { updateItem?.title = "有新版本 \(tag)（点开查看）" }
  }

  // MARK: 状态推进

  private func applyStateNow() {
    clock.onBattery = currentPowerIsBattery()
    let now = CACurrentMediaTime()
    clock.apply(clock.currentTime(), at: now)
    redraw()
    ensureRendering(at: now)
    appendLog("painted=\(clock.currentTime()) image=\(clock.imageSize.width)x\(clock.imageSize.height) onBattery=\(clock.onBattery)")
  }

  private func scheduleTick() {
    tickTimer?.invalidate()
    let now = Date()
    let frac = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
    let fire = Date().addingTimeInterval(1.0 - frac + 0.01)
    tickTimer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
      guard let self else { return }
      let t = CACurrentMediaTime()
      self.clock.apply(self.clock.currentTime(), at: t)
      self.redraw()
      self.ensureRendering(at: t)
      self.scheduleTick()
    }
    RunLoop.main.add(tickTimer!, forMode: .common)
  }

  private func ensureRendering(at now: Double) {
    let busy = clock.smooth && clock.isAnimating(at: now)
    if busy {
      guard renderTimer == nil else { return }
      let t = Timer(timeInterval: 1.0 / kFrameRate, repeats: true) { [weak self] _ in
        guard let self else { return }
        let n = CACurrentMediaTime()
        let sig = self.clock.signature(at: n)
        if sig != self.lastSignature {
          self.lastSignature = sig
          self.redraw()
        }
        if !self.clock.isAnimating(at: n) { self.stopRendering() }
      }
      RunLoop.main.add(t, forMode: .common)
      renderTimer = t
    } else {
      stopRendering()
    }
  }

  private func stopRendering() {
    renderTimer?.invalidate()
    renderTimer = nil
  }

  private var lastSignature = ""

  // MARK: 绘制

  private func redraw() {
    guard let button = statusItem.button else { return }
    button.image = renderImage()
  }

  private func renderImage() -> NSImage {
    renderCount += 1
    let size = clock.imageSize
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let pxW = Int((size.width * scale).rounded(.up))
    let pxH = Int((size.height * scale).rounded(.up))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size.width, height: size.height).fill(using: .copy)
    clock.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height), scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    rep.size = size

    let image = NSImage(size: size)
    image.addRepresentation(rep)
    image.isTemplate = true
    return image
  }

  /// kill -USR1：把当前这一帧原样导出，便于核对
  private func dumpFrame() {
    guard let image = statusItem.button?.image else { return }
    let size = image.size
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let pxW = Int((size.width * scale).rounded(.up))
    let pxH = Int((size.height * scale).rounded(.up))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)).fill(using: .copy)
    image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?
      .write(to: URL(fileURLWithPath: "/tmp/clockclock-menubar-frame.png"))
    appendLog("dump renders=\(renderCount) sec=\(clock.second) blink=\(clock.blinkOn)")
  }

  private func reportFrame() {
    guard let window = statusItem.button?.window else { return }
    let f = window.frame
    let screenH = NSScreen.main?.frame.height ?? 0
    let topY = screenH - (f.origin.y + f.height)
    appendLog("frame top-left=(x: \(f.origin.x), y: \(topY), w: \(f.width), h: \(f.height)) image=\(statusItem.button?.image?.size ?? .zero) menuItems=\(statusItem.menu?.items.count ?? 0) onBattery=\(clock.onBattery)")
  }

  private var logEnabled: Bool { ProcessInfo.processInfo.environment["CLOCKCLOCK_LOG"] == "1" }

  private func appendLog(_ line: String) {
    guard logEnabled else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let url = URL(fileURLWithPath: "/tmp/clockclock-menubar.log")
    let text = "\(stamp) \(line)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(text.data(using: .utf8) ?? Data())
      try? handle.close()
    } else {
      try? text.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  // MARK: 动作

  private func afterToggle() {
    redraw()
    ensureRendering(at: CACurrentMediaTime())
    refreshMenuStates()
  }

  @objc private func toggleSeconds() {
    clock.showSeconds.toggle()
    defaults.set(clock.showSeconds, forKey: "showSeconds")
    afterToggle()
  }

  @objc private func toggleColons() {
    clock.showColons.toggle()
    defaults.set(clock.showColons, forKey: "showColons")
    afterToggle()
  }

  @objc private func toggleBlink() {
    clock.blinkColons.toggle()
    defaults.set(clock.blinkColons, forKey: "blinkColons")
    afterToggle()
  }

  @objc private func toggleSmooth() {
    clock.smooth.toggle()
    defaults.set(clock.smooth, forKey: "smooth")
    applyStateNow()
  }

  @objc private func toggleSmoothSeconds() {
    clock.smoothSeconds.toggle()
    defaults.set(clock.smoothSeconds, forKey: "smoothSeconds")
    applyStateNow()
  }

  @objc private func toggleBatteryThrottle() {
    clock.batteryThrottle.toggle()
    defaults.set(clock.batteryThrottle, forKey: "batteryThrottle")
    applyStateNow()
  }

  @objc private func pickSpinStyle(_ sender: NSMenuItem) {
    clock.spinStyle = SpinStyle(rawValue: sender.tag) ?? .mechanical
    defaults.set(sender.tag, forKey: "spinStyle")
    refreshMenuStates()
  }

  @objc private func pickSweepDuration(_ sender: NSMenuItem) {
    clock.sweepDuration = Double(sender.tag)
    defaults.set(sender.tag, forKey: "sweepSeconds")
    refreshMenuStates()
    appendLog("sweepDuration=\(Int(clock.sweepDuration))")
  }

  @objc private func toggleAutoCheck() {
    let on = !(defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true)
    defaults.set(on, forKey: "autoUpdateCheck")
    if on {
      checkForUpdates(manual: false)
      autoCheckTimer?.invalidate()
      autoCheckTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
        self?.checkForUpdates(manual: false)
      }
      if let t = autoCheckTimer { RunLoop.main.add(t, forMode: .common) }
    } else {
      autoCheckTimer?.invalidate()
      autoCheckTimer = nil
    }
    refreshMenuStates()
  }

  @objc private func checkUpdatesNow() {
    checkForUpdates(manual: true)
  }

  @objc private func openReleasePage() {
    guard let url = latestURL else { return }
    NSWorkspace.shared.open(url)
  }

  private func flashCheckItem(_ text: String) {
    checkItem?.title = text
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      self?.checkItem?.title = "检查更新"
    }
  }

  private func checkForUpdates(manual: Bool) {
    if let fake = ProcessInfo.processInfo.environment["CLOCKCLOCK_FAKE_LATEST"] {
      latestTag = fake
      latestURL = URL(string: "https://github.com/\(repo)/releases")
      hasUpdate = isVersionNewer(fake, than: localVersion)
      updateItem?.title = "有新版本 \(fake)（点开查看）"
      updateItem?.isHidden = !hasUpdate
      refreshMenuStates()
      appendLog("update fake=\(fake) newer=\(hasUpdate)")
      if manual { flashCheckItem(hasUpdate ? "发现新版本 \(fake)" : "已是最新（\(localVersion)）") }
      return
    }
    // 走 releases.atom：没有 API 60 次/小时的限制（这台机的出口 IP 经常被限）
    guard let url = URL(string: "https://github.com/\(repo)/releases.atom") else { return }
    var request = URLRequest(url: url, timeoutInterval: 12)
    request.setValue("ClockClock/\(localVersion)", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
      guard let self else { return }
      var remote: String?
      if let data, let text = String(data: data, encoding: .utf8),
         let marker = text.range(of: "/releases/tag/") {
        var tag = ""
        for ch in text[marker.upperBound...] {
          if ch.isLetter || ch.isNumber || ch == "." || ch == "-" || ch == "_" { tag.append(ch) } else { break }
        }
        if !tag.isEmpty { remote = tag }
      }
      DispatchQueue.main.async {
        guard let tag = remote else {
          self.appendLog("update check failed: \(error?.localizedDescription ?? "no tag in feed")")
          if manual { self.flashCheckItem("检查更新失败") }
          return
        }
        self.latestTag = tag
        self.latestURL = URL(string: "https://github.com/\(self.repo)/releases/tag/\(tag)")
        self.hasUpdate = isVersionNewer(tag, than: self.localVersion)
        self.updateItem?.title = "有新版本 \(tag)（点开查看）"
        self.updateItem?.isHidden = !self.hasUpdate
        self.refreshMenuStates()
        self.appendLog("update check: remote=\(tag) local=\(self.localVersion) newer=\(self.hasUpdate)")
        if manual {
          self.flashCheckItem(self.hasUpdate ? "发现新版本 \(tag)" : "已是最新（\(self.localVersion)）")
        }
      }
    }.resume()
  }

  @objc private func toggleLogin() {
    setLogin(!isLoginInstalled)
    refreshMenuStates()
  }

  @objc private func openWebPage(_ sender: NSMenuItem) {
    if let path = sender.representedObject as? String, FileManager.default.fileExists(atPath: path) {
      NSWorkspace.shared.open(URL(fileURLWithPath: path))
      return
    }
    if let url = URL(string: "https://cooperzhuang.github.io/clockclock-24/") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  @objc private func wakeUp() {
    applyStateNow()
    scheduleTick()
  }

  @objc private func powerChanged() {
    let before = clock.onBattery
    clock.onBattery = currentPowerIsBattery()
    appendLog("power onBattery=\(clock.onBattery) (was \(before))")
    if before != clock.onBattery { applyStateNow() }
    refreshMenuStates()
    redraw()
  }

  // MARK: 开机自启（LaunchAgent，默认不装）

  private var loginPlistPath: String {
    NSHomeDirectory() + "/Library/LaunchAgents/\(loginLabel).plist"
  }

  private var isLoginInstalled: Bool {
    FileManager.default.fileExists(atPath: loginPlistPath)
  }

  private func setLogin(_ on: Bool) {
    let fm = FileManager.default
    let uid = getuid()
    if on {
      let binary = appPath + "/Contents/MacOS/ClockClock"
      let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key><string>\(loginLabel)</string>
        <key>ProgramArguments</key><array><string>\(binary)</string></array>
        <key>RunAtLoad</key><true/>
        <key>ProcessType</key><string>Interactive</string>
      </dict>
      </plist>
      """
      do {
        try fm.createDirectory(atPath: NSHomeDirectory() + "/Library/LaunchAgents",
                               withIntermediateDirectories: true)
        try plist.write(toFile: loginPlistPath, atomically: true, encoding: .utf8)
        run("/bin/launchctl", ["bootstrap", "gui/\(uid)", loginPlistPath])
      } catch {
        NSLog("写入登录项失败: \(error)")
      }
    } else {
      run("/bin/launchctl", ["bootout", "gui/\(uid)/\(loginLabel)"])
      try? fm.removeItem(atPath: loginPlistPath)
    }
  }

  @discardableResult
  private func run(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
  }
}

// MARK: - 入口

let args = CommandLine.arguments

func dumpOne(_ out: String, _ time: String, colons: Bool, seconds: Bool) {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let clock = ClockClock()
  clock.showColons = colons
  clock.showSeconds = seconds
  let now = CACurrentMediaTime()
  clock.apply(seconds ? time : String(time.prefix(4)), at: now)
  clock.hands = clock.hands.map { Hand(from: $0.to, to: $0.to, start: 0, dur: 0.001) }
  let size = clock.imageSize
  let scale: CGFloat = 2
  let pxW = Int((size.width * scale).rounded(.up))
  let pxH = Int((size.height * scale).rounded(.up))
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: size.width, height: size.height).fill(using: .copy)
  clock.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height), scale: scale)
  NSGraphicsContext.restoreGraphicsState()
  rep.size = size
  try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
  print("dumped \(time) colons=\(colons) seconds=\(seconds) -> \(out) (\(size.width)x\(size.height)pt, \(pxW)x\(pxH)px)")
}

if let i = args.firstIndex(of: "--dump"), i + 1 < args.count {
  var time = String(format: "%02d%02d%02d",
                    Calendar.current.component(.hour, from: Date()),
                    Calendar.current.component(.minute, from: Date()),
                    Calendar.current.component(.second, from: Date()))
  var colons = true
  var seconds = true
  for a in args[(i + 1)...] {
    if a.hasPrefix("--colons=") { colons = a.hasSuffix("1") }
    else if a.hasPrefix("--seconds=") { seconds = a.hasSuffix("1") }
    else if a.count >= 4, Int(a) != nil { time = a }
  }
  dumpOne(args[i + 1], time, colons: colons, seconds: seconds)
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
