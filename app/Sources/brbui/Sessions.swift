import Foundation

struct Session {
  let started: Date
  let owner: String     // bundle id of the app that owns the session
  let project: String   // last path component of cwd, for telling sessions apart
}

// What the menu bar shows, kept apart from the AppKit plumbing so it can be
// tested without a screen.
struct SessionBook {
  private(set) var sessions: [String: Session] = [:]

  var count: Int { sessions.count }
  var isBusy: Bool { !sessions.isEmpty }

  // The one that has been going longest: that is the wait people feel.
  var busiest: (sid: String, session: Session)? {
    sessions.min { $0.value.started < $1.value.started }.map { ($0.key, $0.value) }
  }

  mutating func start(_ sid: String, owner: String, cwd: String, at now: Date = Date()) {
    guard !sid.isEmpty else { return }
    sessions[sid] = Session(
      started: now,
      owner: owner,
      project: cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent)
  }

  @discardableResult
  mutating func end(_ sid: String) -> Session? {
    sessions.removeValue(forKey: sid)
  }

  func elapsed(_ sid: String, now: Date = Date()) -> Int? {
    sessions[sid].map { max(0, Int(now.timeIntervalSince($0.started))) }
  }

  // ☕️ nothing running · ⚡️ counting up · 💤 paused. A flash (🔔, ✅) wins
  // while it lasts, because it is the thing that just happened.
  func statusTitle(now: Date = Date(), off: Bool = false, flash: String? = nil) -> String {
    if let flash { return flash }
    if off { return "💤" }
    guard let busy = busiest else { return "☕️" }
    return "⚡️ \(Store.fmt(max(0, Int(now.timeIntervalSince(busy.session.started)))))"
  }

  func headerLine(now: Date = Date(), off: Bool = false) -> String {
    if off { return "💤  brb is paused" }
    guard let busy = busiest else { return "☕️  Nothing running" }
    let secs = max(0, Int(now.timeIntervalSince(busy.session.started)))
    let project = busy.session.project.isEmpty ? "" : " · \(busy.session.project)"
    return "⚡️  Claude is working — \(Store.fmt(secs))\(project)"
  }
}
