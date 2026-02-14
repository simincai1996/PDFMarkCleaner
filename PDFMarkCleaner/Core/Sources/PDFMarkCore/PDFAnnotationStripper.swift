import Foundation
import PDFKit

/// PDF 注释类型数据模型（无 UI 依赖），供 macOS / iOS 共用。
public enum AnnotationKind: String, CaseIterable, Identifiable, Sendable {
    case ink
    case highlight
    case underline
    case strikeOut
    case text
    case freeText
    case stamp
    case square
    case circle
    case line
    case link
    case widget
    case fileAttachment
    case popup
    case caret
    case squiggly
    case polygon
    case polyLine
    case sound

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ink: return "Ink"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikeOut: return "Strikeout"
        case .text: return "Text"
        case .freeText: return "FreeText"
        case .stamp: return "Stamp"
        case .square: return "Square"
        case .circle: return "Circle"
        case .line: return "Line"
        case .link: return "Link"
        case .widget: return "Widget"
        case .fileAttachment: return "File Attachment"
        case .popup: return "Popup"
        case .caret: return "Caret"
        case .squiggly: return "Squiggly"
        case .polygon: return "Polygon"
        case .polyLine: return "PolyLine"
        case .sound: return "Sound"
        }
    }

    /// 系统图标名称（SF Symbols），供 UI 渲染类型图标。
    public var symbolName: String {
        switch self {
        case .ink: return "pencil.tip"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikeOut: return "strikethrough"
        case .text: return "text.bubble"
        case .freeText: return "textformat"
        case .stamp: return "checkmark.seal"
        case .square: return "square"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .link: return "link"
        case .widget: return "slider.horizontal.3"
        case .fileAttachment: return "paperclip"
        case .popup: return "bubble.left"
        case .caret: return "chevron.up"
        case .squiggly: return "scribble"
        case .polygon: return "hexagon"
        case .polyLine: return "waveform.path"
        case .sound: return "speaker.wave.2"
        }
    }

    var tokens: [String] {
        switch self {
        case .ink: return ["ink"]
        case .highlight: return ["highlight"]
        case .underline: return ["underline"]
        case .strikeOut: return ["strikeout"]
        case .text: return ["text"]
        case .freeText: return ["freetext"]
        case .stamp: return ["stamp"]
        case .square: return ["square"]
        case .circle: return ["circle"]
        case .line: return ["line"]
        case .link: return ["link"]
        case .widget: return ["widget"]
        case .fileAttachment: return ["fileattachment"]
        case .popup: return ["popup"]
        case .caret: return ["caret"]
        case .squiggly: return ["squiggly"]
        case .polygon: return ["polygon"]
        case .polyLine: return ["polyline"]
        case .sound: return ["sound"]
        }
    }

    func matches(normalizedType: String) -> Bool {
        tokens.contains(normalizedType)
    }
}

/// 清理流程的错误类型，供上层 UI 做提示与状态更新。
public enum StripError: LocalizedError {
    case openFailed
    case emptyDocument
    case saveFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .openFailed: return "Failed to open PDF."
        case .emptyDocument: return "PDF has no pages."
        case .saveFailed: return "Failed to save PDF."
        case .cancelled: return "Operation cancelled."
        }
    }
}

/// 纯 PDF 处理逻辑：判断、统计、移除注释。
public struct PDFAnnotationStripper {
    private static let slashSet = CharacterSet(charactersIn: "/")

    private static func normalize(_ type: String) -> String {
        type
            .trimmingCharacters(in: slashSet)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    /// 兼容不同来源的注释类型字段：
    /// - 常规注释通常在 `type`
    /// - 某些签名注释会在 `widgetFieldType` 中使用 /Sig
    private static func normalizedTypeCandidates(for annot: PDFAnnotation) -> [String] {
        var candidates: [String] = []

        if let type = annot.type {
            let normalized = normalize(type)
            if !normalized.isEmpty {
                candidates.append(normalized)
            }
        }

        let widgetFieldType = annot.widgetFieldType.rawValue
        if !widgetFieldType.isEmpty {
            let normalized = normalize(widgetFieldType)
            if !normalized.isEmpty {
                candidates.append(normalized)
                if normalized == "sig" {
                    candidates.append("signature")
                }
            }
        }

        if candidates.contains("sig") || candidates.contains("signature") {
            // 某些签名会落在不同注释类型，补齐常见别名避免漏删。
            candidates.append("widget")
            candidates.append("stamp")
            candidates.append("ink")
        }

        var seen = Set<String>()
        var unique: [String] = []
        for candidate in candidates where seen.insert(candidate).inserted {
            unique.append(candidate)
        }
        return unique
    }

    public static func shouldRemove(_ annot: PDFAnnotation, selectedTypes: Set<AnnotationKind>) -> Bool {
        if selectedTypes.isEmpty { return false }
        let candidates = normalizedTypeCandidates(for: annot)
        guard !candidates.isEmpty else { return false }
        return selectedTypes.contains { kind in
            candidates.contains { kind.matches(normalizedType: $0) }
        }
    }

    public static func removeAnnotations(in page: PDFPage, selectedTypes: Set<AnnotationKind>) {
        for annot in page.annotations where shouldRemove(annot, selectedTypes: selectedTypes) {
            page.removeAnnotation(annot)
        }
    }

    public static func kind(for annot: PDFAnnotation) -> AnnotationKind? {
        for normalized in normalizedTypeCandidates(for: annot) {
            if let kind = AnnotationKind.allCases.first(where: { $0.matches(normalizedType: normalized) }) {
                return kind
            }
        }
        return nil
    }

    /// 执行注释清理并写出新 PDF：
    /// - parameters:
    ///   - pagesToProcess: 传 `nil` 表示处理全部页面，否则按 1-based 页码集合处理。
    public static func strip(
        input: URL,
        output: URL,
        selectedTypes: Set<AnnotationKind>,
        pagesToProcess: Set<Int>?,
        progress: @escaping (Double) -> Void,
        shouldCancel: (() -> Bool)? = nil
    ) throws {
        guard let doc = PDFDocument(url: input) else { throw StripError.openFailed }
        let total = doc.pageCount
        if total == 0 { throw StripError.emptyDocument }

        progress(0)
        let processAll = pagesToProcess == nil
        let pageSet = pagesToProcess ?? []

        for index in 0..<total {
            if shouldCancel?() == true {
                throw StripError.cancelled
            }

            autoreleasepool {
                guard let page = doc.page(at: index) else { return }
                let pageNumber = index + 1
                if processAll || pageSet.contains(pageNumber) {
                    removeAnnotations(in: page, selectedTypes: selectedTypes)
                }
            }

            let p = Double(index + 1) / Double(total)
            progress(p)
        }

        if !doc.write(to: output) { throw StripError.saveFailed }
    }
}
