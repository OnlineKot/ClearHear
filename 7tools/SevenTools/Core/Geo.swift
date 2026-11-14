import Foundation

// Odleglosci, kierunki, wschod i zachod slonca. Bez CoreLocation, zeby dalo sie to sprawdzic testem.
enum Geo {
    static let earthR = 6_371_000.0

    // odleglosc w metrach (haversine)
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthR * asin(min(1, a.squareRoot()))
    }

    // azymut z punktu 1 do 2, w stopniach 0...360 (0 = polnoc)
    static func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    static func compassName(_ deg: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[i]
    }

    // 50°03'41.2"N
    static func dms(_ value: Double, positive: String, negative: String) -> String {
        let hemi = value >= 0 ? positive : negative
        let v = abs(value)
        let d = Int(v)
        let m = Int((v - Double(d)) * 60)
        let s = ((v - Double(d)) * 60 - Double(m)) * 60
        return String(format: "%d°%02d'%04.1f\"%@", d, m, s, hemi)
    }

    static func distanceText(_ m: Double) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.1f km", m / 1000)
    }
}

// Wschod i zachod slonca (uproszczony algorytm NOAA, dokladnosc ok. 2 minuty).
enum Sun {
    // zwraca minuty od polnocy UTC danego dnia; nil gdy slonce nie wschodzi/nie zachodzi (doby polarne)
    static func times(dayOfYear n: Int, lat: Double, lon: Double) -> (rise: Double, set: Double)? {
        let g = 2 * Double.pi / 365 * Double(n - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let latR = lat * .pi / 180
        let cosH = (cos(90.833 * .pi / 180) / (cos(latR) * cos(decl))) - tan(latR) * tan(decl)
        guard cosH >= -1 && cosH <= 1 else { return nil }
        let ha = acos(cosH) * 180 / .pi
        let rise = 720 - 4 * (lon + ha) - eqTime
        let set = 720 - 4 * (lon - ha) - eqTime
        return (rise, set)
    }

    static func hhmm(_ minutes: Double, utcOffsetMinutes: Int) -> String {
        var m = Int((minutes + Double(utcOffsetMinutes)).rounded())
        m = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

// Przeliczanie jednostek: kazda kategoria ma jednostke bazowa i mnozniki.
enum Units {
    struct Unit: Hashable { let name: String; let toBase: Double }
    struct Category: Identifiable, Hashable {
        let id: String
        let title: String
        let units: [Unit]
        var isTemperature: Bool { id == "temp" }
    }

    static let all: [Category] = [
        Category(id: "len", title: "Długość", units: [
            Unit(name: "mm", toBase: 0.001), Unit(name: "cm", toBase: 0.01), Unit(name: "m", toBase: 1),
            Unit(name: "km", toBase: 1000), Unit(name: "cal", toBase: 0.0254), Unit(name: "stopa", toBase: 0.3048),
            Unit(name: "jard", toBase: 0.9144), Unit(name: "mila", toBase: 1609.344), Unit(name: "mila morska", toBase: 1852),
        ]),
        Category(id: "mass", title: "Masa", units: [
            Unit(name: "g", toBase: 0.001), Unit(name: "kg", toBase: 1), Unit(name: "t", toBase: 1000),
            Unit(name: "uncja", toBase: 0.028349523), Unit(name: "funt", toBase: 0.45359237),
        ]),
        Category(id: "speed", title: "Prędkość", units: [
            Unit(name: "m/s", toBase: 1), Unit(name: "km/h", toBase: 1 / 3.6), Unit(name: "mph", toBase: 0.44704),
            Unit(name: "węzeł", toBase: 0.514444),
        ]),
        Category(id: "vol", title: "Objętość", units: [
            Unit(name: "ml", toBase: 0.001), Unit(name: "l", toBase: 1), Unit(name: "łyżeczka", toBase: 0.00492892),
            Unit(name: "szklanka (250 ml)", toBase: 0.25), Unit(name: "galon (US)", toBase: 3.785411784),
        ]),
        Category(id: "data", title: "Dane", units: [
            Unit(name: "B", toBase: 1), Unit(name: "KB", toBase: 1024), Unit(name: "MB", toBase: 1_048_576),
            Unit(name: "GB", toBase: 1_073_741_824), Unit(name: "TB", toBase: 1_099_511_627_776),
        ]),
        Category(id: "temp", title: "Temperatura", units: [
            Unit(name: "°C", toBase: 1), Unit(name: "°F", toBase: 1), Unit(name: "K", toBase: 1),
        ]),
    ]

    static func convert(_ v: Double, from: Unit, to: Unit, in cat: Category) -> Double {
        if cat.isTemperature {
            var c = v
            switch from.name { case "°F": c = (v - 32) * 5 / 9; case "K": c = v - 273.15; default: break }
            switch to.name { case "°F": return c * 9 / 5 + 32; case "K": return c + 273.15; default: return c }
        }
        return v * from.toBase / to.toBase
    }
}
