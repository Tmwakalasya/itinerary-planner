import SwiftUI

/// Sharing, the brief's other headline feature: a public link anyone can open
/// without the app, the native OS share sheet, and named collaborators with a
/// view/edit permission each.
struct ShareTripSheet: View {
    let tripID: Trip.ID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var inviteEmail = ""
    @State private var invitePermission: SharePermission = .view
    @State private var didCopyLink = false
    @State private var isPreviewingGuestView = false

    private var trip: Trip? { store.trip(id: tripID) }

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

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                Text(shareURL?.absoluteString ?? "Add a stop to create a link")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(shareURL == nil ? Palette.inkMuted : Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let shareURL {
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
                Text("Set ShareBaseURL in Secrets.plist to your deployed viewer, or these links won't resolve.")
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
                    .opacity(shareURL == nil ? 0.4 : 1)
                }
                // With no stops there's no link, only the placeholder above.
                .disabled(shareURL == nil)

                SecondaryButton(title: "Preview", systemImage: "eye") {
                    isPreviewingGuestView = true
                }
                .disabled(shareURL == nil)
            }
        }
    }

    private func collaboratorsBlock(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "People with access")
            if trip.collaborators.isEmpty {
                Text("No one yet. Invite someone below to let them edit the plan with you.")
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
                        Menu {
                            ForEach(SharePermission.allCases) { permission in
                                Button(permission.title) { setPermission(permission, for: collaborator) }
                            }
                            Divider()
                            Button("Remove", role: .destructive) {
                                store.removeCollaborator(collaborator, from: tripID)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(collaborator.permission.title)
                                    .font(.system(size: 14, weight: .medium))
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Palette.ink)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var inviteBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Invite by email")
            HStack(spacing: 10) {
                TextField("name@example.com", text: $inviteEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .bodyStyle()
                    .padding(14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Picker("", selection: $invitePermission) {
                    ForEach(SharePermission.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Palette.ink)
            }
            PrimaryButton(title: "Send invite", isEnabled: isValidEmail) { invite() }
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
            Collaborator(name: name, email: email, permission: invitePermission),
            to: tripID
        )
        inviteEmail = ""
    }

    private func setPermission(_ permission: SharePermission, for collaborator: Collaborator) {
        guard var trip, let index = trip.collaborators.firstIndex(where: { $0.id == collaborator.id })
        else { return }
        trip.collaborators[index].permission = permission
        store.update(trip)
    }
}
