import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum Theme {
    // zloto agenta
    static let gold = Color(red: 0.88, green: 0.72, blue: 0.30)

    static func pad(_ slot: Int) -> Color {
        Color(hue: (0.02 + Double(slot) * 0.057).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 1)
    }
}

enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .rigid, _ intensity: CGFloat = 1) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.impactOccurred(intensity: intensity)
    }

    static func ok() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// ------------------------------------------------------------------ pady

enum PadMode: String, Codable, CaseIterable, Identifiable {
    case shot, loop, hold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shot: return "Jednorazowy"
        case .loop: return "Pętla"
        case .hold: return "Dopóki trzymasz"
        }
    }

    var symbol: String {
        switch self {
        case .shot: return "play.fill"
        case .loop: return "repeat"
        case .hold: return "hand.tap.fill"
        }
    }
}

struct PadConfig: Codable, Equatable {
    var sound: String               // pusty napis = nic nie przypisano
    var mode: PadMode = .shot
    var volume: Double = 0.9
    var pitch: Double = 0           // poltony
}

@MainActor
final class PadsModel: ObservableObject {
    static let perBank = 16
    static let banks = 2

    @Published var pads: [PadConfig] { didSet { save() } }
    @Published var bank = 0
    @Published var editing = false

    let hub: AudioHub
    let store: SoundStore

    init(hub: AudioHub, store: SoundStore) {
        self.hub = hub
        self.store = store
        if let d = UserDefaults.standard.data(forKey: "pads"),
           let p = try? JSONDecoder().decode([PadConfig].self, from: d),
           p.count == Self.perBank * Self.banks {
            pads = p
        } else {
            var p = Synth.builtins.map { PadConfig(sound: "builtin:" + $0.id) }
            // dlugie dzwieki od razu jako petle
            for i in p.indices where ["builtin:siren", "builtin:alarm", "builtin:drop"].contains(p[i].sound) {
                p[i].mode = .loop
            }
            p += [PadConfig](repeating: PadConfig(sound: ""), count: Self.perBank)
            pads = p
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(pads) { UserDefaults.standard.set(d, forKey: "pads") }
    }

    func global(_ slot: Int) -> Int { bank * Self.perBank + slot }
    func config(_ slot: Int) -> PadConfig { pads[global(slot)] }

    func press(_ slot: Int) {
        let g = global(slot)
        let c = pads[g]
        guard !c.sound.isEmpty, let buf = store.buffer(c.sound) else { return }
        let ratio = pow(2, c.pitch / 12)
        switch c.mode {
        case .shot:
            hub.mixer.play(buf, tag: g, gain: Float(c.volume), ratio: ratio)
        case .loop:
            if hub.mixer.isPlaying(tag: g) {
                hub.mixer.stop(tag: g)
            } else {
                hub.mixer.play(buf, tag: g, gain: Float(c.volume), loop: true, ratio: ratio)
            }
        case .hold:
            hub.mixer.play(buf, tag: g, gain: Float(c.volume), loop: true, ratio: ratio)
        }
    }

    func release(_ slot: Int) {
        let g = global(slot)
        if pads[g].mode == .hold { hub.mixer.release(tag: g) }
    }

    func isPlaying(_ slot: Int) -> Bool { hub.mixer.isPlaying(tag: global(slot)) }
    func progress(_ slot: Int) -> Float? { hub.mixer.progress(tag: global(slot)) }

    func assign(_ slot: Int, sound: String) {
        pads[global(slot)].sound = sound
    }

    func clear(_ slot: Int) {
        hub.mixer.stop(tag: global(slot))
        pads[global(slot)] = PadConfig(sound: "")
    }

    func stopAll() { hub.mixer.stopAll() }
}

// ------------------------------------------------------------------ looper

struct LoopSnap: Equatable {
    var state: LooperCore.State = .empty
    var seconds: Double = 0
    var beats = 0
    var layers: [(gain: Float, muted: Bool)] = []

    static func == (a: LoopSnap, b: LoopSnap) -> Bool {
        a.state == b.state && a.seconds == b.seconds && a.beats == b.beats
            && a.layers.count == b.layers.count
            && zip(a.layers, b.layers).allSatisfy { $0.gain == $1.gain && $0.muted == $1.muted }
    }
}

@MainActor
final class LooperModel: ObservableObject {
    @Published private(set) var snap = LoopSnap()
    @Published private(set) var wave = [Float](repeating: 0, count: 96)
    @Published var source: LooperCore.Source = .mic { didSet { push() } }
    @Published var bpm = 100.0 { didSet { push() } }
    @Published var metronome = false { didSet { push() } }
    @Published var quantize = true { didSet { push() } }
    @Published var inputGain = 1.0 { didSet { push() } }
    @Published var recordingLevel: Float = 0
    @Published var exported: URL?

    let hub: AudioHub
    private var timer: Timer?

    init(hub: AudioHub) { self.hub = hub }

    func appear() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        push()
    }

    func disappear() {
        timer?.invalidate()
        timer = nil
    }

    private func push() {
        let (s, b, m, q, g) = (source, bpm, metronome, quantize, Float(inputGain))
        hub.mixer.loop { l in
            l.source = s
            l.bpm = b
            l.quantize = q
            l.inputGain = g
        }
        hub.mixer.setMetronome(on: m, bpm: b, volume: 0.5)
    }

    func refresh() {
        let n: LoopSnap = hub.mixer.loop { l in
            LoopSnap(state: l.state, seconds: l.seconds, beats: l.beats,
                     layers: l.layers.filter { $0.used }.map { ($0.gain, $0.muted) })
        }
        if n != snap {
            let was = snap.state
            snap = n
            if was != n.state || n.layers.count != 0 { wave = hub.mixer.loopWaveform(bins: 96) }
        }
        if n.state == .recordingFirst || n.state == .overdubbing {
            recordingLevel = source == .mic ? min(1, hub.mixer.levels.mic * 6) : min(1, hub.mixer.levels.out * 1.5)
        } else {
            recordingLevel = 0
        }
    }

    var recSeconds: Double { hub.mixer.loop { Double($0.length) / $0.rate } }

    // glowny przycisk: nagraj -> stop -> dogrywaj
    func mainTap() async {
        switch snap.state {
        case .empty:
            if source == .mic {
                guard await hub.useMic("looper") else { return }
            }
            hub.mixer.resetMicFifo()
            hub.mixer.loop { $0.startFirst() }
            Haptics.tap(.heavy)
        case .recordingFirst:
            hub.mixer.loop { $0.stopFirst() }
            Haptics.ok()
        case .playing, .stopped:
            if source == .mic {
                guard await hub.useMic("looper") else { return }
            }
            hub.mixer.loop { $0.startOverdub() }
            Haptics.tap(.medium)
        case .overdubbing:
            hub.mixer.loop { $0.stopOverdub() }
            Haptics.ok()
        }
        refresh()
        wave = hub.mixer.loopWaveform(bins: 96)
    }

    func togglePlay() {
        hub.mixer.loop { $0.togglePlay() }
        refresh()
    }

    func undo() {
        hub.mixer.loop { $0.undo() }
        refresh()
        wave = hub.mixer.loopWaveform(bins: 96)
    }

    func clear() {
        hub.mixer.loop { $0.clearAll() }
        hub.releaseMic("looper")
        refresh()
        wave = [Float](repeating: 0, count: 96)
    }

    func setGain(_ i: Int, _ v: Float) {
        hub.mixer.loop { l in
            let used = l.layers.filter { $0.used }
            if i < used.count { used[i].gain = v }
        }
        refresh()
    }

    func toggleMute(_ i: Int) {
        hub.mixer.loop { l in
            let used = l.layers.filter { $0.used }
            if i < used.count { used[i].muted.toggle() }
        }
        refresh()
        wave = hub.mixer.loopWaveform(bins: 96)
    }

    func progress() -> Float { hub.mixer.loop { $0.progress } }

    // zgrywa petle do jednego pliku WAV (do wyslania, np. AirDropem). Wola to dopiero udostepnianie.
    func export() -> URL? {
        guard let b = hub.mixer.loopMixdown() else { return nil }
        let out = b.normalized(0.9)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Petla-7Tools.wav")
        do {
            try WAV.encode(out).write(to: u)
            return u
        } catch { return nil }
    }

    func saveToLibrary(_ store: SoundStore) -> Bool {
        guard let b = hub.mixer.loopMixdown() else { return false }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        store.add(b, name: "Pętla " + f.string(from: Date()))
        return true
    }
}

// ------------------------------------------------------------------ sampler

@MainActor
final class SamplerModel: ObservableObject {
    @Published var soundID: String = UserDefaults.standard.string(forKey: "sampler.sound") ?? "builtin:twang" {
        didSet { UserDefaults.standard.set(soundID, forKey: "sampler.sound"); reload() }
    }
    @Published var reverse = false { didSet { reload() } }
    @Published var trimStart = 0.0
    @Published var trimEnd = 1.0
    @Published var root = 60
    @Published var attack = 0.005
    @Published var release = 0.25
    @Published var sustainLoop = false
    @Published var chop = false
    @Published private(set) var buffer: SampleBuffer?
    @Published private(set) var wave: [Float] = []

    let hub: AudioHub
    let store: SoundStore

    init(hub: AudioHub, store: SoundStore) {
        self.hub = hub
        self.store = store
        reload()
    }

    func reload() {
        guard var b = store.buffer(soundID) else {
            buffer = nil
            wave = []
            return
        }
        if reverse { b = b.reversed() }
        buffer = b
        wave = b.waveform(bins: 120)
    }

    var startFrame: Int { Int(trimStart * Double(buffer?.count ?? 0)) }
    var endFrame: Int { max(startFrame + 1, Int(trimEnd * Double(buffer?.count ?? 0))) }

    func noteOn(_ note: Int) {
        guard let b = buffer else { return }
        let ratio = pow(2, Double(note - root) / 12)
        hub.mixer.play(b, tag: 1000 + note, gain: 0.85, loop: sustainLoop, ratio: ratio,
                       start: startFrame, end: endFrame, attack: attack, release: release)
    }

    func noteOff(_ note: Int) { hub.mixer.release(tag: 1000 + note) }

    // pociete na rowne kawalki, jak w samplerach do chopowania
    static let slices = 16

    func sliceOn(_ k: Int) {
        guard let b = buffer else { return }
        let s = startFrame, e = endFrame
        let len = max(1, (e - s) / Self.slices)
        hub.mixer.play(b, tag: 2000 + k, gain: 0.9, start: s + k * len, end: s + (k + 1) * len,
                       attack: 0.001, release: 0.02)
    }
}

// ------------------------------------------------------------------ udostepnianie (AirDrop i reszta)

// Plik powstaje dopiero, gdy ktos naprawde wybierze udostepnianie, a nie przy kazdym rysowaniu ekranu.
struct SoundFile: Transferable {
    let id: String
    let store: SoundStore

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .wav) { item in
            guard let u = await MainActor.run(body: { item.store.wavURL(item.id) }) else {
                throw URLError(.fileDoesNotExist)
            }
            return SentTransferredFile(u)
        }
    }
}

struct LoopFile: Transferable {
    let model: LooperModel

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .wav) { item in
            guard let u = await MainActor.run(body: { item.model.export() }) else {
                throw URLError(.fileDoesNotExist)
            }
            return SentTransferredFile(u)
        }
    }
}
