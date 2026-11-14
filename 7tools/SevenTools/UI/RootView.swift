import SwiftUI

struct RootView: View {
    @EnvironmentObject private var hub: AudioHub
    @EnvironmentObject private var store: SoundStore
    @EnvironmentObject private var pads: PadsModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Pady", systemImage: "square.grid.3x3.fill", value: 0) {
                PadsView()
            }
            Tab("Pętla", systemImage: "repeat", value: 1) {
                LooperView(hub: hub)
            }
            Tab("Sampler", systemImage: "pianokeys", value: 2) {
                SamplerView(hub: hub, store: store)
            }
            Tab("Głos", systemImage: "waveform.badge.mic", value: 3) {
                VoiceView()
            }
            Tab("Narzędzia", systemImage: "wrench.and.screwdriver.fill", value: 4) {
                ToolsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NowPlaying() }
        .tint(Theme.gold)
        .overlay(alignment: .top) {
            if let n = hub.notice {
                NoticeBar(text: n) { hub.notice = nil }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.bouncy(duration: 0.5), value: hub.notice)
        .task { hub.start() }
    }
}

// Pasek nad zakladkami: ile dzwiekow gra i przycisk "stop"
private struct NowPlaying: View {
    @EnvironmentObject private var hub: AudioHub

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let n = hub.mixer.activeVoices
            let looping = hub.mixer.loop { $0.state == .playing || $0.state == .overdubbing }
            HStack(spacing: 12) {
                Image(systemName: n > 0 || looping ? "waveform" : "speaker.slash.fill")
                    .font(.system(size: 20, weight: .bold))
                    .symbolEffect(.variableColor.iterative, isActive: n > 0 || looping)
                    .foregroundStyle(n > 0 || looping ? Theme.gold : Color.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(n > 0 || looping ? "Gra" : "Cisza").spaced(.subheadline, .bold)
                    Text(looping ? "pętla działa" : (n > 0 ? "\(n) dźwięków" : "dotknij pada"))
                        .spaced(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    hub.mixer.stopAll()
                    Haptics.tap(.soft)
                } label: {
                    Image(systemName: "stop.fill").font(.system(size: 18, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zatrzymaj wszystkie dźwięki")
            }
            .padding(.horizontal, 18)
        }
    }
}

struct NoticeBar: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 22, weight: .semibold))
            Text(text).spaced(.subheadline, .semibold).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(Color.orange.opacity(0.25)), in: .rect(cornerRadius: 26))
    }
}
