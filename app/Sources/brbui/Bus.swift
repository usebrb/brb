import Foundation

// A one-line-of-JSON-per-connection unix socket. The hooks are the only
// clients; they fall back to the AppleScript path when nothing answers here.
enum Bus {
  static func listen(path: String, handler: @escaping ([String: Any]) -> [String: Any]) throws {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw Err.socket("socket(): \(errno)") }

    guard var addr = address(for: path) else {
      close(fd)
      throw Err.socket("socket path too long")
    }

    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
    }
    guard bound == 0 else { close(fd); throw Err.socket("bind(): \(errno)") }
    guard Foundation.listen(fd, 16) == 0 else { close(fd); throw Err.socket("listen(): \(errno)") }
    chmod(path, 0o600)

    Thread.detachNewThread {
      while true {
        let cfd = accept(fd, nil, nil)
        if cfd < 0 { if errno == EINTR { continue }; break }
        serve(cfd, handler)
      }
      close(fd)
    }
  }

  private static func serve(_ cfd: Int32, _ handler: @escaping ([String: Any]) -> [String: Any]) {
    defer { close(cfd) }
    guard let line = readLine(cfd), let data = line.data(using: .utf8),
          let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      _ = write(cfd, "{\"ok\":false}\n", 13)
      return
    }
    // The UI lives on the main thread; the socket does not.
    var reply: [String: Any] = ["ok": false]
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
      reply = handler(msg)
      done.signal()
    }
    // A wedged UI must not wedge a Claude Code hook.
    if done.wait(timeout: .now() + 4) == .timedOut { reply = ["ok": false, "why": "busy"] }
    let out = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"ok\":false}".utf8)
    var payload = out
    payload.append(0x0A)
    payload.withUnsafeBytes { _ = write(cfd, $0.baseAddress, payload.count) }
  }

  private static func readLine(_ fd: Int32) -> String? {
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while out.count < 1 << 20 {
      let n = read(fd, &buf, buf.count)
      if n <= 0 { break }
      out.append(contentsOf: buf[0..<n])
      if out.last == 0x0A { break }
    }
    guard !out.isEmpty else { return nil }
    return String(data: out, encoding: .utf8)
  }

  // Client half, so `brb` can talk to a running app without needing netcat.
  static func send(path: String, message: [String: Any], timeout: TimeInterval = 4) -> String? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    guard var addr = address(for: path) else { return nil }

    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
    }
    guard connected == 0 else { return nil }

    guard var body = (try? JSONSerialization.data(withJSONObject: message)) else { return nil }
    body.append(0x0A)
    let wrote = body.withUnsafeBytes { write(fd, $0.baseAddress, body.count) }
    guard wrote == body.count else { return nil }

    return readLine(fd)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // sun_path is a fixed C array; fill it as raw bytes rather than reaching into
  // the tuple, which counts as overlapping access.
  private static func address(for path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    return addr
  }

  enum Err: Error { case socket(String) }
}
