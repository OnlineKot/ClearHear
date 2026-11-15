import Foundation

// Profile na jednym koncie. "Konto" to ta apka na telefonie: wspolne sa biblioteka dzwiekow, pobrane soundboardy i klucze AI.
// Osobne dla kazdego profilu sa ustawienia: pady, sluchanie, IKEA, psikusy, gesty, licznik i reszta.
// Ta czesc nie zalezy od iOS, wiec sprawdzamy ja testem.

struct Profile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var emoji: String
    var hue: Double            // kolor awatara 0...1
    var created = Date()
}

enum ProfileScope {
    // Klucze UserDefaults, ktore naleza do profilu (dokladna nazwa albo przedrostek konczacy sie kropka)
    static let exact: Set<String> = ["pads", "spot", "micSide", "micDirectional"]
    static let prefixes = ["sampler.", "listen.", "counter.", "fake.", "bank.", "ikea.", "gestures.", "gesture.", "starter.", "ai."]

    static func isScoped(_ key: String) -> Bool {
        exact.contains(key) || prefixes.contains { key.hasPrefix($0) }
    }

    // wybiera z calego slownika tylko to, co nalezy do profilu
    static func extract(_ all: [String: Any]) -> [String: Any] {
        all.filter { isScoped($0.key) }
    }
}

enum ProfileBook {
    static let emojis = ["🙂", "😎", "🤓", "🥳", "🧑‍🎤", "🧑‍🚀", "🦊", "🐱", "🐶", "🐼", "🦄", "🐸", "🚀", "🎧", "🎸", "🎮", "🍕", "🌈", "🔥", "⭐"]

    static func defaultProfile() -> Profile { Profile(name: "Ja", emoji: "🙂", hue: 0.58) }

    // nazwa bez dubli: "Ola", "Ola 2", "Ola 3"
    static func uniqueName(_ wanted: String, in list: [Profile]) -> String {
        let base = wanted.trimmingCharacters(in: .whitespaces).isEmpty ? "Profil" : wanted.trimmingCharacters(in: .whitespaces)
        var name = base
        var n = 2
        while list.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    static func nextHue(_ list: [Profile]) -> Double {
        let used = list.map { $0.hue }
        var best = 0.0, bestGap = -1.0
        for i in 0..<12 {
            let h = Double(i) / 12
            let gap = used.map { min(abs($0 - h), 1 - abs($0 - h)) }.min() ?? 1
            if gap > bestGap { bestGap = gap; best = h }
        }
        return best
    }

    // Po usunieciu profilu: ktory ma stac sie aktywny (sasiad), nigdy nie zostawiamy pustej listy.
    static func afterDelete(_ list: [Profile], deleting id: UUID, current: UUID) -> (list: [Profile], current: UUID)? {
        guard list.count > 1, let idx = list.firstIndex(where: { $0.id == id }) else { return nil }
        var l = list
        l.remove(at: idx)
        if current != id { return (l, current) }
        return (l, l[min(idx, l.count - 1)].id)
    }
}
