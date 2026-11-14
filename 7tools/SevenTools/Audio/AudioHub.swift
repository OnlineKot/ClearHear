import AVFoundation
import Combine
import UIKit

// ------------------------------------------------------------------ efekty glosu

struct FXPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    var pitch: Float = 0                 // centy
    var distortion: AVAudioUnitDistortionPreset? = nil
    var distortionMix: Float = 0
    var delay: Double = 0                // sekundy
    var feedback: Float = 0
    var delayMix: Float = 0
    var reverb: AVAudioUnitReverbPreset = .mediumRoom
    var reverbMix: Float = 0
    var highPass: Float = 70             // Hz
    var lowPass: Float = 16000

    static let all: [FXPreset] = [
        FXPreset(id: "clean", name: "Czysty", symbol: "mic.fill"),
        FXPreset(id: "007", name: "Agent 007", symbol: "eye.fill", pitch: -180,
                 delay: 0.07, feedback: 10, delayMix: 8, reverb: .smallRoom, reverbMix: 22),
        FXPreset(id: "robot", name: "Robot", symbol: "cpu.fill",
                 distortion: .multiDecimated2, distortionMix: 55, delay: 0.018, feedback: 62, delayMix: 35),
        FXPreset(id: "chip", name: "Pisklak", symbol: "hare.fill", pitch: 700),
        FXPreset(id: "demon", name: "Demon", symbol: "flame.fill", pitch: -900,
                 distortion: .multiBrokenSpeaker, distortionMix: 22, reverb: .cathedral, reverbMix: 30),
        FXPreset(id: "echo", name: "Echo", symbol: "dot.radiowaves.left.and.right",
                 delay: 0.36, feedback: 46, delayMix: 42),
        FXPreset(id: "hall", name: "Hala", symbol: "building.columns.fill", reverb: .largeHall, reverbMix: 55),
        FXPreset(id: "phone", name: "Telefon", symbol: "phone.fill",
                 distortion: .speechRadioTower, distortionMix: 18, highPass: 420, lowPass: 3300),
    ]
}

// ------------------------------------------------------------------ strumien dzwieku

// Nie jest zwiazany z glownym watkiem: domkniecia graja na watku audio.
final class SevenGraph {
    private let mixer: Mixer
    private(set) var engine: AVAudioEngine?
    private var eq: AVAudioUnitEQ?
    private var pitch: AVAudioUnitTimePitch?
    private var dist: AVAudioUnitDistortion?
    private var delay: AVAudioUnitDelay?
    private var reverb: AVAudioUnitReverb?
    private var gate: AVAudioMixerNode?

    init(mixer: Mixer) { self.mixer = mixer }

    var hasMic: Bool { gate != nil }

    func start(mic: Bool) throws {
        stop()
        let e = AVAudioEngine()
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: mixer.rate, channels: 1) else { return }

        let mixer = self.mixer
        let src = AVAudioSourceNode(format: mono) { _, _, frames, list in
            let bufs = UnsafeMutableAudioBufferListPointer(list)
            let n = Int(frames)
            guard let first = bufs.first, let d0 = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            mixer.render(d0, frames: n)
            if bufs.count > 1 {
                for j in 1..<bufs.count {
                    if let dj = bufs[j].mData { memcpy(dj, d0, n * MemoryLayout<Float>.size) }
                }
            }
            return noErr
        }
        e.attach(src)
        e.connect(src, to: e.mainMixerNode, format: mono)

        if mic {
            let input = e.inputNode
            let hw = input.outputFormat(forBus: 0)
            guard hw.sampleRate > 0, hw.channelCount > 0 else { throw NSError(domain: "7Tools", code: 1) }
            guard let fxFmt = AVAudioFormat(standardFormatWithSampleRate: hw.sampleRate, channels: 1) else { return }

            // wejscie idzie dwiema drogami: do miksera (looper, stroik) i przez efekty do wyjscia
            let micMix = AVAudioMixerNode()
            let sink = AVAudioSinkNode { _, frames, list in
                let bufs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
                guard frames > 0, let first = bufs.first,
                      let d0 = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                mixer.capture(d0, Int(frames))
                return noErr
            }
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            let pitch = AVAudioUnitTimePitch()
            let dist = AVAudioUnitDistortion()
            let delay = AVAudioUnitDelay()
            let reverb = AVAudioUnitReverb()
            let gate = AVAudioMixerNode()
            for n in [micMix, sink, eq, pitch, dist, delay, reverb, gate] as [AVAudioNode] { e.attach(n) }

            e.connect(input, to: [AVAudioConnectionPoint(node: micMix, bus: 0),
                                  AVAudioConnectionPoint(node: eq, bus: 0)], fromBus: 0, format: hw)
            e.connect(micMix, to: sink, format: mono)
            e.connect(eq, to: pitch, format: fxFmt)
            e.connect(pitch, to: dist, format: fxFmt)
            e.connect(dist, to: delay, format: fxFmt)
            e.connect(delay, to: reverb, format: fxFmt)
            e.connect(reverb, to: gate, format: fxFmt)
            e.connect(gate, to: e.mainMixerNode, format: fxFmt)
            gate.outputVolume = 0

            eq.bands[0].filterType = .highPass
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass
            eq.bands[1].bypass = false
            self.eq = eq; self.pitch = pitch; self.dist = dist
            self.delay = delay; self.reverb = reverb; self.gate = gate
        }

        e.mainMixerNode.outputVolume = 1
        e.prepare()
        try e.start()
        engine = e
    }

    func stop() {
        engine?.stop()
        engine = nil
        eq = nil; pitch = nil; dist = nil; delay = nil; reverb = nil; gate = nil
    }

    // ustawia efekt glosu, on = czy w ogole slychac
    func setFX(_ p: FXPreset, on: Bool) {
        guard let gate else { return }
        eq?.bands[0].frequency = p.highPass
        eq?.bands[1].frequency = p.lowPass
        pitch?.pitch = p.pitch
        if let d = p.distortion { dist?.loadFactoryPreset(d) }
        dist?.wetDryMix = p.distortion == nil ? 0 : p.distortionMix
        delay?.delayTime = max(0.001, p.delay)
        delay?.feedback = p.feedback
        delay?.wetDryMix = p.delay > 0 ? p.delayMix : 0
        reverb?.loadFactoryPreset(p.reverb)
        reverb?.wetDryMix = p.reverbMix
        gate.outputVolume = on ? 1 : 0
    }
}

// ------------------------------------------------------------------ stan apki

@MainActor
final class AudioHub: ObservableObject {
    let mixer = Mixer(rate: 48000)
    private let graph: SevenGraph

    @Published private(set) var running = false
    @Published private(set) var micOn = false
    @Published private(set) var headphones = false
    @Published private(set) var micDenied = false
    @Published var notice: String?

    @Published var fx = FXPreset.all[0] { didSet { applyFX() } }
    @Published var fxOn = false { didSet { applyFX() } }

    private var clients = Set<String>()
    private var bag = Set<AnyCancellable>()

    // ile ms dodatkowego opoznienia przy nagrywaniu z mikrofonu (ustawienie w apce)
    var extraLatencyMs: Double { UserDefaults.standard.double(forKey: "latencyMs") }

    init() {
        graph = SevenGraph(mixer: mixer)
        let nc = NotificationCenter.default
        nc.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.interrupted(n) }
            .store(in: &bag)
        nc.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.routeChanged() }
            .store(in: &bag)
        nc.publisher(for: .AVAudioEngineConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)
        nc.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)
    }

    // ---------------------------------------------------------- start

    func start() {
        guard !running else { return }
        rebuild()
    }

    private func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setPreferredSampleRate(48000)
        try? s.setPreferredIOBufferDuration(0.005)
        try s.setActive(true)
    }

    private func rebuild() {
        do {
            try configureSession()
            try graph.start(mic: !clients.isEmpty)
            running = true
            micOn = !clients.isEmpty
            updateLatency()
            applyFX()
            routeChanged()
        } catch {
            running = false
            micOn = false
            notice = "Nie udało się uruchomić dźwięku."
        }
    }

    // ---------------------------------------------------------- mikrofon

    // Funkcje, ktore potrzebuja mikrofonu, zglaszaja sie tu. Mikrofon jest wlaczony tylko, gdy ktos go uzywa.
    @discardableResult
    func useMic(_ client: String) async -> Bool {
        let app = AVAudioApplication.shared
        var ok = app.recordPermission == .granted
        if app.recordPermission == .undetermined {
            ok = await AVAudioApplication.requestRecordPermission()
        }
        guard ok else {
            micDenied = true
            notice = "Brak dostępu do mikrofonu. Włącz go w Ustawieniach telefonu."
            return false
        }
        micDenied = false
        let had = !clients.isEmpty
        clients.insert(client)
        if !had { rebuild() }
        return micOn
    }

    func releaseMic(_ client: String) {
        guard clients.remove(client) != nil else { return }
        if clients.isEmpty {
            if fxOn { fxOn = false }
            rebuild()
        }
    }

    // ---------------------------------------------------------- trasa i opoznienie

    private func routeChanged() {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        let types: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
        headphones = outs.contains { types.contains($0.portType) }
        if !headphones && fxOn {
            fxOn = false
            notice = "Słuchawki odłączone. Wyłączyłem efekty głosu, żeby nie piszczało."
        }
        updateLatency()
    }

    private func updateLatency() {
        let s = AVAudioSession.sharedInstance()
        let sec = s.inputLatency + s.outputLatency + s.ioBufferDuration + extraLatencyMs / 1000
        let frames = max(0, Int(sec * mixer.rate))
        mixer.loop { $0.latencyFrames = frames }
    }

    func applyLatency() { updateLatency() }

    private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended { rebuild() }
    }

    // ---------------------------------------------------------- efekty glosu

    private func applyFX() {
        if fxOn && !headphones {
            fxOn = false
            notice = "Efekty głosu działają tylko ze słuchawkami, bez nich mikrofon by piszczał."
            return
        }
        graph.setFX(fx, on: fxOn)
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

// ------------------------------------------------------------------ import plikow

enum Importer {
    // Czyta dowolny plik audio, sprowadza do mono 48 kHz. Max 60 sekund.
    static func load(_ url: URL, maxSeconds: Double = 60) throws -> SampleBuffer {
        let f = try AVAudioFile(forReading: url)
        let fmt = f.processingFormat
        let frames = AVAudioFrameCount(min(f.length, Int64(fmt.sampleRate * maxSeconds)))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else {
            throw NSError(domain: "7Tools", code: 2)
        }
        try f.read(into: buf, frameCount: frames)
        guard let ch = buf.floatChannelData else { throw NSError(domain: "7Tools", code: 3) }
        let n = Int(buf.frameLength)
        let channels = Int(fmt.channelCount)
        let out = SampleBuffer(count: n, rate: fmt.sampleRate)
        for i in 0..<n {
            var s: Float = 0
            for c in 0..<channels { s += ch[c][i] }
            out.data[i] = s / Float(channels)
        }
        return out.resampled(to: 48000)
    }
}
