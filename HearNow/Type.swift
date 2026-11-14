import SwiftUI

// Czcionka to zwykla systemowa SF Pro. Dokladamy tylko odstep miedzy literami.
// Waga: semibold na co dzien, bold na tytuly. Nic grubszego.

struct Spaced: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight

    // im wiekszy tekst, tym wiekszy odstep
    private var extra: CGFloat {
        switch style {
        case .largeTitle: return 1.0
        case .title, .title2: return 0.8
        case .title3, .headline: return 0.6
        default: return 0.5
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(style, weight: weight))
            .tracking(extra)
    }
}

extension View {
    func spaced(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> some View {
        modifier(Spaced(style: style, weight: weight))
    }
}
