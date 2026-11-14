import SwiftUI

@main
struct HearNowApp: App {
    @StateObject private var engine = HearEngine()
    @StateObject private var updates = UpdateChecker()
    @AppStorage("updateCheck") private var autoCheck = true

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(updates)
                .preferredColorScheme(.dark)
                .tint(.white)
                .overlay(alignment: .top) {
                    UpdateBanner()
                        .environmentObject(updates)
                }
                .task {
                    if autoCheck { await updates.check() }
                }
        }
    }
}
