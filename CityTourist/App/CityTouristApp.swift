import SwiftUI

@main
struct CityTouristApp: App {
    @State private var store = AppStore()
    @State private var catalog = PlaceCatalog()
    @State private var weather = WeatherStore()
    @State private var routes = RouteStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(catalog)
                .environment(weather)
                .environment(routes)
                .tint(Brand.rausch)
        }
    }
}
