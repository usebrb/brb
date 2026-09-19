import AppKit
import Foundation
import Testing
@testable import brbui

// Site icons are fetched from the site itself and cached on disk. The rules
// that matter: never fetch twice, never cache junk, never block the panel, and
// always fall back to the emoji.
@Suite("site icons")
struct IconTests {
  // A 1x1 red PNG, so the tests need no window server to make an image.
  static let png = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """)!

  private func sandbox() -> Store {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("brb-icons-\(UUID().uuidString.prefix(8))")
    let store = Store(root: dir)
    store.prepare()
    return store
  }

  @Test("the site's own icon is tried, biggest first, and no third party is asked")
  func candidates() {
    let urls = IconStore.candidates(forHost: "news.ycombinator.com").map(\.absoluteString)
    #expect(urls.first == "https://news.ycombinator.com/apple-touch-icon.png")
    #expect(urls.contains("https://news.ycombinator.com/favicon.ico"))
    #expect(urls.allSatisfy { $0.contains("news.ycombinator.com") })
  }

  @Test("www is dropped so one cache entry serves both spellings")
  func wwwFolded() {
    let store = sandbox()
    let icons = IconStore(store: store) { _ in nil }
    #expect(icons.cacheURL(forHost: "www.reddit.com") == icons.cacheURL(forHost: "reddit.com"))
    #expect(icons.cacheURL(forHost: "reddit.com").path.hasPrefix(store.state.path))
  }

  @Test("a host that would escape the cache directory is made safe")
  func sanitised() {
    let icons = IconStore(store: sandbox()) { _ in nil }
    let path = icons.cacheURL(forHost: "../../etc/passwd").path
    #expect(!path.contains(".."))
    #expect(path.hasSuffix(".png"))
  }

  @Test("a fetched icon is returned and written to the cache")
  func fetchAndCache() async {
    let store = sandbox()
    let icons = IconStore(store: store) { _ in Self.png }
    let image = await icons.load(forHost: "x.com")
    #expect(image != nil)
    #expect(FileManager.default.fileExists(atPath: icons.cacheURL(forHost: "x.com").path))
  }

  @Test("the second ask never reaches the network")
  func fetchedOnce() async {
    let calls = Box(0)
    let icons = IconStore(store: sandbox()) { _ in
      calls.value += 1
      return Self.png
    }
    _ = await icons.load(forHost: "x.com")
    _ = await icons.load(forHost: "x.com")
    #expect(calls.value == 1)
  }

  @Test("a cache written earlier survives a restart")
  func survivesRestart() async {
    let store = sandbox()
    _ = await IconStore(store: store) { _ in Self.png }.load(forHost: "x.com")

    let calls = Box(0)
    let fresh = IconStore(store: store) { _ in calls.value += 1; return Self.png }
    #expect(fresh.cached(forHost: "x.com") != nil)
    _ = await fresh.load(forHost: "x.com")
    #expect(calls.value == 0)
  }

  @Test("an HTML error page is not cached as an icon")
  func junkNotCached() async {
    let store = sandbox()
    let icons = IconStore(store: store) { _ in Data("<!doctype html><title>404</title>".utf8) }
    let image = await icons.load(forHost: "example.com")
    #expect(image == nil)
    #expect(!FileManager.default.fileExists(atPath: icons.cacheURL(forHost: "example.com").path))
  }

  @Test("every candidate failing just means no icon")
  func allFail() async {
    let icons = IconStore(store: sandbox()) { _ in nil }
    #expect(await icons.load(forHost: "offline.example") == nil)
  }

  @Test("a later candidate is used when the first one is missing")
  func fallsThrough() async {
    let icons = IconStore(store: sandbox()) { url in
      url.path.hasSuffix("favicon.ico") ? Self.png : nil
    }
    #expect(await icons.load(forHost: "x.com") != nil)
  }

  @Test("an empty host is not a fetch")
  func emptyHost() async {
    let calls = Box(0)
    let icons = IconStore(store: sandbox()) { _ in calls.value += 1; return Self.png }
    #expect(await icons.load(forHost: "") == nil)
    #expect(calls.value == 0)
  }

  @Test("the no-icons file turns fetching off entirely")
  func optOut() async {
    let store = sandbox()
    try? Data().write(to: store.root.appendingPathComponent("no-icons"))
    let calls = Box(0)
    let icons = IconStore(store: store) { _ in calls.value += 1; return Self.png }
    #expect(!icons.enabled)
    #expect(await icons.load(forHost: "x.com") == nil)
    #expect(calls.value == 0)
  }

  @Test("notes never ask for an icon: they are not a site")
  func notesHaveNoHost() throws {
    let note = try #require(BreakItem(line: "Water|note:Refill."))
    let site = try #require(BreakItem(line: "X|https://x.com"))
    #expect(note.host == nil)
    #expect(site.host == "x.com")
  }
}
