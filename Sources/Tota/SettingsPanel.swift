import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject var model: AppModel
    private let d = GenSettings.defaults

    private var modeHelp: String {
        switch model.settings.conditioning {
        case "icl":
            return "Copies how you speak in the sample: pace, stress and pauses. Closest to you in testing."
        case "icl_spk":
            return "Copies the sample and adds a voice fingerprint. The voice is steadier, but the delivery drifts toward the model's own style."
        default:
            return "Voice fingerprint only. Ignores the sample's words, so the delivery is the model's own."
        }
    }

    var body: some View {
        Form {
            Section("How it copies you") {
                Picker("Mode", selection: $model.settings.conditioning) {
                    Text("icl").tag("icl")
                    Text("icl + spk").tag("icl_spk")
                    Text("spk").tag("spk")
                }
                .pickerStyle(.segmented)
                Text(modeHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Delivery") {
                SliderRow(title: "Temperature", value: $model.settings.temperature,
                          range: 0...1.5, step: 0.05, format: "%.2f", defaultValue: d.temperature,
                          help: "How much the delivery varies. Lower is steadier but flatter. Higher is livelier but can drift, slur or overact.")
                SliderRow(title: "Detail temperature", value: $model.settings.depthTemperature,
                          range: 0...1.5, step: 0.05, format: "%.2f", defaultValue: d.depthTemperature,
                          help: "Variation in the fine texture of the sound, like breath and rasp. Lower is cleaner, higher is rougher.")
            }

            Section("Sampling limits") {
                SliderRow(title: "Top K", value: intBinding(\.topK),
                          range: 0...256, step: 1, format: "%.0f", defaultValue: Double(d.topK),
                          help: "Each step picks from only the K likeliest sounds. Lower is safer and plainer. 0 turns the limit off.")
                SliderRow(title: "Top P", value: $model.settings.topP,
                          range: 0.05...1, step: 0.05, format: "%.2f", defaultValue: d.topP,
                          help: "Each step picks from the likeliest sounds that together make up this share. 1.00 turns it off.")
                SliderRow(title: "Detail top K", value: intBinding(\.depthTopK),
                          range: 0...256, step: 1, format: "%.0f", defaultValue: Double(d.depthTopK),
                          help: "The same limit for the fine texture of the sound. 0 turns it off.")
            }

            Section("Repetition") {
                SliderRow(title: "Repeat penalty", value: $model.settings.presencePenalty,
                          range: 0...3, step: 0.1, format: "%.1f", defaultValue: d.presencePenalty,
                          help: "Discourages repeating the same sound. Raise it if takes stutter or loop. Too high sounds unnatural. 0 turns it off.")
                SliderRow(title: "Repeat window", value: intBinding(\.presenceWindow),
                          range: 0...64, step: 1, format: "%.0f", defaultValue: Double(d.presenceWindow),
                          help: "How many recent steps the penalty looks back over. 12 steps is about 1 second.")
            }

            Section("Long text") {
                Toggle("Split text into chunks", isOn: $model.settings.splitText)
                Text("The model can run on past the end of long text. Chunks keep each piece short. Each chunk is made separately, so the tone can reset between chunks. If a chunk runs on, the app makes it again, up to 3 tries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.settings.splitText {
                    SliderRow(title: "Chunk size (characters)", value: intBinding(\.maxChars),
                              range: 60...400, step: 10, format: "%.0f", defaultValue: Double(d.maxChars),
                              help: "Longest piece spoken in one go. Chunks end at sentence ends, or at commas in long sentences.")
                    SliderRow(title: "Pause between chunks (seconds)", value: $model.settings.gap,
                              range: 0...1, step: 0.05, format: "%.2f", defaultValue: d.gap,
                              help: "Silence added where one chunk ends and the next starts.")
                }
            }

            Section("Repeatability") {
                Toggle("Fixed seed", isOn: $model.settings.useSeed)
                if model.settings.useSeed {
                    HStack {
                        TextField("Seed", value: $model.settings.seed, format: .number.grouping(.never))
                            .frame(width: 110)
                        Button {
                            model.settings.seed = Int.random(in: 1...999_999)
                        } label: {
                            Label("New Seed", systemImage: "dice")
                        }
                    }
                }
                Text("With a fixed seed, the same text and settings give the same take. Change one setting and you hear only that change. Turn it off to get a new variation each time. Every take records its seed, and Use These Settings on a take brings it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Reset to Defaults") { model.settings = GenSettings() }
                    .disabled(model.settings == GenSettings.defaults)
            }
        }
        .formStyle(.grouped)
    }

    private func intBinding(_ key: WritableKeyPath<GenSettings, Int>) -> Binding<Double> {
        Binding(
            get: { Double(model.settings[keyPath: key]) },
            set: { model.settings[keyPath: key] = Int($0.rounded()) }
        )
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let defaultValue: Double
    let help: String

    private var isDefault: Bool { abs(value - defaultValue) < step / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if !isDefault {
                    Button {
                        value = defaultValue
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to \(String(format: format, defaultValue))")
                }
                Text(String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(isDefault ? .secondary : .primary)
                    .frame(minWidth: 38, alignment: .trailing)
            }
            // Snap to the step here; a stepped Slider draws a tick mark for every step.
            Slider(value: Binding(
                get: { value },
                set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }
            ), in: range)
                .labelsHidden()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
