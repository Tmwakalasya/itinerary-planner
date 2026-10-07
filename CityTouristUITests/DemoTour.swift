import XCTest

/// Not a test of correctness: a scripted walk through the app at a pace a
/// viewer can follow, for recording the demo video with
/// `Scripts/record-demo.sh`. The app launches with `-DemoTour`, which loads
/// a Lisbon trip that's under way (see `DemoTour` in the app).
final class DemoTour: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-DemoTour"]
    }

    func testTour() {
        app.launch()
        // The launch intro, then long enough on Trips to read today's card.
        XCTAssertTrue(button(startingWith: "Today").waitForExistence(timeout: 15))
        hold(5)

        // On the day: where it stands, what to fill the free time with, and
        // what running late does to the rest.
        tap(button(startingWith: "Today"))
        hold(3.5)
        app.swipeUp(velocity: .slow)
        hold(2)
        tap(button(startingWith: "Add "))              // a dinner spot for the free hours
        hold(2.5)
        app.swipeDown(velocity: .slow)
        hold(2)
        tap(button(containing: "Running late"))
        hold(2)
        tap(app.buttons["30 min"])
        hold(3)
        tap(button(containing: "Update today"))
        hold(3.5)

        // Tomorrow: a museum planned too late, a castle that's shut.
        back()
        hold(1.5)
        tap(button(startingWith: "Lisbon"))
        hold(2)
        tap(button(startingWith: "Day 2"))
        hold(3.5)
        tap(button(containing: "Fix this day"))
        hold(4)
        tap(button(startingWith: "Move it to"))
        hold(3)
        tap(button(containing: "Use this plan"))
        hold(4)

        // Finding places in the first place.
        back()
        hold(1)
        app.tabBars.buttons["Explore"].tap()
        hold(3.5)
        app.swipeUp(velocity: .slow)
        hold(2.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        hold(3)
        app.swipeUp(velocity: .slow)
        hold(3)
    }

    // MARK: Helpers

    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Couldn't find \(element)", file: file, line: line)
        element.tap()
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Long enough for a viewer to take in what just happened.
    private func hold(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
