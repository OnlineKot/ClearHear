import SwiftUI
import UIKit

// Sprawdzanie aktualizacji. Pobiera jeden maly plik JSON z /updateapi, niczego o Tobie nie wysyla.
// Numer buildu w apce to numer przebiegu CI, ten sam co "build" w pliku z serwera.

struct RemoteBuild: Decodable, Equatable {
    let version: String
    let build: Int
    let date: String
    let size: Int
    let ipa: URL
    let page: URL

    var sizeText: String {
        String(format: "%.1f MB", Double(size) / 1_048_576).replacingOccurrences(of: ".", with: ",")
    }
}

final class UpdateChecker: ObservableObject {
    static let feed = URL(string: "https://fastlink.teodorteo.com/updateapi/hearnow.json")!
    static let page = URL(string: "https://fastlink.teodorteo.com/hearnow/install/")!

    @Published private(set) var latest: RemoteBuild?
    @Published private(set) var status = "Jeszcze nie sprawdzano."
    @Published private(set) var checking = false
    @Published private(set) var showBanner = false

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var hasUpdate: Bool { (latest?.build ?? 0) > currentBuild }

    // manual: ktos nacisnal "Sprawdz teraz", wiec baner pokazujemy nawet po wczesniejszym zamknieciu
    @MainActor
    func check(manual: Bool = false) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }

        let req = URLRequest(url: Self.feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let remote = try JSONDecoder().decode(RemoteBuild.self, from: data)
            latest = remote

            if remote.build > currentBuild {
                status = "Dostępna wersja \(remote.version) (build \(remote.build))."
                let dismissed = UserDefaults.standard.integer(forKey: "updateDismissed")
                if manual || dismissed != remote.build { showBanner = true }
            } else {
                status = "Masz najnowszą wersję."
                showBanner = false
            }
        } catch {
            status = "Nie udało się sprawdzić. Sprawdź internet i spróbuj jeszcze raz."
        }
    }

    // "x" na banerze: ten build nie wyskoczy sam drugi raz
    @MainActor
    func dismissBanner() {
        if let r = latest { UserDefaults.standard.set(r.build, forKey: "updateDismissed") }
        showBanner = false
    }

    // Otwiera strone instalacji w Safari i zamyka apke. W LiveContainerze zaktualizowac sie nie da,
    // dopoki apka dziala, wiec zamykamy ja sami.
    @MainActor
    func install() {
        let url = latest?.page ?? Self.page
        UIApplication.shared.open(url, options: [:]) { ok in
            guard ok else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
        }
    }
}

// Szklany baner na gorze ekranu, wyjezdza gdy jest nowsza wersja
struct UpdateBanner: View {
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        ZStack {
            if updates.showBanner, let r = updates.latest {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nowa wersja \(r.version)").spaced(.headline, .bold)
                        Text("Build \(r.build), \(r.sizeText)")
                            .spaced(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Button {
                        updates.install()
                    } label: {
                        Text("Aktualizuj").spaced(.subheadline, .bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.blue)
                    Button {
                        updates.dismissBanner()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassEffect(.regular, in: .rect(cornerRadius: 32))
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.bouncy, value: updates.showBanner)
    }
}
