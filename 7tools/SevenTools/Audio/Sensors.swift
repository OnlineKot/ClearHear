import SwiftUI
import CoreMotion
import CoreLocation
import Combine

// ------------------------------------------------------------------ ruch telefonu

// Pozycja telefonu, potrzasanie i nachylenie. Dziala tylko, gdy ktos z niego korzysta.
@MainActor
final class MotionHub: ObservableObject {
    @Published private(set) var pose: Pose = .upright
    @Published private(set) var gravity: (x: Double, y: Double, z: Double) = (0, -1, 0)
    @Published private(set) var shakes = 0

    var onPose: ((Pose, Pose) -> Void)?        // (stara, nowa)
    var onShake: (() -> Void)?

    private let mgr = CMMotionManager()
    private var clients = Set<String>()
    private var shake = ShakeDetector()
    private var t0 = Date()

    var available: Bool { mgr.isDeviceMotionAvailable }

    deinit { mgr.stopDeviceMotionUpdates() }

    func use(_ id: String) {
        let had = !clients.isEmpty
        clients.insert(id)
        if !had { start() }
    }

    func release(_ id: String) {
        clients.remove(id)
        if clients.isEmpty { stop() }
    }

    private func start() {
        guard mgr.isDeviceMotionAvailable else { return }
        t0 = Date()
        mgr.deviceMotionUpdateInterval = 1.0 / 30
        mgr.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            self.handle(m)
        }
    }

    private func stop() {
        mgr.stopDeviceMotionUpdates()
    }

    private func handle(_ m: CMDeviceMotion) {
        let g = m.gravity
        gravity = (g.x, g.y, g.z)
        let new = Pose.classify(x: g.x, y: g.y, z: g.z, previous: pose)
        if new != pose {
            let old = pose
            pose = new
            onPose?(old, new)
        }
        let u = m.userAcceleration
        let total = ((g.x + u.x) * (g.x + u.x) + (g.y + u.y) * (g.y + u.y) + (g.z + u.z) * (g.z + u.z)).squareRoot()
        if shake.feed(magnitude: total, at: Date().timeIntervalSince(t0)) {
            shakes += 1
            onShake?()
        }
    }
}

// ------------------------------------------------------------------ lokalizacja

@MainActor
final class LocationHub: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: Double?
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var placemark: CLPlacemark?
    @Published private(set) var pressure: Double?          // kPa
    @Published private(set) var relativeAltitude: Double?  // m
    @Published var saved: SavedSpot?

    struct SavedSpot: Codable, Equatable {
        var lat: Double
        var lon: Double
        var name: String
        var date: Date
    }

    private let mgr = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let altimeter = CMAltimeter()
    private var lastGeocode: CLLocation?
    private var running = false

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        status = mgr.authorizationStatus
        if let d = UserDefaults.standard.data(forKey: "spot"),
           let s = try? JSONDecoder().decode(SavedSpot.self, from: d) { saved = s }
    }

    var authorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var altimeterAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func start() {
        if status == .notDetermined { mgr.requestWhenInUseAuthorization() }
        guard !running else { return }
        running = true
        mgr.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { mgr.startUpdatingHeading() }
        if altimeterAvailable {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] d, _ in
                guard let d else { return }
                self?.pressure = d.pressure.doubleValue
                self?.relativeAltitude = d.relativeAltitude.doubleValue
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        mgr.stopUpdatingLocation()
        mgr.stopUpdatingHeading()
        altimeter.stopRelativeAltitudeUpdates()
    }

    func saveHere(name: String) {
        guard let l = location else { return }
        let s = SavedSpot(lat: l.coordinate.latitude, lon: l.coordinate.longitude, name: name, date: Date())
        saved = s
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "spot") }
    }

    func forget() {
        saved = nil
        UserDefaults.standard.removeObject(forKey: "spot")
    }

    // ---------------------------------------------------------- delegat

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if self.running && (s == .authorizedWhenInUse || s == .authorizedAlways) {
                self.mgr.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            self.location = l
            self.geocodeIfNeeded(l)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func geocodeIfNeeded(_ l: CLLocation) {
        if let last = lastGeocode, last.distance(from: l) < 80 { return }
        guard !geocoder.isGeocoding else { return }
        lastGeocode = l
        geocoder.reverseGeocodeLocation(l, preferredLocale: Locale(identifier: "pl_PL")) { [weak self] marks, _ in
            Task { @MainActor in self?.placemark = marks?.first }
        }
    }
}

// ------------------------------------------------------------------ gesty

enum GestureAction: String, CaseIterable, Identifiable {
    case none, stopAll, randomPad, toggleListen, siren, nextBank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Nic"
        case .stopAll: return "Zatrzymaj wszystko"
        case .randomPad: return "Zagraj losowy pad"
        case .toggleListen: return "Włącz/wyłącz słuchanie"
        case .siren: return "Syrena"
        case .nextBank: return "Zmień bank padów"
        }
    }
}

enum GestureTrigger: String, CaseIterable, Identifiable {
    case shake, faceDown, upsideDown, tiltLeft, tiltRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shake: return "Potrząśnięcie"
        case .faceDown: return "Ekranem w dół"
        case .upsideDown: return "Do góry nogami"
        case .tiltLeft: return "Na lewy bok"
        case .tiltRight: return "Na prawy bok"
        }
    }

    var symbol: String {
        switch self {
        case .shake: return "iphone.radiowaves.left.and.right"
        case .faceDown: return "iphone.gen3.slash"
        case .upsideDown: return "arrow.triangle.2.circlepath"
        case .tiltLeft: return "rotate.left.fill"
        case .tiltRight: return "rotate.right.fill"
        }
    }

    var defaultAction: GestureAction {
        switch self {
        case .shake: return .randomPad
        case .faceDown: return .stopAll
        case .upsideDown: return .toggleListen
        case .tiltLeft: return .nextBank
        case .tiltRight: return .siren
        }
    }
}

// Wykonuje akcje przypisane do gestow. Zyje przez caly czas dzialania apki.
@MainActor
final class GestureCenter: ObservableObject {
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "gestures.on"); sync() } }
    @Published private(set) var mapping: [GestureTrigger: GestureAction]
    @Published private(set) var last: String?

    private let motion: MotionHub
    private let hub: AudioHub
    private let pads: PadsModel
    private let store: SoundStore

    init(motion: MotionHub, hub: AudioHub, pads: PadsModel, store: SoundStore) {
        self.motion = motion
        self.hub = hub
        self.pads = pads
        self.store = store
        enabled = UserDefaults.standard.bool(forKey: "gestures.on")
        var m: [GestureTrigger: GestureAction] = [:]
        for t in GestureTrigger.allCases {
            let raw = UserDefaults.standard.string(forKey: "gesture." + t.rawValue)
            m[t] = raw.flatMap(GestureAction.init(rawValue:)) ?? t.defaultAction
        }
        mapping = m
        motion.onShake = { [weak self] in self?.fire(.shake) }
        motion.onPose = { [weak self] _, new in
            switch new {
            case .faceDown: self?.fire(.faceDown)
            case .upsideDown: self?.fire(.upsideDown)
            case .landscapeLeft: self?.fire(.tiltLeft)
            case .landscapeRight: self?.fire(.tiltRight)
            default: break
            }
        }
        sync()
    }

    func set(_ t: GestureTrigger, _ a: GestureAction) {
        mapping[t] = a
        UserDefaults.standard.set(a.rawValue, forKey: "gesture." + t.rawValue)
    }

    private func sync() {
        if enabled { motion.use("gestures") } else { motion.release("gestures") }
    }

    private func fire(_ t: GestureTrigger) {
        guard enabled, let a = mapping[t], a != .none else { return }
        last = t.title + " → " + a.title
        Haptics.tap(.medium)
        switch a {
        case .none: break
        case .stopAll:
            hub.mixer.stopAll()
        case .randomPad:
            let filled = (0..<PadsModel.perBank).filter { !pads.config($0).sound.isEmpty }
            if let s = filled.randomElement() { pads.press(s) }
        case .toggleListen:
            Task { await hub.toggleListen() }
        case .siren:
            if let b = store.buffer("builtin:siren") { hub.mixer.play(b, tag: 8800, gain: 0.8) }
        case .nextBank:
            pads.bank = (pads.bank + 1) % PadsModel.banks
        }
    }
}
