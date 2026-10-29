import SwiftUI
import MapKit

/// Where a route starts: here, where the traveller is staying, or any address
/// or place Apple Maps can find near the destination. For when the phone
/// can't find itself, location is off, or the trip starts somewhere else.
struct StartingPointSheet: View {
    let destination: Coordinate
    let lodging: Lodging?
    /// Nil starts from the traveller's own location.
    let onChoose: (Lodging?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = LodgingSearch()
    @State private var query = ""
    @State private var resolving: MKLocalSearchCompletion?
    @State private var notFound = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        option("My location", symbol: "location.fill") { choose(nil) }
                        if let lodging {
                            option("Where you’re staying", detail: lodging.name, symbol: "bed.double") {
                                choose(lodging)
                            }
                        }
                    }

                    TextField("Address or place", text: $query)
                        .bodyStyle()
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("startingPointField")

                    if notFound {
                        Text("Apple Maps couldn’t place that one. Try another suggestion.").metaStyle()
                    }
                    results
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 20)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Starting from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
        .onAppear { search.focus(on: destination) }
        .onChange(of: query) { _, text in
            notFound = false
            search.update(text)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            ForEach(search.results, id: \.self) { completion in
                option(completion.title, detail: completion.subtitle, symbol: "mappin.and.ellipse",
                       isResolving: resolving == completion) {
                    resolve(completion)
                }
                .disabled(resolving != nil)
            }
        }
    }

    private func option(_ title: String, detail: String = "", symbol: String, isResolving: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).cardTitleStyle().lineLimit(1)
                        if !detail.isEmpty { Text(detail).captionStyle().lineLimit(1) }
                    }
                    Spacer(minLength: 8)
                    if isResolving { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                Hairline()
            }
        }
        .buttonStyle(.plain)
    }

    private func choose(_ start: Lodging?) {
        onChoose(start)
        dismiss()
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        resolving = completion
        Task {
            defer { resolving = nil }
            if let start = await search.resolve(completion) {
                choose(start)
            } else {
                notFound = true
            }
        }
    }
}
