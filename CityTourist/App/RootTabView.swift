import SwiftUI

struct RootTabView: View {
    @State private var selection: TabID = .explore

    private enum TabID: Hashable { case explore, saved, trips, profile }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Explore", systemImage: "magnifyingglass", value: TabID.explore) {
                ExploreView()
            }
            Tab("Saved", systemImage: "heart", value: TabID.saved) {
                SavedView()
            }
            Tab("Trips", systemImage: "airplane", value: TabID.trips) {
                TripsView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: TabID.profile) {
                ProfileView()
            }
        }
        .tint(Brand.rausch)
    }
}

#Preview {
    RootTabView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
