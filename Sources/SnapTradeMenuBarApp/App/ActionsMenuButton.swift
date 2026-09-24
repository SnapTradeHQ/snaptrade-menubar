import AppKit
import SwiftUI

/// A native pull-down menu with one continuous highlight while its menu is open.
struct ActionsMenuButton: NSViewRepresentable {
    struct Item {
        let title: String?
        let enabled: Bool
        let action: (@MainActor () -> Void)?

        static let separator = Item(title: nil, enabled: false, action: nil)

        static func action(
            _ title: String,
            enabled: Bool = true,
            action: @escaping @MainActor () -> Void
        ) -> Item {
            Item(title: title, enabled: enabled, action: action)
        }
    }

    let items: [Item]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MenuButton {
        let button = MenuButton(frame: .zero)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Actions")
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.setAccessibilityLabel("Actions")
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        return button
    }

    func updateNSView(_ button: MenuButton, context: Context) {
        context.coordinator.items = items
    }

    final class MenuButton: NSButton {
        func setMenuOpen(_ open: Bool) {
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.backgroundColor = open
                ? NSColor.labelColor.withAlphaComponent(0.15).cgColor
                : nil
        }
    }

    @MainActor final class Coordinator: NSObject {
        var items: [Item] = []

        @objc func openMenu(_ sender: MenuButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, entry) in items.enumerated() {
                guard let title = entry.title else {
                    menu.addItem(.separator())
                    continue
                }
                let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
                item.tag = index
                item.target = self
                item.isEnabled = entry.enabled
                menu.addItem(item)
            }
            sender.setMenuOpen(true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
            sender.setMenuOpen(false)
        }

        @objc private func selectItem(_ item: NSMenuItem) {
            guard items.indices.contains(item.tag) else { return }
            items[item.tag].action?()
        }
    }
}
