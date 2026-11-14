import SwiftUI
import AVFoundation

struct ToolsView: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var path: [Tool] = []
    @State private var showStage = false

    enum Tool: String, Hashable, CaseIterable, Identifiable {
        case tuner, tone, meter, morse, clap, talk, ultra
        case whereAmI, stage, gestures, level
        case strobe, dice, counter, convert, qr, screen, mirror, send
        case ikea
        case pranks, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tuner: return "Stroik"
            case .tone: return "Generator tonów"
            case .meter: return "Miernik dźwięku"
            case .morse: return "Morse"
            case .clap: return "Znajdź telefon"
            case .ultra: return "Skaner ultradźwiękowy"
            case .talk: return "Mówiący pad"
            case .whereAmI: return "Gdzie jestem"
            case .stage: return "Tryb obrotowy"
            case .gestures: return "Gesty"
            case .level: return "Poziomica"
            case .strobe: return "Latarka i strobo"
            case .dice: return "Losowanie"
            case .counter: return "Licznik"
            case .convert: return "Przelicznik"
            case .qr: return "Kod QR"
            case .screen: return "Test ekranu"
            case .mirror: return "Lusterko"
            case .send: return "Wyślij obrazki"
            case .ikea: return "IKEA Navigator"
            case .pranks: return "Psikusy"
            case .settings: return "Ustawienia"
            }
        }

        var subtitle: String {
            switch self {
            case .tuner: return "Gitara, ukulele, głos. Nuta i odchyłka."
            case .tone: return "Sinus, prostokąt, szum, przemiatanie."
            case .meter: return "Jak głośno jest wokół, z wykresem."
            case .morse: return "Dźwiękiem, błyskiem ekranu i latarką."
            case .clap: return "Klaśnij dwa razy, a telefon zadzwoni."
            case .ultra: return "Sonar na echo i detektor wysokich tonów. Dla zabawy."
            case .talk: return "Wpisz tekst, a telefon go wypowie."
            case .whereAmI: return "Miejsce, kompas, wysokość, słońce, parking."
            case .stage: return "Pady i pętla, które obracają się do góry nogami i na bok."
            case .gestures: return "Potrząśnij, odwróć, przechyl, a coś się stanie."
            case .level: return "Połóż albo przyłóż do ściany."
            case .strobe: return "Stała, stroboskop i SOS."
            case .dice: return "Kości, moneta, losowanie z listy."
            case .counter: return "Duży przycisk do liczenia."
            case .convert: return "Długość, masa, prędkość, dane, temperatura."
            case .qr: return "Adres, tekst i Wi-Fi jako kod."
            case .screen: return "Martwe piksele i plamy na ekranie."
            case .mirror: return "Przednia kamera, też do góry nogami."
            case .send: return "Kilka zdjęć naraz, do wybranej osoby."
            case .ikea: return "Mapa IKEA Katowice, kalibracja pozycji, trasa, lista zakupów i asystent AI."
            case .pranks: return "Fałszywa aktualizacja, tryb demo, Evil iOS i inne."
            case .settings: return "Opóźnienie, wersja, źródła dźwięków."
            }
        }

        var symbol: String {
            switch self {
            case .tuner: return "tuningfork"
            case .tone: return "waveform.path"
            case .meter: return "gauge.with.needle.fill"
            case .morse: return "dot.radiowaves.right"
            case .clap: return "hands.clap.fill"
            case .ultra: return "dot.radiowaves.forward"
            case .talk: return "text.bubble.fill"
            case .whereAmI: return "location.fill"
            case .stage: return "rotate.3d"
            case .gestures: return "hand.raised.fingers.spread.fill"
            case .level: return "level.fill"
            case .strobe: return "flashlight.on.fill"
            case .dice: return "dice.fill"
            case .counter: return "plus.circle.fill"
            case .convert: return "arrow.left.arrow.right"
            case .qr: return "qrcode"
            case .screen: return "rectangle.inset.filled"
            case .mirror: return "person.crop.square"
            case .send: return "photo.on.rectangle.angled"
            case .ikea: return "map.fill"
            case .pranks: return "theatermasks.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var tint: Color {
            switch self {
            case .tuner: return .green
            case .tone: return .cyan
            case .meter: return .orange
            case .morse: return .pink
            case .clap: return .yellow
            case .ultra: return .cyan
            case .talk: return .mint
            case .whereAmI: return .blue
            case .stage: return .indigo
            case .gestures: return .purple
            case .level: return .teal
            case .strobe: return .yellow
            case .dice: return .red
            case .counter: return .orange
            case .convert: return .green
            case .qr: return .gray
            case .screen: return .blue
            case .mirror: return .cyan
            case .send: return .pink
            case .ikea: return .yellow
            case .pranks: return .red
            case .settings: return .gray
            }
        }
    }

    private let groups: [(String, [Tool])] = [
        ("Sklep", [.ikea]),
        ("Dźwięk", [.tuner, .tone, .meter, .morse, .ultra, .clap, .talk]),
        ("Gdzie jestem i ruch", [.whereAmI, .stage, .gestures, .level]),
        ("Przydatne", [.strobe, .dice, .counter, .convert, .qr, .screen, .mirror, .send]),
        ("Dla zabawy", [.pranks]),
        ("Apka", [.settings]),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            Page("Narzędzia", "Rzeczy, które się przydają, i takie, które są po prostu fajne") {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.0) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(g.0).spaced(.title3, .bold)
                            ForEach(g.1) { t in row(t) }
                        }
                    }
                }
            }
            .navigationDestination(for: Tool.self) { t in destination(t) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showStage) { StageView(hub: hub) }
    }

    @ViewBuilder
    private func row(_ t: Tool) -> some View {
        if t == .stage {
            Button { showStage = true } label: { rowLabel(t) }.buttonStyle(.plain)
        } else {
            NavigationLink(value: t) { rowLabel(t) }.buttonStyle(.plain)
        }
    }

    private func rowLabel(_ t: Tool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: t.symbol)
                .font(.system(size: 21, weight: .semibold))
                .frame(width: 46, height: 46)
                .glassEffect(.regular.tint(t.tint.opacity(0.45)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).spaced(.headline, .bold)
                Text(t.subtitle).spaced(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
    }

    @ViewBuilder
    private func destination(_ t: Tool) -> some View {
        switch t {
        case .tuner: TunerView(hub: hub)
        case .tone: ToneView()
        case .meter: MeterView()
        case .morse: MorseView()
        case .clap: ClapFinderView()
        case .ultra: UltraView(hub: hub)
        case .talk: TalkView()
        case .whereAmI: LocationView()
        case .stage: EmptyView()
        case .gestures: GesturesView()
        case .level: LevelView()
        case .strobe: StrobeView()
        case .dice: DiceView()
        case .counter: CounterView()
        case .convert: ConverterView()
        case .qr: QRView()
        case .screen: ScreenTestLauncher()
        case .mirror: MirrorView()
        case .send: SendImagesView()
        case .ikea: IkeaView()
        case .pranks: PranksView()
        case .settings: SettingsView()
        }
    }
}

// ------------------------------------------------------------------ stroik

@MainActor
final class TunerModel: ObservableObject {
    @Published var note = "–"
    @Published var octave = ""
    @Published var cents: Float = 0
    @Published var freq: Float = 0
    @Published var active = false        // czy cos slychac
    @Published var inTune = false
    @Published var a4: Float = 440

    private var task: Task<Void, Never>?
    private var recent: [Float] = []
    let hub: AudioHub

    init(hub: AudioHub) { self.hub = hub }

    func start() async {
        guard await hub.useMic("tuner") else { return }
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self else { return }
                let x = self.hub.mixer.recentInput(4096)
                let a4 = self.a4
                let r = await Task.detached(priority: .userInitiated) {
                    x.withUnsafeBufferPointer { Pitch.detect($0.baseAddress!, count: x.count, rate: 48000) }
                }.value
                self.update(r, a4: a4)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        hub.releaseMic("tuner")
    }

    private func update(_ r: (freq: Float, clarity: Float)?, a4: Float) {
        guard let r, r.clarity > 0.8 else {
            recent.removeAll()
            if active { withAnimation(.smooth) { active = false; inTune = false } }
            return
        }
        // mediana z ostatnich pomiarow, zeby wskazowka nie drzala
        recent.append(r.freq)
        if recent.count > 5 { recent.removeFirst() }
        let f = recent.sorted()[recent.count / 2]
        let n = Pitch.note(for: f, a4: a4)
        let was = inTune
        withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
            active = true
            freq = f
            note = n.name
            octave = String(n.octave)
            cents = n.cents
            inTune = abs(n.cents) < 5
        }
        if inTune && !was { Haptics.ok() }
    }
}

struct TunerView: View {
    @EnvironmentObject private var hub: AudioHub
    @StateObject private var model: TunerModel

    init(hub: AudioHub) { _model = StateObject(wrappedValue: TunerModel(hub: hub)) }

    var body: some View {
        Page("Stroik", "Zagraj jedną nutę, najlepiej blisko telefonu") {
            VStack(spacing: 24) {
                gauge
                    .frame(height: 230)
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(model.note).font(.system(size: 84, weight: .bold, design: .rounded))
                        Text(model.octave).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(model.inTune ? Color.green : .white)
                    .contentTransition(.interpolate)
                    Text(model.active ? String(format: "%.1f Hz · %+.0f centów", model.freq, model.cents) : "Czekam na dźwięk…")
                        .spaced(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(maxWidth: .infinity)

                Card {
                    SliderRow(symbol: "tuningfork", title: "Wysokość A4", value: Binding(
                        get: { Double(model.a4) }, set: { model.a4 = Float($0) }), range: 430...450, step: 1) {
                        "\(Int($0)) Hz"
                    }
                }
            }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    // luk od -50 do +50 centow z wskazowka
    private var gauge: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height * 0.95)
            let r = min(size.width * 0.46, size.height * 0.9)
            let a0 = Double.pi * 1.15, a1 = Double.pi * 1.85
            func pt(_ a: Double, _ rr: CGFloat) -> CGPoint { CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr) }

            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            // zielona strefa
            var ok = Path()
            let mid = (a0 + a1) / 2, span = (a1 - a0) * 0.05
            ok.addArc(center: c, radius: r, startAngle: .radians(mid - span), endAngle: .radians(mid + span), clockwise: false)
            ctx.stroke(ok, with: .color(.green.opacity(0.9)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            for i in 0...10 {
                let a = a0 + (a1 - a0) * Double(i) / 10
                var t = Path()
                t.move(to: pt(a, r - 18)); t.addLine(to: pt(a, r - (i % 5 == 0 ? 32 : 26)))
                ctx.stroke(t, with: .color(.white.opacity(0.5)), lineWidth: i % 5 == 0 ? 2.5 : 1.5)
            }

            if model.active {
                let a = mid + (a1 - a0) / 2 * Double(max(-50, min(50, model.cents))) / 50
                var n = Path()
                n.move(to: c); n.addLine(to: pt(a, r - 6))
                ctx.stroke(n, with: .color(model.inTune ? .green : Theme.gold),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)), with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}

// ------------------------------------------------------------------ generator tonow

struct ToneView: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var on = false
    @State private var wave = 0
    @State private var logF = log10(440.0)
    @State private var sweep = false
    @State private var logF2 = log10(4000.0)
    @State private var volume = 0.15

    private var f1: Double { pow(10, logF) }
    private var f2: Double { pow(10, logF2) }

    private static let waves = ["Sinus", "Prostokąt", "Piła", "Trójkąt", "Biały szum", "Różowy szum"]

    var body: some View {
        Page("Generator tonów", "Do testowania głośników, słuchawek i uszu") {
            VStack(spacing: 18) {
                Button {
                    on.toggle()
                    push()
                    Haptics.tap(.medium)
                } label: {
                    Image(systemName: on ? "stop.fill" : "play.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 130, height: 130)
                        .glassEffect(.regular.tint(on ? Color.cyan.opacity(0.55) : nil).interactive(), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .animation(.bouncy, value: on)

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Kształt fali", selection: $wave) {
                            ForEach(0..<Self.waves.count, id: \.self) { Text(Self.waves[$0]).tag($0) }
                        }
                        .pickerStyle(.menu)

                        if wave < 4 {
                            SliderRow(symbol: "waveform", title: sweep ? "Od" : "Częstotliwość", value: $logF,
                                      range: log10(20)...log10(20000)) { Self.hz(pow(10, $0)) }
                            Toggle(isOn: $sweep) { Label("Przemiataj", systemImage: "arrow.left.and.right") }
                            if sweep {
                                SliderRow(symbol: "waveform", title: "Do", value: $logF2,
                                          range: log10(20)...log10(20000)) { Self.hz(pow(10, $0)) }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach([("A4", 440.0), ("50 Hz", 50), ("1 kHz", 1000), ("5 kHz", 5000), ("15 kHz", 15000)], id: \.0) { n, f in
                                        Button { logF = log10(f); push() } label: { Chip(text: n) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        SliderRow(symbol: "speaker.wave.2.fill", title: "Głośność", value: $volume, range: 0.02...0.4) {
                            "\(Int($0 / 0.4 * 100))%"
                        }
                        Text("Zacznij od małej głośności i nie trzymaj wysokich tonów przy uchu.")
                            .spaced(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: wave) { push() }
        .onChange(of: logF) { push() }
        .onChange(of: logF2) { push() }
        .onChange(of: sweep) { push() }
        .onChange(of: volume) { push() }
        .onDisappear {
            on = false
            push()
        }
    }

    private func push() {
        hub.mixer.setTone(on: on, wave: wave, f1: f1, f2: sweep ? f2 : f1, sweep: sweep ? 3 : 0, gain: Float(volume))
    }

    private static func hz(_ f: Double) -> String {
        f >= 1000 ? String(format: "%.2f kHz", f / 1000) : String(format: "%.0f Hz", f)
    }
}

// ------------------------------------------------------------------ miernik dzwieku

struct MeterView: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var db: Double = 0
    @State private var history: [Double] = []
    @State private var peak: Double = 0
    @State private var granted = false
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var label: String {
        switch db {
        case ..<30: return "Cisza"
        case ..<50: return "Cicho, jak w bibliotece"
        case ..<65: return "Rozmowa"
        case ..<80: return "Głośna ulica, odkurzacz"
        case ..<95: return "Bardzo głośno, długo szkodzi"
        default: return "Koncert, uważaj na uszy"
        }
    }

    private var color: Color {
        db < 70 ? .green : (db < 85 ? .orange : .red)
    }

    var body: some View {
        Page("Miernik dźwięku", "Wartości są przybliżone, mikrofon telefonu nie jest miernikiem") {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(Int(db.rounded()))")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: db))
                        .foregroundStyle(color)
                    Text("dB").spaced(.title3, .semibold).foregroundStyle(.secondary)
                    Text(label).spaced(.subheadline, .semibold).contentTransition(.interpolate)
                }
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: Int(db))

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Trace(history: history, color: color).frame(height: 110)
                        HStack {
                            Text("Szczyt \(Int(peak))").monospacedDigit()
                            Spacer()
                            Button("Zeruj") { peak = 0; history = [] }
                        }
                        .spaced(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            granted = await hub.useMic("meter")
        }
        .onDisappear { hub.releaseMic("meter") }
        .onReceive(tick) { _ in
            guard granted else { return }
            let rms = Double(hub.mixer.levels.mic)
            // 0 dBFS to u nas okolo 94 dB (typowa czulosc mikrofonu), reszta w dol
            let v = max(0, min(120, 20 * log10(max(rms, 1e-5)) + 94 + 8))
            withAnimation(.snappy(duration: 0.2)) { db += (v - db) * 0.5 }
            peak = max(peak, db)
            history.append(db)
            if history.count > 150 { history.removeFirst() }
        }
    }

    private struct Trace: View {
        let history: [Double]
        let color: Color

        var body: some View {
            Canvas { ctx, size in
                guard history.count > 1 else { return }
                var p = Path()
                for (i, v) in history.enumerated() {
                    let x = size.width * CGFloat(i) / 150
                    let y = size.height * (1 - CGFloat(v / 120))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// ------------------------------------------------------------------ Morse

struct MorseView: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var text = "SOS"
    @State private var wpm = 15.0
    @State private var flash = false
    @State private var sending = false
    @State private var torch = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        Page("Morse", "Dźwiękiem, błyskiem ekranu i opcjonalnie latarką") {
            VStack(spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Tekst do nadania", text: $text, axis: .vertical)
                            .textInputAutocapitalization(.characters)
                            .padding(12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        Text(code).spaced(.footnote).monospaced().foregroundStyle(Theme.gold).lineLimit(3)
                        SliderRow(symbol: "speedometer", title: "Tempo", value: $wpm, range: 5...30, step: 1) { "\(Int($0)) słów/min" }
                        Toggle(isOn: $torch) { Label("Błysk latarką", systemImage: "flashlight.on.fill") }
                    }
                }

                Button {
                    sending ? stop() : send()
                } label: {
                    Label(sending ? "Stop" : "Nadaj", systemImage: sending ? "stop.fill" : "dot.radiowaves.right")
                        .spaced(.title3, .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .glassEffect(.regular.tint(sending ? Color.red.opacity(0.5) : Color.pink.opacity(0.5)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .animation(.bouncy, value: sending)
            }
        }
        .overlay {
            Color.white.opacity(flash ? 0.92 : 0).ignoresSafeArea().allowsHitTesting(false)
        }
        .onDisappear { stop() }
    }

    private var code: String {
        text.map { c -> String in
            c == " " ? "/" : (Morse.table[Morse.normalize(c)] ?? "")
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func send() {
        let t = text
        let w = wpm
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        sending = true
        hub.mixer.play(Morse.audio(t, wpm: w), tag: 9000, gain: 0.8)
        let timings = Morse.timings(t, wpm: w)
        let useTorch = torch
        job = Task {
            for (on, sec) in timings {
                if Task.isCancelled { break }
                flash = on
                if useTorch { Self.setTorch(on) }
                try? await Task.sleep(for: .seconds(sec))
            }
            flash = false
            Self.setTorch(false)
            sending = false
        }
    }

    private func stop() {
        job?.cancel()
        hub.mixer.stop(tag: 9000)
        flash = false
        sending = false
        Self.setTorch(false)
    }

    private static func setTorch(_ on: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
    }
}
