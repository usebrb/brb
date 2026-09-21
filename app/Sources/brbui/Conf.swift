import AppKit

// Everything the app shares with the shell side. Same files, same meanings:
// the hooks keep deciding what happens, the app only draws it.
//
// The root is passed in rather than read from the environment on every access,
// so a test can point one Store at a scratch directory without disturbing
// another.
struct Store {
  let root: URL

  static func envRoot() -> URL {
    if let c = ProcessInfo.processInfo.environment["BRB_CONF"] {
      return URL(fileURLWithPath: c)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/brb")
  }

  var state: URL { root.appendingPathComponent("state") }
  var sock: String { state.appendingPathComponent("ui.sock").path }
  var logFile: URL { state.appendingPathComponent("brb.log") }
  var offFile: URL { root.appendingPathComponent("OFF") }
  var delayFile: URL { state.appendingPathComponent("delay") }
  var itemsFile: URL { root.appendingPathComponent("items.txt") }

  func prepare() {
    for d in ["active", "shown", "term", "left", "anchor", "rearm"] {
      try? FileManager.default.createDirectory(
        at: state.appendingPathComponent(d), withIntermediateDirectories: true)
    }
  }

  // The shell log, same format, so `brb log` shows one story and not two.
  func log(_ msg: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    let line = "\(f.string(from: Date())) [\("ui".padding(toLength: 9, withPad: " ", startingAt: 0))] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: logFile) {
      defer { try? h.close() }
      _ = try? h.seekToEnd()
      try? h.write(contentsOf: data)
    } else {
      try? data.write(to: logFile)
    }
  }

  var isOff: Bool { FileManager.default.fileExists(atPath: offFile.path) }

  func setOff(_ off: Bool) {
    if off {
      FileManager.default.createFile(atPath: offFile.path, contents: nil)
    } else {
      try? FileManager.default.removeItem(at: offFile)
    }
  }

  // --- break timer ---------------------------------------------------------

  var delay: Int {
    get {
      let raw = (try? String(contentsOf: delayFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return Int(raw) ?? 10
    }
    nonmutating set { try? String(max(3, newValue)).write(to: delayFile, atomically: true, encoding: .utf8) }
  }

  static func fmt(_ secs: Int) -> String {
    if secs < 60 { return "\(secs)s" }
    let m = secs / 60, s = secs % 60
    return s == 0 ? "\(m)m" : "\(m)m \(s)s"
  }

  // --- where this app lives, for the shell to find ------------------------

  var appPointer: URL { state.appendingPathComponent("ui.app") }

  func writeAppPointer(_ bundle: URL) {
    try? bundle.path.write(to: appPointer, atomically: true, encoding: .utf8)
  }

  func clearAppPointer() {
    try? FileManager.default.removeItem(at: appPointer)
  }

  // --- the "you left via the panel" marker the Stop hook reads --------------

  func markLeft(_ sid: String) {
    guard !sid.isEmpty else { return }
    let f = state.appendingPathComponent("left/\(sid)")
    try? String(Int(Date().timeIntervalSince1970)).write(to: f, atomically: true, encoding: .utf8)
  }

  // --- break items ---------------------------------------------------------

  static let defaultItems = """
  # Break panel items.  Format:  Label|target
  #
  #   https://...        opens in your default browser, and counts as leaving
  #   anything://...     opens in its app, and counts as leaving
  #   note:some text     shows a short reminder, does NOT count as leaving
  #
  # Only "leaving" earns you a "Claude is done" callback when the turn ends.
  # An emoji at the start of a label is used as the item's icon.

  🐦 X|https://x.com
  👽 Reddit|https://reddit.com
  📰 Hacker News|https://news.ycombinator.com
  💧 Drink some water|note:Refill. Then look 20 feet away for 20 seconds.
  🪟 Look out the window|note:Eyes off the screen. Find something far away and let them relax.
  🧘 Stand up and stretch|note:Shoulders back, chin up. Thirty seconds is enough.
  """

  @discardableResult
  func ensureItemsFile() -> URL {
    if !FileManager.default.fileExists(atPath: itemsFile.path) {
      try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try? Store.defaultItems.write(to: itemsFile, atomically: true, encoding: .utf8)
    }
    return itemsFile
  }

  func items() -> [BreakItem] {
    let text = (try? String(contentsOf: itemsFile, encoding: .utf8)) ?? Store.defaultItems
    return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
      BreakItem(line: String($0))
    }
  }
}

// The app's own store, plus the short names the UI code reads it by.
enum Conf {
  static let shared = Store(root: Store.envRoot())

  static var sock: String { shared.sock }
  static var logFile: URL { shared.logFile }
  static var itemsFile: URL { shared.itemsFile }
  static var isOff: Bool { shared.isOff }
  static var delay: Int {
    get { shared.delay }
    set { shared.delay = newValue }
  }

  static func prepare() { shared.prepare() }
  static func log(_ msg: String) { shared.log(msg) }
  static func setOff(_ off: Bool) { shared.setOff(off) }
  static func markLeft(_ sid: String) { shared.markLeft(sid) }
  static func items() -> [BreakItem] { shared.items() }
  static func fmt(_ secs: Int) -> String { Store.fmt(secs) }
  @discardableResult static func ensureItemsFile() -> URL { shared.ensureItemsFile() }

  static let icons = IconStore(store: shared)
}

struct BreakItem: Identifiable {
  enum Kind {
    case site(URL)   // leaving: earns the callback
    case app(URL)    // leaving too, but not the browser
    case note(String)
  }

  let id = UUID()
  let emoji: String
  let label: String
  let kind: Kind

  var leaves: Bool {
    if case .note = kind { return false }
    return true
  }

  // Only a site has a logo to fetch; a note is just a note.
  var host: String? {
    if case .site(let url) = kind { return url.host() }
    return nil
  }

  // A label with no emoji of its own still deserves better than a globe.
  static func icon(forHost host: String) -> String {
    let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    switch h {
    case "x.com", "twitter.com": return "🐦"
    case "reddit.com", "old.reddit.com": return "👽"
    case "news.ycombinator.com": return "📰"
    case "youtube.com", "youtu.be": return "📺"
    case "github.com": return "🐙"
    case "instagram.com": return "📸"
    case "mail.google.com", "gmail.com": return "📬"
    case "open.spotify.com", "spotify.com": return "🎧"
    case "linkedin.com": return "💼"
    case "substack.com": return "✉️"
    case "wikipedia.org", "en.wikipedia.org": return "📚"
    default: return "🌐"
    }
  }

  init?(line: String) {
    let raw = line.trimmingCharacters(in: .whitespaces)
    guard !raw.isEmpty, !raw.hasPrefix("#"), let bar = raw.firstIndex(of: "|") else { return nil }
    let target = String(raw[raw.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
    var label = String(raw[..<bar]).trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty, !target.isEmpty else { return nil }

    if target.hasPrefix("note:") {
      kind = .note(String(target.dropFirst(5)))
    } else if let url = URL(string: target), url.scheme != nil {
      kind = (url.scheme == "http" || url.scheme == "https") ? .site(url) : .app(url)
    } else {
      return nil
    }

    // A leading emoji in the label becomes the icon, so the list stays legible.
    if let first = label.first, first.isEmoji {
      emoji = String(first)
      label = String(label.dropFirst()).trimmingCharacters(in: .whitespaces)
    } else if case .note = kind {
      emoji = "📝"
    } else if case .site(let url) = kind {
      emoji = BreakItem.icon(forHost: url.host() ?? "")
    } else {
      emoji = "📱"
    }
    self.label = label
  }
}

extension Character {
  var isEmoji: Bool {
    guard let s = unicodeScalars.first else { return false }
    return s.properties.isEmojiPresentation || (s.properties.isEmoji && unicodeScalars.count > 1)
  }
}

// --- apps ------------------------------------------------------------------

enum Apps {
  static func bundleURL(forID id: String) -> URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
  }

  static func activate(bundleID: String) {
    guard !bundleID.isEmpty else { return }
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
      running.activate(options: [.activateAllWindows])
      return
    }
    guard let url = bundleURL(forID: bundleID) else { return }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: cfg)
  }

  static var defaultBrowserID: String? {
    guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
    else { return nil }
    return Bundle(url: url)?.bundleIdentifier
  }

  static func name(forID id: String) -> String? {
    guard let url = bundleURL(forID: id) else { return nil }
    return url.deletingPathExtension().lastPathComponent
  }

  // Banners still go through osascript: no notification entitlement needed, and
  // it behaves the same whether or not this app is signed.
  // Tests drive the real event path; they must not ring the real machine.
  static var quiet: Bool { ProcessInfo.processInfo.environment["BRB_QUIET"] == "1" }

  static func banner(title: String, message: String, sound: String?) {
    if quiet {
      Conf.log("quiet: would notify [\(title)] \(message)")
      return
    }
    if let sound, let s = NSSound(named: sound) { s.play() }
    let script = "display notification \(quote(message)) with title \(quote(title))"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    try? p.run()
  }

  static func quote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}
