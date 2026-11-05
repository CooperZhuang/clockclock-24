// ClockClock · macOS 状态栏版
//
// 和网页版同一套字形：一个数字 = 2 列 × 3 行 = 6 个表盘 = 12 根指针，
// 0 = 12 点方向、顺时针。状态栏只有 22pt 高，所以每格表盘 6.65pt、
// 只画指针不画盘面（模板图，自动跟随浅色 / 深色菜单栏）。
//
// 节奏与网页版一致：时:分换字 15 秒慢慢转到位（顺时针兜一圈），
// 秒位每秒转 0.8 秒、停 0.2 秒。

import AppKit

let kBarHeight = NSStatusBar.system.thickness          // 22pt
let kMargin: CGFloat = 0.5
let kGapRatio: CGFloat = 0.08
let kStrokeRatio: CGFloat = 0.22
let kHandRatio: CGFloat = 0.52
let kColonRatio: CGFloat = 0.42
let kPadLeft: CGFloat = 4
let kPadRight: CGFloat = 8

let kSweepDuration: Double = 15          // 时:分换字时长（秒）
let kTickDuration: Double = 0.8          // 秒位每格时长（秒）
let kFrameRate: Double = 10              // 动画帧率（这个尺寸下 10fps 已经看不出台阶）

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

// MARK: - 动画

struct Hand {
  var from: Double = 0
  var to: Double = 0
  var start: Double = 0
  var dur: Double = 0.001

  func angle(at now: Double) -> Double {
    if dur <= 0.001 { return to }
    let p = min(1, max(0, (now - start) / dur))
    return from + (to - from) * Easing.cubicBezier(p, 0.62, 0.02, 0.28, 1)
  }
}

enum Easing {
  static func cubic(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
    let m = 1 - t
    return 3 * m * m * t * p1 + 3 * m * t * t * p2 + t * t * t
  }

  /// CSS cubic-bezier(x1,y1,x2,y2)：先解出 t，再取 y
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
  var showSeconds = true
  var smooth = true
  /// 强制秒位也做 0.8s 平滑（默认关：22pt 下位移不到 1px，纯烧 CPU）
  var smoothSeconds = false
  /// 竖版：时:分 + 秒 = 6 位；否则只画 4 位
  private(set) var minute = ""
  private(set) var second = ""

  let face: CGFloat
  let pitch: CGFloat
  let colon: CGFloat

  init() {
    hands = Array(repeating: Hand(), count: handsCount)
    face = (kBarHeight - 2 * kMargin) / 3.16
    pitch = face * (1 + kGapRatio)
    colon = face * kColonRatio
  }

  // 第 d 位数字、第 k 个表盘（0 左上、1 右上、2 左中、3 右中、4 左下、5 右下）
  func faceIndex(digit d: Int, clock k: Int) -> Int {
    let row = k / 2, col = k % 2
    if d < 4 { return row * 8 + d * 2 + col }
    return 24 + row * 4 + (d - 4) * 2 + col
  }

  func columnsX() -> [CGFloat] {
    let count = showSeconds ? 12 : 8
    var xs: [CGFloat] = []
    var x: CGFloat = 0
    for i in 0..<count {
      xs.append(x)
      x += pitch
      if i == 7 && count > 8 { x += colon }
    }
    return xs
  }

  var imageSize: NSSize {
    let xs = columnsX()
    return NSSize(width: xs.last! + face + kPadLeft + kPadRight, height: kBarHeight)
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
      setDigits(time, from: 0, to: 3, dur: smooth ? kSweepDuration : 0.001, spin: smooth, now: now)
    }
    guard hasSeconds else { return }
    let ss = String(time.suffix(2))
    if ss != second {
      second = ss
      // 22pt 高度下秒针一秒只走 6°，默认直接落位省电；菜单里可强制平滑
      let dur = (smooth && smoothSeconds) ? kTickDuration : 0.001
      setDigits(time, from: 4, to: 5, dur: dur, spin: false, now: now)
    }
  }

  func setDigits(_ time: String, from: Int, to: Int, dur: Double, spin: Bool, now: Double) {
    let chars = Array(time)
    for d in from...to {
      guard let digit = Int(String(chars[d])) else { continue }
      for k in 0..<6 {
        let idx = faceIndex(digit: d, clock: k)
        for h in 0..<2 {
          let slot = idx * 2 + h
          let current = hands[slot].angle(at: now)
          let base = current.truncatingRemainder(dividingBy: 360)
          let from360 = base < 0 ? base + 360 : base
          let target = glyphs[digit][k][h]
          var delta = Double(target) - Double(from360)
          delta = delta.truncatingRemainder(dividingBy: 360)
          if delta < 0 { delta += 360 }
          if spin { delta += 360 }
          if delta <= 0.0005 { continue }               // 没变化就别起动画
          hands[slot] = Hand(from: current, to: current + delta, start: now, dur: dur)
        }
      }
    }
  }

  /// 把当前所有指针角度量化成字符串，用于判断这一帧要不要真的重绘
  func signature(at now: Double) -> String {
    var out = ""
    out.reserveCapacity(hands.count * 4)
    for h in hands {
      let q = Int((h.angle(at: now) / 1.5).rounded())
      out += String(q)
      out += ","
    }
    return out
  }

  func isAnimating(at now: Double) -> Bool {
    hands.contains { $0.start + $0.dur > now }
  }

  func draw(in rect: NSRect, scale: CGFloat) {
    let xs = columnsX()
    let ink = NSColor.black
    ink.setFill()
    ink.setStroke()

    let now = CACurrentMediaTime()
    let count = showSeconds ? 12 : 8
    let hpx = rect.height * scale
    let path = NSBezierPath()                       // 一次 stroke，比 72 次便宜
    path.lineWidth = max(1.1, kStrokeRatio * face) * scale
    path.lineCapStyle = .butt
    for col in 0..<count {
      for row in 0..<3 {
        let idx = col < 8 ? row * 8 + col : 24 + row * 4 + (col - 8)
        let cx = (xs[col] + face / 2 + kPadLeft) * scale
        let cyTop = (kMargin + CGFloat(row) * pitch + face / 2) * scale
        for h in 0..<2 {
          let a = hands[idx * 2 + h].angle(at: now)
          let rad = a * .pi / 180
          let ex = cx + sin(rad) * kHandRatio * face * scale
          let eyTop = cyTop - cos(rad) * kHandRatio * face * scale
          path.move(to: NSPoint(x: cx, y: hpx - cyTop))
          path.line(to: NSPoint(x: ex, y: hpx - eyTop))
        }
      }
    }
    path.stroke()
  }
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var clock = ClockClock()
  private var tickTimer: Timer?
  private var renderTimer: Timer?
  private var lastDrawn = ""
  private var lastSignature = ""
  private var signalSources: [DispatchSourceSignal] = []
  private var renderCount = 0

  private let defaults = UserDefaults.standard
  private let loginLabel = "com.cooper.clockclock-menubar"
  private var appPath: String { Bundle.main.bundlePath }

  func applicationDidFinishLaunching(_ notification: Notification) {
    clock.showSeconds = defaults.object(forKey: "showSeconds") as? Bool ?? true
    clock.smooth = defaults.object(forKey: "smooth") as? Bool ?? true
    clock.smoothSeconds = defaults.object(forKey: "smoothSeconds") as? Bool ?? false

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.toolTip = "ClockClock"

    buildMenu()
    refreshMenuStates()          // 让「秒位平滑」在平滑扫动关闭时就是灰的
    applyStateNow()
    scheduleTick()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.reportFrame() }

    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(wakeUp),
      name: NSWorkspace.didWakeNotification, object: nil
    )

    // 调试用：kill -USR1 <pid> 把状态栏按钮当前的实际显示内容导成 PNG
    let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    src.setEventHandler { [weak self] in self?.dumpButtonImage() }
    src.resume()
    signal(SIGUSR1, SIG_IGN)
    signalSources.append(src)

    // 调试用：kill -USR2 <pid> 切换开机自启（等价于点菜单里的「开机自启」）
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
  }

  // MARK: 菜单

  private func buildMenu() {
    let menu = NSMenu()
    menu.addItem(item("显示秒", #selector(toggleSeconds), "s", state: clock.showSeconds))
    menu.addItem(item("平滑扫动", #selector(toggleSmooth), "l", state: clock.smooth))
    menu.addItem(item("秒位平滑", #selector(toggleSmoothSeconds), "k", state: clock.smoothSeconds))
    menu.addItem(.separator())
    menu.addItem(item("开机自启", #selector(toggleLogin), nil, state: isLoginInstalled))
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
      case #selector(toggleSmooth):
        i.state = clock.smooth ? .on : .off
      case #selector(toggleSmoothSeconds):
        i.state = clock.smoothSeconds ? .on : .off
        i.isEnabled = clock.smooth
      case #selector(toggleLogin): i.state = isLoginInstalled ? .on : .off
      default: break
      }
    }
  }

  // MARK: 状态推进

  private func applyStateNow() {
    let now = CACurrentMediaTime()
    clock.apply(clock.currentTime(), at: now)
    redraw()
    ensureRendering(at: now)
    appendLog("painted=\(clock.currentTime()) image=\(clock.imageSize.width)x\(clock.imageSize.height)")
  }

  private func scheduleTick() {
    tickTimer?.invalidate()
    let now = Date()
    let frac = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
    let fire = Date().addingTimeInterval(1.0 - frac + 0.01)
    tickTimer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
      guard let self else { return }
      let t = CACurrentMediaTime()
      let time = self.clock.currentTime()
      self.clock.apply(time, at: t)
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
    rep.size = size                                   // 画完再标定，避免 context 二次放大

    let image = NSImage(size: size)
    image.addRepresentation(rep)
    image.isTemplate = true                              // 自动跟浅/深菜单栏
    return image
  }

  /// 把状态栏项目的窗口位置写到 /tmp，方便外部核对（不影响正常使用）
  private func reportFrame() {
    guard let window = statusItem.button?.window else { return }
    let f = window.frame
    let screenH = NSScreen.main?.frame.height ?? 0
    let topY = screenH - (f.origin.y + f.height)
    let size = statusItem.button?.image?.size ?? .zero
    appendLog("frame top-left=(x: \(f.origin.x), y: \(topY), w: \(f.width), h: \(f.height)) image=\(size) menuItems=\(statusItem.menu?.items.count ?? 0)")
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

  /// kill -USR1 时把「当前这一帧要交给状态栏的图」原样导出，用于核对字形
  private func dumpButtonImage() {
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
    let path = "/tmp/clockclock-menubar-frame.png"
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    // 同一次里再用绘制代码现画一张，用来区分「按钮里的图被 AppKit 处理过」还是「本来就这样」
    let fresh = renderImage()
    if let freshRep = fresh.representations.first as? NSBitmapImageRep,
       let png = freshRep.representation(using: .png, properties: [:]) {
      try? png.write(to: URL(fileURLWithPath: "/tmp/clockclock-menubar-fresh.png"))
    }
    let n = CACurrentMediaTime()
    let secAngles = (48..<72).map { String(format: "%.0f", clock.hands[$0].angle(at: n)) }.joined(separator: ",")
    appendLog("dump renders=\(renderCount) sec=\(clock.second) angles=\(secAngles)")
  }

  // MARK: 动作

  @objc private func toggleSeconds() {
    clock.showSeconds.toggle()
    defaults.set(clock.showSeconds, forKey: "showSeconds")
    refreshMenuStates()
    redraw()
    reportFrame()
  }

  @objc private func toggleSmooth() {
    clock.smooth.toggle()
    defaults.set(clock.smooth, forKey: "smooth")
    refreshMenuStates()
    applyStateNow()
  }

  @objc private func toggleSmoothSeconds() {
    clock.smoothSeconds.toggle()
    defaults.set(clock.smoothSeconds, forKey: "smoothSeconds")
    refreshMenuStates()
    applyStateNow()
  }

  @objc private func toggleLogin() {
    setLogin(!isLoginInstalled)
    refreshMenuStates()
  }

  @objc private func openWebPage(_ sender: NSMenuItem) {
    // 从源码目录跑就打开本地 index.html；下载安装的 App 里没有这个文件，回落到在线版
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
if let i = args.firstIndex(of: "--dump"), i + 1 < args.count {
  // 离线渲染一帧，用于核对字形：--dump <out.png> [HHMMSS]
  let out = args[i + 1]
  let time = (i + 2 < args.count) ? args[i + 2] : {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
    return String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
  }()
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let clock = ClockClock()
  let now = CACurrentMediaTime()
  clock.apply(time, at: now)
  // 落位：所有指针直接停在目标角上
  clock.hands = clock.hands.map { Hand(from: $0.to, to: $0.to, start: 0, dur: 0.001) }
  let size = clock.imageSize
  let scale: CGFloat = 2
  let pxW = Int((size.width * scale).rounded(.up)), pxH = Int((size.height * scale).rounded(.up))
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
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
  print("dumped \(time) -> \(out) (\(size.width)x\(size.height)pt, \(pxW)x\(pxH)px)")
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
