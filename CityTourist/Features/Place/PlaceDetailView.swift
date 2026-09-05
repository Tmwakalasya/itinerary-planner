import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isAddSheetPresented = false

    private var city: City { CityDirectory.city(id: place.cityID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 24) {
                    titleBlock
                    Hairline()
                    factsRow
                    Hairline()
                    aboutBlock
                    Hairline()
                    tagsBlock
                    Hairline()
                    mapBlock
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .background(Palette.canvas)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden()
        .overlay(alignment: .topLeading) { floatingControls }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $isAddSheetPresented) {
            AddToItinerarySheet(place: place)
        }
    }

    // MARK: Hero

    private var hero: some View {
        PlacePhoto(place: place)
            .frame(height: 380)
            .clipped()
    }

    private var floatingControls: some View {
        HStack {
            GlassCircleButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            HStack(spacing: 10) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                        .floatingShadow(y: 1, radius: 4, opacity: 0.18)
                }
                Button {
                    store.toggleSaved(place)
                } label: {
                    Image(systemName: store.isSaved(place) ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.isSaved(place) ? Brand.rausch : Palette.ink)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                        .floatingShadow(y: 1, radius: 4, opacity: 0.18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var shareText: String {
        "\(place.name) — \(place.blurb). Found it on City Tourist."
    }

    // MARK: Content

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place.name)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Palette.ink)
            Text("\(place.neighborhood), \(city.name)")
                .metaStyle()
            HStack(spacing: 6) {
                RatingLabel(rating: place.rating, reviewCount: place.reviewCount, size: 15)
            }
            .padding(.top, 2)

            if let status = place.openStatus {
                Label(status, systemImage: "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(place.isOpenNow == false ? Brand.rausch : Brand.babu)
                    .padding(.top, 4)
            }
        }
    }

    private var factsRow: some View {
        HStack(spacing: 0) {
            fact(symbol: "clock", title: place.durationLabel, subtitle: "Typical visit")
            fact(symbol: "creditcard", title: place.priceLabel, subtitle: "Entry")
            fact(symbol: place.category.symbol, title: place.category.title, subtitle: "Category")
        }
    }

    private func fact(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Palette.ink)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(subtitle).captionStyle()
        }
        .frame(maxWidth: .infinity)
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About this place").sectionTitleStyle()
            Text(place.about)
                .bodyStyle()
                .lineSpacing(4)
        }
    }

    private var tagsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good to know").sectionTitleStyle()
            FlowLayout(spacing: 8) {
                ForEach(place.tags, id: \.self) { tag in
                    Chip(title: tag)
                }
            }
        }
    }

    private var mapBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where you'll be").sectionTitleStyle()
            LookAroundBlock(coordinate: place.coordinate)
            Map(initialPosition: .region(MKCoordinateRegion(
                center: place.coordinate.clLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))) {
                Annotation(place.name, coordinate: place.coordinate.clLocation) {
                    MapPin(number: nil)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .allowsHitTesting(false)
            Text(place.neighborhood).metaStyle()
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        StickyBottomBar {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.durationLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("suggested").captionStyle()
                }
                Spacer()
                Button {
                    isAddSheetPresented = true
                } label: {
                    Text("Add to trip")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(height: 48)
                        .background(
                            LinearGradient(colors: [Brand.rausch, Brand.rauschDeep],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: SampleData.places[0])
            .environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
    }
}
