import SwiftUI

/// "Day updated · Undo", for a few seconds after a whole day changes at once.
/// Styled like the floating Map button it temporarily stands in for.
struct UndoBar: View {
    let undo: PlanUndo

    @Environment(AppStore.self) private var store

    /// Long enough to read and reach for, short enough not to linger.
    private static let lifetime: Duration = .seconds(6)

    var body: some View {
        HStack(spacing: 16) {
            Text(undo.message)
                .font(.system(size: 14, weight: .semibold))
            Button("Undo") {
                withAnimation(.snappy(duration: 0.25)) { store.undoPlan() }
            }
            .font(.system(size: 14, weight: .bold))
            .underline()
        }
        .foregroundStyle(Palette.canvas)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Palette.ink, in: Capsule())
        .floatingShadow(y: 4, radius: 12, opacity: 0.28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: undo.id) {
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) { store.dismissUndo(undo.id) }
        }
    }
}
