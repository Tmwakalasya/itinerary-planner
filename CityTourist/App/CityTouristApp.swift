import SwiftUI

@main
struct CityTouristApp: App {
    /// The unit tests run inside this app. While they do, it stays idle: no
    /// saved state loaded into the shared directories, nothing written back,
    /// and no Explore feed spending Places quota on every test run.
    static let isRunningTests: Bool = {
        #if DEBUG
        // Driven by a UI test, but the app itself has to run as normal.
        if DemoTour.isActive { return false }
        #endif
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    @State private var store = CityTouristApp.makeStore()
    @State private var catalog = PlaceCatalog()
    @State private var weather = WeatherStore()
    @State private var routes = RouteStore()

    private static func makeStore() -> AppStore {
        #if DEBUG
        if DemoTour.isActive { return DemoTour.makeStore() }
        #endif
        return AppStore(loadFromDisk: !isRunningTests, seedDemoContent: !isRunningTests)
    }

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
                    .tint(Brand.rausch)
            }
        }
    }
}
