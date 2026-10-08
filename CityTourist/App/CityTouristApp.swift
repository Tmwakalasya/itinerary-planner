import SwiftUI

@main
struct CityTouristApp: App {
    /// The unit tests run inside this app. While they do, it stays idle: no
    /// saved state loaded into the shared directories, nothing written back,
    /// and no Explore feed spending Places quota on every test run.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    @State private var store = AppStore(loadFromDisk: !CityTouristApp.isRunningTests,
                                        seedDemoContent: !CityTouristApp.isRunningTests)
    @State private var catalog = PlaceCatalog()
    @State private var weather = WeatherStore()
    @State private var routes = RouteStore()
    @State private var events = EventCatalog()

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                Color.clear
            } else {
                RootTabView()
                    .environment(store)
                    .environment(catalog)
                    .environment(weather)
                    .environment(routes)
                    .environment(events)
                    .tint(Brand.rausch)
            }
        }
    }
}
