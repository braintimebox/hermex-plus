import Foundation

struct StreamingMarkdownChunk: Identifiable, Equatable {
    let id: Int
    let text: String
}

struct StreamingMarkdownBlockSegments: Equatable {
    let stableChunks: [StreamingMarkdownChunk]
    let activeMarkdown: String
}

enum StreamingMarkdownBlockSplitter {
    static let stableChunkTargetCharacterCount = 6_000

    /// Incremental scan state. During streaming the same content grows by
    /// append-only each token; re-scanning the WHOLE text from `startIndex`
    /// every frame is the O(N²) driver (the `CTLineCreateWithAttributedString`
    /// main-thread stall on long answers). This holds the resume cursor + the
    /// fence/chunk state so each call scans only the newly-appended bytes.
    ///
    /// Offsets are UTF-8 byte offsets — `String.Index` is tied to a specific
    /// `String` instance's representation and is not safely reusable across
    /// distinct instances that merely compare equal by value. Offsets convert
    /// back via `String.Index(utf8Offset:in:)`, always valid because every
    /// resume point is a line boundary (a character start).
    private struct ScanState {
        var previousText: String = ""
        var scannedUtf8: Int = 0
        var isInsideFence: Bool = false
        var chunkStartUtf8: Int = 0
        var stableChunks: [StreamingMarkdownChunk] = []
    }

    /// Single shared state, guarded like the old memo cache. One active stream
    /// per process is the norm; a non-append text resets the state below.
    private static let stateLock = NSLock()
    private static var state = ScanState()

    static func split(_ text: String) -> StreamingMarkdownBlockSegments {
        stateLock.lock()
        defer { stateLock.unlock() }

        // Append-only fast path: continue the scan from where we stopped.
        // Otherwise (replaced content / new stream / replayed slice) reset and
        // scan from scratch. `hasPrefix` is a cheap memcmp, not a line scan.
        let resumeUtf8: Int
        if !state.previousText.isEmpty, text.hasPrefix(state.previousText) {
            resumeUtf8 = state.scannedUtf8
        } else {
            state = ScanState()
            resumeUtf8 = 0
        }

        let result = scan(text, resumeUtf8: resumeUtf8)
        state.previousText = text
        return result
    }

    private static func scan(
        _ text: String,
        resumeUtf8: Int
    ) -> StreamingMarkdownBlockSegments {
        let utf8 = text.utf8
        let start = text.startIndex

        let resumeIndex = utf8.index(start, offsetBy: resumeUtf8)
        var lineStart = resumeIndex
        var chunkStartIndex = utf8.index(start, offsetBy: state.chunkStartUtf8)
        var isInsideFence = state.isInsideFence
        var stableChunks = state.stableChunks

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let nextLineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            let hasLineBreak = lineEnd < text.endIndex
            let trimmedLine = String(text[lineStart..<lineEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var stableBoundary: String.Index?
            if isFenceDelimiter(trimmedLine) {
                isInsideFence.toggle()
                if !isInsideFence {
                    stableBoundary = nextLineStart
                }
            } else if !isInsideFence, hasLineBreak {
                if trimmedLine.isEmpty || isStableSingleLineBlock(trimmedLine) {
                    stableBoundary = nextLineStart
                }
            }

            if let stableBoundary,
               shouldSealChunk(in: text, from: chunkStartIndex, to: stableBoundary) {
                appendChunk(in: text, from: chunkStartIndex, to: stableBoundary, into: &stableChunks)
                chunkStartIndex = stableBoundary
            }

            lineStart = nextLineStart
        }

        // Persist the cursor + fence/chunk state for the next append.
        state.scannedUtf8 = utf8.distance(from: start, to: text.endIndex)
        state.isInsideFence = isInsideFence
        state.chunkStartUtf8 = utf8.distance(from: start, to: chunkStartIndex)
        state.stableChunks = stableChunks

        return StreamingMarkdownBlockSegments(
            stableChunks: stableChunks,
            activeMarkdown: String(text[chunkStartIndex...])
        )
    }

    private static func shouldSealChunk(
        in text: String,
        from start: String.Index,
        to boundary: String.Index
    ) -> Bool {
        guard boundary < text.endIndex else { return false }
        return text.distance(from: start, to: boundary) >= stableChunkTargetCharacterCount
    }

    private static func appendChunk(
        in text: String,
        from start: String.Index,
        to end: String.Index,
        into chunks: inout [StreamingMarkdownChunk]
    ) {
        guard start < end else { return }
        let chunkText = String(text[start..<end])
        guard !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chunks.append(
            StreamingMarkdownChunk(
                id: chunks.count,
                text: chunkText
            )
        )
    }

    private static func isFenceDelimiter(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private static func isStableSingleLineBlock(_ trimmedLine: String) -> Bool {
        let headingMarkerCount = trimmedLine.prefix(while: { $0 == "#" }).count
        let isHeading = (1...6).contains(headingMarkerCount)
            && trimmedLine.dropFirst(headingMarkerCount).first?.isWhitespace == true
        return isHeading || trimmedLine == "---" || trimmedLine == "***"
    }
}
