#if DEBUG
import SwiftUI

/// Debug-only Streaming Lab (issue #234): replays a canned markdown fixture
/// through the real display pipeline (`MarkdownRenderer(content:isStreaming:)`
/// → chunked streaming view → fade window) while the fade knobs are tuned
/// live via `StreamingTextFadeLab`. No server, deterministic content.
struct StreamingLabView: View {
    @State private var displayedContent = ""
    @State private var isStreaming = false
    @State private var replayID = 0
    @State private var followsTail = true
    // Surfaced here because the user setting silently disables every fade
    // knob below — invisible state the lab must make visible (see the #232
    // textSelection dead-cascade hunt).
    @AppStorage(StreamedTextAnimationSettings.isEnabledKey) private var isStreamedTextAnimationEnabled = true

    /// A/B experiment modes (no production impact — lab only). Isolates which
    /// variable actually produces the "smooth" feel:
    ///   .currentHermes — glyph fade ON, geometry growth NOT animated (prod parity)
    ///   .fadeAndGeometry — glyph fade ON + animated height growth
    ///   .geometryOnly — glyph fade OFF + animated height growth
    enum LabMode: String, CaseIterable, Identifiable {
        case currentHermes = "A · current Hermes (fade, no geometry)"
        case fadeAndGeometry = "B · fade + smooth geometry"
        case geometryOnly = "C · no fade + smooth geometry"
        var id: String { rawValue }
    }
    @State private var labMode: LabMode = .currentHermes

    @State private var wordsPerSecond = StreamingLabReplay.defaultWordsPerSecond
    @State private var fadeDuration = StreamingTextFadeLab.shared.fadeDuration
    @State private var glyphStagger = StreamingTextFadeLab.shared.glyphStagger
    @State private var maxStampLead = StreamingTextFadeLab.shared.maxStampLead

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    Divider()
                    transcript
                    Color.clear
                        .frame(height: 1)
                        .id(Self.tailAnchorID)
                }
                .padding(16)
            }
            .onChange(of: displayedContent) { _, _ in
                guard followsTail else { return }
                // Scroll-follow axis: mode A scrolls instantly (prod parity);
                // modes B and C scroll with an ease-out so the jump is
                // interpolated rather than discrete.
                if let geo = geometryTransition {
                    withAnimation(geo) {
                        proxy.scrollTo(Self.tailAnchorID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(Self.tailAnchorID, anchor: .bottom)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Streaming Lab")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: replayID) {
            await replayFixture()
        }
    }

    private static let tailAnchorID = "streaming-lab-tail"

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("A/B mode", selection: $labMode) {
                ForEach(LabMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: labMode) { _, _ in
                replayID += 1
            }

            HStack(spacing: 12) {
                Button {
                    replayID += 1
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    StreamingTextFadeLab.shared.reset()
                    fadeDuration = StreamingTextFadeDefaults.Baseline.fadeDuration
                    glyphStagger = StreamingTextFadeDefaults.Baseline.glyphStagger
                    maxStampLead = StreamingTextFadeDefaults.Baseline.maxStampLead
                } label: {
                    Label("Reset Knobs", systemImage: "slider.horizontal.2.arrow.trianglehead.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Toggle("Follow tail while streaming", isOn: $followsTail)
                .font(.subheadline)

            Toggle("Streamed text animation (user setting)", isOn: $isStreamedTextAnimationEnabled)
                .font(.subheadline)

            if !isStreamedTextAnimationEnabled {
                Text("Animation is off — the knobs below have no visible effect until it's re-enabled.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            knobSlider(
                title: "Stream speed",
                value: $wordsPerSecond,
                range: StreamingLabReplay.minWordsPerSecond...StreamingLabReplay.maxWordsPerSecond,
                display: String(format: "%.0f words/s", wordsPerSecond)
            )

            knobSlider(
                title: "fadeDuration",
                value: $fadeDuration,
                range: 0.05...1.0,
                display: String(format: "%.2f s", fadeDuration)
            )
            .onChange(of: fadeDuration) { _, newValue in
                StreamingTextFadeLab.shared.fadeDuration = newValue
            }

            knobSlider(
                title: "glyphStagger",
                value: $glyphStagger,
                range: 0...0.06,
                display: String(format: "%.0f ms", glyphStagger * 1000)
            )
            .onChange(of: glyphStagger) { _, newValue in
                StreamingTextFadeLab.shared.glyphStagger = newValue
            }

            knobSlider(
                title: "maxStampLead",
                value: $maxStampLead,
                range: 0...1.5,
                display: String(format: "%.2f s", maxStampLead)
            )
            .onChange(of: maxStampLead) { _, newValue in
                StreamingTextFadeLab.shared.maxStampLead = newValue
            }

            knobReadout
        }
    }

    private func knobSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
        }
    }

    /// Paste-ready values for `StreamingTextFadeDefaults` once a feel is
    /// chosen (the lab never persists anything across launches).
    private var knobReadout: some View {
        Text(
            """
            static let fadeDuration: TimeInterval = \(String(format: "%.3f", fadeDuration))
            static let glyphStagger: TimeInterval = \(String(format: "%.3f", glyphStagger))
            static let maxStampLead: TimeInterval = \(String(format: "%.3f", maxStampLead))
            """
        )
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var transcript: some View {
        MarkdownRenderer(
            content: displayedContent,
            isStreaming: isStreaming,
            forceFadeDisabled: glyphFadeEnabledForMode ? nil : true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
            // Geometry transition axis: animate the *height growth* of the text
            // block between word reveals. This is the variable being isolated —
            // current production Hermes does NOT animate this (height jumps
            // discretely each re-layout), which is the leading hypothesis for
            // the "вырвиглаз" feel. Modes B and C enable it.
            .animation(geometryTransition, value: displayedContent)
    }

    /// The geometry-growth animation, or nil in mode A (current Hermes parity).
    private var geometryTransition: Animation? {
        switch labMode {
        case .currentHermes:
            return nil
        case .fadeAndGeometry, .geometryOnly:
            return .easeOut(duration: 0.12)
        }
    }

    /// Whether glyph-level fade should be active for the current mode.
    /// Modes A and B fade; mode C (geometry-only) disables the glyph fade to
    /// isolate the geometry transition's contribution alone.
    private var glyphFadeEnabledForMode: Bool {
        switch labMode {
        case .currentHermes, .fadeAndGeometry:
            return true
        case .geometryOnly:
            return false
        }
    }

    /// Local word-cadence appender standing in for the server stream: reveals
    /// the fixture unit-by-unit at the production tick interval, with the
    /// speed slider scaling how many units each tick deposits.
    private func replayFixture() async {
        displayedContent = ""
        isStreaming = true

        let fixture = StreamingLabReplay.fixture
        let totalUnits = StreamingLabReplay.fixtureUnitCount
        var revealed = 0
        var carry = 0.0

        while revealed < totalUnits {
            try? await Task.sleep(for: .seconds(StreamingLabReplay.tickInterval))
            guard !Task.isCancelled else { return }

            (revealed, carry) = StreamingLabReplay.advance(
                revealed: revealed,
                carry: carry,
                wordsPerSecond: wordsPerSecond
            )
            revealed = min(revealed, totalUnits)
            displayedContent = StreamingLabReplay.prefix(of: fixture, unitCount: revealed)
        }

        // A cancelled replay must not flip the flag: on restart the new task
        // has already set `isStreaming = true` and this would end its fade.
        guard !Task.isCancelled else { return }
        isStreaming = false
    }
}

#Preview {
    NavigationStack {
        StreamingLabView()
    }
}
#endif
