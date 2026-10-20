import SwiftUI

/// The Me tab: appearance, field-test tools, and credits. Profile and life list come later.
struct MeScreen: View {
    @Bindable var listener: Listener
    @Binding var themeChoice: ThemeChoice

    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $themeChoice) {
                        ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Testing") {
                    NavigationLink("Field-test tools") { FieldTestView(listener: listener) }
                }

                Section("Credits") {
                    Text(Self.credits)
                        .font(.body(15))
                        .foregroundStyle(theme.chromeSoft)
                }
            }
            .font(.body(17))
            .scrollContentBackground(.hidden)
            .background(theme.chromeBackground.ignoresSafeArea())
            .navigationTitle("Me")
        }
    }

    private static let credits = """
        Bird identification by BirdNET (K. Lisa Yang Center for Conservation Bioacoustics, \
        Cornell Lab of Ornithology, and Chemnitz University of Technology), used under CC BY-NC-SA 4.0. \
        Species names from the eBird/Clements taxonomy. Fonts: IM Fell English, EB Garamond and \
        Caveat, under the SIL Open Font License.
        """
}
