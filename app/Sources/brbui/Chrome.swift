import AppKit
import SwiftUI

// A floating card that can take keystrokes without pulling focus away from the
// app you were using. Nonactivating panels don't become key by default.
final class KeyPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

enum Chrome {
  static func panel<V: View>(_ view: V, width: CGFloat) -> KeyPanel {
    let host = NSHostingView(rootView: AnyView(view))
    host.translatesAutoresizingMaskIntoConstraints = false

    let p = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
      styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
      backing: .buffered, defer: false)
    p.isFloatingPanel = true
    p.level = .floating
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.hidesOnDeactivate = false
    p.isMovableByWindowBackground = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    p.contentView = host
    p.setContentSize(host.fittingSize)
    return p
  }

  // Top-right of whichever screen the pointer is on, tucked under the menu bar.
  static func place(_ panel: NSPanel, dropFromTop: CGFloat = 12) {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let size = panel.frame.size
    let x = visible.maxX - size.width - 18
    let y = visible.maxY - size.height - dropFromTop
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  static func present(_ panel: NSPanel, dropFromTop: CGFloat = 12) {
    panel.alphaValue = 0
    place(panel, dropFromTop: dropFromTop)
    panel.orderFrontRegardless()
    panel.makeKey()
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.16
      panel.animator().alphaValue = 1
    }
  }
}

// Shared look: one card, one accent, legible in light and dark.
struct Card<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      // Material alone goes muddy over a bright page, so it gets a window-
      // coloured layer under it and stays readable wherever it lands.
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
      .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
      .padding(10)
  }
}

struct PillButton: View {
  let title: String
  var prominent = false
  var action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(prominent
                  ? Color.accentColor.opacity(hover ? 1.0 : 0.88)
                  : Color.primary.opacity(hover ? 0.14 : 0.08)))
        .foregroundStyle(prominent ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
  }
}
