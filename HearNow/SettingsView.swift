import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: HearEngine
    @EnvironmentObject private var updates: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    @AppStorage("micSide") private var micSide = MicSide.auto.rawValue
    @AppStorage("micDirectional") private var directional = true
    @AppStorage("auto") private var auto = true
    @AppStorage("updateCheck") private var autoCheck = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kierunek", selection: $micSide) {
                        ForEach(MicSide.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Mikrofon kierunkowy", isOn: $directional)
                } header: {
                    Text("Mikrofon")
                } footer: {
                    Text("Skieruj wybrany mikrofon w stronę rozmówcy. Przedni i tylny zbierają głównie to, co jest przed nimi, dolny słyszy wszystko wokół.")
                }
                .onChange(of: micSide) { engine.applyMic() }
                .onChange(of: directional) { engine.applyMic() }

                Section {
                    Toggle("Auto-poziom głosu", isOn: $auto)
                } header: {
                    Text("Dźwięk")
                } footer: {
                    Text("Podciąga cichy głos i przyciąga za głośny, ale tylko gdy ktoś mówi, więc nie podkręca szumu między zdaniami.")
                }

                Section {
                    Label("Gra dalej po zablokowaniu ekranu i w innej apce. Sterujesz nią też z ekranu blokady i z przycisku w słuchawkach.", systemImage: "lock.fill")
                    if Runtime.isLiveContainer {
                        Label("Uruchomione w LiveContainerze. Tło trzyma wtedy sam LiveContainer, więc jeśli dźwięk milknie po zablokowaniu, sprawdź jego ustawienia pracy w tle.", systemImage: "square.stack.3d.up.fill")
                    }
                } header: {
                    Text("W tle")
                }

                Section {
                    Label("Opóźnienie jest najmniejsze na przewodowych słuchawkach. Bezprzewodowe dokładają od 0,1 do 0,3 s, to normalne.", systemImage: "timer")
                    Label("Zacznij od cichej głośności w telefonie. Apka ma limiter, ale głośny dźwięk w uchu nadal szkodzi.", systemImage: "ear.fill")
                } header: {
                    Text("Warto wiedzieć")
                }

                Section {
                    LabeledContent("W telefonie", value: "\(updates.currentVersion) (build \(updates.currentBuild))")
                    LabeledContent("Na serwerze", value: updates.latest.map { "\($0.version) (build \($0.build))" } ?? "nie sprawdzono")
                    Button(updates.checking ? "Sprawdzam…" : "Sprawdź teraz") {
                        Task { await updates.check(manual: true) }
                    }
                    .disabled(updates.checking)
                    if updates.hasUpdate, let r = updates.latest {
                        Button("Aktualizuj do \(r.version)") { updates.install() }
                    }
                    Toggle("Sprawdzaj przy starcie", isOn: $autoCheck)
                } header: {
                    Text("Wersja")
                } footer: {
                    Text(updates.status)
                }
            }
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
