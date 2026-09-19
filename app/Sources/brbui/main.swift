import AppKit

// Two modes in one binary: the menu bar app, and the tiny client the hooks use
// to talk to it.
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "send":
  guard args.count > 1,
        let data = args[1].data(using: .utf8),
        let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  else {
    FileHandle.standardError.write(Data("usage: brb-ui send '{\"event\":\"...\"}'\n".utf8))
    exit(2)
  }
  guard let reply = Bus.send(path: Conf.sock, message: msg) else { exit(1) }
  print(reply)
  exit(reply.contains("\"ok\":true") ? 0 : 1)

case "--version":
  print("brb ui 1.0")
  exit(0)

default:
  // One app at a time: if something already answers on the socket, leave it be.
  if let reply = Bus.send(path: Conf.sock, message: ["event": "ping"], timeout: 1),
     reply.contains("\"ok\":true") {
    exit(0)
  }
  Conf.prepare()
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
}
