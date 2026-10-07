import SwiftUI

/// Sharing, the brief's other headline feature: a public link anyone can open
/// without the app, the native OS share sheet, and named collaborators with a
/// view/edit permission each.
struct ShareTripSheet: View {
    let tripID: Trip.ID

    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var inviteEmail = ""
    @State private var didCopyLink = false
    @State private var isPreviewingGuestView = false

    private var trip: Trip? { store.trip(id: tripID) }

    private var unresolvedIDs: [String] {
        trip?.days.flatMap(\.stops).map(\.placeID)
            .filter { PlaceDirectory.place(id: $0) == nil } ?? []
    }

    private var isResolving: Bool {
        unresolvedIDs.contains { catalog.resolvingPlaceIDs.contains($0) }
    }

    /// The link carries the whole itinerary in its fragment, so it works with
    /// no backend — and a fragment is never sent to the host, so the plan
    /// stays out of server logs.
    private var shareURL: URL? {
        guard let trip else { return nil }
        return try? ShareLinkBuilder.url(
            trip: trip,
            city: CityDirectory.city(id: trip.cityID),
            resolve: { PlaceDirectory.place(id: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let trip {
                    VStack(alignment: .leading, spacing: 28) {
                        summary(trip)
                        linkBlock(trip)
                        collaboratorsBlock(trip)
                        inviteBlock
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, 20)
                }
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Share itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
            .sheet(isPresented: $isPreviewingGuestView) {
                if let trip { GuestItineraryView(trip: trip) }
            }
            .task(id: tripID) { await resolvePlaces() }
        }
    }

    // MARK: Blocks

    private func summary(_ trip: Trip) -> some View {
        HStack(spacing: 14) {
            PlacePhoto(seed: "trip-\(trip.cityID)", category: .attraction, showsGlyph: false,
                       photoURL: CityDirectory.city(id: trip.cityID).photoURL)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title).cardTitleStyle()
                Text("\(trip.dateRangeLabel) · \(trip.stopCount) stops").captionStyle()
            }
            Spacer()
        }
    }

    private func linkBlock(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Anyone with the link")
            Text("Opens in a browser — no account, no app install.")
                .captionStyle()
            Text("A snapshot of your plan. Share a new link after making changes.")
                .captionStyle()

            if !unresolvedIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(isResolving ? "Loading your places…" : "Some places couldn’t load",
                          systemImage: isResolving ? "clock" : "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text("All stops need to load before you can share the complete itinerary.")
                        .captionStyle()
                    if !isResolving {
                        Button("Try again") { Task { await resolvePlaces() } }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
            }

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                Text(trip.stopCount == 0 ? "Add a stop to create a link" : "Trip link")
                    .font(.subheadline)
                    .foregroundStyle(shareURL == nil ? Palette.inkMuted : Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let shareURL, Secrets.hasShareBaseURL {
                    Button {
                        UIPasteboard.general.string = shareURL.absoluteString
                        withAnimation { didCopyLink = true }
                    } label: {
                        Text(didCopyLink ? "Copied" : "Copy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))

            if let shareURL, ShareLinkBuilder.isOversized(shareURL) {
                Label("This itinerary is large, so the link is long — it may get cut short in some apps. Trimming a few stops helps.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.rausch)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !Secrets.hasShareBaseURL {
                Text("Link sharing is unavailable right now. You can still preview your itinerary.")
                    .captionStyle()
                    .foregroundStyle(Brand.rausch)
            }

            HStack(spacing: 12) {
                ShareLink(item: shareURL ?? URL(string: "https://example.invalid")!,
                          subject: Text(trip.title),
                          message: Text("Here's our \(trip.title) plan.")) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                        Text("Share").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(colors: [Brand.rausch, Brand.rauschDeep],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    )
                    .opacity(shareURL == nil || !Secrets.hasShareBaseURL ? 0.4 : 1)
                }
                // With no stops there's no link, only the placeholder above.
                .disabled(shareURL == nil || !Secrets.hasShareBaseURL)

                SecondaryButton(title: "Preview", systemImage: "eye") {
                    isPreviewingGuestView = true
                }
                .disabled(shareURL == nil)
            }
        }
    }

    private func collaboratorsBlock(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Travel companions")
            Text("Keep a local list of who’s coming. Share the trip link to send them the plan.")
                .captionStyle()
            if trip.collaborators.isEmpty {
                Text("Add someone below.")
                    .captionStyle()
            } else {
                ForEach(trip.collaborators) { collaborator in
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: collaborator.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collaborator.name).cardTitleStyle()
                            Text(collaborator.email).captionStyle().lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("Remove", role: .destructive) {
                            store.removeCollaborator(collaborator, from: tripID)
                        }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var inviteBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Add a companion")
            HStack(spacing: 10) {
                TextField("name@example.com", text: $inviteEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .bodyStyle()
                    .padding(14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            }
            PrimaryButton(title: "Add companion", isEnabled: isValidEmail) { invite() }
        }
    }

    // MARK: Actions

    private var isValidEmail: Bool {
        let trimmed = inviteEmail.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count > 5
    }

    private func invite() {
        let email = inviteEmail.trimmingCharacters(in: .whitespaces)
        // Until there's a directory to look names up in, derive one from the address.
        let name = email.split(separator: "@").first.map {
            $0.split(whereSeparator: { ".-_".contains($0) })
                .map(\.capitalized).joined(separator: " ")
        } ?? email
        store.addCollaborator(
            Collaborator(name: name, email: email, permission: .view),
            to: tripID
        )
        inviteEmail = ""
    }

    private func resolvePlaces() async {
        guard let trip else { return }
        await catalog.resolve(trip.days.flatMap(\.stops).map(\.placeID), cityID: trip.cityID)
    }
}
