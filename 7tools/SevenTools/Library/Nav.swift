import Foundation
import SwiftUI
import CoreMotion
import CoreLocation

// ------------------------------------------------------------------ kompas (tylko kierunek, bez lokalizacji GPS)

@MainActor
final class CompassHub: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var heading: Double?       // wygladzony, stopnie od polnocy
    @Published private(set) var accuracy: Double = -1

    private let mgr = CLLocationManager()
    private var running = false

    override init() {
        super.init()
        mgr.delegate = self
        mgr.headingFilter = 2
    }

    var available: Bool { CLLocationManager.headingAvailable() }

    func start() {
        // kompas zwykle dziala bez zgody, ale na wszelki wypadek prosimy o te sama zgode, co w "Gdzie jestem"
        if mgr.authorizationStatus == .notDetermined { mgr.requestWhenInUseAuthorization() }
        guard !running, available else { return }
        running = true
        mgr.startUpdatingHeading()
    }

    func stop() {
        guard running else { return }
        running = false
        mgr.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.magneticHeading
        let acc = h.headingAccuracy
        Task { @MainActor in
            self.accuracy = acc
            guard v >= 0 else { return }
            if let old = self.heading {
                // wygladzanie po okregu, zeby strzalka nie drzala
                self.heading = HeadingCal.norm(old + HeadingCal.diff(v, old) * 0.25)
            } else {
                self.heading = v
            }
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

// ------------------------------------------------------------------ stan nawigacji

struct ListItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var zoneID: String
    var aisle: Int? = nil
    var done = false
}

struct Landmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var floor: Int
    var s: Double
}

@MainActor
final class NavModel: ObservableObject {
    @Published var floor = 1
    @Published var s = 0.0
    @Published var viewFloor = 1
    @Published var placed = false                 // czy ktos juz ustawil, gdzie jest
    @Published var destinationID: String?
    @Published var destinationAisle: Int?
    @Published var list: [ListItem] = []
    @Published var landmarks: [Landmark] = []
    @Published var headingOffset = 0.0
    @Published var headingSet = false
    @Published var autoHeading = true
    @Published var maxAisle = 40
    @Published var strideScale = 1.0
    @Published private(set) var reverse = false   // idziemy pod prad?
    @Published private(set) var walking = false
    @Published var lastEvent = ""

    let compass = CompassHub()
    private let pedometer = CMPedometer()
    private var lastDistance = 0.0
    private var rawSinceAnchor = 0.0
    private var anchorG: Double?
    private var tracking = false
    private var lastStepAt = Date.distantPast

    private static let key = "ikea.nav.v1"

    private struct Stored: Codable {
        var floor: Int; var s: Double; var placed: Bool
        var destinationID: String?; var destinationAisle: Int?
        var list: [ListItem]; var landmarks: [Landmark]
        var headingOffset: Double; var headingSet: Bool; var autoHeading: Bool
        var maxAisle: Int; var strideScale: Double
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let t = try? JSONDecoder().decode(Stored.self, from: d) {
            floor = t.floor; s = t.s; placed = t.placed; viewFloor = t.floor
            destinationID = t.destinationID; destinationAisle = t.destinationAisle
            list = t.list; landmarks = t.landmarks
            headingOffset = t.headingOffset; headingSet = t.headingSet; autoHeading = t.autoHeading
            maxAisle = t.maxAisle; strideScale = t.strideScale
        }
    }

    func save() {
        let t = Stored(floor: floor, s: s, placed: placed, destinationID: destinationID, destinationAisle: destinationAisle,
                       list: list, landmarks: landmarks, headingOffset: headingOffset, headingSet: headingSet,
                       autoHeading: autoHeading, maxAisle: maxAisle, strideScale: strideScale)
        if let d = try? JSONEncoder().encode(t) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    // ---------------------------------------------------------- pozycja

    var global: Double { IkeaMap.global(floor: floor, s: s) }
    var pathBearing: Double { IkeaMap.pointAt(floor: floor, s: s).bearing }

    // kierunek, w ktorym patrzy telefon, w ukladzie planu (nil bez kompasu albo bez kalibracji)
    var mapHeading: Double? {
        guard headingSet, let c = compass.heading else { return nil }
        return HeadingCal.mapHeading(compass: c, offset: headingOffset)
    }

    // najblizszy dzial wzdluz sciezki (do napisu "jestes przy")
    var nearestZone: Zone? {
        IkeaMap.zones.filter { $0.floor == floor }.min { abs($0.s - s) < abs($1.s - s) }
    }

    var nearestDistance: Double { nearestZone.map { abs($0.s - s) } ?? 0 }

    func setPosition(zone: Zone) {
        learnStride(newG: IkeaMap.global(floor: zone.floor, s: zone.s))
        floor = zone.floor
        s = zone.s
        viewFloor = zone.floor
        placed = true
        lastEvent = "Jesteś: \(zone.name)"
        save()
    }

    func setPosition(floor f: Int, s newS: Double) {
        learnStride(newG: IkeaMap.global(floor: f, s: newS))
        floor = f
        s = max(0, min(newS, IkeaMap.floorLength(f)))
        viewFloor = f
        placed = true
        save()
    }

    func setPosition(aisle n: Int) {
        setPosition(floor: 0, s: IkeaMap.aisle(n, maxAisle: maxAisle))
        lastEvent = "Jesteś w magazynie, alejka \(n)"
    }

    func nudge(_ meters: Double) {
        move(meters)
        save()
    }

    // po poprawce pozycji uczymy sie dlugosci kroku: ile naprawde przeszlismy vs ile mierzyl krokomierz
    private func learnStride(newG: Double) {
        defer { anchorG = newG; rawSinceAnchor = 0 }
        guard placed, let a = anchorG, rawSinceAnchor > 12 else { return }
        let actual = abs(newG - a)
        guard actual > 12 else { return }
        let ratio = actual / rawSinceAnchor
        if ratio > 0.5 && ratio < 2 {
            strideScale = min(1.6, max(0.6, strideScale * 0.5 + ratio * 0.5))
        }
    }

    // ---------------------------------------------------------- kierunek

    func calibrateHeading() {
        guard let c = compass.heading else { lastEvent = "Brak kompasu. Odsuń telefon od metalu."; return }
        headingOffset = HeadingCal.offset(compass: c, pathBearing: reverse ? HeadingCal.norm(pathBearing + 180) : pathBearing)
        headingSet = true
        lastEvent = "Kierunek skalibrowany"
        save()
    }

    func toggleReverse() { reverse.toggle() }

    // ---------------------------------------------------------- cel

    var destination: (floor: Int, s: Double, name: String)? {
        if let a = destinationAisle { return (0, IkeaMap.aisle(a, maxAisle: maxAisle), "Magazyn, alejka \(a)") }
        if let id = destinationID, let z = IkeaMap.zone(id) { return (z.floor, z.s, z.name) }
        return nil
    }

    func setDestination(zone: Zone) {
        destinationID = zone.id
        destinationAisle = nil
        viewFloor = placed ? floor : zone.floor
        lastEvent = "Cel: \(zone.name)"
        save()
    }

    func setDestination(aisle n: Int) {
        destinationAisle = max(1, min(n, maxAisle))
        destinationID = nil
        lastEvent = "Cel: magazyn, alejka \(n)"
        save()
    }

    func clearDestination() {
        destinationID = nil
        destinationAisle = nil
        save()
    }

    var route: IkeaMap.Route? {
        guard placed, let d = destination else { return nil }
        return IkeaMap.route(from: (floor, s), to: (d.floor, d.s))
    }

    // Krotki opis nastepnego kroku: co jest po drodze i gdzie skret
    func instruction() -> String? {
        guard let r = route, let d = destination else { return nil }
        if r.meters < 6 { return "Jesteś na miejscu: \(d.name)" }
        let steps = Int(r.meters / (0.72 * max(0.5, strideScale)))
        var out = r.forward ? "Idź zgodnie ze strzałkami" : "Wróć pod prąd (strzałki będą z tyłu)"
        out += ". Do celu około \(Int(r.meters)) m (\(steps) kroków)."
        // pierwszy zakret
        let pts = r.legs.first?.points ?? []
        if pts.count >= 3 {
            var dist = 0.0
            for i in 1..<(pts.count - 1) {
                dist += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
                let b1 = atan2(pts[i].x - pts[i - 1].x, -(pts[i].y - pts[i - 1].y)) * 180 / .pi
                let b2 = atan2(pts[i + 1].x - pts[i].x, -(pts[i + 1].y - pts[i].y)) * 180 / .pi
                let turn = HeadingCal.diff(b2, b1)
                if abs(turn) > 45 {
                    out += " Za \(Int(dist)) m skręć w \(turn > 0 ? "prawo" : "lewo")."
                    break
                }
            }
        }
        if let first = r.passing.first, first.id != destinationID { out += " Po drodze: \(first.name)." }
        return out
    }

    // ---------------------------------------------------------- lista zakupow

    func add(item name: String, zone: Zone? = nil, aisle: Int? = nil) {
        let z = zone ?? IkeaMap.find(name).first
        guard let z else { return }
        list.append(ListItem(name: name, zoneID: z.id, aisle: aisle))
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].done.toggle()
        save()
    }

    func remove(at offsets: IndexSet) {
        list.remove(atOffsets: offsets)
        save()
    }

    // lista w kolejnosci zwiedzania od aktualnej pozycji (zrobione na koncu)
    func orderedList() -> [ListItem] {
        let open = list.filter { !$0.done }
        let pairs = open.compactMap { it -> (name: String, zone: Zone)? in
            IkeaMap.zone(it.zoneID).map { (it.name, $0) }
        }
        let order = IkeaMap.order(pairs, from: placed ? global : 0).map { $0.name }
        let sorted = order.compactMap { n in open.first { $0.name == n } }
        // elementy o tych samych nazwach nie gubia sie
        let rest = open.filter { o in !sorted.contains(where: { $0.id == o.id }) }
        return sorted + rest + list.filter { $0.done }
    }

    func goToNextOnList() {
        guard let n = orderedList().first(where: { !$0.done }), let z = IkeaMap.zone(n.zoneID) else { return }
        if let a = n.aisle { setDestination(aisle: a) } else { setDestination(zone: z) }
    }

    func note(landmark name: String) {
        landmarks.append(Landmark(name: name, floor: floor, s: s))
        lastEvent = "Zapamiętano: \(name)"
        save()
    }

    // ---------------------------------------------------------- kroki

    func startTracking() {
        compass.start()
        guard !tracking, CMPedometer.isStepCountingAvailable() else { return }
        tracking = true
        lastDistance = 0
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            let dist = data.distance?.doubleValue ?? Double(truncating: data.numberOfSteps) * 0.7
            Task { @MainActor in self?.onDistance(dist) }
        }
    }

    func stopTracking() {
        compass.stop()
        guard tracking else { return }
        tracking = false
        pedometer.stopUpdates()
    }

    private func onDistance(_ total: Double) {
        let delta = total - lastDistance
        lastDistance = total
        guard delta > 0, delta < 20, placed else { return }
        rawSinceAnchor += delta
        lastStepAt = Date()
        walking = true

        // kierunek ruchu: zgodnie ze sciezka czy pod prad, na podstawie kompasu (jesli skalibrowany)
        var sign = reverse ? -1.0 : 1.0
        if autoHeading, headingSet, let h = mapHeading {
            let along = HeadingCal.diff(h, pathBearing)
            if abs(along) < 70 { sign = 1 } else if abs(along) > 110 { sign = -1 }
        }
        move(delta * strideScale * sign)

        // dociaganie kierunku: gdy idziemy zgodnie ze sciezka, kompas ma sie zgadzac z jej kierunkiem
        if autoHeading, let c = compass.heading, delta > 0.3 {
            let pb = sign > 0 ? pathBearing : HeadingCal.norm(pathBearing + 180)
            if headingSet {
                headingOffset = HeadingCal.blend(current: headingOffset, compass: c, pathBearing: pb, alpha: 0.04)
            }
        }
        if Int(rawSinceAnchor) % 5 == 0 { save() }
    }

    // przesuwa wzdluz sciezki, przechodzac miedzy pietrami
    private func move(_ meters: Double) {
        var g = global + meters
        let total = IkeaMap.floorLength(1) + IkeaMap.floorLength(0)
        g = max(0, min(total, g))
        let p = IkeaMap.place(global: g)
        if p.floor != floor { viewFloor = p.floor }
        floor = p.floor
        s = p.s
    }

    func tickWalking() {
        if walking && Date().timeIntervalSince(lastStepAt) > 2.5 { walking = false }
    }
}
