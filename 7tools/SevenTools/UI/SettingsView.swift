import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var hub: AudioHub
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var boards: BoardsModel
    @AppStorage("latencyMs") private var latency = 0.0
    @AppStorage("updateCheck") private var autoCheck = true

    var body: some View {
        Form {
            Section {
                SliderRow(symbol: "timer", title: "Korekta opóźnienia", value: $latency, range: -60...120, step: 5) {
                    String(format: "%+.0f ms", $0)
                }
                .onChange(of: latency) { hub.applyLatency() }
            } header: {
                Text("Pętla z mikrofonu")
            } footer: {
                Text("Jeśli dogrywane warstwy wchodzą za późno albo za wcześnie względem reszty, przesuń. Bluetooth zwykle potrzebuje dodatnich wartości.")
            }

            Section {
                Label("Dźwięki z internetu pochodzą z Openverse (m.in. Freesound, Wikimedia Commons, Jamendo) na licencjach Creative Commons. Autor i licencja są zapisane przy każdym dźwięku w Moich dźwiękach. Przy licencjach CC BY podawaj autora, jeśli publikujesz coś z tym dźwiękiem.", systemImage: "globe")
                Label("Dźwięki wbudowane powstają z kodu, są Twoje.", systemImage: "checkmark.seal.fill")
            } header: {
                Text("Źródła dźwięków")
            }

            Section {
                Button("Pobierz prawdziwe dźwięki na pady (bank A)") { Task { await boards.installStarter() } }
                    .disabled(boards.starterProgress != nil)
                Button("Odśwież katalog soundboardów") { Task { await boards.refreshCatalog() } }
            } header: {
                Text("Dźwięki z internetu")
            } footer: {
                Text("Katalog ma \(boards.catalog.boards.count) soundboardów. Pobrane dźwięki zostają w telefonie, więc grają bez internetu.")
            }

            Section {
                Label("Pętle i pady grają dalej po zablokowaniu ekranu i w innej apce.", systemImage: "lock.fill")
                if Runtime.isLiveContainer {
                    Label("Uruchomione w LiveContainerze. Tło trzyma wtedy sam LiveContainer, więc jeśli dźwięk milknie po zablokowaniu, sprawdź jego ustawienia pracy w tle.", systemImage: "square.stack.3d.up.fill")
                }
                if hub.micDenied {
                    Button("Otwórz ustawienia mikrofonu") { hub.openSettings() }
                }
            } header: {
                Text("W tle")
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
        .scrollContentBackground(.hidden)
        .background(Backdrop())
    }
}
