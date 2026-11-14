import SwiftUI

// Falszywy system: wyglada prawie jak prawdziwy, ale wszystko w nim jest zartem.
// Nie ma pol na hasla ani konto, nic nie wychodzi z telefonu.

enum FakeApp: String, CaseIterable, Identifiable {
    case calendar, photos, camera, weather, clock, maps, notes, reminders, files, health, music, calc, compass, store
    case phone, safari, messages, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Kalendarz"
        case .photos: return "Zdjęcia"
        case .camera: return "Aparat"
        case .weather: return "Pogoda"
        case .clock: return "Zegar"
        case .maps: return "Mapy"
        case .notes: return "Notatki"
        case .reminders: return "Przypomnienia"
        case .files: return "Pliki"
        case .health: return "Zdrowie"
        case .music: return "Muzyka"
        case .calc: return "Kalkulator"
        case .compass: return "Kompas"
        case .store: return "Sklep"
        case .phone: return "Telefon"
        case .safari: return "Safari"
        case .messages: return "Wiadomości"
        case .settings: return "Ustawienia"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .photos: return "photo.fill"
        case .camera: return "camera.fill"
        case .weather: return "cloud.sun.fill"
        case .clock: return "clock.fill"
        case .maps: return "map.fill"
        case .notes: return "note.text"
        case .reminders: return "checklist"
        case .files: return "folder.fill"
        case .health: return "heart.fill"
        case .music: return "music.note"
        case .calc: return "plusminus.circle.fill"
        case .compass: return "location.north.circle.fill"
        case .store: return "bag.fill"
        case .phone: return "phone.fill"
        case .safari: return "safari.fill"
        case .messages: return "message.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .calendar: return .red
        case .photos: return .pink
        case .camera: return .gray
        case .weather: return .cyan
        case .clock: return .black
        case .maps: return .green
        case .notes: return .yellow
        case .reminders: return .orange
        case .files: return .blue
        case .health: return .red
        case .music: return .pink
        case .calc: return .orange
        case .compass: return .gray
        case .store: return .blue
        case .phone: return .green
        case .safari: return .blue
        case .messages: return .green
        case .settings: return .gray
        }
    }

    static let grid: [FakeApp] = [.calendar, .photos, .camera, .weather, .clock, .maps, .notes, .reminders,
                                  .files, .health, .music, .calc, .compass, .store]
    static let dock: [FakeApp] = [.phone, .safari, .messages, .settings]
}

// Co pokazuje falszywy system o telefonie. Mozna to zmienic przed startem psikusa albo w Ogolne > Informacje.
enum FakeDeviceInfo {
    static let models = ["iPhone 17 Pro Max", "iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone 15 Pro", "iPhone 14", "iPhone 13 mini",
                         "iPhone 12", "iPhone 11", "iPhone X", "iPhone SE (2. generacji)", "iPhone 8", "iPhone 6s", "iPhone 4",
                         "iPhone 99 Ultra Mega Pro"]
    static let versions = ["26.1", "26.0", "18.7", "17.6", "16.7", "15.8", "14.8", "13.7", "12.5", "9.3.5", "7.1", "99.9"]
    static let capacities = ["16 GB", "64 GB", "128 GB", "256 GB", "512 GB", "1 TB", "1 PB"]
    static let wallpapers: [(String, [Color])] = [
        ("Zachód", [Color(red: 0.1, green: 0.3, blue: 0.7), Color(red: 0.5, green: 0.2, blue: 0.6), Color(red: 0.9, green: 0.4, blue: 0.3)]),
        ("Noc", [Color(red: 0.02, green: 0.02, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.3)]),
        ("Las", [Color(red: 0.05, green: 0.3, blue: 0.2), Color(red: 0.0, green: 0.15, blue: 0.1)]),
        ("Cukierek", [Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 0.4, green: 0.7, blue: 1.0)]),
    ]

    static func next(after v: String) -> String {
        let parts = v.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return "99.9" }
        return "\(parts[0]).\(parts[1] + 1)"
    }
}

struct FakeOSOptions: View {
    @AppStorage("fake.model") private var model = "iPhone 17 Pro Max"
    @AppStorage("fake.ios") private var ios = "26.1"
    @AppStorage("fake.name") private var name = "iPhone"
    @AppStorage("fake.capacity") private var capacity = "256 GB"
    @AppStorage("fake.battery") private var battery = 73.0
    @AppStorage("fake.wall") private var wall = 0
    @AppStorage("fake.timeOn") private var timeOn = false
    @AppStorage("fake.time") private var time = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jaki to telefon").spaced(.subheadline, .bold)
            Picker("Model", selection: $model) { ForEach(FakeDeviceInfo.models, id: \.self) { Text($0).tag($0) } }
            Picker("Wersja iOS", selection: $ios) { ForEach(FakeDeviceInfo.versions, id: \.self) { Text("iOS \($0)").tag($0) } }
            Picker("Pojemność", selection: $capacity) { ForEach(FakeDeviceInfo.capacities, id: \.self) { Text($0).tag($0) } }
            TextField("Nazwa telefonu", text: $name).padding(8).glassEffect(.regular, in: .capsule)
            SliderRow(symbol: "battery.50percent", title: "Bateria", value: $battery, range: 1...100, step: 1) { "\(Int($0))%" }
            Picker("Tapeta", selection: $wall) { ForEach(0..<FakeDeviceInfo.wallpapers.count, id: \.self) { Text(FakeDeviceInfo.wallpapers[$0].0).tag($0) } }
            Toggle("Własna godzina na pasku", isOn: $timeOn)
            if timeOn {
                DatePicker("Godzina", selection: Binding(get: { Date(timeIntervalSince1970: time) }, set: { time = $0.timeIntervalSince1970 }),
                           displayedComponents: .hourAndMinute)
            }
        }
    }
}

// Ogolne > Informacje: model, wersja i reszta do zmiany dotknieciem
struct FakeAbout: View {
    @AppStorage("fake.model") private var model = "iPhone 17 Pro Max"
    @AppStorage("fake.ios") private var ios = "26.1"
    @AppStorage("fake.name") private var name = "iPhone"
    @AppStorage("fake.capacity") private var capacity = "256 GB"

    var body: some View {
        List {
            HStack { Text("Nazwa"); Spacer(); TextField("Nazwa", text: $name).multilineTextAlignment(.trailing).foregroundStyle(.secondary) }
            Picker("Wersja iOS", selection: $ios) { ForEach(FakeDeviceInfo.versions, id: \.self) { Text($0).tag($0) } }
            Picker("Nazwa modelu", selection: $model) { ForEach(FakeDeviceInfo.models, id: \.self) { Text($0).tag($0) } }
            Picker("Pojemność", selection: $capacity) { ForEach(FakeDeviceInfo.capacities, id: \.self) { Text($0).tag($0) } }
            HStack { Text("Numer seryjny"); Spacer(); Text("F2LXJ4KP7Q").foregroundStyle(.secondary) }
            HStack { Text("Gwarancja"); Spacer(); Text("Skończyła się wczoraj").foregroundStyle(.secondary) }
            Text("To jest żart. Dotknij pola, żeby zmienić model, wersję i resztę.").spaced(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Informacje")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FakeOSHome: View {
    @AppStorage("fake.battery") private var battery = 73.0
    @AppStorage("fake.wall") private var wall = 0
    @AppStorage("fake.timeOn") private var timeOn = false
    @AppStorage("fake.time") private var customTime = 0.0
    @State private var open: FakeApp?
    @State private var page = 0
    @State private var hint = false

    var body: some View {
        ZStack {
            LinearGradient(colors: FakeDeviceInfo.wallpapers[min(max(wall, 0), FakeDeviceInfo.wallpapers.count - 1)].1,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack {
                    Text((timeOn ? Date(timeIntervalSince1970: customTime) : Date.now).formatted(date: .omitted, time: .shortened)).spaced(.footnote, .bold)
                    Spacer()
                    Image(systemName: "wifi")
                    Text("\(Int(battery))%").spaced(.caption2, .bold)
                    Image(systemName: battery > 75 ? "battery.100percent" : (battery > 40 ? "battery.50percent" : "battery.25percent"))
                }
                .padding(.horizontal, 30).padding(.top, 14)

                // widzet
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide))).spaced(.caption, .bold).foregroundStyle(.red)
                    Text(Date.now.formatted(.dateTime.day())).font(.system(size: 40, weight: .light))
                    Text("Brak wydarzeń. Jak zawsze.").spaced(.caption).foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal, 18).padding(.top, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 20) {
                    ForEach(FakeApp.grid) { a in icon(a) }
                }
                .padding(.horizontal, 18).padding(.top, 20)

                Spacer()
                HStack(spacing: 6) { ForEach(0..<2, id: \.self) { Circle().fill(.white.opacity($0 == page ? 0.9 : 0.35)).frame(width: 7, height: 7) } }
                    .padding(.bottom, 10)
                HStack(spacing: 16) {
                    ForEach(FakeApp.dock) { a in icon(a, label: false) }
                }
                .padding(14).frame(maxWidth: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: 34))
                .padding(.horizontal, 14).padding(.bottom, 16)
            }
            .foregroundStyle(.white)
        }
        .fullScreenCover(item: $open) { a in FakeAppScreen(app: a) }
    }

    private func icon(_ a: FakeApp, label: Bool = true) -> some View {
        Button { open = a; Haptics.tap(.light, 0.6) } label: {
            VStack(spacing: 5) {
                Image(systemName: a.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(a.color.gradient, in: .rect(cornerRadius: 15, style: .continuous))
                if label { Text(a.title).spaced(.caption2, .medium).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct FakeAppScreen: View {
    let app: FakeApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if app != .settings {
                    HStack {
                        Text(app.title).spaced(.headline, .bold)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 50).padding(.bottom, 8)
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "house.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.trailing, 14).padding(.top, 44)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch app {
        case .settings: FakeSettings()
        case .safari: EvilSafari()
        case .messages: EvilMessages()
        case .camera: EvilCamera()
        case .calc: EvilCalc()
        case .phone: FakePhone()
        case .weather: FakeWeather()
        case .clock: FakeClock()
        case .compass: FakeCompass()
        case .reminders: FakeReminders()
        case .files: FakeFiles()
        case .music: FakeMusic()
        case .calendar: EvilCards(items: [("📅", "Dziś", "Nic. Ani nic. Dużo niczego"), ("🗓️", "Jutro", "Prawdopodobnie też nic"),
                                         ("💸", "Wypłata", "Nigdy (według kalendarza)"), ("🎂", "Urodziny kota", "Każdego dnia, bo kot tak twierdzi")])
        case .photos: EvilCards(items: [("😾", "Twoje najgorsze zdjęcie", "Zrobione w 2019, nadal boli"), ("🐈", "Kot, który cię ocenia", "Ocena: 2/10"),
                                       ("🍕", "Pizza, której nie zjadłeś", "Wspomnienie pizzy to zdrada"), ("🤳", "Selfie z palcem na obiektywie", "Klasyk")])
        case .maps: EvilCards(items: [("📍", "Jesteś tutaj", "Dokładność: aż za duża"), ("🏠", "Do domu: 0 m", "Jesteś w domu? Sprawdź jeszcze raz"),
                                     ("🧭", "Trasa do lodówki", "Najkrótsza: 4 kroki, najszybsza: nie wstawaj")])
        case .notes: EvilCards(items: [("📝", "Lista zakupów", "Mleko. Chleb. Plan zemsty"), ("💡", "Genialny pomysł", "Zapomniałem"), ("📌", "Pamiętać", "O czym?")])
        case .health: EvilCards(items: [("👣", "0 kroków dzisiaj", "Kanapa jest dumna"), ("😴", "Sen: 3 godz.", "Reszta to scrollowanie"), ("🥤", "Woda: 0 szklanek", "Kawa się nie liczy. A szkoda")])
        case .store: EvilCards(items: [("📱", "Nowy telefon: 99 999 zł", "Rata: nerka na miesiąc (żart)"), ("🎧", "Słuchawki: 1 zł", "Tylko jedna. Lewa"), ("🔌", "Ładowarka: 400 zł", "Kabel osobno. Wtyczka osobno. Prąd osobno")])
        }
    }
}

// ------------------------------------------------------------------ Ustawienia

struct SetRow: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let title: String
    var value = ""
    var detail: [(String, String)] = []
    var note = ""
    var update = false
    var about = false
}

struct FakeSettings: View {
    @State private var showUpdate = false

    private static let g0: [SetRow] = [SetRow(symbol: "person.fill", color: .gray, title: "Twoje imię", value: "Konto zablokowane przez kota",
                detail: [("Imię", "Ty"), ("Subskrypcje", "Wszystkie"), ("Kosz", "Pełny"), ("Ostatnia kopia", "Przed Twoim urodzeniem")],
                note: "To tylko żart. Żadne konto nie jest tu używane.")]

    private static let g1: [SetRow] = [SetRow(symbol: "airplane", color: .orange, title: "Tryb samolotowy", value: "off",
                note: "Samolot odleciał bez ciebie."),
         SetRow(symbol: "wifi", color: .blue, title: "Wi-Fi", value: "Sąsiad_5G",
                detail: [("Sąsiad_5G", "Silny. Nie dla ciebie"), ("TP-Link_4A7F", "Słaby, jak twoja wymówka"), ("Nie_Podłączaj_Się", "Bardzo silny"), ("Lodówka-Guest", "Otwarta (ostrzeżenie)")],
                note: "Żadne hasło nie jest tu potrzebne ani zapisywane."),
         SetRow(symbol: "dot.radiowaves.left.and.right", color: .blue, title: "Bluetooth", value: "Lodówka",
                detail: [("Lodówka", "Połączona"), ("Czajnik", "Niedostępny"), ("Słuchawki sąsiada", "Zajęte")]),
         SetRow(symbol: "antenna.radiowaves.left.and.right", color: .green, title: "Sieć komórkowa", value: "5 patyczków",
                detail: [("Zasięg", "Jest, ale nie tam gdzie trzeba"), ("Dane", "Nieograniczone do 100 MB"), ("Roaming", "Zabroniony przez mamę")])]

    private static let g2: [SetRow] = [SetRow(symbol: "bell.badge.fill", color: .red, title: "Powiadomienia", value: "2 137",
                detail: [("Nowe", "2 137"), ("Ważne", "0"), ("Od mamy", "14")]),
         SetRow(symbol: "speaker.wave.3.fill", color: .pink, title: "Dźwięki i haptyka", value: "Głośno",
                detail: [("Dzwonek", "Syrena alarmowa"), ("Wibracje", "Trzęsienie ziemi"), ("Cisza", "Niedostępna")]),
         SetRow(symbol: "moon.fill", color: .indigo, title: "Skupienie", value: "Nie dziś",
                detail: [("Praca", "Wyłączone z urzędu"), ("Sen", "Planowany na 2031"), ("Gry", "Zawsze włączone")]),
         SetRow(symbol: "hourglass", color: .indigo, title: "Czas przed ekranem", value: "23 godz. 59 min",
                detail: [("Dziś", "23 godz. 59 min"), ("Najczęściej", "Ten ekran"), ("Limit", "Tak, ale go zignorowałeś")])]

    private static let g3: [SetRow] = [SetRow(symbol: "gearshape.fill", color: .gray, title: "Ogólne", value: "", about: true),
         SetRow(symbol: "arrow.down.circle.fill", color: .blue, title: "Aktualizacja oprogramowania", value: "1", update: true),
         SetRow(symbol: "battery.100percent", color: .green, title: "Bateria", value: "3%",
                detail: [("Stan baterii", "3% (z 100%)"), ("Ładowanie", "Nadzieją"), ("Zużycie", "Ten ekran: 100%")]),
         SetRow(symbol: "hand.raised.fill", color: .blue, title: "Prywatność i ochrona", value: "Wszystko widoczne",
                detail: [("Lokalizacja", "Znana mamie"), ("Mikrofon", "Słucha. Nudzi się"), ("Aparat", "Ocenia cię")]),
         SetRow(symbol: "textformat.size", color: .blue, title: "Ekran i jasność", value: "Jak mi się podoba",
                detail: [("Jasność", "Sama zmienia się co minutę"), ("Tryb ciemny", "Zawsze, bo smutek"), ("Rozmiar tekstu", "Za mały")])]

    private static let g4: [SetRow] = [SetRow(symbol: "trash.fill", color: .red, title: "Zresetuj", value: "",
                detail: [("Zresetuj ustawienia sieciowe", "Już zresetowane"), ("Wymaż całą zawartość", "Niee, dziękuję")],
                note: "Nic tu nie kasuje niczego.")]

    private let sections: [[SetRow]] = [Self.g0, Self.g1, Self.g2, Self.g3, Self.g4]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ustawienia").font(.system(size: 34, weight: .bold)).listRowBackground(Color.clear)
                }
                ForEach(sections.indices, id: \.self) { si in
                    Section {
                        ForEach(sections[si]) { r in
                            if r.update {
                                Button { showUpdate = true } label: { rowLabel(r) }.buttonStyle(.plain)
                            } else if r.about {
                                NavigationLink { FakeAbout() } label: { rowLabel(r) }
                            } else if r.value == "off" || r.value == "on" {
                                ToggleRow(row: r)
                            } else {
                                NavigationLink { SetDetail(row: r) } label: { rowLabel(r) }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showUpdate) { UpdateOffer() }
    }

    private func rowLabel(_ r: SetRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(r.color.gradient, in: .rect(cornerRadius: 7, style: .continuous))
            Text(r.title).spaced(.body, .regular)
            Spacer(minLength: 6)
            if r.update {
                Text(r.value).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Color.red, in: .circle)
            } else if !r.value.isEmpty {
                Text(r.value).spaced(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // przelacznik, ktory sam wraca i narzeka
    private struct ToggleRow: View {
        let row: SetRow
        @State private var on = false
        @State private var banner = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $on) {
                    HStack(spacing: 12) {
                        Image(systemName: row.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(row.color.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                        Text(row.title)
                    }
                }
                if !banner.isEmpty { Text(banner).spaced(.footnote).foregroundStyle(.red).transition(.opacity) }
            }
            .onChange(of: on) { _, now in
                guard now else { return }
                Task {
                    try? await Task.sleep(for: .seconds(0.7))
                    withAnimation { on = false; banner = row.note }
                    Haptics.tap(.medium)
                }
            }
        }
    }

    private struct SetDetail: View {
        let row: SetRow
        @State private var msg = ""

        var body: some View {
            List {
                ForEach(row.detail.indices, id: \.self) { i in
                    HStack {
                        Text(row.detail[i].0)
                        Spacer(minLength: 10)
                        Text(row.detail[i].1).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { msg = "Nie da się. Spróbuj jutro."; Haptics.tap(.soft) }
                }
                if !row.note.isEmpty { Text(row.note).spaced(.footnote).foregroundStyle(.secondary) }
                if !msg.isEmpty { Text(msg).spaced(.footnote, .semibold).foregroundStyle(.red) }
            }
            .navigationTitle(row.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct UpdateOffer: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fake.ios") private var ios = "26.1"
    @State private var install = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if install {
                FakeUpdate()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 60)).foregroundStyle(.blue)
                    Text("iOS \(FakeDeviceInfo.next(after: ios))").font(.system(size: 28, weight: .bold))
                    Text("Rozmiar: 128 GB. Nowości: nic nie działa, ale ładnie. Błędy zostały dodane celowo.")
                        .spaced(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Pobierz i zainstaluj") { install = true }.buttonStyle(.glassProminent).tint(.blue)
                    Button("Później") { dismiss() }.buttonStyle(.glass)
                }
                .padding(30)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// ------------------------------------------------------------------ male apki

struct FakePhone: View {
    @State private var number = ""
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(number.isEmpty ? " " : number).font(.system(size: 36, weight: .light)).frame(height: 44)
            if !msg.isEmpty { Text(msg).spaced(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).transition(.opacity) }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 16), count: 3), spacing: 14) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"], id: \.self) { k in
                    Button { number.append(k); Haptics.tap(.light) } label: {
                        Text(k).font(.system(size: 30, weight: .regular)).frame(width: 78, height: 78)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 30) {
                Color.clear.frame(width: 70, height: 70)
                Button {
                    guard !number.isEmpty else { return }
                    withAnimation { msg = "Wybieranie…" }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { msg = ["Abonent jest zajęty życiem.", "Numer nie istnieje, ale ty też nie.", "Zostaw wiadomość po sygnale. Sygnału nie będzie."].randomElement() ?? "" }
                    }
                } label: {
                    Image(systemName: "phone.fill").font(.system(size: 28)).foregroundStyle(.white).frame(width: 70, height: 70)
                        .glassEffect(.regular.tint(Color.green.opacity(0.85)).interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                Button { _ = number.popLast() } label: {
                    Image(systemName: "delete.left.fill").font(.system(size: 22)).frame(width: 70, height: 70)
                }
                .buttonStyle(.plain)
            }
            Spacer().frame(height: 30)
        }
    }
}

struct FakeWeather: View {
    private let days = [("Dziś", "☀️", "21°", "przelotny pech"), ("Jutro", "🌧️", "14°", "deszcz wymówek"), ("Śr", "⛈️", "9°", "burza w szklance"),
                        ("Czw", "🌪️", "30°", "tornado u sąsiada"), ("Pt", "❄️", "-2°", "śnieg w sierpniu"), ("Sob", "🌈", "18°", "tęcza na kredyt"), ("Nd", "☁️", "17°", "chmura. Jedna")]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Twoje miasto").spaced(.title2, .semibold)
                Text("21°").font(.system(size: 92, weight: .thin))
                Text("Przeważnie słonecznie, miejscami absurd").spaced(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(days.indices, id: \.self) { i in
                        HStack {
                            Text(days[i].0).frame(width: 60, alignment: .leading)
                            Text(days[i].1)
                            Spacer()
                            Text(days[i].3).spaced(.caption).foregroundStyle(.secondary)
                            Text(days[i].2).frame(width: 50, alignment: .trailing)
                        }
                        .padding(14)
                        if i < days.count - 1 { Divider() }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.top, 14)
            }
            .padding(16)
        }
    }
}

struct FakeClock: View {
    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(tl.date.formatted(.dateTime.hour().minute().second())).font(.system(size: 62, weight: .thin, design: .rounded)).monospacedDigit()
            }
            .padding(.top, 20)
            VStack(spacing: 0) {
                row("Tokio", "tego samego dnia, ale bardziej")
                Divider()
                row("Londyn", "wczoraj, prawie")
                Divider()
                row("Twoja lodówka", "zawsze 3:00 w nocy")
                Divider()
                row("Alarm: Wstawaj", "za późno")
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 24)).padding(.horizontal, 16)
            Spacer()
        }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack { Text(a).spaced(.body, .semibold); Spacer(); Text(b).spaced(.footnote).foregroundStyle(.secondary) }.padding(14)
    }
}

struct FakeCompass: View {
    @State private var angle = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2).frame(width: 260, height: 260)
                Image(systemName: "location.north.fill").font(.system(size: 120)).foregroundStyle(Theme.gold)
                    .rotationEffect(.degrees(angle))
            }
            Text("Wskazuje: lodówka").spaced(.title3, .bold)
            Text("Odległość: 4 kroki").spaced(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.spring(duration: 1.2, bounce: 0.4)) { angle = Double.random(in: -50...50) }
            }
        }
    }
}

struct FakeReminders: View {
    @State private var done = [false, false, false, false]
    private let items = ["Zrobić coś ważnego", "Odpisać mamie", "Wynieść śmieci", "Zacząć dietę (jutro)"]

    var body: some View {
        List {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation { done[i] = true }
                    Haptics.tap(.light)
                    Task { try? await Task.sleep(for: .seconds(1)); withAnimation { done[i] = false } }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done[i] ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(done[i] ? .green : .orange)
                        Text(items[i]).strikethrough(done[i])
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            Text("Zadania same się odhaczają i wracają. Tak działa życie.").spaced(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }
}

struct FakeFiles: View {
    @State private var msg = ""
    private let folders = [("Dokumenty", "puste"), ("Pobrane", "1 TB"), ("Zdjęcia kota", "9 999 plików"), ("Tajne (nie otwieraj)", "?")]

    var body: some View {
        List {
            ForEach(folders.indices, id: \.self) { i in
                Button {
                    msg = i == 3 ? "Mówiłem: nie otwieraj." : "Folder „\(folders[i].0)” jest chwilowo niedostępny."
                    Haptics.tap(.medium)
                } label: {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(folders[i].0)
                        Spacer()
                        Text(folders[i].1).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            if !msg.isEmpty { Text(msg).spaced(.footnote, .semibold).foregroundStyle(.red).listRowBackground(Color.clear) }
        }
        .listStyle(.plain)
    }
}

struct FakeMusic: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var playing = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
                .frame(width: 240, height: 240).overlay(Image(systemName: "music.note").font(.system(size: 90)).foregroundStyle(.white.opacity(0.9)))
            Text("Utwór, którego nie ma").spaced(.title3, .bold)
            Text("Zespół Cisza").spaced(.subheadline).foregroundStyle(.secondary)
            Button {
                playing.toggle()
                if playing, let b = PrankSound.all["chime"]?() { hub.mixer.play(b, tag: 9800, gain: 0.6) }
                Haptics.tap(.medium)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 34)).foregroundStyle(.white)
                    .frame(width: 84, height: 84).glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            Text(playing ? "Gra… ale tylko w twojej głowie" : "Znaleziono 0 piosenek i dużo ciszy").spaced(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
