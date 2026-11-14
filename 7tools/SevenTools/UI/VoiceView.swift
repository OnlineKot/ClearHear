import SwiftUI

// Zmieniacz glosu: mikrofon -> efekt -> sluchawki, na zywo.
struct VoiceView: View {
    @EnvironmentObject private var hub: AudioHub
    @Namespace private var ns

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Głos").spaced(.largeTitle, .bold)
                        Text("Twój głos z efektami, na żywo").spaced(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                powerButton

                if !hub.headphones {
                    Card {
                        Label("Podłącz słuchawki. Bez nich mikrofon łapałby własny głos z głośnika i piszczał.",
                              systemImage: "headphones")
                            .spaced(.subheadline, .semibold)
                    }
                    .transition(.scale(0.95).combined(with: .opacity))
                }

                presets
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .animation(.bouncy(duration: 0.5), value: hub.headphones)
    }

    private var powerButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: hub.fxOn ? "waveform" : "power")
                    .font(.system(size: 46, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: hub.fxOn)
                Text(hub.fxOn ? "Słychać cię" : "Włącz").spaced(.headline, .bold)
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(.white)
            .frame(width: 170, height: 170)
            .glassEffect(.regular.tint(hub.fxOn ? Theme.gold.opacity(0.55) : nil).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .animation(.bouncy(duration: 0.5), value: hub.fxOn)
        .sensoryFeedback(.impact(weight: .medium), trigger: hub.fxOn)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel(hub.fxOn ? "Wyłącz efekty głosu" : "Włącz efekty głosu")
    }

    private func toggle() async {
        if hub.fxOn {
            hub.fxOn = false
            hub.releaseMic("voice")
        } else {
            guard hub.headphones else {
                hub.notice = "Podłącz słuchawki, żeby włączyć efekty głosu."
                return
            }
            guard await hub.useMic("voice") else { return }
            hub.fxOn = true
        }
    }

    private var presets: some View {
        GlassEffectContainer(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(FXPreset.all) { p in
                    Button {
                        withAnimation(.bouncy(duration: 0.5)) { hub.fx = p }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: p.symbol).font(.system(size: 18, weight: .semibold)).frame(width: 26)
                            Text(p.name).spaced(.subheadline, .bold)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(hub.fx == p ? Color.white : Color.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .contentShape(.rect(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                    .background {
                        if hub.fx == p {
                            Color.clear
                                .glassEffect(.regular.tint(Theme.gold.opacity(0.5)).interactive(), in: .rect(cornerRadius: 24))
                                .glassEffectID("fx", in: ns)
                        } else {
                            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 24))
                        }
                    }
                    .accessibilityAddTraits(hub.fx == p ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hub.fx.id)
    }
}
