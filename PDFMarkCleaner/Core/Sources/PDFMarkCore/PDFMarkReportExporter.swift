import Foundation
import PDFKit

public enum PDFMarkReportExporterError: LocalizedError {
    case openFailed

    public var errorDescription: String? {
        switch self {
        case .openFailed:
            return "Failed to open PDF."
        }
    }
}

public struct PDFMarkReportExporter {
    public struct Options: Sendable {
        public var selectedTypes: Set<AnnotationKind>
        public var pagesToInclude: Set<Int>?
        public var scopeDescription: String
        public var generatedAt: Date
        public var includePerAnnotationDetails: Bool

        public init(
            selectedTypes: Set<AnnotationKind> = Set(AnnotationKind.allCases),
            pagesToInclude: Set<Int>? = nil,
            scopeDescription: String = "All Pages",
            generatedAt: Date = Date(),
            includePerAnnotationDetails: Bool = true
        ) {
            self.selectedTypes = selectedTypes
            self.pagesToInclude = pagesToInclude
            self.scopeDescription = scopeDescription
            self.generatedAt = generatedAt
            self.includePerAnnotationDetails = includePerAnnotationDetails
        }
    }

    private struct AnnotationRecord {
        let index: Int
        let kindLabel: String
        let rawType: String
        let widgetFieldType: String?
        let userName: String?
        let contents: String?
        let modificationDate: String?
        let colorHex: String?
        let boundsDescription: String
    }

    private struct PageSummary {
        let pageNumber: Int
        let allMarkCount: Int
        let selectedMarkCount: Int
        let allTypeCounts: [String: Int]
        let selectedTypeCounts: [String: Int]
        let records: [AnnotationRecord]
    }

    private static let slashSet = CharacterSet(charactersIn: "/")
    private static let whitespaceSet = CharacterSet.whitespacesAndNewlines

    public static func buildReport(inputURL: URL, options: Options = Options()) throws -> String {
        guard let document = PDFDocument(url: inputURL) else {
            throw PDFMarkReportExporterError.openFailed
        }

        return buildReport(
            document: document,
            sourceDisplayName: inputURL.lastPathComponent,
            sourcePath: inputURL.path,
            fileSizeBytes: fileSize(for: inputURL),
            options: options
        )
    }

    public static func buildReport(
        document: PDFDocument,
        sourceDisplayName: String,
        sourcePath: String,
        fileSizeBytes: Int64? = nil,
        options: Options = Options()
    ) -> String {
        let totalPages = document.pageCount
        let pagesToInspect = normalizedPagesToInspect(
            pagesToInclude: options.pagesToInclude,
            totalPages: totalPages
        )
        let selectedTypes = options.selectedTypes
        let includeAllDetails = selectedTypes.isEmpty

        var selectedTypeCounts: [String: Int] = [:]
        var allTypeCounts: [String: Int] = [:]
        var pageSummaries: [PageSummary] = []
        var selectedMarkedPages: [Int] = []
        var pagesWithAnyMarks: [Int] = []
        var totalSelectedMarks = 0
        var totalAllMarks = 0

        for pageNumber in pagesToInspect {
            guard let page = document.page(at: pageNumber - 1) else { continue }

            var pageAllTypeCounts: [String: Int] = [:]
            var pageSelectedTypeCounts: [String: Int] = [:]
            var pageRecords: [AnnotationRecord] = []
            let annotations = page.annotations

            for (index, annotation) in annotations.enumerated() {
                let kind = PDFAnnotationStripper.kind(for: annotation)
                let typeLabel = label(for: annotation, kind: kind)
                let isSelected = PDFAnnotationStripper.shouldRemove(annotation, selectedTypes: selectedTypes)

                pageAllTypeCounts[typeLabel, default: 0] += 1
                allTypeCounts[typeLabel, default: 0] += 1
                totalAllMarks += 1

                if isSelected {
                    pageSelectedTypeCounts[typeLabel, default: 0] += 1
                    selectedTypeCounts[typeLabel, default: 0] += 1
                    totalSelectedMarks += 1
                }

                if options.includePerAnnotationDetails && (includeAllDetails || isSelected) {
                    pageRecords.append(
                        makeRecord(
                            annotation,
                            index: index + 1,
                            kindLabel: typeLabel
                        )
                    )
                }
            }

            if !pageAllTypeCounts.isEmpty {
                pagesWithAnyMarks.append(pageNumber)
            }
            if !pageSelectedTypeCounts.isEmpty {
                selectedMarkedPages.append(pageNumber)
            }

            if !pageAllTypeCounts.isEmpty || !pageRecords.isEmpty {
                pageSummaries.append(
                    PageSummary(
                        pageNumber: pageNumber,
                        allMarkCount: annotations.count,
                        selectedMarkCount: pageSelectedTypeCounts.values.reduce(0, +),
                        allTypeCounts: pageAllTypeCounts,
                        selectedTypeCounts: pageSelectedTypeCounts,
                        records: pageRecords
                    )
                )
            }
        }

        let selectedTypeNames = selectedTypes
            .sorted { $0.title < $1.title }
            .map(\.title)

        var lines: [String] = []
        lines.append("PDF Mark Cleaner - Mark Export")
        lines.append("File Name: \(sourceDisplayName)")
        lines.append("File Path: \(sourcePath)")
        if let fileSizeBytes {
            lines.append("File Size: \(fileSizeBytes) bytes")
        }
        lines.append("Exported At: \(iso8601String(from: options.generatedAt))")
        lines.append("Total Pages: \(totalPages)")
        lines.append("Scope: \(options.scopeDescription)")
        lines.append(
            "Pages Included (\(pagesToInspect.count)): \(pagesDescription(pages: pagesToInspect, totalPages: totalPages, treatAsAllPages: options.pagesToInclude == nil))"
        )
        lines.append(
            "Selected Types (\(selectedTypeNames.count)): \(selectedTypeNames.isEmpty ? "None" : selectedTypeNames.joined(separator: ", "))"
        )
        lines.append(
            "Pages With Any Marks (\(pagesWithAnyMarks.count)): \(pagesWithAnyMarks.isEmpty ? "None" : compactPageRanges(pagesWithAnyMarks))"
        )
        lines.append(
            "Marked Pages (Selected Types) (\(selectedMarkedPages.count)): \(selectedMarkedPages.isEmpty ? "None" : compactPageRanges(selectedMarkedPages))"
        )
        lines.append("All Marks Total (Included Scope): \(totalAllMarks)")
        lines.append("Selected Marks Total: \(totalSelectedMarks)")
        lines.append("")

        lines.append("Type Summary (Selected Types):")
        lines.append(contentsOf: formattedCountLines(from: selectedTypeCounts))
        lines.append("")

        lines.append("Type Summary (All Types in Scope):")
        lines.append(contentsOf: formattedCountLines(from: allTypeCounts))
        lines.append("")

        lines.append("Page Details:")
        if pageSummaries.isEmpty {
            lines.append("- None")
        } else {
            for summary in pageSummaries {
                lines.append("Page \(summary.pageNumber)")
                lines.append("- All marks: \(summary.allMarkCount)")
                lines.append("- Selected marks: \(summary.selectedMarkCount)")
                lines.append("- All type counts: \(inlineCountSummary(summary.allTypeCounts))")
                lines.append(
                    "- Selected type counts: \(summary.selectedTypeCounts.isEmpty ? "None" : inlineCountSummary(summary.selectedTypeCounts))"
                )

                if options.includePerAnnotationDetails {
                    if summary.records.isEmpty {
                        lines.append("- Mark details: None")
                    } else {
                        lines.append("- Mark details:")
                        for record in summary.records {
                            var parts: [String] = [
                                "kind=\(record.kindLabel)",
                                "raw=\(record.rawType)",
                                "bounds=\(record.boundsDescription)"
                            ]
                            if let widgetFieldType = record.widgetFieldType {
                                parts.append("widget=\(widgetFieldType)")
                            }
                            if let userName = record.userName {
                                parts.append("user=\(userName)")
                            }
                            if let contents = record.contents {
                                parts.append("contents=\(contents)")
                            }
                            if let colorHex = record.colorHex {
                                parts.append("color=\(colorHex)")
                            }
                            if let modificationDate = record.modificationDate {
                                parts.append("modified=\(modificationDate)")
                            }

                            lines.append("  [\(record.index)] \(parts.joined(separator: "; "))")
                        }
                    }
                }

                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func normalizedPagesToInspect(
        pagesToInclude: Set<Int>?,
        totalPages: Int
    ) -> [Int] {
        guard totalPages > 0 else { return [] }
        if let pagesToInclude {
            return pagesToInclude
                .filter { $0 >= 1 && $0 <= totalPages }
                .sorted()
        }
        return Array(1...totalPages)
    }

    private static func makeRecord(
        _ annotation: PDFAnnotation,
        index: Int,
        kindLabel: String
    ) -> AnnotationRecord {
        let rawType = cleanText(
            annotation.type?.trimmingCharacters(in: slashSet)
        ) ?? "Unknown"

        let widgetFieldType = cleanText(
            annotation.widgetFieldType.rawValue
        )

        let userName = cleanText(annotation.userName)
        let contents = cleanText(annotation.contents)

        let modificationDate = annotationDateString(annotation.modificationDate)

        return AnnotationRecord(
            index: index,
            kindLabel: kindLabel,
            rawType: rawType,
            widgetFieldType: widgetFieldType,
            userName: userName,
            contents: contents,
            modificationDate: modificationDate,
            colorHex: colorHexString(annotation.color.cgColor),
            boundsDescription: boundsDescription(annotation.bounds)
        )
    }

    private static func label(for annotation: PDFAnnotation, kind: AnnotationKind?) -> String {
        if let kind {
            return kind.title
        }
        return cleanText(
            annotation.type?.trimmingCharacters(in: slashSet)
        ) ?? "Unknown"
    }

    private static func annotationDateString(_ value: Any?) -> String? {
        if let date = value as? Date {
            return iso8601String(from: date)
        }
        if let text = value as? String {
            return cleanText(text)
        }
        return nil
    }

    private static func formattedCountLines(from counts: [String: Int]) -> [String] {
        let pairs = counts.sorted {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        }
        if pairs.isEmpty {
            return ["- None"]
        }
        return pairs.map { "- \($0.key): \($0.value)" }
    }

    private static func inlineCountSummary(_ counts: [String: Int]) -> String {
        counts.sorted {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
    }

    private static func pagesDescription(
        pages: [Int],
        totalPages: Int,
        treatAsAllPages: Bool
    ) -> String {
        guard !pages.isEmpty else { return "None" }
        if treatAsAllPages && pages.count == totalPages {
            if totalPages == 1 {
                return "All (1)"
            }
            return "All (1-\(totalPages))"
        }
        return compactPageRanges(pages)
    }

    private static func compactPageRanges(_ pages: [Int]) -> String {
        let sorted = Array(Set(pages)).sorted()
        guard !sorted.isEmpty else { return "None" }

        var ranges: [String] = []
        var start = sorted[0]
        var end = sorted[0]

        for page in sorted.dropFirst() {
            if page == end + 1 {
                end = page
            } else {
                ranges.append(rangeString(start: start, end: end))
                start = page
                end = page
            }
        }
        ranges.append(rangeString(start: start, end: end))
        return ranges.joined(separator: ", ")
    }

    private static func rangeString(start: Int, end: Int) -> String {
        if start == end {
            return "\(start)"
        }
        return "\(start)-\(end)"
    }

    private static func boundsDescription(_ rect: CGRect) -> String {
        String(
            format: "(x: %.2f, y: %.2f, w: %.2f, h: %.2f)",
            Double(rect.origin.x),
            Double(rect.origin.y),
            Double(rect.size.width),
            Double(rect.size.height)
        )
    }

    private static func colorHexString(_ color: CGColor?) -> String? {
        guard let color else { return nil }

        let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)
        let converted = srgbSpace.flatMap {
            color.converted(
                to: $0,
                intent: .defaultIntent,
                options: nil
            )
        } ?? color

        guard let components = converted.components else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        switch components.count {
        case 2:
            red = components[0]
            green = components[0]
            blue = components[0]
        case 3, 4:
            red = components[0]
            green = components[1]
            blue = components[2]
        default:
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    private static func cleanText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: whitespaceSet)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func fileSize(for url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
