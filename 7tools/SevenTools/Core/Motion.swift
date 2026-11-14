import Foundation

// Czujniki bez CoreMotion: z samych liczb da sie sprawdzic, czy telefon jest odwrocony, potrzasany itd.
enum Pose: String, CaseIterable {
    case upright        // normalnie, gora do gory
    case upsideDown     // do gory nogami
    case landscapeLeft  // na boku, gora w lewo
    case landscapeRight
    case faceUp         // ekranem do gory na stole
    case faceDown       // ekranem w dol

    var title: String {
        switch self {
        case .upright: return "Normalnie"
        case .upsideDown: return "Do góry nogami"
        case .landscapeLeft: return "Na boku (lewo)"
        case .landscapeRight: return "Na boku (prawo)"
        case .faceUp: return "Ekranem do góry"
        case .faceDown: return "Ekranem w dół"
        }
    }

    // obrot ekranu w stopniach, zeby tresc byla "do gory" dla trzymajacego
    var screenAngle: Double {
        switch self {
        case .upsideDown: return 180
        case .landscapeLeft: return 90
        case .landscapeRight: return -90
        default: return 0
        }
    }

    // g = wektor grawitacji z czujnika (x w prawo, y w gore telefonu, z z ekranu), w jednostkach g
    static func classify(x: Double, y: Double, z: Double, previous: Pose? = nil) -> Pose {
        // histereza: zostajemy przy poprzedniej pozie, dopoki nowa nie jest wyraznie lepsza
        let bias = 0.12
        func score(_ p: Pose) -> Double {
            let v: Double
            switch p {
            case .upright: v = -y
            case .upsideDown: v = y
            case .landscapeLeft: v = x
            case .landscapeRight: v = -x
            case .faceUp: v = -z
            case .faceDown: v = z
            }
            return v + (p == previous ? bias : 0)
        }
        return Pose.allCases.max { score($0) < score($1) } ?? .upright
    }
}

// Potrzasanie: kilka szybkich zmian przyspieszenia w krotkim czasie.
struct ShakeDetector {
    var threshold = 1.9        // w g, po odjeciu grawitacji
    var needed = 3
    var window = 0.7           // sekundy
    private var hits: [Double] = []
    private var lastFire = -10.0

    mutating func feed(magnitude g: Double, at t: Double) -> Bool {
        if abs(g - 1) > threshold - 1 { hits.append(t) }
        hits.removeAll { t - $0 > window }
        if hits.count >= needed && t - lastFire > 1.0 {
            lastFire = t
            hits.removeAll()
            return true
        }
        return false
    }
}

// Klasniecie: gwaltowny skok glosnosci nad tlem. Dwa w ciagu ok. pol sekundy = sygnal.
struct ClapDetector {
    var ratio: Float = 6         // o ile razy glosniej niz tlo
    var minLevel: Float = 0.06   // i nie ciszej niz to
    private var background: Float = 0.01
    private var lastClap = -10.0
    private var firstClapAt = -10.0

    // level = RMS bloku, t = czas w sekundach. Zwraca true przy podwojnym klasnieciu.
    mutating func feed(level: Float, at t: Double) -> Bool {
        let isClap = level > minLevel && level > background * ratio
        if !isClap { background += 0.05 * (level - background) }
        guard isClap, t - lastClap > 0.12 else { return false }   // jedno klasniecie to kilka blokow
        lastClap = t
        if t - firstClapAt < 0.8 && t - firstClapAt > 0.12 {
            firstClapAt = -10
            return true
        }
        firstClapAt = t
        return false
    }
}

// Jaki jest dzwiek wokol: z poziomu glosnosci wnioskujemy, czy to cisza, rozmowa czy halas.
enum Surroundings: String {
    case quiet, talk, crowd

    var title: String {
        switch self {
        case .quiet: return "Cisza"
        case .talk: return "Rozmowa"
        case .crowd: return "Tłum i hałas"
        }
    }

    // dbfs = srednia glosnosc wejscia w dBFS (np. -60 cicho, -35 rozmowa, -25 halas)
    static func classify(dbfs: Float, previous: Surroundings? = nil) -> Surroundings {
        let h: Float = 3   // histereza w dB
        func shift(_ s: Surroundings) -> Float { previous == s ? h : 0 }
        if dbfs < -52 + shift(.quiet) { return .quiet }
        if dbfs < -30 + shift(.talk) { return .talk }
        return .crowd
    }
}
