import SwiftUI

struct RootView: View {
    @EnvironmentObject private var engine: HearEngine
    @State private var smoother = Smoother()
    @State private var showSettings = false

    @AppStorage("gain") private var gain = 9.0
    @AppStorage("denoise") private var denoise = 0.6
    @AppStorage("clarity") private var clarity = 0.6
    @AppStorage("auto") private var auto = true

    private var tuning: Tuning {
        Tuning(gain: gain, denoise: denoise, clarity: clarity, auto: auto)
    }

    private var running: Bool { engine.state == .running }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Aura(smoother: smoother, running: running)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        if let n = engine.notice {
                            NoticeCard(notice: n)
                                .padding(.top, 14)
                                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(0.92)))
                        }
                        Spacer(minLength: 12)
                        Hero(engine: engine, smoother: smoother, side: heroSide(proxy.size.height))
                        status
                        Spacer(minLength: 16)
                        Panel(gain: $gain, denoise: $denoise, clarity: $clarity, auto: $auto, tuning: tuning)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .animation(.bouncy(duration: 0.55), value: engine.notice)
        .onChange(of: tuning, initial: true) { _, t in engine.apply(t) }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // Kolo ma sie zmiescic razem z panelem nawet na mniejszych iPhone'ach
    private func heroSide(_ height: CGFloat) -> CGFloat {
        min(340, max(230, height * 0.36))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("HearNow").spaced(.largeTitle, .bold)
                RouteChip(route: engine.route)
            }
            Spacer(minLength: 8)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ustawienia")
        }
        .padding(.top, 8)
    }

    private var status: some View {
        let title: String
        let sub: String
        switch engine.state {
        case .idle:
            title = "Dotknij, aby słuchać"
            sub = engine.route.ok ? "Głos z otoczenia trafi prosto do słuchawek" : "Najpierw podłącz słuchawki"
        case .starting:
            title = "Włączam…"
            sub = "Chwila, sprawdzam mikrofon"
        case .running:
            title = "Słucham"
            sub = "Działa też po zablokowaniu ekranu"
        }
        return VStack(spacing: 6) {
            Text(title)
                .spaced(.title2, .bold)
                .id(title)
                .transition(.blurReplace)
            Text(sub)
                .spaced(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .id(sub)
                .transition(.blurReplace)
        }
        .animation(.smooth(duration: 0.45), value: engine.state)
        .animation(.smooth(duration: 0.45), value: engine.route)
        .padding(.top, 4)
    }
}

// Co jest podlaczone. Pomaranczowe, gdy nic.
struct RouteChip: View {
    let route: HearRoute

    var body: some View {
        Label {
            Text(route.name).spaced(.subheadline, .semibold).lineLimit(1)
        } icon: {
            Image(systemName: route.symbol)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(route.ok ? nil : Color.orange.opacity(0.45)), in: .capsule)
        .frame(maxWidth: 260, alignment: .leading)
        .animation(.smooth(duration: 0.4), value: route)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(route.ok ? "Słuchawki: \(route.name)" : "Brak słuchawek")
    }
}

// Komunikat, ktory wyjezdza z gory (brak sluchawek, brak zgody na mikrofon, przerwanie)
struct NoticeCard: View {
    @EnvironmentObject private var engine: HearEngine
    let notice: Notice

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: notice.symbol)
                .font(.system(size: 26, weight: .semibold))
                .symbolEffect(.bounce, value: notice)
            Text(notice.text)
                .spaced(.subheadline, .semibold)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if notice.action == .settings {
                Button {
                    engine.openSettings()
                } label: {
                    Text("Ustawienia").spaced(.subheadline, .bold)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
            }
            Button {
                engine.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij komunikat")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular.tint(Color.orange.opacity(0.25)), in: .rect(cornerRadius: 28))
    }
}

// ------------------------------------------------------------------ panel ze suwakami

struct Panel: View {
    @Binding var gain: Double
    @Binding var denoise: Double
    @Binding var clarity: Double
    @Binding var auto: Bool
    let tuning: Tuning

    @Namespace private var ns

    var body: some View {
        VStack(spacing: 20) {
            presets

            VStack(spacing: 16) {
                KnobRow(symbol: "speaker.wave.3.fill", title: "Głośność",
                        value: $gain, range: 0...24, step: 1, ticks: 1) { "+\(Int($0)) dB" }
                KnobRow(symbol: "wind", title: "Odszumianie",
                        value: $denoise, range: 0...1, step: nil, ticks: 20) { "\(Int($0 * 100))%" }
                KnobRow(symbol: "person.wave.2.fill", title: "Wyrazistość głosu",
                        value: $clarity, range: 0...1, step: nil, ticks: 20) { "\(Int($0 * 100))%" }
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 36))
    }

    // Zaznaczenie to jedna szklana plytka, ktora przeplywa miedzy przyciskami
    private var presets: some View {
        let current = Preset.matching(tuning)
        return GlassEffectContainer(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Preset.allCases) { p in
                    Button {
                        withAnimation(.bouncy(duration: 0.55)) {
                            gain = p.tuning.gain
                            denoise = p.tuning.denoise
                            clarity = p.tuning.clarity
                            auto = p.tuning.auto
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .symbolEffect(.bounce, value: current == p)
                            Text(p.title).spaced(.caption, .semibold).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(current == p ? Color.white : Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(.rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .background {
                        if current == p {
                            Color.clear
                                .glassEffect(.regular.tint(Color.cyan.opacity(0.40)).interactive(), in: .rect(cornerRadius: 22))
                                .glassEffectID("selected", in: ns)
                        }
                    }
                    .accessibilityLabel(p.title)
                    .accessibilityAddTraits(current == p ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: current)
    }
}

struct KnobRow: View {
    let symbol: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let ticks: Double
    let format: (Double) -> String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                Text(title).spaced(.subheadline, .semibold)
                Spacer(minLength: 8)
                Text(format(value))
                    .spaced(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy(duration: 0.2), value: value)
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step) { Text(title) }
                } else {
                    Slider(value: $value, in: range) { Text(title) }
                }
            }
            .accessibilityValue(format(value))
        }
        .sensoryFeedback(.selection, trigger: Int((value * ticks).rounded()))
    }
}
