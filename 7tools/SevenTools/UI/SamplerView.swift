import SwiftUI

struct SamplerView: View {
    @EnvironmentObject private var store: SoundStore
    @EnvironmentObject private var hub: AudioHub
    @StateObject private var model: SamplerModel
    @State private var showPicker = false

    init(hub: AudioHub, store: SoundStore) {
        _model = StateObject(wrappedValue: SamplerModel(hub: hub, store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sampler").spaced(.largeTitle, .bold)
                        Text("Zagraj dowolnym dźwiękiem jak na instrumencie").spaced(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                sampleCard
                modeSwitch
                if model.chop { ChopPads(model: model) } else { Keyboard(model: model) }
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .sheet(isPresented: $showPicker) {
            LibraryView(pick: { model.soundID = $0 })
        }
        .animation(.bouncy(duration: 0.5), value: model.chop)
    }

    // ---------------------------------------------------------- sample i przycinanie

    private var sampleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "waveform").foregroundStyle(Theme.gold)
                    Text(store.name(model.soundID)).spaced(.headline, .bold).lineLimit(1)
                    Spacer()
                    Button { showPicker = true } label: { Chip(text: "Zmień", symbol: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.plain)
                }
                WaveTrim(wave: model.wave, start: $model.trimStart, end: $model.trimEnd)
                    .frame(height: 96)
                HStack {
                    Toggle(isOn: $model.reverse) { Label("Od tyłu", systemImage: "backward.fill") }
                }
            }
        }
    }

    private var modeSwitch: some View {
        Picker("Tryb", selection: $model.chop) {
            Label("Klawisze", systemImage: "pianokeys").tag(false)
            Label("Pocięte", systemImage: "square.grid.4x3.fill").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private var controls: some View {
        Card {
            VStack(spacing: 14) {
                if !model.chop {
                    HStack {
                        Label("Nuta bazowa", systemImage: "music.note")
                            .spaced(.subheadline, .semibold)
                        Spacer()
                        Picker("Nuta bazowa", selection: $model.root) {
                            ForEach(36...84, id: \.self) { n in
                                let x = Pitch.note(for: Pitch.frequency(midi: n))
                                Text("\(x.name)\(x.octave)").tag(n)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    SliderRow(symbol: "arrow.up.right", title: "Narastanie", value: $model.attack, range: 0.001...1) {
                        $0 < 0.01 ? "natychmiast" : String(format: "%.2f s", $0)
                    }
                    SliderRow(symbol: "arrow.down.right", title: "Wybrzmiewanie", value: $model.release, range: 0.01...2.5) {
                        String(format: "%.2f s", $0)
                    }
                    Toggle(isOn: $model.sustainLoop) { Label("Pętla, gdy trzymasz klawisz", systemImage: "repeat") }
                } else {
                    Text("Dźwięk jest pocięty na 16 równych kawałków. Przytnij fragment wyżej, a pady zagrają jego części. Tak robi się chopy.")
                        .spaced(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// ------------------------------------------------------------------ fala z uchwytami

struct WaveTrim: View {
    let wave: [Float]
    @Binding var start: Double
    @Binding var end: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    let n = max(1, wave.count)
                    let bw = size.width / CGFloat(n)
                    for i in 0..<wave.count {
                        let v = CGFloat(wave[i])
                        let x = CGFloat(i) * bw
                        let inside = Double(x / size.width) >= start && Double(x / size.width) <= end
                        let hh = max(2, v * size.height * 0.9)
                        let r = CGRect(x: x + 0.5, y: (size.height - hh) / 2, width: max(1, bw - 1.5), height: hh)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 1.5),
                                 with: .color(inside ? Theme.gold : Color.white.opacity(0.25)))
                    }
                }

                handle(h).offset(x: CGFloat(start) * w - 7)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        start = min(max(0, Double(v.location.x / w)), end - 0.03)
                    })
                handle(h).offset(x: CGFloat(end) * w - 7)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        end = max(min(1, Double(v.location.x / w)), start + 0.03)
                    })
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Zakres dźwięku")
        .accessibilityValue("od \(Int(start * 100)) do \(Int(end * 100)) procent")
    }

    private func handle(_ h: CGFloat) -> some View {
        Capsule()
            .fill(Theme.gold)
            .frame(width: 5, height: h)
            .padding(.horizontal, 5)
            .contentShape(Rectangle().inset(by: -8))
    }
}

// ------------------------------------------------------------------ klawiatura

struct Keyboard: View {
    @ObservedObject var model: SamplerModel
    @State private var down = Set<Int>()

    private static let first = 48          // C3
    private static let whiteCount = 15     // dwie oktawy i troche
    private static let whiteSteps = [0, 2, 4, 5, 7, 9, 11]
    private static let blackAfter: Set<Int> = [0, 1, 3, 4, 5]     // po ktorych bialych jest czarny (w oktawie)

    private func whiteNote(_ i: Int) -> Int {
        Self.first + (i / 7) * 12 + Self.whiteSteps[i % 7]
    }

    var body: some View {
        GeometryReader { geo in
            let kw = geo.size.width / CGFloat(Self.whiteCount)
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(0..<Self.whiteCount, id: \.self) { i in
                        key(note: whiteNote(i), black: false)
                    }
                }
                ForEach(0..<Self.whiteCount - 1, id: \.self) { i in
                    if Self.blackAfter.contains(i % 7) {
                        key(note: whiteNote(i) + 1, black: true)
                            .frame(width: kw * 0.62, height: h * 0.6)
                            .offset(x: kw * CGFloat(i + 1) - kw * 0.31)
                    }
                }
            }
        }
        .frame(height: 190)
    }

    private func key(note: Int, black: Bool) -> some View {
        let on = down.contains(note)
        return RoundedRectangle(cornerRadius: black ? 8 : 12, style: .continuous)
            .fill(.clear)
            .glassEffect(black
                         ? Glass.regular.tint(on ? Theme.gold : Color.black.opacity(0.85)).interactive()
                         : Glass.regular.tint(on ? Theme.gold.opacity(0.8) : Color.white.opacity(0.12)).interactive(),
                         in: .rect(cornerRadius: black ? 8 : 12))
            .overlay(alignment: .bottom) {
                if !black && note % 12 == 0 {
                    Text("C\(note / 12 - 1)").spaced(.caption2, .bold).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 8)
                }
            }
            .scaleEffect(on ? 0.97 : 1, anchor: .top)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: on)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down.contains(note) {
                            down.insert(note)
                            Haptics.tap(.light, 0.7)
                            model.noteOn(note)
                        }
                    }
                    .onEnded { _ in
                        down.remove(note)
                        model.noteOff(note)
                    }
            )
            .accessibilityLabel(Pitch.names[((note % 12) + 12) % 12] + String(note / 12 - 1))
    }
}

struct ChopPads: View {
    @ObservedObject var model: SamplerModel
    @State private var down = Set<Int>()

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(0..<SamplerModel.slices, id: \.self) { k in
                let on = down.contains(k)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.tint(Theme.pad(k).opacity(on ? 0.75 : 0.3)).interactive(), in: .rect(cornerRadius: 20))
                    .overlay(Text("\(k + 1)").spaced(.title3, .bold).foregroundStyle(.white.opacity(0.9)))
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(on ? 0.94 : 1)
                    .animation(.spring(duration: 0.22, bounce: 0.4), value: on)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !down.contains(k) {
                                    down.insert(k)
                                    Haptics.tap(.rigid, 0.9)
                                    model.sliceOn(k)
                                }
                            }
                            .onEnded { _ in down.remove(k) }
                    )
            }
        }
    }
}
