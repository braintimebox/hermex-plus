import SwiftUI

struct ScheduleMessageSheet: View {
    let draftMessage: String
    let onSchedule: (Date) -> Void
    let onCancel: () -> Void

    @State private var scheduledDate = Date().addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Send at",
                    selection: $scheduledDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()

                Text(draftMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal)
            }
            .navigationTitle("Schedule Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        onSchedule(scheduledDate)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
