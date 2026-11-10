// Excerpt from Studio's AppState.swift: the smart scheduler.
// Shared as a code sample. The full app source is private.
//
// Studio doesn't just list tasks by due date. It picks a day to WORK on each
// task, so a Friday essay shows up on Tuesday, Wednesday or Thursday instead.
//
// Algorithm:
//   1. Take all incomplete, non-overdue tasks, earliest due date first.
//   2. For each task, choose the best day to schedule it:
//      - between today and the day before it's due
//      - within the user's "days ahead" window (default 7)
//      - prefer the day with the fewest tasks already assigned (lightest load)
//      - never go over the daily task limit unless every day is full
//      - break ties by distance to a target day set by the user's style
//        (strict = as early as possible, balanced = middle, relaxed = late)
//   3. Overdue tasks always show up today.

    private struct ScheduleEntry {
        let task: StudioTask
        let scheduledDate: Date
    }

    private func buildSchedule(
        for upcomingTasks: [StudioTask],
        from todayStart: Date,
        calendar: Calendar
    ) -> [ScheduleEntry] {

        let sorted = upcomingTasks.sorted { $0.dueDate < $1.dueDate }

        // Track how many tasks are assigned to each day (key = days from today)
        var dayLoad: [Int: Int] = [:]

        var entries: [ScheduleEntry] = []

        for task in sorted {
            let dueStart = calendar.startOfDay(for: task.dueDate)
            let daysUntilDue = calendar.dateComponents([.day], from: todayStart, to: dueStart).day ?? 0

            guard daysUntilDue >= 0 else { continue }

            // Schedule at least 1 day before the due date when possible.
            // If due today (daysUntilDue == 0) it's already overdue-adjacent — schedule today.
            let latestOffset = max(0, daysUntilDue - 1)
            let earliestOffset = max(0, latestOffset - max(schedulerPrefs.daysAheadWindow - 1, 0))

            let offsets = Array(earliestOffset...latestOffset)
            let targetOffset: Double

            switch schedulingStrictness {
            case .strict:   targetOffset = Double(earliestOffset)
            case .balanced: targetOffset = Double(earliestOffset + latestOffset) / 2.0
            case .relaxed:  targetOffset = Double(latestOffset)
            }

            let bestDayOffset = offsets.min { lhs, rhs in
                let lhsLoad = dayLoad[lhs] ?? 0
                let rhsLoad = dayLoad[rhs] ?? 0

                let lhsOverLimit = lhsLoad >= schedulerPrefs.dailyTaskLimit
                let rhsOverLimit = rhsLoad >= schedulerPrefs.dailyTaskLimit
                if lhsOverLimit != rhsOverLimit {
                    return !lhsOverLimit
                }

                if lhsLoad != rhsLoad {
                    return lhsLoad < rhsLoad
                }

                let lhsDistance = abs(Double(lhs) - targetOffset)
                let rhsDistance = abs(Double(rhs) - targetOffset)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }

                return lhs < rhs
            } ?? latestOffset

            dayLoad[bestDayOffset] = (dayLoad[bestDayOffset] ?? 0) + 1

            if let scheduledDate = calendar.date(byAdding: .day, value: bestDayOffset, to: todayStart) {
                entries.append(ScheduleEntry(task: task, scheduledDate: scheduledDate))
            }
        }

