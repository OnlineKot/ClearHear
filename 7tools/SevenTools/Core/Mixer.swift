import Foundation

// Cala apka gra przez jeden mikser: pady, klawisze samplera, looper, metronom, generator tonu.
// UI wola metody z glownego watku, watek audio wola render() i capture().
// Wszystko pod jedna blokada. Watek audio nie czeka na nia (tryLock), a trzymana jest bardzo krotko.
final class Mixer {
    struct Voice {
        var buf: SampleBuffer?
        var pos: Double = 0
        var step: Double = 1
        var gain: Float = 1
        var loop = false
        var start = 0
        var end = 0
        var tag = 0
        var phase = 0          // 0 wolny, 1 narasta, 2 trzyma, 3 opada
        var env: Float = 0
        var up: Float = 0.01
        var down: Float = 0.01
        var age = 0
    }

    struct Tone {
        var on = false
        var wave = 0           // 0 sinus, 1 prostokat, 2 pila, 3 trojkat, 4 bialy szum, 5 rozowy szum
        var f1 = 440.0
        var f2 = 440.0
        var sweep = 0.0        // sekundy w jedna strone, 0 = bez przemiatania
        var gain: Float = 0.2
        var phase = 0.0
        var t = 0.0
        var env: Float = 0
        var pink: (Float, Float, Float) = (0, 0, 0)
    }

    static let maxVoices = 40
    static let block = 4096

    let rate: Double
    let looper: LooperCore
    private let lock = NSLock()

    private var voices = [Voice](repeating: Voice(), count: Mixer.maxVoices)
    private var age = 0
    private var tone = Tone()
    private var noise = Noise()

    private let bus = UnsafeMutablePointer<Float>.allocate(capacity: Mixer.block)
    private let rec = UnsafeMutablePointer<Float>.allocate(capacity: Mixer.block)

    // mikrofon: kolejka dla looplera i okno do stroika
    private let fifo = UnsafeMutablePointer<Float>.allocate(capacity: 32768)
    private var fifoR = 0
    private var fifoW = 0
    private let tap = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    private var tapW = 0

    // "Sluchaj" (dawne HearNow): mikrofon -> odszumianie i podbicie glosu -> do wyjscia
    let listenKnobs = Knobs()
    let listenMeters = Meters()
    private let listenDSP: VoiceDSP
    private let listenRing = Ring(capacity: 16384)
    private var listenOn = false

    // nagrywanie wlasnego sampla (max 30 s)
    private let recBuf = UnsafeMutablePointer<Float>.allocate(capacity: 48000 * 30)
    private var recLen = 0
    private var recOn = false

    // metronom
    private var metroOn = false
    private var metroBpm = 100.0
    private var metroVol: Float = 0.5
    private var metroPos = 0.0
    private var metroBeat = 0

    // poziomy
    private var outPeak: Float = 0
    private var micRms: Float = 0
    private var micPeak: Float = 0
    private var limiter: Float = 1

    var masterGain: Float = 0.9

    init(rate: Double = 48000) {
        self.rate = rate
        looper = LooperCore(rate: rate)
        listenDSP = VoiceDSP(rate: Float(rate), knobs: listenKnobs, meters: listenMeters)
        bus.initialize(repeating: 0, count: Mixer.block)
        rec.initialize(repeating: 0, count: Mixer.block)
        fifo.initialize(repeating: 0, count: 32768)
        tap.initialize(repeating: 0, count: 8192)
        recBuf.initialize(repeating: 0, count: 48000 * 30)
    }

    deinit {
        bus.deallocate()
        rec.deallocate()
        fifo.deallocate()
        tap.deallocate()
        recBuf.deallocate()
    }

    private func locked<T>(_ f: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return f()
    }

    // ================================================================ glosy (UI)

    // ratio = zmiana wysokosci (2 = oktawa wyzej). start/end to zakres w probkach buforu.
    func play(_ buf: SampleBuffer, tag: Int, gain: Float = 1, loop: Bool = false, ratio: Double = 1,
              start: Int = 0, end: Int? = nil, attack: Double = 0.003, release: Double = 0.03) {
        locked {
            // ten sam tag gra juz? wygaszamy go szybko i startujemy od nowa
            for i in voices.indices where voices[i].phase != 0 && voices[i].tag == tag {
                voices[i].phase = 3
                voices[i].down = Float(1 / (rate * 0.006))
            }
            var slot = voices.firstIndex { $0.phase == 0 }
            if slot == nil {
                slot = voices.indices.min { voices[$0].age < voices[$1].age }
            }
            guard let i = slot else { return }
            age += 1
            let s = max(0, min(buf.count - 1, start))
            let e = max(s + 1, min(buf.count, end ?? buf.count))
            voices[i] = Voice(buf: buf, pos: Double(s), step: ratio * buf.rate / rate, gain: gain, loop: loop,
                              start: s, end: e, tag: tag, phase: 1, env: 0,
                              up: Float(1 / max(1, rate * attack)), down: Float(1 / max(1, rate * release)), age: age)
        }
    }

    // pusc klawisz: glos opada zgodnie ze swoim czasem release
    func release(tag: Int) {
        locked {
            for i in voices.indices where voices[i].phase != 0 && voices[i].phase != 3 && voices[i].tag == tag {
                voices[i].phase = 3
            }
        }
    }

    func stop(tag: Int) {
        locked {
            for i in voices.indices where voices[i].phase != 0 && voices[i].tag == tag {
                voices[i].phase = 3
                voices[i].down = Float(1 / (rate * 0.01))
            }
        }
    }

    func stopAll() {
        locked {
            for i in voices.indices where voices[i].phase != 0 {
                voices[i].phase = 3
                voices[i].down = Float(1 / (rate * 0.015))
            }
        }
    }

    func isPlaying(tag: Int) -> Bool {
        locked { voices.contains { $0.phase != 0 && $0.phase != 3 && $0.tag == tag } }
    }

    // gdzie jest glos w swoim zakresie, 0...1
    func progress(tag: Int) -> Float? {
        locked {
            guard let v = voices.first(where: { $0.phase != 0 && $0.tag == tag }) else { return nil }
            let len = Double(max(1, v.end - v.start))
            return Float(min(1, max(0, (v.pos - Double(v.start)) / len)))
        }
    }

    var activeVoices: Int { locked { voices.filter { $0.phase != 0 }.count } }

    // ================================================================ generator tonu, metronom (UI)

    func setTone(on: Bool, wave: Int, f1: Double, f2: Double, sweep: Double, gain: Float) {
        locked {
            tone.on = on
            tone.wave = wave
            tone.f1 = f1
            tone.f2 = f2
            tone.sweep = sweep
            tone.gain = min(0.5, gain)   // twardy sufit, zeby nie zrobic nikomu krzywdy w uszach
        }
    }

    func setMetronome(on: Bool, bpm: Double, volume: Float) {
        locked {
            metroOn = on
            metroBpm = max(20, min(300, bpm))
            metroVol = volume
        }
    }

    // ================================================================ looper (UI)

    func loop<T>(_ f: (LooperCore) -> T) -> T { locked { f(looper) } }

    func loopWaveform(bins: Int) -> [Float] { locked { looper.waveform(bins: bins) } }

    func loopMixdown() -> SampleBuffer? { locked { looper.mixdown() } }

    // ================================================================ poziomy i okno mikrofonu (UI)

    var levels: (out: Float, mic: Float, micPeak: Float) { locked { (outPeak, micRms, micPeak) } }

    func recentInput(_ n: Int) -> [Float] {
        locked {
            let m = min(n, 8192)
            var out = [Float](repeating: 0, count: m)
            for i in 0..<m { out[i] = tap[(tapW - m + i + 8192 * 2) % 8192] }
            return out
        }
    }

    // sluchanie na zywo
    func setListening(_ on: Bool) {
        locked {
            listenOn = on
            listenRing.skip(listenRing.available)
            if on { listenRing.prefill(512) } else { listenMeters.clear() }
        }
    }

    var isListening: Bool { locked { listenOn } }

    // nagrywanie sampla z mikrofonu
    func startSampleRecording() { locked { recLen = 0; recOn = true } }

    var sampleRecordingSeconds: Double { locked { Double(recLen) / rate } }

    func stopSampleRecording() -> SampleBuffer? {
        locked {
            recOn = false
            let n = recLen
            recLen = 0
            guard n > Int(rate * 0.05) else { return nil }
            let b = SampleBuffer(count: n, rate: rate)
            b.data.update(from: recBuf, count: n)
            return b
        }
    }

    func resetMicFifo() {
        locked {
            fifoR = 0
            fifoW = 0
        }
    }

    // ================================================================ watek audio

    // Mikrofon przyszedl. Zapisujemy do okna stroika i kolejki dla looplera.
    func capture(_ x: UnsafePointer<Float>, _ n: Int) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        var sq: Float = 0
        var pk: Float = 0
        for i in 0..<n {
            tap[tapW] = x[i]
            tapW = (tapW + 1) & 8191
            if fifoW - fifoR >= 32768 { fifoR += 1 }
            fifo[fifoW & 32767] = x[i]
            fifoW += 1
            sq += x[i] * x[i]
            pk = max(pk, abs(x[i]))
            if recOn && recLen < 48000 * 30 {
                recBuf[recLen] = x[i]
                recLen += 1
            }
        }
        if listenOn { listenDSP.process(x, n, into: listenRing) }
        let r = (sq / Float(max(1, n))).squareRoot()
        micRms += 0.5 * (r - micRms)
        micPeak = max(pk, micPeak * 0.97)
        // jak nikt nie czyta kolejki (looper nie slucha mikrofonu), nie pozwol jej rosnac
        if fifoW - fifoR > 16384 { fifoR = fifoW - 4096 }
    }

    // Gra dalej. out ma `frames` probek mono.
    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        guard lock.try() else {
            out.update(repeating: 0, count: frames)
            return
        }
        defer { lock.unlock() }
        var done = 0
        while done < frames {
            let n = min(Mixer.block, frames - done)
            block(out + done, n)
            done += n
        }
    }

    private func block(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        bus.update(repeating: 0, count: n)
        voicesInto(bus, n)
        toneInto(bus, n)

        out.update(repeating: 0, count: n)

        // nagrywanie dla looplera: z mikrofonu albo z tego, co graja pady
        if looper.source == .mic {
            let avail = fifoW - fifoR
            if looper.isRecording {
                for i in 0..<n { rec[i] = i < avail ? fifo[(fifoR + i) & 32767] : 0 }
            }
            fifoR += min(avail, n)
            if looper.isRecording && avail < n { /* brak probek: zera, trudno */ }
            looper.process(play: out, rec: rec, frames: n)
        } else {
            fifoR = fifoW
            looper.process(play: out, rec: bus, frames: n)
        }

        metronomeInto(out, n)
        for i in 0..<n { out[i] += bus[i] }

        // sluchanie: opoznienie ma nie rosnac, wiec nadmiar wyrzucamy
        if listenOn {
            let extra = listenRing.available - 2048
            if extra > 0 { listenRing.skip(extra) }
            let got = listenRing.read(rec, n)
            for i in 0..<got { out[i] += rec[i] }
        } else if listenRing.available > 0 {
            listenRing.skip(listenRing.available)
        }

        // glosnosc i miekki limiter
        var pk: Float = 0
        for i in 0..<n {
            var y = out[i] * masterGain
            let a = abs(y)
            if a > 0.85 {
                let over = (a - 0.85) / 0.15
                let soft = 0.85 + 0.15 * tanhf(over)
                y = y < 0 ? -soft : soft
            }
            out[i] = y
            pk = max(pk, abs(y))
        }
        outPeak = max(pk, outPeak * 0.95)
    }

    private func voicesInto(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        for vi in voices.indices where voices[vi].phase != 0 {
            guard let buf = voices[vi].buf else { voices[vi].phase = 0; continue }
            let d = buf.data
            var pos = voices[vi].pos
            let step = voices[vi].step
            let gain = voices[vi].gain
            let loop = voices[vi].loop
            let start = voices[vi].start
            let end = voices[vi].end
            let up = voices[vi].up
            let down = voices[vi].down
            var env = voices[vi].env
            var phase = voices[vi].phase
            let span = Double(end - start)

            for i in 0..<n {
                if phase == 1 {
                    env += up
                    if env >= 1 { env = 1; phase = 2 }
                } else if phase == 3 {
                    env -= down
                    if env <= 0 { phase = 0; break }
                }
                let i0 = Int(pos)
                if i0 >= end - 1 && !loop {
                    // ostatnia probka: konczymy
                    phase = 0
                    break
                }
                var i1 = i0 + 1
                if i1 >= end { i1 = loop ? start : end - 1 }
                let f = Float(pos - Double(i0))
                let s = d[i0] * (1 - f) + d[i1] * f
                out[i] += s * gain * env
                pos += step
                if pos >= Double(end) {
                    if loop { pos -= span } else { phase = 0; break }
                }
            }
            voices[vi].pos = pos
            voices[vi].env = env
            voices[vi].phase = phase
        }
    }

    private func toneInto(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        if !tone.on && tone.env <= 0.0001 { return }
        let target: Float = tone.on ? tone.gain : 0
        for i in 0..<n {
            tone.env += (target - tone.env) * 0.002
            var f = tone.f1
            if tone.sweep > 0 {
                let p = (tone.t / tone.sweep).truncatingRemainder(dividingBy: 2)
                let k = p < 1 ? p : 2 - p
                f = tone.f1 * pow(tone.f2 / tone.f1, k)
            }
            tone.t += 1 / rate
            tone.phase += f / rate
            tone.phase -= tone.phase.rounded(.down)
            let p = Float(tone.phase)
            var s: Float
            switch tone.wave {
            case 1: s = p < 0.5 ? 0.7 : -0.7
            case 2: s = (p * 2 - 1) * 0.7
            case 3: s = (abs(p * 4 - 2) - 1) * 0.9
            case 4: s = noise.next() * 0.6
            case 5:
                let w = noise.next()
                tone.pink.0 = 0.99765 * tone.pink.0 + w * 0.099046
                tone.pink.1 = 0.963 * tone.pink.1 + w * 0.2965164
                tone.pink.2 = 0.57 * tone.pink.2 + w * 1.0526913
                s = (tone.pink.0 + tone.pink.1 + tone.pink.2 + w * 0.1848) * 0.25
            default: s = sinf(2 * .pi * p)
            }
            out[i] += s * tone.env
        }
    }

    private func metronomeInto(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        guard metroOn else { return }
        let beatLen = rate * 60 / metroBpm
        let clickLen = Int(rate * 0.03)
        let aligned = looper.length > 0 && looper.beats > 0 && (looper.state == .playing || looper.state == .overdubbing)
        for i in 0..<n {
            var inBeat: Int
            var beat: Int
            if aligned {
                // przy petli metronom idzie za glowica, wiec uderzenia pasuja do nagrania
                let h = Double(looper.head + i)
                beat = Int(h / beatLen) % 4
                inBeat = Int(h.truncatingRemainder(dividingBy: beatLen))
            } else {
                inBeat = Int(metroPos)
                beat = metroBeat
                metroPos += 1
                if metroPos >= beatLen {
                    metroPos -= beatLen
                    metroBeat = (metroBeat + 1) % 4
                }
            }
            if inBeat < clickLen {
                let f: Float = beat == 0 ? 1500 : 1000
                let e = expf(-Float(inBeat) / Float(rate * 0.006))
                out[i] += sinf(2 * .pi * f * Float(inBeat) / Float(rate)) * e * metroVol
            }
        }
    }
}
