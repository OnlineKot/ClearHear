import Foundation

// Sprawdzian rdzenia bez telefonu (Mac i Linux):
//   swiftc -O -parse-as-library SevenTools/Core/*.swift tools/core_check.swift -o corecheck && ./corecheck

var failed = 0
func check(_ ok: Bool, _ msg: String) {
    print(ok ? "  ok    " : "  BLAD  ", msg)
    if !ok { failed += 1 }
}

func sine(_ f: Double, _ sec: Double, rate: Double = 48000, amp: Float = 0.5) -> SampleBuffer {
    let b = SampleBuffer(count: Int(sec * rate), rate: rate)
    for i in 0..<b.count { b.data[i] = amp * Float(sin(2 * .pi * f * Double(i) / rate)) }
    return b
}

func renderAll(_ m: Mixer, frames: Int, chunk: Int = 480) -> [Float] {
    var out = [Float](repeating: 0, count: frames)
    var tmp = [Float](repeating: 0, count: chunk)
    var i = 0
    while i < frames {
        let n = min(chunk, frames - i)
        tmp.withUnsafeMutableBufferPointer { m.render($0.baseAddress!, frames: n) }
        for k in 0..<n { out[i + k] = tmp[k] }
        i += n
    }
    return out
}

func rms(_ x: ArraySlice<Float>) -> Float {
    (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot()
}

@main
struct CoreCheck {
    static func main() {
        print("Dzwieki wbudowane")
        for (id, _, make) in Synth.builtins {
            let b = make()
            var bad = false
            for i in 0..<b.count where !b.data[i].isFinite || abs(b.data[i]) > 1.001 { bad = true }
            if b.peak() < 0.05 || bad { print("   ", id, "peak", b.peak(), "bad", bad) }
            check(b.peak() >= 0.05 && !bad, "\(id): glosny, skonczony, w zakresie (\(String(format: "%.2f", b.peak())), \(String(format: "%.2f", b.duration)) s)")
        }
        check(Synth.builtins.count == 16, "16 wbudowanych dzwiekow")

        print("WAV")
        do {
            let a = sine(440, 0.5, amp: 0.6)
            let d = WAV.encode(a)
            if let b = WAV.decode(d) {
                var err: Float = 0
                for i in 0..<min(a.count, b.count) { err = max(err, abs(a.data[i] - b.data[i])) }
                check(b.count == a.count && b.rate == a.rate && err < 0.001, "zapis i odczyt tam i z powrotem, blad \(err)")
            } else { check(false, "odczyt WAV") }
            check(WAV.decode(Data([1, 2, 3])) == nil, "smieci nie wywalaja odczytu")
        }

        print("Resampling")
        do {
            let a = sine(1000, 0.2, rate: 44100)
            let b = a.resampled(to: 48000)
            check(abs(Double(b.count) - 0.2 * 48000) < 2, "dlugosc po zmianie czestotliwosci")
            let p = Pitch.detect(b.data, count: 2048, rate: 48000)
            check(p != nil && abs(p!.freq - 1000) < 5, "wysokosc dzwieku zachowana (\(p?.freq ?? 0) Hz)")
        }

        print("Mikser: granie, wysokosc, petla")
        do {
            let m = Mixer(rate: 48000)
            m.masterGain = 1
            let s = sine(1000, 1.0)
            m.play(s, tag: 1)
            let out = renderAll(m, frames: 4800)
            check(rms(out[2400..<4800]) > 0.3, "jeden dzwiek gra, rms \(rms(out[2400..<4800]))")
            let p = Pitch.detect(Array(out[2000..<4048]), count: 2048, rate: 48000)
            check(p != nil && abs(p!.freq - 1000) < 6, "wysokosc 1000 Hz (\(p?.freq ?? 0))")

            m.stopAll()
            _ = renderAll(m, frames: 2400)
            check(m.activeVoices == 0, "stopAll wycisza")

            // oktawa wyzej
            m.play(s, tag: 2, ratio: 2)
            let o2 = renderAll(m, frames: 4800)
            let p2 = Pitch.detect(Array(o2[2000..<4048]), count: 2048, rate: 48000, maxHz: 3000)
            check(p2 != nil && abs(p2!.freq - 2000) < 12, "ratio 2 = oktawa wyzej (\(p2?.freq ?? 0))")
            m.stopAll(); _ = renderAll(m, frames: 2400)

            // koniec jednorazowego dzwieku
            let short = sine(500, 0.05)
            m.play(short, tag: 3)
            _ = renderAll(m, frames: 4800)
            check(m.activeVoices == 0, "jednorazowy dzwiek sam sie konczy")

            // petla gra dluzej niz dlugosc probki
            m.play(short, tag: 4, loop: true)
            let lo = renderAll(m, frames: 48000)
            check(rms(lo[40000..<48000]) > 0.2 && m.isPlaying(tag: 4), "petla gra bez konca")
            var maxJump: Float = 0
            for i in 1..<lo.count { maxJump = max(maxJump, abs(lo[i] - lo[i - 1])) }
            check(maxJump < 0.25, "petla bez trzaskow (najwiekszy skok \(maxJump))")
            m.stop(tag: 4)
            _ = renderAll(m, frames: 2400)
            check(!m.isPlaying(tag: 4), "stop(tag) zatrzymuje petle")

            // ten sam tag = ponowne uruchomienie, nie dublowanie
            m.play(s, tag: 5); _ = renderAll(m, frames: 480)
            m.play(s, tag: 5); _ = renderAll(m, frames: 2400)
            check(m.activeVoices == 1, "ten sam pad nie gra podwojnie")

            // zapas glosow: 60 naraz nie wywala
            m.stopAll(); _ = renderAll(m, frames: 2400)
            for t in 0..<60 { m.play(s, tag: 100 + t) }
            _ = renderAll(m, frames: 4800)
            check(m.activeVoices <= Mixer.maxVoices, "kradzenie glosow przy przepelnieniu (\(m.activeVoices))")
        }

        print("Mikser: limiter i generator")
        do {
            let m = Mixer(rate: 48000)
            m.masterGain = 1
            let loud = sine(200, 1, amp: 1)
            for t in 0..<10 { m.play(loud, tag: t) }
            let o = renderAll(m, frames: 9600)
            check((o.map { abs($0) }.max() ?? 0) <= 1.0, "dziesiec glosnych dzwiekow nie przekracza 1.0")

            let g = Mixer(rate: 48000)
            g.masterGain = 1
            g.setTone(on: true, wave: 0, f1: 440, f2: 440, sweep: 0, gain: 5)
            let t = renderAll(g, frames: 48000)
            check(rms(t[40000..<48000]) < 0.5 / 1.3 && rms(t[40000..<48000]) > 0.1, "generator ma twardy sufit glosnosci (\(rms(t[40000..<48000])))")
            g.setTone(on: false, wave: 0, f1: 440, f2: 440, sweep: 0, gain: 0.2)
            let off = renderAll(g, frames: 48000)
            check(rms(off[40000..<48000]) < 0.001, "generator da sie wylaczyc")
        }

        print("Looper z padow")
        do {
            let m = Mixer(rate: 48000)
            m.masterGain = 1
            m.loop { l in
                l.source = .pads
                l.quantize = false
                l.startFirst()
            }
            // pierwsza warstwa: 1 s dzwieku 500 Hz z padu
            m.play(sine(500, 1.0, amp: 0.4), tag: 1)
            _ = renderAll(m, frames: 48000)
            m.loop { $0.stopFirst() }
            let st = m.loop { ($0.state, $0.length) }
            check(st.0 == .playing && abs(st.1 - 48000) < 1000, "petla ustalona (\(st.1) probek)")

            // po zakonczeniu dzwieku z padu slychac juz tylko petle
            _ = renderAll(m, frames: 48000)
            let l1 = renderAll(m, frames: 24000)
            check(rms(l1[0..<24000]) > 0.15, "petla gra sama, rms \(rms(l1[0..<24000]))")

            // dogrywka z padu na wierzch
            m.loop { $0.startOverdub() }
            m.play(sine(1500, 0.5, amp: 0.3), tag: 2)
            _ = renderAll(m, frames: 48000)
            m.loop { $0.stopOverdub() }
            check(m.loop { $0.layerCount } == 2, "dwie warstwy")
            let mix = renderAll(m, frames: 48000)
            let p = Pitch.detect(Array(mix[0..<2048]), count: 2048, rate: 48000)
            check(rms(mix[0..<48000]) > 0.1, "obie warstwy graja")
            _ = p

            let md = m.loopMixdown()
            check(md != nil && md!.count == st.1, "zgranie petli do jednego dzwieku")

            // cofnij
            m.loop { $0.undo() }
            check(m.loop { $0.layerCount } == 1, "cofnij zdejmuje ostatnia warstwe")
            m.loop { $0.clearAll() }
            check(m.loop { $0.state } == .empty, "wyczysc")
        }

        print("Looper z mikrofonu: dogrywka trafia w to samo miejsce")
        do {
            let rate = 48000.0
            let m = Mixer(rate: rate)
            m.masterGain = 1
            let latency = 960   // 20 ms
            m.loop { l in
                l.source = .mic
                l.quantize = false
                l.latencyFrames = latency
                l.startFirst()
            }
            // "mikrofon" daje impuls co 0,25 s przez 1 s
            func feed(_ x: [Float]) {
                var i = 0
                while i < x.count {
                    let n = min(480, x.count - i)
                    x.withUnsafeBufferPointer { m.capture($0.baseAddress! + i, n) }
                    _ = renderAll(m, frames: n)
                    i += n
                }
            }
            var first = [Float](repeating: 0, count: 48000)
            for k in 0..<4 { first[k * 12000] = 0.8 }
            feed(first)
            m.loop { $0.stopFirst() }
            let len = m.loop { $0.length }
            check(abs(len - 48000) <= 480, "dlugosc petli z mikrofonu \(len)")

            // dogrywka: impuls w polowie kazdego kroku, ale mikrofon spoznia sie o `latency`
            m.loop { $0.startOverdub() }
            var second = [Float](repeating: 0, count: len)
            // slyszalem petle na pozycji p, w tym samym momencie zagralem. Do mikrofonu dochodzi to z opoznieniem
            for k in 0..<4 { let at = k * 12000 + 6000 + latency; if at < len { second[at] = 0.8 } }
            // glowica na starcie dogrywki
            feed(second)
            m.loop { $0.stopOverdub() }
            let mix = m.loopMixdown()!
            var peaks = [Int]()
            for i in 0..<mix.count where abs(mix.data[i]) > 0.5 { peaks.append(i) }
            let want = [6000, 12000, 18000, 24000, 30000, 36000, 42000]   // 0 pomijamy: szew petli jest wygaszony
            var ok = peaks.count >= 6
            for w in want where !peaks.contains(where: { abs($0 - w) <= 2 * 480 }) { ok = false }
            check(ok, "impulsy z dogrywki lacza sie w siatke co 6000 probek: \(peaks.prefix(12))")
        }

        print("Kwantyzacja")
        do {
            let m = Mixer(rate: 48000)
            m.loop { l in l.source = .pads; l.bpm = 120; l.quantize = true; l.startFirst() }
            m.play(sine(300, 4, amp: 0.2), tag: 1)
            _ = renderAll(m, frames: 100000)    // ok. 2,08 s: 4 uderzenia przy 120 BPM to 2 s
            m.loop { $0.stopFirst() }
            let (len, beats) = m.loop { ($0.length, $0.beats) }
            check(len == 96000 && beats == 4, "petla zaokraglona do 4 uderzen (\(len) probek, \(beats) uderzen)")
        }

        print("Nagrywanie sampla")
        do {
            let m = Mixer(rate: 48000)
            m.startSampleRecording()
            let x = sine(300, 0.5, amp: 0.4)
            var i = 0
            while i < x.count { let n = min(480, x.count - i); m.capture(x.data + i, n); i += n }
            let r = m.stopSampleRecording()
            check(r != nil && abs(r!.count - x.count) < 2 && r!.peak() > 0.35, "nagranie z mikrofonu trafia do bufora")
            check(m.stopSampleRecording() == nil, "puste nagranie to nil")
        }


        print("Sluchanie przez mikser")
        do {
            let m = Mixer(rate: 48000)
            m.masterGain = 1
            m.listenKnobs.gainDB = 9; m.listenKnobs.denoise = 0.6; m.listenKnobs.clarity = 0.6; m.listenKnobs.auto = true
            m.setListening(true)
            var rng = Noise()
            // 12 s: szum i co sekunde "slowo" (ton z modulacja), ciche potem glosne
            func feedSecond(_ amp: Float) -> [Float] {
                var out = [Float]()
                let n = 48000
                var x = [Float](repeating: 0, count: n)
                for i in 0..<n {
                    let t = Float(i) / 48000
                    let word: Float = t < 0.5 ? Float(sin(2 * .pi * 220 * t) + 0.5 * sin(2 * .pi * 880 * t)) * (0.5 - 0.5 * cosf(2 * .pi * 4 * t)) : 0
                    x[i] = word * amp + rng.next() * 0.002
                }
                var i = 0
                while i < n {
                    let c = min(480, n - i)
                    x.withUnsafeBufferPointer { m.capture($0.baseAddress! + i, c) }
                    out += renderAll(m, frames: c)
                    i += c
                }
                return out
            }
            var last: [Float] = []
            for _ in 0..<4 { last = feedSecond(0.01) }
            let quiet = rms(last[0..<24000])
            for _ in 0..<3 { last = feedSecond(1.2) }
            let loudRms = rms(last[0..<24000])
            let loudPeak = (last.map { abs($0) }.max() ?? 0)
            print(String(format: "  cichy %.4f, glosny %.4f, szczyt %.2f", quiet, loudRms, loudPeak))
            check(quiet > 0.004, "cichy dzwiek jest slyszalny przez mikser")
            check(loudPeak <= 0.62 && loudRms < 0.2, "glosny dzwiek nie bije po uszach")
            m.setListening(false)
            let off = renderAll(m, frames: 4800)
            check(rms(off[2400..<4800]) < 0.001, "po wylaczeniu cisza")
        }


        print("Skaner ultradzwiekowy")
        do {
            let rate = 48000.0
            let eng = SonarEngine(rate: rate)
            var rng = Noise()
            func scene(_ echoes: [(Double, Float)]) -> [Float] {
                var x = [Float](repeating: 0, count: 8192)
                for i in 0..<x.count { x[i] = rng.next() * 0.002 }
                func put(_ at: Int, _ amp: Float) {
                    for i in 0..<eng.chirp.count where at + i < x.count { x[at + i] += eng.chirp.data[i] * amp }
                }
                put(1500, 0.5)    // sygnal bezposredni (glosnik -> mikrofon)
                for (m, a) in echoes { put(1500 + Int(2 * m / Ultra.speedOfSound * rate), a) }
                return x
            }
            let one = eng.analyze(scene([(3.0, 0.05)]))
            check(one.direct != nil && abs(one.direct! - 1500) < 6, "znalazl sygnal bezposredni (\(one.direct ?? -1))")
            check(one.echoes.count == 1 && abs(one.echoes[0].meters - 3.0) < 0.12, "echo z 3 m: \(one.echoes.map { String(format: "%.2f", $0.meters) })")
            let two = eng.analyze(scene([(1.5, 0.08), (3.5, 0.03)]))
            check(two.echoes.count == 2 && abs(two.echoes[0].meters - 1.5) < 0.12 && abs(two.echoes[1].meters - 3.5) < 0.12,
                  "dwa echa: \(two.echoes.map { String(format: "%.2f", $0.meters) })")
            check(two.echoes[0].strength > two.echoes[1].strength, "blizsze echo jest silniejsze")
            let none = eng.analyze(scene([]))
            check(none.echoes.isEmpty, "bez ech nic nie zglasza (\(none.echoes.count))")
            let silence = eng.analyze([Float](repeating: 0, count: 8192))
            check(silence.direct == nil && silence.echoes.isEmpty, "cisza to brak wyniku")

            // pasma wysokich tonow
            let fft = FFT(2048)
            var tone = [Float](repeating: 0, count: 2048)
            for i in 0..<2048 { tone[i] = 0.3 * sinf(2 * .pi * 19000 * Float(i) / 48000) + rng.next() * 0.001 }
            let b = Ultra.bands(tone, rate: 48000, count: 20, from: 14000, to: 24000, fft: fft)
            let best = b.indices.max { b[$0] < b[$1] }!
            let center = 14000 + 10000 * (Float(best) + 0.5) / 20
            check(abs(center - 19000) < 600, "19 kHz laduje w pasmie okolo \(Int(center)) Hz")
            check(b[best] > b.sorted()[10] + 20, "ton wyraznie ponad tlem")
            let quiet = Ultra.bands((0..<2048).map { _ in rng.next() * 0.001 }, rate: 48000, count: 20, from: 14000, to: 24000, fft: fft)
            check((quiet.max() ?? 0) - (quiet.min() ?? 0) < 20, "szum jest plaski")
        }


        print("IKEA: schemat, trasa, wyszukiwanie")
        do {
            check(abs(IkeaMap.floorLength(1) - 556) < 0.01 && abs(IkeaMap.floorLength(0) - 556) < 0.01, "sciezki maja po 556 m")
            let a = IkeaMap.pointAt(floor: 1, s: 50)
            check(abs(a.p.x - 60) < 0.01 && abs(a.p.y - 10) < 0.01 && abs(a.bearing - 90) < 0.5, "s=50: (60,10), idzie na wschod (\(a.bearing)°)")
            let b = IkeaMap.pointAt(floor: 1, s: 107)
            check(abs(b.p.x - 110) < 0.01 && abs(b.p.y - 17) < 0.01 && abs(b.bearing - 180) < 0.5, "zakret w dol, kierunek na poludnie")
            let c = IkeaMap.pointAt(floor: 1, s: 150)
            check(abs(c.bearing - 270) < 0.5, "drugi rzad idzie na zachod (\(c.bearing)°)")
            check(IkeaMap.zones.allSatisfy { $0.s >= 0 && $0.s <= IkeaMap.floorLength($0.floor) }, "wszystkie dzialy leza na sciezce")
            check(Set(IkeaMap.zones.map { $0.id }).count == IkeaMap.zones.count, "id dzialow sa unikalne")

            // trasa w przod, na jednym pietrze
            let r1 = IkeaMap.route(from: (1, 55), to: (1, 285))
            check(r1.forward && abs(r1.meters - 230) < 0.01 && r1.legs.count == 1, "salony -> kuchnie: 230 m w przod")
            check(r1.passing.map { $0.id }.contains("restauracja") && r1.passing.map { $0.id }.contains("jadalnie"), "po drodze restauracja i jadalnie")
            // trasa przez pietra
            let r2 = IkeaMap.route(from: (1, 415), to: (0, 140))
            check(r2.legs.count == 2 && r2.legs[0].floor == 1 && r2.legs[1].floor == 0 && abs(r2.meters - (556 - 415 + 140)) < 0.01, "szafy -> naczynia: dwa pietra, \(Int(r2.meters)) m")
            // pod prad
            let r3 = IkeaMap.route(from: (1, 285), to: (1, 55))
            check(!r3.forward && abs(r3.meters - 230) < 0.01, "kuchnie -> salony: pod prad, 230 m")
            check(!r3.passing.isEmpty && r3.passing.first!.s >= r3.passing.last!.s, "mijane dzialy w kolejnosci powrotu")
            check(r1.legs[0].points.count >= 3 && r1.legs[0].points.first == IkeaMap.pointAt(floor: 1, s: 55).p, "lamana trasy zaczyna sie w miejscu startu")

            // global <-> pietro
            let g = IkeaMap.global(floor: 0, s: 100)
            let pl = IkeaMap.place(global: g)
            check(pl.floor == 0 && abs(pl.s - 100) < 0.01, "przeliczenie pozycji globalnej")

            // wyszukiwanie
            check(IkeaMap.find("kanapa").first?.id == "salony", "kanapa -> salony")
            check(IkeaMap.find("Łóżko 160").first?.id == "lozka", "Łóżko 160 -> lozka (\(IkeaMap.find("Łóżko 160").first?.id ?? "-"))")
            check(IkeaMap.find("garnek").first?.id == "naczynia", "garnek -> naczynia")
            check(IkeaMap.find("lampka nocna").first?.id == "oswietlenie", "lampka nocna -> oswietlenie (\(IkeaMap.find("lampka nocna").map { $0.id }.prefix(3)))")
            check(IkeaMap.find("pościel").first?.id == "tekstylia", "pościel -> tekstylia")
            check(IkeaMap.find("klopsiki").first?.id == "restauracja", "klopsiki -> restauracja")
            check(IkeaMap.find("szafa pax").first?.id == "pax", "szafa pax -> PAX")
            check(IkeaMap.find("rosliny").first?.id == "rosliny", "rosliny -> rosliny (\(IkeaMap.find("rosliny").first?.id ?? "-"))")
            check(IkeaMap.find("xyzqwerty").isEmpty, "nieznane slowo nic nie zwraca")

            // magazyn
            check(abs(IkeaMap.aisle(1) - 345) < 0.01 && abs(IkeaMap.aisle(40) - 435) < 0.01 && IkeaMap.aisle(20) > 345 && IkeaMap.aisle(20) < 435, "alejki rozlozone w magazynie")

            // kolejnosc listy
            let items = [("garnek", IkeaMap.zone("naczynia")!), ("sofa", IkeaMap.zone("salony")!), ("lozko", IkeaMap.zone("lozka")!)]
            let ord = IkeaMap.order(items, from: 100)
            check(ord.map { $0.name } == ["lozko", "garnek", "sofa"], "lista: najpierw to, co przed nami, potem to, co za nami (\(ord.map { $0.name }))")

            // klik w mape
            check(IkeaMap.nearestZone(to: P(x: 66, y: 12), floor: 1)?.id == "salony", "klik przy salonach wybiera salony")
            check(IkeaMap.nearestZone(to: P(x: 60, y: 82), floor: 1) == nil, "klik daleko od sciezki nic nie wybiera")

            // kompas
            let off = HeadingCal.offset(compass: 130, pathBearing: 90)
            check(abs(off - 40) < 0.001 && abs(HeadingCal.mapHeading(compass: 130, offset: off) - 90) < 0.001, "offset kompasu 40°")
            check(abs(HeadingCal.diff(350, 10) + 20) < 0.001 && abs(HeadingCal.norm(-10) - 350) < 0.001, "roznica katow przez 0°")
            var o = 0.0
            for _ in 0..<80 { o = HeadingCal.blend(current: o, compass: 215, pathBearing: 180) }
            check(abs(o - 35) < 1.5, "offset dociaga sie do prawdziwego (\(Int(o))°)")
            var o2 = 350.0
            for _ in 0..<80 { o2 = HeadingCal.blend(current: o2, compass: 20, pathBearing: 0) }
            check(abs(HeadingCal.diff(o2, 20)) < 1.5, "dociaganie przez 360°/0° (\(Int(o2))°)")
        }


        print("Profile")
        do {
            check(ProfileScope.isScoped("pads") && ProfileScope.isScoped("ikea.nav.v1") && ProfileScope.isScoped("fake.model")
                  && ProfileScope.isScoped("listen.gain") && ProfileScope.isScoped("bank.parody") && ProfileScope.isScoped("ai.provider"), "klucze profilu rozpoznane")
            check(!ProfileScope.isScoped("updateCheck") && !ProfileScope.isScoped("boards.adopted") && !ProfileScope.isScoped("profiles.list")
                  && !ProfileScope.isScoped("latencyMs") && !ProfileScope.isScoped("padsX") && !ProfileScope.isScoped("spotify"), "klucze wspolne zostaja wspolne")
            let all: [String: Any] = ["pads": Data([1]), "listen.gain": 9.0, "updateCheck": true, "boards.adopted": ["a": "b"], "counter.value": 3]
            let sc = ProfileScope.extract(all)
            check(Set(sc.keys) == Set(["pads", "listen.gain", "counter.value"]), "wycinek profilu: \(sc.keys.sorted())")

            let a = Profile(name: "Ola", emoji: "🐱", hue: 0.1)
            let b = Profile(name: "ola 2", emoji: "🐶", hue: 0.5)
            check(ProfileBook.uniqueName("Ola", in: [a, b]) == "Ola 3", "unikalna nazwa: \(ProfileBook.uniqueName("Ola", in: [a, b]))")
            check(ProfileBook.uniqueName("  ", in: []) == "Profil" && ProfileBook.uniqueName("Ewa", in: [a]) == "Ewa", "puste i wolne nazwy")
            let h = ProfileBook.nextHue([a, b])
            check(abs(h - 0.1) > 0.05 && abs(h - 0.5) > 0.05, "nowy kolor nie powtarza zajetych (\(h))")

            let c = Profile(name: "Ewa", emoji: "🦊", hue: 0.8)
            let list = [a, b, c]
            let r1 = ProfileBook.afterDelete(list, deleting: b.id, current: b.id)
            check(r1 != nil && r1!.list.count == 2 && r1!.current == c.id, "usuniecie aktywnego daje sasiada")
            let r2 = ProfileBook.afterDelete(list, deleting: c.id, current: a.id)
            check(r2 != nil && r2!.current == a.id && r2!.list.count == 2, "usuniecie innego nie zmienia aktywnego")
            let r3 = ProfileBook.afterDelete(list, deleting: c.id, current: c.id)
            check(r3 != nil && r3!.current == b.id, "usuniecie ostatniego daje poprzedni")
            check(ProfileBook.afterDelete([a], deleting: a.id, current: a.id) == nil, "ostatniego profilu nie da sie usunac")
            let enc = try? JSONEncoder().encode(list)
            let dec = enc.flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
            check(dec == list, "profile zapisuja sie i odczytuja")
        }

        print("Stroik")
        do {
            let rate: Float = 48000
            for (f, name) in [(82.41, "E2"), (110.0, "A2"), (196.0, "G3"), (329.63, "E4"), (440.0, "A4"), (987.77, "B5")] as [(Double, String)] {
                let b = SampleBuffer(count: 4096, rate: 48000)
                for i in 0..<4096 {
                    var v: Float = 0
                    for h in 1...5 { v += Float(sin(2 * .pi * f * Double(h) * Double(i) / 48000)) / Float(h) }
                    b.data[i] = v * 0.25
                }
                let p = Pitch.detect(b.data, count: 4096, rate: rate)
                let n = p.map { Pitch.note(for: $0.freq) }
                check(p != nil && abs(p!.freq / Float(f) - 1) < 0.005, "\(name): wykryto \(p?.freq ?? 0) Hz jako \(n?.name ?? "?")\(n?.octave ?? 0), \(String(format: "%+.1f", n?.cents ?? 0)) centow")
            }
            let noise = SampleBuffer(count: 4096, rate: 48000)
            var rng = Noise()
            for i in 0..<4096 { noise.data[i] = rng.next() * 0.3 }
            let pn = Pitch.detect(noise.data, count: 4096, rate: rate)
            check(pn == nil || pn!.clarity < 0.7, "szum nie udaje dzwieku")
            let sil = SampleBuffer(count: 4096, rate: 48000)
            check(Pitch.detect(sil.data, count: 4096, rate: rate) == nil, "cisza to brak dzwieku")
            let a = Pitch.note(for: 440)
            check(a.name == "A" && a.octave == 4 && abs(a.cents) < 0.01, "440 Hz to A4")
            let flat = Pitch.note(for: 436)
            check(flat.name == "A" && flat.cents < -10, "436 Hz to A o \(flat.cents) centow nizej")
        }

        print("Morse")
        do {
            let t = Morse.timings("SOS", wpm: 20)
            let unit = 1.2 / 20.0
            // S=... O=--- S=...  : 9 sygnalow
            check(t.filter { $0.on }.count == 9, "SOS ma 9 sygnalow")
            check(abs(t[0].seconds - unit) < 1e-9 && abs(t.filter { $0.on }[3].seconds - 3 * unit) < 1e-9, "kropka = 1 jednostka, kreska = 3")
            check(Morse.timings("ĄĆ", wpm: 20).filter { $0.on }.count == 6, "polskie litery")
            let a = Morse.audio("E E", wpm: 15)
            check(a.peak() > 0.3 && a.duration > 0.3, "dzwiek Morse'a")
        }


        print("Dzwieki do psikusow")
        for (id, make) in PrankSound.all.sorted(by: { $0.key < $1.key }) {
            let b = make()
            var bad = false
            for i in 0..<b.count where !b.data[i].isFinite || abs(b.data[i]) > 1.001 { bad = true }
            check(b.peak() >= 0.05 && !bad, "\(id): glosny, skonczony (\(String(format: "%.2f", b.peak())), \(String(format: "%.2f", b.duration)) s)")
        }

        print("Geo i slonce")
        do {
            // Krakow -> Warszawa: ok. 252 km, azymut ok. 31 stopni
            let d = Geo.distance(50.0647, 19.9450, 52.2297, 21.0122)
            check(abs(d - 252_000) < 4000, "Krakow-Warszawa \(Int(d / 1000)) km")
            let b = Geo.bearing(50.0647, 19.9450, 52.2297, 21.0122)
            check(abs(b - 17) < 4, "azymut \(Int(b)) stopni (N-NE)")
            check(Geo.compassName(0) == "N" && Geo.compassName(92) == "E" && Geo.compassName(359) == "N" && Geo.compassName(225) == "SW", "nazwy stron swiata")
            check(Geo.dms(50.0614, positive: "N", negative: "S").hasPrefix("50°03'") && Geo.dms(-33.8, positive: "N", negative: "S").hasSuffix("S"), "stopnie, minuty, sekundy")
            check(Geo.distanceText(850) == "850 m" && Geo.distanceText(2500) == "2.5 km", "tekst odleglosci")
            // Krakow, 21 czerwca (dzien 172): wschod ok. 04:15 CEST, zachod ok. 20:55 CEST
            if let t = Sun.times(dayOfYear: 172, lat: 50.0647, lon: 19.945) {
                let rise = Sun.hhmm(t.rise, utcOffsetMinutes: 120), set = Sun.hhmm(t.set, utcOffsetMinutes: 120)
                check(rise.hasPrefix("04:") && set.hasPrefix("20:") || set.hasPrefix("21:"), "wschod \(rise), zachod \(set) w Krakowie 21.06")
            } else { check(false, "slonce w Krakowie") }
            check(Sun.times(dayOfYear: 172, lat: 80, lon: 20) == nil, "doba polarna: brak wschodu")
        }

        print("Jednostki")
        do {
            let len = Units.all[0], temp = Units.all[5]
            let km = len.units.first { $0.name == "km" }!, mile = len.units.first { $0.name == "mila" }!
            check(abs(Units.convert(10, from: km, to: mile, in: len) - 6.2137) < 0.001, "10 km = 6,21 mili")
            let c = temp.units[0], f = temp.units[1], k = temp.units[2]
            check(abs(Units.convert(100, from: c, to: f, in: temp) - 212) < 0.001, "100°C = 212°F")
            check(abs(Units.convert(0, from: c, to: k, in: temp) - 273.15) < 0.001, "0°C = 273,15 K")
            check(abs(Units.convert(-40, from: f, to: c, in: temp) + 40) < 0.001, "-40°F = -40°C")
        }

        print("Poza telefonu i gesty")
        do {
            check(Pose.classify(x: 0, y: -1, z: 0) == .upright, "pionowo")
            check(Pose.classify(x: 0, y: 1, z: 0) == .upsideDown, "do gory nogami")
            check(Pose.classify(x: 1, y: 0, z: 0) == .landscapeLeft && Pose.classify(x: -1, y: 0, z: 0) == .landscapeRight, "na boku")
            check(Pose.classify(x: 0, y: 0, z: -1) == .faceUp && Pose.classify(x: 0, y: 0, z: 1) == .faceDown, "plasko")
            // histereza: lekkie przechylenie nie przeskakuje
            check(Pose.classify(x: 0.55, y: -0.6, z: 0, previous: .upright) == .upright, "histereza przy przechyle")
            check(Pose.upsideDown.screenAngle == 180, "ekran obrocony o 180")

            var sh = ShakeDetector()
            var fired = 0
            for i in 0..<20 { if sh.feed(magnitude: 1.0, at: Double(i) * 0.02) { fired += 1 } }
            check(fired == 0, "bez ruchu nie potrzasa")
            for i in 0..<8 { if sh.feed(magnitude: i % 2 == 0 ? 3.2 : 0.2, at: 1 + Double(i) * 0.06) { fired += 1 } }
            check(fired == 1, "potrzasniecie wykryte raz (\(fired))")

            var cl = ClapDetector()
            var claps = 0
            var t = 0.0
            func block(_ level: Float, _ n: Int) { for _ in 0..<n { if cl.feed(level: level, at: t) { claps += 1 }; t += 0.01 } }
            block(0.005, 100)
            block(0.4, 2); block(0.005, 20)
            check(claps == 0, "jedno klasniecie to jeszcze nie sygnal")
            block(0.4, 2); block(0.005, 50)
            check(claps == 1, "dwa klasniecia = sygnal (\(claps))")
            block(0.05, 200)   // glosna rozmowa, ale bez skoku
            check(claps == 1, "rozmowa nie jest klasnieciem")

            check(Surroundings.classify(dbfs: -65) == .quiet && Surroundings.classify(dbfs: -40) == .talk && Surroundings.classify(dbfs: -20) == .crowd, "srodowisko z poziomu")
            check(Surroundings.classify(dbfs: -51, previous: .quiet) == .quiet, "histereza srodowiska")
        }

        print("Wydajnosc")
        do {
            let m = Mixer(rate: 48000)
            for (i, b) in Synth.builtins.enumerated() { m.play(b.make(), tag: i, loop: true) }
            m.loop { l in l.source = .pads; l.quantize = false; l.startFirst() }
            _ = renderAll(m, frames: 48000)
            m.loop { $0.stopFirst() }
            for _ in 0..<3 { m.loop { $0.startOverdub() }; _ = renderAll(m, frames: 48000); m.loop { $0.stopOverdub() } }
            let t0 = Date()
            _ = renderAll(m, frames: 48000 * 10)
            let dt = Date().timeIntervalSince(t0)
            print(String(format: "  10 s dzwieku (16 petli + 4 warstwy) policzone w %.2f s, czyli %.1f%% jednego rdzenia", dt, dt / 10 * 100))
            check(dt / 10 < 0.2, "obciazenie mniejsze niz 20% jednego rdzenia")
        }

        if failed > 0 {
            print("\nBLEDY: \(failed)")
            exit(1)
        }
        print("\nWszystko dziala.")
    }
}
