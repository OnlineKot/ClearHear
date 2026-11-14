import SwiftUI

// Wspolne klocki: tlo, naglowek strony, okragly przycisk ze szkla, karta.

struct Backdrop: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.gold.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct Page<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).spaced(.largeTitle, .bold)
                    if let subtitle {
                        Text(subtitle).spaced(.subheadline).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
    }
}

struct GlassIcon: View {
    let symbol: String
    var size: CGFloat = 46
    var tint: Color? = nil
    var label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .glassEffect(.regular.tint(tint).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

// Wiersz z suwakiem: ikona, nazwa, wartosc
struct SliderRow: View {
    let symbol: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 22)
                Text(title).spaced(.subheadline, .semibold)
                Spacer(minLength: 8)
                Text(format(value))
                    .spaced(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy(duration: 0.2), value: value)
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step) { Text(title) }
                } else {
                    Slider(value: $value, in: range) { Text(title) }
                }
            }
            .accessibilityValue(format(value))
        }
    }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil
    var selected = false

    private var glass: Glass {
        selected ? Glass.regular.tint(Theme.gold).interactive() : Glass.regular.interactive()
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
            Text(text).spaced(.subheadline, .semibold).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.black : Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(glass, in: .capsule)
    }
}

struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .spaced(.subheadline, .semibold)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
    }
}
