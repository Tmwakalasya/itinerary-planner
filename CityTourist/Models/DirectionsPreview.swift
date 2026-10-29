import MapKit
import Observation

/// Owns one visible route preview. A late walking response must never replace
/// the driving route selected while it was loading.
@MainActor
@Observable
final class DirectionsPreview {
    enum State: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var route: MKRoute?
    private(set) var state: State = .idle
    @ObservationIgnored private var requestID = UUID()

    func load(from origin: Coordinate, to destination: Coordinate, mode: TravelMode,
              calculate: (Coordinate, Coordinate, TravelMode) async throws -> MKRoute = {
                  try await RouteService().directions(from: $0, to: $1, mode: $2)
              }) async {
        let id = UUID()
        requestID = id
        route = nil
        state = .loading
        do {
            try Task.checkCancellation()
            let result = try await calculate(origin, destination, mode)
            guard requestID == id else { return }
            try Task.checkCancellation()
            route = result
            state = .loaded
        } catch {
            guard requestID == id else { return }
            state = Task.isCancelled || error is CancellationError
                ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Invalidate even a response from a provider that ignores cancellation.
    /// The screen also cancels its task, which cancels the MapKit request.
    func clear() {
        requestID = UUID()
        route = nil
        state = .idle
    }
}
