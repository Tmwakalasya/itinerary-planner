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
/// travelling or pushed back second. Moving a stop out of its slot has to be
/// worth a quarter of an hour of travel, so a day isn't reshuffled for small
/// savings, and a stop shut all day stays where it is: no order opens it.
/// Every order is tried for a normal day, and an order already worse than the
/// best found is abandoned partway.
///
/// A booked stop is held to its slot and its time, like a stop shut all day:
/// the booking says the place takes you then, whatever its regular hours or
/// the daylight say, so the only thing that can go wrong is arriving late.
///
/// Rain isn't weighed: forecasts are daily, so no order is drier than another.
struct DayPlanner {

    struct Stop {
        var id: ItineraryStop.ID
        var duration: Int
        var isOutdoors: Bool
        /// The place's hours that day; nil when they aren't known.
        var hours: WeeklyHours.Day?
        /// Meals are held to their planned time: breakfast at three in the
        /// afternoon isn't a better day, however much walking it saves.
        var isMeal = false
        /// A reservation or timed ticket: it keeps its slot and its time.
        var isBooked = false
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
        /// Booked for a time you'd reach this many minutes after.
        case lateForBooking(by: Int)
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

        var lateBookings: Int {
            visits.filter { visit in
                if case .lateForBooking = visit.problem { return true }
                return false
            }.count
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

    /// Past this many stops, orders are improved one swap at a time rather
    /// than every one being tried.
    static let exhaustiveLimit = 9

    /// What moving a stop out of its own slot costs, in the planner's units:
    /// 100 is a minute of travel or delay.
    static let moveCost = 1_500
    /// What each minute a meal drifts from its planned time costs.
    static let mealDriftCost = 50

    /// Booked stops and stops shut all day keep their own slot.
    private var pinned: Set<Int> {
        Set(stops.indices.filter { stops[$0].isBooked || stops[$0].hours?.isClosedAllDay == true })
    }

    /// The stops in their current order, timed realistically.
    func current() -> Plan {
        finish(stops.indices.reduce(Progress(free: availableFrom)) { visit($1, after: $0) })
    }

    /// The best order found. The current one wins ties, so nothing moves
    /// without a reason.
    func best() -> Plan {
        guard stops.count > 1 else { return current() }
        return stops.count <= Self.exhaustiveLimit ? searchEveryOrder() : improveBySwapping()
    }

    // MARK: Search

    private func searchEveryOrder() -> Plan {
        var best = current()
        var used = Array(repeating: false, count: stops.count)
        let pinned = pinned

        func extend(_ progress: Progress) {
            // Scores only grow as stops are added, so this can't catch up.
            guard progress.score < best.score else { return }
            if progress.visits.count == stops.count {
                let plan = finish(progress)
                if plan.score < best.score { best = plan }
                return
            }
            let slot = progress.visits.count
            let candidates = pinned.contains(slot) ? [slot] : stops.indices.filter { !pinned.contains($0) }
            for i in candidates where !used[i] {
                used[i] = true
                extend(visit(i, after: progress))
                used[i] = false
            }
        }

        extend(Progress(free: availableFrom))
        return best
    }

    /// Swaps rather than moves, so stops in between keep their slots and a
    /// pinned stop is never shifted.
    private func improveBySwapping() -> Plan {
        var order = Array(stops.indices)
        var best = current()
        let free = stops.indices.filter { !pinned.contains($0) }
        var improved = true
        while improved {
            improved = false
            for a in free {
                for b in free where b > a {
                    var candidate = order
                    candidate.swapAt(a, b)
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
        var late = 0
        if let free = progress.free {
            let arrival = free + (progress.last == nil ? 0 : hop)
            if stop.isBooked {
                late = max(0, arrival - slot)
            } else {
                start = max(start, arrival)
            }
        }

        var problem: Problem?
        var penalty = 0
        var closes: Int?
        if stop.isBooked {
            if late > 0 {
                problem = .lateForBooking(by: late)
                penalty += 20_000 + 1_000 * late
            }
        } else if let hours = stop.hours, !hours.isClosedAllDay {
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
        if stop.isOutdoors && !stop.isBooked {
            let dark = min(stop.duration,
                           max(0, end - (sunset ?? end)) + max(0, (sunrise ?? start) - start))
            if dark > 0 {
                problem = problem ?? .inTheDark(minutes: dark)
                penalty += 10_000 + 300 * dark
            }
        }

        // A minute of travel or delay costs 100. Leaving its own slot costs a
        // stop a quarter of an hour's worth, and a meal more the further it
        // drifts, so the current order keeps ties and wins small differences.
        let moved = i == progress.visits.count ? 0 : Self.moveCost
        let drift = stop.isMeal ? Self.mealDriftCost * abs(start - slots[i]) : 0

        next.visits.append(Visit(id: stop.id, start: start, problem: problem))
        next.last = i
        next.free = end
        next.travel += hop
        next.pushed += start - slot
        next.score += penalty + 100 * (hop + start - slot) + moved + drift
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
