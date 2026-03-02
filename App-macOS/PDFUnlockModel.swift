import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine
import PDFKit
import PDFMarkCore

final class PDFUnlockModel: ObservableObject {
    @Published var processingMode: ProcessingMode = .single {
        didSet {
            guard processingMode != oldValue else { return }
            let modeSnapshot = processingMode
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.processingMode == modeSnapshot else { return }
                self.handleModeChanged(for: modeSnapshot)
            }
        }
    }
    @Published var batchInputURLs: [URL] = []
    @Published var batchIndex: Int = 0
    @Published var batchOutputDirectory: URL?
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var unlockPassword: String = "" {
        didSet {
            guard inputURL != nil else { return }
            refreshUnlockedPreview()
        }
    }
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var status = "Select a PDF file."

    @Published var originalPreview: PDFDocument?
    @Published var unlockedPreview: PDFDocument?
    @Published private(set) var pageCount: Int = 0
    @Published var currentPageNumber: Int = 1
    @Published var previewScale: CGFloat = 1.0
    @Published var isCurrentFileLocked = false
    @Published var passwordErrorMessage: String?

    private var lockStateByPath: [String: Bool] = [:]
    private var latestSingleProcessedInputPath: String?
    private var latestSingleProcessedOutputURL: URL?
    private var batchProcessedOutputByInputPath: [String: URL] = [:]
    private let minPreviewScale: CGFloat = 0.5
    private let maxPreviewScale: CGFloat = 3.0
    private nonisolated static let minimumProgressDisplayDuration: TimeInterval = 0.45

    var isBatchMode: Bool {
        processingMode == .batch
    }

    var hasLockedInputsInBatch: Bool {
        batchInputURLs.contains { isLockedDocument($0) }
    }

    var canProcess: Bool {
        guard hasInput else { return false }
        if requiresPasswordForRun {
            return !unlockPassword.isEmpty
        }
        return true
    }

    var canReplaceOriginal: Bool {
        guard !isRunning else { return false }
        guard inputURL != nil else { return false }
        if isBatchMode {
            return !processedBatchPairs().isEmpty
        }
        if currentProcessedSingleOutput() != nil {
            return true
        }
        return canProcess
    }

    var suggestedOutputURL: URL? {
        guard let inputURL else { return nil }
        return suggestedOutputURL(for: inputURL)
    }

    func suggestedOutputURL(for url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let filename = base + "_unlocked.pdf"
        if isBatchMode, let batchDir = batchOutputDirectory {
            return batchDir.appendingPathComponent(filename)
        }
        return url.deletingLastPathComponent().appendingPathComponent(filename)
    }

    func pickInput() {
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

    func pickBatchInputs() {
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
            processingMode = .batch
            applyBatchInputsSelection(pdfURLs)
            return
        }

        processingMode = .single
        open(url: pdfURLs[0])
    }

    func open(url: URL) {
        inputURL = url
        outputURL = nil
        currentPageNumber = 1
        status = "Selected: \(url.lastPathComponent)"
        loadDocuments(url: url)
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

    func clearSelection() {
        if isRunning {
            status = "Processing... Please wait."
            return
        }

        if isBatchMode {
            batchInputURLs = []
            batchIndex = 0
            batchOutputDirectory = nil
        }

        resetState(statusMessage: "Select a PDF file.")
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
        batchIndex = clamped

        let url = batchInputURLs[clamped]
        inputURL = url
        outputURL = nil
        currentPageNumber = 1
        status = "Selected: \(url.lastPathComponent)"
        loadDocuments(url: url)
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
        let removedPath = removed.standardizedFileURL.path
        let wasCurrent = inputURL == removed

        batchInputURLs.remove(at: index)
        lockStateByPath.removeValue(forKey: removedPath)
        batchProcessedOutputByInputPath.removeValue(forKey: removedPath)

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

    func start() {
        if isBatchMode {
            startBatch()
            return
        }

        guard canProcess else {
            status = requiresPasswordForRun ? "Enter a password for this PDF." : "Please select a PDF first."
            return
        }
        guard let inputURL else {
            status = "Please select a PDF first."
            return
        }
        if isRunning { return }

        let output = outputURL ?? suggestedOutputURL ?? inputURL
        runUnlock(input: inputURL, to: output)
    }

    func saveAs() {
        if isBatchMode {
            status = "Save is disabled in batch mode."
            return
        }
        guard canProcess else {
            status = requiresPasswordForRun ? "Enter a password for this PDF." : "Please select a PDF first."
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
            runUnlock(input: inputURL, to: url) { [weak self] success in
                guard success else { return }
                self?.clearAfterAction(message: "Saved: \(url.lastPathComponent)")
            }
        }
    }

    func replaceOriginal() {
        if isBatchMode {
            replaceBatchOriginals()
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

        if let processedOutput = currentProcessedSingleOutput() {
            do {
                try replaceInputFile(input: inputURL, withOutput: processedOutput)
                clearAfterAction(message: "Replaced: \(inputURL.lastPathComponent)")
            } catch {
                status = "Replace failed: \(error.localizedDescription)"
            }
            return
        }

        guard canProcess else {
            status = requiresPasswordForRun ? "Enter a password for this PDF." : "Please select a PDF first."
            return
        }

        let tempName = ".pdfunlocker_tmp_\(UUID().uuidString).pdf"
        let tempURL = inputURL.deletingLastPathComponent().appendingPathComponent(tempName)

        runUnlock(input: inputURL, to: tempURL) { [weak self] success in
            guard let self else { return }
            if !success { return }
            do {
                try self.replaceInputFile(input: inputURL, withOutput: tempURL)
                self.clearAfterAction(message: "Replaced: \(inputURL.lastPathComponent)")
            } catch {
                self.status = "Replace failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
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
            clearAfterAction(message: "Moved to Trash: \(inputURL.lastPathComponent)")
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
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

    func zoomIn() {
        adjustZoom(by: 0.1)
    }

    func zoomOut() {
        adjustZoom(by: -0.1)
    }

    func resetZoom() {
        previewScale = 1.0
    }

    func resolveBatchOutputURL(
        for preferred: URL,
        reservedPaths: inout Set<String>,
        pathExists: (String) -> Bool
    ) -> (url: URL, wasRenamed: Bool) {
        let preferredURL = preferred.standardizedFileURL
        let directory = preferredURL.deletingLastPathComponent()
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        let ext = preferredURL.pathExtension

        func normalized(_ url: URL) -> String {
            url.standardizedFileURL.path.lowercased()
        }

        var candidate = preferredURL
        var suffix = 2
        while true {
            let normalizedPath = normalized(candidate)
            let usedInRun = reservedPaths.contains(normalizedPath)
            let existsOnDisk = pathExists(candidate.path)
            if !usedInRun && !existsOnDisk {
                reservedPaths.insert(normalizedPath)
                return (candidate, candidate != preferredURL)
            }

            let filename: String
            if ext.isEmpty {
                filename = "\(baseName)_\(suffix)"
            } else {
                filename = "\(baseName)_\(suffix).\(ext)"
            }
            candidate = directory.appendingPathComponent(filename)
            suffix += 1
        }
    }

    func resolveBatchOutputURL(
        for preferred: URL,
        reservedPaths: inout Set<String>
    ) -> (url: URL, wasRenamed: Bool) {
        resolveBatchOutputURL(
            for: preferred,
            reservedPaths: &reservedPaths,
            pathExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    private var hasInput: Bool {
        if isBatchMode {
            return !batchInputURLs.isEmpty
        }
        return inputURL != nil
    }

    private var requiresPasswordForRun: Bool {
        if isBatchMode {
            return hasLockedInputsInBatch
        }
        return isCurrentFileLocked
    }

    private var normalizedPassword: String? {
        unlockPassword.isEmpty ? nil : unlockPassword
    }

    private func currentProcessedSingleOutput() -> URL? {
        guard let inputURL else { return nil }
        let inputPath = inputURL.standardizedFileURL.path
        guard latestSingleProcessedInputPath == inputPath,
              let output = latestSingleProcessedOutputURL else {
            return nil
        }
        let outputPath = output.standardizedFileURL.path
        guard outputPath != inputPath else { return nil }
        guard FileManager.default.fileExists(atPath: output.path) else { return nil }
        return output
    }

    private func recordSingleProcessedOutput(input: URL, output: URL) {
        latestSingleProcessedInputPath = input.standardizedFileURL.path
        latestSingleProcessedOutputURL = output.standardizedFileURL
    }

    private func processedBatchPairs() -> [(input: URL, output: URL)] {
        batchInputURLs.compactMap { input in
            let key = input.standardizedFileURL.path
            guard let output = batchProcessedOutputByInputPath[key] else {
                return nil
            }
            let outputPath = output.standardizedFileURL.path
            guard outputPath != key else { return nil }
            guard FileManager.default.fileExists(atPath: output.path) else {
                return nil
            }
            return (input, output)
        }
    }

    private func replaceBatchOriginals() {
        guard !batchInputURLs.isEmpty else {
            status = "Please select PDF files first."
            return
        }
        if isRunning { return }

        let pairs = processedBatchPairs()
        guard !pairs.isEmpty else {
            status = "No processed output files to replace."
            return
        }

        guard confirm(
            title: "Replace original PDFs?",
            message: "This will overwrite \(pairs.count) original file(s). This action cannot be undone."
        ) else {
            return
        }

        var replacedCount = 0
        var failedCount = 0

        for pair in pairs {
            do {
                try replaceInputFile(input: pair.input, withOutput: pair.output)
                replacedCount += 1
            } catch {
                failedCount += 1
            }
        }

        if let current = inputURL {
            loadDocuments(url: current)
        }

        if failedCount == 0 {
            status = "Replaced originals: \(replacedCount) file(s)"
        } else {
            status = "Replaced \(replacedCount) file(s), failed \(failedCount) file(s)"
        }
    }

    private func replaceInputFile(input: URL, withOutput output: URL) throws {
        let fileManager = FileManager.default

        if input.standardizedFileURL.path == output.standardizedFileURL.path {
            return
        }

        let tempName = ".pdfunlocker_replace_tmp_\(UUID().uuidString).pdf"
        let tempURL = input.deletingLastPathComponent().appendingPathComponent(tempName)

        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }

        try fileManager.copyItem(at: output, to: tempURL)
        do {
            _ = try fileManager.replaceItemAt(input, withItemAt: tempURL, backupItemName: nil, options: [])
            lockStateByPath[input.standardizedFileURL.path] = false
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private func startBatch() {
        guard !batchInputURLs.isEmpty else {
            status = "Please select PDF files first."
            return
        }
        if hasLockedInputsInBatch && unlockPassword.isEmpty {
            status = "Enter a password for locked PDFs."
            return
        }
        if isRunning { return }

        let urls = batchInputURLs
        let password = normalizedPassword
        var reservedOutputPaths = Set<String>()
        var renamedOutputCount = 0
        let processStart = Date()

        progress = 0
        isRunning = true
        status = Self.progressStatus(prefix: "Unlocking batch", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var lastError: Error?

            for (index, url) in urls.enumerated() {
                do {
                    let preferredOutput = self.suggestedOutputURL(for: url)
                    let resolved = self.resolveBatchOutputURL(
                        for: preferredOutput,
                        reservedPaths: &reservedOutputPaths
                    )
                    if resolved.wasRenamed {
                        renamedOutputCount += 1
                    }

                    try PDFUnlocker.unlock(
                        input: url,
                        output: resolved.url,
                        password: password,
                        progress: { p in
                            let overall = (Double(index) + p) / Double(urls.count)
                            DispatchQueue.main.async {
                                self.progress = overall
                                self.status = Self.progressStatus(
                                    prefix: "Unlocking batch \(index + 1)/\(urls.count)",
                                    progress: overall
                                )
                            }
                        }
                    )

                    if url == self.inputURL {
                        DispatchQueue.main.async {
                            self.batchProcessedOutputByInputPath[url.standardizedFileURL.path] = resolved.url.standardizedFileURL
                            self.unlockedPreview = PDFDocument(url: resolved.url)
                            if let count = self.unlockedPreview?.pageCount, count > 0 {
                                self.pageCount = count
                                self.currentPageNumber = self.clampPageNumber(self.currentPageNumber)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.batchProcessedOutputByInputPath[url.standardizedFileURL.path] = resolved.url.standardizedFileURL
                        }
                    }
                } catch {
                    lastError = error
                    break
                }
            }

            let remaining = Self.remainingProgressDelay(startedAt: processStart)
            if remaining > 0 {
                Thread.sleep(forTimeInterval: remaining)
            }

            DispatchQueue.main.async {
                self.isRunning = false
                if let error = lastError {
                    self.status = "Batch failed: \(error.localizedDescription)"
                    if let unlockError = error as? PDFUnlockError, unlockError == .invalidPassword {
                        self.passwordErrorMessage = "Invalid password."
                    }
                } else {
                    self.progress = 1
                    self.passwordErrorMessage = nil
                    if renamedOutputCount > 0 {
                        self.status = "Batch done: \(urls.count) files (renamed: \(renamedOutputCount))"
                    } else {
                        self.status = "Batch done: \(urls.count) files"
                    }
                }
            }
        }
    }

    private func runUnlock(input: URL, to output: URL, completion: ((Bool) -> Void)? = nil) {
        if isCurrentFileLocked && unlockPassword.isEmpty {
            status = "Enter a password for this PDF."
            completion?(false)
            return
        }
        if isRunning { return }

        let password = normalizedPassword
        let processStart = Date()

        progress = 0
        isRunning = true
        status = Self.progressStatus(prefix: "Unlocking", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try PDFUnlocker.unlock(
                    input: input,
                    output: output,
                    password: password,
                    progress: { p in
                        DispatchQueue.main.async {
                            self?.progress = p
                            self?.status = Self.progressStatus(prefix: "Unlocking", progress: p)
                        }
                    }
                )

                let remaining = Self.remainingProgressDelay(startedAt: processStart)
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }

                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.progress = 1
                    self?.status = "Done: \(output.lastPathComponent)"
                    self?.passwordErrorMessage = nil
                    if let self {
                        self.recordSingleProcessedOutput(input: input, output: output)
                    }
                    if input == self?.inputURL {
                        self?.unlockedPreview = PDFDocument(url: output)
                        if let count = self?.unlockedPreview?.pageCount, count > 0 {
                            self?.pageCount = count
                            if let current = self?.currentPageNumber {
                                self?.currentPageNumber = self?.clampPageNumber(current) ?? current
                            }
                        }
                    }
                    completion?(true)
                }
            } catch {
                let remaining = Self.remainingProgressDelay(startedAt: processStart)
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }

                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.status = "Failed: \(error.localizedDescription)"
                    if let unlockError = error as? PDFUnlockError, unlockError == .invalidPassword {
                        self?.passwordErrorMessage = "Invalid password."
                    }
                    completion?(false)
                }
            }
        }
    }

    private func loadDocuments(url: URL) {
        originalPreview = PDFDocument(url: url)
        pageCount = originalPreview?.pageCount ?? 0

        let locked = isLockedDocument(url)
        isCurrentFileLocked = locked
        if !locked {
            passwordErrorMessage = nil
        }

        if pageCount == 0 {
            currentPageNumber = 1
        } else {
            currentPageNumber = clampPageNumber(currentPageNumber)
        }

        refreshUnlockedPreview()
    }

    private func refreshUnlockedPreview() {
        guard let inputURL else {
            unlockedPreview = nil
            isCurrentFileLocked = false
            passwordErrorMessage = nil
            return
        }

        do {
            let doc = try PDFUnlocker.makeUnlockedDocument(input: inputURL, password: normalizedPassword)
            unlockedPreview = doc
            pageCount = max(pageCount, doc.pageCount)
            currentPageNumber = clampPageNumber(currentPageNumber)
            passwordErrorMessage = nil
        } catch let error as PDFUnlockError {
            unlockedPreview = nil
            switch error {
            case .invalidPassword:
                passwordErrorMessage = "Invalid password."
            case .passwordRequired:
                passwordErrorMessage = nil
            default:
                passwordErrorMessage = nil
            }
        } catch {
            unlockedPreview = nil
            passwordErrorMessage = nil
        }
    }

    private func isLockedDocument(_ url: URL) -> Bool {
        let key = url.standardizedFileURL.path
        if let cached = lockStateByPath[key] {
            return cached
        }

        let locked = PDFDocument(url: url)?.isLocked ?? false
        lockStateByPath[key] = locked
        return locked
    }

    private func applyBatchInputsSelection(_ urls: [URL]) {
        batchInputURLs = urls
        batchIndex = 0

        let allowed = Set(urls.map { $0.standardizedFileURL.path })
        lockStateByPath = lockStateByPath.filter { allowed.contains($0.key) }
        batchProcessedOutputByInputPath = batchProcessedOutputByInputPath.filter { allowed.contains($0.key) }

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
            lockStateByPath.removeValue(forKey: inputURL.standardizedFileURL.path)

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

    private func handleModeChanged(for mode: ProcessingMode) {
        if mode == .batch {
            if batchInputURLs.isEmpty, let current = inputURL {
                batchInputURLs = [current]
                batchIndex = 0
            }
            if !batchInputURLs.isEmpty {
                switchToBatchIndex(min(batchIndex, batchInputURLs.count - 1))
            } else {
                resetState(statusMessage: "Select a PDF file.")
            }
        } else {
            batchOutputDirectory = nil
            if let current = inputURL {
                batchInputURLs = []
                batchIndex = 0
                open(url: current)
            }
        }
    }

    private func adjustZoom(by delta: CGFloat) {
        let newValue = previewScale + delta
        let clamped = min(max(newValue, minPreviewScale), maxPreviewScale)
        previewScale = clamped
    }

    private func clampPageNumber(_ number: Int) -> Int {
        if pageCount == 0 { return max(1, number) }
        return max(1, min(number, pageCount))
    }

    private nonisolated static func progressStatus(prefix: String, progress: Double) -> String {
        let clamped = max(0, min(1, progress))
        let percent = Int((clamped * 100).rounded())
        return "\(prefix) (\(percent)%)"
    }

    private nonisolated static func remainingProgressDelay(startedAt: Date) -> TimeInterval {
        let elapsed = Date().timeIntervalSince(startedAt)
        return max(0, minimumProgressDisplayDuration - elapsed)
    }

    private func clearAfterAction(message: String) {
        clearSelection()
        status = "File processing completed. \(message)"
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
        unlockedPreview = nil
        pageCount = 0
        currentPageNumber = 1
        previewScale = 1.0
        isCurrentFileLocked = false
        passwordErrorMessage = nil
        progress = 0
        isRunning = false
        lockStateByPath.removeAll()
        batchProcessedOutputByInputPath.removeAll()
        latestSingleProcessedInputPath = nil
        latestSingleProcessedOutputURL = nil
        status = statusMessage
    }
}
