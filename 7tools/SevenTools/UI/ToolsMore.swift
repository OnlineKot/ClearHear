import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage.CIFilterBuiltins

// ------------------------------------------------------------------ latarka: stala, stroboskop, SOS

struct StrobeView: View {
    @State private var mode = 0           // 0 stala, 1 stroboskop, 2 SOS
    @State private var on = false
    @State private var hz = 6.0
    @State private var level = 1.0
    @State private var screenFlash = true
    @State private var lit = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        Page("Latarka", "Stała, stroboskop i SOS") {
            VStack(spacing: 18) {
                Button {
                    on ? stop() : start()
                } label: {
                    Image(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 150, height: 150)
                        .glassEffect(.regular.tint(on ? Color.yellow.opacity(0.5) : nil).interactive(), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .animation(.bouncy, value: on)

                Picker("Tryb", selection: $mode) {
                    Text("Stała").tag(0)
                    Text("Strobo").tag(1)
                    Text("SOS").tag(2)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { if on { stop(); start() } }

                Card {
                    VStack(spacing: 14) {
                        if mode == 1 {
                            SliderRow(symbol: "bolt.fill", title: "Częstotliwość", value: $hz, range: 1...15, step: 1) { "\(Int($0)) Hz" }
                        }
                        SliderRow(symbol: "sun.max.fill", title: "Jasność latarki", value: $level, range: 0.1...1) { "\(Int($0 * 100))%" }
                        Toggle(isOn: $screenFlash) { Label("Błyskaj też ekranem", systemImage: "iphone") }
                        Text("Uwaga: szybkie błyski mogą wywołać atak u osób z padaczką światłoczułą. Nie świeć nimi w oczy.")
                            .spaced(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay { Color.white.opacity(lit && screenFlash ? 0.95 : 0).ignoresSafeArea().allowsHitTesting(false) }
        .onDisappear { stop() }
    }

    private func start() {
        on = true
        let m = mode, f = hz
        job = Task {
            switch m {
            case 0:
                await set(true)
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(0.5)) }
            case 1:
                while !Task.isCancelled {
                    await set(true); try? await Task.sleep(for: .seconds(0.5 / f))
                    await set(false); try? await Task.sleep(for: .seconds(0.5 / f))
                }
            default:
                // ...---... w alfabecie Morse'a
                let pattern: [Double] = [0.2, 0.2, 0.2, 0.6, 0.6, 0.6, 0.2, 0.2, 0.2]
                while !Task.isCancelled {
                    for d in pattern {
                        if Task.isCancelled { break }
                        await set(true); try? await Task.sleep(for: .seconds(d))
                        await set(false); try? await Task.sleep(for: .seconds(0.2))
                    }
                    try? await Task.sleep(for: .seconds(1.0))
                }
            }
        }
    }

    private func stop() {
        job?.cancel()
        on = false
        lit = false
        Self.torch(false, 0)
    }

    @MainActor
    private func set(_ v: Bool) async {
        lit = v
        Self.torch(v, Float(level))
    }

    static func torch(_ on: Bool, _ level: Float) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        try? d.lockForConfiguration()
        if on { try? d.setTorchModeOn(level: max(0.05, min(1, level))) } else { d.torchMode = .off }
        d.unlockForConfiguration()
    }
}

// ------------------------------------------------------------------ szukaj telefonu klasnieciem

struct ClapFinderView: View {
    @EnvironmentObject private var hub: AudioHub
    @EnvironmentObject private var store: SoundStore
    @State private var armed = false
    @State private var ringing = false
    @State private var detector = ClapDetector()
    @State private var t = 0.0
    @State private var volume = 0.6
    @State private var flash = false
    private let tick = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    var body: some View {
        Page("Znajdź telefon", "Klaśnij dwa razy, a telefon zacznie dzwonić") {
            VStack(spacing: 18) {
                Button {
                    Task { await toggle() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: ringing ? "bell.fill" : (armed ? "ear.fill" : "hands.clap.fill"))
                            .font(.system(size: 50, weight: .bold))
                            .symbolEffect(.bounce, isActive: ringing)
                            .contentTransition(.symbolEffect(.replace))
                        Text(ringing ? "Dzwoni! Dotknij, aby wyłączyć" : (armed ? "Nasłuchuję klaśnięć…" : "Uzbrój"))
                            .spaced(.subheadline, .bold).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 210, height: 210)
                    .glassEffect(.regular.tint(ringing ? Color.red.opacity(0.6) : (armed ? Color.green.opacity(0.35) : nil)).interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .animation(.bouncy, value: armed)
                .animation(.bouncy, value: ringing)

                Card {
                    VStack(spacing: 12) {
                        SliderRow(symbol: "speaker.wave.3.fill", title: "Głośność dzwonka", value: $volume, range: 0.2...1) { "\(Int($0 * 100))%" }
                        Text("Telefon musi być w tym czasie włączony, a apka otwarta albo działająca w tle. Mikrofon słucha tylko po uzbrojeniu.")
                            .spaced(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay { Color.white.opacity(flash ? 0.9 : 0).ignoresSafeArea().allowsHitTesting(false) }
        .onReceive(tick) { _ in
            guard armed, !ringing else { return }
            t += 0.02
            if detector.feed(level: hub.mixer.levels.mic, at: t) { ring() }
        }
        .onDisappear { disarm() }
    }

    private func toggle() async {
        if ringing {
            stopRing()
        } else if armed {
            disarm()
        } else {
            guard await hub.useMic("clap") else { return }
            detector = ClapDetector()
            armed = true
        }
    }

    private func ring() {
        ringing = true
        if let b = store.buffer("builtin:alarm") { hub.mixer.play(b, tag: 8900, gain: Float(volume), loop: true) }
        Haptics.ok()
        Task {
            while ringing {
                flash.toggle()
                try? await Task.sleep(for: .seconds(0.25))
            }
            flash = false
        }
    }

    private func stopRing() {
        ringing = false
        hub.mixer.stop(tag: 8900)
        t = 0
        detector = ClapDetector()
    }

    private func disarm() {
        if ringing { stopRing() }
        if armed { armed = false; hub.releaseMic("clap") }
    }
}

// ------------------------------------------------------------------ mowiacy pad

final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var speaking = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float, pitch: Float) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = rate
        u.pitchMultiplier = pitch
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { DispatchQueue.main.async { self.speaking = true } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.speaking = false } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { DispatchQueue.main.async { self.speaking = false } }
}

struct TalkView: View {
    @StateObject private var speaker = Speaker()
    @State private var text = "Halo, tu agent zero zero siedem."
    @State private var voiceID = ""
    @State private var rate = 0.5
    @State private var pitch = 1.0

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("pl") || $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    private static let phrases = ["Halo? Słyszysz mnie?", "Uwaga, to nie są ćwiczenia.", "Bond. James Bond.",
                                  "Telefon wykrył, że jesteś za bardzo normalny.", "Proszę odsunąć się od telefonu."]

    var body: some View {
        Page("Mówiący pad", "Wpisz tekst, a telefon go wypowie") {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 12) {
                        TextField("Co ma powiedzieć?", text: $text, axis: .vertical)
                            .lineLimit(2...6)
                            .padding(12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Self.phrases, id: \.self) { p in
                                    Button { text = p } label: { Chip(text: p) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Card {
                    VStack(spacing: 12) {
                        Picker("Głos", selection: $voiceID) {
                            Text("Domyślny").tag("")
                            ForEach(voices, id: \.identifier) { Text("\($0.name) (\($0.language))").tag($0.identifier) }
                        }
                        .pickerStyle(.menu)
                        SliderRow(symbol: "hare.fill", title: "Tempo", value: $rate, range: 0.2...0.7) { String(format: "%.2f", $0) }
                        SliderRow(symbol: "tuningfork", title: "Wysokość", value: $pitch, range: 0.5...2) { String(format: "%.1fx", $0) }
                    }
                }
                Button {
                    if speaker.speaking {
                        speaker.stop()
                    } else {
                        speaker.say(text, voice: AVSpeechSynthesisVoice(identifier: voiceID), rate: Float(rate), pitch: Float(pitch))
                    }
                } label: {
                    Label(speaker.speaking ? "Stop" : "Mów", systemImage: speaker.speaking ? "stop.fill" : "speaker.wave.3.fill")
                        .spaced(.title3, .bold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .glassEffect(.regular.tint(Theme.gold.opacity(0.5)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear { speaker.stop() }
    }
}

// ------------------------------------------------------------------ losowanie

struct DiceView: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var sides = 6
    @State private var count = 1
    @State private var values: [Int] = [6]
    @State private var rolling = false
    @State private var coin: Bool? = nil
    @State private var flip = 0.0
    @State private var names = "Ala\nOla\nKasia"
    @State private var picked = ""

    var body: some View {
        Page("Losowanie", "Kości, moneta i wybór z listy") {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            ForEach([4, 6, 8, 10, 12, 20, 100], id: \.self) { s in
                                Button { sides = s; values = [Int](repeating: s, count: count) } label: { Chip(text: "k\(s)", selected: sides == s) }
                                    .buttonStyle(.plain)
                            }
                        }
                        Stepper("Ile kości: \(count)", value: $count, in: 1...6)
                            .onChange(of: count) { values = [Int](repeating: sides, count: count) }
                        HStack(spacing: 12) {
                            ForEach(values.indices, id: \.self) { i in
                                Text("\(values[i])")
                                    .font(.system(size: values.count > 3 ? 26 : 44, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: 84)
                                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                                    .contentTransition(.numericText())
                            }
                        }
                        Text("Suma: \(values.reduce(0, +))").spaced(.subheadline, .semibold).foregroundStyle(.secondary)
                        Button { roll() } label: {
                            Label("Rzuć", systemImage: "dice.fill").spaced(.headline, .bold).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .glassEffect(.regular.tint(Theme.gold.opacity(0.5)).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain).disabled(rolling)
                    }
                }

                Card {
                    VStack(spacing: 12) {
                        Text(coin == nil ? "Moneta" : (coin! ? "ORZEŁ" : "RESZKA"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .frame(width: 120, height: 120)
                            .glassEffect(.regular.tint(Theme.gold.opacity(0.4)), in: .circle)
                            .rotation3DEffect(.degrees(flip), axis: (x: 1, y: 0, z: 0))
                        Button("Rzuć monetą") {
                            withAnimation(.easeInOut(duration: 0.7)) { flip += 1080 }
                            Haptics.tap(.medium)
                            Task {
                                try? await Task.sleep(for: .seconds(0.7))
                                coin = Bool.random()
                                Haptics.ok()
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity)
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wybierz z listy (jedna pozycja na linię)").spaced(.subheadline, .semibold)
                        TextEditor(text: $names)
                            .frame(height: 100).scrollContentBackground(.hidden)
                            .padding(8).glassEffect(.regular, in: .rect(cornerRadius: 18))
                        Button("Losuj") {
                            let items = names.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                            picked = items.randomElement() ?? ""
                            Haptics.ok()
                        }
                        .buttonStyle(.glassProminent).tint(Theme.gold)
                        if !picked.isEmpty {
                            Text(picked).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
                                .contentTransition(.interpolate).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func roll() {
        rolling = true
        Task {
            for _ in 0..<10 {
                withAnimation(.snappy(duration: 0.08)) { values = (0..<count).map { _ in Int.random(in: 1...sides) } }
                if let b = PrankSound.all["tick"]?() { hub.mixer.play(b, tag: 8700, gain: 0.5) }
                Haptics.tap(.light, 0.6)
                try? await Task.sleep(for: .milliseconds(70))
            }
            rolling = false
            Haptics.ok()
        }
    }
}

// ------------------------------------------------------------------ licznik

struct CounterView: View {
    @AppStorage("counter.value") private var value = 0
    @AppStorage("counter.step") private var step = 1
    @EnvironmentObject private var hub: AudioHub

    var body: some View {
        Page("Licznik", "Dotknij dużego przycisku, żeby liczyć") {
            VStack(spacing: 18) {
                Text("\(value)")
                    .font(.system(size: 110, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                    .frame(maxWidth: .infinity)
                    .animation(.snappy(duration: 0.25), value: value)

                Button {
                    value += step
                    Haptics.tap(.rigid)
                    if let b = PrankSound.all["tick"]?() { hub.mixer.play(b, tag: 8701, gain: 0.5) }
                } label: {
                    Image(systemName: "plus").font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 170)
                        .glassEffect(.regular.tint(Theme.gold.opacity(0.4)).interactive(), in: .rect(cornerRadius: 40))
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Button { value -= step; Haptics.tap(.soft) } label: {
                        Image(systemName: "minus").font(.system(size: 28, weight: .bold)).frame(maxWidth: .infinity).frame(height: 64)
                    }
                    .buttonStyle(.glass)
                    Button(role: .destructive) { value = 0; Haptics.ok() } label: {
                        Text("Zeruj").spaced(.headline, .bold).frame(maxWidth: .infinity).frame(height: 64)
                    }
                    .buttonStyle(.glass)
                }
                Stepper("Krok: \(step)", value: $step, in: 1...100)
                    .padding(16).glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
        }
    }
}

// ------------------------------------------------------------------ przelicznik

struct ConverterView: View {
    @State private var cat = Units.all[0]
    @State private var from = Units.all[0].units[2]
    @State private var to = Units.all[0].units[3]
    @State private var text = "1"

    private var result: String {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return "–" }
        let r = Units.convert(v, from: from, to: to, in: cat)
        return abs(r) >= 1e9 || (abs(r) < 1e-4 && r != 0) ? String(format: "%.4e", r) : String(format: "%.6g", r)
    }

    var body: some View {
        Page("Przelicznik", "Długość, masa, prędkość, objętość, dane, temperatura") {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Units.all) { c in
                            Button {
                                cat = c; from = c.units[0]; to = c.units[min(1, c.units.count - 1)]
                            } label: { Chip(text: c.title, selected: c == cat) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Card {
                    VStack(spacing: 14) {
                        TextField("Wartość", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 18))
                        Picker("Z", selection: $from) { ForEach(cat.units, id: \.self) { Text($0.name).tag($0) } }
                            .pickerStyle(.menu)
                        Button {
                            let t = from; from = to; to = t
                            Haptics.tap(.light)
                        } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 20, weight: .bold)) }
                        .buttonStyle(.glass)
                        Picker("Na", selection: $to) { ForEach(cat.units, id: \.self) { Text($0.name).tag($0) } }
                            .pickerStyle(.menu)
                        Text(result + " " + to.name)
                            .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ kod QR

struct QRView: View {
    @State private var kind = 0
    @State private var text = "https://fastlink.teodorteo.com"
    @State private var ssid = ""
    @State private var pass = ""
    @State private var image: UIImage?

    private var payload: String {
        kind == 0 ? text : "WIFI:T:WPA;S:\(ssid);P:\(pass);;"
    }

    var body: some View {
        Page("Kod QR", "Tekst, adres strony albo dane do sieci Wi-Fi") {
            VStack(spacing: 16) {
                Picker("Rodzaj", selection: $kind) {
                    Text("Tekst / adres").tag(0)
                    Text("Wi-Fi").tag(1)
                }
                .pickerStyle(.segmented)

                Card {
                    VStack(spacing: 12) {
                        if kind == 0 {
                            TextField("Tekst lub adres", text: $text, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 18))
                        } else {
                            TextField("Nazwa sieci", text: $ssid).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).glassEffect(.regular, in: .capsule)
                            SecureField("Hasło", text: $pass)
                                .padding(12).glassEffect(.regular, in: .capsule)
                        }
                    }
                }

                if let image {
                    Image(uiImage: image)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(width: 260, height: 260)
                        .padding(16).background(Color.white, in: .rect(cornerRadius: 24))
                        .frame(maxWidth: .infinity)
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Kod QR", image: Image(uiImage: image))) {
                        Label("Wyślij obrazek", systemImage: "square.and.arrow.up").spaced(.headline, .bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .onChange(of: payload, initial: true) { _, p in image = Self.make(p) }
    }

    private static func make(_ s: String) -> UIImage? {
        guard !s.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// ------------------------------------------------------------------ test ekranu

struct ScreenTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var i = 0

    private let colors: [Color] = [.black, .white, .red, .green, .blue, Color(white: 0.5)]

    var body: some View {
        ZStack {
            if i < colors.count {
                colors[i]
            } else if i == colors.count {
                LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
            } else {
                LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing)
            }
            VStack {
                Spacer()
                Text("Dotknij, aby zmienić kolor (\(i + 1)/\(colors.count + 2))")
                    .spaced(.footnote, .semibold).foregroundStyle(.gray).padding(8)
                    .background(.black.opacity(0.5), in: .capsule)
                    .padding(.bottom, 30)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { i = (i + 1) % (colors.count + 2) }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.gray) }
                .padding(20)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

struct ScreenTestLauncher: View {
    @State private var show = false

    var body: some View {
        Page("Test ekranu", "Sprawdź martwe piksele i plamy na wyświetlaczu") {
            Button { show = true } label: {
                Label("Uruchom na pełnym ekranie", systemImage: "rectangle.inset.filled").spaced(.headline, .bold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 64)
                    .glassEffect(.regular.tint(Color.blue.opacity(0.5)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $show) { ScreenTestView() }
    }
}

// ------------------------------------------------------------------ lusterko

struct CameraPreview: UIViewRepresentable {
    let position: AVCaptureDevice.Position

    final class Holder: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer_: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()
    }

    func makeUIView(context: Context) -> Holder {
        let v = Holder()
        v.layer_.session = v.session
        v.layer_.videoGravity = .resizeAspectFill
        if let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: d), v.session.canAddInput(input) {
            v.session.addInput(input)
        }
        DispatchQueue.global(qos: .userInitiated).async { v.session.startRunning() }
        return v
    }

    func updateUIView(_ uiView: Holder, context: Context) {}

    static func dismantleUIView(_ uiView: Holder, coordinator: ()) {
        uiView.session.stopRunning()
    }
}

struct MirrorView: View {
    @State private var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var flipV = false
    @State private var mirrored = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if allowed {
                CameraPreview(position: .front)
                    .ignoresSafeArea()
                    .scaleEffect(x: mirrored ? -1 : 1, y: flipV ? -1 : 1)
                VStack {
                    Spacer()
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button { mirrored.toggle() } label: { Chip(text: "Lustro", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", selected: mirrored) }
                                .buttonStyle(.plain)
                            Button { flipV.toggle() } label: { Chip(text: "Do góry nogami", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", selected: flipV) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 30)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Lusterko potrzebuje aparatu").spaced(.headline, .bold)
                    Button("Pozwól") {
                        AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { allowed = ok } }
                    }
                    .buttonStyle(.glassProminent).tint(Theme.gold)
                }
            }
        }
        .navigationTitle("Lusterko")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ------------------------------------------------------------------ wysylanie obrazkow

struct SendImagesView: View {
    @State private var picks: [PhotosPickerItem] = []
    @State private var urls: [URL] = []
    @State private var loading = false

    var body: some View {
        Page("Wyślij obrazki", "Wybierz kilka zdjęć i wyślij je wybranej osobie, np. AirDropem") {
            VStack(spacing: 16) {
                PhotosPicker(selection: $picks, maxSelectionCount: 20, matching: .images) {
                    Label("Wybierz zdjęcia", systemImage: "photo.on.rectangle.angled").spaced(.headline, .bold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .glassEffect(.regular.tint(Color.blue.opacity(0.5)).interactive(), in: .capsule)
                }

                if loading { ProgressView() }

                if !urls.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(urls, id: \.self) { u in
                            AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                                .frame(height: 100).clipShape(.rect(cornerRadius: 14))
                        }
                    }
                    ShareLink(items: urls) {
                        Label("Wyślij \(urls.count) zdj.", systemImage: "square.and.arrow.up").spaced(.headline, .bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.gold)
                }

                Card {
                    Text("Arkusz udostępniania pozwala wybrać odbiorców, także kilka osób w Wiadomościach. Nie ma tu wysyłania do obcych w okolicy bez ich zgody.")
                        .spaced(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: picks) { _, items in Task { await load(items) } }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        loading = true
        defer { loading = false }
        var out: [URL] = []
        for (i, it) in items.enumerated() {
            if let d = try? await it.loadTransferable(type: Data.self) {
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("zdjecie-\(i + 1).jpg")
                if (try? d.write(to: u)) != nil { out.append(u) }
            }
        }
        urls = out
    }
}
