import SwiftUI
import AppKit

struct PresetPicker: View {
    @ObservedObject var presetManager: PresetManager
    let onSelect: (RouterPreset) -> Void
    let onSave: () -> Void
    let onDelete: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            showMenu()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 8, weight: .semibold))
                Text(presetManager.selectedPresetName ?? "Custom")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(presetManager.selectedPresetName != nil ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                presetManager.selectedPresetName != nil
                    ? Color.blue.opacity(isHovered ? 0.9 : 0.7)
                    : Color.primary.opacity(isHovered ? 0.12 : 0.06),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func showMenu() {
        let menu = NSMenu()

        // Save current as preset
        let saveItem = NSMenuItem(title: "Save Current as Preset…", action: #selector(PresetMenuTarget.saveClicked(_:)), keyEquivalent: "")
        saveItem.target = PresetMenuTarget.shared
        saveItem.representedObject = onSave
        saveItem.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
        menu.addItem(saveItem)

        if !presetManager.presets.isEmpty {
            menu.addItem(.separator())

            // Custom option
            let customItem = NSMenuItem(title: "Custom", action: #selector(PresetMenuTarget.customClicked(_:)), keyEquivalent: "")
            customItem.target = PresetMenuTarget.shared
            customItem.representedObject = { [weak presetManager] in
                presetManager?.selectedPresetName = nil
            } as () -> Void
            if presetManager.selectedPresetName == nil {
                customItem.state = .on
            }
            menu.addItem(customItem)

            menu.addItem(.separator())

            let headerItem = NSMenuItem(title: "PRESETS", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            headerItem.attributedTitle = NSAttributedString(
                string: "PRESETS",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(headerItem)

            for preset in presetManager.presets {
                let item = NSMenuItem(title: preset.name, action: #selector(PresetMenuTarget.presetSelected(_:)), keyEquivalent: "")
                item.target = PresetMenuTarget.shared
                item.representedObject = (preset, onSelect) as Any
                if presetManager.selectedPresetName == preset.name {
                    item.state = .on
                }

                // Add submenu for delete
                let submenu = NSMenu()
                let deleteItem = NSMenuItem(title: "Delete \(preset.name)", action: #selector(PresetMenuTarget.deleteClicked(_:)), keyEquivalent: "")
                deleteItem.target = PresetMenuTarget.shared
                deleteItem.representedObject = (preset.name, onDelete) as Any
                deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                submenu.addItem(deleteItem)
                item.submenu = submenu

                menu.addItem(item)
            }
        }

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
        }
    }
}

class PresetMenuTarget: NSObject {
    static let shared = PresetMenuTarget()

    @objc func saveClicked(_ sender: NSMenuItem) {
        guard let callback = sender.representedObject as? () -> Void else { return }
        callback()
    }

    @objc func customClicked(_ sender: NSMenuItem) {
        guard let callback = sender.representedObject as? () -> Void else { return }
        callback()
    }

    @objc func presetSelected(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (RouterPreset, (RouterPreset) -> Void) else { return }
        let (preset, callback) = info
        callback(preset)
    }

    @objc func deleteClicked(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (String, (String) -> Void) else { return }
        let (name, callback) = info
        callback(name)
    }
}
