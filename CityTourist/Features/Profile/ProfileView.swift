import SwiftUI
import UserNotifications

/// Settings for this phone. There are no accounts yet, so trips and saved
/// places live on the device; this says so rather than offering a sign-in
/// that does nothing.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var copiedFeedbackAddress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("\(count(store.trips.count, "trip")) and \(count(store.savedPlaceIDs.count, "saved place")), kept on this \(UIDevice.current.model).")
                        .metaStyle()

                    settingsSection
                    aboutSection
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Settings")
        }
    }

    private var settingsSection: some View {
        row("Notifications", symbol: "bell") { openNotificationSettings() }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About").sectionTitleStyle().padding(.bottom, 8)
            if let feedbackURL, let address = Secrets.feedbackEmail {
                row("Send feedback", symbol: "bubble.left") {
                    // Without a mail app the link goes nowhere; hand over the address instead.
                    openURL(feedbackURL) { accepted in
                        guard !accepted else { return }
                        UIPasteboard.general.string = address
                        copiedFeedbackAddress = true
                    }
                }
                if copiedFeedbackAddress {
                    Text("No mail app here, so the address is copied: \(address)").captionStyle().padding(.top, 8)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("City Tourist \(Self.version) · Beta").captionStyle()
                Text("Places and opening hours from Google. Events from Ticketmaster. Weather from Open-Meteo. Travel times from Apple Maps.")
                    .captionStyle()
            }
            .padding(.top, 16)
        }
    }

    /// The first time, asks; after that, iOS only lets the Settings app
    /// change the answer.
    private func openNotificationSettings() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                store.requestNotificationPermission()
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }

    /// An email with the build already in it, when a feedback address is set.
    private var feedbackURL: URL? {
        guard let address = Secrets.feedbackEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "City Tourist beta feedback"),
            URLQueryItem(name: "body", value: "\n\n\nCity Tourist \(Self.version), iOS \(UIDevice.current.systemVersion)")
        ]
        return components.url
    }

    /// "1.0 (3)": the version and the build, so feedback says which one.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

#Preview {
    ProfileView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
