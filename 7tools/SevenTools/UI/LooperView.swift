import SwiftUI

struct LooperView: View {
    @EnvironmentObject private var hub: AudioHub
    @EnvironmentObject private var store: SoundStore
    @StateObject private var model: LooperModel
    @State private var confirmClear = false
    @State private var toast: String?
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(hub: AudioHub) {
        _model = StateObject(wrappedValue: LooperModel(hub: hub))
    }

    private var state: LooperCore.State { model.snap.state }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                ringArea
                statusText
                actions
                if !model.snap.layers.isEmpty { layers }
                settings
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(text: toast).padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.bouncy, value: toast)
        .animation(.bouncy(duration: 0.5), value: model.snap.layers.count)
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .confirmationDialog("Wyczyścić całą pętlę?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Wyczyść", role: .destructive) { model.clear() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pętla").spaced(.largeTitle, .bold)
                Text("Nagrywaj warstwy jedna na drugą").spaced(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // ---------------------------------------------------------- okrag z fala i glowny przycisk

    private var ringArea: some View {
        let side: CGFloat = 300
        return ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state == .empty && model.recordingLevel == 0)) { _ in
                Canvas { ctx, size in drawRing(ctx, size) }
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)

            Button {
                Task { await model.mainTap() }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: mainSymbol)
                        .font(.system(size: 44, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(mainLabel).spaced(.subheadline, .bold)
                        .contentTransition(.interpolate)
                }
                .foregroundStyle(.white)
                .frame(width: 150, height: 150)
                .glassEffect(.regular.tint(mainTint).interactive(), in: .circle)
                .scaleEffect(model.snap.state == .recordingFirst || model.snap.state == .overdubbing
                             ? 1 + CGFloat(model.recordingLevel) * 0.1 : 1)
            }
            .buttonStyle(.plain)
            .animation(.bouncy(duration: 0.45), value: state)
            .animation(.spring(duration: 0.15), value: model.recordingLevel)
            .accessibilityLabel(mainLabel)
        }
        .frame(height: side)
    }

    private var mainSymbol: String {
        switch state {
        case .empty: return "circle.fill"
        case .recordingFirst, .overdubbing: return "stop.fill"
        case .playing, .stopped: return "plus.circle.fill"
        }
    }

    private var mainLabel: String {
        switch state {
        case .empty: return "Nagraj"
        case .recordingFirst: return "Zakończ"
        case .playing, .stopped: return "Dogrywaj"
        case .overdubbing: return "Gotowe"
        }
    }

    private var mainTint: Color? {
        switch state {
        case .empty: return Color.red.opacity(0.5)
        case .recordingFirst: return Color.red.opacity(0.75)
        case .playing, .stopped: return Theme.gold.opacity(0.45)
        case .overdubbing: return Color.orange.opacity(0.75)
        }
    }

    private func drawRing(_ context: GraphicsContext, _ size: CGSize) {
        var ctx = context
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r0 = size.width * 0.31
        let maxLen = size.width * 0.17
        let bins = model.wave.count
        let prog = Double(model.progress())
        let recording = state == .recordingFirst || state == .overdubbing

        // delikatny okrag pod spodem
        var base = Path()
        base.addEllipse(in: CGRect(x: c.x - r0 + 2, y: c.y - r0 + 2, width: (r0 - 2) * 2, height: (r0 - 2) * 2))
        ctx.stroke(base, with: .color(.white.opacity(0.10)), lineWidth: 1)

        var lit = Path(), dim = Path()
        for i in 0..<bins {
            let a = Double(i) / Double(bins) * 2 * .pi - .pi / 2
            let v = CGFloat(model.wave[i])
            let len = 3 + v * maxLen
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
            p.addLine(to: CGPoint(x: c.x + cos(a) * (r0 + len), y: c.y + sin(a) * (r0 + len)))
            if Double(i) / Double(bins) <= prog && state != .empty { lit.addPath(p) } else { dim.addPath(p) }
        }
        ctx.stroke(dim, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 6))
            l.stroke(lit, with: .color(Theme.gold.opacity(0.8)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        ctx.stroke(lit, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        // glowica
        if model.snap.seconds > 0 {
            let a = prog * 2 * .pi - .pi / 2
            let hp = CGPoint(x: c.x + cos(a) * (r0 - 8), y: c.y + sin(a) * (r0 - 8))
            ctx.fill(Path(ellipseIn: CGRect(x: hp.x - 5, y: hp.y - 5, width: 10, height: 10)), with: .color(.white))
        }

        // przy pierwszym nagraniu fala zywa: pulsujacy okrag z poziomu mikrofonu
        if recording {
            let r = r0 + 6 + CGFloat(model.recordingLevel) * maxLen
            var p = Path()
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.stroke(p, with: .color(Color.red.opacity(0.7)), lineWidth: 2)
        }
    }

    private var statusText: some View {
        let t: String
        switch state {
        case .empty: t = model.source == .mic ? "Dotknij i zacznij grać lub śpiewać" : "Dotknij, a potem graj na padach"
        case .recordingFirst: t = "Nagrywam pierwszą warstwę…"
        case .playing: t = String(format: "%.1f s · %d %@", model.snap.seconds, model.snap.layers.count, layerWord(model.snap.layers.count))
        case .overdubbing: t = "Dogrywam warstwę…"
        case .stopped: t = "Zatrzymana"
        }
        return Text(t)
            .spaced(.subheadline, .semibold)
            .foregroundStyle(.secondary)
            .contentTransition(.interpolate)
            .animation(.smooth, value: t)
    }

    private func layerWord(_ n: Int) -> String {
        n == 1 ? "warstwa" : (n % 10 >= 2 && n % 10 <= 4 && !(n % 100 >= 12 && n % 100 <= 14) ? "warstwy" : "warstw")
    }

    // ---------------------------------------------------------- przyciski

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIcon(symbol: state == .stopped ? "play.fill" : "pause.fill", tint: nil,
                          label: state == .stopped ? "Wznów pętlę" : "Wstrzymaj pętlę") { model.togglePlay() }
                    .disabled(model.snap.seconds == 0)
                GlassIcon(symbol: "arrow.uturn.backward", tint: nil, label: "Cofnij warstwę") { model.undo() }
                    .disabled(model.snap.layers.isEmpty)
                GlassIcon(symbol: "trash.fill", tint: Color.red.opacity(0.4), label: "Wyczyść") { confirmClear = true }
                    .disabled(state == .empty)
                Spacer(minLength: 0)
                if model.snap.seconds > 0 {
                    Button {
                        if model.saveToLibrary(store) { show("Zapisano w Moich dźwiękach") }
                    } label: {
                        Chip(text: "Do biblioteki", symbol: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: LoopFile(model: model), preview: SharePreview("Pętla 7Tools")) {
                        Chip(text: "AirDrop", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .opacity(state == .empty ? 0.5 : 1)
        .animation(.smooth, value: state)
    }

    private var layers: some View {
        Card {
            VStack(spacing: 14) {
                ForEach(Array(model.snap.layers.enumerated()), id: \.offset) { i, l in
                    HStack(spacing: 12) {
                        Button {
                            model.toggleMute(i)
                        } label: {
                            Image(systemName: l.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .frame(width: 30)
                                .foregroundStyle(l.muted ? Color.secondary : Theme.gold)
                        }
                        .buttonStyle(.plain)
                        Text("Warstwa \(i + 1)").spaced(.subheadline, .semibold).frame(width: 88, alignment: .leading)
                        Slider(value: Binding(get: { Double(l.gain) }, set: { model.setGain(i, Float($0)) }), in: 0...1.5)
                            .disabled(l.muted)
                    }
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var settings: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ustawienia pętli").spaced(.headline, .bold)

                Picker("Skąd nagrywać", selection: $model.source) {
                    Text("Mikrofon").tag(LooperCore.Source.mic)
                    Text("Pady i klawisze").tag(LooperCore.Source.pads)
                }
                .pickerStyle(.segmented)
                .disabled(state != .empty)

                Text(model.source == .mic
                     ? "Nagrywa to, co słyszy mikrofon. Najlepiej ze słuchawkami, bo inaczej pętla nagra samą siebie."
                     : "Nagrywa to, co grasz na padach i klawiszach, bez mikrofonu. Wejdź w Pady, zagraj, a pętla to złapie.")
                    .spaced(.footnote).foregroundStyle(.secondary)

                SliderRow(symbol: "metronome.fill", title: "Tempo", value: $model.bpm, range: 40...220, step: 1) {
                    "\(Int($0)) BPM"
                }
                Toggle(isOn: $model.metronome) { Label("Metronom", systemImage: "metronome") }
                Toggle(isOn: $model.quantize) { Label("Zaokrąglaj do uderzeń", systemImage: "square.grid.3x1.below.line.grid.1x2") }
                    .disabled(state != .empty)
                if model.source == .mic {
                    SliderRow(symbol: "mic.fill", title: "Czułość wejścia", value: $model.inputGain, range: 0.3...3) {
                        String(format: "%.1fx", $0)
                    }
                }
            }
        }
    }

    private func show(_ t: String) {
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == t { toast = nil }
        }
    }
}
