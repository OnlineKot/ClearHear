import SwiftUI

@main
struct SevenToolsApp: App {
    @StateObject private var hub: AudioHub
    @StateObject private var store: SoundStore
    @StateObject private var pads: PadsModel
    @StateObject private var motion: MotionHub
    @StateObject private var location = LocationHub()
    @StateObject private var gestures: GestureCenter
    @StateObject private var updates = UpdateChecker()
    @AppStorage("updateCheck") private var autoCheck = true
    @State private var showSplash = true

    init() {
        let h = AudioHub()
        let s = SoundStore()
        _hub = StateObject(wrappedValue: h)
        _store = StateObject(wrappedValue: s)
        let p = PadsModel(hub: h, store: s)
        let m = MotionHub()
        _pads = StateObject(wrappedValue: p)
        _motion = StateObject(wrappedValue: m)
        _gestures = StateObject(wrappedValue: GestureCenter(motion: m, hub: h, pads: p, store: s))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(hub)
                    .environmentObject(store)
                    .environmentObject(pads)
                    .environmentObject(motion)
                    .environmentObject(location)
                    .environmentObject(gestures)
                    .environmentObject(updates)
                    .overlay(alignment: .top) {
                        UpdateBanner().environmentObject(updates)
                    }

                if showSplash {
                    Splash {
                        withAnimation(.smooth(duration: 0.5)) { showSplash = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.gold)
            .task {
                if autoCheck { await updates.check() }
            }
        }
    }
}
