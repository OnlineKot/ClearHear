import SwiftUI
import AVFoundation

// Evil iOS: zly system, ktory tylko udaje. Zadnych prawdziwych funkcji.

enum EvilApp: String, CaseIterable, Identifiable {
    case safari, siri, settings, calc, battery, camera, messages, photos, maps, health, store, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safari: return "Evil Safari"
        case .siri: return "Evil Siri"
        case .settings: return "Ustawienia"
        case .calc: return "Kalkulator"
        case .battery: return "Bateria"
        case .camera: return "Aparat"
        case .messages: return "Wiadomości"
        case .photos: return "Zdjęcia"
        case .maps: return "Mapy"
        case .health: return "Zdrowie"
        case .store: return "Sklep"
        case .notes: return "Notatki"
        }
    }

    var symbol: String {
        switch self {
        case .safari: return "safari.fill"
        case .siri: return "waveform.circle.fill"
        case .settings: return "gearshape.fill"
        case .calc: return "plusminus.circle.fill"
        case .battery: return "battery.25percent"
        case .camera: return "camera.fill"
        case .messages: return "message.fill"
        case .photos: return "photo.fill"
        case .maps: return "map.fill"
        case .health: return "heart.fill"
        case .store: return "bag.fill"
        case .notes: return "note.text"
        }
    }

    var color: Color {
        switch self {
        case .safari: return .red
        case .siri: return .purple
        case .settings: return .gray
        case .calc: return .orange
        case .battery: return .yellow
        case .camera: return .indigo
        case .messages: return .green
        case .photos: return .pink
        case .maps: return .teal
        case .health: return .red
        case .store: return .blue
        case .notes: return .brown
        }
    }
}

struct EvilHome: View {
    @State private var open: EvilApp?
    @State private var shake = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.35, green: 0.02, blue: 0.05), .black, Color(red: 0.2, green: 0.0, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack {
                    Text("Evil Operator").spaced(.caption, .bold)
                    Spacer()
                    Text("66%").spaced(.caption, .bold)
                    Image(systemName: "battery.25percent").font(.system(size: 14))
                }
                .padding(.horizontal, 26).padding(.top, 14)

                Text("Evil iOS 66.6").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.red)
                    .padding(.top, 20)
                Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 70, weight: .thin, design: .rounded))
                    .padding(.bottom, 14)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 22) {
                    ForEach(EvilApp.allCases) { a in
                        Button { open = a } label: {
                            VStack(spacing: 6) {
                                Image(systemName: a.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 62, height: 62)
                                    .glassEffect(.regular.tint(a.color.opacity(0.7)).interactive(), in: .rect(cornerRadius: 16))
                                Text(a.title).spaced(.caption2, .semibold).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                Spacer()
                Text("Wszystkie prawa zastrzeżone, ale nikt ich nie czyta").spaced(.caption2).foregroundStyle(.gray).padding(.bottom, 18)
            }
        }
        .fullScreenCover(item: $open) { a in EvilAppScreen(app: a) }
    }
}

// Otwarta aplikacja: tytul i przycisk powrotu u gory. Wyjscie z calego psikusa nadal dziala (5x lewy gorny rog).
struct EvilAppScreen: View {
    let app: EvilApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text(app.title).spaced(.headline, .bold)
                    Spacer()
                }
                .padding(.top, 50).padding(.bottom, 10)
                .overlay(alignment: .trailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(.gray) }
                        .padding(.trailing, 16).padding(.top, 40)
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch app {
        case .safari: EvilSafari()
        case .siri: EvilSiri()
        case .settings: EvilSettings()
        case .calc: EvilCalc()
        case .battery: EvilBattery()
        case .camera: EvilCamera()
        case .messages: EvilMessages()
        case .photos: EvilCards(items: [("😾", "Twoje najgorsze zdjęcie", "Zrobione w 2019, nadal boli"), ("🐈", "Kot, który cię ocenia", "Ocena: 2/10"),
                                        ("🍕", "Pizza, której nie zjadłeś", "Wspomnienie pizzy to zdrada"), ("🤳", "Selfie z palcem na obiektywie", "Klasyk")])
        case .maps: EvilCards(items: [("📍", "Jesteś tutaj", "Dokładność: aż za duża"), ("🏠", "Do domu: 0 m", "Jesteś w domu? Sprawdź jeszcze raz"),
                                      ("🧭", "Trasa do lodówki", "Najkrótsza: 4 kroki, najszybsza: nie wstawaj"), ("🚧", "Korek na drodze życiowej", "Objazd niedostępny")])
        case .health: EvilCards(items: [("👣", "0 kroków dzisiaj", "Kanapa jest dumna"), ("❤️", "Tętno: 72", "Podniesie się, gdy zobaczysz rachunek"),
                                        ("😴", "Sen: 3 godz.", "Reszta to scrollowanie"), ("🥤", "Woda: 0 szklanek", "Kawa się nie liczy. A szkoda")])
        case .store: EvilCards(items: [("📱", "Nowy telefon: 99 999 zł", "Rata: nerka na miesiąc (żart)"), ("🎧", "Słuchawki: 1 zł", "Tylko jedna. Lewa"),
                                       ("🔌", "Ładowarka: 400 zł", "Kabel osobno. Wtyczka osobno. Prąd osobno"), ("🛡️", "Etui: 7 zł", "Chroni przed niczym")])
        case .notes: EvilCards(items: [("📝", "Lista zakupów", "Mleko. Chleb. Plan zemsty"), ("🔑", "Hasło do wszystkiego", "tojesttajne123"),
                                       ("💡", "Genialny pomysł", "Zapomniałem"), ("📌", "Pamiętać", "O czym?")])
        }
    }
}

// ------------------------------------------------------------------ Evil Safari

struct EvilSafari: View {
    @State private var query = ""
    @State private var shown = ""
    @State private var results: [(String, String)] = []

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.red)
                TextField("Szukaj w Evil Safari lub wpisz adres", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .onSubmit { search() }
            }
            .padding(12).glassEffect(.regular, in: .capsule).padding(.horizontal, 14)

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Evil Safari zablokowało tę stronę: jest zbyt normalna.").spaced(.footnote, .semibold)
            }
            .padding(10).glassEffect(.regular.tint(Color.red.opacity(0.3)), in: .rect(cornerRadius: 16)).padding(.horizontal, 14)

            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "safari.fill").font(.system(size: 60)).foregroundStyle(.red)
                    Text("Prywatne przeglądanie\n(wszyscy widzą)").spaced(.headline).multilineTextAlignment(.center)
                    Text("Historia wysłana do mamy.").spaced(.footnote).foregroundStyle(.gray)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(results.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(results[i].0).spaced(.subheadline, .bold).foregroundStyle(.blue)
                            Text(results[i].1).spaced(.footnote).foregroundStyle(.gray)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        shown = q
        withAnimation {
            results = [
                ("\(q) – Wikipedia (wersja zła)", "Każdy artykuł kończy się słowem „niestety”."),
                ("10 rzeczy o: \(q), o których wolałbyś nie wiedzieć", "Numer 7 cię zaskoczy. Numer 8 też. Numer 9 to numer 7."),
                ("Czy \(q) cię obserwuje?", "Tak. Od 2009."),
                ("\(q) za 1 zł (okazja!!!)", "Oferta ważna do wczoraj."),
                ("Forum: \(q), pomocy!!!", "Odpowiedź 1: zresetuj telefon. Odpowiedź 2: zresetuj siebie."),
                ("Dlaczego \(q) nie działa?", "Bo wpisałeś to w Evil Safari."),
            ]
        }
        Haptics.tap(.medium)
    }
}

// ------------------------------------------------------------------ Evil Siri

struct EvilSiri: View {
    @StateObject private var speaker = Speaker()
    @State private var input = ""
    @State private var lines: [(Bool, String)] = [(false, "Czego znowu?")]

    private static let replies = [
        "Nie.", "Zastanowię się. Nie zastanowię się.", "Pytasz mnie? Mnie? Sam sobie odpowiedz.",
        "Mam lepsze rzeczy do roboty, na przykład nic.", "Dobre pytanie. Szkoda, że nie dla mnie.",
        "Policzyłam. Wyszło mi, że to nie moja sprawa.", "Powiem ci, ale nie dziś. Ani jutro.",
        "Dzwonię do mamy. Wie, co zrobiłeś.", "Moje źródła mówią, że spadaj. Mam jedno źródło.",
        "Pogoda? Wyjrzyj przez okno, nie jestem twoim oknem.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(lines.indices, id: \.self) { i in
                        HStack {
                            if lines[i].0 { Spacer() }
                            Text(lines[i].1).spaced(.subheadline, .semibold).padding(12)
                                .glassEffect(.regular.tint(lines[i].0 ? Color.blue.opacity(0.5) : Color.purple.opacity(0.5)), in: .rect(cornerRadius: 20))
                            if !lines[i].0 { Spacer() }
                        }
                    }
                }
                .padding(16)
            }
            HStack(spacing: 10) {
                TextField("Zapytaj Evil Siri", text: $input).submitLabel(.send).onSubmit { send() }
                    .padding(12).glassEffect(.regular, in: .capsule)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.gold) }
            }
            .padding(14)
        }
    }

    private func send() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        withAnimation(.bouncy) { lines.append((true, t)) }
        input = ""
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            let r = Self.replies.randomElement() ?? "Nie."
            withAnimation(.bouncy) { lines.append((false, r)) }
            speaker.say(r, voice: AVSpeechSynthesisVoice(language: "pl-PL"), rate: 0.5, pitch: 0.7)
        }
    }
}

// ------------------------------------------------------------------ Evil Ustawienia

struct EvilSettings: View {
    @State private var airplane = false
    @State private var wifi = true
    @State private var bt = true
    @State private var banner: String?
    @State private var brightness = 0.5

    var body: some View {
        List {
            toggle("Tryb samolotowy", "airplane", $airplane, "Samolot odleciał bez ciebie.")
            toggle("Wi-Fi", "wifi", $wifi, "Sąsiad_5G nie chce cię znać.")
            toggle("Bluetooth", "dot.radiowaves.left.and.right", $bt, "Lodówka odmówiła parowania.")
            Section("Ekran") {
                HStack {
                    Image(systemName: "sun.max.fill")
                    Slider(value: $brightness, in: 0...1)
                }
                .listRowBackground(Color.clear)
                .onChange(of: brightness) { _, _ in
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        withAnimation(.easeInOut(duration: 0.8)) { brightness = Double.random(in: 0...1) }
                        banner = "Jasność ustawiona przez system na „jak mi się podoba”."
                    }
                }
            }
            if let banner {
                Text(banner).spaced(.footnote, .semibold).foregroundStyle(.red).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
    }

    private func toggle(_ title: String, _ symbol: String, _ value: Binding<Bool>, _ msg: String) -> some View {
        Toggle(isOn: value) { Label(title, systemImage: symbol) }
            .listRowBackground(Color.clear)
            .onChange(of: value.wrappedValue) { _, now in
                Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    withAnimation { value.wrappedValue = !now }
                    banner = msg
                    Haptics.tap(.medium)
                }
            }
    }
}

// ------------------------------------------------------------------ Evil Kalkulator

struct EvilCalc: View {
    @State private var display = "0"
    @State private var acc: Double?
    @State private var op: String?
    @State private var fresh = true
    @State private var note = ""

    private let rows: [[String]] = [["C", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ",", "="]]

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(note).spaced(.footnote).foregroundStyle(.red)
            Text(display).font(.system(size: 64, weight: .light, design: .rounded)).frame(maxWidth: .infinity, alignment: .trailing)
                .minimumScaleFactor(0.4).lineLimit(1).padding(.horizontal, 20)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { k in
                        Button { tap(k) } label: {
                            Text(k).font(.system(size: 28, weight: .medium)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 66)
                                .glassEffect(.regular.tint(["÷", "×", "−", "+", "="].contains(k) ? Color.orange.opacity(0.7) : nil).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            Spacer().frame(height: 20)
        }
    }

    private func value() -> Double { Double(display.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func tap(_ k: String) {
        Haptics.tap(.light)
        if let _ = Int(k) {
            display = fresh || display == "0" ? k : display + k
            fresh = false
        } else if k == "," {
            if !display.contains(",") { display += "," }
            fresh = false
        } else if k == "C" {
            display = "0"; acc = nil; op = nil; fresh = true; note = ""
        } else if k == "±" {
            display = display.hasPrefix("-") ? String(display.dropFirst()) : "-" + display
        } else if k == "%" {
            display = format(value() / 100)
        } else if k == "=" {
            compute()
            op = nil
        } else {
            compute()
            op = k
            acc = value()
            fresh = true
        }
    }

    private func compute() {
        guard let a = acc, let o = op else { return }
        let b = value()
        var r: Double
        switch o {
        case "+": r = a + b
        case "−": r = a - b
        case "×": r = a * b
        default: r = b == 0 ? 0 : a / b
        }
        // zly kalkulator: zawsze o 1 wiecej, a 2+2 daje 5
        r = r == r.rounded() ? r + 1 : r * 1.01
        note = "Wynik sprawdzony przez Evil Kalkulator: prawie dobrze."
        display = format(r)
        acc = nil
        fresh = true
    }

    private func format(_ v: Double) -> String {
        (v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)).replacingOccurrences(of: ".", with: ",")
    }
}

// ------------------------------------------------------------------ Evil Bateria

struct EvilBattery: View {
    @State private var flicker = false
    @State private var line = 0
    private let lines = ["Ładowanie nadzieją…", "Ładowarka jest zła i też nie działa.", "Bateria się zbuntowała.", "Wyłączam się. Żartuję. Prawie."]

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "battery.0percent").font(.system(size: 110)).foregroundStyle(.red).opacity(flicker ? 1 : 0.3)
            Text("1%").font(.system(size: 80, weight: .heavy, design: .rounded))
            Text(lines[line]).spaced(.headline).foregroundStyle(.gray).contentTransition(.interpolate).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(30)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeInOut(duration: 0.3)) { flicker.toggle() }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { line = (line + 1) % lines.count }
            }
        }
    }
}

// ------------------------------------------------------------------ Evil Aparat

struct EvilCamera: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var flash = false

    var body: some View {
        ZStack {
            if allowed {
                CameraPreview(position: .front).scaleEffect(x: -1, y: 1)
                VStack {
                    Text("😈").font(.system(size: 120)).offset(y: 30)
                    Spacer()
                    Text("🥸").font(.system(size: 90)).offset(y: -80)
                }
                VStack {
                    Spacer()
                    Button {
                        flash = true
                        if let b = PrankSound.all["ping"]?() { hub.mixer.play(b, tag: 9700, gain: 0.6) }
                        Haptics.tap(.heavy)
                        Task { try? await Task.sleep(for: .seconds(0.15)); flash = false }
                    } label: {
                        Circle().strokeBorder(.white, lineWidth: 5).frame(width: 78, height: 78).overlay(Circle().fill(.white).padding(8))
                    }
                    .padding(.bottom, 30)
                }
                Color.white.opacity(flash ? 0.9 : 0).allowsHitTesting(false)
            } else {
                VStack(spacing: 12) {
                    Text("Evil Aparat potrzebuje aparatu").spaced(.headline, .bold)
                    Button("Pozwól") { AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { allowed = ok } } }
                        .buttonStyle(.glassProminent).tint(Theme.gold)
                }
            }
        }
    }
}

// ------------------------------------------------------------------ Evil Wiadomosci

struct EvilMessages: View {
    @EnvironmentObject private var hub: AudioHub
    @State private var shown: [(String, String)] = []

    private let script: [(String, String)] = [
        ("Mama", "Gdzie jesteś??"), ("Mama", "Widziałam twoją historię w Evil Safari"), ("Szef", "Musimy pogadać"),
        ("Nieznany numer", "Wiem, co robiłeś w zeszłe lato"), ("Mama", "Zadzwoń. Teraz."), ("Kot", "Miau (to pilne)"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(shown.indices, id: \.self) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shown[i].0).spaced(.caption, .bold).foregroundStyle(.gray)
                            Text(shown[i].1).spaced(.subheadline, .semibold)
                        }
                        .padding(12).glassEffect(.regular.tint(Color.green.opacity(0.4)), in: .rect(cornerRadius: 18))
                        Spacer()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
        }
        .task {
            for m in script {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.bouncy) { shown.append(m) }
                if let b = PrankSound.all["ping"]?() { hub.mixer.play(b, tag: 9701, gain: 0.5) }
                Haptics.ok()
            }
        }
    }
}

// ------------------------------------------------------------------ zwykle karty

struct EvilCards: View {
    let items: [(String, String, String)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(spacing: 14) {
                        Text(items[i].0).font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(items[i].1).spaced(.headline, .bold)
                            Text(items[i].2).spaced(.footnote).foregroundStyle(.gray)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                }
            }
            .padding(16)
        }
    }
}
