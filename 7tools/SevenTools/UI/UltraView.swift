import SwiftUI

// Skaner ultradzwiekowy (dla zabawy). Dwa tryby:
//  - Sonar: wysyla cichy pisk 17 do 21 kHz i slucha ech. Pokazuje orientacyjna odleglosc do najblizszych rzeczy.
//  - Detektor: pokazuje, czy w poblizu cos wydaje wysokie tony (14 do 24 kHz).
// Telefon nie ma prawdziwego ultradzwieku, mikrofon i glosnik sa na to za skromne. Wyniki sa orientacyjne.

struct Blip: Identifiable {
    let id = UUID()
    let meters: Double
    let strength: Float
    let angle: Double
    let born: TimeInterval
}

@MainActor
final class UltraModel: ObservableObject {
    enum Mode: Int { case sonar, detector }

    @Published var mode: Mode = .sonar
    @Published private(set) var running = false
    @Published private(set) var blips: [Blip] = []
    @Published private(set) var nearest: Double?
    @Published private(set) var bands = [Float](repeating: -100, count: 20)
    @Published private(set) var peakHz: Float?
    @Published private(set) var active = false
    @Published private(set) var history: [[Float]] = []
    @Published var volume = 0.35

    let hub: AudioHub
    private let sonar = SonarEngine()
    private let fft = FFT(2048)
    private var task: Task<Void, Never>?
    private var recentNearest: [Double] = []

    init(hub: AudioHub) { self.hub = hub }

    static func sweepAngle(_ t: TimeInterval) -> Double { (t * 1.4).truncatingRemainder(dividingBy: 2 * .pi) }

    func start() async {
        guard !running else { return }
        guard await hub.useMic("ultra") else { return }
        running = true
        blips = []
        history = []
        nearest = nil
        recentNearest = []
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.mode == .sonar {
                    await self.sonarStep()
                } else {
                    self.detectorStep()
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if running { hub.releaseMic("ultra") }
        running = false
        hub.mixer.stop(tag: 9900)
    }

    private func sonarStep() async {
        hub.mixer.play(sonar.chirp, tag: 9900, gain: Float(volume), attack: 0.0005, release: 0.002)
        try? await Task.sleep(for: .milliseconds(110))
        let window = hub.mixer.recentInput(8192)
        let res = sonar.analyze(window)
        let now = Date.timeIntervalSinceReferenceDate
        let angle = Self.sweepAngle(now)
        withAnimation(.easeOut(duration: 0.2)) {
            for e in res.echoes {
                blips.append(Blip(meters: e.meters, strength: e.strength, angle: angle + Double.random(in: -0.15...0.15), born: now))
            }
            blips.removeAll { now - $0.born > 4 }
            recentNearest.append(res.echoes.first?.meters ?? -1)
            if recentNearest.count > 4 { recentNearest.removeFirst() }
            let seen = recentNearest.filter { $0 > 0 }
            nearest = seen.count >= 2 ? seen.min() : nil
        }
        try? await Task.sleep(for: .milliseconds(110))
    }

    private func detectorStep() {
        let x = hub.mixer.recentInput(2048)
        guard x.count >= 2048 else { return }
        let b = Ultra.bands(x, rate: 48000, count: 20, from: 14000, to: 24000, fft: fft)
        bands = b
        history.append(b)
        if history.count > 70 { history.removeFirst() }
        let sorted = b.sorted()
        let median = sorted[sorted.count / 2]
        if let best = b.indices.max(by: { b[$0] < b[$1] }), b[best] > median + 14, b[best] > -78 {
            peakHz = 14000 + 10000 * (Float(best) + 0.5) / 20
            active = true
        } else {
            peakHz = nil
            active = false
        }
    }
}

struct UltraView: View {
    @EnvironmentObject private var hub: AudioHub
    @StateObject private var model: UltraModel

    init(hub: AudioHub) { _model = StateObject(wrappedValue: UltraModel(hub: hub)) }

    var body: some View {
        Page("Skaner ultradźwiękowy", "Zabawa w skanowanie. Nie musi być dokładne") {
            VStack(spacing: 16) {
                Picker("Tryb", selection: $model.mode) {
                    Label("Sonar", systemImage: "dot.radiowaves.forward").tag(UltraModel.Mode.sonar)
                    Label("Detektor", systemImage: "waveform.path.ecg").tag(UltraModel.Mode.detector)
                }
                .pickerStyle(.segmented)
                .onChange(of: model.mode) { if model.running { model.stop(); Task { await model.start() } } }

                if model.mode == .sonar { sonarPanel } else { detectorPanel }

                Button {
                    if model.running { model.stop() } else { Task { await model.start() } }
                } label: {
                    Label(model.running ? "Stop" : "Skanuj", systemImage: model.running ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .spaced(.title3, .bold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .glassEffect(.regular.tint(model.running ? Color.red.opacity(0.5) : Color.cyan.opacity(0.5)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: model.running)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.mode == .sonar {
                            SliderRow(symbol: "speaker.wave.2.fill", title: "Głośność piszczenia", value: $model.volume, range: 0.1...0.8) { "\(Int($0 / 0.8 * 100))%" }
                            Text("Sonar nie wie, z której strony jest przedmiot. Kropka pokazuje tylko odległość. Najlepiej działa w pustym pokoju, z telefonem skierowanym na ścianę.")
                                .spaced(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Pokazuje wysokie tony 14 do 24 kHz, np. z odstraszaczy szkodników, czujek ruchu albo gwizdka na psa. Mikrofon telefonu słyszy je słabo, więc to wskazówka, nie pomiar.")
                                .spaced(.footnote).foregroundStyle(.secondary)
                        }
                        Text("Piski są wysokie i zwierzęta mogą je słyszeć. Nie włączaj sonaru tuż przy psie, kocie ani gryzoniu. Prawdziwego ultradźwięku (40 kHz i więcej) telefon nie ma.")
                            .spaced(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .onDisappear { model.stop() }
    }

    // ---------------------------------------------------------- sonar

    private var sonarPanel: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.running && model.blips.isEmpty)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in drawRadar(ctx, size, t) }
            }
            .frame(width: 300, height: 300)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(model.nearest.map { String(format: "%.1f m", $0) } ?? (model.running ? "Nic w zasięgu" : "–"))
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(model.nearest == nil ? Color.secondary : Theme.gold)
                    .contentTransition(.numericText())
                Text("najbliższy przedmiot (orientacyjnie)").spaced(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func drawRadar(_ ctx: GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = min(size.width, size.height) / 2 - 6
        for i in 1...4 {
            let rr = r * CGFloat(i) / 4
            var p = Path()
            p.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            ctx.stroke(p, with: .color(.green.opacity(0.28)), lineWidth: 1)
            ctx.draw(Text("\(i) m").font(.system(size: 9)).foregroundStyle(.green.opacity(0.6)), at: CGPoint(x: c.x + 4 + rr * 0.0, y: c.y - rr + 8), anchor: .leading)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
        ctx.stroke(cross, with: .color(.green.opacity(0.18)), lineWidth: 1)

        // przemiatana linia z poswiata za nia
        if model.running {
            let a = UltraModel.sweepAngle(t)
            for k in 0..<18 {
                let aa = a - Double(k) * 0.045
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(aa) * r, y: c.y + sin(aa) * r))
                ctx.stroke(p, with: .color(.green.opacity(0.5 * (1 - Double(k) / 18))), lineWidth: 3)
            }
        }
        // echa
        for b in model.blips {
            let age = t - b.born
            let fade = max(0, 1 - age / 4)
            let rr = min(1, b.meters / 4) * r
            let p = CGPoint(x: c.x + cos(b.angle) * rr, y: c.y + sin(b.angle) * rr)
            let s = 7 + CGFloat(b.strength) * 12
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)), with: .color(Theme.gold.opacity(fade)))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2)), with: .color(Theme.gold.opacity(fade * 0.4)), lineWidth: 1.5)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.white))
    }

    // ---------------------------------------------------------- detektor

    private var detectorPanel: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(model.peakHz.map { String(format: "%.1f kHz", $0 / 1000) } ?? (model.running ? "Cisza" : "–"))
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(model.active ? Color.green : Color.secondary)
                    .contentTransition(.numericText())
                Text(model.active ? "Wykryto wysoki ton" : "Brak wysokich tonów").spaced(.footnote).foregroundStyle(.secondary)
            }

            Canvas { ctx, size in
                let n = model.bands.count
                let bw = size.width / CGFloat(n)
                for i in 0..<n {
                    let v = CGFloat(max(0, min(1, (model.bands[i] + 100) / 50)))
                    let h = max(2, v * size.height)
                    let r = CGRect(x: CGFloat(i) * bw + 1.5, y: size.height - h, width: bw - 3, height: h)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color(hue: 0.55 - 0.2 * Double(v), saturation: 0.7, brightness: 1)))
                }
            }
            .frame(height: 120)
            .accessibilityHidden(true)

            // wodospad: jak zmienialo sie widmo w ostatnich sekundach
            Canvas { ctx, size in
                let cols = model.history
                guard !cols.isEmpty else { return }
                let cw = size.width / 70
                let n = cols[0].count
                let ch = size.height / CGFloat(n)
                for (x, col) in cols.enumerated() {
                    for (y, v) in col.enumerated() {
                        let a = Double(max(0, min(1, (v + 95) / 45)))
                        ctx.fill(Path(CGRect(x: CGFloat(x) * cw, y: size.height - CGFloat(y + 1) * ch, width: cw + 0.5, height: ch + 0.5)),
                                 with: .color(Color(hue: 0.62 - 0.5 * a, saturation: 0.8, brightness: 0.15 + 0.85 * a)))
                    }
                }
            }
            .frame(height: 130)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .accessibilityHidden(true)

            HStack {
                Text("14 kHz").spaced(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("19 kHz").spaced(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("24 kHz").spaced(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
