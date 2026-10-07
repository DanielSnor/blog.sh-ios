import SwiftUI

/// What is the app's own and no blog's: how it is read on this device.
/// Where a blog is and the key to it are that blog's, and are kept with
/// it, behind its row in the list of blogs.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = AppLanguage.read()
    private var look = Look.shared

    var body: some View {
        PaperScreen(name: String(localized: "Settings")) {
            SectionLabel("Language")
            Plate {
                ForEach(AppLanguage.allCases) { choice in
                    Button {
                        language = choice
                        choice.write()
                    } label: {
                        HStack(spacing: 10) {
                            // A language is named in itself, so it is found by
                            // somebody who cannot read the one the app is in.
                            Group {
                                if let name = choice.name { Text(verbatim: name) } else { Text("As the system has it") }
                            }
                            .font(.ui(15))
                            .foregroundStyle(Theme.ink)
                            Spacer(minLength: 8)
                            if choice == language {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(choice == language ? .isSelected : [])
                }
            }
            Hint("The app speaks the chosen language after it is started again.")

            SectionLabel("Colours")
            Plate {
                SwitchRow(label: "Use the default colour scheme", isOn: Binding(get: { look.own }, set: { look.own = $0 }))
            }
            Hint("The app wears the colours of the blog that is open. With this on it keeps to its own, the same for every blog.")

            SectionLabel("Text size")
            TextSizePicker()
            Hint("The first is the size the system has; the others are steps above it. It holds on this device, for every blog.")

            BuildMark()
                .padding(.top, 36)
                .padding(.bottom, 8)
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// Which build this is, at the foot of the settings: the engine's mark,
/// when the app was built and from which commit. Nothing to set -- what
/// is read out when one copy has to be told from another.
struct BuildMark: View {
    var stamp = BuildStamp.own

    var body: some View {
        VStack(spacing: 8) {
            Image("EngineMark")
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            if let built = stamp.built {
                Text(verbatim: built.formatted(date: .numeric, time: .shortened))
                    .font(.mono(12))
                    .foregroundStyle(Theme.muted)
            }
            if let commit = stamp.commit {
                Text(verbatim: commit)
                    .font(.mono(12))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
