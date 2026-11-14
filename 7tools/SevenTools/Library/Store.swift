import Foundation

// Jeden dzwiek na liscie. Wbudowane maja id "builtin:...", reszta to UUID.
struct SoundItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var seconds: Double
    var creator: String? = nil
    var license: String? = nil
    var licenseURL: String? = nil
    var sourceURL: String? = nil

    var builtin: Bool { id.hasPrefix("builtin:") }

    var licenseLabel: String? {
        guard let l = license, !l.isEmpty else { return nil }
        return l.lowercased() == "cc0" ? "CC0" : "CC " + l.uppercased()
    }
}

// Dzwieki zapisane w telefonie: pliki WAV w Application Support/7Tools/Sounds i spis w index.json.
@MainActor
final class SoundStore: ObservableObject {
    @Published private(set) var user: [SoundItem] = []

    private var cache: [String: SampleBuffer] = [:]
    private let dir: URL
    private let index: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("7Tools", isDirectory: true)
        dir = base.appendingPathComponent("Sounds", isDirectory: true)
        index = base.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: index),
           let items = try? JSONDecoder().decode([SoundItem].self, from: d) {
            user = items
        }
    }

    static let builtinItems: [SoundItem] = Synth.builtins.map {
        SoundItem(id: "builtin:" + $0.id, name: $0.name, seconds: 0)
    }

    var all: [SoundItem] { Self.builtinItems + user }

    func item(_ id: String) -> SoundItem? {
        all.first { $0.id == id }
    }

    func name(_ id: String) -> String { item(id)?.name ?? "Pusty" }

    // bufor do grania, ladowany leniwie
    func buffer(_ id: String) -> SampleBuffer? {
        if let b = cache[id] { return b }
        var b: SampleBuffer?
        if id.hasPrefix("builtin:") {
            let key = String(id.dropFirst(8))
            b = Synth.builtins.first { $0.id == key }?.make()
        } else if let d = try? Data(contentsOf: file(id)) {
            b = WAV.decode(d)?.resampled(to: 48000)
        }
        if let b { cache[id] = b }
        return b
    }

    private func file(_ id: String) -> URL { dir.appendingPathComponent(id + ".wav") }

    func wavURL(_ id: String) -> URL? {
        if id.hasPrefix("builtin:") {
            // wbudowane zapisujemy do pliku dopiero, gdy ktos chce je wyslac
            guard let b = buffer(id) else { return nil }
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(name(id) + ".wav")
            try? WAV.encode(b).write(to: u)
            return u
        }
        return FileManager.default.fileExists(atPath: file(id).path) ? file(id) : nil
    }

    @discardableResult
    func add(_ buffer: SampleBuffer, name: String, creator: String? = nil, license: String? = nil,
             licenseURL: String? = nil, sourceURL: String? = nil) -> SoundItem {
        let b = buffer.peak() > 0.001 ? buffer.normalized(0.9) : buffer
        b.fadeEdges()
        let item = SoundItem(id: UUID().uuidString, name: name, seconds: b.duration,
                             creator: creator, license: license, licenseURL: licenseURL, sourceURL: sourceURL)
        try? WAV.encode(b).write(to: file(item.id))
        cache[item.id] = b
        user.insert(item, at: 0)
        save()
        return item
    }

    func rename(_ id: String, to name: String) {
        guard let i = user.firstIndex(where: { $0.id == id }) else { return }
        user[i].name = name
        save()
    }

    func remove(_ id: String) {
        user.removeAll { $0.id == id }
        cache[id] = nil
        try? FileManager.default.removeItem(at: file(id))
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(user) { try? d.write(to: index, options: .atomic) }
    }
}

// ------------------------------------------------------------------ biblioteka z internetu (Openverse)

// Openverse to wyszukiwarka dzwiekow na wolnych licencjach (m.in. z Freesound, Wikimedia, Jamendo).
// Dziala bez klucza. Autor i licencja zostaja przy dzwieku.
struct OVSound: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let creator: String?
    let url: String
    let license: String
    let licenseURL: String?
    let landing: String?
    let duration: Int?          // ms
    let filesize: Int?
    let filetype: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, title, creator, url, license, duration, filesize, filetype, source
        case licenseURL = "license_url"
        case landing = "foreign_landing_url"
    }

    var name: String { (title?.isEmpty == false ? title! : "Dźwięk") }
    var seconds: Double { Double(duration ?? 0) / 1000 }

    var licenseLabel: String { license.lowercased() == "cc0" ? "CC0" : "CC " + license.uppercased() }
}

struct OVPage: Decodable {
    let results: [OVSound]
    let pageCount: Int
    let resultCount: Int

    enum CodingKeys: String, CodingKey {
        case results
        case pageCount = "page_count"
        case resultCount = "result_count"
    }
}

enum Openverse {
    static func search(_ query: String, page: Int = 1, effectsOnly: Bool = true) async throws -> OVPage {
        var c = URLComponents(string: "https://api.openverse.org/v1/audio/")!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: "20"),
        ]
        if effectsOnly { items.append(URLQueryItem(name: "category", value: "sound_effect")) }
        c.queryItems = items
        var req = URLRequest(url: c.url!, timeoutInterval: 20)
        req.setValue("7Tools", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(OVPage.self, from: data)
    }

    // pobiera plik do pamieci i dekoduje. Max ok. 8 MB.
    static func download(_ s: OVSound) async throws -> SampleBuffer {
        guard let url = URL(string: s.url) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("7Tools", forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0
        guard size < 8_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let ext = s.filetype ?? url.pathExtension
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (ext.isEmpty ? "mp3" : ext))
        try FileManager.default.moveItem(at: tmp, to: dst)
        defer { try? FileManager.default.removeItem(at: dst) }
        return try Importer.load(dst)
    }
}
