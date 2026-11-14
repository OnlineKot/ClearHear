import Foundation
import SwiftUI
import Security
import UIKit

// ------------------------------------------------------------------ klucze w Keychain

enum Keychain {
    private static let service = "pl.fastlink.seventools.keys"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
}

// ------------------------------------------------------------------ lokalny "MCP" w apce
// Narzedzia opisane tak jak w Model Context Protocol (nazwa, opis, schemat JSON) i wywolywane przez JSON-RPC 2.0
// (initialize, tools/list, tools/call). Wszystko dzieje sie w apce, bez serwera i bez sieci.
// Model (Claude, Gemini, Grok) dostaje te narzedzia jako "function calling" i wola je, a apka je wykonuje.

struct MCPTool {
    let name: String
    let description: String
    let schema: [String: Any]
}

struct MCPLogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let request: String
    let response: String
}

@MainActor
final class LocalMCP: ObservableObject {
    @Published private(set) var log: [MCPLogEntry] = []
    private let nav: NavModel
    private var nextID = 1

    init(nav: NavModel) { self.nav = nav }

    private static func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }

    private static let str: [String: Any] = ["type": "string"]

    let tools: [MCPTool] = [
        MCPTool(name: "get_state", description: "Zwraca, gdzie jest użytkownik w sklepie (dział, piętro, metry), kierunek, cel, trasę i listę zakupów.",
                schema: LocalMCP.obj([:])),
        MCPTool(name: "list_zones", description: "Lista wszystkich działów sklepu z id, nazwą i piętrem (1 = wystawa, 0 = parter).",
                schema: LocalMCP.obj([:])),
        MCPTool(name: "find_zone_for_item", description: "Znajduje działy, w których leży dana rzecz (np. kanapa, garnek, lampka, pościel).",
                schema: LocalMCP.obj(["query": LocalMCP.str], required: ["query"])),
        MCPTool(name: "set_position", description: "Ustawia pozycję użytkownika: podaj zone_id działu albo numer alejki magazynu (aisle). Używaj, gdy użytkownik mówi lub pokazuje na zdjęciu, gdzie jest.",
                schema: LocalMCP.obj(["zone_id": LocalMCP.str, "aisle": ["type": "integer"]])),
        MCPTool(name: "set_destination", description: "Ustawia cel nawigacji: zone_id działu, numer alejki magazynu (aisle) albo nazwa rzeczy (query).",
                schema: LocalMCP.obj(["zone_id": LocalMCP.str, "aisle": ["type": "integer"], "query": LocalMCP.str])),
        MCPTool(name: "clear_destination", description: "Usuwa cel nawigacji.", schema: LocalMCP.obj([:])),
        MCPTool(name: "get_route", description: "Zwraca opis trasy z obecnej pozycji do celu: metry, kroki, kierunek, co jest po drodze.",
                schema: LocalMCP.obj([:])),
        MCPTool(name: "add_to_list", description: "Dodaje rzecz do listy zakupów (dział dobierany sam, jeśli nie podano zone_id). Dla magazynu można podać aisle z metki ceny.",
                schema: LocalMCP.obj(["item": LocalMCP.str, "zone_id": LocalMCP.str, "aisle": ["type": "integer"]], required: ["item"])),
        MCPTool(name: "get_list", description: "Zwraca listę zakupów w kolejności zwiedzania.", schema: LocalMCP.obj([:])),
        MCPTool(name: "mark_done", description: "Odhacza rzecz z listy zakupów po nazwie.",
                schema: LocalMCP.obj(["item": LocalMCP.str], required: ["item"])),
        MCPTool(name: "note_landmark", description: "Zapamiętuje obecne miejsce jako punkt orientacyjny o podanej nazwie.",
                schema: LocalMCP.obj(["name": LocalMCP.str], required: ["name"])),
    ]

    // ---------------------------------------------------------- JSON-RPC

    func handle(_ req: [String: Any]) -> [String: Any] {
        let id = req["id"] ?? 0
        let method = req["method"] as? String ?? ""
        var result: [String: Any] = [:]
        switch method {
        case "initialize":
            result = ["protocolVersion": "2025-06-18", "capabilities": ["tools": [String: Any]()],
                      "serverInfo": ["name": "007tools-ikea-local", "version": "1.0"]]
        case "tools/list":
            result = ["tools": tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] as [String: Any] }]
        case "tools/call":
            let p = req["params"] as? [String: Any] ?? [:]
            let name = p["name"] as? String ?? ""
            let args = p["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = run(name, args)
            result = ["content": [["type": "text", "text": text]], "isError": isError]
        default:
            let resp: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Nieznana metoda \(method)"]]
            record(req, resp)
            return resp
        }
        let resp: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        if method != "tools/list" { record(req, resp) }
        return resp
    }

    // wygodny skrot dla agenta: wywolanie narzedzia jako tools/call, zwraca tekst wyniku
    func call(_ name: String, _ args: [String: Any]) -> String {
        nextID += 1
        let resp = handle(["jsonrpc": "2.0", "id": nextID, "method": "tools/call", "params": ["name": name, "arguments": args]])
        let res = resp["result"] as? [String: Any]
        let content = res?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? "{}"
    }

    private func record(_ req: [String: Any], _ resp: [String: Any]) {
        func pretty(_ o: [String: Any]) -> String {
            guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) else { return "?" }
            return s
        }
        log.append(MCPLogEntry(request: pretty(req), response: pretty(resp)))
        if log.count > 60 { log.removeFirst() }
    }

    private func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    private func zoneInfo(_ z: Zone) -> [String: Any] {
        ["id": z.id, "name": z.name, "floor": z.floor, "meters_on_floor": z.s]
    }

    // ---------------------------------------------------------- wykonanie narzedzi

    private func run(_ name: String, _ a: [String: Any]) -> (String, Bool) {
        switch name {
        case "get_state":
            var st: [String: Any] = ["placed": nav.placed, "floor": nav.floor, "meters_on_floor": Int(nav.s)]
            if let z = nav.nearestZone { st["nearest_zone"] = zoneInfo(z); st["meters_from_zone"] = Int(nav.nearestDistance) }
            if let h = nav.mapHeading { st["heading_on_plan_deg"] = Int(h) }
            st["compass_calibrated"] = nav.headingSet
            st["walking_against_flow"] = nav.reverse
            if let d = nav.destination { st["destination"] = d.name }
            if let r = nav.route { st["route_meters"] = Int(r.meters); st["route_forward"] = r.forward }
            if let i = nav.instruction() { st["instruction"] = i }
            st["list"] = nav.orderedList().map { ["item": $0.name, "zone": IkeaMap.zone($0.zoneID)?.name ?? $0.zoneID, "done": $0.done] as [String: Any] }
            return (json(st), false)

        case "list_zones":
            return (json(["zones": IkeaMap.zones.map { zoneInfo($0) }]), false)

        case "find_zone_for_item":
            let q = a["query"] as? String ?? ""
            let found = IkeaMap.find(q).prefix(4).map { zoneInfo($0) }
            return (json(["query": q, "matches": found]), false)

        case "set_position":
            if let n = a["aisle"] as? Int {
                nav.setPosition(aisle: n)
                return (json(["ok": true, "position": "Magazyn, alejka \(n)"]), false)
            }
            guard let id = a["zone_id"] as? String, let z = IkeaMap.zone(id) else {
                return (json(["ok": false, "error": "Podaj zone_id z list_zones albo aisle."]), true)
            }
            nav.setPosition(zone: z)
            return (json(["ok": true, "position": z.name]), false)

        case "set_destination":
            if let n = a["aisle"] as? Int { nav.setDestination(aisle: n); return (json(["ok": true, "destination": "Magazyn, alejka \(n)"]), false) }
            if let id = a["zone_id"] as? String, let z = IkeaMap.zone(id) { nav.setDestination(zone: z); return (json(["ok": true, "destination": z.name]), false) }
            if let q = a["query"] as? String, let z = IkeaMap.find(q).first { nav.setDestination(zone: z); return (json(["ok": true, "destination": z.name, "matched_from": q]), false) }
            return (json(["ok": false, "error": "Nie znaleziono celu. Użyj list_zones albo find_zone_for_item."]), true)

        case "clear_destination":
            nav.clearDestination()
            return (json(["ok": true]), false)

        case "get_route":
            guard nav.placed else { return (json(["error": "Najpierw ustaw pozycję (set_position)."]), true) }
            guard let d = nav.destination, let r = nav.route else { return (json(["error": "Brak celu. Użyj set_destination."]), true) }
            return (json(["destination": d.name, "meters": Int(r.meters), "steps": Int(r.meters / 0.72),
                          "forward": r.forward, "passing": r.passing.map { $0.name }, "instruction": nav.instruction() ?? ""]), false)

        case "add_to_list":
            let item = a["item"] as? String ?? ""
            var zone: Zone?
            if let id = a["zone_id"] as? String { zone = IkeaMap.zone(id) }
            nav.add(item: item, zone: zone, aisle: a["aisle"] as? Int)
            if let last = nav.list.last, last.name == item {
                return (json(["ok": true, "item": item, "zone": IkeaMap.zone(last.zoneID)?.name ?? last.zoneID]), false)
            }
            return (json(["ok": false, "error": "Nie wiem, gdzie leży \"\(item)\". Podaj zone_id."]), true)

        case "get_list":
            return (json(["list": nav.orderedList().map { ["item": $0.name, "zone": IkeaMap.zone($0.zoneID)?.name ?? $0.zoneID, "done": $0.done] as [String: Any] }]), false)

        case "mark_done":
            let item = (a["item"] as? String ?? "").lowercased()
            if let it = nav.list.first(where: { $0.name.lowercased() == item && !$0.done }) ?? nav.list.first(where: { $0.name.lowercased().contains(item) && !$0.done }) {
                nav.toggle(it.id)
                return (json(["ok": true, "item": it.name]), false)
            }
            return (json(["ok": false, "error": "Nie ma takiej pozycji na liście."]), true)

        case "note_landmark":
            let n = a["name"] as? String ?? "Punkt"
            nav.note(landmark: n)
            return (json(["ok": true, "name": n]), false)

        default:
            return (json(["error": "Nieznane narzędzie \(name)"]), true)
        }
    }
}

// ------------------------------------------------------------------ dostawcy modeli

enum LLMProvider: String, CaseIterable, Identifiable {
    case claude, gemini, grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-5-5"
        case .gemini: return "gemini-2.5-flash"
        case .grok: return "grok-4"
        }
    }

    var keyHint: String {
        switch self {
        case .claude: return "console.anthropic.com"
        case .gemini: return "aistudio.google.com"
        case .grok: return "console.x.ai"
        }
    }
}

struct ChatLine: Identifiable {
    enum Role { case user, assistant, tool, error }
    let id = UUID()
    let role: Role
    let text: String
    var image: UIImage? = nil
}

enum LLMError: LocalizedError {
    case http(Int, String)
    case noKey
    case bad(String)

    var errorDescription: String? {
        switch self {
        case .http(let c, let m): return "Błąd \(c): \(m)"
        case .noKey: return "Najpierw wpisz klucz API w ustawieniach asystenta."
        case .bad(let m): return m
        }
    }
}

// Jeden agent, trzy dialekty. Trzymamy historie w formacie danego dostawcy, zeby narzedzia i zdjecia szly poprawnie.
@MainActor
final class Assistant: ObservableObject {
    @Published var lines: [ChatLine] = []
    @Published private(set) var busy = false
    @Published var provider: LLMProvider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider"); reset() } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "ai.model." + provider.rawValue) } }
    @Published private(set) var models: [String] = []
    @Published var keyDraft = ""
    @Published private(set) var hasKey = false
    @Published var status = ""

    let nav: NavModel
    let mcp: LocalMCP
    private var claude: [[String: Any]] = []
    private var gemini: [[String: Any]] = []
    private var grok: [[String: Any]] = []

    init(nav: NavModel, mcp: LocalMCP) {
        self.nav = nav
        self.mcp = mcp
        let p = LLMProvider(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "") ?? .claude
        provider = p
        model = UserDefaults.standard.string(forKey: "ai.model." + p.rawValue) ?? p.defaultModel
        hasKey = !Keychain.get(p.rawValue).isEmpty
    }

    private var key: String { Keychain.get(provider.rawValue) }

    func saveKey() {
        Keychain.set(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.rawValue)
        keyDraft = ""
        hasKey = !key.isEmpty
        status = hasKey ? "Klucz zapisany w Keychain tego telefonu." : "Klucz usunięty."
    }

    func reset() {
        claude = []; gemini = []; grok = []
        lines = []
        model = UserDefaults.standard.string(forKey: "ai.model." + provider.rawValue) ?? provider.defaultModel
        hasKey = !key.isEmpty
        models = []
    }

    // ---------------------------------------------------------- prompt

    private var system: String {
        let zones = IkeaMap.zones.map { "- \($0.id): \($0.name) (piętro \($0.floor))" }.joined(separator: "\n")
        return """
        Jesteś asystentem nawigacji po sklepie IKEA Katowice, wbudowanym w apkę 007Tools. Odpowiadaj krótko, po polsku, bez ozdobników.
        Użytkownik jest w sklepie i idzie. Masz narzędzia (lokalny MCP w apce) do odczytu i ustawiania jego pozycji, celu, trasy i listy zakupów. \
        Używaj ich zamiast zgadywać. Gdy użytkownik mówi lub pokazuje na zdjęciu, gdzie jest (tabliczka działu, numer alejki, znak nad głową), \
        odczytaj to i wywołaj set_position. Gdy chce coś znaleźć, użyj find_zone_for_item, potem set_destination i get_route. \
        Gdy prosi o dodanie rzeczy do listy, użyj add_to_list.
        Mapa to SCHEMAT typowego układu IKEA, a nie oficjalny plan Katowic, więc jeśli tabliczki w sklepie mówią co innego, ufaj tabliczkom i popraw pozycję.
        Wystawa jest na piętrze 1 (jedna ścieżka, strzałki na podłodze), na parterze 0 jest hala, magazyn samoobsługowy (alejki) i kasy.
        Działy:
        \(zones)
        """
    }

    private var toolDefs: [(name: String, description: String, schema: [String: Any])] {
        mcp.tools.map { ($0.name, $0.description, $0.schema) }
    }

    // ---------------------------------------------------------- rozmowa

    func send(_ text: String, image: UIImage?) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || image != nil, !busy else { return }
        guard !key.isEmpty else { lines.append(ChatLine(role: .error, text: LLMError.noKey.localizedDescription)); return }
        lines.append(ChatLine(role: .user, text: t.isEmpty ? "Spójrz na zdjęcie" : t, image: image))
        busy = true
        defer { busy = false }
        let b64 = image.flatMap { Self.jpegBase64($0) }
        do {
            switch provider {
            case .claude: try await runClaude(t.isEmpty ? "Spójrz na zdjęcie." : t, b64)
            case .gemini: try await runGemini(t.isEmpty ? "Spójrz na zdjęcie." : t, b64)
            case .grok: try await runGrok(t.isEmpty ? "Spójrz na zdjęcie." : t, b64)
            }
        } catch {
            lines.append(ChatLine(role: .error, text: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        }
    }

    private static func jpegBase64(_ img: UIImage) -> String? {
        let maxSide: CGFloat = 1024
        let s = max(img.size.width, img.size.height)
        let k = s > maxSide ? maxSide / s : 1
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let r = UIGraphicsImageRenderer(size: size)
        let small = r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }

    private func post(_ url: String, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw LLMError.bad("Zły adres") }
        var req = URLRequest(url: u, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, r) = try await URLSession.shared.data(for: req)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        guard code == 200 else {
            let err = obj["error"]
            let msg = ((err as? [String: Any])?["message"] as? String) ?? (err as? String) ?? String(data: d.prefix(200), encoding: .utf8) ?? ""
            throw LLMError.http(code, msg)
        }
        return obj
    }

    private func say(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { lines.append(ChatLine(role: .assistant, text: t)) }
    }

    private func toolLine(_ name: String, _ args: [String: Any]) {
        let a = (try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        lines.append(ChatLine(role: .tool, text: "\(name) \(a == "{}" ? "" : a)"))
    }

    // ---------------------------------------------------------- Claude

    private func runClaude(_ text: String, _ b64: String?) async throws {
        var content: [[String: Any]] = []
        if let b64 { content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]]) }
        content.append(["type": "text", "text": text])
        claude.append(["role": "user", "content": content])
        let tools = toolDefs.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] as [String: Any] }

        for _ in 0..<6 {
            let r = try await post("https://api.anthropic.com/v1/messages",
                                   headers: ["x-api-key": key, "anthropic-version": "2023-06-01"],
                                   body: ["model": model, "max_tokens": 1024, "system": system, "messages": claude, "tools": tools])
            let blocks = r["content"] as? [[String: Any]] ?? []
            claude.append(["role": "assistant", "content": blocks])
            var results: [[String: Any]] = []
            for b in blocks {
                if b["type"] as? String == "text" { say(b["text"] as? String ?? "") }
                if b["type"] as? String == "tool_use", let id = b["id"] as? String, let name = b["name"] as? String {
                    let args = b["input"] as? [String: Any] ?? [:]
                    toolLine(name, args)
                    results.append(["type": "tool_result", "tool_use_id": id, "content": mcp.call(name, args)])
                }
            }
            if results.isEmpty { return }
            claude.append(["role": "user", "content": results])
        }
    }

    // ---------------------------------------------------------- Gemini

    private func runGemini(_ text: String, _ b64: String?) async throws {
        var parts: [[String: Any]] = []
        if let b64 { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        parts.append(["text": text])
        gemini.append(["role": "user", "parts": parts])
        let decls = toolDefs.map { ["name": $0.name, "description": $0.description, "parameters": $0.schema] as [String: Any] }

        for _ in 0..<6 {
            let r = try await post("https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent",
                                   headers: ["x-goog-api-key": key],
                                   body: ["systemInstruction": ["parts": [["text": system]]], "contents": gemini,
                                          "tools": [["functionDeclarations": decls]]])
            let cand = (r["candidates"] as? [[String: Any]])?.first
            let content = cand?["content"] as? [String: Any]
            let ps = content?["parts"] as? [[String: Any]] ?? []
            // oddajemy czesci dokladnie tak, jak przyszly (zawieraja m.in. podpisy rozumowania)
            gemini.append(["role": "model", "parts": ps])
            var responses: [[String: Any]] = []
            for p in ps {
                if let t = p["text"] as? String, p["thought"] as? Bool != true { say(t) }
                if let fc = p["functionCall"] as? [String: Any], let name = fc["name"] as? String {
                    let args = fc["args"] as? [String: Any] ?? [:]
                    toolLine(name, args)
                    responses.append(["functionResponse": ["name": name, "response": ["result": mcp.call(name, args)]]])
                }
            }
            if responses.isEmpty { return }
            gemini.append(["role": "user", "parts": responses])
        }
    }

    // ---------------------------------------------------------- Grok (xAI, format OpenAI)

    private func runGrok(_ text: String, _ b64: String?) async throws {
        if grok.isEmpty { grok.append(["role": "system", "content": system]) }
        if let b64 {
            grok.append(["role": "user", "content": [["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
                                                     ["type": "text", "text": text]]])
        } else {
            grok.append(["role": "user", "content": text])
        }
        let tools = toolDefs.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema]] as [String: Any] }

        for _ in 0..<6 {
            let r = try await post("https://api.x.ai/v1/chat/completions",
                                   headers: ["authorization": "Bearer \(key)"],
                                   body: ["model": model, "messages": grok, "tools": tools, "tool_choice": "auto"])
            guard let msg = (r["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else { return }
            grok.append(msg)
            say(msg["content"] as? String ?? "")
            let calls = msg["tool_calls"] as? [[String: Any]] ?? []
            if calls.isEmpty { return }
            for c in calls {
                guard let id = c["id"] as? String, let fn = c["function"] as? [String: Any], let name = fn["name"] as? String else { continue }
                let argStr = fn["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argStr.utf8))) as? [String: Any] ?? [:]
                toolLine(name, args)
                grok.append(["role": "tool", "tool_call_id": id, "content": mcp.call(name, args)])
            }
        }
    }

    // ---------------------------------------------------------- lista modeli i test klucza

    func refreshModels() async {
        guard !key.isEmpty else { status = LLMError.noKey.localizedDescription; return }
        status = "Pobieram modele…"
        do {
            var url = ""
            var headers: [String: String] = [:]
            switch provider {
            case .claude: url = "https://api.anthropic.com/v1/models?limit=100"; headers = ["x-api-key": key, "anthropic-version": "2023-06-01"]
            case .gemini: url = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100"; headers = ["x-goog-api-key": key]
            case .grok: url = "https://api.x.ai/v1/models"; headers = ["authorization": "Bearer \(key)"]
            }
            var req = URLRequest(url: URL(string: url)!, timeoutInterval: 30)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (d, r) = try await URLSession.shared.data(for: req)
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
            guard code == 200 else {
                let m = ((o["error"] as? [String: Any])?["message"] as? String) ?? "kod \(code)"
                throw LLMError.http(code, m)
            }
            var ids: [String] = []
            if provider == .gemini {
                for m in (o["models"] as? [[String: Any]] ?? []) {
                    let methods = m["supportedGenerationMethods"] as? [String] ?? []
                    if methods.contains("generateContent"), let n = m["name"] as? String { ids.append(n.replacingOccurrences(of: "models/", with: "")) }
                }
            } else {
                ids = (o["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            }
            models = ids.sorted()
            status = models.isEmpty ? "Klucz działa, ale lista modeli jest pusta." : "Klucz działa. Modeli: \(models.count)."
            if !models.contains(model), let first = models.first(where: { $0.contains("flash") || $0.contains("sonnet") || $0.contains("grok-4") }) ?? models.first {
                model = first
            }
        } catch {
            status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
