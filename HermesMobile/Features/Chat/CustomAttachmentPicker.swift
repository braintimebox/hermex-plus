import ImageIO
import Observation
import Photos
import SwiftUI
import UIKit

struct HermexPickedMedia: Sendable {
    let data: Data
    let filename: String
}

private enum HermexAttachmentPickerMode: Equatable {
    case menu
    case camera
    case photos
}

enum HermexAttachmentPickerPolicy {
    static let maximumBotAttachments = 8
    static let maximumSessionImages = 10
    static let maximumVisiblePhotos = 180

    static func availableCapacity(existingCount: Int, maximum: Int = maximumBotAttachments) -> Int {
        max(0, maximum - existingCount)
    }

    static func toggledSelection(_ selected: [String], id: String, capacity: Int) -> [String] {
        if selected.contains(id) {
            return selected.filter { $0 != id }
        }
        guard selected.count < max(0, capacity) else { return selected }
        return selected + [id]
    }

    static func visibleSelection(_ selected: [String], visibleIDs: Set<String>) -> [String] {
        selected.filter(visibleIDs.contains)
    }

    static func confirmationLabel(count: Int) -> String {
        count == 1 ? String(localized: "Add 1 Photo") : String(localized: "Add \\(count) Photos")
    }
}

struct HermexAttachmentLifecycleFence {
    private(set) var activeID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        activeID = id
        return id
    }

    mutating func invalidate() {
        activeID = nil
    }

    mutating func consume(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }
}

private enum HermexPhotoLibraryStatus: Equatable {
    case idle
    case loading
    case denied
    case empty
    case ready(limited: Bool)
}

@MainActor
@Observable
private final class HermexAttachmentPickerModel {
    private(set) var libraryStatus: HermexPhotoLibraryStatus = .idle
    private(set) var assets: [PHAsset] = []
    private(set) var selectedAssetIDs: [String] = []
    private(set) var isPreparing = false
    private(set) var hasLimitedAccess = false
    var errorMessage: String?

    var selectionCount: Int { selectedAssetIDs.count }

    func loadLibrary() async {
        libraryStatus = .loading
        var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard authorization == .authorized || authorization == .limited else {
            assets = []
            selectedAssetIDs = []
            hasLimitedAccess = false
            libraryStatus = .denied
            return
        }
        hasLimitedAccess = authorization == .limited

        let options = PHFetchOptions()
        options.fetchLimit = HermexAttachmentPickerPolicy.maximumVisiblePhotos
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var loaded: [PHAsset] = []
        loaded.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in loaded.append(asset) }
        selectedAssetIDs = HermexAttachmentPickerPolicy.visibleSelection(
            selectedAssetIDs,
            visibleIDs: Set(loaded.map(\.localIdentifier))
        )
        assets = loaded
        libraryStatus = loaded.isEmpty ? .empty : .ready(limited: authorization == .limited)
    }

    func toggle(_ asset: PHAsset, capacity: Int) {
        let nextIDs = HermexAttachmentPickerPolicy.toggledSelection(
            selectedAssetIDs,
            id: asset.localIdentifier,
            capacity: capacity
        )
        guard nextIDs != selectedAssetIDs else { return }
        selectedAssetIDs = nextIDs
    }

    func clearSelection() {
        selectedAssetIDs = []
    }
}

/// A strip of attachments shown under the composer draft. The owner keeps files
/// alive from restore through upload, queueing and send.
struct HermexAttachmentStrip: View {
    let attachments: [HermexPickedMedia]
    let onRemove: (Int) -> Void

    var body: some View {
        if attachments.isEmpty { EmptyView() }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, media in
                        HermexAttachmentChip(media: media) {
                            onRemove(index)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 88)
        }
    }
}

struct HermexAttachmentChip: View {
    let media: HermexPickedMedia
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: UIImage(data: media.data) ?? UIImage())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
        }
    }
}

struct HermexAttachmentMenuRow: View {
    let title: Text
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                title
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HermexAttachmentPanelSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.systemBackground))
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

struct HermexAttachmentPickerLayoutMetrics {
    static func menuWidth(containerWidth: CGFloat) -> CGFloat {
        min(320, containerWidth - 32)
    }

    static var menuLeadingPadding: CGFloat { 16 }
}
