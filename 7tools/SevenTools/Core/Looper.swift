import Foundation

// Looper: pierwsza warstwa ustala dlugosc petli, kolejne dogrywasz na wierzch.
// Nie ma tu blokad, wywoluje to Mixer pod swoja blokada.
final class LooperCore {
    enum State { case empty, recordingFirst, playing, overdubbing, stopped }
    enum Source { case mic, pads }

    final class Layer {
        let data: UnsafeMutablePointer<Float>
        let capacity: Int
        var gain: Float = 1
        var muted = false
        var used = false
        var dirty = 0          // ile poczatkowych probek moze byc niezerowych

        init(capacity: Int) {
            self.capacity = capacity
            data = .allocate(capacity: capacity)
            data.initialize(repeating: 0, count: capacity)
        }

        deinit { data.deallocate() }

        func wipe() {
            if dirty > 0 { data.update(repeating: 0, count: min(dirty, capacity)) }
            dirty = 0
            used = false
            gain = 1
            muted = false
        }
    }

    static let maxLayers = 8

    let rate: Double
    let maxFrames: Int
    private(set) var layers: [Layer]
    private(set) var state: State = .empty
    private(set) var length = 0
    private(set) var head = 0
    private var recPos = 0
    private var active = -1

    var source: Source = .mic
    var latencyFrames = 0
    var inputGain: Float = 1
    var bpm: Double = 100
    var quantize = true
    private(set) var beats = 0     // ile uderzen metronomu miesci petla, 0 = nie wiadomo

    // do petli audio: wskazniki warstw zebrane raz na blok, zeby nie ruszac licznikow referencji w kazdej probce
    private let ptrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: LooperCore.maxLayers)
    private let gains = UnsafeMutablePointer<Float>.allocate(capacity: LooperCore.maxLayers)

    deinit {
        ptrs.deallocate()
        gains.deallocate()
    }

    init(rate: Double, seconds: Double = 40) {
        self.rate = rate
        maxFrames = Int(rate * seconds)
        layers = (0..<LooperCore.maxLayers).map { _ in Layer(capacity: Int(rate * seconds)) }
    }

    var layerCount: Int { layers.filter { $0.used }.count }
    var seconds: Double { Double(length) / rate }
    var isRecording: Bool { state == .recordingFirst || state == .overdubbing }
    var progress: Float { length > 0 ? Float(head) / Float(length) : 0 }

    // ---------------------------------------------------------------- sterowanie

    func startFirst() {
        clearAll()
        recPos = 0
        active = 0
        layers[0].dirty = maxFrames
        state = .recordingFirst
    }

    func stopFirst() {
        guard state == .recordingFirst else { return }
        var len = recPos
        beats = 0
        if quantize && bpm > 20 && len > Int(rate * 0.3) {
            let beatLen = rate * 60 / bpm
            let b = max(1, Int((Double(len) / beatLen).rounded()))
            len = min(maxFrames, Int(Double(b) * beatLen))
            beats = Int(Double(len) / beatLen + 0.5)
        }
        guard len > Int(rate * 0.05) else { clearAll(); return }
        length = len
        // zero za koncem nagrania, i krotkie wygaszenie na szwie
        if len > recPos { for i in recPos..<len { layers[0].data[i] = 0 } }
        let f = min(len / 4, Int(rate * 0.004))
        for i in 0..<f {
            let g = Float(i) / Float(f)
            layers[0].data[i] *= g
            layers[0].data[len - 1 - i] *= g
        }
        layers[0].used = true
        layers[0].dirty = len
        head = 0
        active = -1
        state = .playing
    }

    func startOverdub() {
        guard state == .playing || state == .stopped, length > 0 else { return }
        guard let i = layers.indices.first(where: { !layers[$0].used }) else { return }
        layers[i].wipe()
        layers[i].dirty = length
        layers[i].used = true
        active = i
        state = .overdubbing
    }

    func stopOverdub() {
        guard state == .overdubbing, active >= 0 else { return }
        layers[active].used = true
        active = -1
        state = .playing
    }

    func togglePlay() {
        if state == .playing { state = .stopped } else if state == .stopped { head = 0; state = .playing }
    }

    // cofa ostatnia warstwe; po ostatniej czysci wszystko
    func undo() {
        if state == .overdubbing, active >= 0 {
            layers[active].wipe()
            active = -1
            state = .playing
            return
        }
        guard let last = layers.indices.last(where: { layers[$0].used }) else { return }
        layers[last].wipe()
        if layerCount == 0 { clearAll() }
    }

    func clearAll() {
        for l in layers { l.wipe() }
        state = .empty
        length = 0
        head = 0
        recPos = 0
        active = -1
        beats = 0
    }

    // ---------------------------------------------------------------- dzwiek

    // Gra warstwy do `out` (dodaje) i nagrywa z `rec`. Wywolywane co blok audio.
    func process(play out: UnsafeMutablePointer<Float>, rec: UnsafePointer<Float>, frames n: Int) {
        switch state {
        case .empty, .stopped:
            return
        case .recordingFirst:
            let d = layers[0].data
            for i in 0..<n {
                if recPos >= maxFrames { stopFirst(); return }
                d[recPos] = rec[i] * inputGain
                recPos += 1
            }
        case .playing, .overdubbing:
            var k = 0
            for l in layers where l.used && !l.muted {
                ptrs[k] = l.data
                gains[k] = l.gain
                k += 1
            }
            let target: UnsafeMutablePointer<Float>? = state == .overdubbing && active >= 0 ? layers[active].data : nil
            let lat = source == .mic ? latencyFrames : 0
            var h = head
            let len = length
            for i in 0..<n {
                var s: Float = 0
                for j in 0..<k { s += ptrs[j][h] * gains[j] }
                out[i] += s
                if let t = target {
                    var idx = h - lat
                    while idx < 0 { idx += len }
                    t[idx % len] += rec[i] * inputGain
                }
                h += 1
                if h >= len { h = 0 }
            }
            head = h
        }
    }

    // ---------------------------------------------------------------- podglad i eksport

    func mixdown() -> SampleBuffer? {
        guard length > 0 else { return nil }
        let b = SampleBuffer(count: length, rate: rate)
        for l in layers where l.used && !l.muted {
            for i in 0..<length { b.data[i] += l.data[i] * l.gain }
        }
        return b
    }

    func waveform(bins: Int) -> [Float] {
        guard length > 0 else { return [Float](repeating: 0, count: bins) }
        var out = [Float](repeating: 0, count: bins)
        for k in 0..<bins {
            let s = length * k / bins
            let e = max(s + 1, length * (k + 1) / bins)
            var p: Float = 0
            for i in s..<min(e, length) {
                var v: Float = 0
                for l in layers where l.used && !l.muted { v += l.data[i] * l.gain }
                p = max(p, abs(v))
            }
            out[k] = min(1, p)
        }
        return out
    }
}
