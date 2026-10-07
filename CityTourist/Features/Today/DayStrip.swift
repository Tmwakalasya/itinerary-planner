import SwiftUI

/// Where each stop sits along a day strip, and where "now" falls.
///
/// Stops are spaced by their start times, so a long afternoon gap shows as
/// one, but never closer than `minSpacing`, so their labels don't collide. A
/// day too long for the space it's given gets wider than it, and scrolls.
struct DayStripLayout: Equatable {
    /// Centre of each stop's marker, in the strip's own coordinates.
    var positions: [CGFloat]
    var width: CGFloat
    /// Nil before the first stop starts and once the last has ended.
    var nowX: CGFloat?

    static func make(stops: [ItineraryStop], now: Int, width: CGFloat,
                     inset: CGFloat, minSpacing: CGFloat) -> DayStripLayout {
        guard let first = stops.first, let last = stops.last else {
            return DayStripLayout(positions: [], width: width, nowX: nil)
        }
        let span = CGFloat(max(1, last.startMinute - first.startMinute))
        let perMinute = max(0, width - 2 * inset) / span

        var positions: [CGFloat] = [inset]
        for (a, b) in zip(stops, stops.dropFirst()) {
            let gap = CGFloat(b.startMinute - a.startMinute) * perMinute
            positions.append(positions[positions.count - 1] + max(minSpacing, gap))
        }

        var nowX: CGFloat?
        if now >= first.startMinute, now < last.startMinute + last.durationMinutes,
           let i = stops.lastIndex(where: { $0.startMinute <= now }) {
            if i + 1 < stops.count {
                let fraction = CGFloat(now - stops[i].startMinute)
                    / CGFloat(max(1, stops[i + 1].startMinute - stops[i].startMinute))
                nowX = positions[i] + fraction * (positions[i + 1] - positions[i])
            } else {
                nowX = positions[i]
            }
        }

        return DayStripLayout(positions: positions,
                              width: max(width, positions[positions.count - 1] + inset),
                              nowX: nowX)
    }
}

/// The whole day at a glance, top of the Today screen: what's done, where
/// you are, and what's still to come, spaced by time.
struct DayStrip: View {
    let stops: [ItineraryStop]
    let now: Int

    private static let inset: CGFloat = 46
    private static let minSpacing: CGFloat = 92
    private static let height: CGFloat = 66
    private static let lineY: CGFloat = 30

    var body: some View {
        let status = TodayStatus.make(stops: stops, now: now)

        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let layout = DayStripLayout.make(stops: stops, now: now, width: geometry.size.width,
                                                 inset: Self.inset, minSpacing: Self.minSpacing)
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        track(layout, status: status)
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            marker(stop, state: state(of: stop, in: status))
                                .position(x: layout.positions[index], y: Self.lineY)
                        }
                        // Between stops, a tick shows how far along the hop you are.
                        if status.current == nil, let nowX = layout.nowX {
                            Capsule()
                                .fill(Brand.rausch)
                                .frame(width: 3, height: 18)
                                .position(x: nowX, y: Self.lineY)
                        }
                    }
                    .frame(width: layout.width, height: Self.height, alignment: .topLeading)
                }
                .scrollClipDisabled()
            }
            .frame(height: Self.height)

            Text(summary(status))
                .captionStyle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(status))
    }

    // MARK: Pieces

    private enum StopState { case done, current, upcoming }

    private func state(of stop: ItineraryStop, in status: TodayStatus) -> StopState {
        if status.current?.id == stop.id { return .current }
        return status.earlier.contains { $0.id == stop.id } ? .done : .upcoming
    }

    private func track(_ layout: DayStripLayout, status: TodayStatus) -> some View {
        let start = layout.positions.first ?? 0
        let end = layout.positions.last ?? 0
        let done = status.isDone && !status.earlier.isEmpty ? end : (layout.nowX ?? start)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: end - start, height: 2)
                .offset(x: start, y: Self.lineY - 1)
            Rectangle()
                .fill(Palette.ink)
                .frame(width: max(0, done - start), height: 2)
                .offset(x: start, y: Self.lineY - 1)
        }
    }

    /// The dot sits exactly on the line; its time and name hang above and
    /// below without moving it.
    private func marker(_ stop: ItineraryStop, state: StopState) -> some View {
        dot(state)
            .frame(width: 20, height: 20)
            .overlay(alignment: .top) {
                Text(stop.timeLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(state == .upcoming ? Palette.inkMuted : Palette.ink)
                    .fixedSize()
                    .offset(y: -18)
            }
            .overlay(alignment: .bottom) {
                Text(PlaceDirectory.place(id: stop.placeID)?.name ?? "…")
                    .font(.system(size: 12, weight: state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .upcoming ? Palette.inkMuted : Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: Self.minSpacing - 10)
                    .offset(y: 20)
            }
    }

    @ViewBuilder
    private func dot(_ state: StopState) -> some View {
        switch state {
        case .done:
            Circle()
                .fill(Palette.ink)
                .frame(width: 14, height: 14)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Palette.canvas)
                }
        case .current:
            Circle()
                .fill(Brand.rausch)
                .frame(width: 16, height: 16)
                .overlay { Circle().strokeBorder(Palette.canvas, lineWidth: 3) }
                .background { Circle().fill(Brand.rausch.opacity(0.18)).frame(width: 26, height: 26) }
        case .upcoming:
            Circle()
                .fill(Palette.canvas)
                .frame(width: 14, height: 14)
                .overlay { Circle().strokeBorder(Palette.inkFaint, lineWidth: 1.5) }
        }
    }

    /// "2 done · at LX Factory · 3 to go".
    private func summary(_ status: TodayStatus) -> String {
        var parts: [String] = []
        let done = status.earlier.count
        if done > 0 { parts.append(done == stops.count ? "all \(done) done" : "\(done) done") }
        if let current = status.current {
            parts.append("at \(PlaceDirectory.place(id: current.placeID)?.name ?? "your stop")")
        }
        let toGo = (status.next == nil ? 0 : 1) + status.later.count
        if toGo > 0 { parts.append("\(toGo) to go") }
        let line = parts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}

/// The same day as dots only, for the Today card on the Trips tab.
struct DayDots: View {
    let stops: [ItineraryStop]
    let now: Int

    var body: some View {
        let status = TodayStatus.make(stops: stops, now: now)
        GeometryReader { geometry in
            // Squeezed to fit: the card has no room to scroll.
            let spacing = min(16, max(0, geometry.size.width - 12) / CGFloat(max(1, stops.count - 1)))
            let layout = DayStripLayout.make(stops: stops, now: now, width: geometry.size.width,
                                             inset: 6, minSpacing: spacing)
            let start = layout.positions.first ?? 0
            let end = layout.positions.last ?? 0
            let done = status.isDone && !status.earlier.isEmpty ? end : (layout.nowX ?? start)

            ZStack(alignment: .topLeading) {
                Rectangle().fill(.white.opacity(0.35))
                    .frame(width: end - start, height: 2)
                    .offset(x: start, y: 6)
                Rectangle().fill(.white)
                    .frame(width: max(0, done - start), height: 2)
                    .offset(x: start, y: 6)
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    dot(for: stop, in: status)
                        .position(x: layout.positions[index], y: 7)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dot(for stop: ItineraryStop, in status: TodayStatus) -> some View {
        if status.current?.id == stop.id {
            Circle().fill(.white).frame(width: 12, height: 12)
                .overlay { Circle().fill(Brand.rausch).frame(width: 5, height: 5) }
        } else if status.earlier.contains(where: { $0.id == stop.id }) {
            Circle().fill(.white).frame(width: 8, height: 8)
        } else {
            Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }
}
