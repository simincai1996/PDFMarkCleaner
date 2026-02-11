import XCTest
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

    private func makeModel() -> AppModel {
        let model = AppModel()
        model.skipBackgroundWorkForTesting = true
        Self.retainedModels.append(model)
        return model
    }
}
