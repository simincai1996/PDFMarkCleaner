import Foundation
import PDFKit

enum AnnotationKind: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    var title: String {
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

enum StripError: LocalizedError {
    case openFailed
    case emptyDocument
    case saveFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .openFailed: return "Failed to open PDF."
        case .emptyDocument: return "PDF has no pages."
        case .saveFailed: return "Failed to save PDF."
        case .cancelled: return "Operation cancelled."
        }
    }
}

struct PDFAnnotationStripper {
    private static let slashSet = CharacterSet(charactersIn: "/")

    private static func normalize(_ type: String) -> String {
        type
            .trimmingCharacters(in: slashSet)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    static func shouldRemove(_ annot: PDFAnnotation, selectedTypes: Set<AnnotationKind>) -> Bool {
        if selectedTypes.isEmpty { return false }
        guard let type = annot.type else { return false }
        let normalized = normalize(type)
        return selectedTypes.contains { $0.matches(normalizedType: normalized) }
    }

    static func removeAnnotations(in page: PDFPage, selectedTypes: Set<AnnotationKind>) {
        for annot in page.annotations where shouldRemove(annot, selectedTypes: selectedTypes) {
            page.removeAnnotation(annot)
        }
    }

    static func kind(for annot: PDFAnnotation) -> AnnotationKind? {
        guard let type = annot.type else { return nil }
        let normalized = normalize(type)
        return AnnotationKind.allCases.first { $0.matches(normalizedType: normalized) }
    }

    static func strip(
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
