import Foundation
import Testing
@testable import brbui

// The socket is the whole contract with the hooks: one line of JSON in, one
// line of JSON out, and never a hang.
@Suite("event bus", .serialized)
struct BusTests {
  private func tempSocket() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("brb-test-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("ui.sock").path
  }

  @Test("a message reaches the handler and the reply comes back")
  func roundTrip() throws {
    let path = tempSocket()
    let seen = Box<[String: Any]>([:])
    try Bus.listen(path: path) { msg in
      seen.value = msg
      return ["ok": true, "echo": msg["event"] as? String ?? ""]
    }

    let reply = try #require(Bus.send(path: path, message: ["event": "panel", "session": "s1"]))
    #expect(reply.contains("\"ok\":true"))
    #expect(reply.contains("panel"))
    #expect(seen.value["session"] as? String == "s1")
  }

  @Test("a handler that says no is reported as no")
  func refused() throws {
    let path = tempSocket()
    try Bus.listen(path: path) { _ in ["ok": false, "why": "off"] }
    let reply = try #require(Bus.send(path: path, message: ["event": "panel"]))
    #expect(reply.contains("\"ok\":false"))
  }

  @Test("nothing listening means no reply, not a hang")
  func noListener() {
    let start = Date()
    let reply = Bus.send(path: tempSocket(), message: ["event": "ping"], timeout: 1)
    #expect(reply == nil)
    #expect(Date().timeIntervalSince(start) < 3)
  }

  @Test("junk on the wire is answered, not crashed on")
  func junk() throws {
    let path = tempSocket()
    try Bus.listen(path: path) { _ in ["ok": true] }

    // Hand-rolled client: the real one would never send this.
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
    }
    #expect(connected == 0)
    _ = "not json at all\n".withCString { write(fd, $0, strlen($0)) }

    var buf = [UInt8](repeating: 0, count: 256)
    let n = read(fd, &buf, buf.count)
    #expect(n > 0)
    #expect(String(decoding: buf[0..<max(0, n)], as: UTF8.self).contains("\"ok\":false"))
  }

  @Test("a path too long for sun_path is refused, not truncated")
  func longPath() {
    let long = "/tmp/" + String(repeating: "x", count: 200) + "/ui.sock"
    #expect(throws: (any Error).self) { try Bus.listen(path: long) { _ in ["ok": true] } }
    #expect(Bus.send(path: long, message: ["event": "ping"], timeout: 1) == nil)
  }
}

// Small holder so a test can read what the socket thread handed the handler.
final class Box<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T
  init(_ value: T) { stored = value }
  var value: T {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
