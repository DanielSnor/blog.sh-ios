import SwiftUI

/// What is the app's own and no blog's: how it is read on this device.
/// Where a blog is and the key to it are that blog's, and are kept with
/// it, behind its row in the list of blogs.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = AppLanguage.read()

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

            ColoursSection()

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

/// Whose colours the app wears -- the open blog's, its own, or the ones
/// chosen here -- and, for the last, the table they are chosen in: five
/// colours by day and five by night, each a well that opens the system's
/// picker.
struct ColoursSection: View {
    @Environment(\.colorScheme) private var colorScheme
    private var look = Look.shared
    @State private var picking: Pick?

    /// The chosen colours cannot be read on this screen as it is now: the
    /// section then keeps to the app's own, so there is always a way back.
    private var unreadable: Bool {
        guard look.wearing == .chosen else { return false }
        let worn = look.worn
        return !(colorScheme == .dark ? worn.dark : worn.light).legible
    }

    var body: some View {
        // In the app's own colours while the chosen ones cannot be read.
        let ground: Ground? = unreadable ? .plain : nil
        let ink = ground?.ink ?? Theme.ink
        let muted = ground?.muted ?? Theme.muted
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Colours")
            Plate {
                ForEach(Colouring.allCases) { choice in
                    Button {
                        if choice == .chosen { look.wearChosen() } else { look.wearing = choice }
                    } label: {
                        HStack(spacing: 10) {
                            Text(name(choice))
                                .font(.ui(15))
                                .foregroundStyle(ink)
                            Spacer(minLength: 8)
                            if choice == look.wearing {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(choice == look.wearing ? .isSelected : [])
                }
            }
            Hint("The app wears the colours of the blog that is open, its default ones, or the ones chosen here.")

            if look.wearing == .chosen {
                Plate {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Text("Light").engineLabel(11, bold: false).foregroundStyle(muted)
                                .gridColumnAlignment(.center)
                            Text("Dark").engineLabel(11, bold: false).foregroundStyle(muted)
                                .gridColumnAlignment(.center)
                        }
                        ForEach(Shades.Part.allCases) { part in
                            GridRow {
                                Text(verbatim: name(part))
                                    .font(.ui(15))
                                    .foregroundStyle(ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ForEach([false, true], id: \.self) { dark in
                                    let pick = Pick(part: part, dark: dark)
                                    ColourWell(value: well(pick).wrappedValue, edge: muted, label: Text(title(pick))) { picking = pick }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 14)
                Hint(ground != nil ? "The chosen colours cannot be read here, so this part keeps to the default scheme until they can."
                           : "Tap a colour to change it. It holds on this device, for every blog.")
                Plate {
                    Button {
                        look.chosen = look.blog
                    } label: {
                        Text("Start again from the blog's colours")
                            .font(.ui(15))
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.top, 14)
            }
        }
        // In its own colours the section brings its ground with it: the
        // page under it is in the ones that cannot be read.
        .padding(ground == nil ? 0 : 12)
        .background(ground?.paper ?? Color.clear, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .padding(.top, ground == nil ? 0 : 14)
        .tint(ground?.accent ?? Theme.accent)
        .environment(\.ground, ground)
        // Half the screen's height, so the app is seen changing over it.
        .sheet(item: $picking) { pick in
            ColourPicker(value: well(pick), title: title(pick))
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        }
    }

    private func name(_ choice: Colouring) -> LocalizedStringKey {
        switch choice {
        case .blog: "As the blog has them"
        case .own: "The default scheme"
        case .chosen: "Your own"
        }
    }

    private func name(_ part: Shades.Part) -> String {
        switch part {
        case .bg: String(localized: "Background")
        case .text: String(localized: "Text")
        case .metaText: String(localized: "Muted text")
        case .border: String(localized: "Dividers")
        case .accent: String(localized: "Accent")
        }
    }

    /// One well of the table: which colour, of which scheme.
    private struct Pick: Identifiable, Hashable {
        let part: Shades.Part
        let dark: Bool
        var id: Self { self }
    }

    /// What a well is called, where it has to say so by itself: "Text, Dark".
    private func title(_ pick: Pick) -> String {
        name(pick.part) + ", " + (pick.dark ? String(localized: "Dark") : String(localized: "Light"))
    }

    private func well(_ pick: Pick) -> Binding<UInt32> {
        let scheme: WritableKeyPath<Colours, Shades> = pick.dark ? \.dark : \.light
        return Binding(get: { (look.chosen ?? look.worn)[keyPath: scheme][keyPath: pick.part.path] },
                       set: { value in
                           var colours = look.chosen ?? look.worn
                           colours[keyPath: scheme][keyPath: pick.part.path] = value
                           look.chosen = colours
                       })
    }
}

/// One colour, shown: a swatch that is a key. The system's own well is a
/// ring of every colour around the chosen one; ten of those in a table
/// say less than ten plain swatches.
struct ColourWell: View {
    let value: UInt32
    /// The colour of the swatch's edge: the muted one of its surroundings.
    let edge: Color
    let label: Text
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ColourPicker.colour(value))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(edge.opacity(0.55), lineWidth: 1))
                .frame(width: 52, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// The system's colour picker, for one colour: every move in it is the
/// colour at once, so the app is seen changing behind it.
struct ColourPicker: UIViewControllerRepresentable {
    @Binding var value: UInt32
    let title: String

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.title = title
        picker.selectedColor = UIColor(Self.colour(value))
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.value = $value
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var value: Binding<UInt32>

        init(value: Binding<UInt32>) { self.value = value }

        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            value.wrappedValue = ColourPicker.number(color)
        }
    }

    static func colour(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }

    /// A picked colour as the number a palette writes: in sRGB, each part
    /// held between black and white.
    static func number(_ colour: UIColor) -> UInt32 {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        func part(_ c: CGFloat) -> UInt32 { UInt32((min(max(c, 0), 1) * 255).rounded()) }
        return part(r) << 16 | part(g) << 8 | part(b)
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
