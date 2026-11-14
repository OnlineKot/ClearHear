import Foundation

// Dzwieki wbudowane. Wszystkie powstaja z kodu, wiec nie ma plikow ani cudzych praw autorskich.
struct Noise {
    var s: UInt64 = 0x2545F4914F6CDD1D
    mutating func next() -> Float {
        s ^= s << 13
        s ^= s >> 7
        s ^= s << 17
        return Float(Double(s >> 11) / Double(1 << 53)) * 2 - 1
    }
}

enum Synth {
    static let rate: Double = 48000

    // nazwa, symbol, funkcja. Kolejnosc = kolejnosc padow od lewej gornej.
    static let builtins: [(id: String, name: String, make: () -> SampleBuffer)] = [
        ("kick", "Kick", kick),
        ("snare", "Werbel", snare),
        ("hat", "Hi-hat", hat),
        ("openhat", "Open hat", openHat),
        ("clap", "Klaps", clap),
        ("drop", "Bass drop", bassDrop),
        ("siren", "Syrena", siren),
        ("horn", "Róg", airHorn),
        ("laser", "Laser", laser),
        ("coin", "Moneta", coin),
        ("whoosh", "Whoosh", whoosh),
        ("boom", "Wybuch", explosion),
        ("twang", "Twang 007", twang),
        ("alarm", "Alarm", alarm),
        ("tape", "Tape stop", tapeStop),
        ("beep", "Beep", beep),
    ]

    private static func make(_ seconds: Double, _ f: (Double, Int) -> Float) -> SampleBuffer {
        let n = Int(seconds * rate)
        let b = SampleBuffer(count: n, rate: rate)
        for i in 0..<n { b.data[i] = f(Double(i) / rate, i) }
        // zadnego dzwieku glosniejszego niz 0,95, zeby pady nie przesterowywaly
        let p = b.peak()
        if p > 0.95 {
            let g = 0.95 / p
            for i in 0..<n { b.data[i] *= g }
        }
        b.fadeEdges(ms: 2)
        return b
    }

    private static func env(_ t: Double, _ decay: Double) -> Float { Float(exp(-t * decay)) }

    static func kick() -> SampleBuffer {
        var phase = 0.0
        return make(0.55) { t, _ in
            let f = 45 + 120 * exp(-t * 28)
            phase += 2 * .pi * f / rate
            let click = t < 0.004 ? Float(1 - t / 0.004) * 0.5 : 0
            return (Float(sin(phase)) * env(t, 7) + click) * 0.95
        }
    }

    static func snare() -> SampleBuffer {
        var n = Noise()
        var lp: Float = 0
        return make(0.32) { t, _ in
            let w = n.next()
            lp += 0.55 * (w - lp)
            let tone = Float(sin(2 * .pi * 185 * t)) * env(t, 30)
            return (tone * 0.5 + (w - lp * 0.4) * env(t, 16) * 0.8) * 0.85
        }
    }

    static func hat() -> SampleBuffer {
        var n = Noise()
        var prev: Float = 0
        return make(0.09) { t, _ in
            let w = n.next()
            let hp = w - prev
            prev = w
            return hp * env(t, 55) * 0.6
        }
    }

    static func openHat() -> SampleBuffer {
        var n = Noise()
        var prev: Float = 0
        return make(0.4) { t, _ in
            let w = n.next()
            let hp = w - prev
            prev = w
            return hp * env(t, 9) * 0.5
        }
    }

    static func clap() -> SampleBuffer {
        var n = Noise()
        var lp: Float = 0
        return make(0.3) { t, _ in
            let w = n.next()
            lp += 0.35 * (w - lp)
            let bursts = [0.0, 0.012, 0.024].reduce(Float(0)) { acc, s in
                acc + (t >= s ? env(t - s, 120) : 0)
            }
            return lp * (bursts * 0.55 + env(t, 14) * 0.6)
        }
    }

    static func bassDrop() -> SampleBuffer {
        var phase = 0.0
        return make(1.6) { t, _ in
            let f = 30 + 140 * exp(-t * 2.2)
            phase += 2 * .pi * f / rate
            let x = Float(sin(phase)) * 2.2 * min(1, Float(t) * 80)
            return tanhf(x) * 0.9 * Float(max(0, 1 - t / 1.6))
        }
    }

    static func siren() -> SampleBuffer {
        var phase = 0.0
        return make(2.4) { t, _ in
            let f = 950 + 450 * sin(2 * .pi * t / 1.2)
            phase += 2 * .pi * f / rate
            return Float(sin(phase) + 0.25 * sin(2 * phase)) * 0.55 * min(1, Float(2.4 - t) * 8)
        }
    }

    static func airHorn() -> SampleBuffer {
        let freqs: [Double] = [415.3, 466.2, 554.4]
        var ph = [Double](repeating: 0, count: 3)
        return make(1.3) { t, _ in
            let vib = 1 + 0.004 * sin(2 * .pi * 6 * t)
            var s: Float = 0
            for k in 0..<3 {
                ph[k] += freqs[k] * vib / rate
                ph[k] -= ph[k].rounded(.down)
                let saw = Float(ph[k] * 2 - 1)
                s += saw
            }
            let e = min(1, Float(t) * 60) * min(1, Float(1.3 - t) * 6)
            return tanhf(s * 0.9) * 0.55 * e
        }
    }

    static func laser() -> SampleBuffer {
        var phase = 0.0
        return make(0.4) { t, _ in
            let f = 2400 * exp(-t * 9) + 180
            phase += 2 * .pi * f / rate
            return Float(sin(phase)) * env(t, 6) * 0.7
        }
    }

    static func coin() -> SampleBuffer {
        var phase = 0.0
        return make(0.55) { t, _ in
            let f: Double = t < 0.08 ? 987.8 : 1318.5
            phase += 2 * .pi * f / rate
            let sq: Float = sin(phase) > 0 ? 1 : -1
            let e: Float = t < 0.08 ? 1 : env(t - 0.08, 7)
            return sq * e * 0.28
        }
    }

    static func whoosh() -> SampleBuffer {
        var n = Noise()
        var lp: Float = 0
        return make(0.9) { t, _ in
            let a = Float(0.03 + 0.5 * sin(.pi * t / 0.9))
            lp += a * (n.next() - lp)
            return lp * Float(sin(.pi * t / 0.9)) * 1.6
        }
    }

    static func explosion() -> SampleBuffer {
        var n = Noise()
        var lp: Float = 0
        var phase = 0.0
        return make(1.8) { t, _ in
            let a = Float(0.02 + 0.5 * exp(-t * 4))
            lp += a * (n.next() - lp)
            phase += 2 * .pi * (38 + 40 * exp(-t * 6)) / rate
            return (lp * 1.8 + Float(sin(phase)) * 0.8) * env(t, 2.6) * 0.8
        }
    }

    // szarpniecie strun, Karplus-Strong: dzwiek w stylu filmow szpiegowskich
    static func twang() -> SampleBuffer {
        let notes: [(Double, Double)] = [(82.41, 0), (123.47, 0.04), (196.0, 0.08), (246.94, 0.12)]
        let total = 2.2
        let n = Int(total * rate)
        let out = SampleBuffer(count: n, rate: rate)
        var noise = Noise()
        for (f, start) in notes {
            let len = max(2, Int(rate / f))
            var line = (0..<len).map { _ in noise.next() }
            var idx = 0
            let s0 = Int(start * rate)
            for i in s0..<n {
                let nxt = (idx + 1) % len
                let v = line[idx]
                line[idx] = (line[idx] + line[nxt]) * 0.5 * 0.9985
                idx = nxt
                out.data[i] += v * 0.28
            }
        }
        for i in 0..<n { out.data[i] = tanhf(out.data[i] * 1.8) * 0.8 }
        out.fadeEdges(ms: 3)
        return out
    }

    static func alarm() -> SampleBuffer {
        var phase = 0.0
        return make(1.6) { t, _ in
            let on = Int(t / 0.2) % 2 == 0
            phase += 2 * .pi * 1760 / rate
            return on ? Float(sin(phase)) * 0.45 : 0
        }
    }

    static func tapeStop() -> SampleBuffer {
        var phase = 0.0
        return make(1.1) { t, _ in
            let f = 440 * pow(max(0.02, 1 - t / 1.1), 2.2)
            phase += 2 * .pi * f / rate
            var saw = Float((phase / (2 * .pi)).truncatingRemainder(dividingBy: 1) * 2 - 1)
            saw *= 0.45
            return saw * Float(max(0, 1 - t / 1.1))
        }
    }

    static func beep() -> SampleBuffer {
        make(0.25) { t, _ in Float(sin(2 * .pi * 1000 * t)) * 0.5 }
    }
}

// Alfabet Morse'a
enum Morse {
    static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.", ".": ".-.-.-", ",": "--..--",
        "?": "..--..", "!": "-.-.--", "/": "-..-.", "-": "-....-", "=": "-...-",
    ]

    // rozpoznaje tez polskie litery
    static func normalize(_ c: Character) -> Character {
        let map: [Character: Character] = ["Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z"]
        let u = Character(String(c).uppercased())
        return map[u] ?? u
    }

    // lista (swieci, ile sekund); wpm = slow na minute
    static func timings(_ text: String, wpm: Double) -> [(on: Bool, seconds: Double)] {
        let unit = 1.2 / max(5, wpm)
        var out: [(Bool, Double)] = []
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        for (wi, w) in words.enumerated() {
            let letters = w.compactMap { c -> String? in table[normalize(c)] }
            for (li, code) in letters.enumerated() {
                for (si, s) in code.enumerated() {
                    out.append((true, s == "." ? unit : unit * 3))
                    if si < code.count - 1 { out.append((false, unit)) }
                }
                if li < letters.count - 1 { out.append((false, unit * 3)) }
            }
            if wi < words.count - 1 { out.append((false, unit * 7)) }
        }
        return out
    }

    static func audio(_ text: String, wpm: Double, freq: Double = 650) -> SampleBuffer {
        let t = timings(text, wpm: wpm)
        let total = max(0.05, t.reduce(0) { $0 + $1.seconds })
        let rate = Synth.rate
        let b = SampleBuffer(count: Int(total * rate) + 1, rate: rate)
        var pos = 0.0
        var phase = 0.0
        for (on, sec) in t {
            let n = Int(sec * rate)
            let start = Int(pos * rate)
            if on {
                for i in 0..<n where start + i < b.count {
                    phase += 2 * .pi * freq / rate
                    let edge = min(1, Float(min(i, n - i)) / Float(rate * 0.004))
                    b.data[start + i] = Float(sin(phase)) * 0.5 * edge
                }
            }
            pos += sec
        }
        return b
    }
}
