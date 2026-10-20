import HoverTalkCore
import SwiftUI

/// The Settings window's content: voice, speed, reading mode, and the voice server.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @FocusState private var isURLFieldFocused: Bool

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
            GroupBox(AppCopy.voiceServerSectionTitle) {
                voiceServerSection.padding(8)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var voiceServerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                AppCopy.voiceServerToggleTitle,
                isOn: Binding(get: { model.server.enabled }, set: { model.setServerEnabled($0) })
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                TextField(AppCopy.voiceServerURLLabel, text: $model.serverURLText, prompt: Text(AppCopy.voiceServerURLPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($isURLFieldFocused)
                    .onSubmit { model.commitServerURL() }
                Button(AppCopy.testConnectionButton) { model.testConnection() }
            }
            .onChange(of: isURLFieldFocused) { _, isFocused in
                if !isFocused {
                    model.commitServerURL()
                }
            }
            if let message = model.urlValidationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let status = model.connectionStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(
                AppCopy.remoteVoicePickerTitle,
                selection: Binding(get: { model.server.voice }, set: { model.selectRemoteVoice($0) })
            ) {
                Text(AppCopy.automaticVoiceTitle).tag(VoiceSelection.automatic)
                ForEach(model.remoteVoiceChoices) { voice in
                    Text(model.label(for: voice)).tag(VoiceSelection.voice(id: voice.id))
                }
            }
            Text(AppCopy.voiceServerPrivacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppCopy.voiceServerGuide)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
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
