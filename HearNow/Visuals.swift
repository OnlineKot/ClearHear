import SwiftUI

// Wygladzone liczby z miernikow. Mierniki skacza co kilka milisekund, oko tego nie lubi,
// wiec rosna szybko i opadaja wolno.
final class Smoother {
    var voice = [Float](repeating: 0, count: Meters.bands)
    var raw = [Float](repeating: 0, count: Meters.bands)
    var level: Float = 0
    var speech: Float = 0
    private var last: TimeInterval = 0

    func update(_ m: Meters, now: TimeInterval) {
        guard now != last else { return }
        let dt = Float(min(0.1, max(0.001, now - last)))
        last = now
        let up = 1 - expf(-dt * 30)
        let down = 1 - expf(-dt * 7)
        for i in 0..<Meters.bands {
            let v = m.voice[i], r = m.raw[i]
            voice[i] += (v - voice[i]) * (v > voice[i] ? up : down)
            raw[i] += (r - raw[i]) * (r > raw[i] ? up : down)
        }
        let l = min(1, m.outLevel * 6)
        level += (l - level) * (l > level ? up : down)
        speech += (m.speech - speech) * (1 - expf(-dt * 6))
    }
}

extension Color {
    // od turkusu przez blekit do fioletu, jak w Siri
    static func tone(_ t: Double) -> Color {
        Color(hue: 0.50 + 0.30 * t, saturation: 0.55, brightness: 1)
    }
}

// ------------------------------------------------------------------ tlo

// Zywa poswiata za wszystkim. Czarna, gdy apka nie slucha, i rozjasnia sie z glosem.
struct Aura: View {
    let smoother: Smoother
    let running: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce || !running)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let lv = Double(smoother.level)
            let sp = Double(smoother.speech)
            let a = reduce ? 0.0 : 1.0
            let x1 = Float(0.5 + 0.10 * a * sin(t * 0.55))
            let y1 = Float(0.5 + 0.10 * a * cos(t * 0.45))
            let cx = Float(0.5 + 0.14 * a * sin(t * 0.70 + 1))
            let cy = Float(0.5 + 0.14 * a * cos(t * 0.60))
            let y2 = Float(0.5 + 0.10 * a * sin(t * 0.50 + 2))
            let x3 = Float(0.5 + 0.10 * a * cos(t * 0.65 + 3))

            let points: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(x1, 0), SIMD2(1, 0),
                SIMD2(0, y1), SIMD2(cx, cy), SIMD2(1, y2),
                SIMD2(0, 1), SIMD2(x3, 1), SIMD2(1, 1),
            ]
            let navy = Color(red: 0.02, green: 0.06, blue: 0.22)
            let violet = Color(red: 0.10, green: 0.02, blue: 0.30)
            let core = Color(red: 0.0, green: 0.45 + 0.3 * sp, blue: 0.95)
            let teal = Color(red: 0.0, green: 0.30, blue: 0.55)
            let deep = Color(red: 0.05, green: 0.10, blue: 0.35)
            let colors: [Color] = [
                .black, navy, .black,
                violet, core, teal,
                .black, deep, .black,
            ]

            MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .opacity(running ? 0.30 + 0.45 * lv : 0)
            .blur(radius: 24)
            .ignoresSafeArea()
        }
        .animation(.smooth(duration: 1.4), value: running)
        .allowsHitTesting(false)
    }
}

// ------------------------------------------------------------------ srodek ekranu

// Wielkie szklane kolo z pierscieniem widma. Dotkniecie wlacza i wylacza sluchanie.
// Kolorowe kreski to to, co slychac po obrobce, szare cienkie to to, co weszlo z mikrofonu.
// Jak szare sa dluzsze od kolorowych, to widac ile odjelo odszumianie.
struct Hero: View {
    @ObservedObject var engine: HearEngine
    let smoother: Smoother
    let side: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var running: Bool { engine.state == .running }

    var body: some View {
        TimelineView(.animation(minimumInterval: running ? nil : 1.0 / 20, paused: reduce && !running)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let _ = smoother.update(engine.meters, now: t)
            let level = CGFloat(smoother.level)

            ZStack {
                Canvas { ctx, size in
                    drawRing(ctx, size, t)
                }
                .accessibilityHidden(true)

                orb(level: level)
            }
        }
        .frame(width: side, height: side)
    }

    private func orb(level: CGFloat) -> some View {
        let d = side * 0.58
        let starting = engine.state == .starting
        return Button {
            engine.toggle()
        } label: {
            Image(systemName: running ? "waveform" : "mic.fill")
                .font(.system(size: d * 0.32, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: running && !reduce)
                .symbolEffect(.pulse, isActive: starting)
                .frame(width: d, height: d)
                .glassEffect(.regular.tint(running ? Color.cyan.opacity(0.30) : nil).interactive(), in: .circle)
                .scaleEffect(running && !reduce ? 1 + 0.05 * level : 1)
        }
        .buttonStyle(.plain)
        .animation(.bouncy(duration: 0.6), value: engine.state)
        .sensoryFeedback(trigger: running) { _, now in
            now ? SensoryFeedback.success : SensoryFeedback.impact(flexibility: .soft)
        }
        .accessibilityLabel(running ? "Zatrzymaj słuchanie" : "Zacznij słuchać")
        .accessibilityHint("Włącza i wyłącza wzmacnianie głosu w słuchawkach")
    }

    private func drawRing(_ context: GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        var ctx = context
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r0 = side * 0.34
        let count = 64
        let maxLen = side * 0.17
        let live = running

        var glow = Path()
        var crisp: [(Path, Color)] = []
        var haze = Path()

        for j in 0..<count {
            let b = j < 32 ? j : 63 - j      // lustro: niskie tony u gory, wysokie u dolu
            let ang = Double(j) / Double(count) * 2 * .pi - .pi / 2
            let dir = CGPoint(x: cos(ang), y: sin(ang))
            func line(_ len: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: c.x + dir.x * r0, y: c.y + dir.y * r0))
                p.addLine(to: CGPoint(x: c.x + dir.x * (r0 + len), y: c.y + dir.y * (r0 + len)))
                return p
            }

            if live {
                let v = CGFloat(smoother.voice[b])
                let r = CGFloat(smoother.raw[b])
                haze.addPath(line(3 + r * maxLen))
                let len = 3 + v * maxLen
                let color = Color.tone(Double(b) / 31)
                crisp.append((line(len), color))
                glow.addPath(line(len))
            } else {
                // w bezczynnosci cicha fala przebiega po pierscieniu
                let wave = reduce ? 0.5 : 0.5 + 0.5 * sin(t * 1.4 - Double(j) * 0.22)
                crisp.append((line(3 + 3 * CGFloat(wave)), Color.white.opacity(0.22 + 0.2 * wave)))
            }
        }

        if live {
            ctx.stroke(haze, with: .color(.white.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 7))
                l.stroke(glow, with: .color(Color.tone(0.4).opacity(0.7)),
                         style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        for (p, color) in crisp {
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
    }
}
