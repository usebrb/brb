import Foundation
import Testing
@testable import brbui

// The item list is the one thing users edit by hand, so every shape it can
// take has a case here.
@Suite("break items")
struct ItemTests {

  @Test("a site is a departure and keeps its label")
  func site() throws {
    let item = try #require(BreakItem(line: "Hacker News|https://news.ycombinator.com"))
    #expect(item.label == "Hacker News")
    #expect(item.leaves)
    if case .site(let url) = item.kind {
      #expect(url.host() == "news.ycombinator.com")
    } else {
      Issue.record("expected a site, got \(item.kind)")
    }
  }

  @Test("a note is not a departure")
  func note() throws {
    let item = try #require(BreakItem(line: "Water|note:Refill your glass."))
    #expect(!item.leaves)
    #expect(item.emoji == "📝")
    if case .note(let text) = item.kind {
      #expect(text == "Refill your glass.")
    } else {
      Issue.record("expected a note")
    }
  }

  @Test("a non-http scheme opens its app and still counts as leaving")
  func appScheme() throws {
    let item = try #require(BreakItem(line: "Music|music://"))
    #expect(item.leaves)
    if case .app = item.kind {} else { Issue.record("expected an app target") }
  }

  @Test("a leading emoji becomes the icon")
  func leadingEmoji() throws {
    let item = try #require(BreakItem(line: "🐦 X|https://x.com"))
    #expect(item.emoji == "🐦")
    #expect(item.label == "X")
  }

  @Test("a known host gets an icon when the label has none")
  func hostIcon() throws {
    let x = try #require(BreakItem(line: "X|https://x.com"))
    let hn = try #require(BreakItem(line: "HN|https://news.ycombinator.com"))
    let other = try #require(BreakItem(line: "Somewhere|https://example.com"))
    #expect(x.emoji == "🐦")
    #expect(hn.emoji == "📰")
    #expect(other.emoji == "🌐")
  }

  @Test("comments, blanks and malformed lines are skipped", arguments: [
    "", "   ", "# a comment", "no pipe here", "Label|", "|https://x.com", "Label|not-a-url",
  ])
  func skipped(line: String) {
    #expect(BreakItem(line: line) == nil)
  }

  @Test("the shipped defaults all parse")
  func defaultsParse() {
    let lines = Store.defaultItems.split(separator: "\n", omittingEmptySubsequences: false)
    let parsed = lines.compactMap { BreakItem(line: String($0)) }
    #expect(parsed.count == 6)
    #expect(parsed.filter(\.leaves).count == 3)
  }
}

@Suite("durations")
struct DurationTests {
  @Test("seconds under a minute stay seconds")
  func seconds() {
    #expect(Store.fmt(5) == "5s")
    #expect(Store.fmt(59) == "59s")
  }

  @Test("whole minutes drop the seconds")
  func minutes() {
    #expect(Store.fmt(60) == "1m")
    #expect(Store.fmt(300) == "5m")
  }

  @Test("anything else reads as both")
  func both() {
    #expect(Store.fmt(90) == "1m 30s")
    #expect(Store.fmt(4 * 60 + 12) == "4m 12s")
  }
}
