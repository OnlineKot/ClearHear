import SwiftUI

// Dawne HearNow: mikrofon telefonu w sluchawkach, z odszumianiem i podbiciem glosu.

struct ListenTuning: Equatable {
    var gain: Double
    var denoise: Double
    var clarity: Double
}

enum ListenPreset: String, CaseIterable, Identifiable {
    case talk, crowd, far, quiet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk: return "Rozmowa"
        case .crowd: return "Tłum"
        case .far: return "Z daleka"
        case .quiet: return "Cisza"
        }
    }

    var symbol: String {
        switch self {
        case .talk: return "bubble.left.and.bubble.right.fill"
        case .crowd: return "person.3.fill"
        case .far: return "binoculars.fill"
        case .quiet: return "moon.fill"
        }
    }

    var tuning: ListenTuning {
        switch self {
        case .talk: return ListenTuning(gain: 9, denoise: 0.6, clarity: 0.6)
        case .crowd: return ListenTuning(gain: 10, denoise: 0.9, clarity: 0.8)
        case .far: return ListenTuning(gain: 14, denoise: 0.7, clarity: 0.7)
        case .quiet: return ListenTuning(gain: 8, denoise: 0.35, clarity: 0.4)
        }
    }

    static func matching(_ t: ListenTuning) -> ListenPreset? { allCases.first { $0.tuning == t } }
}

// Wygladzone widmo do rysowania (rosnie szybko, opada wolno)
final class ListenSmoother {
    var voice = [Float](repeating: 0, count: Meters.bands)
    var raw = [Float](repeating: 0, count: Meters.bands)
    var level: Float = 0
    private var last: TimeInterval = 0

    func update(_ m: Meters, now: TimeInterval) {
        guard now != last else { return }
        let dt = Float(min(0.1, max(0.001, now - last)))
        last = now
        let up = 1 - expf(-dt * 30)
        let down = 1 - expf(-dt * 7)
        for i in 0..<Meters.bands {
            let v = m.voice[i], r = m.raw[i]
            voice[i] += (v - voice[i]) * (v > voice[i] ? up : down)
            raw[i] += (r - raw[i]) * (r > raw[i] ? up : down)
        }
        let l = min(1, m.outLevel * 6)
        level += (l - level) * (l > level ? up : down)
    }
}

struct ListenView: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var smoother = ListenSmoother()
    @State private var env: Surroundings?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var ns

    @AppStorage("listen.gain") private var gain = 9.0
    @AppStorage("listen.denoise") private var denoise = 0.6
    @AppStorage("listen.clarity") private var clarity = 0.6
    @AppStorage("listen.autoLevel") private var autoLevel = true
    @AppStorage("listen.autoEnv") private var autoEnv = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var tuning: ListenTuning { ListenTuning(gain: gain, denoise: denoise, clarity: clarity) }

    var body: some View {
        VStack(spacing: 18) {
            orb
            Text(hub.listening ? "Słucham" : "Dotknij, aby słuchać")
                .spaced(.title2, .bold)
                .contentTransition(.interpolate)
            Text(subtitle)
                .spaced(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            presets
            sliders
        }
        .onChange(of: tuning, initial: true) { _, _ in push() }
        .onChange(of: autoLevel, initial: true) { _, _ in push() }
        .onReceive(tick) { _ in detect() }
        .animation(.smooth(duration: 0.4), value: hub.listening)
    }

    private var subtitle: String {
        if !hub.headphones { return "Najpierw podłącz słuchawki" }
        if let env, autoEnv, hub.listening { return "Wykryto: \(env.title.lowercased())" }
        return "Głos z otoczenia trafi prosto do słuchawek, wyraźniejszy i bez szumu"
    }

    private func push() {
        let k = hub.mixer.listenKnobs
        k.gainDB = Float(gain)
        k.denoise = Float(denoise)
        k.clarity = Float(clarity)
        k.auto = autoLevel
    }

    // Co sekunde patrzymy na poziom wejscia i, jesli wlaczone, dobieramy ustawienia do otoczenia
    private func detect() {
        guard hub.listening else { return }
        let rms = hub.mixer.listenMeters.inLevel
        let dbfs = 20 * log10f(max(rms, 1e-5))
        let e = Surroundings.classify(dbfs: dbfs, previous: env)
        if e != env { env = e }
        guard autoEnv else { return }
        let p: ListenPreset = e == .quiet ? .quiet : (e == .talk ? .talk : .crowd)
        if ListenPreset.matching(tuning) != p {
            withAnimation(.smooth(duration: 0.8)) {
                gain = p.tuning.gain
                denoise = p.tuning.denoise
                clarity = p.tuning.clarity
            }
        }
    }

    // ---------------------------------------------------------- srodek

    private var orb: some View {
        let side: CGFloat = 280
        return TimelineView(.animation(minimumInterval: hub.listening ? nil : 1.0 / 20, paused: reduce && !hub.listening)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let _ = smoother.update(hub.mixer.listenMeters, now: t)
            let level = CGFloat(smoother.level)

            ZStack {
                Canvas { ctx, size in drawRing(ctx, size, t) }
                    .accessibilityHidden(true)

                Button {
                    Task { await hub.toggleListen() }
                } label: {
                    Image(systemName: hub.listening ? "waveform" : "ear.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: hub.listening && !reduce)
                        .frame(width: side * 0.58, height: side * 0.58)
                        .glassEffect(.regular.tint(hub.listening ? Color.cyan.opacity(0.3) : nil).interactive(), in: .circle)
                        .scaleEffect(hub.listening && !reduce ? 1 + 0.05 * level : 1)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(trigger: hub.listening) { _, now in
                    now ? SensoryFeedback.success : SensoryFeedback.impact(flexibility: .soft)
                }
                .accessibilityLabel(hub.listening ? "Zatrzymaj słuchanie" : "Zacznij słuchać")
            }
        }
        .frame(width: side, height: side)
    }

    private func drawRing(_ context: GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        var ctx = context
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r0 = size.width * 0.34
        let maxLen = size.width * 0.17
        let live = hub.listening
        var glow = Path(), haze = Path()
        var crisp: [(Path, Color)] = []

        for j in 0..<64 {
            let b = j < 32 ? j : 63 - j
            let ang = Double(j) / 64 * 2 * .pi - .pi / 2
            let dir = CGPoint(x: cos(ang), y: sin(ang))
            func line(_ len: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: c.x + dir.x * r0, y: c.y + dir.y * r0))
                p.addLine(to: CGPoint(x: c.x + dir.x * (r0 + len), y: c.y + dir.y * (r0 + len)))
                return p
            }
            if live {
                let v = CGFloat(smoother.voice[b]), r = CGFloat(smoother.raw[b])
                haze.addPath(line(3 + r * maxLen))
                let l = line(3 + v * maxLen)
                glow.addPath(l)
                crisp.append((l, Color(hue: 0.5 + 0.3 * Double(b) / 31, saturation: 0.55, brightness: 1)))
            } else {
                let wave = reduce ? 0.5 : 0.5 + 0.5 * sin(t * 1.4 - Double(j) * 0.22)
                crisp.append((line(3 + 3 * CGFloat(wave)), Color.white.opacity(0.22 + 0.2 * wave)))
            }
        }
        if live {
            ctx.stroke(haze, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 7))
                l.stroke(glow, with: .color(Color.cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        for (p, color) in crisp {
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
    }

    // ---------------------------------------------------------- ustawienia

    private var presets: some View {
        let current = autoEnv ? nil : ListenPreset.matching(tuning)
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.bouncy(duration: 0.5)) { autoEnv.toggle() }
                } label: {
                    chipLabel("Auto", "sparkles", selected: autoEnv)
                }
                .buttonStyle(.plain)
                .background {
                    if autoEnv {
                        Color.clear.glassEffect(.regular.tint(Theme.gold.opacity(0.55)).interactive(), in: .rect(cornerRadius: 20))
                            .glassEffectID("sel", in: ns)
                    }
                }
                ForEach(ListenPreset.allCases) { p in
                    Button {
                        withAnimation(.bouncy(duration: 0.5)) {
                            autoEnv = false
                            gain = p.tuning.gain
                            denoise = p.tuning.denoise
                            clarity = p.tuning.clarity
                        }
                    } label: {
                        chipLabel(p.title, p.symbol, selected: current == p)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if current == p {
                            Color.clear.glassEffect(.regular.tint(Color.cyan.opacity(0.4)).interactive(), in: .rect(cornerRadius: 20))
                                .glassEffectID("sel", in: ns)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: current?.rawValue ?? (autoEnv ? "auto" : "own"))
    }

    private func chipLabel(_ title: String, _ symbol: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(title).spaced(.caption2, .semibold).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.65))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentShape(.rect(cornerRadius: 20))
    }

    private var sliders: some View {
        Card {
            VStack(spacing: 14) {
                SliderRow(symbol: "speaker.wave.3.fill", title: "Głośność", value: $gain, range: 0...24, step: 1) { "+\(Int($0)) dB" }
                SliderRow(symbol: "wind", title: "Odszumianie", value: $denoise, range: 0...1) { "\(Int($0 * 100))%" }
                SliderRow(symbol: "person.wave.2.fill", title: "Wyrazistość głosu", value: $clarity, range: 0...1) { "\(Int($0 * 100))%" }
                Toggle(isOn: $autoLevel) { Label("Wyrównuj głośność (szept i krzyk wychodzą podobnie)", systemImage: "slider.horizontal.below.rectangle") }
                    .spaced(.footnote, .semibold)
                Text("Głośność ustawia docelowy poziom, a nie samo wzmocnienie. Mikrofon przy ustach zawsze jest głośniejszy niż rozmówca z daleka, więc zacznij od cichej głośności w telefonie.")
                    .spaced(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
