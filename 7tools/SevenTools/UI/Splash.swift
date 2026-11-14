import SwiftUI

// Wejscie w stylu Bonda: lufa, z ktorej wyjezdza siodemka. Dotkniecie pomija.
struct Splash: View {
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var start = Date()
    @State private var finished = false

    private let total = 2.6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if reduce {
                logo(1)
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSince(start)
                    ZStack {
                        Canvas { ctx, size in drawBarrel(ctx, size, t) }
                        logo(min(1, max(0, (t - 1.2) / 0.7)))
                    }
                    .onChange(of: t > total) { _, over in if over { finish() } }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            if reduce {
                try? await Task.sleep(for: .seconds(0.9))
                finish()
            }
        }
        .accessibilityLabel("007Tools")
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        done()
    }

    private func logo(_ p: Double) -> some View {
        VStack(spacing: 6) {
            Text("007")
                .font(.system(size: 76, weight: .black, design: .rounded))
                .tracking(4)
            Text("Tools")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .tracking(10)
                .foregroundStyle(Theme.gold)
        }
        .foregroundStyle(.white)
        .opacity(p)
        .scaleEffect(0.85 + 0.15 * p)
        .blur(radius: (1 - p) * 14)
    }

    private func drawBarrel(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height)
        // kolo "lufy" rosnie z kropki, potem sie rozwiera i znika
        let grow = min(1, t / 0.7)
        let ease = 1 - pow(1 - grow, 3)
        let outro = max(0, min(1, (t - 1.15) / 0.7))
        let r = base * 0.42 * ease * (1 + outro * 1.6)
        let alpha = 1 - outro

        guard r > 1 else { return }
        // zewnetrzny pierscien
        var ring = Path()
        ring.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.stroke(ring, with: .color(.white.opacity(alpha)), lineWidth: max(1, r * 0.035))

        // nacięcia gwintu: kreski od srodka, obracaja sie
        let rot = t * 0.9
        let inner = r * 0.9
        for i in 0..<14 {
            let a = rot + Double(i) / 14 * 2 * .pi
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * inner * 0.15, y: c.y + sin(a) * inner * 0.15))
            p.addLine(to: CGPoint(x: c.x + cos(a + 0.5) * inner, y: c.y + sin(a + 0.5) * inner))
            ctx.stroke(p, with: .color(.white.opacity(0.35 * alpha)), lineWidth: max(0.6, r * 0.008))
        }
        // wnetrze
        var hole = Path()
        let hr = r * 0.82
        hole.addEllipse(in: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2))
        ctx.stroke(hole, with: .color(.white.opacity(0.7 * alpha)), lineWidth: max(0.8, r * 0.012))

        // zlota poświata
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.12))
            l.stroke(ring, with: .color(Theme.gold.opacity(0.55 * alpha)), lineWidth: r * 0.05)
        }
    }
}
