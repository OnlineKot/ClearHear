import Foundation

// Schemat IKEA: typowy uklad sklepu (wystawa na pietrze jedna sciezka "dlugiej drogi", na parterze hala, magazyn, kasy).
// To NIE jest oficjalny plan konkretnego sklepu. Uklad Katowic moze sie roznic, dlatego pozycje i kierunek kalibruje sie w sklepie.
// Sam kod nie zalezy od iOS, wiec sprawdzamy go testem.

struct P: Equatable {
    var x: Double
    var y: Double
}

struct Zone: Identifiable, Hashable {
    let id: String
    let name: String
    let floor: Int          // 1 = wystawa (pietro), 0 = parter (hala, magazyn, kasy)
    let s: Double           // odleglosc wzdluz sciezki tego pietra, w metrach
    let emoji: String
    let keywords: [String]  // czym ludzie nazywaja to, co tam leży (bez polskich znakow, male litery)
}

enum IkeaMap {
    // wspolrzedne w metrach, y rosnie w dol (jak na ekranie), gora mapy = polnoc planu
    static let showroom: [P] = [
        P(x: 10, y: 10), P(x: 110, y: 10), P(x: 110, y: 24), P(x: 10, y: 24), P(x: 10, y: 38),
        P(x: 110, y: 38), P(x: 110, y: 52), P(x: 10, y: 52), P(x: 10, y: 66), P(x: 110, y: 66),
    ]
    static let ground: [P] = [
        P(x: 110, y: 10), P(x: 10, y: 10), P(x: 10, y: 24), P(x: 110, y: 24), P(x: 110, y: 38),
        P(x: 10, y: 38), P(x: 10, y: 52), P(x: 110, y: 52), P(x: 110, y: 66), P(x: 10, y: 66),
    ]

    static func path(_ floor: Int) -> [P] { floor == 1 ? showroom : ground }

    static let zones: [Zone] = [
        // pietro: wystawa
        Zone(id: "wejscie", name: "Wejście na wystawę", floor: 1, s: 0, emoji: "🛗", keywords: ["wejscie", "schody", "ruchome"]),
        Zone(id: "male", name: "Małe mieszkania", floor: 1, s: 20, emoji: "🏘️", keywords: ["male mieszkanie", "kawalerka", "male przestrzenie"]),
        Zone(id: "salony", name: "Salony: sofy i fotele", floor: 1, s: 55, emoji: "🛋️", keywords: ["sofa", "kanapa", "fotel", "wersalka", "narozik", "stolik kawowy", "puf", "salon"]),
        Zone(id: "rtv", name: "Salony: RTV i regały", floor: 1, s: 85, emoji: "📺", keywords: ["rtv", "tv", "telewizor", "szafka rtv", "komoda rtv"]),
        Zone(id: "regaly", name: "Przechowywanie: regały", floor: 1, s: 130, emoji: "📚", keywords: ["regal", "kallax", "billy", "szafka", "witryna", "komoda", "przechowywanie"]),
        Zone(id: "biura", name: "Biura domowe", floor: 1, s: 165, emoji: "💻", keywords: ["biurko", "krzeslo biurowe", "fotel biurowy", "biuro", "organizer biurkowy"]),
        Zone(id: "restauracja", name: "Restauracja", floor: 1, s: 205, emoji: "🍽️", keywords: ["restauracja", "klopsiki", "jedzenie", "kawa", "obiad", "toaleta", "wc"]),
        Zone(id: "jadalnie", name: "Jadalnie", floor: 1, s: 245, emoji: "🪑", keywords: ["stol", "krzesla", "krzeslo", "jadalnia", "lawa", "stol jadalniany"]),
        Zone(id: "kuchnie", name: "Kuchnie", floor: 1, s: 285, emoji: "🍳", keywords: ["kuchnia", "szafki kuchenne", "blat", "zlew", "metod", "fronty", "okap"]),
        Zone(id: "lozka", name: "Sypialnie: łóżka", floor: 1, s: 360, emoji: "🛏️", keywords: ["lozko", "lozka", "rama lozka", "sypialnia", "szafka nocna", "malm", "brimnes"]),
        Zone(id: "materace", name: "Materace i poduszki", floor: 1, s: 385, emoji: "😴", keywords: ["materac", "poduszka", "koldra", "topper", "podklad"]),
        Zone(id: "pax", name: "Garderoby i szafy (PAX)", floor: 1, s: 415, emoji: "👔", keywords: ["szafa", "pax", "garderoba", "szafa przesuwna", "drzwi do szafy"]),
        Zone(id: "lazienki", name: "Łazienki", floor: 1, s: 470, emoji: "🛁", keywords: ["lazienka", "umywalka", "szafka lazienkowa", "lustro lazienkowe", "bateria", "prysznic"]),
        Zone(id: "dzieci", name: "Pokoje dziecięce", floor: 1, s: 505, emoji: "🧸", keywords: ["dzieci", "dziecko", "lozeczko", "kojec", "krzeselko", "pokoj dzieciecy"]),
        Zone(id: "smaland", name: "Småland (strefa zabaw)", floor: 1, s: 525, emoji: "🎠", keywords: ["smaland", "zabawa", "plac zabaw"]),
        Zone(id: "schody", name: "Zejście do hali", floor: 1, s: 556, emoji: "⬇️", keywords: ["zejscie", "schody w dol"]),
        // parter: hala targowa
        Zone(id: "dekoracje", name: "Hala: dekoracje i ramki", floor: 0, s: 20, emoji: "🖼️", keywords: ["ramka", "obraz", "plakat", "swieca", "swiece", "wazon", "zegar", "dekoracja", "lustro"]),
        Zone(id: "tekstylia", name: "Hala: tekstylia", floor: 0, s: 60, emoji: "🧵", keywords: ["poscie", "zaslona", "firana", "dywan", "koc", "narzuta", "poszewka", "reczniki", "recznik", "prescieradlo", "zaslony"]),
        Zone(id: "naczynia", name: "Hala: naczynia i garnki", floor: 0, s: 140, emoji: "🥘", keywords: ["garnek", "patelnia", "talerz", "talerze", "szklanka", "szklanki", "kubek", "sztucce", "noz", "nozyk", "deska", "naczynia", "miska"]),
        Zone(id: "oswietlenie", name: "Hala: oświetlenie", floor: 0, s: 180, emoji: "💡", keywords: ["lampa", "lampka", "zarowka", "oswietlenie", "zyrandol", "kinkiet", "led", "swiatelka"]),
        Zone(id: "rosliny", name: "Hala: rośliny i doniczki", floor: 0, s: 245, emoji: "🪴", keywords: ["roslina", "kwiat", "doniczka", "oslonka", "sztuczne kwiaty", "ziemia"]),
        Zone(id: "zabawki", name: "Hala: zabawki", floor: 0, s: 275, emoji: "🧩", keywords: ["zabawka", "zabawki", "klocki", "pluszak", "misie", "gry"]),
        Zone(id: "organizacja", name: "Hala: pojemniki i organizacja", floor: 0, s: 305, emoji: "📦", keywords: ["pojemnik", "pudelko", "kosz", "wieszak", "organizer", "skrzynka", "worek", "wieszaki", "haczyki"]),
        Zone(id: "lazienka_hala", name: "Hala: akcesoria łazienkowe", floor: 0, s: 322, emoji: "🧴", keywords: ["dywanik lazienkowy", "kosz na pranie", "zaslona prysznicowa", "dozownik", "szczotka do wc", "mydelniczka"]),
        Zone(id: "magazyn", name: "Magazyn samoobsługowy", floor: 0, s: 390, emoji: "🏗️", keywords: ["magazyn", "alejka", "wozek", "paleta", "odbior"]),
        Zone(id: "kasy", name: "Kasy", floor: 0, s: 470, emoji: "🧾", keywords: ["kasa", "kasy", "platnosc", "zaplata", "samoobslugowa"]),
        Zone(id: "bistro", name: "Bistro i szwedzki sklep", floor: 0, s: 500, emoji: "🌭", keywords: ["bistro", "hot dog", "hotdog", "lody", "szwedzki sklep", "czekolada", "klopsiki mrozone", "spozywczy"]),
        Zone(id: "wyjscie", name: "Wyjście i punkt zwrotów", floor: 0, s: 545, emoji: "🚪", keywords: ["wyjscie", "zwrot", "zwroty", "reklamacja", "obsluga klienta", "parking"]),
    ]

    static func zone(_ id: String) -> Zone? { zones.first { $0.id == id } }

    // ---------------------------------------------------------------- geometria sciezki

    static func length(_ pts: [P]) -> Double {
        var l = 0.0
        for i in 1..<pts.count { l += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        return l
    }

    static func floorLength(_ floor: Int) -> Double { length(path(floor)) }

    // pozycja i kierunek (stopnie od "gory mapy" zgodnie z ruchem wskazowek) w punkcie s sciezki
    static func pointAt(floor: Int, s: Double) -> (p: P, bearing: Double) {
        let pts = path(floor)
        var rest = max(0, min(s, floorLength(floor)))
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if rest <= seg || i == pts.count - 1 {
                let t = seg > 0 ? min(1, rest / seg) : 0
                let bearing = atan2(b.x - a.x, -(b.y - a.y)) * 180 / .pi
                return (P(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), (bearing + 360).truncatingRemainder(dividingBy: 360))
            }
            rest -= seg
        }
        return (pts[0], 0)
    }

    // odcinek sciezki od s1 do s2 jako lamana (do narysowania trasy)
    static func slice(floor: Int, from s1: Double, to s2: Double) -> [P] {
        let a = min(s1, s2), b = max(s1, s2)
        var out = [pointAt(floor: floor, s: a).p]
        let pts = path(floor)
        var acc = 0.0
        for i in 1..<pts.count {
            acc += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            if acc > a + 0.01 && acc < b - 0.01 { out.append(pts[i]) }
        }
        out.append(pointAt(floor: floor, s: b).p)
        return s1 <= s2 ? out : out.reversed()
    }

    // ---------------------------------------------------------------- pozycja globalna (wystawa, potem parter)

    static func global(floor: Int, s: Double) -> Double { floor == 1 ? s : floorLength(1) + s }

    static func place(global g: Double) -> (floor: Int, s: Double) {
        let l1 = floorLength(1)
        if g <= l1 { return (1, max(0, g)) }
        return (0, min(floorLength(0), g - l1))
    }

    // Magazyn: numer alejki z metki ceny -> miejsce na sciezce parteru (alejki 1..maxAisle rozlozone rowno)
    static let warehouseStart = 345.0
    static let warehouseEnd = 435.0

    static func aisle(_ n: Int, maxAisle: Int = 40) -> Double {
        let k = Double(max(1, min(n, maxAisle)) - 1) / Double(max(1, maxAisle - 1))
        return warehouseStart + (warehouseEnd - warehouseStart) * k
    }

    // ---------------------------------------------------------------- trasa

    struct Leg {
        var floor: Int
        var points: [P]
        var meters: Double
    }

    struct Route {
        var legs: [Leg]
        var meters: Double
        var forward: Bool            // zgodnie ze strzalkami (kierunek zwiedzania) czy pod prad
        var passing: [Zone]          // co mija po drodze
    }

    static func route(from: (floor: Int, s: Double), to: (floor: Int, s: Double)) -> Route {
        let g1 = global(floor: from.floor, s: from.s), g2 = global(floor: to.floor, s: to.s)
        let forward = g2 >= g1
        let lo = min(g1, g2), hi = max(g1, g2)
        let l1 = floorLength(1)
        var legs: [Leg] = []
        // czesc na pietrze 1
        if lo < l1 {
            let a = lo, b = min(hi, l1)
            if b - a > 0.01 {
                let pts = slice(floor: 1, from: forward ? a : b, to: forward ? b : a)
                legs.append(Leg(floor: 1, points: pts, meters: b - a))
            }
        }
        if hi > l1 {
            let a = max(lo, l1) - l1, b = hi - l1
            if b - a > 0.01 {
                let pts = slice(floor: 0, from: forward ? a : b, to: forward ? b : a)
                legs.append(Leg(floor: 0, points: pts, meters: b - a))
            }
        }
        if !forward { legs.reverse() }
        let passing = zones.filter {
            let g = global(floor: $0.floor, s: $0.s)
            return g > lo + 1 && g < hi - 1
        }
        let ordered = forward ? passing : passing.reversed()
        return Route(legs: legs, meters: hi - lo, forward: forward, passing: ordered)
    }

    // Najblizsze miejsce na sciezce do punktu (do klikniecia w mape)
    static func nearestZone(to p: P, floor: Int, maxDistance: Double = 9) -> Zone? {
        var best: (Zone, Double)?
        for z in zones where z.floor == floor {
            let q = pointAt(floor: floor, s: z.s).p
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < maxDistance && (best == nil || d < best!.1) { best = (z, d) }
        }
        return best?.0
    }

    // ---------------------------------------------------------------- szukanie po nazwie rzeczy

    static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl"))
            .replacingOccurrences(of: "ł", with: "l")
    }

    // Zwraca dzialy, w ktorych najpewniej lezy dana rzecz, od najlepszego
    static func find(_ query: String) -> [Zone] {
        let q = normalize(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var scored: [(Zone, Int)] = []
        for z in zones {
            var score = 0
            if normalize(z.name).contains(q) { score += 5 }
            for k in z.keywords {
                if k == q { score += 10 }
                else if q.contains(k) { score += 6 + k.count / 4 }
                else if k.contains(q) && q.count >= 3 { score += 4 }
            }
            // pojedyncze slowa zapytania
            for w in q.split(separator: " ") where w.count >= 3 {
                if z.keywords.contains(where: { $0 == String(w) }) { score += 5 }
            }
            if score > 0 { scored.append((z, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    // Lista zakupow w kolejnosci zwiedzania sciezki, zaczynajac od pozycji
    static func order(_ items: [(name: String, zone: Zone)], from g: Double) -> [(name: String, zone: Zone)] {
        let forwardOnes = items.filter { global(floor: $0.zone.floor, s: $0.zone.s) >= g - 1 }
            .sorted { global(floor: $0.zone.floor, s: $0.zone.s) < global(floor: $1.zone.floor, s: $1.zone.s) }
        let behind = items.filter { global(floor: $0.zone.floor, s: $0.zone.s) < g - 1 }
            .sorted { global(floor: $0.zone.floor, s: $0.zone.s) < global(floor: $1.zone.floor, s: $1.zone.s) }
        return forwardOnes + behind
    }
}

// Kierunek: kompas telefonu to inny uklad niz plan sklepu. Offset to roznica miedzy nimi, uczona w czasie marszu.
enum HeadingCal {
    static func diff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    static func norm(_ a: Double) -> Double { (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

    // offset taki, ze (kompas - offset) = kierunek na planie
    static func offset(compass: Double, pathBearing: Double) -> Double { norm(compass - pathBearing) }

    // powolne dociaganie offsetu do tego, co widac w marszu zgodnie ze sciezka
    static func blend(current: Double, compass: Double, pathBearing: Double, alpha: Double = 0.08) -> Double {
        let target = offset(compass: compass, pathBearing: pathBearing)
        return norm(current + diff(target, current) * alpha)
    }

    static func mapHeading(compass: Double, offset: Double) -> Double { norm(compass - offset) }
}
