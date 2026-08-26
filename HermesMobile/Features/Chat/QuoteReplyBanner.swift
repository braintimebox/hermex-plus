import SwiftUI

struct QuoteReplyBanner: View {
    let author: String
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(author)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)

                Text(text)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(.leading, 13)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss quote")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}
