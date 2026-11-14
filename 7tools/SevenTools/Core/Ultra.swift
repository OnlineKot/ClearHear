import Foundation

// Skaner "ultradzwiekowy": telefon nie ma prawdziwego ultradzwieku (to okolice 17 do 21 kHz, tuz za granica slyszalnosci),
// ale wystarcza do zabawy: sonar na echo i podglad wysokich tonow. Bez CoreAudio, zeby dalo sie to sprawdzic testem.
enum Ultra {
    static let speedOfSound = 343.0   // m/s

    // Krotki pisk z przemiataniem czestotliwosci (chirp), z lagodnym wejsciem i wyjsciem
    static func chirp(rate: Double = 48000, from f0: Double = 17500, to f1: Double = 21000, ms: Double = 6) -> SampleBuffer {
        let n = Int(rate * ms / 1000)
        let b = SampleBuffer(count: n, rate: rate)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let f = f0 + (f1 - f0) * t
            phase += 2 * .pi * f / rate
            let w = 0.5 - 0.5 * cos(2 * .pi * t)
            b.data[i] = Float(sin(phase) * w)
        }
        return b
    }

    // Energia w pasmach od `from` do `to` Hz (dB wzgledem pelnej skali, ok. -100...0). x musi miec count = potega dwojki.
    static func bands(_ x: [Float], rate: Float, count bandCount: Int, from: Float, to: Float, fft: FFT) -> [Float] {
        let n = fft.n
        precondition(x.count >= n)
        let re = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let im = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { re.deallocate(); im.deallocate() }
        let start = x.count - n
        for i in 0..<n {
            let w = 0.5 - 0.5 * cosf(2 * .pi * Float(i) / Float(n))
            re[i] = x[start + i] * w
            im[i] = 0
        }
        fft.forward(re, im)
        let binHz = rate / Float(n)
        let norm = 1 / (Float(n) * 0.25)
        var out = [Float](repeating: -100, count: bandCount)
        for b in 0..<bandCount {
            let lo = from + (to - from) * Float(b) / Float(bandCount)
            let hi = from + (to - from) * Float(b + 1) / Float(bandCount)
            let k0 = max(1, Int(lo / binHz)), k1 = min(n / 2 - 1, max(k0, Int(hi / binHz)))
            var p: Float = 0
            for k in k0...k1 {
                let m = (re[k] * re[k] + im[k] * im[k]) * norm * norm
                p = max(p, m)
            }
            out[b] = 10 * log10f(p + 1e-10)
        }
        return out
    }
}

struct Echo: Equatable {
    var meters: Double
    var strength: Float      // 0...1 wzgledem sygnalu bezposredniego
}

// Sonar: dopasowany filtr (korelacja z piskiem) i szukanie ech za sygnalem bezposrednim (z glosnika do mikrofonu).
final class SonarEngine {
    let rate: Double
    let chirp: SampleBuffer
    private let size: Int
    private let fft: FFT
    private let chirpRe: UnsafeMutablePointer<Float>
    private let chirpIm: UnsafeMutablePointer<Float>
    private let re: UnsafeMutablePointer<Float>
    private let im: UnsafeMutablePointer<Float>
    private let env: UnsafeMutablePointer<Float>

    init(rate: Double = 48000, windowSamples: Int = 8192) {
        self.rate = rate
        chirp = Ultra.chirp(rate: rate)
        var s = 1
        while s < windowSamples + chirp.count { s <<= 1 }
        size = s
        fft = FFT(s)
        chirpRe = .allocate(capacity: s); chirpIm = .allocate(capacity: s)
        re = .allocate(capacity: s); im = .allocate(capacity: s); env = .allocate(capacity: s)
        for i in 0..<s { chirpRe[i] = i < chirp.count ? chirp.data[i] : 0; chirpIm[i] = 0 }
        fft.forward(chirpRe, chirpIm)
    }

    deinit {
        chirpRe.deallocate(); chirpIm.deallocate(); re.deallocate(); im.deallocate(); env.deallocate()
    }

    // window = ostatnie probki z mikrofonu, w ktorych jest caly pisk i jego echa.
    // Zwraca echa (odleglosc od telefonu w metrach), posortowane od najblizszego, albo pusta liste.
    func analyze(_ window: [Float], minMeters: Double = 0.25, maxMeters: Double = 5) -> (direct: Int?, echoes: [Echo]) {
        let n = min(window.count, size - chirp.count)
        guard n > chirp.count * 2 else { return (nil, []) }
        for i in 0..<size { re[i] = i < n ? window[window.count - n + i] : 0; im[i] = 0 }
        fft.forward(re, im)
        // korelacja = FFT(okno) * sprzezone FFT(pisk)
        for k in 0..<size {
            let a = re[k], b = im[k]
            let c = chirpRe[k], d = -chirpIm[k]
            re[k] = a * c - b * d
            im[k] = a * d + b * c
        }
        fft.inverse(re, im)
        let scale = 1 / Float(size)
        // obwiednia: maksimum modulu z kilku sasiednich probek (nosna ma okolo 2,5 probki)
        let limit = n
        for i in 0..<limit {
            var m: Float = 0
            let lo = max(0, i - 3), hi = min(limit - 1, i + 3)
            for j in lo...hi { m = max(m, abs(re[j] * scale)) }
            env[i] = m
        }
        // sygnal bezposredni: najsilniejszy punkt
        var p0 = 0
        var peak: Float = 0
        for i in 0..<limit where env[i] > peak { peak = env[i]; p0 = i }
        guard peak > 1e-4 else { return (nil, []) }

        // prog: kilka razy ponad mediane szumu i nie mniej niz 2% sygnalu bezposredniego
        var sample = [Float]()
        var i = 0
        while i < limit { sample.append(env[i]); i += 8 }
        sample.sort()
        let floorLevel = sample[sample.count / 2]
        let threshold = max(floorLevel * 5, peak * 0.02)

        let minSep = Int(2 * minMeters / Ultra.speedOfSound * rate)
        let maxSep = Int(2 * maxMeters / Ultra.speedOfSound * rate)
        var echoes: [Echo] = []
        var j = p0 + minSep
        let end = min(limit - 2, p0 + maxSep)
        while j < end {
            if env[j] > threshold && env[j] >= env[j - 1] && env[j] >= env[j + 1] {
                // lokalne maksimum w okienku +-20 probek
                var isMax = true
                for k in max(0, j - 20)...min(limit - 1, j + 20) where env[k] > env[j] { isMax = false; break }
                if isMax {
                    let meters = Double(j - p0) / rate * Ultra.speedOfSound / 2
                    echoes.append(Echo(meters: meters, strength: min(1, env[j] / peak)))
                    j += 40
                    continue
                }
            }
            j += 1
        }
        return (p0, Array(echoes.prefix(5)))
    }
}
