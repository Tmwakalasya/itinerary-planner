import SwiftUI

/// A short, local animation; the real screen loads underneath it.
struct LaunchIntroView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                route.stroke(Palette.hairline, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                route.trim(from: 0, to: appeared ? 1 : 0)
                    .stroke(Brand.rausch, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .animation(.easeInOut(duration: 0.55).delay(0.08), value: appeared)

                ForEach(0..<3) { index in
                    Circle()
                        .fill(Palette.canvas)
                        .overlay(Circle().stroke(Brand.rausch, lineWidth: 3))
                        .frame(width: 14, height: 14)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)
                        .position(points[index])
                        .animation(.easeOut(duration: 0.2).delay(Double(index) * 0.18), value: appeared)
                }
            }
            .frame(width: 176, height: 80)

            Text("City Tourist")
                .font(.title.weight(.bold))
                .tracking(-0.6)
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private var points: [CGPoint] {
        [CGPoint(x: 12, y: 62), CGPoint(x: 88, y: 18), CGPoint(x: 164, y: 52)]
    }

    private var route: Path {
        Path { path in
            path.move(to: points[0])
            path.addCurve(to: points[1], control1: CGPoint(x: 48, y: 62), control2: CGPoint(x: 50, y: 18))
            path.addCurve(to: points[2], control1: CGPoint(x: 126, y: 18), control2: CGPoint(x: 128, y: 52))
        }
    }
}
