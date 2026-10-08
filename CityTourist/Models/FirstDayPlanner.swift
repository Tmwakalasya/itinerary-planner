import Foundation

/// Selects places and checks their timetable together. A small, deterministic
/// greedy search: each addition must leave the whole proposed day feasible.
/// This is a daytime starter itinerary, with one lunch and no ticketed events.
struct FirstDayPlanner {
    enum Pace: String, CaseIterable, Identifiable {
        case relaxed, balanced, busy
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var slots: [Int] {
            switch self {
            case .relaxed: [600, 780, 900]
            case .balanced: [570, 660, 780, 900]
            case .busy: [540, 645, 780, 870, 990]
            }
        }
        var buffer: Int { self == .relaxed ? 30 : self == .balanced ? 20 : 10 }
    }

    struct Suggestion: Identifiable {
        var place: Place
        var start: Int
        var reason: String
        var id: String { place.id }
        var stop: ItineraryStop {
            ItineraryStop(placeID: place.id, startMinute: start, durationMinutes: place.typicalMinutes)
        }
    }

    var city: City
    var date: Date
    var interests: Set<PlaceCategory>
    var pace: Pace
    /// Earliest departure from the city centre; for today, never in the past.
    var availableFrom: Int = 9 * 60
    var calendar: Calendar = .current

    static let interests: [PlaceCategory] = [.attraction, .museum, .nature, .activity, .food]
    static let dayEnds = 18 * 60

    func propose(among places: [Place], mustSee: Place? = nil) -> [Suggestion] {
        let candidates = eligible(places)
        var result: [Suggestion] = []
        var anchorSlot: Int?
        if let mustSee {
            guard candidates.contains(where: { $0.id == mustSee.id }) else { return [] }
            for slot in pace.slots where (slot == 780) == (mustSee.category == .food) {
                if let anchor = scheduled([Suggestion(place: mustSee, start: slot, reason: "Your must-see")]) {
                    result = anchor
                    anchorSlot = slot
                    break
                }
            }
            guard anchorSlot != nil else { return [] }
        }
        for slot in pace.slots {
            // The anchor already occupies one of the pace's slots.
            if slot == anchorSlot { continue }
            let isLunch = slot == 780
            let used = Set(result.map(\.id))
            let options = candidates.filter {
                !used.contains($0.id) && ($0.category == .food) == isLunch
                    && (isLunch || interests.contains($0.category))
            }
            var best: (plan: [Suggestion], score: Double)?
            for place in options {
                let reason = isLunch ? "A lunch break along your route" : "Matches your \(place.category.title.lowercased()) interest"
                let draft = result + [Suggestion(place: place, start: slot, reason: reason)]
                guard let plan = scheduled(draft.sorted { $0.start < $1.start }) else { continue }
                let score = quality(place) - Double(travel(plan) - travel(result)) * 1.5
                if best == nil || score > best!.score { best = (plan, score) }
            }
            if let best { result = best.plan }
        }
        return result
    }

    /// Replace just this stop. All other places and start times remain intact;
    /// if no alternative fits both neighbours, keep the current proposal.
    func replacing(_ id: String, in proposal: [Suggestion], among places: [Place],
                   excluding: Set<String> = []) -> [Suggestion]? {
        guard let index = proposal.firstIndex(where: { $0.id == id }) else { return nil }
        let old = proposal[index]
        let used = Set(proposal.map(\.id)).union(excluding)
        let options = eligible(places).filter {
            !used.contains($0.id) && ($0.category == .food) == (old.place.category == .food)
                && ($0.category == .food || interests.contains($0.category))
        }
        var best: (plan: [Suggestion], score: Double)?
        for place in options {
            var draft = proposal
            draft[index] = Suggestion(place: place, start: old.start,
                                      reason: place.category == .food ? "A lunch break along your route"
                                      : "Matches your \(place.category.title.lowercased()) interest")
            guard let checked = scheduled(draft),
                  zip(checked, draft).allSatisfy({ $0.start == $1.start }) else { continue }
            let score = quality(place) - Double(travel(checked)) * 1.5
            if best == nil || score > best!.score { best = (checked, score) }
        }
        return best?.plan
    }

    private func eligible(_ places: [Place]) -> [Place] {
        var seen: Set<String> = []
        return places.filter {
            $0.cityID == city.id && $0.event == nil && $0.category != .nightlife
                && $0.typicalMinutes > 0 && seen.insert($0.id).inserted
        }.sorted { $0.id < $1.id }
    }

    private func quality(_ place: Place) -> Double {
        // Shrink sparse ratings toward 4.0 so one five-star review cannot
        // outrank hundreds of strong reviews by itself.
        let count = Double(max(0, place.reviewCount))
        return ((place.rating * count + 4 * 50) / (count + 50)) * 20
    }

    private func travel(_ proposal: [Suggestion]) -> Int {
        var previous = city.coordinate
        return proposal.reduce(0) { total, suggestion in
            let hop = TravelEstimate.minutes(from: previous, to: suggestion.place.coordinate)
            previous = suggestion.place.coordinate
            return total + hop
        }
    }

    private func scheduled(_ draft: [Suggestion]) -> [Suggestion]? {
        guard !draft.isEmpty else { return [] }
        let weekday = calendar.component(.weekday, from: date) - 1
        let stops = draft.map { $0.stop }
        let travel = draft.enumerated().map { i, from in
            draft.enumerated().map { j, to in
                i == j ? 0 : TravelEstimate.minutes(from: from.place.coordinate, to: to.place.coordinate) + pace.buffer
            }
        }
        let firstHop = TravelEstimate.minutes(from: city.coordinate, to: draft[0].place.coordinate)
        let planner = DayPlanner(
            stops: zip(draft, stops).map { suggestion, stop in
                DayPlanner.Stop(id: stop.id, duration: stop.durationMinutes,
                                isOutdoors: suggestion.place.category.isOutdoors,
                                hours: suggestion.place.weeklyHours?.day(weekday),
                                isMeal: suggestion.place.category == .food)
            },
            slots: draft.map(\.start), travel: travel,
            availableFrom: availableFrom + firstHop
        )
        // Preserve slot order, including lunch. Selection explores candidates;
        // the existing planner supplies opening-time waits and conflict checks.
        let plan = planner.current()
        guard plan.visits.allSatisfy({ $0.problem == nil }) else { return nil }
        var result = draft
        for index in result.indices {
            let start = plan.visits[index].start
            let place = result[index].place
            guard start + place.typicalMinutes <= Self.dayEnds,
                  place.category != .food || (720...870).contains(start) else { return nil }
            result[index].start = start
        }
        return result
    }
}
