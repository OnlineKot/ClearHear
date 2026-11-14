import SwiftUI
import AVFoundation

// Psikusy: pelnoekranowe zarty. Zadnych prawdziwych danych, nic nie wychodzi z telefonu.
// Wyjscie z kazdego: 5 razy dotknij lewy gorny rog.

enum Prank: String, CaseIterable, Identifiable {
    case update, demo, fakeOS, evil, spider, fly, crack, call, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .update: return "Aktualizacja systemu"
        case .demo: return "Tryb demo"
        case .fakeOS: return "Fałszywy iOS"
        case .evil: return "Evil iOS"
        case .spider: return "Pająk na ekranie"
        case .fly: return "Mucha"
        case .crack: return "Pęknięty ekran"
        case .call: return "Fałszywy telefon"
        case .battery: return "Bateria 1%"
        }
    }

    var subtitle: String {
        switch self {
        case .update: return "Pasek postępu, który nigdy nie dochodzi do końca"
        case .demo: return "Telefon \"ze sklepu\", z którego nie da się wyjść"
        case .fakeOS: return "Prawie jak prawdziwy: ekran główny, Ustawienia i apki systemowe z głupimi wartościami"
        case .evil: return "Zły system z Evil Safari, Evil Siri i kalkulatorem, który kłamie"
        case .spider: return "Pająk chodzi po ekranie. Da się go zgnieść"
        case .fly: return "Bzyczy i lata po ekranie"
        case .crack: return "Ekran pęka z hukiem szkła"
        case .call: return "Dzwoni \"Mama\" z dzwonkiem i drganiem"
        case .battery: return "Ostrzeżenie o baterii i czarny ekran"
        }
    }

    var symbol: String {
        switch self {
        case .update: return "arrow.down.circle.fill"
        case .demo: return "storefront.fill"
        case .fakeOS: return "iphone.gen3"
        case .evil: return "flame.fill"
        case .spider: return "ladybug.fill"
        case .fly: return "ant.fill"
        case .crack: return "bolt.horizontal.fill"
        case .call: return "phone.arrow.down.left.fill"
        case .battery: return "battery.25percent"
        }
    }

    var tint: Color {
        switch self {
        case .update: return .blue
        case .demo: return .orange
        case .fakeOS: return .blue
        case .evil: return .red
        case .spider: return .purple
        case .fly: return .green
        case .crack: return .gray
        case .call: return .green
        case .battery: return .yellow
        }
    }
}

struct PranksView: View {
    @State private var selected: Prank?

    var body: some View {
        Page("Psikusy", "Żarty na ekranie. Pokaż komuś telefon i patrz na minę") {
            VStack(spacing: 12) {
                ForEach(Prank.allCases) { p in
                    Button { selected = p } label: {
                        HStack(spacing: 16) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 50, height: 50)
                                .glassEffect(.regular.tint(p.tint.opacity(0.5)), in: .circle)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).spaced(.headline, .bold)
                                Text(p.subtitle).spaced(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 4)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
                    }
                    .buttonStyle(.plain)
                }
                Text("To tylko zabawa. Nie podszywa się pod żadną firmę ani nie prosi o żadne dane. Żartuj z ludźmi, którzy to wytrzymają.")
                    .spaced(.footnote).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        .fullScreenCover(item: $selected) { p in PrankRunner(prank: p) }
    }
}

// Ekran startowy z instrukcja, potem sam zart na caly ekran z ukrytym wyjsciem.
struct PrankRunner: View {
    let prank: Prank
    @EnvironmentObject private var hub: AudioHub
    @Environment(\.dismiss) private var dismiss

    @State private var started = false
    @State private var dim = true
    @State private var callName = "Mama"
    @State private var callPhrase = "Halo? Słyszysz mnie? Dzwonię w sprawie tego, co zrobiłeś."
    @State private var taps = 0
    @State private var lastTap = Date.distantPast
    @State private var oldBrightness: CGFloat = 0.5

    var body: some View {
        ZStack {
            if started {
                Color.black.ignoresSafeArea()
                runner
                    .ignoresSafeArea()
                Color.clear
                    .frame(width: 90, height: 90)
                    .contentShape(Rectangle())
                    .onTapGesture { exitTap() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea()
            } else {
                setup
            }
        }
        .statusBarHidden(started)
        .persistentSystemOverlays(started ? .hidden : .automatic)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var runner: some View {
        switch prank {
        case .update: FakeUpdate()
        case .demo: DemoMode()
        case .fakeOS: FakeOSHome()
        case .evil: EvilHome()
        case .spider: BugScreen(kind: .spider)
        case .fly: BugScreen(kind: .fly)
        case .crack: CrackedScreen()
        case .call: FakeCall(name: callName, phrase: callPhrase, finish: leave)
        case .battery: LowBattery()
        }
    }

    private var setup: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: prank.symbol).font(.system(size: 54, weight: .semibold))
                    .frame(width: 120, height: 120)
                    .glassEffect(.regular.tint(prank.tint.opacity(0.5)), in: .circle)
                Text(prank.title).spaced(.largeTitle, .bold)
                Text(prank.subtitle).spaced(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Wyjście: 5 razy dotknij lewy górny róg ekranu.", systemImage: "hand.tap.fill").spaced(.subheadline, .bold)
                        if prank == .call {
                            TextField("Kto dzwoni", text: $callName).padding(10).glassEffect(.regular, in: .capsule)
                            TextField("Co powie po odebraniu", text: $callPhrase, axis: .vertical)
                                .lineLimit(2...4).padding(10).glassEffect(.regular, in: .rect(cornerRadius: 18))
                        }
                        Toggle(isOn: $dim) { Label("Przyciemnij ekran", systemImage: "sun.min.fill") }
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Button("Anuluj") { dismiss() }.buttonStyle(.glass)
                    Button("Start") { start() }.buttonStyle(.glassProminent).tint(Theme.gold)
                }
                .controlSize(.large)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private func start() {
        oldBrightness = UIScreen.main.brightness
        if dim { UIScreen.main.brightness = 0.2 }
        UIApplication.shared.isIdleTimerDisabled = true
        started = true
    }

    private func exitTap() {
        let now = Date()
        taps = now.timeIntervalSince(lastTap) < 2 ? taps + 1 : 1
        lastTap = now
        if taps >= 5 { leave() }
    }

    private func leave() {
        hub.mixer.stopAll()
        UIApplication.shared.isIdleTimerDisabled = false
        if started && dim { UIScreen.main.brightness = oldBrightness }
        dismiss()
    }
}

private enum PrankAudio {
    static var cache: [String: SampleBuffer] = [:]
    static func buf(_ id: String) -> SampleBuffer? {
        if let b = cache[id] { return b }
        guard let b = PrankSound.all[id]?() else { return nil }
        cache[id] = b
        return b
    }
}

// ------------------------------------------------------------------ fałszywa aktualizacja

struct FakeUpdate: View {
    @State private var progress = 0.02
    @State private var eta = "Pozostało: około 3 godz."
    @State private var restarting = false

    private static let etas = ["Pozostało: około 3 godz.", "Pozostało: 12 min", "Pozostało: 47 godz.", "Obliczanie czasu…",
                               "Pozostało: mniej niż minuta", "Pozostało: 2 dni", "Pozostało: -4 min", "Pozostało: dużo"]

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 26) {
                Text("7").font(.system(size: 90, weight: .black, design: .rounded)).foregroundStyle(Theme.gold)
                if restarting {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white).scaleEffect(1.3)
                        Text("Coś poszło nie tak. Ponawiam…").spaced(.subheadline).foregroundStyle(.gray)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("Aktualizowanie systemu").spaced(.title3, .semibold)
                        ProgressView(value: progress).tint(.white).frame(width: 230).animation(.linear(duration: 0.5), value: progress)
                        Text(eta).spaced(.footnote).foregroundStyle(.gray).contentTransition(.interpolate)
                        Text("Nie wyłączaj telefonu").spaced(.caption).foregroundStyle(.gray.opacity(0.7))
                    }
                }
            }
        }
        .task {
            var etaTimer = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if restarting { continue }
                etaTimer += 1
                if etaTimer % 10 == 0 { withAnimation { eta = Self.etas.randomElement() ?? eta } }
                if progress < 0.95 {
                    progress += Double.random(in: 0.002...0.012)
                } else if progress < 0.99 {
                    progress += 0.0004
                } else {
                    // staje na 99% i zaczyna od nowa
                    try? await Task.sleep(for: .seconds(8))
                    restarting = true
                    try? await Task.sleep(for: .seconds(4))
                    progress = 0.02
                    restarting = false
                }
            }
        }
    }
}

// ------------------------------------------------------------------ tryb demo

struct DemoMode: View {
    private static let promos = ["Najnowsza generacja", "Zobacz aparat w akcji", "Bateria na cały dzień", "Dotknij, aby zacząć", "Pytaj o ratalne 0%"]
    @State private var i = 0
    @State private var pin = false
    @State private var code = ""
    @State private var wrong = 0
    @State private var shakeAmount = 0.0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.1, blue: 0.4), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 20) {
                Spacer()
                Text("TRYB DEMO").font(.system(size: 20, weight: .heavy)).tracking(6).foregroundStyle(Theme.gold)
                Text(Self.promos[i]).font(.system(size: 38, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                    .id(i).transition(.blurReplace)
                Text("Dotknij ekran, aby poznać telefon").spaced(.subheadline).foregroundStyle(.gray)
                Spacer()
                Text("Ten telefon jest własnością sklepu. Aby wyjść z trybu demo, poproś o pomoc pracownika.")
                    .spaced(.caption).foregroundStyle(.gray).multilineTextAlignment(.center).padding(.horizontal, 30)
                Button("Wyjdź z trybu demo") { pin = true }.buttonStyle(.glass).padding(.bottom, 30)
            }
            .padding(.horizontal, 20)

            if pin {
                Color.black.opacity(0.85)
                    .onTapGesture { pin = false }
                VStack(spacing: 16) {
                    Text("Kod pracownika").spaced(.title3, .bold)
                    Text(String(repeating: "● ", count: code.count) + String(repeating: "○ ", count: max(0, 4 - code.count)))
                        .font(.system(size: 28)).offset(x: shakeAmount)
                    if wrong > 0 { Text("Nieprawidłowy kod. Spróbuj później.").spaced(.footnote).foregroundStyle(.red) }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 14), count: 3), spacing: 14) {
                        ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"], id: \.self) { k in
                            if k.isEmpty { Color.clear.frame(width: 70, height: 70) } else {
                                Button { press(k) } label: {
                                    Text(k).font(.system(size: 28, weight: .semibold)).frame(width: 70, height: 70)
                                        .glassEffect(.regular.interactive(), in: .circle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.smooth) { i = (i + 1) % Self.promos.count }
            }
        }
    }

    private func press(_ k: String) {
        Haptics.tap(.light)
        if k == "⌫" { _ = code.popLast(); return }
        code.append(k)
        if code.count == 4 {
            // kod nigdy nie pasuje
            wrong += 1
            Haptics.ok()
            withAnimation(.default.repeatCount(4, autoreverses: true).speed(6)) { shakeAmount = 12 }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                shakeAmount = 0
                code = ""
            }
        }
    }
}

// ------------------------------------------------------------------ bateria 1%

struct LowBattery: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var stage = 0   // 0 normalnie, 1 ostrzezenie, 2 czarny, 3 zart

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.1, green: 0.15, blue: 0.3), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 86, weight: .thin, design: .rounded))
                Text("Przesuń, aby odblokować").spaced(.footnote).foregroundStyle(.gray)
            }

            if stage == 1 {
                VStack(spacing: 14) {
                    Image(systemName: "battery.0percent").font(.system(size: 34)).foregroundStyle(.red)
                    Text("Niski poziom baterii").spaced(.headline, .bold)
                    Text("Pozostało 1% energii.").spaced(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Zamknij") {}.buttonStyle(.glass)
                        Button("Oszczędzanie") {}.buttonStyle(.glassProminent).tint(.yellow)
                    }
                }
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
                .padding(40)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if stage >= 2 {
                Color.black.ignoresSafeArea()
                    .onTapGesture { if stage == 2 { withAnimation { stage = 3 } } }
            }
            if stage == 3 {
                VStack(spacing: 10) {
                    Text("😄").font(.system(size: 80))
                    Text("Żartowałem!").spaced(.title, .bold)
                    Text("Bateria jest w porządku.").spaced(.subheadline).foregroundStyle(.gray)
                }
            }
        }
        .animation(.bouncy, value: stage)
        .task {
            try? await Task.sleep(for: .seconds(2))
            stage = 1
            if let b = PrankAudio.buf("error") { hub.mixer.play(b, tag: 9300, gain: 0.7) }
            Haptics.ok()
            try? await Task.sleep(for: .seconds(5))
            if let b = PrankAudio.buf("powerdown") { hub.mixer.play(b, tag: 9301, gain: 0.7) }
            stage = 2
        }
    }
}

// ------------------------------------------------------------------ pekniety ekran

struct CrackedScreen: View {
    @EnvironmentObject private var hub: AudioHub

    struct Crack: Identifiable {
        let id = UUID()
        let lines: [[CGPoint]]
    }

    @State private var cracks: [Crack] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.1, green: 0.2, blue: 0.45), Color(red: 0.05, green: 0.05, blue: 0.15)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 6) {
                    Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 92, weight: .thin, design: .rounded))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).spaced(.headline).foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 90)

                Canvas { ctx, _ in
                    for c in cracks {
                        for line in c.lines {
                            var p = Path()
                            p.move(to: line[0])
                            for pt in line.dropFirst() { p.addLine(to: pt) }
                            ctx.stroke(p, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                            ctx.stroke(p, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in addCrack(at: v.location) })
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                addCrack(at: CGPoint(x: geo.size.width * 0.6, y: geo.size.height * 0.4))
            }
        }
    }

    private func addCrack(at p: CGPoint) {
        var lines: [[CGPoint]] = []
        let rays = Int.random(in: 7...11)
        for r in 0..<rays {
            var angle = Double(r) / Double(rays) * 2 * .pi + Double.random(in: -0.25...0.25)
            var cur = p
            var line = [cur]
            var len = CGFloat.random(in: 40...90)
            for _ in 0..<Int.random(in: 4...8) {
                angle += Double.random(in: -0.3...0.3)
                cur = CGPoint(x: cur.x + cos(angle) * len, y: cur.y + sin(angle) * len)
                line.append(cur)
                if Bool.random() {
                    let b = angle + Double.random(in: -1...1)
                    lines.append([cur, CGPoint(x: cur.x + cos(b) * len * 0.8, y: cur.y + sin(b) * len * 0.8)])
                }
                len *= 0.85
            }
            lines.append(line)
        }
        withAnimation(.easeOut(duration: 0.12)) { cracks.append(Crack(lines: lines)) }
        if let b = PrankAudio.buf("glass") { hub.mixer.play(b, tag: 9400 + cracks.count % 4, gain: 0.9) }
        Haptics.tap(.heavy)
    }
}

// ------------------------------------------------------------------ pajak i mucha

struct BugScreen: View {
    enum Kind { case spider, fly }

    let kind: Kind
    @EnvironmentObject private var hub: AudioHub

    final class Sim {
        var pos = CGPoint(x: -40, y: 300)
        var target = CGPoint(x: 150, y: 400)
        var vel = CGVector(dx: 0, dy: 0)
        var angle = 0.0
        var phase = 0.0
        var alive = true
        var respawnAt = 0.0
        var lastTick = 0.0
        var last: TimeInterval = 0
    }

    @State private var sim = Sim()
    @State private var splats: [CGPoint] = []

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let now = tl.date.timeIntervalSinceReferenceDate
                let _ = step(now, geo.size)
                Canvas { ctx, size in
                    for s in splats { drawSplat(ctx, s) }
                    if sim.alive { kind == .spider ? drawSpider(ctx) : drawFly(ctx) }
                }
            }
            .background(Color(white: 0.93))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in tap(v.location) })
        }
        .onAppear {
            if kind == .fly, let b = PrankAudio.buf("fly") { hub.mixer.play(b, tag: 9500, gain: 0.55, loop: true) }
        }
        .onDisappear { hub.mixer.stop(tag: 9500) }
    }

    private func step(_ now: TimeInterval, _ size: CGSize) {
        let dt = sim.last == 0 ? 0.016 : min(0.05, now - sim.last)
        sim.last = now
        if !sim.alive {
            if now > sim.respawnAt {
                sim.alive = true
                sim.pos = CGPoint(x: -30, y: CGFloat.random(in: 100...(size.height - 100)))
                sim.target = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                if kind == .fly, let b = PrankAudio.buf("fly") { hub.mixer.play(b, tag: 9500, gain: 0.55, loop: true) }
            }
            return
        }
        let dx = sim.target.x - sim.pos.x, dy = sim.target.y - sim.pos.y
        let dist = max(1, (dx * dx + dy * dy).squareRoot())
        if dist < 25 || (kind == .fly && Int(now * 3) % 2 == 0 && Double.random(in: 0...1) < 0.05) {
            sim.target = CGPoint(x: CGFloat.random(in: 30...(size.width - 30)), y: CGFloat.random(in: 60...(size.height - 60)))
        }
        let speed: CGFloat = kind == .spider ? 95 : 260
        let jitter: CGFloat = kind == .fly ? 140 : 0
        sim.vel = CGVector(dx: dx / dist * speed + CGFloat.random(in: -jitter...jitter),
                           dy: dy / dist * speed + CGFloat.random(in: -jitter...jitter))
        sim.pos.x += sim.vel.dx * CGFloat(dt)
        sim.pos.y += sim.vel.dy * CGFloat(dt)
        sim.angle = atan2(Double(sim.vel.dy), Double(sim.vel.dx))
        sim.phase += dt * (kind == .spider ? 14 : 60)
        // szelest nozek
        if kind == .spider && now - sim.lastTick > 0.11 {
            sim.lastTick = now
            if let b = PrankAudio.buf("tick") { hub.mixer.play(b, tag: 9501, gain: 0.3) }
            Haptics.tap(.soft, 0.25)
        }
    }

    private func tap(_ p: CGPoint) {
        guard sim.alive else { return }
        let d = ((p.x - sim.pos.x) * (p.x - sim.pos.x) + (p.y - sim.pos.y) * (p.y - sim.pos.y)).squareRoot()
        if d < 60 {
            sim.alive = false
            sim.respawnAt = Date.timeIntervalSinceReferenceDate + 3
            splats.append(sim.pos)
            if splats.count > 5 { splats.removeFirst() }
            hub.mixer.stop(tag: 9500)
            if let b = PrankAudio.buf("splat") { hub.mixer.play(b, tag: 9502, gain: 0.9) }
            Haptics.ok()
        }
    }

    private func drawSplat(_ ctx: GraphicsContext, _ p: CGPoint) {
        var path = Path()
        for i in 0..<9 {
            let a = Double(i) / 9 * 2 * .pi
            let r: CGFloat = i % 2 == 0 ? 26 : 12
            path.addEllipse(in: CGRect(x: p.x + cos(a) * r - 6, y: p.y + sin(a) * r - 6, width: 12, height: 12))
        }
        path.addEllipse(in: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36))
        ctx.fill(path, with: .color(Color(white: 0.1).opacity(0.8)))
    }

    private func drawSpider(_ context: GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: sim.pos.x, y: sim.pos.y)
        ctx.rotate(by: .radians(sim.angle))
        for side in [-1.0, 1.0] {
            for i in 0..<4 {
                let base = (Double(i) - 1.5) * 0.55
                let wave = sin(sim.phase + Double(i) * 1.6 + (side > 0 ? 0 : .pi)) * 0.3
                var leg = Path()
                let a1 = side * (1.2 + base * 0.4) + wave
                let kx = cos(a1) * 22, ky = sin(a1) * 22
                leg.move(to: CGPoint(x: base * 9, y: side * 5))
                leg.addLine(to: CGPoint(x: base * 9 + kx, y: side * 5 + ky))
                leg.addLine(to: CGPoint(x: base * 9 + kx * 1.5 + side * 4, y: side * 5 + ky * 1.7 + CGFloat(wave) * 12))
                ctx.stroke(leg, with: .color(.black), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        ctx.fill(Path(ellipseIn: CGRect(x: -16, y: -11, width: 28, height: 22)), with: .color(.black))
        ctx.fill(Path(ellipseIn: CGRect(x: 8, y: -7, width: 15, height: 14)), with: .color(.black))
    }

    private func drawFly(_ context: GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: sim.pos.x, y: sim.pos.y)
        ctx.rotate(by: .radians(sim.angle))
        let flap = sin(sim.phase) * 0.6
        for s in [-1.0, 1.0] {
            var wing = Path()
            wing.addEllipse(in: CGRect(x: -6, y: s > 0 ? 2 : -14 - CGFloat(flap) * 4, width: 16, height: 12 + CGFloat(abs(flap)) * 4))
            ctx.fill(wing, with: .color(.gray.opacity(0.5)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: -9, y: -5, width: 18, height: 10)), with: .color(.black))
        ctx.fill(Path(ellipseIn: CGRect(x: 6, y: -4, width: 8, height: 8)), with: .color(Color(white: 0.15)))
    }
}

// ------------------------------------------------------------------ falszywy telefon

struct FakeCall: View {
    let name: String
    let phrase: String
    let finish: () -> Void

    @EnvironmentObject private var hub: AudioHub
    @StateObject private var speaker = Speaker()
    @State private var answered = false
    @State private var seconds = 0
    @State private var ringing = true
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.35), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Spacer().frame(height: 80)
                Text(name).font(.system(size: 40, weight: .medium))
                Text(answered ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "komórka…")
                    .spaced(.title3).foregroundStyle(.gray).monospacedDigit()
                Circle().fill(Color.gray.opacity(0.35)).frame(width: 130, height: 130)
                    .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: 60, weight: .semibold)))
                    .padding(.top, 20)
                    .scaleEffect(ringing ? 1.05 : 1)
                    .animation(ringing ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: ringing)
                Spacer()
                HStack(spacing: 70) {
                    callButton("phone.down.fill", .red, answered ? "Zakończ" : "Odrzuć") {
                        stop()
                        finish()
                    }
                    if !answered {
                        callButton("phone.fill", .green, "Odbierz") { answer() }
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .onAppear {
            if let b = PrankAudio.buf("ring") { hub.mixer.play(b, tag: 9600, gain: 0.9, loop: true) }
        }
        .onReceive(tick) { _ in
            if answered { seconds += 1 } else if ringing { Haptics.ok() }
        }
        .onDisappear { stop() }
    }

    private func callButton(_ symbol: String, _ color: Color, _ label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular.tint(color.opacity(0.85)).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            Text(label).spaced(.footnote).foregroundStyle(.white)
        }
    }

    private func answer() {
        hub.mixer.stop(tag: 9600)
        ringing = false
        answered = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            speaker.say(phrase, voice: AVSpeechSynthesisVoice(language: "pl-PL"), rate: 0.5, pitch: 1)
        }
    }

    private func stop() {
        hub.mixer.stop(tag: 9600)
        speaker.stop()
    }
}
