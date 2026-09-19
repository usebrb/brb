import Foundation
import Testing
@testable import brbui

// What the menu bar says, for every state a turn can leave it in.
@Suite("menu bar state")
struct SessionTests {
  let t0 = Date(timeIntervalSince1970: 1_700_000_000)

  @Test("nothing running is a cup of coffee")
  func idle() {
    let book = SessionBook()
    #expect(book.statusTitle(now: t0) == "☕️")
    #expect(book.headerLine(now: t0) == "☕️  Nothing running")
    #expect(!book.isBusy)
  }

  @Test("a working turn counts up")
  func working() {
    var book = SessionBook()
    book.start("s1", owner: "com.apple.Terminal", cwd: "/Users/me/code/brb", at: t0)
    #expect(book.statusTitle(now: t0.addingTimeInterval(74)) == "⚡️ 1m 14s")
    #expect(book.headerLine(now: t0.addingTimeInterval(74)) == "⚡️  Claude is working — 1m 14s · brb")
  }

  @Test("a turn with no working directory says so without a stray separator")
  func noProject() {
    var book = SessionBook()
    book.start("s1", owner: "com.apple.Terminal", cwd: "", at: t0)
    #expect(book.headerLine(now: t0.addingTimeInterval(5)) == "⚡️  Claude is working — 5s")
  }

  @Test("the longest running session is the one shown")
  func busiestWins() {
    var book = SessionBook()
    book.start("young", owner: "t", cwd: "/tmp/young", at: t0.addingTimeInterval(100))
    book.start("old", owner: "t", cwd: "/tmp/old", at: t0)
    #expect(book.busiest?.sid == "old")
    #expect(book.headerLine(now: t0.addingTimeInterval(160)).contains("old"))
  }

  @Test("ending one session leaves the other counting")
  func endOne() {
    var book = SessionBook()
    book.start("a", owner: "t", cwd: "/tmp/a", at: t0)
    book.start("b", owner: "t", cwd: "/tmp/b", at: t0.addingTimeInterval(10))
    let ended = book.end("a")
    #expect(ended?.project == "a")
    #expect(book.count == 1)
    #expect(book.busiest?.sid == "b")
  }

  @Test("ending a session nobody started is harmless")
  func endUnknown() {
    var book = SessionBook()
    #expect(book.end("ghost") == nil)
    #expect(book.count == 0)
  }

  @Test("a session with no id is never recorded")
  func emptySession() {
    var book = SessionBook()
    book.start("", owner: "t", cwd: "/tmp/x", at: t0)
    #expect(book.count == 0)
  }

  @Test("paused beats busy, and a flash beats both")
  func precedence() {
    var book = SessionBook()
    book.start("s1", owner: "t", cwd: "/tmp/x", at: t0)
    #expect(book.statusTitle(now: t0, off: true) == "💤")
    #expect(book.statusTitle(now: t0, off: true, flash: "✅") == "✅")
    #expect(book.statusTitle(now: t0, off: false, flash: "🔔") == "🔔")
    #expect(book.headerLine(now: t0, off: true) == "💤  brb is paused")
  }

  @Test("a clock that jumps backwards never shows a negative age")
  func clockSkew() {
    var book = SessionBook()
    book.start("s1", owner: "t", cwd: "/tmp/x", at: t0)
    #expect(book.statusTitle(now: t0.addingTimeInterval(-30)) == "⚡️ 0s")
    #expect(book.elapsed("s1", now: t0.addingTimeInterval(-30)) == 0)
  }
}
