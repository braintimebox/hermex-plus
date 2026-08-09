import SwiftUI

struct ScheduleMessageSheet: View {
    let draftMessage: String
    let onSchedule: (Date) -> Void
    let onCancel: () -> Void

    @State private var scheduledDate = Date().addingTimeInterval(3600)

    var body: some View ...[truncated]