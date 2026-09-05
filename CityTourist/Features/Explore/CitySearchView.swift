import SwiftUI

/// "Where to?" — a live search over every city Google knows, with the bundled
/// destinations offered as suggestions before you type.
struct CitySearchView: View {
    /// Cities the user has been to recently, offered above the samples.
    var recents: [City] = []
    /// Marked with a checkmark so the current choice is always visible.
    var selection: City?
    /// Called once a suggestion has been resolved to a full city.
    let onSelect: (City) -> Void

    @State private var model = CitySearchModel()
    @State private var resolvingID: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField

            if !model.isAvailable {
                Text("Add a Google Places key to search any city — until then, the destinations below are available.")
                    .captionStyle()
            }

            if model.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                results
            } else {
                popular
            }
        }
        .task(id: model.query) { await model.search() }
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.inkMuted)

            TextField("Search cities", text: $model.query)
                .font(.system(size: 16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .submitLabel(.search)

            if model.isSearching {
                ProgressView().controlSize(.small)
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.elevated, in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
        .floatingShadow(y: 2, radius: 8, opacity: 0.08)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if let message = model.errorMessage, model.suggestions.isEmpty, !model.isSearching {
            Text(message)
                .captionStyle()
                .padding(.vertical, 8)
        }

        VStack(spacing: 0) {
            ForEach(model.suggestions) { suggestion in
                Button {
                    select(suggestion)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name).cardTitleStyle()
                            if !suggestion.region.isEmpty {
                                Text(suggestion.region).captionStyle()
                            }
                        }
                        Spacer(minLength: 8)
                        if resolvingID == suggestion.id {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(resolvingID != nil)

                Hairline()
            }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private var popular: some View {
        if !recents.isEmpty {
            cityList("Recent", cities: recents)
        }
        // Don't repeat a city that's already in the recents list above.
        let unseen = model.popular.filter { city in !recents.contains { $0.id == city.id } }
        if !unseen.isEmpty {
            cityList("Popular destinations", cities: unseen)
        }
    }

    private func cityList(_ title: String, cities: [City]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
                .textCase(.uppercase)
                .tracking(0.6)

            ForEach(cities) { city in
                Button {
                    onSelect(city)
                } label: {
                    HStack(spacing: 14) {
                        PlacePhoto(seed: city.id, category: .attraction,
                                   showsGlyph: false, photoURL: city.photoURL)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.displayName).cardTitleStyle()
                            if !city.tagline.isEmpty {
                                Text(city.tagline).captionStyle().lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if selection?.id == city.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Brand.rausch)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func select(_ suggestion: CitySuggestion) {
        resolvingID = suggestion.id
        Task {
            defer { resolvingID = nil }
            if let city = await model.resolve(suggestion) {
                isFieldFocused = false
                onSelect(city)
            }
        }
    }
}
