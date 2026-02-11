import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine
import PDFKit

enum RemovalScope: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Pages"
        case .selected: return "Selected Pages"
        }
    }
}

enum ProcessingMode: String, CaseIterable, Identifiable {
    case single
    case batch

    var id: String { rawValue }
}

private struct FileState {
    var outputURL: URL?
    var originalPreview: PDFDocument?
    var cleanedPreview: PDFDocument?
    var pageCount: Int
    var currentPageNumber: Int
    var markedPages: [Int]
    var selectedPages: Set<Int>
    var perPageTypeCounts: [Int: [AnnotationKind: Int]]
    var documentTypeCounts: [AnnotationKind: Int]
    var currentPageTypeCounts: [AnnotationKind: Int]
    var selectedPagesTypeCounts: [AnnotationKind: Int]
    var inputFileSizeBytes: Int64
    var estimatedFileSizeBytes: Int64?
    var isEstimateStale: Bool
    var lastEstimateKey: String?
    var cleanedProcessedPages: Set<Int>
}

final class AppModel: ObservableObject {
    @Published var processingMode: ProcessingMode = .single {
        didSet {
            handleModeChanged()
        }
    }
    @Published var batchInputURLs: [URL] = []
    @Published var batchIndex: Int = 0
    @Published var batchOutputDirectory: URL?
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var selectedTypes: Set<AnnotationKind> = Set(AnnotationKind.allCases) {
        didSet {
            if inputURL != nil {
                handleSelectionChanged()
            }
        }
    }
    @Published var removalScope: RemovalScope = .all {
        didSet {
            if inputURL != nil {
                handleScopeChanged()
            }
        }
    }
    @Published var selectedPages: Set<Int> = [] {
        didSet {
            if inputURL != nil && !isUpdatingSelection {
                handleSelectedPagesChanged()
            }
        }
    }
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var status = "Select a PDF file."

    @Published var originalPreview: PDFDocument?
    @Published var cleanedPreview: PDFDocument?
    @Published private(set) var pageCount: Int = 0
    @Published var currentPageNumber: Int = 1 {
        didSet {
            if inputURL != nil {
                updateCurrentPageCounts()
            }
        }
    }
    @Published var markedPages: [Int] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var previewScale: CGFloat = 1.0

    @Published var inputFileSizeBytes: Int64 = 0
    @Published var estimatedFileSizeBytes: Int64?
    @Published var isEstimatingSize = false
    @Published var estimateProgress: Double = 0
    @Published var isEstimateStale = true
    @Published var documentTypeCounts: [AnnotationKind: Int] = [:]
    @Published var currentPageTypeCounts: [AnnotationKind: Int] = [:]
    @Published var selectedPagesTypeCounts: [AnnotationKind: Int] = [:]

    private var scanToken = UUID()
    private var estimateToken = UUID()
    private var lastEstimateKey: String?
    private var cleanedProcessedPages = Set<Int>()
    private var isUpdatingSelection = false
    private var perPageTypeCounts: [Int: [AnnotationKind: Int]] = [:]
    private let minPreviewScale: CGFloat = 0.5
    private let maxPreviewScale: CGFloat = 3.0
    private let scanUpdateStride = 12
    private var fileStates: [URL: FileState] = [:]

    var isBatchMode: Bool {
        processingMode == .batch
    }

    var suggestedOutputURL: URL? {
        guard let inputURL else { return nil }
        return suggestedOutputURL(for: inputURL)
    }

    func suggestedOutputURL(for url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let filename = base + "_cleaned.pdf"
        if isBatchMode, let batchDir = batchOutputDirectory {
            return batchDir.appendingPathComponent(filename)
        }
        return url.deletingLastPathComponent().appendingPathComponent(filename)
    }

    private var hasInput: Bool {
        if isBatchMode {
            return !batchInputURLs.isEmpty
        }
        return inputURL != nil
    }

    var canProcess: Bool {
        guard hasInput else { return false }
        if selectedTypes.isEmpty { return false }
        if removalScope == .selected && !isBatchMode && selectedPages.isEmpty { return false }
        return true
    }

    var canEstimate: Bool {
        guard inputURL != nil else { return false }
        if selectedTypes.isEmpty { return false }
        if removalScope == .selected && !isBatchMode && selectedPages.isEmpty { return false }
        return true
    }

    func pickInput() {
        saveCurrentState()
        processingMode = .single

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        inputURL = url
        outputURL = nil
        currentPageNumber = 1
        status = "Selected: \(url.lastPathComponent)"
        updateFileSize(for: url)
        loadDocuments(url: url)
        scanMarkedPages()
        markEstimateStale(clearValue: true)
    }

    func pickBatchInputs() {
        saveCurrentState()
        processingMode = .batch

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            applyBatchInputsSelection(normalizedPDFURLs(from: panel.urls))
        }
    }

    func handleDroppedFiles(_ urls: [URL], allowBatch: Bool) {
        if isRunning {
            status = "Processing... Please wait."
            return
        }

        let pdfURLs = normalizedPDFURLs(from: urls)
        guard !pdfURLs.isEmpty else {
            status = "Please drop PDF files."
            return
        }

        if allowBatch && isBatchMode {
            appendBatchInputs(pdfURLs)
            return
        }

        if allowBatch && pdfURLs.count > 1 {
            saveCurrentState()
            processingMode = .batch
            applyBatchInputsSelection(pdfURLs)
            return
        }

        saveCurrentState()
        processingMode = .single
        open(url: pdfURLs[0])
    }

    func pickBatchOutputDirectory() {
        guard !batchInputURLs.isEmpty else {
            status = "Please select PDF files first."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            batchOutputDirectory = url
            status = "Output folder: \(url.lastPathComponent)"
        }
    }

    func clearSelection() {
        if isRunning {
            status = "Processing... Please wait."
            return
        }

        if isBatchMode {
            fileStates.removeAll()
            batchInputURLs = []
            batchIndex = 0
            batchOutputDirectory = nil
        }
        resetState(statusMessage: "Select a PDF file.")
    }

    func pickOutput() {
        if isBatchMode {
            status = "Output selection is disabled in batch mode."
            return
        }
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.directoryURL = inputURL.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedOutputURL?.lastPathComponent ?? "output.pdf"

        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
            status = "Output: \(url.lastPathComponent)"
        }
    }

    func start() {
        if isBatchMode {
            startBatch()
            return
        }
        guard canProcess else {
            status = "Select types/pages before processing."
            return
        }
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isRunning { return }

        let output = outputURL ?? suggestedOutputURL ?? inputURL
        runStrip(to: output)
    }

    func saveAs() {
        if isBatchMode {
            status = "Save is disabled in batch mode."
            return
        }
        guard canProcess else {
            status = "Select types/pages before saving."
            return
        }
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isRunning { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.directoryURL = inputURL.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedOutputURL?.lastPathComponent ?? "output.pdf"

        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
            runStrip(to: url)
        }
    }

    func exportMarkedPages() {
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isScanning {
            status = "Scanning marked pages..."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.directoryURL = inputURL.deletingLastPathComponent()
        panel.nameFieldStringValue = "marked_pages.txt"

        if panel.runModal() == .OK, let url = panel.url {
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            let marks = markedPages.map(String.init).joined(separator: ", ")
            let types = selectedTypes.sorted { $0.title < $1.title }.map { $0.title }.joined(separator: ", ")
            let content = """
            PDF Mark Cleaner - Marked Pages Export
            File: \(inputURL.path)
            Exported: \(timestamp)
            Types: \(types.isEmpty ? "None" : types)
            Total pages: \(pageCount)
            Marked pages (\(markedPages.count)):
            \(marks)
            """

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                status = "Exported: \(url.lastPathComponent)"
            } catch {
                status = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func estimateSize() {
        guard inputURL != nil else {
            status = "Please select a PDF first."
            return
        }
        if isEstimatingSize || isRunning { return }

        if selectedTypes.isEmpty {
            status = "Select annotation types to estimate."
            return
        }
        if removalScope == .selected && selectedPages.isEmpty {
            status = "Select pages to estimate."
            return
        }

        let key = makeEstimateKey()
        if !isEstimateStale, key == lastEstimateKey, estimatedFileSizeBytes != nil {
            status = "Estimate is up to date."
            return
        }

        estimateOutputSize(forKey: key)
    }

    func replaceOriginal() {
        if isBatchMode {
            status = "Replace is disabled in batch mode."
            return
        }
        guard canProcess else {
            status = "Select types/pages before replacing."
            return
        }
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isRunning { return }

        guard confirm(
            title: "Replace original PDF?",
            message: "This will overwrite the original file. This action cannot be undone."
        ) else {
            return
        }

        let tempName = ".pdfmarkcleaner_tmp_\(UUID().uuidString).pdf"
        let tempURL = inputURL.deletingLastPathComponent().appendingPathComponent(tempName)

        runStrip(to: tempURL, completion: { [weak self] success in
            guard let self else { return }
            if !success { return }
            do {
                let fileManager = FileManager.default
                _ = try fileManager.replaceItemAt(inputURL, withItemAt: tempURL, backupItemName: nil, options: [])
                self.status = "Replaced: \(inputURL.lastPathComponent)"
                self.updateFileSize(for: inputURL)
                self.loadDocuments(url: inputURL)
                self.scanMarkedPages()
                self.markEstimateStale(clearValue: true)
            } catch {
                self.status = "Replace failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
            }
        })
    }

    func deleteOriginal() {
        if isBatchMode {
            deleteCurrentBatchItem()
            return
        }
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isRunning { return }

        guard confirm(
            title: "Delete original PDF?",
            message: "The file will be moved to Trash."
        ) else {
            return
        }

        do {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: inputURL, resultingItemURL: &trashed)
            resetState(statusMessage: "Moved to Trash: \(inputURL.lastPathComponent)")
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
        }
    }

    func switchToBatchIndex(_ index: Int) {
        guard !batchInputURLs.isEmpty else {
            resetState(statusMessage: "Select a PDF file.")
            return
        }
        guard !isRunning else {
            status = "Processing... Please wait."
            return
        }

        let clamped = max(0, min(index, batchInputURLs.count - 1))
        if let current = inputURL, current != batchInputURLs[clamped] {
            saveCurrentState()
        }

        batchIndex = clamped
        let url = batchInputURLs[clamped]
        inputURL = url
        outputURL = nil
        scanToken = UUID()
        estimateToken = UUID()
        isEstimatingSize = false
        estimateProgress = 0

        if restoreState(for: url) {
            status = "Selected: \(url.lastPathComponent)"
            return
        }

        currentPageNumber = 1
        selectedPages = []
        markedPages = []
        documentTypeCounts = [:]
        perPageTypeCounts = [:]
        currentPageTypeCounts = [:]
        selectedPagesTypeCounts = [:]
        updateFileSize(for: url)
        loadDocuments(url: url)
        scanMarkedPages()
        markEstimateStale(clearValue: true)
        status = "Selected: \(url.lastPathComponent)"
    }

    func stepBatchItem(_ delta: Int) {
        switchToBatchIndex(batchIndex + delta)
    }

    func removeBatchInput(at index: Int) {
        guard !isRunning else {
            status = "Processing... Please wait."
            return
        }
        guard batchInputURLs.indices.contains(index) else { return }

        let removed = batchInputURLs[index]
        let wasCurrent = inputURL == removed
        batchInputURLs.remove(at: index)
        fileStates.removeValue(forKey: removed)

        guard !batchInputURLs.isEmpty else {
            inputURL = nil
            outputURL = nil
            clearCurrentDocumentState(statusMessage: "Select a PDF file.")
            batchIndex = 0
            return
        }

        if wasCurrent {
            inputURL = nil
            let newIndex = min(index, batchInputURLs.count - 1)
            switchToBatchIndex(newIndex)
            return
        }

        if index < batchIndex {
            batchIndex -= 1
        }
        status = "Removed from batch: \(removed.lastPathComponent)"
    }

    private func applyBatchInputsSelection(_ urls: [URL]) {
        batchInputURLs = urls
        batchIndex = 0
        fileStates = fileStates.filter { urls.contains($0.key) }
        if urls.isEmpty {
            resetState(statusMessage: "Select a PDF file.")
        } else {
            switchToBatchIndex(0)
            status = "Selected: \(urls.count) files"
        }
    }

    private func appendBatchInputs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        var known = Set(batchInputURLs.map { $0.standardizedFileURL.path })
        var additions: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if known.insert(path).inserted {
                additions.append(url)
            }
        }

        guard !additions.isEmpty else {
            status = "No new PDF files added."
            return
        }

        let wasEmpty = batchInputURLs.isEmpty
        batchInputURLs.append(contentsOf: additions)
        if wasEmpty || inputURL == nil {
            switchToBatchIndex(0)
            status = "Selected: \(batchInputURLs.count) files"
        } else {
            status = "Added: \(additions.count) file(s)"
        }
    }

    private func normalizedPDFURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            let fileURL = url.standardizedFileURL
            guard fileURL.isFileURL else { continue }
            guard fileURL.pathExtension.lowercased() == "pdf" else { continue }
            if seen.insert(fileURL.path).inserted {
                result.append(fileURL)
            }
        }

        return result
    }

    private func startBatch() {
        guard !batchInputURLs.isEmpty else {
            status = "Please select PDF files first."
            return
        }
        guard !selectedTypes.isEmpty else {
            status = "No annotation types selected."
            return
        }
        if isRunning { return }

        let urls = batchInputURLs
        let typesSnapshot = selectedTypes

        progress = 0
        isRunning = true
        status = "Processing batch..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var lastError: Error?

            for (index, url) in urls.enumerated() {
                do {
                    let output = self.suggestedOutputURL(for: url)
                    try PDFAnnotationStripper.strip(
                        input: url,
                        output: output,
                        selectedTypes: typesSnapshot,
                        pagesToProcess: nil,
                        progress: { p in
                            let overall = (Double(index) + p) / Double(urls.count)
                            DispatchQueue.main.async {
                                self.progress = overall
                            }
                        }
                    )

                    let size = self.fileSize(for: output)
                    DispatchQueue.main.async {
                        if url == self.inputURL {
                            self.estimatedFileSizeBytes = size
                            self.isEstimateStale = false
                            self.lastEstimateKey = self.makeEstimateKey()
                        }
                        if var state = self.fileStates[url] {
                            state.estimatedFileSizeBytes = size
                            state.isEstimateStale = false
                            self.fileStates[url] = state
                        }
                    }
                } catch {
                    lastError = error
                    break
                }
            }

            DispatchQueue.main.async {
                self.isRunning = false
                if let error = lastError {
                    self.status = "Batch failed: \(error.localizedDescription)"
                } else {
                    self.progress = 1
                    self.status = "Batch done: \(urls.count) files"
                }
            }
        }
    }

    private func deleteCurrentBatchItem() {
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isRunning { return }

        guard confirm(
            title: "Delete original PDF?",
            message: "The file will be moved to Trash."
        ) else {
            return
        }

        do {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: inputURL, resultingItemURL: &trashed)
            fileStates.removeValue(forKey: inputURL)
            if let index = batchInputURLs.firstIndex(of: inputURL) {
                batchInputURLs.remove(at: index)
                if batchInputURLs.isEmpty {
                    batchIndex = 0
                    resetState(statusMessage: "Moved to Trash: \(inputURL.lastPathComponent)")
                    return
                }
                let newIndex = min(index, batchInputURLs.count - 1)
                switchToBatchIndex(newIndex)
                status = "Moved to Trash: \(inputURL.lastPathComponent)"
            } else {
                resetState(statusMessage: "Moved to Trash: \(inputURL.lastPathComponent)")
            }
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
        }
    }

    func selectAllMarkedPages() {
        guard !markedPages.isEmpty else { return }
        selectedPages = Set(markedPages)
    }

    func clearSelectedPages() {
        selectedPages = []
    }

    func applyPageRangeInput(_ input: String) {
        guard inputURL != nil else {
            status = "Please select a PDF first."
            return
        }
        guard removalScope == .selected else {
            status = "Switch to Selected Pages to apply ranges."
            return
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            selectedPages = []
            status = "Selected pages cleared."
            return
        }

        let tokens = trimmed.split { ch in
            ch == "," || ch == ";" || ch == " " || ch == "\n" || ch == "\t"
        }

        var result = Set<Int>()
        var invalidCount = 0

        for tokenSub in tokens {
            let token = String(tokenSub).trimmingCharacters(in: .whitespaces)
            if token.isEmpty { continue }

            let parts = token.split { ch in
                ch == "-" || ch == "–" || ch == "—"
            }

            if parts.count == 1 {
                if let value = Int(parts[0]), value >= 1, value <= pageCount {
                    result.insert(value)
                } else {
                    invalidCount += 1
                }
            } else if parts.count == 2 {
                guard let start = Int(parts[0]), let end = Int(parts[1]) else {
                    invalidCount += 1
                    continue
                }

                let lower = min(start, end)
                let upper = max(start, end)
                if upper < 1 || lower > pageCount {
                    invalidCount += 1
                    continue
                }

                let clampedLower = max(1, lower)
                let clampedUpper = min(pageCount, upper)
                for page in clampedLower...clampedUpper {
                    result.insert(page)
                }
            } else {
                invalidCount += 1
            }
        }

        selectedPages = result

        if result.isEmpty {
            status = "No valid pages found."
        } else if invalidCount == 0 {
            status = "Selected \(result.count) pages."
        } else {
            status = "Selected \(result.count) pages. Ignored \(invalidCount) token(s)."
        }
    }

    func setCurrentPageNumber(_ number: Int) {
        let clamped = clampPageNumber(number)
        if clamped != currentPageNumber {
            currentPageNumber = clamped
        }
    }

    func stepPage(_ delta: Int) {
        setCurrentPageNumber(currentPageNumber + delta)
    }

    func goToPreviousMarkedPage() {
        guard !markedPages.isEmpty else { return }
        let current = currentPageNumber
        if let prev = markedPages.last(where: { $0 < current }) {
            setCurrentPageNumber(prev)
        }
    }

    func goToNextMarkedPage() {
        guard !markedPages.isEmpty else { return }
        let current = currentPageNumber
        if let next = markedPages.first(where: { $0 > current }) {
            setCurrentPageNumber(next)
        }
    }

    func zoomIn() {
        adjustZoom(by: 0.1)
    }

    func zoomOut() {
        adjustZoom(by: -0.1)
    }

    func resetZoom() {
        previewScale = 1.0
    }

    func handleCleanedPageChanged(_ page: PDFPage) {
        applyCleaning(to: page)
        guard let doc = cleanedPreview else { return }
        let index = doc.index(for: page)
        if index != NSNotFound {
            if index > 0, let prev = doc.page(at: index - 1) {
                applyCleaning(to: prev)
            }
            if index + 1 < doc.pageCount, let next = doc.page(at: index + 1) {
                applyCleaning(to: next)
            }
        }
    }

    private func adjustZoom(by delta: CGFloat) {
        let newValue = previewScale + delta
        let clamped = min(max(newValue, minPreviewScale), maxPreviewScale)
        previewScale = clamped
    }

    private func handleModeChanged() {
        saveCurrentState()
        if isBatchMode {
            removalScope = .all
            selectedPages = []
            if batchInputURLs.isEmpty, let current = inputURL {
                batchInputURLs = [current]
                batchIndex = 0
            }
            if !batchInputURLs.isEmpty {
                switchToBatchIndex(min(batchIndex, batchInputURLs.count - 1))
            } else {
                resetState(statusMessage: "Select a PDF file.")
            }
        }
    }

    private func saveCurrentState() {
        guard let inputURL else { return }
        fileStates[inputURL] = FileState(
            outputURL: outputURL,
            originalPreview: originalPreview,
            cleanedPreview: cleanedPreview,
            pageCount: pageCount,
            currentPageNumber: currentPageNumber,
            markedPages: markedPages,
            selectedPages: selectedPages,
            perPageTypeCounts: perPageTypeCounts,
            documentTypeCounts: documentTypeCounts,
            currentPageTypeCounts: currentPageTypeCounts,
            selectedPagesTypeCounts: selectedPagesTypeCounts,
            inputFileSizeBytes: inputFileSizeBytes,
            estimatedFileSizeBytes: estimatedFileSizeBytes,
            isEstimateStale: isEstimateStale,
            lastEstimateKey: lastEstimateKey,
            cleanedProcessedPages: cleanedProcessedPages
        )
    }

    private func restoreState(for url: URL) -> Bool {
        guard let state = fileStates[url] else { return false }
        outputURL = state.outputURL
        originalPreview = state.originalPreview
        cleanedPreview = state.cleanedPreview
        pageCount = state.pageCount
        currentPageNumber = state.currentPageNumber
        markedPages = state.markedPages
        selectedPages = state.selectedPages
        perPageTypeCounts = state.perPageTypeCounts
        documentTypeCounts = state.documentTypeCounts
        currentPageTypeCounts = state.currentPageTypeCounts
        selectedPagesTypeCounts = state.selectedPagesTypeCounts
        inputFileSizeBytes = state.inputFileSizeBytes
        estimatedFileSizeBytes = state.estimatedFileSizeBytes
        isEstimateStale = state.isEstimateStale
        lastEstimateKey = state.lastEstimateKey
        cleanedProcessedPages = state.cleanedProcessedPages
        isEstimatingSize = false
        estimateProgress = 0
        return true
    }

    private func handleSelectionChanged() {
        resetCleanedPreview()
        if perPageTypeCounts.isEmpty, !isScanning {
            scanMarkedPages()
        } else {
            updateMarkedPagesFromCounts()
        }
        markEstimateStale()
    }

    private func handleScopeChanged() {
        if removalScope == .selected, selectedPages.isEmpty, !markedPages.isEmpty {
            isUpdatingSelection = true
            selectedPages = Set(markedPages)
            isUpdatingSelection = false
        }
        resetCleanedPreview()
        updateSelectedPagesCounts()
        markEstimateStale()
    }

    private func handleSelectedPagesChanged() {
        resetCleanedPreview()
        updateSelectedPagesCounts()
        markEstimateStale()
    }

    private func markEstimateStale(clearValue: Bool = false) {
        estimateToken = UUID()
        isEstimateStale = true
        lastEstimateKey = nil
        isEstimatingSize = false
        estimateProgress = 0
        if clearValue {
            estimatedFileSizeBytes = nil
        }
    }

    private func loadDocuments(url: URL) {
        originalPreview = PDFDocument(url: url)
        cleanedPreview = PDFDocument(url: url)
        pageCount = originalPreview?.pageCount ?? 0
        cleanedProcessedPages.removeAll()
        applyCleaningForPageNumber(currentPageNumber)
        updateCurrentPageCounts()
    }

    private func resetCleanedPreview() {
        guard let url = inputURL else { return }
        cleanedPreview = PDFDocument(url: url)
        cleanedProcessedPages.removeAll()
        applyCleaningForPageNumber(currentPageNumber)
        updateCurrentPageCounts()
    }

    private func applyCleaningForPageNumber(_ number: Int) {
        guard shouldProcessPage(number) else { return }
        guard let doc = cleanedPreview else { return }
        let clamped = clampPageNumber(number)
        guard let page = doc.page(at: clamped - 1) else { return }
        applyCleaning(to: page)
    }

    private func applyCleaning(to page: PDFPage) {
        guard let doc = cleanedPreview else { return }
        let index = doc.index(for: page)
        if index == NSNotFound { return }
        let pageNumber = index + 1
        if !shouldProcessPage(pageNumber) { return }
        if cleanedProcessedPages.contains(pageNumber) { return }

        for annot in page.annotations {
            let shouldHide = PDFAnnotationStripper.shouldRemove(annot, selectedTypes: selectedTypes)
            annot.shouldDisplay = !shouldHide
        }

        cleanedProcessedPages.insert(pageNumber)
    }

    private func shouldProcessPage(_ pageNumber: Int) -> Bool {
        switch removalScope {
        case .all:
            return true
        case .selected:
            return selectedPages.contains(pageNumber)
        }
    }

    private func runStrip(to output: URL, completion: ((Bool) -> Void)? = nil) {
        guard let inputURL else {
            status = "Please select a PDF first."
            completion?(false)
            return
        }
        if isRunning { return }

        if selectedTypes.isEmpty {
            status = "No annotation types selected."
            completion?(false)
            return
        }

        if removalScope == .selected && selectedPages.isEmpty {
            status = "No pages selected."
            completion?(false)
            return
        }

        let selectedSnapshot = selectedTypes
        let pagesSnapshot = removalScope == .selected ? selectedPages : nil

        progress = 0
        isRunning = true
        status = "Processing..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try PDFAnnotationStripper.strip(
                    input: inputURL,
                    output: output,
                    selectedTypes: selectedSnapshot,
                    pagesToProcess: pagesSnapshot,
                    progress: { p in
                        DispatchQueue.main.async {
                            self?.progress = p
                        }
                    }
                )

                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.status = "Done: \(output.lastPathComponent)"
                    if let size = self?.fileSize(for: output) {
                        self?.estimatedFileSizeBytes = size
                        self?.lastEstimateKey = self?.makeEstimateKey()
                        self?.isEstimateStale = false
                    }
                    completion?(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.status = "Failed: \(error.localizedDescription)"
                    completion?(false)
                }
            }
        }
    }

    private func scanMarkedPages() {
        guard let inputURL else { return }

        let token = UUID()
        scanToken = token
        let typesSnapshot = selectedTypes

        isScanning = true
        scanProgress = 0
        markedPages = []
        documentTypeCounts = [:]
        perPageTypeCounts = [:]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let doc = PDFDocument(url: inputURL) else {
                DispatchQueue.main.async {
                    if self.scanToken == token {
                        self.isScanning = false
                    }
                }
                return
            }

            let total = doc.pageCount
            var pages: [Int] = []
            var perPage: [Int: [AnnotationKind: Int]] = [:]
            var totalCounts: [AnnotationKind: Int] = [:]

            if total == 0 {
                DispatchQueue.main.async {
                    if self.scanToken == token {
                        self.markedPages = []
                        self.documentTypeCounts = [:]
                        self.perPageTypeCounts = [:]
                        self.isScanning = false
                        self.scanProgress = 0
                        self.currentPageTypeCounts = [:]
                        self.selectedPagesTypeCounts = [:]
                    }
                }
                return
            }

            for index in 0..<total {
                if self.scanToken != token { return }
                autoreleasepool {
                    if let page = doc.page(at: index) {
                        var pageCounts: [AnnotationKind: Int] = [:]
                        for annot in page.annotations {
                            if let kind = PDFAnnotationStripper.kind(for: annot) {
                                pageCounts[kind, default: 0] += 1
                                totalCounts[kind, default: 0] += 1
                            }
                        }

                        if !pageCounts.isEmpty {
                            perPage[index + 1] = pageCounts
                        }

                        if !typesSnapshot.isEmpty {
                            let hasSelected = pageCounts.contains { typesSnapshot.contains($0.key) && $0.value > 0 }
                            if hasSelected {
                                pages.append(index + 1)
                            }
                        }
                    }
                }

                if index % self.scanUpdateStride == 0 {
                    let progress = Double(index + 1) / Double(total)
                    DispatchQueue.main.async {
                        if self.scanToken == token {
                            self.scanProgress = progress
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                if self.scanToken == token {
                    self.perPageTypeCounts = perPage
                    self.documentTypeCounts = totalCounts
                    self.markedPages = pages.sorted()
                    self.isScanning = false
                    self.scanProgress = 1

                    if self.removalScope == .selected {
                        self.isUpdatingSelection = true
                        if self.selectedPages.isEmpty {
                            self.selectedPages = Set(self.markedPages)
                        }
                        self.isUpdatingSelection = false
                    }

                    self.updateCurrentPageCounts()
                    self.updateSelectedPagesCounts()
                }
            }
        }
    }

    private func estimateOutputSize(forKey key: String) {
        guard let inputURL else { return }
        if isRunning { return }

        let canEstimate = !selectedTypes.isEmpty && (removalScope == .all || !selectedPages.isEmpty)
        if !canEstimate {
            estimatedFileSizeBytes = nil
            lastEstimateKey = nil
            isEstimateStale = true
            return
        }

        let token = UUID()
        estimateToken = token
        let typesSnapshot = selectedTypes
        let pagesSnapshot = removalScope == .selected ? selectedPages : nil

        isEstimatingSize = true
        estimateProgress = 0
        estimatedFileSizeBytes = nil
        isEstimateStale = true

        let tempName = "pdfmarkcleaner_estimate_\(UUID().uuidString).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempName)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                try PDFAnnotationStripper.strip(
                    input: inputURL,
                    output: tempURL,
                    selectedTypes: typesSnapshot,
                    pagesToProcess: pagesSnapshot,
                    progress: { p in
                        DispatchQueue.main.async {
                            if self.estimateToken == token {
                                self.estimateProgress = p
                            }
                        }
                    },
                    shouldCancel: { self.estimateToken != token }
                )

                let size = self.fileSize(for: tempURL)
                DispatchQueue.main.async {
                    if self.estimateToken == token {
                        self.estimatedFileSizeBytes = size
                        self.lastEstimateKey = key
                        self.isEstimatingSize = false
                        self.isEstimateStale = false
                    }
                }
            } catch StripError.cancelled {
                DispatchQueue.main.async {
                    if self.estimateToken == token {
                        self.isEstimatingSize = false
                        self.isEstimateStale = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if self.estimateToken == token {
                        self.isEstimatingSize = false
                        self.estimatedFileSizeBytes = nil
                        self.isEstimateStale = true
                    }
                }
            }

            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func updateFileSize(for url: URL) {
        inputFileSizeBytes = fileSize(for: url) ?? 0
    }

    private func updateMarkedPagesFromCounts() {
        if selectedTypes.isEmpty {
            markedPages = []
            return
        }

        var pages: [Int] = []
        for (pageNumber, counts) in perPageTypeCounts {
            let hasSelected = counts.contains { selectedTypes.contains($0.key) && $0.value > 0 }
            if hasSelected {
                pages.append(pageNumber)
            }
        }

        markedPages = pages.sorted()

        if removalScope == .selected, selectedPages.isEmpty, !markedPages.isEmpty {
            isUpdatingSelection = true
            selectedPages = Set(markedPages)
            isUpdatingSelection = false
        }

        updateSelectedPagesCounts()
    }

    private func updateCurrentPageCounts() {
        let pageNumber = clampPageNumber(currentPageNumber)
        if let cached = perPageTypeCounts[pageNumber] {
            currentPageTypeCounts = cached
            return
        }

        guard let doc = originalPreview ?? (inputURL != nil ? PDFDocument(url: inputURL!) : nil),
              let page = doc.page(at: pageNumber - 1) else {
            currentPageTypeCounts = [:]
            return
        }

        currentPageTypeCounts = countsForPage(page)
    }

    private func updateSelectedPagesCounts() {
        guard !selectedPages.isEmpty else {
            selectedPagesTypeCounts = [:]
            return
        }
        guard !perPageTypeCounts.isEmpty else {
            selectedPagesTypeCounts = [:]
            return
        }

        var counts: [AnnotationKind: Int] = [:]
        for page in selectedPages {
            if let pageCounts = perPageTypeCounts[page] {
                for (kind, value) in pageCounts {
                    counts[kind, default: 0] += value
                }
            }
        }
        selectedPagesTypeCounts = counts
    }

    private func countsForPage(_ page: PDFPage) -> [AnnotationKind: Int] {
        var counts: [AnnotationKind: Int] = [:]
        for annot in page.annotations {
            if let kind = PDFAnnotationStripper.kind(for: annot) {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }

    private func fileSize(for url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64
    }

    private func makeEstimateKey() -> String {
        let inputPath = inputURL?.path ?? ""
        let size = inputFileSizeBytes
        let types = selectedTypes.map { $0.rawValue }.sorted().joined(separator: ",")
        let pages: String
        if removalScope == .selected {
            pages = selectedPages.sorted().map(String.init).joined(separator: ",")
        } else {
            pages = ""
        }
        return "\(inputPath)|\(size)|types:\(types)|scope:\(removalScope.rawValue)|pages:\(pages)"
    }

    private func clampPageNumber(_ number: Int) -> Int {
        if pageCount == 0 { return max(1, number) }
        return max(1, min(number, pageCount))
    }

    private func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Confirm")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func resetState(statusMessage: String) {
        inputURL = nil
        outputURL = nil
        batchOutputDirectory = nil
        clearCurrentDocumentState(statusMessage: statusMessage)
    }

    private func clearCurrentDocumentState(statusMessage: String) {
        originalPreview = nil
        cleanedPreview = nil
        pageCount = 0
        currentPageNumber = 1
        markedPages = []
        selectedPages = []
        isScanning = false
        scanProgress = 0
        previewScale = 1.0
        cleanedProcessedPages.removeAll()
        scanToken = UUID()
        estimateToken = UUID()
        estimatedFileSizeBytes = nil
        isEstimatingSize = false
        estimateProgress = 0
        isEstimateStale = true
        inputFileSizeBytes = 0
        lastEstimateKey = nil
        documentTypeCounts = [:]
        currentPageTypeCounts = [:]
        selectedPagesTypeCounts = [:]
        perPageTypeCounts = [:]
        status = statusMessage
    }
}
