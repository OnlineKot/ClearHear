import Foundation

// Wykrywanie wysokosci dzwieku (YIN) dla stroika, plus nazwy nut.
enum Pitch {
    // Zwraca czestotliwosc i pewnosc (0...1) albo nil, gdy to szum albo cisza.
    static func detect(_ x: UnsafePointer<Float>, count n: Int, rate: Float,
                       minHz: Float = 55, maxHz: Float = 1500) -> (freq: Float, clarity: Float)? {
        let tauMin = max(2, Int(rate / maxHz))
        let tauMax = min(n / 2 - 1, Int(rate / minHz))
        guard tauMax > tauMin + 2 else { return nil }
        let w = n / 2

        var energy: Float = 0
        for i in 0..<n { energy += x[i] * x[i] }
        if (energy / Float(n)).squareRoot() < 0.004 { return nil }

        // roznica kwadratow dla kazdego opoznienia
        var d = [Float](repeating: 0, count: tauMax + 1)
        for tau in 1...tauMax {
            var s: Float = 0
            for i in 0..<w {
                let v = x[i] - x[i + tau]
                s += v * v
            }
            d[tau] = s
        }
        // znormalizowana skumulowana srednia
        var cm = [Float](repeating: 1, count: tauMax + 1)
        var run: Float = 0
        for tau in 1...tauMax {
            run += d[tau]
            cm[tau] = run > 0 ? d[tau] * Float(tau) / run : 1
        }
        // pierwszy dolek ponizej progu
        var best = -1
        var tau = tauMin
        while tau <= tauMax {
            if cm[tau] < 0.15 {
                while tau + 1 <= tauMax && cm[tau + 1] < cm[tau] { tau += 1 }
                best = tau
                break
            }
            tau += 1
        }
        if best < 0 {
            // brak wyraznego dolka: bierzemy najnizszy, ale tylko jak jest dosc glebokii
            var m = Float.greatestFiniteMagnitude
            for t in tauMin...tauMax where cm[t] < m { m = cm[t]; best = t }
            if m > 0.35 { return nil }
        }
        // interpolacja paraboliczna wokol dolka
        var t0 = Float(best)
        if best > 1 && best < tauMax {
            let a = cm[best - 1], b = cm[best], c = cm[best + 1]
            let den = a - 2 * b + c
            if abs(den) > 1e-9 { t0 += 0.5 * (a - c) / den }
        }
        let clarity = max(0, min(1, 1 - cm[best]))
        return (rate / t0, clarity)
    }

    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // nuta najblizsza czestotliwosci i odchylka w centach (-50...50)
    static func note(for freq: Float, a4: Float = 440) -> (name: String, octave: Int, cents: Float, midi: Int) {
        let m = 69 + 12 * log2f(freq / a4)
        let r = Int(m.rounded())
        let cents = (m - Float(r)) * 100
        let idx = ((r % 12) + 12) % 12
        return (names[idx], r / 12 - 1, cents, r)
    }

    static func frequency(midi: Int, a4: Float = 440) -> Float {
        a4 * powf(2, Float(midi - 69) / 12)
    }
}
