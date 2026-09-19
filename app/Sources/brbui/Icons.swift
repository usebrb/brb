import AppKit

// Real site logos instead of stand-in emoji. Each icon comes from the site
// itself — no favicon service in the middle, so the only server that learns
// what is on your break list is the one you were about to visit anyway — and
// is cached under state/icons so it is fetched once, ever.
//
// Everything here degrades to nil, and nil means the emoji is used.
final class IconStore: @unchecked Sendable {
  typealias Fetch = @Sendable (URL) async -> Data?

  private let store: Store
  private let fetch: Fetch
  private let lock = NSLock()
  private var memory: [String: NSImage] = [:]
  private var missed: Set<String> = []

  init(store: Store, fetch: @escaping Fetch = IconStore.download) {
    self.store = store
    self.fetch = fetch
  }

  // An opt-out for anyone who would rather the app made no requests at all.
  var enabled: Bool {
    !FileManager.default.fileExists(atPath: store.root.appendingPathComponent("no-icons").path)
  }

  // Biggest first: apple-touch-icon is a real logo, favicon.ico is often 16px.
  static func candidates(forHost host: String) -> [URL] {
    let h = canonical(host)
    guard !h.isEmpty else { return [] }
    return [
      "https://\(h)/apple-touch-icon.png",
      "https://\(h)/apple-touch-icon-precomposed.png",
      "https://\(h)/favicon.ico",
    ].compactMap(URL.init(string:))
  }

  static func canonical(_ host: String) -> String {
    let h = host.lowercased().trimmingCharacters(in: .whitespaces)
    return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
  }

  func cacheURL(forHost host: String) -> URL {
    // A host is not a path: anything that could climb out of the directory is
    // replaced before it becomes a filename.
    let safe = String(IconStore.canonical(host)
      .map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
      .replacingOccurrences(of: "..", with: "_")
    return store.state
      .appendingPathComponent("icons")
      .appendingPathComponent(safe + ".png")
  }

  // Sync, for drawing: whatever we already have, or nothing.
  func cached(forHost host: String) -> NSImage? {
    let key = IconStore.canonical(host)
    guard !key.isEmpty else { return nil }
    if let hit = lock.withLock({ memory[key] }) { return hit }
    guard let data = try? Data(contentsOf: cacheURL(forHost: key)),
          let image = IconStore.image(from: data) else { return nil }
    lock.withLock { memory[key] = image }
    return image
  }

  @discardableResult
  func load(forHost host: String) async -> NSImage? {
    let key = IconStore.canonical(host)
    guard !key.isEmpty, enabled else { return nil }
    if let hit = cached(forHost: key) { return hit }
    if lock.withLock({ missed.contains(key) }) { return nil }

    for url in IconStore.candidates(forHost: key) {
      guard let data = await fetch(url), let image = IconStore.image(from: data) else { continue }
      try? FileManager.default.createDirectory(
        at: cacheURL(forHost: key).deletingLastPathComponent(), withIntermediateDirectories: true)
      if let png = IconStore.png(from: image) {
        try? png.write(to: cacheURL(forHost: key))
      }
      lock.withLock { memory[key] = image }
      return image
    }

    // Remember the miss for this run, so a dead host is not retried per frame.
    lock.withLock { _ = missed.insert(key) }
    return nil
  }

  func warm(_ items: [BreakItem]) {
    guard enabled else { return }
    let hosts = items.compactMap(\.host)
    guard !hosts.isEmpty else { return }
    Task.detached(priority: .utility) { [weak self] in
      for host in hosts { await self?.load(forHost: host) }
    }
  }

  // An error page is bytes too, so anything that is not a decodable image with
  // a real size is treated as a miss rather than cached.
  static func image(from data: Data) -> NSImage? {
    guard !data.isEmpty, let image = NSImage(data: data),
          image.size.width > 0, image.size.height > 0 else { return nil }
    return image
  }

  static func png(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  static let download: Fetch = { url in
    var request = URLRequest(url: url, timeoutInterval: 4)
    request.setValue("brb", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return data
  }
}
