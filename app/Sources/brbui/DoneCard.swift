import AppKit
import SwiftUI

final class DoneCardController {
  private var panel: KeyPanel?
  private var expiry: Timer?

  private let message: String
  private let owner: String
  private let project: String
  private let worked: Int?

  init(message: String, owner: String, project: String, worked: Int?) {
    self.message = message
    self.owner = owner
    self.project = project
    self.worked = worked
  }

  func show() {
    let backTo = Apps.name(forID: owner)
    let view = DoneCardView(
      message: message,
      project: project,
      worked: worked,
      backTo: backTo,
      onBack: { [weak self] in
        guard let self else { return }
        Apps.activate(bundleID: self.owner)
        Conf.log("back to work -> \(self.owner)")
        self.close()
      },
      onStay: { [weak self] in self?.close() })

    // Clear of the notification banner, which is drawn above every window.
    let p = Chrome.panel(view, width: 340)
    Chrome.present(p, dropFromTop: 104)
    panel = p

    // Same ten minutes the AppleScript dialog gave up after.
    expiry = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
      self?.close()
    }
  }

  func close() {
    expiry?.invalidate()
    expiry = nil
    guard let p = panel else { return }
    panel = nil
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.12
      p.animator().alphaValue = 0
    }, completionHandler: { p.orderOut(nil) })
  }
}

struct DoneCardView: View {
  let message: String
  let project: String
  let worked: Int?
  let backTo: String?
  let onBack: () -> Void
  let onStay: () -> Void

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Text("✅").font(.system(size: 24))
          VStack(alignment: .leading, spacing: 2) {
            Text("Claude is done").font(.system(size: 14, weight: .semibold))
            if !subtitle.isEmpty {
              Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
          }
        }

        Text(message)
          .font(.system(size: 12))
          .foregroundStyle(.primary.opacity(0.9))
          .fixedSize(horizontal: false, vertical: true)

        HStack {
          PillButton(title: "Stay here", action: onStay)
          Spacer()
          PillButton(title: backTo.map { "Back to \($0)" } ?? "Back to work",
                     prominent: true, action: onBack)
        }
        .padding(.top, 2)
      }
      .padding(16)
    }
    .frame(width: 340)
    .onKeyPress(.escape) { onStay(); return .handled }
    .onKeyPress(.return) { onBack(); return .handled }
  }

  private var subtitle: String {
    var parts: [String] = []
    if let worked { parts.append("worked \(Conf.fmt(worked))") }
    if !project.isEmpty { parts.append(project) }
    return parts.joined(separator: " · ")
  }
}
