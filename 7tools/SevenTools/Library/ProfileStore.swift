import Foundation
import SwiftUI

// Profile na jednym koncie. Wspolne: biblioteka dzwiekow, pobrane soundboardy, klucze AI.
// Osobne: wszystko, co ProfileScope uzna za profilowe (pady, sluchanie, IKEA, psikusy, gesty, licznik...).
// Przelaczenie zapisuje ustawienia biezacego profilu do pliku, wczytuje cudze i buduje ekrany od nowa.

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile]
    @Published private(set) var currentID: UUID
    @Published private(set) var generation = 0
    @Published var askOnLaunch: Bool { didSet { UserDefaults.standard.set(askOnLaunch, forKey: "profiles.ask") } }

    private let dir: URL
    private let ud = UserDefaults.standard

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("7Tools/Profiles", isDirectory: true)
        dir = base
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        askOnLaunch = ud.bool(forKey: "profiles.ask")
        if let d = ud.data(forKey: "profiles.list"), let l = try? JSONDecoder().decode([Profile].self, from: d), !l.isEmpty {
            profiles = l
            let cur = ud.string(forKey: "profiles.current").flatMap(UUID.init(uuidString:))
            currentID = l.contains(where: { $0.id == cur }) ? cur! : l[0].id
        } else {
            // pierwszy raz: dotychczasowe ustawienia stają sie profilem "Ja"
            let p = ProfileBook.defaultProfile()
            profiles = [p]
            currentID = p.id
            persist()
        }
    }

    var current: Profile { profiles.first { $0.id == currentID } ?? profiles[0] }

    private func persist() {
        if let d = try? JSONEncoder().encode(profiles) { ud.set(d, forKey: "profiles.list") }
        ud.set(currentID.uuidString, forKey: "profiles.current")
    }

    // ---------------------------------------------------------- pliki z ustawieniami

    private func file(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".plist") }

    private func liveScoped() -> [String: Any] { ProfileScope.extract(ud.dictionaryRepresentation()) }

    private func write(_ values: [String: Any], to id: UUID) {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) else { return }
        try? d.write(to: file(id), options: .atomic)
    }

    private func read(_ id: UUID) -> [String: Any] {
        guard let d = try? Data(contentsOf: file(id)),
              let o = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] else { return [:] }
        return o
    }

    private func clearLive() {
        for k in liveScoped().keys { ud.removeObject(forKey: k) }
    }

    // ---------------------------------------------------------- przelaczanie

    func switchTo(_ id: UUID, hub: AudioHub) {
        guard id != currentID, profiles.contains(where: { $0.id == id }) else { return }
        // wyciszamy wszystko, zanim zmienimy ustawienia
        hub.mixer.stopAll()
        hub.mixer.setTone(on: false, wave: 0, f1: 440, f2: 440, sweep: 0, gain: 0)
        hub.stopListen()
        if hub.fxOn { hub.fxOn = false }

        write(liveScoped(), to: currentID)
        clearLive()
        for (k, v) in read(id) { ud.set(v, forKey: k) }
        currentID = id
        persist()
        generation += 1
        Haptics.ok()
    }

    // ---------------------------------------------------------- zarzadzanie

    @discardableResult
    func add(name: String, emoji: String, copyCurrent: Bool) -> Profile {
        let p = Profile(name: ProfileBook.uniqueName(name, in: profiles), emoji: emoji, hue: ProfileBook.nextHue(profiles))
        if copyCurrent { write(liveScoped(), to: p.id) }
        profiles.append(p)
        persist()
        return p
    }

    func update(_ id: UUID, name: String, emoji: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        var others = profiles
        others.remove(at: i)
        profiles[i].name = ProfileBook.uniqueName(name, in: others)
        profiles[i].emoji = emoji
        persist()
    }

    func delete(_ id: UUID) {
        guard let r = ProfileBook.afterDelete(profiles, deleting: id, current: currentID) else { return }
        let wasCurrent = id == currentID
        try? FileManager.default.removeItem(at: file(id))
        profiles = r.list
        if wasCurrent {
            clearLive()
            for (k, v) in read(r.current) { ud.set(v, forKey: k) }
            currentID = r.current
            generation += 1
        }
        persist()
    }
}
