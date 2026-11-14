import SwiftUI
import UniformTypeIdentifiers

// Podglad dzwiekow: z internetu (pobiera i gra) albo z telefonu.
@MainActor
final class PreviewModel: ObservableObject {
    @Published var loading: String?
    @Published var playing: String?
    @Published var error: String?

    private var cache: [String: SampleBuffer] = [:]
    var hub: AudioHub?

    func stop() {
        hub?.mixer.stop(tag: -1)
        playing = nil
    }

    func playLocal(_ id: String, _ buf: SampleBuffer?) {
        if playing == id { stop(); return }
        guard let buf else { return }
        hub?.mixer.play(buf, tag: -1, gain: 0.9)
        playing = id
        scheduleReset(buf.duration, id)
    }

    func playRemote(_ s: OVSound) async {
        if playing == s.id { stop(); return }
        guard let buf = await fetch(s) else { return }
        hub?.mixer.play(buf, tag: -1, gain: 0.9)
        playing = s.id
        scheduleReset(buf.duration, s.id)
    }

    func fetch(_ s: OVSound) async -> SampleBuffer? {
        if let b = cache[s.id] { return b }
        loading = s.id
        error = nil
        defer { loading = nil }
        do {
            let b = try await Openverse.download(s)
            cache[s.id] = b
            return b
        } catch {
            self.error = "Nie udało się pobrać tego dźwięku."
            return nil
        }
    }

    private func scheduleReset(_ sec: Double, _ id: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(sec + 0.1))
            if self?.playing == id { self?.playing = nil }
        }
    }
}

struct LibraryView: View {
    // gdy ustawione, wybor dzwieku konczy sie wywolaniem tej funkcji (np. przypisanie do pada)
    let pick: ((String) -> Void)?

    @EnvironmentObject private var store: SoundStore
    @EnvironmentObject private var hub: AudioHub
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = PreviewModel()

    @State private var tab = 1
    @State private var webMode = 0
    @State private var query = ""
    @State private var results: [OVSound] = []
    @State private var page = 1
    @State private var pages = 1
    @State private var total = 0
    @State private var searching = false
    @State private var searchError: String?
    @State private var effectsOnly = true
    @State private var toast: String?
    @State private var showRecorder = false
    @State private var showImporter = false
    @State private var renaming: SoundItem?
    @State private var newName = ""

    private static let quick = ["airhorn", "applause", "laugh", "explosion", "scream", "cat", "dog", "vinyl scratch",
                                "laser", "sci-fi", "door", "glass", "thunder", "bell", "cheer", "whistle"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Skąd", selection: $tab) {
                    Text("Moje dźwięki").tag(0)
                    Text("Internet").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if tab == 0 { mine } else { internet }
            }
            .background(Backdrop())
            .navigationTitle(pick == nil ? "Biblioteka" : "Wybierz dźwięk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zamknij") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showRecorder = true } label: { Label("Nagraj dźwięk", systemImage: "mic.fill") }
                        Button { showImporter = true } label: { Label("Importuj plik", systemImage: "folder.fill") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Toast(text: toast)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.bouncy, value: toast)
            .sheet(isPresented: $showRecorder) { RecorderSheet { id in finish(id) } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { r in
                if case .success(let url) = r { importFile(url) }
            }
            .alert("Zmień nazwę", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nazwa", text: $newName)
                Button("Zapisz") {
                    if let r = renaming { store.rename(r.id, to: newName) }
                    renaming = nil
                }
                Button("Anuluj", role: .cancel) { renaming = nil }
            }
        }
        .onAppear { preview.hub = hub }
        .onDisappear { preview.stop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // ---------------------------------------------------------- moje

    private var mine: some View {
        List {
            ForEach(store.all) { item in
                HStack(spacing: 12) {
                    let m = preview
                    Button {
                        m.playLocal(item.id, store.buffer(item.id))
                    } label: {
                        Image(systemName: m.playing == item.id ? "stop.fill" : "play.fill")
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).spaced(.body, .semibold).lineLimit(1)
                        Text(subtitle(item)).spaced(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let l = item.licenseLabel { licenseBadge(l) }
                    ShareLink(item: SoundFile(id: item.id, store: store), preview: SharePreview(item.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let pick {
                        pick(item.id)
                        dismiss()
                    }
                }
                .swipeActions(edge: .trailing) {
                    if !item.builtin {
                        Button(role: .destructive) { store.remove(item.id) } label: { Label("Usuń", systemImage: "trash") }
                        Button { renaming = item; newName = item.name } label: { Label("Nazwa", systemImage: "pencil") }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func subtitle(_ item: SoundItem) -> String {
        if item.builtin { return "Wbudowany" }
        var p = [String(format: "%.1f s", item.seconds)]
        if let c = item.creator, !c.isEmpty { p.append(c) }
        return p.joined(separator: " · ")
    }

    private func licenseBadge(_ text: String) -> some View {
        Text(text)
            .spaced(.caption2, .bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
    }

    // ---------------------------------------------------------- internet

    private var internet: some View {
        VStack(spacing: 8) {
            Picker("Internet", selection: $webMode) {
                Text("Soundboardy").tag(0)
                Text("Szukaj").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            if webMode == 0 { BoardsHome(pick: pick) } else { web }
        }
    }

    private var web: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Szukaj dźwięków (po angielsku)", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search(reset: true) } }
                if !query.isEmpty {
                    Button { query = ""; results = [] } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { effectsOnly.toggle(); if !query.isEmpty { Task { await search(reset: true) } } } label: {
                        Chip(text: "Tylko efekty", symbol: "bolt.fill", selected: effectsOnly)
                    }
                    .buttonStyle(.plain)
                    ForEach(Self.quick, id: \.self) { q in
                        Button { query = q; Task { await search(reset: true) } } label: { Chip(text: q) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            if results.isEmpty && !searching {
                VStack(spacing: 10) {
                    Image(systemName: searchError == nil ? "waveform.badge.magnifyingglass" : "wifi.exclamationmark")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(searchError ?? "Wpisz, czego szukasz, albo wybierz hasło. Dźwięki są z Openverse, na wolnych licencjach.")
                        .spaced(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(results) { s in row(s) }
                    if page < pages {
                        Button {
                            Task { await search(reset: false) }
                        } label: {
                            HStack { Spacer(); Text("Więcej wyników").spaced(.subheadline, .semibold); Spacer() }
                        }
                        .listRowBackground(Color.clear)
                    }
                    Text("Źródło: Openverse. Licencje Creative Commons (CC0 bez wymagań, CC BY wymaga podania autora). Autor i licencja zapisują się razem z dźwiękiem.")
                        .spaced(.caption2)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay { if searching && results.isEmpty { ProgressView() } }
            }
        }
    }

    private func row(_ s: OVSound) -> some View {
        let m = preview
        return HStack(spacing: 12) {
            Button {
                Task { await m.playRemote(s) }
            } label: {
                ZStack {
                    if m.loading == s.id {
                        ProgressView()
                    } else {
                        Image(systemName: m.playing == s.id ? "stop.fill" : "play.fill")
                    }
                }
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).spaced(.body, .semibold).lineLimit(1)
                Text([s.seconds > 0 ? String(format: "%.1f s", s.seconds) : nil, s.creator, s.source]
                    .compactMap { $0 }.joined(separator: " · "))
                    .spaced(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            licenseBadge(s.licenseLabel)
            Button {
                Task { await add(s) }
            } label: {
                Image(systemName: pick == nil ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.gold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pick == nil ? "Zapisz w Moich dźwiękach" : "Użyj tego dźwięku")
        }
        .listRowBackground(Color.clear)
    }

    private func search(reset: Bool) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if reset { page = 0; results = [] }
        searching = true
        searchError = nil
        defer { searching = false }
        do {
            let r = try await Openverse.search(q, page: page + 1, effectsOnly: effectsOnly)
            page += 1
            pages = r.pageCount
            total = r.resultCount
            let known = Set(results.map(\.id))
            results += r.results.filter { !known.contains($0.id) }
            if results.isEmpty { searchError = "Nic nie znaleziono. Spróbuj innego hasła albo wyłącz „Tylko efekty”." }
        } catch {
            searchError = "Nie udało się połączyć z internetem. Spróbuj jeszcze raz."
        }
    }

    private func add(_ s: OVSound) async {
        guard let buf = await preview.fetch(s) else {
            show("Nie udało się pobrać dźwięku")
            return
        }
        let item = store.add(buf, name: s.name, creator: s.creator, license: s.license,
                             licenseURL: s.licenseURL, sourceURL: s.landing)
        Haptics.ok()
        finish(item.id)
    }

    private func finish(_ id: String) {
        if let pick {
            pick(id)
            dismiss()
        } else {
            show("Zapisano w Moich dźwiękach")
        }
    }

    private func show(_ t: String) {
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == t { toast = nil }
        }
    }

    private func importFile(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let b = try Importer.load(url)
            let item = store.add(b, name: url.deletingPathExtension().lastPathComponent)
            Haptics.ok()
            finish(item.id)
        } catch {
            show("Tego pliku nie da się odczytać")
        }
    }
}

// ------------------------------------------------------------------ nagrywanie wlasnego dzwieku

struct RecorderSheet: View {
    let done: (String) -> Void

    @EnvironmentObject private var hub: AudioHub
    @EnvironmentObject private var store: SoundStore
    @Environment(\.dismiss) private var dismiss
    @State private var recording = false
    @State private var buffer: SampleBuffer?
    @State private var level: Float = 0
    @State private var seconds = 0.0
    @State private var name = ""
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Spacer()
                Button {
                    Task { await toggle() }
                } label: {
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 170, height: 170)
                        .glassEffect(.regular.tint(recording ? Color.red.opacity(0.55) : nil).interactive(), in: .circle)
                        .scaleEffect(recording ? 1 + CGFloat(level) * 0.12 : 1)
                        .animation(.spring(duration: 0.2), value: level)
                }
                .buttonStyle(.plain)

                Text(String(format: "%.1f s", seconds))
                    .spaced(.title, .bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(recording ? "Nagrywam, dotknij, żeby skończyć" : (buffer == nil ? "Dotknij, żeby nagrać (do 30 s)" : "Gotowe, nazwij i zapisz"))
                    .spaced(.subheadline)
                    .foregroundStyle(.secondary)

                if buffer != nil && !recording {
                    TextField("Nazwa", text: $name)
                        .padding(14)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.horizontal, 30)
                    HStack(spacing: 12) {
                        Button("Posłuchaj") {
                            if let b = buffer { hub.mixer.play(b, tag: -1) }
                        }
                        .buttonStyle(.glass)
                        Button("Zapisz") {
                            if let b = buffer {
                                let item = store.add(b, name: name.isEmpty ? "Nagranie" : name)
                                dismiss()
                                done(item.id)
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.gold)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Backdrop())
            .navigationTitle("Nagraj dźwięk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { cancel() } } }
            .onReceive(tick) { _ in
                guard recording else { return }
                seconds = hub.mixer.sampleRecordingSeconds
                level = min(1, hub.mixer.levels.mic * 6)
                if seconds >= 29.9 { stopNow() }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { hub.releaseMic("recorder") }
    }

    private func toggle() async {
        if recording {
            stopNow()
        } else {
            guard await hub.useMic("recorder") else { return }
            buffer = nil
            seconds = 0
            name = ""
            hub.mixer.startSampleRecording()
            recording = true
            Haptics.tap(.heavy)
        }
    }

    private func stopNow() {
        buffer = hub.mixer.stopSampleRecording()
        recording = false
        level = 0
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        name = "Nagranie " + f.string(from: Date())
        Haptics.ok()
    }

    private func cancel() {
        _ = hub.mixer.stopSampleRecording()
        dismiss()
    }
}
