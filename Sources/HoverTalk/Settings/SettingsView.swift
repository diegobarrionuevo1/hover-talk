import HoverTalkCore
import SwiftUI

/// The Settings window's content: voice, speed, reading mode, and the voice server placeholder.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(AppCopy.voiceSectionTitle) {
                voiceSection.padding(8)
            }
            GroupBox(AppCopy.speedSectionTitle) {
                speedSection.padding(8)
            }
            GroupBox(AppCopy.readingSectionTitle) {
                Toggle(
                    AppCopy.continuousReadingSettingTitle,
                    isOn: Binding(get: { model.isContinuous }, set: { model.setContinuous($0) })
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            // Placeholder: T6d fills this section with the self-hosted voice server settings.
            GroupBox(AppCopy.voiceServerSectionTitle) {
                Text(AppCopy.voiceServerPlaceholder)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(AppCopy.voiceSearchPlaceholder, text: $model.query)
                .textFieldStyle(.roundedBorder)
            List(selection: Binding(get: { model.selection }, set: { if let selection = $0 { model.select(selection) } })) {
                Text(AppCopy.automaticVoiceTitle).tag(VoiceSelection.automatic)
                ForEach(model.groups) { group in
                    Section(VoiceLanguageNames.name(for: group.language)) {
                        ForEach(group.voices) { voice in
                            Text(voice.displayName).tag(VoiceSelection.voice(id: voice.id))
                        }
                    }
                }
            }
            .frame(height: 260)
            HStack {
                Button(AppCopy.previewVoiceButton) { model.preview() }
                Spacer()
                Button(AppCopy.downloadMoreVoicesTitle) { model.downloadVoices() }
            }
            Text(AppCopy.voiceQualityHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var speedSection: some View {
        HStack {
            Slider(
                value: Binding(get: { model.rate.multiplier }, set: { model.setRate(multiplier: $0) }),
                in: SpeechRate.minimum...SpeechRate.maximum,
                step: SpeechRate.step
            )
            Text(model.rate.displayText)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }
}
