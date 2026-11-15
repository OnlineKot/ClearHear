import SwiftUI

@main
struct SevenToolsApp: App {
    @StateObject private var hub = AudioHub()
    @StateObject private var store = SoundStore()
    @StateObject private var profiles = ProfileStore()
    @StateObject private var updates = UpdateChecker()
    @AppStorage("updateCheck") private var autoCheck = true
    @State private var showSplash = true
    @State private var showPicker = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                // wszystko, co zalezy od profilu, powstaje od nowa przy kazdym przelaczeniu (.id)
                ProfileHost(hub: hub, store: store)
                    .id(profiles.generation)
                    .environmentObject(hub)
                    .environmentObject(store)
                    .environmentObject(profiles)
                    .environmentObject(updates)
                    .overlay(alignment: .top) {
                        UpdateBanner().environmentObject(updates)
                    }

                if showPicker {
                    ProfilePicker { withAnimation(.smooth(duration: 0.4)) { showPicker = false } }
                        .environmentObject(profiles)
                        .environmentObject(hub)
                        .transition(.opacity)
                        .zIndex(1)
                }

                if showSplash {
                    Splash {
                        withAnimation(.smooth(duration: 0.5)) { showSplash = false }
                        if profiles.askOnLaunch && profiles.profiles.count > 1 { showPicker = true }
                    }
                    .transition(.opacity)
                    .zIndex(2)
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

// Modele zalezne od profilu. Czytaja ustawienia przy tworzeniu, dlatego po zmianie profilu powstaja od nowa.
struct ProfileHost: View {
    @StateObject private var pads: PadsModel
    @StateObject private var motion: MotionHub
    @StateObject private var location = LocationHub()
    @StateObject private var gestures: GestureCenter
    @StateObject private var boards: BoardsModel

    init(hub: AudioHub, store: SoundStore) {
        let p = PadsModel(hub: hub, store: store)
        let m = MotionHub()
        _pads = StateObject(wrappedValue: p)
        _motion = StateObject(wrappedValue: m)
        _gestures = StateObject(wrappedValue: GestureCenter(motion: m, hub: hub, pads: p, store: store))
        _boards = StateObject(wrappedValue: BoardsModel(hub: hub, store: store, pads: p))
    }

    var body: some View {
        RootView()
            .environmentObject(pads)
            .environmentObject(motion)
            .environmentObject(location)
            .environmentObject(gestures)
            .environmentObject(boards)
            .task {
                await boards.refreshCatalog()
                await boards.installStarterIfNeeded()
            }
    }
}
