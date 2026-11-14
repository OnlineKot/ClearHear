import AVFoundation
import Combine
import MediaPlayer
import UIKit

// ------------------------------------------------------------------ dzwiek

enum HearError: Error {
    case noInput
    case noHeadphones
}

// Sam strumien: mikrofon -> obrobka (Voice.swift) -> bufor -> glosnik/sluchawki.
// Celowo nie jest zwiazany z glownym watkiem: domkniecia ponizej graja na watku audio.
final class AudioGraph {
    private let knobs: Knobs
    private let meters: Meters
    private let ring = Ring(capacity: 16384)
    private let mono = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    private(set) var engine: AVAudioEngine?

    init(knobs: Knobs, meters: Meters) {
        self.knobs = knobs
        self.meters = meters
        mono.initialize(repeating: 0, count: 8192)
    }

    deinit { mono.deallocate() }

    func start() throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else { throw HearError.noInput }

        let rate = hw.sampleRate
        guard let inFmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: hw.channelCount),
              let outFmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
        else { throw HearError.noInput }

        let dsp = VoiceDSP(rate: Float(rate), knobs: knobs, meters: meters)
        let ring = self.ring
        let mono = self.mono
        ring.skip(ring.available)
        ring.prefill(512)

        // wejscie: bierzemy probki z mikrofonu i oddajemy do obrobki
        let sink = AVAudioSinkNode { _, frames, list in
            let bufs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            let n = Int(frames)
            guard n > 0, let first = bufs.first,
                  let d0 = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            if bufs.count > 1, let d1 = bufs[1].mData?.assumingMemoryBound(to: Float.self) {
                // dwa kanaly: usredniamy
                var done = 0
                while done < n {
                    let m = min(8192, n - done)
                    for i in 0..<m { mono[i] = 0.5 * (d0[done + i] + d1[done + i]) }
                    dsp.process(mono, m, into: ring)
                    done += m
                }
            } else {
                dsp.process(d0, n, into: ring)
            }
            return noErr
        }

        // wyjscie: oddajemy gotowe probki, a jak zabraknie, cisza
        let src = AVAudioSourceNode(format: outFmt) { _, _, frames, list in
            let bufs = UnsafeMutableAudioBufferListPointer(list)
            let n = Int(frames)
            // opoznienie ma nie rosnac: jak sie nazbieralo, wyrzucamy najstarsze
            let extra = ring.available - 2048
            if extra > 0 { ring.skip(extra) }
            guard let first = bufs.first,
                  let d0 = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let got = ring.read(d0, n)
            if got < n { for i in got..<n { d0[i] = 0 } }
            if bufs.count > 1 {
                for j in 1..<bufs.count {
                    if let dj = bufs[j].mData { memcpy(dj, d0, n * MemoryLayout<Float>.size) }
                }
            }
            return noErr
        }

        engine.attach(sink)
        engine.attach(src)
        engine.connect(input, to: sink, format: inFmt)
        engine.connect(src, to: engine.mainMixerNode, format: outFmt)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        engine?.stop()
        engine = nil
        meters.clear()
    }
}

// ------------------------------------------------------------------ sesja i stan apki

struct Notice: Equatable {
    enum Action { case none, settings }
    var symbol: String
    var text: String
    var action: Action = .none
}

struct HearRoute: Equatable {
    var name: String
    var symbol: String
    var ok: Bool
    static let none = HearRoute(name: "Brak słuchawek", symbol: "headphones", ok: false)
}

extension MicSide {
    var orientation: AVAudioSession.Orientation? {
        switch self {
        case .auto: return nil
        case .bottom: return .bottom
        case .front: return .front
        case .back: return .back
        }
    }
}

@MainActor
final class HearEngine: ObservableObject {
    enum State { case idle, starting, running }

    @Published private(set) var state: State = .idle
    @Published private(set) var route = HearRoute.none
    @Published private(set) var notice: Notice?

    let knobs = Knobs()
    let meters = Meters()

    private var graph: AudioGraph?
    private var bag = Set<AnyCancellable>()
    private var resumeAfterInterruption = false
    private var restartTask: Task<Void, Never>?

    var running: Bool { state == .running }

    // tylko sluchawki: z glosnika telefonu mikrofon od razu by zapiszczal
    private static let headphoneTypes: Set<AVAudioSession.Port> = [
        .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio,
    ]

    init() {
        let nc = NotificationCenter.default
        nc.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.routeChanged(n) }
            .store(in: &bag)
        nc.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.interrupted(n) }
            .store(in: &bag)
        nc.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.mediaReset() }
            .store(in: &bag)
        nc.publisher(for: .AVAudioEngineConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.engineChanged() }
            .store(in: &bag)

        setupRemote()
        refreshRoute()
    }

    func apply(_ t: Tuning) {
        knobs.gainDB = Float(t.gain)
        knobs.denoise = Float(t.denoise)
        knobs.clarity = Float(t.clarity)
        knobs.auto = t.auto
    }

    func toggle() {
        state == .idle ? start() : stop()
    }

    func dismissNotice() { notice = nil }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // ---------------------------------------------------------- start i stop

    func start() {
        guard state == .idle else { return }
        notice = nil
        state = .starting
        Task { await begin() }
    }

    private func begin() async {
        let app = AVAudioApplication.shared
        var granted = app.recordPermission == .granted
        if app.recordPermission == .undetermined {
            granted = await AVAudioApplication.requestRecordPermission()
        }
        guard state == .starting else { return }   // ktos w miedzyczasie zrezygnowal
        guard granted else {
            fail(Notice(symbol: "mic.slash.fill",
                        text: "Brak dostępu do mikrofonu. Włącz go w Ustawieniach.",
                        action: .settings))
            return
        }

        let s = AVAudioSession.sharedInstance()
        do {
            // tryb domyslny zostawia systemowe wzmocnienie mikrofonu (measurement dawal za cichy sygnal)
            do {
                try s.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP])
            } catch {
                try s.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP])
            }
            try? s.setPreferredSampleRate(48000)
            try? s.setPreferredIOBufferDuration(0.005)
            try s.setActive(true)
            applyMic()
            refreshRoute()
            guard route.ok else { throw HearError.noHeadphones }

            let g = AudioGraph(knobs: knobs, meters: meters)
            try g.start()
            graph = g
            state = .running
            nowPlaying(true)
        } catch HearError.noHeadphones {
            fail(Notice(symbol: "headphones",
                        text: "Podłącz słuchawki. Bez nich mikrofon od razu by zapiszczał."))
        } catch {
            fail(Notice(symbol: "exclamationmark.triangle.fill",
                        text: "Nie udało się uruchomić dźwięku. Spróbuj jeszcze raz."))
        }
    }

    private func fail(_ n: Notice) {
        graph?.stop()
        graph = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        nowPlaying(false)
        state = .idle
        notice = n
    }

    func stop(notice n: Notice? = nil) {
        restartTask?.cancel()
        graph?.stop()
        graph = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        nowPlaying(false)
        state = .idle
        notice = n
    }

    // ---------------------------------------------------------- trasa dzwieku

    func refreshRoute() {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let p = outs.first(where: { Self.headphoneTypes.contains($0.portType) }) else {
            route = .none
            return
        }
        var symbol = "headphones"
        if p.portName.localizedCaseInsensitiveContains("airpods pro") {
            symbol = "airpodspro"
        } else if p.portName.localizedCaseInsensitiveContains("airpods") {
            symbol = "airpods"
        }
        route = HearRoute(name: p.portName, symbol: symbol, ok: true)
    }

    private func routeChanged(_ n: Notification) {
        refreshRoute()
        if state == .running && !route.ok {
            stop(notice: Notice(symbol: "headphones",
                                text: "Słuchawki odłączone. Wyłączyłem słuchanie, żeby nie piszczało."))
        }
    }

    // System sam zatrzymuje silnik przy zmianie trasy albo czestotliwosci. Podnosimy go po chwili.
    private func engineChanged() {
        guard state == .running else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, self.state == .running else { return }
            self.refreshRoute()
            do {
                try self.graph?.start()
            } catch {
                self.stop(notice: Notice(symbol: "exclamationmark.triangle.fill",
                                         text: "Dźwięk się przerwał. Włącz słuchanie jeszcze raz."))
            }
        }
    }

    private func mediaReset() {
        guard state != .idle else { return }
        stop(notice: Notice(symbol: "exclamationmark.triangle.fill",
                            text: "System zrestartował dźwięk. Włącz słuchanie jeszcze raz."))
    }

    private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            guard state != .idle else { return }
            resumeAfterInterruption = true
            stop(notice: Notice(symbol: "phone.fill",
                                text: "Przerwane, np. rozmową albo Siri. Wrócę, gdy się skończy."))
        case .ended:
            let raw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let opts = AVAudioSession.InterruptionOptions(rawValue: raw)
            if resumeAfterInterruption && opts.contains(.shouldResume) {
                resumeAfterInterruption = false
                start()
            }
        @unknown default:
            break
        }
    }

    // ---------------------------------------------------------- mikrofon

    // Zawsze mikrofon telefonu (nie ten z przewodowych sluchawek, bo ten jest przy ustach),
    // a w nim wybrany kierunek i wzor zbierania.
    func applyMic() {
        let s = AVAudioSession.sharedInstance()
        let d = UserDefaults.standard
        let side = MicSide(rawValue: d.string(forKey: "micSide") ?? "") ?? .auto
        let directional = d.object(forKey: "micDirectional") as? Bool ?? true

        guard let mic = s.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        try? s.setPreferredInput(mic)

        guard let wanted = side.orientation,
              let src = mic.dataSources?.first(where: { $0.orientation == wanted }) else {
            try? mic.setPreferredDataSource(nil)
            return
        }
        try? mic.setPreferredDataSource(src)
        let pattern: AVAudioSession.PolarPattern = directional ? .cardioid : .omnidirectional
        if src.supportedPolarPatterns?.contains(pattern) == true {
            try? src.setPreferredPolarPattern(pattern)
        }
    }

    // ---------------------------------------------------------- ekran blokady

    private func setupRemote() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.start() }
            return .success
        }
        rc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
    }

    private func nowPlaying(_ on: Bool) {
        let c = MPNowPlayingInfoCenter.default()
        if on {
            c.nowPlayingInfo = [
                MPMediaItemPropertyTitle: "HearNow",
                MPMediaItemPropertyArtist: "Słucham na żywo",
                MPNowPlayingInfoPropertyIsLiveStream: true,
            ]
            c.playbackState = .playing
        } else {
            c.playbackState = .stopped
            c.nowPlayingInfo = nil
        }
    }
}
