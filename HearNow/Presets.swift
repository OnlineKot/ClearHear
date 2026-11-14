import SwiftUI

// Cztery ustawienia na start. Dotkniecie suwaka robi z nich "wlasne".
struct Tuning: Equatable {
    var gain: Double       // dB, 0...24
    var denoise: Double    // 0...1
    var clarity: Double    // 0...1
    var auto: Bool
}

enum Preset: String, CaseIterable, Identifiable {
    case talk, crowd, far, quiet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk: return "Rozmowa"
        case .crowd: return "Tłum"
        case .far: return "Z daleka"
        case .quiet: return "Cisza"
        }
    }

    var symbol: String {
        switch self {
        case .talk: return "bubble.left.and.bubble.right.fill"
        case .crowd: return "person.3.fill"
        case .far: return "binoculars.fill"
        case .quiet: return "moon.fill"
        }
    }

    var tuning: Tuning {
        switch self {
        case .talk: return Tuning(gain: 9, denoise: 0.6, clarity: 0.6, auto: true)
        case .crowd: return Tuning(gain: 12, denoise: 0.9, clarity: 0.8, auto: true)
        case .far: return Tuning(gain: 18, denoise: 0.7, clarity: 0.7, auto: true)
        case .quiet: return Tuning(gain: 6, denoise: 0.35, clarity: 0.4, auto: true)
        }
    }

    static func matching(_ t: Tuning) -> Preset? {
        allCases.first { $0.tuning == t }
    }
}

// Kierunek mikrofonu. W iPhonie sa trzy: dolny, przedni (przy ekranie) i tylny (przy aparacie).
enum MicSide: String, CaseIterable, Identifiable {
    case auto, bottom, front, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatycznie"
        case .bottom: return "Dolny"
        case .front: return "Przedni (od strony ekranu)"
        case .back: return "Tylny (od strony aparatu)"
        }
    }
}
