import SwiftUI
import MapKit

/// Street-level preview of a place, tappable into Apple's full Look Around
/// viewer.
///
/// Coverage is patchy outside major cities, so this renders nothing when
/// there's no scene — the detail screen simply keeps the map it already had,
/// rather than showing an empty frame or an apology.
struct LookAroundBlock: View {
    let coordinate: Coordinate

    @State private var scene: MKLookAroundScene?
    @State private var didFinishLookup = false

    var body: some View {
        content
            .task(id: coordinate) { await load() }
            .animation(.easeOut(duration: 0.25), value: scene != nil)
    }

    @ViewBuilder
    private var content: some View {
        if let scene {
            VStack(alignment: .leading, spacing: 8) {
                LookAroundPreview(initialScene: scene)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                Text("Tap to look around")
                    .captionStyle()
            }
        } else {
            // A zero-height placeholder rather than an implicit EmptyView:
            // lifecycle modifiers on a view with no layout presence are not
            // reliably run, so .task above would never fire and the lookup
            // would silently never happen.
            Color.clear
                .frame(height: 0)
                .overlay(alignment: .leading) {
                    #if DEBUG
                    if didFinishLookup {
                        Text("· no street view here")
                            .captionStyle()
                            .fixedSize()
                            .offset(y: 8)
                    }
                    #endif
                }
        }
    }

    private func load() async {
        didFinishLookup = false
        // The request must be held for the whole await: created inline as a
        // temporary, ARC can release it mid-flight and the scene comes back
        // nil — indistinguishable from "no coverage here".
        let request = MKLookAroundSceneRequest(coordinate: coordinate.clLocation)
        scene = try? await request.scene
        didFinishLookup = true
    }
}
