import Testing
import Foundation
import MapKit
@testable import CityTourist

@MainActor
struct DirectionsTests {
    private let origin = Coordinate(latitude: 38.7105, longitude: -9.1366)
    private let destination = Coordinate(latitude: 38.7139, longitude: -9.1334)

    @Test func routeRequestUsesTheSelectedOriginDestinationAndTravelMode() throws {
        let walking = try RouteService.directionsRequest(from: origin, to: destination, mode: .walking)
        #expect(walking.source?.placemark.coordinate.latitude == origin.latitude)
        #expect(walking.source?.placemark.coordinate.longitude == origin.longitude)
        #expect(walking.destination?.placemark.coordinate.latitude == destination.latitude)
        #expect(walking.destination?.placemark.coordinate.longitude == destination.longitude)
        #expect(walking.transportType == .walking)
        #expect(!walking.requestsAlternateRoutes)
        let driving = try RouteService.directionsRequest(from: origin, to: destination, mode: .driving)
        #expect(driving.transportType == .automobile)
    }

    @Test func transitIsNotSilentlyReplacedWithAWalk() {
        #expect(throws: RouteService.DirectionsError.self) {
            try RouteService.directionsRequest(from: origin, to: destination, mode: .transit)
        }
    }

    /// Today opens on the way the leave-by time was worked out, so a transit
    /// hop isn't previewed as a long walk.
    @Test func todayOpensDirectionsOnTheLegsWayOfGettingThere() {
        let transitLeg = TravelLeg(fromPlaceID: "here", toPlaceID: "museum", mode: .transit, seconds: 1_800)
        #expect(DirectionsView.startingMode(to: "museum", leg: transitLeg, gettingAround: .transit) == .transit)

        let walkLeg = TravelLeg(fromPlaceID: "here", toPlaceID: "museum", mode: .walking, seconds: 600)
        #expect(DirectionsView.startingMode(to: "museum", leg: walkLeg, gettingAround: .car) == .walking)

        #expect(DirectionsView.startingMode(to: "cafe", leg: transitLeg, gettingAround: .car) == .driving,
                "a leg to another stop doesn't count")
        #expect(DirectionsView.startingMode(to: "cafe", leg: nil, gettingAround: .transit) == .transit)
    }

    @Test func appleMapsOpensInTheChosenMode() {
        #expect(DirectionsView.mapsLaunchMode(for: .walking) == MKLaunchOptionsDirectionsModeWalking)
        #expect(DirectionsView.mapsLaunchMode(for: .transit) == MKLaunchOptionsDirectionsModeTransit)
        #expect(DirectionsView.mapsLaunchMode(for: .driving) == MKLaunchOptionsDirectionsModeDriving)
    }

    @Test func aLateWalkingResponseCannotReplaceTheNewDrivingRoute() async throws {
        let preview = DirectionsPreview()
        let walking = MKRoute(), driving = MKRoute()
        let pending = AsyncStream<CheckedContinuation<MKRoute, Error>>.makeStream()
        var iterator = pending.stream.makeAsyncIterator()
        let old = Task {
            await preview.load(from: origin, to: destination, mode: .walking) { _, _, _ in
                try await withCheckedThrowingContinuation { pending.continuation.yield($0) }
            }
        }
        let completion = try #require(await iterator.next())

        await preview.load(from: origin, to: destination, mode: .driving) { _, _, _ in driving }
        completion.resume(returning: walking)
        await old.value

        #expect(preview.route === driving)
        #expect(preview.state == .loaded)
        pending.continuation.finish()
    }

    @Test func failedReplacementClearsTheOldRouteAndOffersAnError() async throws {
        let preview = DirectionsPreview()
        await preview.load(from: origin, to: destination, mode: .walking) { _, _, _ in MKRoute() }
        let pending = AsyncStream<CheckedContinuation<MKRoute, Error>>.makeStream()
        var iterator = pending.stream.makeAsyncIterator()
        let replacement = Task {
            await preview.load(from: origin, to: destination, mode: .driving) { _, _, _ in
                try await withCheckedThrowingContinuation { pending.continuation.yield($0) }
            }
        }
        let completion = try #require(await iterator.next())
        #expect(preview.route == nil, "a walking line must not be labelled as driving")
        #expect(preview.state == .loading)
        completion.resume(throwing: RouteService.DirectionsError.noRoute)
        await replacement.value
        #expect(preview.route == nil)
        guard case .failed(let message) = preview.state else {
            Issue.record("An unavailable route needs a visible error")
            return
        }
        #expect(!message.isEmpty)
        pending.continuation.finish()
    }

    @Test func leavingThePreviewRejectsALateResponse() async throws {
        let preview = DirectionsPreview()
        let pending = AsyncStream<CheckedContinuation<MKRoute, Error>>.makeStream()
        var iterator = pending.stream.makeAsyncIterator()
        let task = Task {
            await preview.load(from: origin, to: destination, mode: .walking) { _, _, _ in
                try await withCheckedThrowingContinuation { pending.continuation.yield($0) }
            }
        }
        let completion = try #require(await iterator.next())
        preview.clear()
        completion.resume(returning: MKRoute())
        await task.value
        #expect(preview.state == .idle)
        #expect(preview.route == nil)
        pending.continuation.finish()
    }

    @Test func cancelledLookupDoesNotBecomeAnErrorOrRoute() async throws {
        let preview = DirectionsPreview()
        let pending = AsyncStream<CheckedContinuation<MKRoute, Error>>.makeStream()
        var iterator = pending.stream.makeAsyncIterator()
        let task = Task {
            await preview.load(from: origin, to: destination, mode: .walking) { _, _, _ in
                try await withCheckedThrowingContinuation { pending.continuation.yield($0) }
            }
        }
        let completion = try #require(await iterator.next())
        task.cancel()
        completion.resume(returning: MKRoute())
        await task.value
        #expect(preview.state == .idle)
        #expect(preview.route == nil)
        pending.continuation.finish()
    }

    @Test func anAlreadyCancelledLookupDoesNotContactTheProvider() async {
        let preview = DirectionsPreview()
        var called = false
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await preview.load(from: origin, to: destination, mode: .walking) { _, _, _ in
                called = true
                return MKRoute()
            }
        }
        await task.value
        #expect(!called)
        #expect(preview.state == .idle)
    }

    @Test func freshLocationIsAcceptedAndOldOrInvalidFixesAreRejected() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func fix(age: TimeInterval, accuracy: Double = 10) -> CLLocation {
            CLLocation(coordinate: origin.clLocation, altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: -1,
                       timestamp: now.addingTimeInterval(-age))
        }
        #expect(LocationProvider.isUsable(fix(age: 10), now: now))
        #expect(LocationProvider.isUsable(fix(age: 10, accuracy: 1_000), now: now),
                "an approximate fix is allowed and labelled in the UI")
        #expect(!LocationProvider.isUsable(fix(age: 121), now: now))
        #expect(!LocationProvider.isUsable(fix(age: -60), now: now))
        #expect(!LocationProvider.isUsable(fix(age: 0, accuracy: -1), now: now))
    }

    /// Opt in only for an explicit network smoke check. Ordinary test runs
    /// remain offline. The origin is a fixed public coordinate, not the user.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITYTOURIST_LIVE_DIRECTIONS_TEST"] == "1"),
          .timeLimit(.minutes(1)))
    func liveWalkingAndDrivingRoutesContainGeometryAndInstructions() async throws {
        for mode in [TravelMode.walking, .driving] {
            let route = try await RouteService().directions(from: origin, to: destination, mode: mode)
            #expect(route.polyline.pointCount > 2)
            #expect(route.distance > 0)
            #expect(route.expectedTravelTime > 0)
            #expect(route.steps.contains { !$0.instructions.isEmpty })
            #expect(route.transportType == (mode == .walking ? .walking : .automobile))
            print("Live \(mode.rawValue) route: \(route.polyline.pointCount) points, \(route.steps.count) steps, \(Int(route.distance)) metres")
        }
    }
}
