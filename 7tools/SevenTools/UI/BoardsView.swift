import SwiftUI

// Lista soundboardow (kolekcji z numerowanymi padami)
struct BoardsHome: View {
    let pick: ((String) -> Void)?
    @EnvironmentObject private var boards: BoardsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Soundboardy").spaced(.title2, .bold)
                Text("Prawdziwe nagrania, każde z numerem. Dotknij pada, żeby zagrać. Dźwięk pobiera się za pierwszym razem.")
                    .spaced(.footnote).foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(boards.catalog.boards) { b in
                        NavigationLink {
                            BoardView(board: b, pick: pick)
                        } label: {
                            VStack(spacing: 6) {
                                Text(b.emoji).font(.system(size: 40))
                                Text(b.title).spaced(.headline, .bold).lineLimit(1).minimumScaleFactor(0.7)
                                Text("\(b.sounds.count) dźwięków").spaced(.caption).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if boards.catalog.boards.isEmpty {
                    Text("Brak katalogu soundboardów. Połącz się z internetem i otwórz ten ekran jeszcze raz.")
                        .spaced(.subheadline).foregroundStyle(.secondary)
                }

                Text("Źródło: Openverse (głównie Freesound). Licencje: CC0, CC BY, CC BY-SA albo domena publiczna. Autor i licencja są przy każdym dźwięku.")
                    .spaced(.caption2).foregroundStyle(.secondary).padding(.top, 6)
            }
            .padding(16)
        }
        .task { await boards.refreshCatalog() }
    }
}

struct BoardView: View {
    let board: Board
    let pick: ((String) -> Void)?

    @EnvironmentObject private var boards: BoardsModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BoardSound?
    @State private var busy = false
    @State private var toast: String?

    private var cached: Int { board.sounds.filter { boards.isCached($0) }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Text(board.emoji).font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(board.title).spaced(.title2, .bold)
                        Text("\(board.sounds.count) dźwięków, pobrane: \(cached)").spaced(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(board.sounds) { s in
                        pad(s)
                    }
                }

                if let s = selected { detail(s).transition(.move(edge: .bottom).combined(with: .opacity)) }

                actions
            }
            .padding(16)
        }
        .background(Backdrop())
        .navigationTitle(board.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.bouncy(duration: 0.45), value: selected)
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(text: toast).padding(.bottom, 14).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.bouncy, value: toast)
    }

    private func pad(_ s: BoardSound) -> some View {
        let st = boards.stateOf(s)
        let isSel = selected == s
        return Button {
            selected = s
            Haptics.tap(.rigid, 0.9)
            Task { await boards.play(s) }
        } label: {
            ZStack {
                VStack(spacing: 3) {
                    Text("\(s.n)").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(s.title).spaced(.caption2, .semibold).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .padding(4)

                VStack {
                    HStack {
                        Spacer()
                        switch st {
                        case .loading: ProgressView().controlSize(.mini)
                        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        case .idle: Image(systemName: "icloud.and.arrow.down").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        case .ready: EmptyView()
                        }
                    }
                    Spacer()
                }
                .padding(7)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .glassEffect(.regular.tint(Theme.pad(s.n - 1).opacity(isSel ? 0.7 : 0.3)).interactive(), in: .rect(cornerRadius: 20))
            .overlay {
                if isSel {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.gold, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.n). \(s.title)")
    }

    private func detail(_ s: BoardSound) -> some View {
        let st = boards.stateOf(s)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(s.n). \(s.title)").spaced(.headline, .bold)
                    Spacer()
                    Text(s.licenseLabel).spaced(.caption2, .bold).padding(.horizontal, 8).padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }
                if let o = s.original, !o.isEmpty {
                    Text("Nagranie: \(o)").spaced(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if let c = s.creator, !c.isEmpty { Text("Autor: \(c)").spaced(.footnote).foregroundStyle(.secondary) }
                if case .failed(let why) = st {
                    Text("Nie udało się pobrać (\(why)).").spaced(.footnote, .semibold).foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button { Task { await boards.play(s) } } label: { Chip(text: "Zagraj", symbol: "play.fill") }.buttonStyle(.plain)
                    Button {
                        Task {
                            if await boards.adopt(s) != nil { show("Zapisano w Moich dźwiękach") } else { show("Nie udało się pobrać") }
                        }
                    } label: { Chip(text: "Zapisz", symbol: "square.and.arrow.down") }.buttonStyle(.plain)
                    if let pick {
                        Button {
                            Task {
                                if let id = await boards.adopt(s) {
                                    Haptics.ok()
                                    pick(id)
                                    dismiss()
                                } else { show("Nie udało się pobrać") }
                            }
                        } label: { Chip(text: "Użyj", symbol: "checkmark", selected: true) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                busy = true
                Task { await boards.downloadAll(board); busy = false; show("Pobrano cały soundboard") }
            } label: {
                HStack {
                    if busy { ProgressView() }
                    Label(busy ? "Pobieram…" : "Pobierz wszystkie", systemImage: "icloud.and.arrow.down.fill")
                }
                .spaced(.subheadline, .bold).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain).disabled(busy)

            Menu {
                Button("Na pady banku A") { Task { await useBank(0) } }
                Button("Na pady banku B") { Task { await useBank(1) } }
            } label: {
                Label("Użyj jako bank padów", systemImage: "square.grid.3x3.fill")
                    .spaced(.subheadline, .bold).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .glassEffect(.regular.tint(Theme.gold).interactive(), in: .capsule)
            }
        }
    }

    private func useBank(_ bank: Int) async {
        busy = true
        let n = await boards.useAsBank(board, bank: bank)
        busy = false
        Haptics.ok()
        show("Wstawiono \(n) dźwięków do banku \(bank == 0 ? "A" : "B")")
    }

    private func show(_ t: String) {
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == t { toast = nil }
        }
    }
}

// Pasek na stronie Pady: pobieranie prawdziwych dzwiekow na start
struct StarterBanner: View {
    @EnvironmentObject private var boards: BoardsModel

    var body: some View {
        Group {
            if let p = boards.starterProgress {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pobieram prawdziwe dźwięki").spaced(.subheadline, .bold)
                        Text("\(p.done) z \(p.total)").spaced(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                }
                .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 22))
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let e = boards.starterError {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 22)).foregroundStyle(.orange)
                    Text(e).spaced(.footnote, .semibold)
                    Spacer(minLength: 4)
                    Button("Ponów") { Task { await boards.installStarter() } }.buttonStyle(.glass)
                }
                .padding(14).glassEffect(.regular.tint(Color.orange.opacity(0.2)), in: .rect(cornerRadius: 22))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.bouncy(duration: 0.5), value: boards.starterProgress?.done)
        .animation(.bouncy(duration: 0.5), value: boards.starterError)
    }
}
