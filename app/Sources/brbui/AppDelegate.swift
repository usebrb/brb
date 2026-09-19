import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var book = SessionBook()
  private var breakPanel: BreakPanelController?
  private var doneCard: DoneCardController?
  private var flash: (emoji: String, until: Date)?
  private var ticker: Timer?

  func applicationDidFinishLaunching(_ note: Notification) {
    Conf.prepare()
    Conf.ensureItemsFile()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "☕️"
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    do {
      try Bus.listen(path: Conf.sock) { [weak self] msg in
        self?.handle(msg) ?? ["ok": false]
      }
      // Leave the shell a pointer to this bundle: it needs the binary as a
      // client, and guessing at install paths is how it ends up drawing the
      // AppleScript panel on top of ours.
      Conf.shared.writeAppPointer(Bundle.main.bundleURL)
      Conf.log("app up, listening on \(Conf.sock)")
    } catch {
      Conf.log("app up but socket failed: \(error) - hooks will use AppleScript")
    }

    Conf.icons.warm(Conf.items())

    ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refreshStatus()
    }
    refreshStatus()
  }

  func applicationWillTerminate(_ note: Notification) {
    unlink(Conf.sock)
    Conf.shared.clearAppPointer()
    Conf.log("app down")
  }

  // MARK: - events from the hooks

  private func handle(_ msg: [String: Any]) -> [String: Any] {
    let event = msg["event"] as? String ?? ""
    let sid = msg["session"] as? String ?? ""
    let str = { (k: String) in msg[k] as? String ?? "" }

    switch event {
    case "ping":
      return ["ok": true, "app": "brb"]

    case "start":
      book.start(sid, owner: str("owner"), cwd: str("cwd"))
      doneCard?.close()
      refreshStatus()
      return ["ok": true]

    case "panel":
      guard !Conf.isOff else { return ["ok": false, "why": "off"] }
      let s = book.sessions[sid]
      showBreakPanel(sid: sid, started: s?.started ?? Date(), project: s?.project ?? str("project"))
      return ["ok": true]

    case "attention":
      flashStatus("🔔")
      Apps.banner(title: "Claude needs you", message: str("message"), sound: "Ping")
      breakPanel?.close()
      return ["ok": true]

    case "done":
      let s = book.end(sid)
      // One panel, shared: it only comes down when nothing else is working.
      if str("panel") != "keep" { breakPanel?.close() }
      flashStatus("✅")
      refreshStatus()
      showDoneCard(
        message: str("message").isEmpty ? "Turn complete." : str("message"),
        owner: str("owner").isEmpty ? (s?.owner ?? "") : str("owner"),
        project: s?.project ?? str("project"),
        worked: s.map { Int(Date().timeIntervalSince($0.started)) })
      return ["ok": true]

    case "stop":
      book.end(sid)
      if str("panel") != "keep" { breakPanel?.close() }
      refreshStatus()
      return ["ok": true]

    default:
      return ["ok": false, "why": "unknown event"]
    }
  }

  // MARK: - status item

  private func flashStatus(_ emoji: String) {
    flash = (emoji, Date().addingTimeInterval(8))
    refreshStatus()
  }

  private var busiest: (sid: String, session: Session)? { book.busiest }

  private func refreshStatus() {
    guard let button = statusItem.button else { return }
    let showing = flash.flatMap { $0.until > Date() ? $0.emoji : nil }
    if showing == nil { flash = nil }
    button.title = book.statusTitle(off: Conf.isOff, flash: showing)
  }

  // MARK: - menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    menu.addItem(disabled(book.headerLine(off: Conf.isOff)))

    if book.count > 1 {
      menu.addItem(disabled("     \(book.count) sessions busy"))
    }

    menu.addItem(.separator())
    menu.addItem(disabled("Take a break"))
    let items = Conf.items()
    for item in items {
      let logo = item.host.flatMap { Conf.icons.cached(forHost: $0) }
      let m = NSMenuItem(
        title: logo == nil ? "\(item.emoji)  \(item.label)" : item.label,
        action: #selector(pickFromMenu(_:)), keyEquivalent: "")
      if let logo {
        let sized = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
          logo.draw(in: rect)
          return true
        }
        m.image = sized
      }
      m.target = self
      m.representedObject = item.id
      menu.addItem(m)
    }
    Conf.icons.warm(items)

    menu.addItem(.separator())
    let panelItem = NSMenuItem(title: "Open the break panel", action: #selector(openPanelNow), keyEquivalent: "")
    panelItem.target = self
    menu.addItem(panelItem)

    let timer = NSMenuItem(title: "Break timer: \(Conf.fmt(Conf.delay))", action: nil, keyEquivalent: "")
    let sub = NSMenu()
    for secs in [5, 10, 30, 60, 120, 300] {
      let m = NSMenuItem(title: Conf.fmt(secs), action: #selector(setTimer(_:)), keyEquivalent: "")
      m.target = self
      m.tag = secs
      m.state = (secs == Conf.delay) ? .on : .off
      sub.addItem(m)
    }
    timer.submenu = sub
    menu.addItem(timer)

    let edit = NSMenuItem(title: "Edit break list…", action: #selector(editItems), keyEquivalent: "")
    edit.target = self
    menu.addItem(edit)

    menu.addItem(.separator())
    let toggle = NSMenuItem(
      title: Conf.isOff ? "Turn brb on" : "Pause brb",
      action: #selector(toggleOff), keyEquivalent: "")
    toggle.target = self
    menu.addItem(toggle)

    let log = NSMenuItem(title: "Open the log", action: #selector(openLog), keyEquivalent: "")
    log.target = self
    menu.addItem(log)

    let quit = NSMenuItem(title: "Quit brb", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)
  }

  private func disabled(_ title: String) -> NSMenuItem {
    let m = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    m.isEnabled = false
    return m
  }

  @objc private func pickFromMenu(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? UUID,
          let item = Conf.items().first(where: { $0.id == id }) else { return }
    take(item, sid: busiest?.sid ?? "")
  }

  @objc private func openPanelNow() {
    let busy = busiest
    showBreakPanel(
      sid: busy?.sid ?? "",
      started: busy?.session.started ?? Date(),
      project: busy?.session.project ?? "")
  }

  @objc private func setTimer(_ sender: NSMenuItem) {
    Conf.delay = sender.tag
    Conf.log("break timer set to \(sender.tag)s (menu bar)")
  }

  @objc private func editItems() {
    NSWorkspace.shared.open(Conf.ensureItemsFile())
  }

  @objc private func toggleOff() {
    Conf.setOff(!Conf.isOff)
    if Conf.isOff { breakPanel?.close() }
    refreshStatus()
  }

  @objc private func openLog() {
    NSWorkspace.shared.open(Conf.logFile)
  }

  // MARK: - windows

  private func showBreakPanel(sid: String, started: Date, project: String) {
    breakPanel?.close()
    let c = BreakPanelController(sid: sid, started: started, project: project)
    c.onPick = { [weak self] item in self?.take(item, sid: sid) }
    c.show()
    breakPanel = c
    Conf.log("panel shown for sid=\(String(sid.prefix(8)))")
  }

  private func showDoneCard(message: String, owner: String, project: String, worked: Int?) {
    doneCard?.close()
    let c = DoneCardController(message: message, owner: owner, project: project, worked: worked)
    c.show()
    doneCard = c
    Apps.banner(title: "Claude is done", message: message, sound: "Glass")
    Conf.log("callback card shown, return-to='\(owner)'")
  }

  // Picking an item is what "leaving" means: the Stop hook reads that marker.
  private func take(_ item: BreakItem, sid: String) {
    switch item.kind {
    case .note:
      break  // handled inside the panel, and never counts as leaving
    case .site(let url):
      NSWorkspace.shared.open(url)
      Conf.markLeft(sid)
      breakPanel?.close()
      if let browser = Apps.defaultBrowserID {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { Apps.activate(bundleID: browser) }
      }
      Conf.log("opened \(url.absoluteString)")
    case .app(let url):
      NSWorkspace.shared.open(url)
      Conf.markLeft(sid)
      breakPanel?.close()
      Conf.log("opened \(url.absoluteString)")
    }
  }
}
