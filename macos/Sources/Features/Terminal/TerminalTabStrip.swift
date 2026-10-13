import AppKit
import SwiftUI

/// Tracks the native tab group of a window so the bottom strip can render it.
/// Every tab is its own NSWindow, so each window owns one strip and one model.
final class TerminalTabStripModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: ObjectIdentifier
        let index: Int
        let title: String
        let isSelected: Bool
        weak var window: NSWindow?

        static func == (l: Tab, r: Tab) -> Bool {
            l.id == r.id && l.index == r.index && l.title == r.title && l.isSelected == r.isSelected
        }
    }

    @Published private(set) var tabs: [Tab] = []

    private weak var window: NSWindow?
    private var observations: [NSKeyValueObservation] = []
    private var observedIDs: [ObjectIdentifier] = []
    private var notificationTokens: [NSObjectProtocol] = []

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func attach(to window: NSWindow?) {
        guard window !== self.window else { return }
        self.window = window
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens = []
        guard let window else {
            observations = []
            observedIDs = []
            tabs = []
            return
        }

        // The tab group is assigned after the window is created, so refresh
        // when the window gains focus and once on the next loop turn.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
        refresh()
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func select(_ tab: Tab) {
        guard let target = tab.window else { return }
        target.tabGroup?.selectedWindow = target
        target.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        guard let window else { return }

        let windows = window.tabGroup?.windows ?? [window]
        let selected = window.tabGroup?.selectedWindow ?? window
        let newTabs = windows.enumerated().map { offset, w in
            Tab(
                id: ObjectIdentifier(w),
                index: offset + 1,
                title: w.title,
                isSelected: w === selected,
                window: w
            )
        }
        if newTabs != tabs { tabs = newTabs }

        // Only rebind observers when the set of windows changes, not on
        // every title update.
        let ids = windows.map { ObjectIdentifier($0) }
        if ids != observedIDs {
            observedIDs = ids
            observe(windows: windows)
        }

    }

    private func observe(windows: [NSWindow]) {
        observations = []

        if let group = window?.tabGroup {
            observations.append(group.observe(\.windows, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            })
            observations.append(group.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            })
        }

        for w in windows {
            observations.append(w.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            })
        }
    }
}

/// A tmux-style status strip: `1:title  2:title`, active tab inverted.
struct TerminalTabStripView: View {
    @ObservedObject var model: TerminalTabStripModel

    static let height: CGFloat = 24

    /// Tabs size to their text, so long titles are cut to keep the strip readable.
    private static func shortTitle(_ title: String) -> String {
        title.count > 24 ? String(title.prefix(23)) + "…" : title
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.tabs) { tab in
                Button { model.select(tab) } label: {
                    Text("\(tab.index):\(Self.shortTitle(tab.title))")
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                        .foregroundColor(tab.isSelected ? .black : .white.opacity(0.65))
                        .background(tab.isSelected ? Color.white.opacity(0.85) : .clear)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // Darkens whatever the window shows behind it, so the strip follows
        // background-opacity and blur but stays distinct from the terminal.
        .background(Color.black.opacity(0.3))
    }
}
