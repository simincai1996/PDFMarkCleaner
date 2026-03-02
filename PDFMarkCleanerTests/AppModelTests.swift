import XCTest
import PDFKit
import AppKit
import PDFMarkCore
@testable import PDFMarkCleaner

@MainActor
final class AppModelTests: XCTestCase {
    private static var retainedModels: [AppModel] = []

    func testBatchDropAppendsAcrossMultipleDropsAndDeduplicates() {
        let model = makeModel()
        let a = URL(fileURLWithPath: "/tmp/pdfmark-tests/a.pdf")
        let b = URL(fileURLWithPath: "/tmp/pdfmark-tests/b.pdf")
        let c = URL(fileURLWithPath: "/tmp/pdfmark-tests/c.pdf")

        model.handleDroppedFiles([a, b], allowBatch: true)
        XCTAssertEqual(model.processingMode, .batch)
        XCTAssertEqual(model.batchInputURLs, [a, b])

        model.handleDroppedFiles([b, c], allowBatch: true)
        XCTAssertEqual(model.batchInputURLs, [a, b, c])

        model.handleDroppedFiles([a, b, c], allowBatch: true)
        XCTAssertEqual(model.batchInputURLs, [a, b, c])
    }

    func testRemoveBatchInputOnlyRemovesListEntry() throws {
        let model = makeModel()
        let root = try makeTempDirectory(name: "remove-list")
        defer { try? FileManager.default.removeItem(at: root) }

        let keep = try makeTempPDF(named: "keep", in: root)
        let remove = try makeTempPDF(named: "remove", in: root)

        model.handleDroppedFiles([keep, remove], allowBatch: true)
        model.removeBatchInput(at: 1)

        XCTAssertEqual(model.batchInputURLs, [keep])
        XCTAssertTrue(FileManager.default.fileExists(atPath: remove.path))
    }

    func testRemoveCurrentBatchInputSwitchesSelectionToNearestNeighbor() {
        let model = makeModel()
        let a = URL(fileURLWithPath: "/tmp/pdfmark-tests/switch-a.pdf")
        let b = URL(fileURLWithPath: "/tmp/pdfmark-tests/switch-b.pdf")
        let c = URL(fileURLWithPath: "/tmp/pdfmark-tests/switch-c.pdf")

        model.handleDroppedFiles([a, b, c], allowBatch: true)
        model.switchToBatchIndex(1)
        model.removeBatchInput(at: 1)

        XCTAssertEqual(model.batchInputURLs, [a, c])
        XCTAssertEqual(model.batchIndex, 1)
        XCTAssertEqual(model.inputURL, c)
    }

    func testRemovingLastBatchInputClearsCurrentSelection() {
        let model = makeModel()
        let first = URL(fileURLWithPath: "/tmp/pdfmark-tests/only-a.pdf")
        let second = URL(fileURLWithPath: "/tmp/pdfmark-tests/only-b.pdf")

        model.handleDroppedFiles([first, second], allowBatch: true)
        model.removeBatchInput(at: 1)
        model.removeBatchInput(at: 0)

        XCTAssertTrue(model.batchInputURLs.isEmpty)
        XCTAssertNil(model.inputURL)
        XCTAssertNil(model.outputURL)
    }

    func testResolveBatchOutputURLAvoidsExistingAndReservedPaths() {
        let model = makeModel()
        var reserved = Set<String>()

        let preferred = URL(fileURLWithPath: "/tmp/pdfmark-tests/output/report_cleaned.pdf")
        let existing = Set([
            preferred.path,
            "/tmp/pdfmark-tests/output/report_cleaned_2.pdf"
        ])

        let first = model.resolveBatchOutputURL(for: preferred, reservedPaths: &reserved) { path in
            existing.contains(path)
        }
        XCTAssertTrue(first.wasRenamed)
        XCTAssertEqual(first.url.path, "/tmp/pdfmark-tests/output/report_cleaned_3.pdf")

        let second = model.resolveBatchOutputURL(for: preferred, reservedPaths: &reserved) { path in
            existing.contains(path)
        }
        XCTAssertEqual(second.url.path, "/tmp/pdfmark-tests/output/report_cleaned_4.pdf")
    }

    func testSignatureWidgetCanBeRemovedWhenWidgetSelected() {
        let annotation = PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .signature

        XCTAssertTrue(
            PDFAnnotationStripper.shouldRemove(
                annotation,
                selectedTypes: Set([.widget])
            )
        )
    }

    func testSignatureWidgetCanBeRemovedWhenStampSelected() {
        let annotation = PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .signature

        XCTAssertTrue(
            PDFAnnotationStripper.shouldRemove(
                annotation,
                selectedTypes: Set([.stamp])
            )
        )
    }

    func testMarkReportExportIncludesSummaryAndDetails() throws {
        let root = try makeTempDirectory(name: "report-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeAnnotatedPDF(named: "summary", in: root)
        let options = PDFMarkReportExporter.Options(
            selectedTypes: Set([.highlight]),
            scopeDescription: "All Pages",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let report = try PDFMarkReportExporter.buildReport(inputURL: sourceURL, options: options)

        XCTAssertTrue(report.contains("Selected Marks Total: 1"))
        XCTAssertTrue(report.contains("Marked Pages (Selected Types) (1): 1"))
        XCTAssertTrue(report.contains("Type Summary (Selected Types):"))
        XCTAssertTrue(report.contains("- Highlight: 1"))
        XCTAssertTrue(report.contains("Page 1"))
        XCTAssertTrue(report.contains("contents=keep this"))
    }

    func testMarkReportExportRespectsSelectedPagesScope() throws {
        let root = try makeTempDirectory(name: "report-scope")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeAnnotatedPDF(named: "scope", in: root)
        let options = PDFMarkReportExporter.Options(
            selectedTypes: Set([.text]),
            pagesToInclude: Set([2]),
            scopeDescription: "Selected Pages",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let report = try PDFMarkReportExporter.buildReport(inputURL: sourceURL, options: options)

        XCTAssertTrue(report.contains("Pages Included (1): 2"))
        XCTAssertTrue(report.contains("Marked Pages (Selected Types) (1): 2"))
        XCTAssertTrue(report.contains("Page 2"))
        XCTAssertFalse(report.contains("Page 1\n- All marks"))
    }

    func testPDFUnlockerUnlocksPasswordProtectedPDF() throws {
        let root = try makeTempDirectory(name: "unlock-success")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makePasswordProtectedPDF(
            named: "locked",
            in: root,
            userPassword: "1234"
        )
        let outputURL = root.appendingPathComponent("locked_unlocked.pdf")

        let lockedDoc = PDFDocument(url: sourceURL)
        XCTAssertTrue(lockedDoc?.isLocked == true)

        try PDFUnlocker.unlock(
            input: sourceURL,
            output: outputURL,
            password: "1234",
            progress: { _ in }
        )

        let unlockedDoc = PDFDocument(url: outputURL)
        XCTAssertNotNil(unlockedDoc)
        XCTAssertFalse(unlockedDoc?.isLocked ?? true)
    }

    func testPDFUnlockerRequiresPasswordForLockedPDF() throws {
        let root = try makeTempDirectory(name: "unlock-no-password")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makePasswordProtectedPDF(
            named: "locked",
            in: root,
            userPassword: "1234"
        )
        let outputURL = root.appendingPathComponent("locked_unlocked.pdf")

        XCTAssertThrowsError(
            try PDFUnlocker.unlock(
                input: sourceURL,
                output: outputURL,
                password: nil,
                progress: { _ in }
            )
        ) { error in
            guard let unlockError = error as? PDFUnlockError,
                  unlockError == .passwordRequired else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    private func makeTempDirectory(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfmarkcleaner-tests", isDirectory: true)
            .appendingPathComponent(name + "-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTempPDF(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        let content = Data("%PDF-1.4\n%EOF\n".utf8)
        guard FileManager.default.createFile(atPath: url.path, contents: content) else {
            throw NSError(domain: "AppModelTests", code: 1)
        }
        return url
    }

    private func makeAnnotatedPDF(named name: String, in directory: URL) throws -> URL {
        let document = PDFDocument()
        let page1 = try makeBlankPDFPage()
        let page2 = try makeBlankPDFPage()

        let highlight = PDFAnnotation(
            bounds: CGRect(x: 20, y: 30, width: 120, height: 24),
            forType: .highlight,
            withProperties: nil
        )
        highlight.userName = "tester"
        highlight.contents = "keep this"
        highlight.color = .yellow
        page1.addAnnotation(highlight)

        let textNote = PDFAnnotation(
            bounds: CGRect(x: 40, y: 60, width: 32, height: 32),
            forType: .text,
            withProperties: nil
        )
        textNote.userName = "tester"
        textNote.contents = "todo"
        page2.addAnnotation(textNote)

        document.insert(page1, at: 0)
        document.insert(page2, at: 1)

        let url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        guard document.write(to: url) else {
            throw NSError(domain: "AppModelTests", code: 2)
        }
        return url
    }

    private func makePasswordProtectedPDF(
        named name: String,
        in directory: URL,
        userPassword: String
    ) throws -> URL {
        let document = PDFDocument()
        let page = try makeBlankPDFPage()
        document.insert(page, at: 0)

        let url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: "owner-password",
            .userPasswordOption: userPassword
        ]
        guard document.write(to: url, withOptions: options) else {
            throw NSError(domain: "AppModelTests", code: 4)
        }
        return url
    }

    private func makeBlankPDFPage() throws -> PDFPage {
        let size = NSSize(width: 300, height: 420)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw NSError(domain: "AppModelTests", code: 3)
        }
        return page
    }

    private func makeModel() -> AppModel {
        let model = AppModel()
        model.skipBackgroundWorkForTesting = true
        Self.retainedModels.append(model)
        return model
    }
}
