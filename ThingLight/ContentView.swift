import SwiftUI

struct ContentView: View {
    @State private var debugMode: DebugMode = .composite
    @State private var settings = VolumetricSettings.default
    @State private var renderText = "THE\nTHING"
    @State private var showControls = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            VolumetricMetalView(debugMode: $debugMode, settings: $settings, renderText: $renderText)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ThingLight")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Button("Reset") {
                        settings = .cinematic
                        debugMode = .composite
                        renderText = "THE\nTHING"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(showControls ? "Hide" : "Show") {
                        showControls.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if showControls {
                    Text("Render Text")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    TextField("Use \\n for line breaks", text: $renderText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)

                    Picker("Debug", selection: $debugMode) {
                        ForEach(DebugMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Adaptive Samples", isOn: $settings.adaptiveSampling)
                        .tint(.blue)
                    Toggle("Auto Compact", isOn: $settings.compactModeEnabled)
                        .tint(.blue)
                    sliderRow("Compact Edge", value: $settings.compactShortEdgeThreshold, in: 96...360)

                    intSliderRow("Base Samples", value: $settings.baseSampleCount, in: 32...180)
                    sliderRow("Downsample", value: $settings.downsampleScale, in: 0.25...1.0)
                    sliderRow("Exposure", value: $settings.exposure, in: 0.2...1.8)
                    sliderRow("Decay", value: $settings.decay, in: 0.88...0.995)
                    sliderRow("Density", value: $settings.density, in: 0.2...1.4)
                    sliderRow("Weight", value: $settings.weight, in: 0.05...1.0)
                    sliderRow("Anim Speed", value: $settings.animationSpeed, in: 0.0...4.0)
                    sliderRow("Anim Amount", value: $settings.animationAmount, in: 0.0...1.0)
                    sliderRow("Noise", value: $settings.noiseAmount, in: 0.0...0.25)
                    sliderRow("Text Intensity", value: $settings.textIntensity, in: 0.5...2.0)
                    sliderRow("Halo Intensity", value: $settings.haloIntensity, in: 0.0...2.4)
                    sliderRow("Background", value: $settings.backgroundLift, in: 0.4...1.6)
                    sliderRow("Light X", value: $settings.lightBaseX, in: 0.2...0.8)
                    sliderRow("Light Y", value: $settings.lightBaseY, in: 0.2...0.8)
                    sliderRow("Drift X", value: $settings.lightDriftX, in: 0.0...0.14)
                    sliderRow("Drift Y", value: $settings.lightDriftY, in: 0.0...0.14)
                }
            }
            .padding(14)
            .frame(width: 350)
            .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .padding(16)
        }
        .background(Color.black)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(3)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            Slider(value: value, in: range)
                .tint(.blue)
        }
    }

    private func intSliderRow(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        let asDouble = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = Int($0.rounded()) }
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text("\(value.wrappedValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            Slider(value: asDouble, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .tint(.blue)
        }
    }
}

#Preview {
    ContentView()
}
