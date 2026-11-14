import SwiftUI

struct PadsView: View {
    @EnvironmentObject private var pads: PadsModel
    @EnvironmentObject private var store: SoundStore
    @State private var editSlot: Int?
    @State private var pickSlot: Int?
    @State private var showLibrary = false
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 16) {
            header
            bankPicker
            grid
            Spacer(minLength: 0)
            if pads.editing {
                Text("Tryb edycji: dotknij pada, żeby zmienić dźwięk, tryb i głośność.")
                    .spaced(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Backdrop())
        .animation(.bouncy(duration: 0.5), value: pads.editing)
        .sheet(item: Binding(get: { editSlot.map { SlotID(id: $0) } }, set: { editSlot = $0?.id })) { s in
            PadEditor(slot: s.id)
        }
        .sheet(item: Binding(get: { pickSlot.map { SlotID(id: $0) } }, set: { pickSlot = $0?.id })) { s in
            LibraryView(pick: { id in
                pads.assign(s.id, sound: id)
                Haptics.ok()
            })
        }
        .sheet(isPresented: $showLibrary) { LibraryView(pick: nil) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pady").spaced(.largeTitle, .bold)
                Text("Soundboard").spaced(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    GlassIcon(symbol: "globe", tint: nil, label: "Biblioteka dźwięków") { showLibrary = true }
                    GlassIcon(symbol: "pencil", tint: pads.editing ? Theme.gold.opacity(0.6) : nil,
                              label: "Edytuj pady") { withAnimation(.bouncy) { pads.editing.toggle() } }
                    GlassIcon(symbol: "stop.fill", tint: Color.red.opacity(0.45), label: "Zatrzymaj wszystko") {
                        pads.stopAll()
                        Haptics.tap(.soft)
                    }
                }
            }
        }
    }

    private var bankPicker: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<PadsModel.banks, id: \.self) { b in
                    Button {
                        withAnimation(.bouncy(duration: 0.45)) { pads.bank = b }
                    } label: {
                        Text("Bank " + (b == 0 ? "A" : "B"))
                            .spaced(.subheadline, .bold)
                            .foregroundStyle(pads.bank == b ? Color.white : Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if pads.bank == b {
                            Color.clear
                                .glassEffect(.regular.tint(Theme.gold.opacity(0.5)).interactive(), in: .capsule)
                                .glassEffectID("bank", in: ns)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: pads.bank)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(0..<PadsModel.perBank, id: \.self) { slot in
                PadCell(slot: slot,
                        onEdit: { editSlot = slot },
                        onEmpty: { pickSlot = slot })
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .id(pads.bank)
        .transition(.opacity.combined(with: .scale(0.96)))
    }
}

struct SlotID: Identifiable { let id: Int }

struct PadCell: View {
    let slot: Int
    let onEdit: () -> Void
    let onEmpty: () -> Void

    @EnvironmentObject private var pads: PadsModel
    @EnvironmentObject private var store: SoundStore
    @State private var down = false

    var body: some View {
        let c = pads.config(slot)
        let empty = c.sound.isEmpty

        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let playing = pads.isPlaying(slot)
            let prog = pads.progress(slot)
            let lit = playing || down

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.tint(Theme.pad(slot).opacity(empty ? 0.05 : (lit ? 0.7 : 0.28))).interactive(),
                                 in: .rect(cornerRadius: 22))

                if let p = prog, c.mode != .hold || playing {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .trim(from: 0, to: CGFloat(p))
                        .stroke(Theme.pad(slot), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(1.5)
                }

                if empty {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: c.mode.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .opacity(c.mode == .shot ? 0 : 0.8)
                        Text(store.name(c.sound))
                            .spaced(.caption, .bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }

                if pads.editing {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.gold.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .scaleEffect(down ? 0.94 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: down)
        }
        .contentShape(.rect(cornerRadius: 22))
        .modifier(PadTouch(editing: pads.editing, down: $down,
                           press: {
                               if empty { onEmpty() } else {
                                   Haptics.tap(.rigid, 0.9)
                                   pads.press(slot)
                               }
                           },
                           release: { pads.release(slot) },
                           edit: onEdit))
        .accessibilityLabel(empty ? "Pusty pad \(slot + 1)" : store.name(c.sound))
        .accessibilityAddTraits(.isButton)
    }
}

// Dotyk bez opoznienia: gra od razu przy dotknieciu, a przy "dopoki trzymasz" konczy po puszczeniu.
struct PadTouch: ViewModifier {
    let editing: Bool
    @Binding var down: Bool
    let press: () -> Void
    let release: () -> Void
    let edit: () -> Void

    func body(content: Content) -> some View {
        if editing {
            content.onTapGesture { edit() }
        } else {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            press()
                        }
                    }
                    .onEnded { _ in
                        down = false
                        release()
                    }
            )
        }
    }
}

// ------------------------------------------------------------------ edycja pada

struct PadEditor: View {
    let slot: Int
    @EnvironmentObject private var pads: PadsModel
    @EnvironmentObject private var store: SoundStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickSound = false

    private var g: Int { pads.global(slot) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dźwięk") {
                    HStack {
                        Text(store.name(pads.pads[g].sound)).spaced(.body, .semibold)
                        Spacer()
                        Button("Zmień") { pickSound = true }
                    }
                    Button {
                        pads.press(slot)
                    } label: {
                        Label("Posłuchaj", systemImage: "play.fill")
                    }
                    .disabled(pads.pads[g].sound.isEmpty)
                }

                Section("Jak gra") {
                    Picker("Tryb", selection: $pads.pads[g].mode) {
                        ForEach(PadMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Brzmienie") {
                    SliderRow(symbol: "speaker.wave.2.fill", title: "Głośność", value: $pads.pads[g].volume,
                              range: 0...1.2) { "\(Int($0 * 100))%" }
                    SliderRow(symbol: "tuningfork", title: "Wysokość", value: $pads.pads[g].pitch,
                              range: -12...12, step: 1) { String(format: "%+.0f st", $0) }
                }

                Section {
                    Button("Wyczyść pad", role: .destructive) {
                        pads.clear(slot)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Pad \(slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } }
            }
            .sheet(isPresented: $pickSound) {
                LibraryView(pick: { id in pads.assign(slot, sound: id) })
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
