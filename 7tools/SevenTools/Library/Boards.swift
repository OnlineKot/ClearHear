import Foundation
import SwiftUI

// Katalog soundboardow: prawdziwe nagrania z Openverse (Freesound i inne), wybrane na wolnych licencjach.
// Sam plik katalogu jest w apce i na stronie, wiec dzwieki pobiera sie dopiero po dotknieciu.

struct BoardSound: Codable, Identifiable, Hashable {
    var n: Int
    var title: String
    var original: String?
    var url: String
    var creator: String?
    var license: String
    var page: String?
    var seconds: Double

    var id: String { url }

    var licenseLabel: String { license.lowercased() == "cc0" ? "CC0" : (license.lowercased() == "pdm" ? "PD" : "CC " + license.uppercased()) }
}

struct Board: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var emoji: String
    var sounds: [BoardSound]
}

struct StarterRef: Codable, Hashable {
    var board: String
    var n: Int
}

struct BoardCatalog: Codable {
    var version: Int
    var updated: String?
    var boards: [Board]
    var starter: [StarterRef]
}

enum SoundState: Equatable {
    case idle, loading, ready
    case failed(String)
}

@MainActor
final class BoardsModel: ObservableObject {
    @Published private(set) var catalog: BoardCatalog
    @Published private(set) var state: [String: SoundState] = [:]
    @Published private(set) var starterProgress: (done: Int, total: Int)?
    @Published var starterError: String?
    @Published var lastInfo: String?

    private let hub: AudioHub
    private let store: SoundStore
    private let pads: PadsModel
    private var memory: [String: SampleBuffer] = [:]
    private let dir: URL
    private var adopted: [String: String]      // url -> id dzwieku w Moich dzwiekach

    static let remote = URL(string: "https://fastlink.teodorteo.com/7tools/boards.json")!

    init(hub: AudioHub, store: SoundStore, pads: PadsModel) {
        self.hub = hub
        self.store = store
        self.pads = pads
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("7Tools/Boards", isDirectory: true)
        dir = base
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        adopted = (UserDefaults.standard.dictionary(forKey: "boards.adopted") as? [String: String]) ?? [:]

        if let u = Bundle.main.url(forResource: "boards", withExtension: "json"),
           let d = try? Data(contentsOf: u),
           let c = try? JSONDecoder().decode(BoardCatalog.self, from: d) {
            catalog = c
        } else {
            catalog = BoardCatalog(version: 0, updated: nil, boards: [], starter: [])
        }
    }

    // ---------------------------------------------------------- katalog

    // Nowszy katalog ze strony (mozna dodawac soundboardy bez nowej wersji apki)
    func refreshCatalog() async {
        var req = URLRequest(url: Self.remote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (d, r) = try? await URLSession.shared.data(for: req),
              (r as? HTTPURLResponse)?.statusCode == 200,
              let c = try? JSONDecoder().decode(BoardCatalog.self, from: d),
              !c.boards.isEmpty else { return }
        if c.version >= catalog.version { catalog = c }
    }

    func board(_ id: String) -> Board? { catalog.boards.first { $0.id == id } }

    func sound(_ ref: StarterRef) -> BoardSound? { board(ref.board)?.sounds.first { $0.n == ref.n } }

    // ---------------------------------------------------------- pliki

    private func fileURL(_ s: BoardSound) -> URL {
        // stabilny skrot adresu (FNV-1a), bo hashValue zmienia sie miedzy uruchomieniami
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.url.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return dir.appendingPathComponent(String(h, radix: 16) + ".wav")
    }

    func isCached(_ s: BoardSound) -> Bool {
        memory[s.url] != nil || FileManager.default.fileExists(atPath: fileURL(s).path)
    }

    func stateOf(_ s: BoardSound) -> SoundState {
        state[s.url] ?? (isCached(s) ? .ready : .idle)
    }

    // Zwraca bufor: z pamieci, z dysku albo pobiera. Przy bledzie ustawia stan "failed" z kodem.
    func load(_ s: BoardSound) async -> SampleBuffer? {
        if let b = memory[s.url] { return b }
        if let d = try? Data(contentsOf: fileURL(s)), let b = WAV.decode(d) {
            let r = b.resampled(to: 48000)
            memory[s.url] = r
            state[s.url] = .ready
            return r
        }
        guard let url = URL(string: s.url) else { state[s.url] = .failed("zły adres"); return nil }
        state[s.url] = .loading
        do {
            // domyslny User-Agent systemu: serwery dzwiekow nie lubia dziwnych naglowkow
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { state[s.url] = .failed("HTTP \(code)"); return nil }
            let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0
            guard size > 0, size < 5_000_000 else { state[s.url] = .failed("plik za duży"); return nil }
            let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.moveItem(at: tmp, to: dst)
            defer { try? FileManager.default.removeItem(at: dst) }
            let raw = try Importer.load(dst, maxSeconds: 20)
            let buf = raw.peak() > 0.001 ? raw.normalized(to: 0.9) : raw
            buf.fadeEdges()
            try? WAV.encode(buf).write(to: fileURL(s))
            memory[s.url] = buf
            state[s.url] = .ready
            return buf
        } catch {
            state[s.url] = .failed("brak internetu albo błąd pliku")
            return nil
        }
    }

    func play(_ s: BoardSound) async {
        guard let b = await load(s) else { return }
        hub.mixer.play(b, tag: 21000 + s.n, gain: 0.9)
        lastInfo = s.original.map { "\($0) · \(s.creator ?? "?") · \(s.licenseLabel)" }
    }

    func downloadAll(_ board: Board) async {
        for s in board.sounds where !isCached(s) {
            _ = await load(s)
        }
    }

    // ---------------------------------------------------------- do Moich dzwiekow i do padow

    // Zapisuje dzwiek w Moich dzwiekach (z autorem i licencja). Drugi raz nie dubluje.
    @discardableResult
    func adopt(_ s: BoardSound) async -> String? {
        if let id = adopted[s.url], store.item(id) != nil { return id }
        guard let b = await load(s) else { return nil }
        let item = store.add(b, name: s.title, creator: s.creator, license: s.license,
                             licenseURL: nil, sourceURL: s.page)
        adopted[s.url] = item.id
        UserDefaults.standard.set(adopted, forKey: "boards.adopted")
        return item.id
    }

    // Wrzuca 16 dzwiekow soundboardu na pady wybranego banku (0 = A, 1 = B)
    func useAsBank(_ board: Board, bank: Int) async -> Int {
        var done = 0
        for (i, s) in board.sounds.prefix(PadsModel.perBank).enumerated() {
            if let id = await adopt(s) {
                pads.pads[bank * PadsModel.perBank + i] = PadConfig(sound: id)
                done += 1
            }
        }
        return done
    }

    // ---------------------------------------------------------- paczka startowa

    var starterDone: Bool { UserDefaults.standard.bool(forKey: "starter.v1") }

    // Przy pierwszym uruchomieniu pady dostaja prawdziwe nagrania zamiast syntezatora.
    // Jesli ktos wczesniej zmienil pady po swojemu, nie ruszamy ich.
    func installStarterIfNeeded() async {
        guard !starterDone, !catalog.starter.isEmpty else { return }
        let untouched = (0..<PadsModel.perBank).allSatisfy { pads.pads[$0].sound.hasPrefix("builtin:") }
        guard untouched else {
            UserDefaults.standard.set(true, forKey: "starter.v1")
            return
        }
        await installStarter()
    }

    func installStarter() async {
        starterError = nil
        let refs = Array(catalog.starter.prefix(PadsModel.perBank))
        starterProgress = (0, refs.count)
        var failures = 0
        var attempted = 0
        for (i, r) in refs.enumerated() {
            attempted += 1
            if let s = sound(r), let id = await adopt(s) {
                pads.pads[i].sound = id
                pads.pads[i].mode = .shot
            } else {
                failures += 1
                // cztery pierwsze padly pod rzad: pewnie brak internetu albo blokada, nie meczymy
                if failures >= 4 && failures == attempted { break }
            }
            starterProgress = (attempted, refs.count)
        }
        starterProgress = nil
        if failures == 0 || failures < attempted {
            UserDefaults.standard.set(true, forKey: "starter.v1")
        } else {
            starterError = "Nie udało się pobrać prawdziwych dźwięków. Sprawdź internet i spróbuj w Bibliotece → Soundboardy."
        }
    }
}
