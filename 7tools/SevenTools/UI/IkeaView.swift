import SwiftUI
import PhotosUI

// IKEA Navigator: schemat sklepu, kalibracja pozycji (dzial, zdjecie tablicy, kompas, kroki), cel, lista zakupow i asystent AI.
// To schemat typowego ukladu IKEA, nie oficjalny plan konkretnego sklepu. Dlatego kalibruje sie go na miejscu.

struct IkeaView: View {
    @StateObject private var nav: NavModel
    @StateObject private var mcp: LocalMCP
    @StateObject private var ai: Assistant
    @State private var tab = 0
    @State private var calibrating = false
    @State private var pendingPhoto = false

    init() {
        let n = NavModel()
        let m = LocalMCP(nav: n)
        _nav = StateObject(wrappedValue: n)
        _mcp = StateObject(wrappedValue: m)
        _ai = StateObject(wrappedValue: Assistant(nav: n, mcp: m))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Widok", selection: $tab) {
                Text("Mapa").tag(0)
                Text("Lista").tag(1)
                Text("Asystent").tag(2)
                Text("MCP").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            switch tab {
            case 0: IkeaMapTab(nav: nav, calibrate: { calibrating = true })
            case 1: IkeaListTab(nav: nav)
            case 2: IkeaChat(ai: ai, nav: nav, startWithPhoto: $pendingPhoto)
            default: MCPConsole(mcp: mcp)
            }
        }
        .background(Backdrop())
        .navigationTitle("IKEA Navigator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nav.startTracking() }
        .onDisappear { nav.stopTracking(); nav.save() }
        .sheet(isPresented: $calibrating) {
            CalibrationSheet(nav: nav, hasKey: ai.hasKey) {
                calibrating = false
                pendingPhoto = true
                tab = 2
            }
        }
        .environmentObject(nav)
    }
}

// ------------------------------------------------------------------ mapa

struct IkeaMapTab: View {
    @ObservedObject var nav: NavModel
    let calibrate: () -> Void

    @State private var query = ""
    @State private var matches: [Zone] = []
    @State private var selected: Zone?
    @State private var aisleText = ""
    @State private var landmarkName = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                status
                floorPicker
                IkeaMapCanvas(nav: nav, floor: nav.viewFloor) { z in selected = z; Haptics.tap(.light) }
                    .aspectRatio(120.0 / 80.0, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 22))
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .overlay(alignment: .topLeading) {
                        Text("Schemat typowego IKEA, nie oficjalny plan").spaced(.caption2).foregroundStyle(.secondary).padding(8)
                    }
                if let z = selected { zoneCard(z).transition(.move(edge: .bottom).combined(with: .opacity)) }
                destinationCard
                search
                chips
                controls
                aisle
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .animation(.bouncy(duration: 0.45), value: selected)
        .animation(.bouncy(duration: 0.45), value: nav.destinationID)
        .onReceive(tick) { _ in nav.tickWalking() }
    }

    // ---------------------------------------------------------- gora: gdzie jestem

    private var status: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if nav.placed, let z = nav.nearestZone {
                    HStack(spacing: 10) {
                        Text(z.emoji).font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nav.nearestDistance < 12 ? "Jesteś przy: \(z.name)" : "Blisko: \(z.name) (\(Int(nav.nearestDistance)) m)")
                                .spaced(.headline, .bold)
                            Text(nav.floor == 1 ? "Piętro: wystawa" : "Parter: hala, magazyn, kasy").spaced(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    Label("Nie wiem jeszcze, gdzie jesteś. Dotknij „Kalibruj” i wskaż miejsce.", systemImage: "location.slash")
                        .spaced(.subheadline, .semibold)
                }
                HStack(spacing: 8) {
                    pill(nav.walking ? "Idziesz" : "Stoisz", nav.walking ? "figure.walk" : "figure.stand")
                    pill(nav.reverse ? "Pod prąd" : "Z prądem", nav.reverse ? "arrow.uturn.backward" : "arrow.forward")
                    if let h = nav.mapHeading {
                        pill("\(Int(h))° \(Geo.compassName(h))", "location.north.fill")
                    } else if nav.compass.heading != nil {
                        pill("Kompas niezgrany", "exclamationmark.triangle")
                    }
                    Spacer()
                    Button(action: calibrate) { Chip(text: "Kalibruj", symbol: "scope", selected: !nav.placed) }.buttonStyle(.plain)
                }
                if !nav.lastEvent.isEmpty { Text(nav.lastEvent).spaced(.caption).foregroundStyle(Theme.gold) }
            }
        }
    }

    private func pill(_ t: String, _ symbol: String) -> some View {
        Label(t, systemImage: symbol).spaced(.caption, .semibold)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
    }

    private var floorPicker: some View {
        Picker("Piętro", selection: $nav.viewFloor) {
            Text("Wystawa (piętro)").tag(1)
            Text("Hala, magazyn, kasy (parter)").tag(0)
        }
        .pickerStyle(.segmented)
    }

    // ---------------------------------------------------------- cel

    private func zoneCard(_ z: Zone) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(z.emoji) \(z.name)").spaced(.headline, .bold)
                    Spacer()
                    Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Button { nav.setDestination(zone: z); selected = nil; Haptics.ok() } label: { Chip(text: "Idź tutaj", symbol: "flag.fill", selected: true) }.buttonStyle(.plain)
                    Button { nav.setPosition(zone: z); selected = nil; Haptics.ok() } label: { Chip(text: "Jestem tutaj", symbol: "mappin.circle.fill") }.buttonStyle(.plain)
                    Button { nav.add(item: z.name, zone: z); Haptics.ok() } label: { Chip(text: "Na listę", symbol: "plus") }.buttonStyle(.plain)
                }
            }
        }
    }

    private var destinationCard: some View {
        Group {
            if let d = nav.destination {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(d.name, systemImage: "flag.checkered").spaced(.headline, .bold)
                            Spacer()
                            Button { nav.clearDestination() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                        }
                        if !nav.placed {
                            Text("Ustaw, gdzie jesteś, a pokażę trasę.").spaced(.footnote).foregroundStyle(.secondary)
                        } else if let i = nav.instruction() {
                            Text(i).spaced(.subheadline).foregroundStyle(.white.opacity(0.9))
                        }
                        if nav.list.contains(where: { !$0.done }) {
                            Button { nav.goToNextOnList() } label: { Chip(text: "Następny z listy", symbol: "list.bullet") }.buttonStyle(.plain)
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var search: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Czego szukasz? (np. sofa, garnek, lampa)", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .onSubmit { matches = IkeaMap.find(query) }
                    .onChange(of: query) { _, q in matches = q.count >= 2 ? Array(IkeaMap.find(q).prefix(4)) : [] }
                if !query.isEmpty { Button { query = ""; matches = [] } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).glassEffect(.regular, in: .capsule)

            if !matches.isEmpty {
                VStack(spacing: 6) {
                    ForEach(matches) { z in
                        Button { nav.setDestination(zone: z); query = ""; matches = []; Haptics.ok() } label: {
                            HStack {
                                Text("\(z.emoji) \(z.name)").spaced(.subheadline, .semibold)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").foregroundStyle(Theme.gold)
                            }
                            .padding(12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if query.count >= 3 {
                Text("Nie wiem, gdzie to leży. Wybierz dział poniżej albo zapytaj asystenta.").spaced(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wybierz dział").spaced(.footnote, .semibold).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(IkeaMap.zones) { z in
                        Button { nav.setDestination(zone: z); Haptics.tap(.light) } label: {
                            Chip(text: "\(z.emoji) \(z.name)", selected: nav.destinationID == z.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- narzedzia

    private var controls: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Korekta").spaced(.subheadline, .bold)
                HStack(spacing: 8) {
                    Button { nav.toggleReverse() } label: { Chip(text: "Idę pod prąd", symbol: "arrow.uturn.backward", selected: nav.reverse) }.buttonStyle(.plain)
                    Button { nav.nudge(-5) } label: { Chip(text: "−5 m", symbol: "minus") }.buttonStyle(.plain)
                    Button { nav.nudge(5) } label: { Chip(text: "+5 m", symbol: "plus") }.buttonStyle(.plain)
                }
                Toggle(isOn: $nav.autoHeading) { Label("Auto-dopasuj kierunek podczas marszu", systemImage: "location.north.line.fill") }
                    .spaced(.footnote, .semibold)
                    .onChange(of: nav.autoHeading) { nav.save() }
                HStack(spacing: 8) {
                    TextField("Nazwa miejsca", text: $landmarkName).padding(10).glassEffect(.regular, in: .capsule)
                    Button {
                        let n = landmarkName.trimmingCharacters(in: .whitespaces)
                        nav.note(landmark: n.isEmpty ? "Punkt" : n)
                        landmarkName = ""
                    } label: { Chip(text: "Zapamiętaj", symbol: "bookmark.fill") }.buttonStyle(.plain)
                }
                ForEach(nav.landmarks) { l in
                    HStack {
                        Image(systemName: "bookmark.fill").foregroundStyle(Theme.gold)
                        Text(l.name).spaced(.footnote, .semibold)
                        Spacer()
                        Button("Tu jestem") { nav.setPosition(floor: l.floor, s: l.s) }.font(.footnote)
                        Button(role: .destructive) { nav.landmarks.removeAll { $0.id == l.id }; nav.save() } label: { Image(systemName: "trash") }.font(.footnote)
                    }
                }
            }
        }
    }

    private var aisle: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Magazyn: alejka z metki ceny").spaced(.subheadline, .bold)
                HStack(spacing: 8) {
                    TextField("Nr alejki", text: $aisleText).keyboardType(.numberPad).padding(10).glassEffect(.regular, in: .capsule)
                    Button { if let n = Int(aisleText) { nav.setDestination(aisle: n); Haptics.ok() } } label: { Chip(text: "Idź", symbol: "flag.fill", selected: true) }.buttonStyle(.plain)
                    Button { if let n = Int(aisleText) { nav.setPosition(aisle: n); Haptics.ok() } } label: { Chip(text: "Jestem tu", symbol: "mappin") }.buttonStyle(.plain)
                }
                Stepper("Liczba alejek w magazynie: \(nav.maxAisle)", value: $nav.maxAisle, in: 10...80, step: 2)
                    .spaced(.footnote)
                    .onChange(of: nav.maxAisle) { nav.save() }
            }
        }
    }
}

// Rysunek planu: sciezka ze strzalkami, dzialy, trasa, pozycja i kierunek
struct IkeaMapCanvas: View {
    @ObservedObject var nav: NavModel
    let floor: Int
    let onZone: (Zone) -> Void

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 120
            Canvas { ctx, size in draw(ctx, k) }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    let p = P(x: v.location.x / k, y: v.location.y / k)
                    if let z = IkeaMap.nearestZone(to: p, floor: floor, maxDistance: 9) { onZone(z) }
                })
        }
        .accessibilityLabel("Plan sklepu")
    }

    private func pt(_ p: P, _ k: Double) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }

    private func draw(_ ctx: GraphicsContext, _ k: Double) {
        var ctx = ctx
        let pts = IkeaMap.path(floor)

        // sciezka
        var path = Path()
        path.move(to: pt(pts[0], k))
        for p in pts.dropFirst() { path.addLine(to: pt(p, k)) }
        ctx.stroke(path, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 7 * k, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [5, 5]))

        // strzalki kierunku zwiedzania
        let len = IkeaMap.floorLength(floor)
        var s = 8.0
        while s < len {
            let a = IkeaMap.pointAt(floor: floor, s: s)
            drawArrow(ctx, pt(a.p, k), a.bearing, size: 2.2 * k, color: .white.opacity(0.35))
            s += 16
        }

        // trasa do celu
        if let r = nav.route {
            for leg in r.legs where leg.floor == floor && leg.points.count >= 2 {
                var rp = Path()
                rp.move(to: pt(leg.points[0], k))
                for p in leg.points.dropFirst() { rp.addLine(to: pt(p, k)) }
                ctx.stroke(rp, with: .color(Theme.gold.opacity(0.35)), style: StrokeStyle(lineWidth: 8 * k, lineCap: .round, lineJoin: .round))
                ctx.stroke(rp, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 2.6 * k, lineCap: .round, lineJoin: .round))
            }
        }

        // dzialy
        for z in IkeaMap.zones where z.floor == floor {
            let c = pt(IkeaMap.pointAt(floor: floor, s: z.s).p, k)
            let isDest = nav.destinationID == z.id
            let r = (isDest ? 4.2 : 3.2) * k
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(isDest ? Theme.gold : Color.black.opacity(0.75)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(isDest ? .white : Theme.gold.opacity(0.7)), lineWidth: 1.2)
            ctx.draw(Text(z.emoji).font(.system(size: r * 1.25)), at: c)
        }

        // magazyn: zaznaczony cel alejki
        if let a = nav.destinationAisle, floor == 0 {
            let c = pt(IkeaMap.pointAt(floor: 0, s: IkeaMap.aisle(a, maxAisle: nav.maxAisle)).p, k)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3 * k, y: c.y - 3 * k, width: 6 * k, height: 6 * k)), with: .color(Theme.gold))
            ctx.draw(Text("\(a)").font(.system(size: 3.2 * k, weight: .bold)).foregroundStyle(.black), at: c)
        }

        // zapamietane miejsca
        for l in nav.landmarks where l.floor == floor {
            let c = pt(IkeaMap.pointAt(floor: floor, s: l.s).p, k)
            ctx.draw(Text("🔖").font(.system(size: 3.6 * k)), at: CGPoint(x: c.x, y: c.y - 5 * k))
        }

        // uzytkownik
        if nav.placed && nav.floor == floor {
            let a = IkeaMap.pointAt(floor: floor, s: nav.s)
            let c = pt(a.p, k)
            if let h = nav.mapHeading {
                // stozek kierunku, w ktorym patrzy telefon
                let rad = (h - 90) * .pi / 180
                var cone = Path()
                cone.move(to: c)
                cone.addArc(center: c, radius: 11 * k, startAngle: .radians(rad - 0.45), endAngle: .radians(rad + 0.45), clockwise: false)
                cone.closeSubpath()
                ctx.fill(cone, with: .color(Color.cyan.opacity(0.35)))
            }
            let walkBearing = nav.reverse ? HeadingCal.norm(a.bearing + 180) : a.bearing
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4 * k, y: c.y - 4 * k, width: 8 * k, height: 8 * k)), with: .color(Color.cyan.opacity(0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.4 * k, y: c.y - 2.4 * k, width: 4.8 * k, height: 4.8 * k)), with: .color(.cyan))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 2.4 * k, y: c.y - 2.4 * k, width: 4.8 * k, height: 4.8 * k)), with: .color(.white), lineWidth: 2)
            drawArrow(ctx, c, nav.mapHeading ?? walkBearing, size: 2.6 * k, color: .white, offset: 4.6 * k)
        }
    }

    // trojkat wskazujacy kierunek (stopnie od gory mapy, zgodnie z ruchem wskazowek)
    private func drawArrow(_ ctx: GraphicsContext, _ c: CGPoint, _ bearing: Double, size: Double, color: Color, offset: Double = 0) {
        var ctx = ctx
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: .radians(bearing * .pi / 180))
        var t = Path()
        t.move(to: CGPoint(x: 0, y: -size - offset))
        t.addLine(to: CGPoint(x: size * 0.7, y: size * 0.6 - offset))
        t.addLine(to: CGPoint(x: -size * 0.7, y: size * 0.6 - offset))
        t.closeSubpath()
        ctx.fill(t, with: .color(color))
    }
}

// ------------------------------------------------------------------ kalibracja

struct CalibrationSheet: View {
    @ObservedObject var nav: NavModel
    let hasKey: Bool
    let askPhoto: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("1. Wskaż, gdzie teraz stoisz. Najlepiej przy dużej tabliczce działu albo znaku nad głową.")
                        .spaced(.footnote)
                    Button { askPhoto() } label: {
                        Label(hasKey ? "Zrób zdjęcie tabliczki (AI ustawi pozycję)" : "Zdjęcie tabliczki (wymaga klucza AI)", systemImage: "camera.viewfinder")
                    }
                    ForEach([1, 0], id: \.self) { f in
                        DisclosureGroup(f == 1 ? "Wystawa (piętro)" : "Hala, magazyn, kasy (parter)") {
                            ForEach(IkeaMap.zones.filter { $0.floor == f }) { z in
                                Button {
                                    nav.setPosition(zone: z)
                                    Haptics.ok()
                                } label: {
                                    HStack {
                                        Text("\(z.emoji) \(z.name)")
                                        Spacer()
                                        if nav.placed && nav.nearestZone?.id == z.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
                                    }
                                }
                            }
                        }
                    }
                } header: { Text("Gdzie jestem") }

                Section {
                    Text("2. Stań twarzą w tę stronę, w którą prowadzi strzałka na podłodze (kierunek zwiedzania), i dotknij. Potem apka sama dociąga kierunek w marszu.")
                        .spaced(.footnote)
                    Button {
                        nav.calibrateHeading()
                        Haptics.ok()
                    } label: { Label("Kalibruj kierunek", systemImage: "location.north.fill") }
                        .disabled(!nav.placed)
                    HStack {
                        Text("Kompas")
                        Spacer()
                        Text(nav.compass.heading.map { "\(Int($0))°" } ?? "brak").foregroundStyle(.secondary)
                    }
                    if nav.compass.accuracy > 25 {
                        Label("Kompas jest niedokładny. Zrób telefonem „ósemkę” w powietrzu i odsuń go od metalu.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).spaced(.footnote)
                    }
                } header: { Text("Kierunek") }

                Section {
                    Text("3. Idź. Krokomierz przesuwa kropkę wzdłuż ścieżki. Gdy kropka się rozjedzie, wskaż dział jeszcze raz, a apka nauczy się długości twojego kroku.")
                        .spaced(.footnote)
                    HStack {
                        Text("Skala kroku")
                        Spacer()
                        Text(String(format: "%.2f", nav.strideScale)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .navigationTitle("Kalibracja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// ------------------------------------------------------------------ lista zakupow

struct IkeaListTab: View {
    @ObservedObject var nav: NavModel
    @State private var text = ""
    @State private var suggestion: Zone?

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("Dodaj do listy (np. lampka, pościel)", text: $text)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .onChange(of: text) { _, t in suggestion = t.count >= 3 ? IkeaMap.find(t).first : nil }
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.gold) }
                        .buttonStyle(.plain)
                }
                if let z = suggestion { Text("Leży w: \(z.emoji) \(z.name)").spaced(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                ForEach(nav.orderedList()) { it in
                    HStack(spacing: 12) {
                        Button { nav.toggle(it.id); Haptics.tap(.light) } label: {
                            Image(systemName: it.done ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                                .foregroundStyle(it.done ? Color.green : Theme.gold)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.name).spaced(.body, .semibold).strikethrough(it.done)
                            if let z = IkeaMap.zone(it.zoneID) {
                                Text("\(z.emoji) \(z.name)\(it.aisle.map { ", alejka \($0)" } ?? "")")
                                    .spaced(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if nav.placed, !it.done, let z = IkeaMap.zone(it.zoneID) {
                            Text(distanceText(z)).spaced(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Button {
                            if let a = it.aisle { nav.setDestination(aisle: a) } else if let z = IkeaMap.zone(it.zoneID) { nav.setDestination(zone: z) }
                        } label: { Image(systemName: "flag.fill").foregroundStyle(Theme.gold) }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { idx in
                    let ordered = nav.orderedList()
                    nav.list.removeAll { l in idx.contains { ordered[$0].id == l.id } }
                    nav.save()
                }
            } header: { Text("W kolejności zwiedzania") } footer: {
                Text("Lista układa się wzdłuż ścieżki: najpierw to, co jest przed Tobą, potem to, co już minąłeś.")
            }

            if nav.list.contains(where: { !$0.done }) {
                Button { nav.goToNextOnList() } label: { Label("Prowadź do następnego", systemImage: "arrow.turn.up.right") }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        nav.add(item: t, zone: suggestion)
        if nav.list.last?.name != t {
            nav.lastEvent = "Nie wiem, gdzie leży „\(t)”. Dodaj dział z mapy."
        }
        text = ""
        suggestion = nil
    }

    private func distanceText(_ z: Zone) -> String {
        let g = IkeaMap.global(floor: z.floor, s: z.s) - nav.global
        return (g >= 0 ? "" : "↩ ") + "\(Int(abs(g))) m"
    }
}

// ------------------------------------------------------------------ asystent AI

struct IkeaChat: View {
    @ObservedObject var ai: Assistant
    @ObservedObject var nav: NavModel
    @Binding var startWithPhoto: Bool

    @State private var text = ""
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var pick: PhotosPickerItem?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(LLMProvider.allCases) { p in Button(p.title) { ai.provider = p } }
                } label: { Chip(text: ai.provider.title, symbol: "sparkles") }
                Text(ai.model).spaced(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape.fill").foregroundStyle(.white).frame(width: 40, height: 40).glassEffect(.regular.interactive(), in: .circle) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if ai.lines.isEmpty { intro }
                        ForEach(ai.lines) { l in bubble(l).id(l.id) }
                        if ai.busy { ProgressView().padding() }
                    }
                    .padding(16)
                }
                .onChange(of: ai.lines.count) { _, _ in
                    if let last = ai.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            inputBar
        }
        .sheet(isPresented: $showCamera) { CameraPicker { img in photo = img } }
        .sheet(isPresented: $showSettings) { AssistantSettings(ai: ai) }
        .onChange(of: pick) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { photo = img }
            }
        }
        .onAppear {
            if startWithPhoto {
                startWithPhoto = false
                text = "Gdzie jestem? Odczytaj tabliczkę i ustaw moją pozycję."
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            }
        }
    }

    private var intro: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asystent po IKEA").spaced(.headline, .bold)
                Text("Zapytaj, gdzie co leży, poproś o trasę albo wyślij zdjęcie tabliczki, a ustawię Twoją pozycję. Asystent steruje apką przez lokalne narzędzia (MCP w telefonie).")
                    .spaced(.footnote).foregroundStyle(.secondary)
                if !ai.hasKey {
                    Label("Najpierw wpisz swój klucz API (Claude, Gemini albo Grok) w ustawieniach.", systemImage: "key.fill").spaced(.footnote, .semibold).foregroundStyle(.orange)
                    Button("Ustawienia asystenta") { showSettings = true }.buttonStyle(.glassProminent).tint(Theme.gold)
                }
            }
        }
    }

    private func bubble(_ l: ChatLine) -> some View {
        HStack {
            if l.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let img = l.image { Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160).clipShape(.rect(cornerRadius: 14)) }
                if l.role == .tool {
                    Label(l.text, systemImage: "wrench.and.screwdriver.fill").spaced(.caption, .semibold).foregroundStyle(Theme.gold)
                } else {
                    Text(l.text).spaced(.subheadline, .medium)
                }
            }
            .padding(12)
            .glassEffect(.regular.tint(tint(l.role)), in: .rect(cornerRadius: 18))
            if l.role != .user { Spacer(minLength: 40) }
        }
    }

    private func tint(_ r: ChatLine.Role) -> Color? {
        switch r {
        case .user: return Color.blue.opacity(0.4)
        case .assistant: return nil
        case .tool: return Theme.gold.opacity(0.12)
        case .error: return Color.red.opacity(0.35)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let p = photo {
                HStack {
                    Image(uiImage: p).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(.rect(cornerRadius: 10))
                    Text("Zdjęcie dołączone").spaced(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button { photo = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                Button { showCamera = true } label: { Image(systemName: "camera.fill").frame(width: 40, height: 40).glassEffect(.regular.interactive(), in: .circle) }
                    .buttonStyle(.plain).foregroundStyle(.white)
                PhotosPicker(selection: $pick, matching: .images) {
                    Image(systemName: "photo").frame(width: 40, height: 40).glassEffect(.regular.interactive(), in: .circle).foregroundStyle(.white)
                }
                TextField("Napisz do asystenta", text: $text, axis: .vertical).lineLimit(1...3)
                    .padding(.horizontal, 14).padding(.vertical, 10).glassEffect(.regular, in: .capsule)
                    .submitLabel(.send).onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain).disabled(ai.busy)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    private func send() {
        let t = text, p = photo
        text = ""
        photo = nil
        Task { await ai.send(t, image: p) }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.done(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct AssistantSettings: View {
    @ObservedObject var ai: Assistant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Dostawca") {
                    Picker("Model AI", selection: $ai.provider) { ForEach(LLMProvider.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented)
                    if ai.models.isEmpty {
                        TextField("Nazwa modelu", text: $ai.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        Picker("Model", selection: $ai.model) { ForEach(ai.models, id: \.self) { Text($0).tag($0) } }
                    }
                    Button("Pobierz listę modeli i sprawdź klucz") { Task { await ai.refreshModels() } }
                }

                Section {
                    SecureField(ai.hasKey ? "Klucz zapisany (wpisz nowy, aby zmienić)" : "Wklej klucz API", text: $ai.keyDraft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Zapisz klucz") { ai.saveKey() }.disabled(ai.keyDraft.isEmpty)
                    if ai.hasKey { Button("Usuń klucz", role: .destructive) { ai.keyDraft = ""; Keychain.set("", for: ai.provider.rawValue); ai.saveKey() } }
                } header: { Text("Klucz API (\(ai.provider.keyHint))") } footer: {
                    Text("Klucz trafia do Keychain tego telefonu i jest wysyłany tylko do wybranego dostawcy (Anthropic, Google albo xAI). Zapytania i zdjęcia idą bezpośrednio z telefonu, bez żadnego mojego serwera.")
                }

                if !ai.status.isEmpty { Section { Text(ai.status).spaced(.footnote) } }
            }
            .navigationTitle("Asystent AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// ------------------------------------------------------------------ konsola MCP

struct MCPConsole: View {
    @ObservedObject var mcp: LocalMCP
    @State private var tool = "get_state"
    @State private var args = "{}"
    @State private var out = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lokalny MCP").spaced(.headline, .bold)
                        Text("Narzędzia opisane jak w Model Context Protocol i wołane przez JSON-RPC 2.0 (initialize, tools/list, tools/call). Działa w apce, bez serwera. Modele (Claude, Gemini, Grok) wołają te narzędzia, a apka je wykonuje na Twoim telefonie.")
                            .spaced(.footnote).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wywołaj ręcznie").spaced(.subheadline, .bold)
                        Picker("Narzędzie", selection: $tool) { ForEach(mcp.tools, id: \.name) { Text($0.name).tag($0.name) } }.pickerStyle(.menu)
                        Text(mcp.tools.first { $0.name == tool }?.description ?? "").spaced(.caption).foregroundStyle(.secondary)
                        TextField("Argumenty (JSON)", text: $args).font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(10).glassEffect(.regular, in: .rect(cornerRadius: 14))
                        Button("tools/call") {
                            let a = (try? JSONSerialization.jsonObject(with: Data(args.utf8))) as? [String: Any] ?? [:]
                            out = mcp.call(tool, a)
                        }
                        .buttonStyle(.glassProminent).tint(Theme.gold)
                        if !out.isEmpty { Text(out).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Narzędzia (\(mcp.tools.count))").spaced(.subheadline, .bold)
                        ForEach(mcp.tools, id: \.name) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.gold)
                                Text(t.description).spaced(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dziennik wywołań").spaced(.subheadline, .bold)
                        if mcp.log.isEmpty { Text("Jeszcze nic nie wołano.").spaced(.footnote).foregroundStyle(.secondary) }
                        ForEach(mcp.log.reversed().prefix(12)) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("→ " + e.request).font(.system(size: 10, design: .monospaced)).foregroundStyle(.cyan)
                                Text("← " + e.response).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
