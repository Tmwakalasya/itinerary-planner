import SwiftUI
import MapKit

/// "Where are you staying?" Any hotel or address Apple Maps can find near the
/// trip's city. Apple Maps rather than Google: it's free, needs no key, and
/// the address is the traveller's own to keep with the trip.
struct LodgingSheet: View {
    let tripID: Trip.ID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var search = LodgingSearch()
    @State private var query = ""
    @State private var resolving: MKLocalSearchCompletion?
    @FocusState private var isFieldFocused: Bool

    private var trip: Trip? { store.trip(id: tripID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Each day starts and ends here, so it shapes the order a fixed day takes and when to leave for your first stop.")
                        .metaStyle()

                    TextField("Hotel name or address", text: $query)
                        .bodyStyle()
                        .autocorrectionDisabled()
                        .focused($isFieldFocused)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    results

                    if let lodging = trip?.lodging {
                        Button("Remove \(lodging.name)", role: .destructive) {
                            store.setLodging(nil, for: tripID)
                            dismiss()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.rausch)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 20)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Where are you staying?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
        .onAppear {
            if let trip { search.focus(on: CityDirectory.city(id: trip.cityID).coordinate) }
            isFieldFocused = true
        }
        .onChange(of: query) { _, text in search.update(text) }
    }

    private var results: some View {
        VStack(spacing: 0) {
            ForEach(search.results, id: \.self) { completion in
                Button {
                    choose(completion)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bed.double")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title).cardTitleStyle().lineLimit(1)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle).captionStyle().lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if resolving == completion { ProgressView().controlSize(.small) }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(resolving != nil)
                Hairline()
            }
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        resolving = completion
        Task {
            defer { resolving = nil }
            if let lodging = await search.resolve(completion) {
                store.setLodging(lodging, for: tripID)
                dismiss()
            }
        }
    }
}

/// Apple Maps autocomplete for hotels and addresses around one city.
@MainActor
@Observable
final class LodgingSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func focus(on coordinate: Coordinate) {
        completer.region = MKCoordinateRegion(center: coordinate.clLocation,
                                              span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
    }

    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { results = [] }
        completer.queryFragment = trimmed
    }

    /// The picked suggestion's name and position.
    func resolve(_ completion: MKLocalSearchCompletion) async -> Lodging? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return Lodging(name: item.name ?? completion.title,
                       coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.results = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
