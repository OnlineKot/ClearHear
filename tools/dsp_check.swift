import Foundation

// Sprawdzian rdzenia dzwieku bez telefonu. Dziala na Macu i na Linuksie:
//
//   swiftc -O -parse-as-library HearNow/Voice.swift HearNow/Ring.swift tools/dsp_check.swift -o dspcheck
//   ./dspcheck
//
// Robi sztuczna "mowe" (samogloski z formantami, slowa i przerwy) plus szum i patrzy, czy
// szum miedzy slowami spada, a glos zostaje.

struct Rng {
    var s: UInt64 = 0x9E3779B97F4A7C15
    mutating func next() -> Float {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float(Double(s >> 11) / Double(1 << 53)) * 2 - 1
    }
}

let rate: Float = 48000

// samogloski: kilka harmonicznych podbitych w okolicach formantow
func speechSignal(seconds: Float, rng: inout Rng) -> (x: [Float], active: [Bool]) {
    let n = Int(seconds * rate)
    var x = [Float](repeating: 0, count: n)
    var active = [Bool](repeating: false, count: n)
    var phase = [Float](repeating: 0, count: 40)
    let formants: [(Float, Float)] = [(700, 1), (1220, 0.7), (2600, 0.45)]
    for i in 0..<n {
        let t = Float(i) / rate
        // slowo trwa 0,7 s, potem 0,6 s ciszy
        let inWord = t.truncatingRemainder(dividingBy: 1.3) < 0.7
        active[i] = inWord
        if !inWord { continue }
        let wt = t.truncatingRemainder(dividingBy: 1.3)
        let syl = 0.5 - 0.5 * cosf(2 * .pi * 4 * wt)           // sylaby 4 razy na sekunde
        let f0 = 120 + 25 * sinf(2 * .pi * 0.8 * t) + 8 * sinf(2 * .pi * 5.5 * t)
        var v: Float = 0
        for h in 1..<40 {
            let f = f0 * Float(h)
            if f > 5000 { break }
            phase[h] += 2 * .pi * f / rate
            var a: Float = 0
            for (fc, w) in formants { a += w * expf(-0.5 * powf((f - fc) / (0.25 * fc + 80), 2)) }
            v += a / Float(h).squareRoot() * sinf(phase[h])
        }
        x[i] = v * syl * 0.055
    }
    return (x, active)
}

func pinkish(_ n: Int, rng: inout Rng, level: Float) -> [Float] {
    var out = [Float](repeating: 0, count: n)
    var b0: Float = 0, b1: Float = 0, b2: Float = 0
    for i in 0..<n {
        let w = rng.next()
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        out[i] = (b0 + b1 + b2 + w * 0.1848) * 0.2 * level
    }
    return out
}

func rms(_ x: [Float], _ idx: [Int]) -> Float {
    if idx.isEmpty { return 0 }
    var s: Float = 0
    for i in idx { s += x[i] * x[i] }
    return (s / Float(idx.count)).squareRoot()
}

func db(_ a: Float, _ b: Float) -> Float { 20 * log10f(max(a, 1e-9) / max(b, 1e-9)) }

func run(_ x: [Float], knobs: Knobs, dsp: VoiceDSP? = nil) -> [Float] {
    let meters = Meters()
    let d = dsp ?? VoiceDSP(rate: rate, knobs: knobs, meters: meters)
    let ring = Ring(capacity: 1 << 20)
    var out = [Float]()
    out.reserveCapacity(x.count)
    let chunk = 240
    var tmp = [Float](repeating: 0, count: chunk)
    var i = 0
    while i < x.count {
        let m = min(chunk, x.count - i)
        x.withUnsafeBufferPointer { d.process($0.baseAddress! + i, m, into: ring) }
        let a = ring.available
        if a > 0 {
            var left = a
            while left > 0 {
                let r = ring.read(&tmp, min(left, chunk))
                out.append(contentsOf: tmp[0..<r])
                left -= r
            }
        }
        i += m
    }
    return out
}

var failed = 0
func check(_ ok: Bool, _ msg: String) {
    print(ok ? "  ok    " : "  BLAD  ", msg)
    if !ok { failed += 1 }
}

@main
struct Check {
    static func main() {
        var rng = Rng()

        // 1. FFT tam i z powrotem
        print("FFT")
        do {
            let f = FFT(1024)
            let re = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
            let im = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
            var orig = [Float](repeating: 0, count: 1024)
            for i in 0..<1024 { orig[i] = rng.next(); re[i] = orig[i]; im[i] = 0 }
            f.forward(re, im)
            f.inverse(re, im)
            var err: Float = 0
            for i in 0..<1024 { err = max(err, abs(re[i] / 1024 - orig[i])) }
            check(err < 1e-4, "FFT tam i z powrotem, blad \(err)")

            // sinus w binie 100 ma byc w binie 100
            for i in 0..<1024 { re[i] = sinf(2 * .pi * 100 * Float(i) / 1024); im[i] = 0 }
            f.forward(re, im)
            var best = 0
            var bv: Float = 0
            for k in 0..<512 {
                let v = re[k] * re[k] + im[k] * im[k]
                if v > bv { bv = v; best = k }
            }
            check(best == 100, "sinus laduje w dobrym binie (\(best))")
            re.deallocate(); im.deallocate()
        }

        // 2. bufor kolowy
        print("Ring")
        do {
            let r = Ring(capacity: 8)
            let a: [Float] = [1, 2, 3, 4, 5, 6]
            a.withUnsafeBufferPointer { r.write($0.baseAddress!, 6) }
            var o = [Float](repeating: 0, count: 4)
            let got = r.read(&o, 4)
            check(got == 4 && o == [1, 2, 3, 4], "kolejnosc probek")
            a.withUnsafeBufferPointer { r.write($0.baseAddress!, 6) }   // zawija sie, miesci 6, wolne 6
            check(r.available == 8, "zapelnia sie do pojemnosci (\(r.available))")
            r.skip(3)
            var o2 = [Float](repeating: 0, count: 8)
            let g2 = r.read(&o2, 8)
            check(g2 == 5, "skip wyrzuca najstarsze (zostalo \(g2))")
        }

        // 3. ton 1 kHz wlaczany i wylaczany (staly ton to dla odszumiacza "tlo", wiec samego sinusa nie ma sensu mierzyc)
        print("Ton 1 kHz, bez obrobki")
        do {
            let k = Knobs()
            k.gainDB = 0; k.denoise = 0; k.clarity = 0; k.auto = false
            var x = [Float](repeating: 0, count: Int(rate * 6))
            var on = [Int]()
            for i in 0..<x.count {
                let t = Float(i) / rate
                if t.truncatingRemainder(dividingBy: 1.0) < 0.5 {
                    x[i] = 0.1 * sinf(2 * .pi * 1000 * Float(i) / rate)
                    if t > 3 && t.truncatingRemainder(dividingBy: 1.0) > 0.1 { on.append(i) }
                }
            }
            let y = run(x, knobs: k)
            let ratio = db(rms(y, on.filter { $0 < y.count }), rms(x, on.filter { $0 < y.count }))
            check(abs(ratio) < 1.5, "poziom tonu zmienil sie o \(ratio) dB")
            check(x.count - y.count < 2048, "opoznienie mniejsze niz 2048 probek (brakuje \(x.count - y.count))")
        }

        // 4. mowa + szum
        print("Mowa i szum")
        for (name, den, clar, lvl) in [("odszumianie 0,6, szum cichy", Float(0.6), Float(0.6), Float(0.012)),
                                       ("odszumianie 1,0, szum cichy", Float(1.0), Float(0.6), Float(0.012)),
                                       ("odszumianie 0,6, szum glosny", Float(0.6), Float(0.6), Float(0.035)),
                                       ("odszumianie 1,0, szum glosny", Float(1.0), Float(0.6), Float(0.035))] {
            let (sp, act) = speechSignal(seconds: 16, rng: &rng)
            let noise = pinkish(sp.count, rng: &rng, level: lvl)
            var x = sp
            for i in 0..<x.count { x[i] += noise[i] }

            let k = Knobs()
            k.gainDB = 0; k.denoise = den; k.clarity = clar; k.auto = false
            let y = run(x, knobs: k)

            // pomijamy 3 pierwsze sekundy (uczenie szumu) i 0,25 s po koncu kazdego slowa
            var pause = [Int](), word = [Int]()
            for i in Int(rate * 3)..<y.count {
                let t = Float(i) / rate
                let wt = t.truncatingRemainder(dividingBy: 1.3)
                if i < act.count && act[i] { word.append(i) }
                else if wt > 0.95 && wt < 1.28 { pause.append(i) }
            }
            let pIn = rms(x, pause), pOut = rms(y, pause)
            let wIn = rms(x, word), wOut = rms(y, word)
            let pr = db(pOut, pIn)
            let wr = db(wOut, wIn)
            // glos czysty (bez szumu) jako odniesienie do poziomu
            let wClean = rms(sp, word)
            print(String(format: "  [%@] przerwy: %.1f dB, slowa: %+.1f dB (wzgledem wejscia), slowa czyste vs wyjscie: %+.1f dB",
                         name, pr, wr, db(wOut, wClean)))
            check(pr < -10, "szum w przerwach spada o ponad 10 dB")
            check(wr > -3 && wr < 5, "glos zostaje w granicach -3...+5 dB")
        }

        // 5. limiter: bardzo glosne wejscie nie przekracza 0,95
        print("Limiter")
        do {
            let k = Knobs()
            k.gainDB = 24; k.denoise = 0; k.clarity = 0; k.auto = true
            var x = [Float](repeating: 0, count: Int(rate * 2))
            for i in 0..<x.count { x[i] = 0.9 * sinf(2 * .pi * 440 * Float(i) / rate) }
            let y = run(x, knobs: k)
            let peak = y.map { abs($0) }.max() ?? 0
            check(peak <= 0.601, "szczyt \(peak) nie przekracza 0,6 (sufit przy sluchawkach)")
            check(!y.contains { $0.isNaN }, "bez NaN")
        }


        // 5b. glosnosc: cichy szept i krzyk maja wyjsc w podobnym poziomie, bez huku
        print("Wyrownywanie glosnosci")
        do {
            func words(scale: Float, noiseLvl: Float) -> (outRms: Float, peak: Float, inRms: Float) {
                var r = Rng()
                let (sp, act) = speechSignal(seconds: 14, rng: &r)
                let nz = pinkish(sp.count, rng: &r, level: noiseLvl)
                var x = sp
                for i in 0..<x.count { x[i] = x[i] * scale + nz[i] }
                let k = Knobs()
                k.gainDB = 9; k.denoise = 0.6; k.clarity = 0.6; k.auto = true
                let y = run(x, knobs: k)
                var word = [Int]()
                for i in Int(rate * 4)..<min(y.count, act.count) where act[i] { word.append(i) }
                let pk = y.map { abs($0) }.max() ?? 0
                return (rms(y, word), pk, rms(x, word))
            }
            let quiet = words(scale: 0.08, noiseLvl: 0.0004)
            let normal = words(scale: 1, noiseLvl: 0.004)
            let shout = words(scale: 6, noiseLvl: 0.004)
            print(String(format: "  wejscie: %.4f / %.4f / %.4f  wyjscie: %.3f / %.3f / %.3f  szczyt: %.2f", quiet.inRms, normal.inRms, shout.inRms, quiet.outRms, normal.outRms, shout.outRms, shout.peak))
            check(db(shout.inRms, quiet.inRms) > 30, "wejscia roznia sie o \(db(shout.inRms, quiet.inRms)) dB")
            check(db(shout.outRms, quiet.outRms) < 12, "wyjscia roznia sie o \(db(shout.outRms, quiet.outRms)) dB (poniżej 12)")
            check(quiet.outRms > 0.015, "szept jest slyszalny (rms \(quiet.outRms))")
            check(shout.outRms < 0.2 && shout.peak <= 0.601, "krzyk nie bije po uszach (rms \(shout.outRms), szczyt \(shout.peak))")

            // plynne wejscie po starcie
            let k = Knobs()
            k.gainDB = 9; k.auto = true
            var x = [Float](repeating: 0, count: Int(rate * 3))
            for i in 0..<x.count { x[i] = 0.3 * sinf(2 * .pi * 300 * Float(i) / rate) }
            let y = run(x, knobs: k)
            let first = rms(y, Array(0..<4800)), later = rms(y, Array(Int(rate * 2)..<(y.count - 10)))
            check(first < later * 0.5, "pierwsze 0,1 s jest cichsze niz pozniej (\(first) vs \(later))")
        }

        // 6. cisza i pelna cisza cyfrowa nie psuja niczego
        print("Cisza")
        do {
            let k = Knobs()
            let y = run([Float](repeating: 0, count: Int(rate)), knobs: k)
            check(!y.contains { $0.isNaN || $0.isInfinite }, "zera na wejsciu daja zera, bez NaN")
            check((y.map { abs($0) }.max() ?? 0) < 1e-6, "cisza zostaje cisza")
        }

        // 7. koszt: 20 s dzwieku ma sie policzyc znacznie szybciej niz w 20 s
        print("Wydajnosc")
        do {
            let (sp, _) = speechSignal(seconds: 20, rng: &rng)
            let k = Knobs()
            let t0 = Date()
            _ = run(sp, knobs: k)
            let dt = Date().timeIntervalSince(t0)
            let load = dt / 20 * 100
            print(String(format: "  20 s dzwieku policzone w %.2f s, czyli %.1f%% jednego rdzenia", dt, load))
            check(load < 15, "obciazenie mniejsze niz 15% jednego rdzenia")
        }

        if failed > 0 {
            print("\nBLEDY: \(failed)")
            exit(1)
        }
        print("\nWszystko dziala.")
    }
}
