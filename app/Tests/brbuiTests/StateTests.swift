import Foundation
import Testing
@testable import brbui

// State the app shares with the shell: the timer, the kill switch, the
// "you left via the panel" marker the Stop hook reads. Each test gets its own
// Store, so they can run together without stepping on each other.
@Suite("shared state")
struct StateTests {
  private func sandbox() -> Store {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("brb-conf-\(UUID().uuidString.prefix(8))")
    let store = Store(root: dir)
    store.prepare()
    return store
  }

  @Test("the timer round-trips through the file the shell reads")
  func timer() {
    let store = sandbox()
    store.delay = 45
    #expect(store.delay == 45)
    let onDisk = try? String(contentsOf: store.root.appendingPathComponent("state/delay"), encoding: .utf8)
    #expect(onDisk?.trimmingCharacters(in: .whitespacesAndNewlines) == "45")
  }

  @Test("the timer never goes below the three second floor")
  func timerFloor() {
    let store = sandbox()
    store.delay = 1
    #expect(store.delay == 3)
  }

  @Test("a missing timer file means the ten second default")
  func timerDefault() {
    #expect(sandbox().delay == 10)
  }

  @Test("a garbled timer file falls back to the default rather than zero")
  func timerGarbled() {
    let store = sandbox()
    try? "banana".write(to: store.delayFile, atomically: true, encoding: .utf8)
    #expect(store.delay == 10)
  }

  @Test("the kill switch is a file, the same one `brb off` writes")
  func killSwitch() {
    let store = sandbox()
    #expect(!store.isOff)
    store.setOff(true)
    #expect(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("OFF").path))
    #expect(store.isOff)
    store.setOff(false)
    #expect(!store.isOff)
  }

  @Test("leaving writes the marker the Stop hook looks for")
  func leftMarker() {
    let store = sandbox()
    store.markLeft("sid-42")
    #expect(FileManager.default.fileExists(
      atPath: store.state.appendingPathComponent("left/sid-42").path))
  }

  @Test("no session means no stray marker")
  func leftMarkerNeedsSession() {
    let store = sandbox()
    store.markLeft("")
    let entries = (try? FileManager.default.contentsOfDirectory(
      atPath: store.state.appendingPathComponent("left").path)) ?? []
    #expect(entries.isEmpty)
  }

  @Test("the items file is seeded once and then left alone")
  func itemsSeeding() {
    let store = sandbox()
    let f = store.ensureItemsFile()
    #expect(store.items().count == 6)

    try? "🎹 Piano|https://example.com".write(to: f, atomically: true, encoding: .utf8)
    _ = store.ensureItemsFile()
    let items = store.items()
    #expect(items.count == 1)
    #expect(items.first?.emoji == "🎹")
  }

  @Test("an items file that is there but empty leaves an empty list, not the defaults")
  func itemsEmpty() {
    let store = sandbox()
    try? "# everything commented out\n".write(to: store.itemsFile, atomically: true, encoding: .utf8)
    #expect(store.items().isEmpty)
  }

  @Test("the log lands in the same file `brb log` tails")
  func logging() {
    let store = sandbox()
    store.log("hello from the tests")
    let text = (try? String(contentsOf: store.logFile, encoding: .utf8)) ?? ""
    #expect(text.contains("[ui"))
    #expect(text.contains("hello from the tests"))
  }

  @Test("logging twice appends rather than replacing")
  func logAppends() {
    let store = sandbox()
    store.log("first line")
    store.log("second line")
    let text = (try? String(contentsOf: store.logFile, encoding: .utf8)) ?? ""
    #expect(text.contains("first line"))
    #expect(text.contains("second line"))
  }

  @Test("the socket sits under the state directory the hooks look in")
  func socketPath() {
    let store = sandbox()
    #expect(store.sock == store.root.appendingPathComponent("state/ui.sock").path)
  }
}
