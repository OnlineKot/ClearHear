import Foundation

// Jeden dzwiek w pamieci: mono, floaty. Wszystko w apce (pady, sampler, looper) gra z takich buforow.
final class SampleBuffer {
    let data: UnsafeMutablePointer<Float>
    let count: Int
    let rate: Double

    init(count: Int, rate: Double) {
        self.count = max(1, count)
        self.rate = rate
        data = .allocate(capacity: self.count)
        data.initialize(repeating: 0, count: self.count)
    }

    convenience init(_ samples: [Float], rate: Double) {
        self.init(count: samples.count, rate: rate)
        for i in 0..<samples.count { data[i] = samples[i] }
    }

    deinit { data.deallocate() }

    var duration: Double { Double(count) / rate }

    func peak() -> Float {
        var p: Float = 0
        for i in 0..<count { p = max(p, abs(data[i])) }
        return p
    }

    // liniowe przeliczenie na inna czestotliwosc probkowania
    func resampled(to newRate: Double) -> SampleBuffer {
        if abs(newRate - rate) < 0.5 { return copy() }
        let n = max(1, Int((Double(count) * newRate / rate).rounded()))
        let out = SampleBuffer(count: n, rate: newRate)
        let ratio = rate / newRate
        for i in 0..<n {
            let p = Double(i) * ratio
            let i0 = min(count - 1, Int(p))
            let i1 = min(count - 1, i0 + 1)
            let f = Float(p - Double(i0))
            out.data[i] = data[i0] * (1 - f) + data[i1] * f
        }
        return out
    }

    func copy() -> SampleBuffer {
        let out = SampleBuffer(count: count, rate: rate)
        out.data.update(from: data, count: count)
        return out
    }

    func reversed() -> SampleBuffer {
        let out = SampleBuffer(count: count, rate: rate)
        for i in 0..<count { out.data[i] = data[count - 1 - i] }
        return out
    }

    func normalized(to target: Float = 0.9) -> SampleBuffer {
        let p = peak()
        let out = copy()
        if p > 0.0001 {
            let g = target / p
            for i in 0..<count { out.data[i] *= g }
        }
        return out
    }

    func trimmed(_ a: Int, _ b: Int) -> SampleBuffer {
        let lo = max(0, min(count - 1, a))
        let hi = max(lo + 1, min(count, b))
        let out = SampleBuffer(count: hi - lo, rate: rate)
        out.data.update(from: data + lo, count: hi - lo)
        return out
    }

    // krotkie wejscie i wyjscie, zeby na brzegach nie trzaskalo
    func fadeEdges(ms: Double = 3) {
        let n = min(count / 2, max(1, Int(rate * ms / 1000)))
        for i in 0..<n {
            let g = Float(i) / Float(n)
            data[i] *= g
            data[count - 1 - i] *= g
        }
    }

    // wysokosc slupkow do rysowania fali, 0...1
    func waveform(bins: Int, from: Int = 0, to: Int? = nil) -> [Float] {
        let a = max(0, min(count - 1, from))
        let b = max(a + 1, min(count, to ?? count))
        var out = [Float](repeating: 0, count: bins)
        for k in 0..<bins {
            let s = a + (b - a) * k / bins
            let e = max(s + 1, a + (b - a) * (k + 1) / bins)
            var p: Float = 0
            for i in s..<min(e, b) { p = max(p, abs(data[i])) }
            out[k] = min(1, p)
        }
        return out
    }
}

// Plik WAV: zapis 16 bit mono, odczyt typowych wariantow (8/16/24/32 bit, float), wiele kanalow schodzi do mono.
enum WAV {
    static func encode(_ b: SampleBuffer) -> Data {
        let n = b.count
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(b.rate)); u32(UInt32(b.rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
        var pcm = [Int16](repeating: 0, count: n)
        for i in 0..<n { pcm[i] = Int16(max(-1, min(1, b.data[i])) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }

    static func decode(_ d: Data) -> SampleBuffer? {
        let bytes = [UInt8](d)
        guard bytes.count > 44, String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        func le32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 }
        func le16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }

        var fmtTag = 1, channels = 1, rate = 44100, bits = 16
        var dataStart = -1, dataLen = 0
        var o = 12
        while o + 8 <= bytes.count {
            let id = String(decoding: bytes[o..<o + 4], as: UTF8.self)
            let len = le32(o + 4)
            if id == "fmt " && o + 8 + 16 <= bytes.count {
                fmtTag = le16(o + 8)
                channels = max(1, le16(o + 10))
                rate = le32(o + 12)
                bits = le16(o + 22)
            } else if id == "data" {
                dataStart = o + 8
                dataLen = min(len, bytes.count - dataStart)
                break
            }
            o += 8 + len + (len & 1)
        }
        guard dataStart >= 0, rate > 0, [8, 16, 24, 32].contains(bits) else { return nil }
        let bps = bits / 8
        let frames = dataLen / (bps * channels)
        guard frames > 0 else { return nil }

        let out = SampleBuffer(count: frames, rate: Double(rate))
        for i in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
                let p = dataStart + (i * channels + c) * bps
                var v: Float
                switch bits {
                case 8: v = (Float(bytes[p]) - 128) / 128
                case 16: v = Float(Int16(truncatingIfNeeded: le16(p))) / 32768
                case 24:
                    var x = Int(bytes[p]) | Int(bytes[p + 1]) << 8 | Int(bytes[p + 2]) << 16
                    if x & 0x800000 != 0 { x -= 0x1000000 }
                    v = Float(x) / 8388608
                default:
                    if fmtTag == 3 {
                        v = Float(bitPattern: UInt32(truncatingIfNeeded: le32(p)))
                    } else {
                        v = Float(Int32(truncatingIfNeeded: le32(p))) / 2147483648
                    }
                }
                sum += v
            }
            out.data[i] = sum / Float(channels)
        }
        return out
    }
}
