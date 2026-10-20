import AppKit
import HoverTalkCore

/// The Voice submenu of the status menu: the voice server's status line, Automatic, the voices
/// of the user's languages and of the last reading under language headers
/// (`VoiceCatalog.menuGroups`), a link to the Settings window for the rest, and the voice
/// download link with a hint.
@MainActor
final class VoiceMenu: NSObject {
    /// At most this many voices, plus the chosen one when it would not be shown.
    static let voiceLimit = 25

    let item = NSMenuItem(title: AppCopy.voiceMenuTitle, action: nil, keyEquivalent: "")
    var onSelect: ((VoiceSelection) -> Void)?
    var onShowSettings: (() -> Void)?

    private let menu = NSMenu()

    override init() {
        super.init()
        menu.autoenablesItems = false
        item.submenu = menu
    }

    /// Rebuilds the items for `catalog`, with a check mark on `selection`, under the voice
    /// server's status line (`RemoteVoicePresenter.menuStatus`) when there is one.
    func update(catalog: VoiceCatalog, selection: VoiceSelection, lastReadingLanguage: String?, serverStatus: String?) {
        menu.removeAllItems()

        if let serverStatus {
            let status = NSMenuItem(title: serverStatus, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.separator())
        }

        let automatic = makeItem(AppCopy.automaticVoiceTitle, action: #selector(selectAutomatic))
        automatic.state = selection == .automatic ? .on : .off
        menu.addItem(automatic)

        let groups = catalog.menuGroups(lastReadingLanguage: lastReadingLanguage, limit: Self.voiceLimit, keeping: selection)
        for group in groups {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: VoiceLanguageNames.name(for: group.language)))
            for voice in group.voices {
                let voiceItem = makeItem(voice.displayName, action: #selector(selectVoice(_:)))
                voiceItem.representedObject = voice.id
                voiceItem.state = selection == .voice(id: voice.id) ? .on : .off
                menu.addItem(voiceItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(AppCopy.moreVoicesMenuTitle, action: #selector(showSettings)))
        menu.addItem(makeItem(AppCopy.downloadMoreVoicesTitle, action: #selector(downloadVoices)))
        let hint = NSMenuItem(title: AppCopy.voiceQualityMenuHint, action: nil, keyEquivalent: "")
        hint.attributedTitle = NSAttributedString(
            string: AppCopy.voiceQualityMenuHint,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        hint.isEnabled = false
        menu.addItem(hint)
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func selectAutomatic() {
        onSelect?(.automatic)
    }

    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onSelect?(.voice(id: id))
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func downloadVoices() {
        VoiceDownloads.openSystemSettings()
    }
}
