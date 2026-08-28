import Foundation

enum MarkdownMathSegment: Equatable {
    case markdown(String)
    case displayMath(String)
}

enum MarkdownMathSegmenter {
    /// Memoized results keyed by content. `segments(in:)` is a pure function of
    /// `content`, but it does an O(N) `Array(content)` copy plus a full
    /// protection-mask scan on every call — and it runs inside `body` (both the
    /// static and streaming renderers call it per token flush, ~16ms). Caching
    /// by content removes the repeated O(N) work.
    ///
    /// F1 (scroll perf): a multi-entry (LRU) cache instead of a single entry so
    /// a fast scroll back through history (A→B→A) does NOT re-miss and re-scan a
    /// message that was already segmented. Bounded to avoid unbounded memory;
    /// results are value-type and cheap to hold. Lock-guarded because `body`
    /// can be evaluated off the main actor.
    private static let cacheLock = NSLock()
    private static var cache: [(content: String, result: [MarkdownMathSegment])] = []
    private static let cacheLimit = 24

    static func segments(in content: String) -> [MarkdownMathSegment] {
        // Fast path: read the cache, but do NOT hold the lock over the
        // O(N) compute (that would serialize any other caller). A miss may
        // race another thread computing the same content — harmless, both
        // produce the same value-type result.
        cacheLock.lock()
        for i in cache.indices where cache[i].content == content {
            let hit = cache[i].result
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let result = computeSegments(in: content)

        cacheLock.lock()
        if cache.count >= cacheLimit {
            cache.removeFirst()
        }
        cache.append((content: content, result: result))
        cacheLock.unlock()
        return result
    }

    private static func computeSegments(in content: String) -> [MarkdownMathSegment] {
        let characters = Array(content)
        guard characters.count >= 4 else {
            return [.markdown(MarkdownMathFormatter.replacingInlineMath(in: content))]
        }

        let protected = MarkdownMathProtection.mask(for: characters)
        var segments: [MarkdownMathSegment] = []
        var cursor = 0
        var index = 0

        while index < characters.count {
            guard let delimiter = displayDelimiter(in: characters, at: index, protected: protected),
                  let closeIndex = closingDisplayDelimiter(
                    in: characters,
                    from: index + delimiter.openLength,
                    protected: protected,
                    delimiter: delimiter
                  )
            else {
                index += 1
                continue
            }

            appendMarkdown(String(characters[cursor..<index]), to: &segments)
            let latex = String(characters[(index + delimiter.openLength)..<closeIndex])
            appendDisplayMath(latex, to: &segments)
            index = closeIndex + delimiter.closeLength
            cursor = index
        }

        appendMarkdown(String(characters[cursor...]), to: &segments)
        return segments.isEmpty ? [.markdown(MarkdownMathFormatter.replacingInlineMath(in: content))] : segments
    }

    private static func closingDisplayDelimiter(
        in characters: [Character],
        from startIndex: Int,
        protected: [Bool],
        delimiter: DisplayDelimiter
    ) -> Int? {
        var index = startIndex
        while index < characters.count {
            if delimiter.isClose(in: characters, at: index, protected: protected) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func displayDelimiter(
        in characters: [Character],
        at index: Int,
        protected: [Bool]
    ) -> DisplayDelimiter? {
        for delimiter in DisplayDelimiter.allCases where delimiter.isOpen(in: characters, at: index, protected: protected) {
            return delimiter
        }
        return nil
    }

    private static func appendMarkdown(
        _ markdown: String,
        to segments: inout [MarkdownMathSegment]
    ) {
        let rendered = MarkdownMathFormatter.replacingInlineMath(in: markdown)
        guard !rendered.isEmpty else { return }
        segments.append(.markdown(rendered))
    }

    private static func appendDisplayMath(
        _ latex: String,
        to segments: inout [MarkdownMathSegment]
    ) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments.append(.displayMath(trimmed))
    }
}

private enum DisplayDelimiter: CaseIterable {
    case dollars
    case brackets

    var openLength: Int {
        switch self {
        case .dollars, .brackets:
            return 2
        }
    }

    var closeLength: Int {
        switch self {
        case .dollars, .brackets:
            return 2
        }
    }

    func isOpen(in characters: [Character], at index: Int, protected: [Bool]) -> Bool {
        switch self {
        case .dollars:
            return matches("$$", in: characters, at: index, protected: protected)
                && !MarkdownMathProtection.isEscaped(characters, at: index)
        case .brackets:
            return matches(#"\["#, in: characters, at: index, protected: protected)
                && !MarkdownMathProtection.isEscaped(characters, at: index)
        }
    }

    func isClose(in characters: [Character], at index: Int, protected: [Bool]) -> Bool {
        switch self {
        case .dollars:
            return matches("$$", in: characters, at: index, protected: protected)
                && !MarkdownMathProtection.isEscaped(characters, at: index)
        case .brackets:
            return matches(#"\]"#, in: characters, at: index, protected: protected)
                && !MarkdownMathProtection.isEscaped(characters, at: index)
        }
    }

    private func matches(
        _ token: String,
        in characters: [Character],
        at index: Int,
        protected: [Bool]
    ) -> Bool {
        let tokenCharacters = Array(token)
        guard index >= 0, index + tokenCharacters.count <= characters.count else { return false }
        for offset in 0..<tokenCharacters.count where protected[index + offset] {
            return false
        }
        return Array(characters[index..<(index + tokenCharacters.count)]) == tokenCharacters
    }
}

enum MarkdownMathProtection {
    static func mask(for characters: [Character]) -> [Bool] {
        let fenced = fencedCodeMask(for: characters)
        let inline = inlineCodeMask(for: characters, existingMask: fenced)
        return zip(fenced, inline).map { $0 || $1 }
    }

    static func isEscaped(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return false }

        var backslashCount = 0
        var cursor = index - 1
        while cursor >= 0, characters[cursor] == "\\" {
            backslashCount += 1
            if cursor == 0 { break }
            cursor -= 1
        }

        return backslashCount % 2 == 1
    }

    private static func fencedCodeMask(for characters: [Character]) -> [Bool] {
        var mask = Array(repeating: false, count: characters.count)
        var lineStart = 0
        var fenceStart: Int?
        var fenceCharacter: Character?

        while lineStart < characters.count {
            let lineEnd = nextLineEnd(in: characters, from: lineStart)
            let nextLineStart = lineEnd < characters.count ? lineEnd + 1 : lineEnd

            if let opening = fenceOpening(in: characters, lineStart: lineStart, lineEnd: lineEnd) {
                if let start = fenceStart, opening.character == fenceCharacter {
                    mark(&mask, start..<nextLineStart)
                    fenceStart = nil
                    fenceCharacter = nil
                } else if fenceStart == nil {
                    fenceStart = lineStart
                    fenceCharacter = opening.character
                }
            }

            lineStart = nextLineStart
        }

        if let start = fenceStart {
            mark(&mask, start..<characters.count)
        }

        return mask
    }

    private static func inlineCodeMask(for characters: [Character], existingMask: [Bool]) -> [Bool] {
        var mask = Array(repeating: false, count: characters.count)
        var index = 0

        while index < characters.count {
            guard characters[index] == "`", !existingMask[index] else {
                index += 1
                continue
            }

            let runLength = backtickRunLength(in: characters, at: index)
            if let closeIndex = closingBacktickRun(
                in: characters,
                from: index + runLength,
                length: runLength,
                existingMask: existingMask
            ) {
                mark(&mask, index..<(closeIndex + runLength))
                index = closeIndex + runLength
            } else {
                index += runLength
            }
        }

        return mask
    }

    private static func fenceOpening(
        in characters: [Character],
        lineStart: Int,
        lineEnd: Int
    ) -> (character: Character, count: Int)? {
        var cursor = lineStart
        while cursor < lineEnd, characters[cursor].isWhitespace {
            cursor += 1
        }

        guard cursor + 2 < lineEnd else { return nil }
        let candidate = characters[cursor]
        guard candidate == "`" || candidate == "~" else { return nil }

        var count = 0
        while cursor + count < lineEnd, characters[cursor + count] == candidate {
            count += 1
        }

        return count >= 3 ? (candidate, count) : nil
    }

    private static func closingBacktickRun(
        in characters: [Character],
        from startIndex: Int,
        length: Int,
        existingMask: [Bool]
    ) -> Int? {
        var index = startIndex
        while index < characters.count {
            if characters[index] == "`", !existingMask[index], backtickRunLength(in: characters, at: index) == length {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func backtickRunLength(in characters: [Character], at index: Int) -> Int {
        var count = 0
        while index + count < characters.count, characters[index + count] == "`" {
            count += 1
        }
        return count
    }

    private static func nextLineEnd(in characters: [Character], from startIndex: Int) -> Int {
        var index = startIndex
        while index < characters.count, characters[index] != "\n" {
            index += 1
        }
        return index
    }

    private static func mark(_ mask: inout [Bool], _ range: Range<Int>) {
        for index in range where mask.indices.contains(index) {
            mask[index] = true
        }
    }
}

extension [MarkdownMathSegment] {
    var containsMath: Bool {
        contains {
            if case .displayMath = $0 { return true }
            return false
        }
    }
}
