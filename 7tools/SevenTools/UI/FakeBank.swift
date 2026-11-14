import SwiftUI

// Bank Kasztan: wymyslony bank-parodia. Nie jest prawdziwy i nie udaje zadnego prawdziwego banku ani sklepu.
// Na kazdym ekranie jest widoczny napis PARODIA, nie ma eksportu potwierdzen ani zrzutow "dla urzedu".

struct BankTx: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var emoji: String
    var amount: Double        // ujemne = wydatek
    var daysAgo: Int
    var note: String
}

@MainActor
final class BankModel: ObservableObject {
    @Published var owner: String { didSet { save() } }
    @Published var balance: Double { didSet { save() } }
    @Published var txs: [BankTx] { didSet { save() } }

    private static let key = "bank.parody"

    private struct Stored: Codable {
        var owner: String
        var balance: Double
        var txs: [BankTx]
    }

    static let defaults: [BankTx] = [
        BankTx(title: "Żaba", emoji: "🐸", amount: -12.40, daysAgo: 0, note: "Bułka i energetyk. Bułka jest zadowolona."),
        BankTx(title: "Biedronkowo", emoji: "🐞", amount: -87.15, daysAgo: 1, note: "Zakupy na tydzień, wystarczyły na dwa dni."),
        BankTx(title: "Kebab u Zbyszka", emoji: "🌯", amount: -29.00, daysAgo: 2, note: "Z ostrym. Nie żałujesz. Żałujesz."),
        BankTx(title: "Przelew od Mamy", emoji: "💌", amount: 100.00, daysAgo: 3, note: "„Kup coś zdrowego”. Kupiłeś kebab."),
        BankTx(title: "Stacja Benzynek", emoji: "⛽", amount: -210.50, daysAgo: 4, note: "Pełny bak. Pusty portfel."),
        BankTx(title: "Kawa u Kotka", emoji: "☕", amount: -16.00, daysAgo: 5, note: "Kot też dostał mleko."),
        BankTx(title: "Prąd SA", emoji: "💡", amount: -241.99, daysAgo: 8, note: "Prąd był. Teraz go nie ma. W portfelu."),
        BankTx(title: "Wypłata (żart)", emoji: "💸", amount: 4999.00, daysAgo: 10, note: "To parodia. Takie pieniądze są tylko tutaj."),
    ]

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Stored.self, from: d) {
            owner = s.owner; balance = s.balance; txs = s.txs
        } else {
            owner = "Jan Kowalski"
            balance = 1234.56
            txs = Self.defaults
        }
    }

    private func save() {
        let s = Stored(owner: owner, balance: balance, txs: txs)
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func reset() {
        owner = "Jan Kowalski"
        balance = 1234.56
        txs = Self.defaults
    }

    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "pl_PL")
        return (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) + " zł"
    }
}

struct FakeBank: View {
    @StateObject private var bank = BankModel()
    @State private var showEdit = false
    @State private var showTransfer = false
    @State private var detail: BankTx?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.05), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ribbon
                    header
                    actions
                    transactions
                }
                .padding(.horizontal, 16)
                .padding(.top, 50)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)

            // znak wodny na calym ekranie, widoczny tez na zrzucie
            VStack(spacing: 120) {
                ForEach(0..<4, id: \.self) { _ in
                    Text("PARODIA").font(.system(size: 64, weight: .black)).tracking(8)
                        .foregroundStyle(.white.opacity(0.07)).rotationEffect(.degrees(-24))
                }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showEdit) { BankEditor(bank: bank) }
        .sheet(isPresented: $showTransfer) { BankTransfer(bank: bank) }
        .sheet(item: $detail) { t in
            VStack(spacing: 14) {
                Text(t.emoji).font(.system(size: 70))
                Text(t.title).spaced(.title2, .bold)
                Text(BankModel.money(t.amount)).font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(t.amount < 0 ? Color.red : Color.green)
                Text(t.note).spaced(.body).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("Parodia. To nie jest prawdziwa transakcja.").spaced(.footnote).foregroundStyle(Theme.gold)
            }
            .padding(30).presentationDetents([.medium])
        }
    }

    private var ribbon: some View {
        HStack(spacing: 8) {
            Image(systemName: "theatermasks.fill")
            Text("PARODIA. To nie jest prawdziwy bank ani prawdziwe pieniądze.").spaced(.caption, .bold)
        }
        .padding(10).frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(Color.yellow.opacity(0.35)), in: .rect(cornerRadius: 14))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Bank Kasztan").spaced(.headline, .bold).foregroundStyle(Theme.gold)
            Text(bank.owner).spaced(.title3, .semibold)
            Text(BankModel.money(bank.balance))
                .font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText(value: bank.balance))
            Text("Dostępne środki (niepoważne)").spaced(.footnote).foregroundStyle(.secondary)
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                button("Przelew", "arrow.up.right") { showTransfer = true }
                button("Edytuj", "pencil") { showEdit = true }
            }
        }
    }

    private func button(_ t: String, _ symbol: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: symbol).spaced(.subheadline, .bold).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .glassEffect(.regular.tint(Theme.gold.opacity(0.35)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var transactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ostatnie transakcje").spaced(.headline, .bold)
            ForEach(bank.txs) { t in
                Button { detail = t; Haptics.tap(.light) } label: {
                    HStack(spacing: 12) {
                        Text(t.emoji).font(.system(size: 26)).frame(width: 46, height: 46)
                            .glassEffect(.regular, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).spaced(.subheadline, .bold)
                            Text(t.daysAgo == 0 ? "dziś" : "\(t.daysAgo) dn. temu").spaced(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(BankModel.money(t.amount)).spaced(.subheadline, .bold).monospacedDigit()
                            .foregroundStyle(t.amount < 0 ? Color.white : Color.green)
                    }
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Edycja jest jawna: imie, kwota i lista transakcji. Wszystko tylko w tej parodii.
struct BankEditor: View {
    @ObservedObject var bank: BankModel
    @Environment(\.dismiss) private var dismiss
    @State private var balanceText = ""
    @State private var adding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Właściciel i saldo") {
                    TextField("Imię i nazwisko", text: $bank.owner)
                    TextField("Saldo", text: $balanceText).keyboardType(.decimalPad)
                        .onChange(of: balanceText) { _, t in
                            if let v = Double(t.replacingOccurrences(of: ",", with: ".")) { bank.balance = v }
                        }
                }
                Section("Transakcje") {
                    ForEach($bank.txs) { $t in
                        VStack(alignment: .leading) {
                            HStack {
                                TextField("Emoji", text: $t.emoji).frame(width: 44)
                                TextField("Nazwa", text: $t.title)
                            }
                            HStack {
                                Text("Kwota")
                                TextField("0", value: $t.amount, format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .onDelete { bank.txs.remove(atOffsets: $0) }
                    Button("Dodaj transakcję") {
                        bank.txs.insert(BankTx(title: "Nowa pozycja", emoji: "🧾", amount: -10, daysAgo: 0, note: "Dopisane ręcznie, w parodii."), at: 0)
                    }
                }
                Section {
                    Button("Przywróć domyślne", role: .destructive) { bank.reset(); balanceText = String(bank.balance) }
                } footer: {
                    Text("To parodia. Wszystko, co tu wpiszesz, zostaje w telefonie i jest oznaczone napisem PARODIA.")
                }
            }
            .navigationTitle("Edycja parodii")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
            .onAppear { balanceText = String(bank.balance) }
        }
    }
}

struct BankTransfer: View {
    @ObservedObject var bank: BankModel
    @Environment(\.dismiss) private var dismiss
    @State private var to = "Mama"
    @State private var amountText = "10"
    @State private var title = "Na bułkę"
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Przelew (parodia)") {
                    TextField("Dla kogo", text: $to)
                    TextField("Kwota", text: $amountText).keyboardType(.decimalPad)
                    TextField("Tytuł", text: $title)
                }
                if sent {
                    Section { Label("Wysłano. Naprawdę nie. To parodia.", systemImage: "theatermasks.fill").foregroundStyle(Theme.gold) }
                }
            }
            .navigationTitle("Nowy przelew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zamknij") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Wyślij") {
                        guard let v = Double(amountText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
                        bank.balance -= v
                        bank.txs.insert(BankTx(title: "Przelew: \(to)", emoji: "📤", amount: -v, daysAgo: 0, note: title + " (parodia)"), at: 0)
                        sent = true
                        Haptics.ok()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
