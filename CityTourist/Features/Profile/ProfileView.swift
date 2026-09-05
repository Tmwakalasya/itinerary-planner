import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let account = store.account {
                        accountHeader(account)
                    } else {
                        signedOutHeader
                    }

                    settingsSection
                    aboutSection

                    if store.isSignedIn {
                        Button("Log out") { store.signOut() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .underline()
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Profile")
            .sheet(isPresented: $isSigningIn) { SignInSheet() }
        }
    }

    private func accountHeader(_ account: Account) -> some View {
        HStack(spacing: 16) {
            InitialsAvatar(initials: account.initials, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.ink)
                Text(account.email).metaStyle()
                Text("\(store.trips.count) trips · \(store.savedPlaceIDs.count) saved")
                    .captionStyle()
            }
            Spacer()
        }
    }

    private var signedOutHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log in to plan").displayStyle()
            Text("Save trips across your devices and share them with the people you're travelling with.")
                .metaStyle()
            PrimaryButton(title: "Log in or sign up") { isSigningIn = true }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").sectionTitleStyle().padding(.bottom, 8)
            row("Notifications", symbol: "bell") { store.requestNotificationPermission() }
            row("Offline downloads", symbol: "arrow.down.circle")
            row("Currency and units", symbol: "globe")
            row("Privacy", symbol: "lock")
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About").sectionTitleStyle().padding(.bottom, 8)
            row("How City Tourist works", symbol: "questionmark.circle")
            row("Give us feedback", symbol: "bubble.left")
            row("Terms and privacy policy", symbol: "doc.text")
        }
    }

    private func row(_ title: String, symbol: String, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                    Text(title).bodyStyle()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.vertical, 16)
                Hairline()
            }
        }
        .buttonStyle(.plain)
    }
}

/// Mock auth. The brief calls for Google and Apple SSO with email as a
/// fallback, so the three entry points are laid out the way they'd ship.
struct SignInSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var name = ""

    private var canContinue: Bool {
        email.contains("@") && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Log in or sign up").displayStyle()

                    VStack(spacing: 12) {
                        ssoButton("Continue with Apple", symbol: "apple.logo")
                        ssoButton("Continue with Google", symbol: "g.circle")
                    }

                    HStack(spacing: 12) {
                        Hairline()
                        Text("or").captionStyle()
                        Hairline()
                    }

                    VStack(spacing: 0) {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                            .padding(16)
                        Hairline()
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(16)
                    }
                    .bodyStyle()
                    .overlay {
                        RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    }

                    PrimaryButton(title: "Continue", isEnabled: canContinue) {
                        store.signIn(name: name.trimmingCharacters(in: .whitespaces), email: email)
                        dismiss()
                    }

                    Text("We'll only email you about trips you've asked us to remind you about.")
                        .captionStyle()
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 20)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private func ssoButton(_ title: String, symbol: String) -> some View {
        Button {
            store.signIn(name: "Alex Rivera", email: "alex@example.com")
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .overlay {
                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
