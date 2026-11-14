import SwiftUI

// Obraca tresc o dowolny kat (0, 90, 180, 270), z poprawnym rozmiarem. Dzieki temu apka da sie trzymac
// do gory nogami albo bokiem, nawet gdy system nie obraca ekranu.
struct Rotating<Content: View>: View {
    let angle: Double
    let content: Content

    init(angle: Double, @ViewBuilder content: () -> Content) {
        self.angle = angle
        self.content = content()
    }

    var body: some View {
        GeometryReader { g in
            let sideways = Int(abs(angle)) % 180 == 90
            let w = sideways ? g.size.height : g.size.width
            let h = sideways ? g.size.width : g.size.height
            content
                .frame(width: w, height: h)
                .rotationEffect(.degrees(angle))
                .position(x: g.size.width / 2, y: g.size.height / 2)
                .animation(.smooth(duration: 0.5), value: angle)
        }
    }
}

// Tryb obrotowy: ekran z padami i najwazniejszymi przyciskami, ktory sam sie obraca do gory dla trzymajacego.
// Dziala do gory nogami, na boku i pod kazdym katem, w jakim go trzymasz.
struct StageView: View {
    @EnvironmentObject private var hub: AudioHub
    @EnvironmentObject private var motion: MotionHub
    @EnvironmentObject private var pads: PadsModel
    @EnvironmentObject private var store: SoundStore
    @Environment(\.dismiss) private var dismiss

    @State private var panel = 0
    @State private var lockAngle: Double?
    @StateObject private var looper: LooperModel

    init(hub: AudioHub) {
        _looper = StateObject(wrappedValue: LooperModel(hub: hub))
    }

    private var angle: Double { lockAngle ?? motion.pose.screenAngle }

    var body: some View {
        ZStack {
            Backdrop()
            Rotating(angle: angle) {
                VStack(spacing: 14) {
                    topBar
                    Group {
                        switch panel {
                        case 0: padsPanel
                        case 1: loopPanel
                        default: listenPanel
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomBar
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 40)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            motion.use("stage")
            looper.appear()
        }
        .onDisappear {
            motion.release("stage")
            looper.disappear()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(motion.pose.title).spaced(.footnote, .semibold).foregroundStyle(.secondary)
            Spacer()
            GlassIcon(symbol: lockAngle == nil ? "lock.open.fill" : "lock.fill", size: 40,
                      tint: lockAngle == nil ? nil : Theme.gold.opacity(0.5),
                      label: lockAngle == nil ? "Zablokuj obrót" : "Odblokuj obrót") {
                lockAngle = lockAngle == nil ? motion.pose.screenAngle : nil
            }
            GlassIcon(symbol: "xmark", size: 40, tint: nil, label: "Zamknij tryb obrotowy") { dismiss() }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                tab(0, "Pady", "square.grid.3x3.fill")
                tab(1, "Pętla", "repeat")
                tab(2, "Słuchaj", "ear.fill")
                GlassIcon(symbol: "stop.fill", size: 48, tint: Color.red.opacity(0.45), label: "Zatrzymaj wszystko") {
                    hub.mixer.stopAll()
                }
            }
        }
    }

    private func tab(_ i: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.bouncy(duration: 0.4)) { panel = i }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).spaced(.subheadline, .bold)
            }
            .foregroundStyle(panel == i ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassEffect(panel == i ? Glass.regular.tint(Theme.gold).interactive() : Glass.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // ---------------------------------------------------------- panele

    private var padsPanel: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<PadsModel.perBank, id: \.self) { slot in
                    PadCell(slot: slot, onEdit: {}, onEmpty: {})
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            HStack {
                Button {
                    withAnimation(.bouncy) { pads.bank = (pads.bank + 1) % PadsModel.banks }
                } label: {
                    Chip(text: "Bank " + (pads.bank == 0 ? "A" : "B"), symbol: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private var loopPanel: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Button {
                Task { await looper.mainTap() }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: looperSymbol).font(.system(size: 50, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(looperLabel).spaced(.headline, .bold)
                }
                .foregroundStyle(.white)
                .frame(width: 190, height: 190)
                .glassEffect(.regular.tint(looperTint).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                GlassIcon(symbol: "play.pause.fill", label: "Wstrzymaj lub wznów") { looper.togglePlay() }
                GlassIcon(symbol: "arrow.uturn.backward", label: "Cofnij") { looper.undo() }
                GlassIcon(symbol: "trash.fill", tint: Color.red.opacity(0.4), label: "Wyczyść") { looper.clear() }
            }
            Spacer(minLength: 0)
        }
        .animation(.bouncy, value: looper.snap.state)
    }

    private var looperSymbol: String {
        switch looper.snap.state {
        case .empty: return "circle.fill"
        case .recordingFirst, .overdubbing: return "stop.fill"
        default: return "plus.circle.fill"
        }
    }

    private var looperLabel: String {
        switch looper.snap.state {
        case .empty: return "Nagraj"
        case .recordingFirst: return "Zakończ"
        case .overdubbing: return "Gotowe"
        default: return "Dogrywaj"
        }
    }

    private var looperTint: Color {
        switch looper.snap.state {
        case .empty, .recordingFirst: return Color.red.opacity(0.6)
        case .overdubbing: return Color.orange.opacity(0.7)
        default: return Theme.gold.opacity(0.45)
        }
    }

    private var listenPanel: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Button {
                Task { await hub.toggleListen() }
            } label: {
                Image(systemName: hub.listening ? "waveform" : "ear.fill")
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: hub.listening)
                    .frame(width: 190, height: 190)
                    .glassEffect(.regular.tint(hub.listening ? Color.cyan.opacity(0.3) : nil).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            Text(hub.listening ? "Słucham" : (hub.headphones ? "Dotknij, aby słuchać" : "Podłącz słuchawki"))
                .spaced(.headline, .bold)
            Spacer(minLength: 0)
        }
    }
}

// ------------------------------------------------------------------ gesty

struct GesturesView: View {
    @EnvironmentObject private var gestures: GestureCenter
    @EnvironmentObject private var motion: MotionHub

    var body: some View {
        Page("Gesty", "Steruj telefonem ruchem: potrząśnij, odwróć, przechyl") {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $gestures.enabled) { Label("Gesty włączone", systemImage: "hand.raised.fingers.spread.fill").spaced(.headline, .bold) }
                        Text("Gesty działają, gdy apka jest otwarta. W tle iOS wyłącza czujniki ruchu.")
                            .spaced(.footnote).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(spacing: 16) {
                        ForEach(GestureTrigger.allCases) { t in
                            HStack(spacing: 12) {
                                Image(systemName: t.symbol).font(.system(size: 20, weight: .semibold)).frame(width: 30)
                                Text(t.title).spaced(.subheadline, .semibold)
                                Spacer(minLength: 6)
                                Picker(t.title, selection: Binding(
                                    get: { gestures.mapping[t] ?? .none },
                                    set: { gestures.set(t, $0) })) {
                                    ForEach(GestureAction.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    }
                }
                .opacity(gestures.enabled ? 1 : 0.5)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Teraz: \(motion.pose.title)").spaced(.subheadline, .bold)
                        if let l = gestures.last {
                            Text("Ostatni gest: \(l)").spaced(.footnote).foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
        }
        .onAppear { motion.use("gestures-view") }
        .onDisappear { motion.release("gestures-view") }
    }
}

// ------------------------------------------------------------------ poziomica

struct LevelView: View {
    @EnvironmentObject private var motion: MotionHub
    @State private var wasLevel = false

    var body: some View {
        Page("Poziomica", "Połóż telefon płasko albo przyłóż go do ściany") {
            VStack(spacing: 24) {
                let g = motion.gravity
                // plasko: x i y daja nachylenie. Pionowo: x daje przechyl
                let flat = abs(g.z) > 0.8
                let tiltX = flat ? asin(max(-1, min(1, g.x))) * 180 / .pi : asin(max(-1, min(1, g.x))) * 180 / .pi
                let tiltY = flat ? asin(max(-1, min(1, g.y))) * 180 / .pi : 0
                let level = abs(tiltX) < 0.6 && abs(tiltY) < 0.6

                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(70)
                    Rectangle().fill(.white.opacity(0.15)).frame(width: 1)
                    Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                    Circle()
                        .fill(level ? Color.green : Theme.gold)
                        .frame(width: 54, height: 54)
                        .glassEffect(.regular.tint(level ? Color.green.opacity(0.5) : nil), in: .circle)
                        .offset(x: CGFloat(max(-1, min(1, tiltX / 20))) * 110,
                                y: CGFloat(max(-1, min(1, tiltY / 20))) * -110)
                        .animation(.spring(duration: 0.2), value: tiltX)
                }
                .frame(width: 280, height: 280)
                .frame(maxWidth: .infinity)

                Text(String(format: "%+.1f° · %+.1f°", tiltX, tiltY))
                    .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(level ? Color.green : .white)
                    .frame(maxWidth: .infinity)
                    .onChange(of: level) { _, now in if now { Haptics.ok() } }
            }
        }
        .onAppear { motion.use("level") }
        .onDisappear { motion.release("level") }
    }
}
