import AppKit
import SwiftUI

final class BreakPanelController {
  var onPick: ((BreakItem) -> Void)?
  private var panel: KeyPanel?
  private let sid: String
  private let started: Date
  private let project: String

  init(sid: String, started: Date, project: String) {
    self.sid = sid
    self.started = started
    self.project = project
  }

  func show() {
    let view = BreakPanelView(
      started: started,
      project: project,
      items: Conf.items(),
      onPick: { [weak self] item in self?.onPick?(item) },
      onClose: { [weak self] in self?.close() })
    let p = Chrome.panel(view, width: 360)
    Chrome.present(p)
    panel = p
  }

  func close() {
    guard let p = panel else { return }
    panel = nil
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.12
      p.animator().alphaValue = 0
    }, completionHandler: { p.orderOut(nil) })
  }
}

struct BreakPanelView: View {
  let started: Date
  let project: String
  let items: [BreakItem]
  let onPick: (BreakItem) -> Void
  let onClose: () -> Void

  @State private var note: BreakItem?
  @State private var delay: Int = Conf.delay
  @State private var showTimer = false

  private let presets = [5, 10, 30, 60, 120, 300]

  var body: some View {
    Card {
      if let note { noteView(note) } else { listView }
    }
    .frame(width: 360)
    .onKeyPress(.escape) { onClose(); return .handled }
    .onKeyPress { press in
      guard note == nil, let n = Int(press.characters), n >= 1, n <= items.count
      else { return .ignored }
      pick(items[n - 1])
      return .handled
    }
  }

  // MARK: - the list

  private var listView: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider().opacity(0.5)

      VStack(spacing: 1) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          ItemRow(item: item, index: index + 1) { pick(item) }
        }
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 6)

      Divider().opacity(0.5)
      footer
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      Text("☕️").font(.system(size: 26))
      VStack(alignment: .leading, spacing: 2) {
        Text("Time for a break?").font(.system(size: 14, weight: .semibold))
        TimelineView(.periodic(from: .now, by: 1)) { _ in
          Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
          .foregroundStyle(.secondary).padding(6)
      }
      .buttonStyle(.plain)
      .help("Stay here")
    }
    .padding(.horizontal, 14)
    .padding(.top, 13)
    .padding(.bottom, 11)
  }

  private var subtitle: String {
    let secs = max(0, Int(Date().timeIntervalSince(started)))
    let where_ = project.isEmpty ? "" : " · \(project)"
    return "Claude has been working \(Conf.fmt(secs))\(where_)"
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Button {
          withAnimation(.easeOut(duration: 0.12)) { showTimer.toggle() }
        } label: {
          HStack(spacing: 4) {
            Text("⏱")
            Text("Panel opens after \(Conf.fmt(delay))")
            Image(systemName: showTimer ? "chevron.up" : "chevron.down")
              .font(.system(size: 8, weight: .bold))
          }
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)

        Spacer()
        PillButton(title: "Stay here", action: onClose)
      }

      if showTimer {
        HStack(spacing: 6) {
          ForEach(presets, id: \.self) { secs in
            Button {
              delay = secs
              Conf.delay = secs
              Conf.log("break timer set to \(secs)s (panel)")
            } label: {
              Text(Conf.fmt(secs))
                .font(.system(size: 11, weight: secs == delay ? .semibold : .regular))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                  RoundedRectangle(cornerRadius: 6)
                    .fill(secs == delay ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08)))
                .foregroundStyle(secs == delay ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
          }
        }
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }

  // MARK: - a note stays in the panel; it is not a departure

  private func noteView(_ item: BreakItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(item.emoji).font(.system(size: 34))
      Text(item.label).font(.system(size: 14, weight: .semibold))
      if case .note(let text) = item.kind {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        PillButton(title: "Back to the list") { withAnimation { note = nil } }
        Spacer()
        PillButton(title: "Done", prominent: true, action: onClose)
      }
    }
    .padding(16)
  }

  private func pick(_ item: BreakItem) {
    if case .note = item.kind {
      withAnimation(.easeOut(duration: 0.12)) { note = item }
    } else {
      onPick(item)
    }
  }
}

// The site's own logo when we have it, the emoji until then.
struct ItemIcon: View {
  let item: BreakItem
  var size: CGFloat = 17
  @State private var logo: NSImage?

  var body: some View {
    Group {
      if let logo {
        Image(nsImage: logo)
          .resizable()
          .interpolation(.high)
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      } else {
        Text(item.emoji).font(.system(size: size - 1))
      }
    }
    .frame(width: 22, height: size)
    .task {
      guard let host = item.host else { return }
      if let hit = Conf.icons.cached(forHost: host) { logo = hit; return }
      logo = await Conf.icons.load(forHost: host)
    }
  }
}

private struct ItemRow: View {
  let item: BreakItem
  let index: Int
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        ItemIcon(item: item)
        Text(item.label).font(.system(size: 13))
        Spacer()
        if item.leaves && hover {
          Text("calls you back").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        Text("\(index)")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.secondary.opacity(hover ? 0.9 : 0.45))
          .frame(width: 14)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(hover ? Color.primary.opacity(0.09) : Color.clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
  }
}
