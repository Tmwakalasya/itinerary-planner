import SwiftUI
import MapKit

/// A route from a fresh location fix, kept inside City Tourist. This is a
/// preview with manual refresh, not a background navigation session.
struct DirectionsView: View {
    let place: Place

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = LocationProvider(desiredAccuracy: kCLLocationAccuracyBest)
    @State private var preview = DirectionsPreview()
    @State private var mode: TravelMode
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStep: Int?
    @State private var retryID = UUID()

    private struct RequestKey: Hashable {
        let origin: Coordinate?
        let destination: Coordinate
        let mode: TravelMode
        let retryID: UUID
    }

    init(place: Place, initialMode: TravelMode = .walking) {
        self.place = place
        _mode = State(initialValue: initialMode == .driving ? .driving : .walking)
    }

    private var requestKey: RequestKey {
        RequestKey(origin: scenePhase == .background ? nil : location.coordinate,
                   destination: place.coordinate, mode: mode, retryID: retryID)
    }

    private var steps: [MKRoute.Step] {
        preview.route?.steps.filter { !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    routeMap
                        .frame(height: min(340, max(200, geometry.size.height * 0.43)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(place.name).sectionTitleStyle()
                                Text("Directions from your location").metaStyle()
                            }
                            Picker("Travel option", selection: $mode) {
                                Label("Walk", systemImage: "figure.walk").tag(TravelMode.walking)
                                Label("Drive", systemImage: "car.fill").tag(TravelMode.driving)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("directionsTravelMode")
                            routeContent
                        }
                        .padding(Metric.gutter)
                    }
                    .background(Palette.canvas)
                }
            }
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { location.refresh() }
            .task(id: requestKey) {
                selectedStep = nil
                guard scenePhase != .background, let origin = location.coordinate else {
                    preview.clear()
                    position = .automatic
                    return
                }
                await preview.load(from: origin, to: place.coordinate, mode: mode)
            }
            .onChange(of: preview.route) { _, route in
                if let route { show(route.polyline) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { location.refresh() }
                else if phase == .background { location.stop(); preview.clear() }
            }
            .onDisappear { location.stop(); preview.clear() }
        }
    }

    private var routeMap: some View {
        Map(position: $position) {
            if let route = preview.route {
                MapPolyline(route.polyline)
                    .stroke(Brand.rausch, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                if let selectedStep, steps.indices.contains(selectedStep) {
                    MapPolyline(steps[selectedStep].polyline)
                        .stroke(Brand.babu, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                }
            }
            if let origin = location.coordinate {
                Annotation("You", coordinate: origin.clLocation) {
                    Image(systemName: "location.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .background(.white, in: Circle())
                        .accessibilityLabel("Your starting location")
                }
            }
            Marker(place.name, coordinate: place.coordinate.clLocation).tint(Brand.rausch)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay(alignment: .bottomTrailing) {
            if let route = preview.route {
                Button {
                    selectedStep = nil
                    show(route.polyline)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Show whole route")
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        if !location.isAuthorized {
            if location.canAsk {
                Text("Use your location to find a route to \(place.name).").bodyStyle()
                PrimaryButton(title: "Use my location") { location.requestPermission() }
            } else if location.authorization == .denied {
                Text("Location access is off. Allow it in Settings to get directions from where you are.").bodyStyle()
                SecondaryButton(title: "Open Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                Text("Location access is restricted on this device.").bodyStyle()
            }
        } else if location.isLocating {
            ProgressView("Finding your location…")
        } else if let error = location.errorMessage {
            Text("Couldn’t find your location").cardTitleStyle()
            Text(error).metaStyle()
            refreshButton
        } else {
            switch preview.state {
            case .idle:
                Text("Update your location to preview the route.").metaStyle()
                refreshButton
            case .loading:
                ProgressView(mode == .walking ? "Finding a walking route…" : "Finding a driving route…")
            case .failed(let message):
                Text("Route unavailable").sectionTitleStyle()
                Text(message).metaStyle()
                SecondaryButton(title: "Try route again", systemImage: "arrow.clockwise") { retryID = UUID() }
                refreshButton
            case .loaded:
                if let route = preview.route {
                    routeSummary(route)
                    refreshButton
                    stepList
                }
            }
        }
    }

    private func routeSummary(_ route: MKRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(duration(route.expectedTravelTime)).font(.title.bold())
                    Text(distance(route.distance)).metaStyle()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(duration(route.expectedTravelTime)).font(.title.bold())
                    Text(distance(route.distance)).metaStyle()
                }
            }
            Text("Route preview · Update your location to refresh directions.").captionStyle()
            if (location.horizontalAccuracy ?? 0) > 100 {
                Text("Your location is approximate; the route starts nearby.").captionStyle()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var refreshButton: some View {
        SecondaryButton(title: "Update my location", systemImage: "location") {
            preview.clear()
            selectedStep = nil
            location.refresh()
            // A fresh fix may have exactly the same coordinates. The user's
            // refresh still requests a new route and updated travel time.
            retryID = UUID()
        }
    }

    @ViewBuilder
    private var stepList: some View {
        if steps.isEmpty {
            Text("Written directions aren’t available for this route.").metaStyle()
        } else {
            Text("Step by step").sectionTitleStyle()
            Text("Tap a step to see it on the map.").captionStyle()
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Button {
                    selectedStep = index
                    show(step.polyline)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .background(Palette.surface, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.instructions).bodyStyle()
                            if step.distance > 0 { Text(distance(step.distance)).captionStyle() }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(selectedStep == index ? Brand.babu.opacity(0.1) : Palette.canvas,
                                in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show this step on the map")
                Hairline()
            }
        }
    }

    private func show(_ line: MKPolyline) {
        guard line.pointCount > 0 else { return }
        let rect = line.boundingMapRect
        position = .rect(rect.insetBy(dx: -max(rect.width * 0.2, 400),
                                     dy: -max(rect.height * 0.2, 400)))
    }

    private func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}
