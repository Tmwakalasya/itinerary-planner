import Foundation

/// Finds the best order for one day's stops.
///
/// The day keeps its time slots — the start times already planned, earliest
/// first — and the planner decides which stop takes which. A stop starts at
/// its slot unless you couldn't be there yet (the hop from the stop before
/// runs over) or the place opens a little later, and then it's pushed back to
/// when you could. Never earlier, so a lunch slot or a sunset slot survives;
/// it's the same contract as reordering by hand.
///
/// Orders are scored on what would go wrong first — a closed door, a visit
/// cut short by closing time, an outdoor stop in the dark — and on time spent
/// travelling or pushed back second, so a plan that works only changes when
/// the change is worth making. Every order is tried for a normal day, and an
/// order already worse than the best found is abandoned partway.
///
/// Rain isn't weighed: forecasts are daily, so no order is drier than another.
struct DayPlanner {

    struct Stop {
        var id: ItineraryStop.ID
        var duration: Int
        var isOutdoors: Bool
        /// The place's hours that day; nil when they aren't known.
        var hours: WeeklyHours.Day?
    }

    enum Problem: Equatable {
        /// Nothing opens that day. No order fixes this; another day might.
        case closedAllDay
        /// Shut when you'd arrive, and not opening soon enough to wait.
        case closedOnArrival
        /// Closes this many minutes before the visit would end.
        case closesEarly(by: Int)
        /// Outdoors for this many minutes before sunrise or after sunset.
        case inTheDark(minutes: Int)
    }

    struct Visit: Equatable {
        var id: ItineraryStop.ID
        var start: Int
        var problem: Problem?
    }

    struct Plan: Equatable {
        /// In the order they'd happen.
        var visits: [Visit]
        var travelMinutes: Int
        /// How far, in total, stops start after their slots.
        var pushedMinutes: Int
        /// Lower is better. Whole units, so ties are exact and the current
        /// order reliably wins them.
        var score: Int

        /// Problems a different order or time could fix; a place closed all
        /// day isn't one of them.
        var fixableProblems: Int {
            visits.filter { $0.problem != nil && $0.problem != .closedAllDay }.count
        }
    }

    var stops: [Stop]
    /// Planned start of each slot, earliest first; one per stop.
    var slots: [Int]
    /// Minutes between stops: `travel[i][j]` is from stop i to stop j.
    var travel: [[Int]]
    /// Minutes from where you're staying to each stop, and back again.
    var fromLodging: [Int]? = nil
    var toLodging: [Int]? = nil
    /// Nothing can start before this, e.g. when you're running late.
    var availableFrom: Int? = nil
    var sunrise: Int? = nil
    var sunset: Int? = nil

    /// The longest worth waiting for a place to open before calling it shut.
    static let longestWait = 90

    /// Past this many stops, orders are improved one move at a time rather
    /// than every one being tried.
    static let exhaustiveLimit = 9

    /// The stops in their current order, timed realistically.
    func current() -> Plan {
        finish(stops.indices.reduce(Progress(free: availableFrom)) { visit($1, after: $0) })
    }

    /// The best order found. The current one wins ties, so nothing moves
    /// without a reason.
    func best() -> Plan {
        guard stops.count > 1 else { return current() }
        return stops.count <= Self.exhaustiveLimit ? searchEveryOrder() : improveOneMoveAtATime()
    }

    // MARK: Search

    private func searchEveryOrder() -> Plan {
        var best = current()
        var used = Array(repeating: false, count: stops.count)

        func extend(_ progress: Progress) {
            // Scores only grow as stops are added, so this can't catch up.
            guard progress.score < best.score else { return }
            if progress.visits.count == stops.count {
                let plan = finish(progress)
                if plan.score < best.score { best = plan }
                return
            }
            for i in stops.indices where !used[i] {
                used[i] = true
                extend(visit(i, after: progress))
                used[i] = false
            }
        }

        extend(Progress(free: availableFrom))
        return best
    }

    private func improveOneMoveAtATime() -> Plan {
        var order = Array(stops.indices)
        var best = current()
        var improved = true
        while improved {
            improved = false
            for from in order.indices {
                for to in order.indices where to != from {
                    var candidate = order
                    candidate.insert(candidate.remove(at: from), at: to)
                    let plan = finish(candidate.reduce(Progress(free: availableFrom)) { visit($1, after: $0) })
                    if plan.score < best.score {
                        order = candidate
                        best = plan
                        improved = true
                    }
                }
            }
        }
        return best
    }

    // MARK: Timing one order

    private struct Progress {
        var visits: [Visit] = []
        var last: Int?
        /// When you're next free to start something.
        var free: Int?
        var travel = 0
        var pushed = 0
        var score = 0
    }

    /// Adds stop `i` in the next slot.
    private func visit(_ i: Int, after progress: Progress) -> Progress {
        var next = progress
        let stop = stops[i]
        let slot = slots[progress.visits.count]

        var hop = 0
        if let last = progress.last {
            hop = travel[last][i]
        } else if let fromLodging {
            hop = fromLodging[i]
        }
        // The first stop's time is the day's own start: the hop from where
        // you're staying shapes the order but doesn't push the clock.
        var start = slot
        if let free = progress.free {
            start = max(start, free + (progress.last == nil ? 0 : hop))
        }

        var problem: Problem?
        var penalty = 0
        var closes: Int?
        if let hours = stop.hours, !hours.isClosedAllDay {
            if let open = hours.span(containing: start) {
                closes = open.end
            } else if let opening = hours.nextOpening(after: start),
                      opening.start - start <= Self.longestWait {
                start = opening.start
                closes = hours.span(containing: opening.start)?.end
            } else {
                problem = .closedOnArrival
                penalty += 100_000
            }
        } else if stop.hours?.isClosedAllDay == true {
            // The same in every order, so it doesn't weigh on which is best.
            problem = .closedAllDay
        }

        // A pushed start lands on a round five minutes.
        if start > slot { start = (start + 4) / 5 * 5 }
        let end = start + stop.duration

        if let closes, end > closes {
            problem = problem ?? .closesEarly(by: end - closes)
            penalty += 20_000 + 1_000 * (end - closes)
        }
        if stop.isOutdoors {
            let dark = min(stop.duration,
                           max(0, end - (sunset ?? end)) + max(0, (sunrise ?? start) - start))
            if dark > 0 {
                problem = problem ?? .inTheDark(minutes: dark)
                penalty += 10_000 + 300 * dark
            }
        }

        // A minute of travel or delay costs 100; moving a stop from its own
        // slot costs 1, so ties keep yours.
        let moved = i == progress.visits.count ? 0 : 1

        next.visits.append(Visit(id: stop.id, start: start, problem: problem))
        next.last = i
        next.free = end
        next.travel += hop
        next.pushed += start - slot
        next.score += penalty + 100 * (hop + start - slot) + moved
        return next
    }

    private func finish(_ progress: Progress) -> Plan {
        var travel = progress.travel, score = progress.score
        if let last = progress.last, let toLodging {
            travel += toLodging[last]
            score += 100 * toLodging[last]
        }
        return Plan(visits: progress.visits, travelMinutes: travel,
                    pushedMinutes: progress.pushed, score: score)
    }
}
