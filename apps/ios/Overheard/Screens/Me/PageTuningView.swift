#if DEBUG
    import OverheardKit
    import SwiftUI
    import UIKit

    /// Try journal-page settings live (Debug builds only): a sample page at the top, sliders
    /// below. Changes apply to every page in the app; "Copy as code" gives the Swift to paste
    /// into `PageStyle.standard` once it looks right.
    struct PageTuningView: View {
        @Bindable var tuning: PageTuning
        let catalog: SpeciesCatalog?

        @State private var arrangement = 0
        @State private var copied = false

        var body: some View {
            VStack(spacing: 0) {
                preview
                controls
            }
            .navigationTitle("Page tuning")
            .navigationBarTitleDisplayMode(.inline)
        }

        // MARK: - Sample page

        private var preview: some View {
            JournalPage(
                seed: "tuning-\(arrangement)",
                dateLine: Formatting.pageDate(.now),
                birds: sampleBirds,
                emptyNote: "No sample birds (the species catalog didn't load)",
                isLive: true
            )
            .frame(height: 380)
            .padding(12)
        }

        private var sampleBirds: [PageBird] {
            guard let catalog else { return [] }
            let walk = DemoWalk(catalog: catalog)
            return PageBird.onPage(birds: walk.birds, pending: walk.pending)
        }

        // MARK: - Controls

        private var controls: some View {
            Form {
                Section {
                    Button("Try another arrangement") { arrangement += 1 }
                    Button(copied ? "Copied" : "Copy as code") { copyCode() }
                    Button("Reset to standard", role: .destructive) { tuning.reset() }
                        .disabled(tuning.isStandard)
                }

                Section("Size") {
                    TuningSlider(
                        "Bird heard once", value: $tuning.style.smallestBirdFraction, in: 0.1...0.8, format: .fraction)
                    TuningStepper("Full size at calls", value: $tuning.style.fullSizeAtCalls, in: 2...20)
                    TuningSlider("Largest bird", value: $tuning.style.largestBird, in: 150...360, format: .points)
                    TuningSlider(
                        "…or of page width", value: $tuning.style.largestBirdPageFraction, in: 0.4...0.9,
                        format: .fraction)
                    TuningSlider("Smallest bird", value: $tuning.style.smallestBird, in: 40...160, format: .points)
                    TuningSlider("Grow to fill page", value: $tuning.style.fillScale, in: 1...2.5, format: .times)
                }

                Section("Spacing and tilt") {
                    TuningSlider("Tuck into margins", value: $tuning.style.nestle, in: 0...40, format: .points)
                    TuningSlider("Largest tilt", value: $tuning.style.maxTilt, in: 0...12, format: .degrees)
                }

                Section("Spread") {
                    TuningSlider("First bird, across", value: $tuning.style.firstSpotX, in: 0...1, format: .fraction)
                    TuningSlider("First bird, down", value: $tuning.style.firstSpotY, in: 0...0.6, format: .fraction)
                    TuningSlider("Band, left", value: $tuning.style.spreadLeft, in: 0...0.5, format: .fraction)
                    TuningSlider("Band, right", value: $tuning.style.spreadRight, in: 0.5...1, format: .fraction)
                    TuningSlider("Band, top", value: $tuning.style.spreadTop, in: 0...0.5, format: .fraction)
                    TuningSlider("Band, bottom", value: $tuning.style.spreadBottom, in: 0.5...1, format: .fraction)
                    TuningSlider("Random nudge", value: $tuning.style.nudge, in: 0...0.3, format: .fraction)
                }

                Section("Names") {
                    TuningSlider("Handwriting size", value: $tuning.style.nameFontSize, in: 12...28, format: .points)
                    TuningSlider("Stays for", value: $tuning.style.nameShowsFor, in: 1...10, format: .seconds)
                    Toggle("New birds show their name", isOn: $tuning.style.introducesNewBirds)
                }

                Section("Layout effort") {
                    TuningStepper("Arrangements per size", value: $tuning.style.arrangementsPerSize, in: 1...8)
                    TuningSlider("Search step", value: $tuning.style.searchStep, in: 4...16, format: .points)
                }
            }
        }

        private func copyCode() {
            UIPasteboard.general.string = tuning.asCode
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
    }

    // MARK: - Controls

    /// A labeled slider with its value shown in the unit it's measured in.
    private struct TuningSlider: View {
        enum Format {
            case points, fraction, times, degrees, seconds

            func text(_ value: Double) -> String {
                switch self {
                case .points: String(format: "%.0f pt", value)
                case .fraction: String(format: "%.2f", value)
                case .times: String(format: "%.2f×", value)
                case .degrees: String(format: "%.1f°", value)
                case .seconds: String(format: "%.1f s", value)
                }
            }
        }

        let title: String
        @Binding var value: Double
        let range: ClosedRange<Double>
        let format: Format

        init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: Format) {
            self.title = title
            self._value = value
            self.range = range
            self.format = format
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent(title, value: format.text(value)).monospacedDigit()
                Slider(value: $value, in: range)
            }
        }
    }

    /// A labeled stepper for whole-number settings.
    private struct TuningStepper: View {
        let title: String
        @Binding var value: Int
        let range: ClosedRange<Int>

        init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) {
            self.title = title
            self._value = value
            self.range = range
        }

        var body: some View {
            Stepper("\(title): \(value)", value: $value, in: range).monospacedDigit()
        }
    }
#endif
