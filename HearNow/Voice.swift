import Foundation

// Odszumianie i podbicie glosu. Sam Swift, bez AVFoundation, zeby ten sam plik dalo sie
// odpalic i sprawdzic na Linuksie (tools/dsp_check.swift).
//
// Droga dzwieku: ramka 1024 probek, co 256 FFT, odjecie szumu (Wiener z "decision directed"),
// krzywa pod glos, bramka miedzy zdaniami, FFT w druga strone, potem poziom, limiter.

// Pokretla z ekranu. UI pisze, watek audio czyta. To pojedyncze floaty, wiec lekki wyscig nie szkodzi.
final class Knobs {
    private let p = UnsafeMutablePointer<Float>.allocate(capacity: 4)

    init() {
        p.initialize(repeating: 0, count: 4)
        gainDB = 9
        denoise = 0.6
        clarity = 0.6
        auto = true
    }

    deinit { p.deallocate() }

    var gainDB: Float { get { p[0] } set { p[0] = newValue } }     // 0...24
    var denoise: Float { get { p[1] } set { p[1] = newValue } }    // 0...1
    var clarity: Float { get { p[2] } set { p[2] = newValue } }    // 0...1
    var auto: Bool { get { p[3] > 0.5 } set { p[3] = newValue ? 1 : 0 } }
}

// Co widac na ekranie: widmo przed i po obrobce oraz poziomy. Pisze audio, czyta UI.
final class Meters {
    static let bands = 32

    let voice = UnsafeMutablePointer<Float>.allocate(capacity: Meters.bands)   // po obrobce, 0...1
    let raw = UnsafeMutablePointer<Float>.allocate(capacity: Meters.bands)     // przed obrobka, 0...1
    private let v = UnsafeMutablePointer<Float>.allocate(capacity: 4)

    init() {
        voice.initialize(repeating: 0, count: Meters.bands)
        raw.initialize(repeating: 0, count: Meters.bands)
        v.initialize(repeating: 0, count: 4)
    }

    deinit {
        voice.deallocate()
        raw.deallocate()
        v.deallocate()
    }

    var outLevel: Float { get { v[0] } set { v[0] = newValue } }    // RMS na wyjsciu
    var inLevel: Float { get { v[1] } set { v[1] = newValue } }     // RMS na wejsciu
    var speech: Float { get { v[2] } set { v[2] = newValue } }      // 0...1, czy slychac glos
    var reduction: Float { get { v[3] } set { v[3] = newValue } }   // ile dB odjeto, srednio

    func clear() {
        voice.update(repeating: 0, count: Meters.bands)
        raw.update(repeating: 0, count: Meters.bands)
        v.update(repeating: 0, count: 4)
    }
}

// Zwykle FFT radix-2 na dwoch tablicach (czesc rzeczywista i urojona). Bez skalowania.
final class FFT {
    let n: Int
    private let cosT: UnsafeMutablePointer<Float>
    private let sinT: UnsafeMutablePointer<Float>
    private let rev: UnsafeMutablePointer<Int32>

    init(_ n: Int) {
        precondition(n >= 4 && n & (n - 1) == 0)
        self.n = n
        cosT = .allocate(capacity: n / 2)
        sinT = .allocate(capacity: n / 2)
        rev = .allocate(capacity: n)
        for k in 0..<n / 2 {
            let a = 2.0 * Double.pi * Double(k) / Double(n)
            cosT[k] = Float(cos(a))
            sinT[k] = Float(sin(a))
        }
        var bits = 0
        while (1 << bits) < n { bits += 1 }
        for i in 0..<n {
            var r = 0
            var x = i
            for _ in 0..<bits {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            rev[i] = Int32(r)
        }
    }

    deinit {
        cosT.deallocate()
        sinT.deallocate()
        rev.deallocate()
    }

    func forward(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>) {
        run(re, im, -1)
    }

    // po forward i inverse wychodzi n razy wiecej niz weszlo
    func inverse(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>) {
        run(re, im, 1)
    }

    private func run(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>, _ sign: Float) {
        for i in 0..<n {
            let j = Int(rev[i])
            if j > i {
                let tr = re[i]; re[i] = re[j]; re[j] = tr
                let ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var size = 2
        while size <= n {
            let half = size / 2
            let step = n / size
            var start = 0
            while start < n {
                var k = 0
                for j in start..<start + half {
                    let wr = cosT[k]
                    let wi = sign * sinT[k]
                    let l = j + half
                    let tr = re[l] * wr - im[l] * wi
                    let ti = re[l] * wi + im[l] * wr
                    re[l] = re[j] - tr
                    im[l] = im[j] - ti
                    re[j] += tr
                    im[j] += ti
                    k += step
                }
                start += size
            }
            size <<= 1
        }
    }
}

final class VoiceDSP {
    static let n = 1024
    static let hop = 256
    static let bins = n / 2 + 1

    private let n = VoiceDSP.n
    private let hop = VoiceDSP.hop
    private let nb = VoiceDSP.bins
    private let rate: Float
    private let knobs: Knobs
    private let meters: Meters
    private let fft = FFT(VoiceDSP.n)

    // bufory, wszystko zaalokowane raz
    private let win: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let ola: UnsafeMutablePointer<Float>
    private let re: UnsafeMutablePointer<Float>
    private let im: UnsafeMutablePointer<Float>
    private let hopIn: UnsafeMutablePointer<Float>
    private let hopOut: UnsafeMutablePointer<Float>
    private let ps: UnsafeMutablePointer<Float>       // wygladzona moc
    private let noise: UnsafeMutablePointer<Float>    // sledzony szum
    private let hold: UnsafeMutablePointer<Float>     // jak dlugo bin jest wysoko ponad szumem
    private let aprev: UnsafeMutablePointer<Float>    // z poprzedniej ramki, do decision directed
    private let gain: UnsafeMutablePointer<Float>
    private let wgt: UnsafeMutablePointer<Float>      // krzywa pod glos
    private let bandOf: UnsafeMutablePointer<Int32>   // do ktorego slupka widma nalezy bin
    private let accOut: UnsafeMutablePointer<Float>
    private let accRaw: UnsafeMutablePointer<Float>
    private let accN: UnsafeMutablePointer<Float>

    private let invNorm2: Float     // moc 1.0 = sinus na pelnej skali
    private let kLo: Int            // pasmo mowy 300...3400 Hz
    private let kHi: Int

    private var fill = 0
    private var primed = false
    private var lastClarity: Float = -1
    private var speech: Float = 0
    private var env: Float = 0.05
    private var agc: Float = 1
    private var gSm: Float = 1
    private var lim: Float = 1
    private var redAvg: Float = 0

    init(rate: Float, knobs: Knobs, meters: Meters) {
        self.rate = rate
        self.knobs = knobs
        self.meters = meters

        func alloc(_ count: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        let n = VoiceDSP.n, hop = VoiceDSP.hop, nb = VoiceDSP.bins
        win = alloc(n); frame = alloc(n); ola = alloc(n); re = alloc(n); im = alloc(n)
        hopIn = alloc(hop); hopOut = alloc(hop)
        ps = alloc(nb); noise = alloc(nb); hold = alloc(nb); aprev = alloc(nb)
        gain = alloc(nb); wgt = alloc(nb)
        accOut = alloc(Meters.bands); accRaw = alloc(Meters.bands); accN = alloc(Meters.bands)
        bandOf = .allocate(capacity: nb)

        // pierwiastek z okna Hanninga, na wejsciu i wyjsciu
        for i in 0..<n {
            let h = 0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(n))
            win[i] = Float(h.squareRoot())
        }
        let norm = Float(n) * 0.3183
        invNorm2 = 1 / (norm * norm)

        kLo = max(1, Int(300 * Float(n) / rate))
        kHi = min(nb - 1, Int(3400 * Float(n) / rate))

        // slupki widma: 32 sztuki rozlozone logarytmicznie od 100 Hz do 8 kHz
        for k in 0..<nb {
            let f = Float(k) * rate / Float(n)
            if f < 100 || f > 8000 {
                bandOf[k] = -1
            } else {
                let b = Int(Float(Meters.bands) * logf(f / 100) / logf(80))
                bandOf[k] = Int32(min(Meters.bands - 1, max(0, b)))
            }
        }
        rebuildCurve(0.6)
    }

    deinit {
        for p in [win, frame, ola, re, im, hopIn, hopOut, ps, noise, hold, aprev, gain, wgt, accOut, accRaw, accN] {
            p.deallocate()
        }
        bandOf.deallocate()
    }

    // Wrzuca probki z mikrofonu, gotowe (obrobione) oddaje do bufora. Wola watek audio.
    func process(_ x: UnsafePointer<Float>, _ count: Int, into out: Ring) {
        var i = 0
        while i < count {
            let take = min(hop - fill, count - i)
            (hopIn + fill).update(from: x + i, count: take)
            fill += take
            i += take
            if fill == hop {
                fill = 0
                step()
                out.write(hopOut, hop)
            }
        }
    }

    // ---------------------------------------------------------------- krzywa pod glos

    private func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private func bump(_ f: Float, _ f0: Float, _ sigma: Float) -> Float {
        let o = log2f(f / f0) / sigma
        return expf(-0.5 * o * o)
    }

    // Krzywa w dB: odciecie dudnienia, lekkie odmulenie, podbicie zrozumialosci (spolgloski)
    // okolo 2,8 kHz i ucieta gora, w ktorej siedzi syk.
    private func rebuildCurve(_ c: Float) {
        lastClarity = c
        for k in 0..<nb {
            let f = max(1, Float(k) * rate / Float(n))
            var db: Float = -40 * (1 - smooth(60, 140, f))
            db += -2.5 * c * bump(f, 250, 0.7)
            db += 7.0 * c * bump(f, 2800, 0.8)
            db += -(2 + 8 * c) * smooth(5500, 10000, f)
            wgt[k] = powf(10, db / 20)
        }
    }

    // ---------------------------------------------------------------- jedna ramka

    private func step() {
        let d = knobs.denoise
        let c = knobs.clarity
        if abs(c - lastClarity) > 0.004 { rebuildCurve(c) }

        // wsuwamy nowe 256 probek na koniec ramki
        frame.update(from: frame + hop, count: n - hop)
        (frame + n - hop).update(from: hopIn, count: hop)

        var inSq: Float = 0
        for i in 0..<hop { inSq += hopIn[i] * hopIn[i] }

        for i in 0..<n {
            re[i] = frame[i] * win[i]
            im[i] = 0
        }
        fft.forward(re, im)

        shape(d)

        // druga polowka widma to lustro pierwszej
        im[0] = 0
        im[n / 2] = 0
        for k in 1..<n / 2 {
            re[n - k] = re[k]
            im[n - k] = -im[k]
        }
        fft.inverse(re, im)

        // okna sie nakladaja czterokrotnie, suma okien Hanninga daje 2
        let scale = 0.5 / Float(n)
        for i in 0..<n { ola[i] += re[i] * win[i] * scale }
        hopOut.update(from: ola, count: hop)
        ola.update(from: ola + hop, count: n - hop)
        (ola + n - hop).update(repeating: 0, count: hop)

        levels(inSq: inSq)
    }

    // Szum, wzmocnienia, bramka. Zmienia re i im.
    private func shape(_ d: Float) {
        let beta = 1 + 2.2 * d
        let floorG = powf(10, -(8 + 20 * d) / 20)
        let bias: Float = 1.5
        let eps: Float = 1e-12

        var bandSig: Float = 0
        var bandNoise: Float = 0

        for k in 0..<nb {
            let p = (re[k] * re[k] + im[k] * im[k]) * invNorm2
            if !primed {
                ps[k] = p
                noise[k] = p
            }
            ps[k] += 0.4 * (p - ps[k])
            let s = ps[k]

            // sledzenie szumu: w dol szybko, w gore wolno, a gdy cos wisi wysoko dluzej niz ok. 1,5 s,
            // to uznajemy to za nowe tlo
            var nz = noise[k]
            if s < nz {
                nz += 0.2 * (s - nz)
                hold[k] = 0
            } else if s < 3 * nz {
                nz += 0.03 * (s - nz)
                hold[k] = 0
            } else {
                hold[k] += 1
                nz *= hold[k] > 280 ? 1.01 : 1.0025
            }
            noise[k] = nz

            let nzb = nz * bias + eps
            let gamma = p / nzb
            // decision directed: mieszamy to co bylo w poprzedniej ramce z tym co widac teraz
            let xi = max(0.98 * aprev[k] + 0.02 * max(gamma - 1, 0), 0.003)
            let g = max(xi / (xi + beta), floorG)
            aprev[k] = g * g * gamma
            gain[k] = g

            if k >= kLo && k <= kHi {
                bandSig += s
                bandNoise += nzb
            }
        }
        primed = true

        // czy w pasmie mowy jest cos wyraznie ponad tlem
        let snrDB = 10 * log10f((bandSig + eps) / (bandNoise + eps))
        let inst = min(1, max(0, (snrDB - 4) / 10))
        if inst > speech {
            speech += 0.35 * (inst - speech)
        } else {
            speech += 0.02 * (inst - speech)
        }
        // miedzy zdaniami przycinamy jeszcze troche (do -8 dB przy pelnym odszumianiu)
        let gateFloor = powf(10, -(8 * d) / 20)
        let gate = gateFloor + (1 - gateFloor) * speech

        for i in 0..<Meters.bands {
            accOut[i] = 0
            accRaw[i] = 0
            accN[i] = 0
        }
        var redSum: Float = 0
        for k in 0..<nb {
            let gl = gain[max(k - 1, 0)]
            let gr = gain[min(k + 1, nb - 1)]
            let gs = 0.25 * gl + 0.5 * gain[k] + 0.25 * gr
            let total = gs * wgt[k] * gate
            let pRaw = (re[k] * re[k] + im[k] * im[k]) * invNorm2
            re[k] *= total
            im[k] *= total
            let b = Int(bandOf[k])
            if b >= 0 {
                accRaw[b] += pRaw
                accOut[b] += pRaw * total * total
                accN[b] += 1
                redSum += gs * gate
            }
        }

        // slupki widma na ekran: opadaja powoli, rosna od razu
        for i in 0..<Meters.bands where accN[i] > 0 {
            let vo = min(1, max(0, (10 * log10f(accOut[i] / accN[i] + 1e-12) + 80) / 55))
            let vr = min(1, max(0, (10 * log10f(accRaw[i] / accN[i] + 1e-12) + 80) / 55))
            meters.voice[i] = max(vo, meters.voice[i] * 0.9)
            meters.raw[i] = max(vr, meters.raw[i] * 0.9)
        }
        let avg = redSum / Float(max(1, nb))
        redAvg += 0.05 * (avg - redAvg)
        meters.speech = speech
    }

    // ---------------------------------------------------------------- poziom i limiter

    private func levels(inSq: Float) {
        var sq: Float = 0
        for i in 0..<hop { sq += hopOut[i] * hopOut[i] }
        let rms = (sq / Float(hop)).squareRoot()

        // auto-poziom: dociaga cichy glos do ok. -26 dBFS, ale tylko gdy ktos mowi,
        // zeby nie podkrecac szumu miedzy zdaniami
        if speech > 0.5 { env += 0.08 * (rms - env) }
        var want: Float = 1
        if knobs.auto { want = min(max(0.05 / max(env, 1e-4), 0.5), 4) }
        if speech > 0.5 || want == 1 {
            agc += 0.02 * (want - agc)
        } else {
            agc += 0.0005 * (1 - agc)
        }

        let target = powf(10, knobs.gainDB / 20) * agc
        let ceiling: Float = 0.85
        var outSq: Float = 0
        for i in 0..<hop {
            gSm += 0.003 * (target - gSm)
            var y = hopOut[i] * gSm
            let a = abs(y)
            let need: Float = a > ceiling ? ceiling / a : 1
            if need < lim {
                lim += 0.6 * (need - lim)
            } else {
                lim += 0.0003 * (1 - lim)
            }
            y *= lim
            y = min(0.95, max(-0.95, y))
            hopOut[i] = y
            outSq += y * y
        }

        meters.outLevel = (outSq / Float(hop)).squareRoot()
        meters.inLevel = (inSq / Float(hop)).squareRoot()
        meters.reduction = -20 * log10f(max(redAvg, 0.001))
    }
}
