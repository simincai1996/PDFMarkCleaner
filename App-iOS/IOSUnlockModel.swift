import Foundation
import PDFKit
import Combine
import UniformTypeIdentifiers
import PDFMarkCore

enum IOSUnlockProcessingMode: String, CaseIterable, Identifiable {
    case single
    case batch

    var id: String { rawValue }
}

@MainActor
final class IOSUnlockModel: ObservableObject, @unchecked Sendable {
    @Published var processingMode: IOSUnlockProcessingMode = .single {
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
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var batchOutputURLs: [URL] = []
    @Published var unlockPassword = "" {
        didSet {
            guard inputURL != nil else { return }
            refreshUnlockedPreview()
        }
    }
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var status: String = "请选择 PDF 文件。"

    @Published var originalPreview: PDFDocument?
    @Published var unlockedPreview: PDFDocument?
    @Published var pageCount: Int = 0
    @Published var currentPageNumber: Int = 1
    @Published var previewScale: CGFloat = 1.0
    @Published var isCurrentFileLocked = false
    @Published var passwordErrorMessage: String?
    @Published var errorMessage: String?

    private nonisolated static let minimumProgressDisplayDuration: TimeInterval = 0.45

    private var outputByInputPath: [String: URL] = [:]
    private var scopedURLsByPath: [String: URL] = [:]
    private var previewLocalCopyByInputPath: [String: URL] = [:]
    private var lockStateByPath: [String: Bool] = [:]
    private var latestSingleProcessedInputPath: String?
    private var latestSingleProcessedOutputURL: URL?

    private let minPreviewScale: CGFloat = 0.5
    private let maxPreviewScale: CGFloat = 3.0

    var isBatchMode: Bool {
        processingMode == .batch
    }

    var canProcess: Bool {
        guard !isRunning else { return false }
        guard hasInput else { return false }
        if requiresPasswordForRun {
            return !unlockPassword.isEmpty
        }
        return true
    }

    var canSaveAsSingle: Bool {
        !isRunning && !isBatchMode && outputURL != nil
    }

    var canSaveAsBatch: Bool {
        !isRunning && isBatchMode && !batchOutputURLs.isEmpty
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

    var canDeleteOriginal: Bool {
        guard !isRunning else { return false }
        if isBatchMode {
            return !batchInputURLs.isEmpty
        }
        return inputURL != nil
    }

    var batchReplaceReadyCount: Int {
        processedBatchPairs().count
    }

    var batchDocumentCount: Int {
        batchInputURLs.count
    }

    var hasLockedInputsInBatch: Bool {
        batchInputURLs.contains { isLockedDocument($0) }
    }

    var suggestedOutputFilename: String {
        guard let inputURL else { return "unlocked.pdf" }
        return Self.outputFileName(for: inputURL)
    }

    func handlePickedFiles(_ urls: [URL], allowBatch: Bool) {
        let normalizedURLs = urls.filter { $0.isFileURL }

        for url in normalizedURLs {
            retainSecurityScope(for: url)
        }

        let pickedFiles = normalizedPickedFiles(from: normalizedURLs)
        let acceptedPaths = Set(pickedFiles.map { $0.standardizedFileURL.path })
        for url in normalizedURLs where !acceptedPaths.contains(url.standardizedFileURL.path) {
            releaseSecurityScope(for: url)
        }

        guard !pickedFiles.isEmpty else {
            status = "请选择 PDF 文件。"
            return
        }

        if !allowBatch, pickedFiles.count > 1 {
            for skipped in pickedFiles.dropFirst() {
                releaseSecurityScope(for: skipped)
            }
        }

        if allowBatch, (processingMode == .batch || pickedFiles.count > 1) {
            processingMode = .batch
            appendBatchInputs(pickedFiles)
            return
        }

        processingMode = .single
        openSingle(pickedFiles[0])
        if !allowBatch && pickedFiles.count > 1 {
            status = "已关闭高级批处理，仅导入第一个文件。"
        }
    }

    func switchToBatchIndex(_ index: Int) {
        guard batchInputURLs.indices.contains(index) else { return }
        batchIndex = index
        inputURL = batchInputURLs[index]
        refreshCurrentDocumentState()
        status = "批处理文件：\(index + 1)/\(batchInputURLs.count)"
    }

    func stepBatchItem(_ delta: Int) {
        let next = batchIndex + delta
        switchToBatchIndex(next)
    }

    func removeBatchInput(at index: Int) {
        guard !isRunning else { return }
        guard batchInputURLs.indices.contains(index) else { return }

        let removed = batchInputURLs.remove(at: index)
        let removedPath = removed.standardizedFileURL.path
        releaseSecurityScope(forPath: removedPath)
        removePreviewLocalCopy(forPath: removedPath)
        outputByInputPath.removeValue(forKey: removedPath)
        lockStateByPath.removeValue(forKey: removedPath)
        batchOutputURLs.removeAll { $0.lastPathComponent == Self.outputFileName(for: removed) }

        guard !batchInputURLs.isEmpty else {
            clearInputs()
            processingMode = .batch
            status = "批处理列表已清空。"
            return
        }

        let nextIndex = min(index, batchInputURLs.count - 1)
        switchToBatchIndex(nextIndex)
    }

    func clearInputs() {
        releaseAllSecurityScopes()
        clearPreviewLocalCopies()
        isRunning = false
        inputURL = nil
        outputURL = nil
        batchInputURLs = []
        batchOutputURLs = []
        batchIndex = 0
        pageCount = 0
        currentPageNumber = 1
        previewScale = 1.0
        originalPreview = nil
        unlockedPreview = nil
        progress = 0
        outputByInputPath.removeAll()
        lockStateByPath.removeAll()
        latestSingleProcessedInputPath = nil
        latestSingleProcessedOutputURL = nil
        passwordErrorMessage = nil
        errorMessage = nil
        status = "请选择 PDF 文件。"
    }

    func process() {
        if isBatchMode {
            processBatch()
        } else {
            processSingle()
        }
    }

    func prepareSingleExportPayload() -> (data: Data, filename: String)? {
        guard let outputURL else {
            status = "请先完成解锁，再执行另存。"
            return nil
        }

        do {
            let data = try Self.readData(from: outputURL)
            return (data, outputURL.lastPathComponent)
        } catch {
            status = "读取导出文件失败：\(error.localizedDescription)"
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func markSingleSaveAsCompleted(destination: URL) {
        clearAfterAction(message: "已另存：\(destination.lastPathComponent)")
    }

    func saveBatchOutputs(to directoryURL: URL) {
        guard !isRunning else { return }
        guard isBatchMode else {
            status = "当前不是批处理模式。"
            return
        }
        guard !batchOutputURLs.isEmpty else {
            status = "请先完成批处理，再执行另存。"
            return
        }

        let outputs = batchOutputURLs
        isRunning = true
        progress = 0
        errorMessage = nil
        status = Self.progressStatus(prefix: "正在批量另存", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var copied = 0
            var failed = 0
            var reserved = Set<String>()

            let hasDirectoryAccess = directoryURL.startAccessingSecurityScopedResource()
            defer {
                if hasDirectoryAccess {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }

            for (index, output) in outputs.enumerated() {
                do {
                    try Self.copyOutput(output, toDirectory: directoryURL, reservedPaths: &reserved)
                    copied += 1
                } catch {
                    failed += 1
                }

                let overall = Double(index + 1) / Double(outputs.count)
                Task { @MainActor in
                    self.progress = overall
                    self.status = Self.progressStatus(
                        prefix: "正在批量另存 \(index + 1)/\(outputs.count)",
                        progress: overall
                    )
                }
            }

            let finalCopied = copied
            let finalFailed = failed
            Task { @MainActor in
                self.isRunning = false
                self.progress = 1
                if finalFailed == 0 {
                    self.clearAfterAction(message: "批量另存完成：\(finalCopied) 个文件。")
                } else {
                    self.clearAfterAction(message: "批量另存完成：成功 \(finalCopied) 个，失败 \(finalFailed) 个。")
                }
            }
        }
    }

    func replaceOriginals() {
        if isBatchMode {
            replaceBatchOriginals()
        } else {
            replaceSingleOriginal()
        }
    }

    func deleteOriginals() {
        if isBatchMode {
            deleteBatchOriginals()
        } else {
            deleteSingleOriginal()
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

    private func processSingle() {
        guard let sourceURL = inputURL else {
            status = "请先选择 PDF 文件。"
            return
        }
        guard canProcess else {
            status = requiresPasswordForRun ? "请输入 PDF 密码。" : "请先选择 PDF 文件。"
            return
        }

        let password = normalizedPassword
        let processStart = Date()
        isRunning = true
        progress = 0
        errorMessage = nil
        passwordErrorMessage = nil
        status = Self.progressStatus(prefix: "正在解锁", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let workDirectory = try Self.makeWorkDirectory()
                let localInput = workDirectory.appendingPathComponent("input.pdf")
                try Self.copyInputPDF(from: sourceURL, to: localInput)
                let output = workDirectory.appendingPathComponent(Self.outputFileName(for: sourceURL))

                try PDFUnlocker.unlock(
                    input: localInput,
                    output: output,
                    password: password,
                    progress: { p in
                        Task { @MainActor in
                            self.progress = p
                            self.status = Self.progressStatus(prefix: "正在解锁", progress: p)
                        }
                    }
                )

                let unlocked = (try? Self.readData(from: output)).flatMap(PDFDocument.init(data:))
                Self.runOnMainAfterMinimumProgressDuration(startedAt: processStart) { [weak self] in
                    guard let self else { return }
                    self.outputURL = output
                    self.outputByInputPath[sourceURL.standardizedFileURL.path] = output
                    self.recordSingleProcessedOutput(input: sourceURL, output: output)
                    self.unlockedPreview = unlocked
                    if let count = unlocked?.pageCount, count > 0 {
                        self.pageCount = count
                        self.currentPageNumber = self.clampPageNumber(self.currentPageNumber)
                    }
                    self.progress = 1
                    self.status = "解锁完成，可直接分享导出。"
                    self.isRunning = false
                    self.passwordErrorMessage = nil
                }
            } catch {
                Self.runOnMainAfterMinimumProgressDuration(startedAt: processStart) { [weak self] in
                    guard let self else { return }
                    self.isRunning = false
                    self.status = "解锁失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                    if let unlockError = error as? PDFUnlockError, unlockError == .invalidPassword {
                        self.passwordErrorMessage = "密码错误。"
                    }
                }
            }
        }
    }

    private func processBatch() {
        guard !batchInputURLs.isEmpty else {
            status = "请先选择批处理文件。"
            return
        }
        guard canProcess else {
            status = requiresPasswordForRun ? "请输入批量文件密码。" : "请先选择批处理文件。"
            return
        }

        let urls = batchInputURLs
        let password = normalizedPassword
        let processStart = Date()
        isRunning = true
        progress = 0
        errorMessage = nil
        passwordErrorMessage = nil
        status = Self.progressStatus(prefix: "正在批处理解锁", progress: 0)
        batchOutputURLs = []
        outputByInputPath.removeAll()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let workDirectory = try Self.makeWorkDirectory()
                var outputs: [URL] = []
                var reserved = Set<String>()

                for (index, sourceURL) in urls.enumerated() {
                    let localInput = workDirectory.appendingPathComponent("input-\(index).pdf")
                    try Self.copyInputPDF(from: sourceURL, to: localInput)
                    let preferred = workDirectory.appendingPathComponent(Self.outputFileName(for: sourceURL))
                    let output = Self.resolveBatchOutputURL(for: preferred, reservedPaths: &reserved)

                    try PDFUnlocker.unlock(
                        input: localInput,
                        output: output,
                        password: password,
                        progress: { p in
                            let overall = (Double(index) + p) / Double(urls.count)
                            Task { @MainActor in
                                self.progress = overall
                                self.status = Self.progressStatus(
                                    prefix: "正在批处理解锁 \(index + 1)/\(urls.count)",
                                    progress: overall
                                )
                            }
                        }
                    )

                    outputs.append(output)
                    Task { @MainActor in
                        self.outputByInputPath[sourceURL.standardizedFileURL.path] = output
                    }
                }

                let finalOutputs = outputs
                Self.runOnMainAfterMinimumProgressDuration(startedAt: processStart) { [weak self] in
                    guard let self else { return }
                    self.batchOutputURLs = finalOutputs
                    self.progress = 1
                    self.isRunning = false
                    self.passwordErrorMessage = nil
                    self.status = "批处理解锁完成，共 \(finalOutputs.count) 个文件。"
                    self.refreshCurrentDocumentState()
                }
            } catch {
                Self.runOnMainAfterMinimumProgressDuration(startedAt: processStart) { [weak self] in
                    guard let self else { return }
                    self.isRunning = false
                    self.status = "批处理解锁失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                    if let unlockError = error as? PDFUnlockError, unlockError == .invalidPassword {
                        self.passwordErrorMessage = "密码错误。"
                    }
                }
            }
        }
    }

    private func replaceSingleOriginal() {
        guard let inputURL else {
            status = "请先选择文件。"
            return
        }
        guard !isRunning else { return }

        if let processedOutput = currentProcessedSingleOutput() {
            do {
                try Self.overwriteFile(at: inputURL, with: processedOutput)
                lockStateByPath[inputURL.standardizedFileURL.path] = false
                clearAfterAction(message: "已替换原文件：\(inputURL.lastPathComponent)")
            } catch {
                status = "替换失败：\(error.localizedDescription)"
                errorMessage = error.localizedDescription
            }
            return
        }

        guard canProcess else {
            status = requiresPasswordForRun ? "请输入 PDF 密码。" : "请先完成解锁，再替换原文件。"
            return
        }

        isRunning = true
        progress = 0
        errorMessage = nil
        passwordErrorMessage = nil
        status = Self.progressStatus(prefix: "正在替换原文件", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let workDirectory = try Self.makeWorkDirectory()
                let localInput = workDirectory.appendingPathComponent("replace-input.pdf")
                try Self.copyInputPDF(from: inputURL, to: localInput)
                let localOutput = workDirectory.appendingPathComponent("replace-output.pdf")

                try PDFUnlocker.unlock(
                    input: localInput,
                    output: localOutput,
                    password: normalizedPassword,
                    progress: { p in
                        Task { @MainActor in
                            self.progress = p
                            self.status = Self.progressStatus(prefix: "正在替换原文件", progress: p)
                        }
                    }
                )

                try Self.overwriteFile(at: inputURL, with: localOutput)
                lockStateByPath[inputURL.standardizedFileURL.path] = false

                Task { @MainActor in
                    self.isRunning = false
                    self.progress = 1
                    self.clearAfterAction(message: "已替换原文件：\(inputURL.lastPathComponent)")
                }
            } catch {
                Task { @MainActor in
                    self.isRunning = false
                    self.status = "替换失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                    if let unlockError = error as? PDFUnlockError, unlockError == .invalidPassword {
                        self.passwordErrorMessage = "密码错误。"
                    }
                }
            }
        }
    }

    private func replaceBatchOriginals() {
        let pairs = processedBatchPairs()
        guard !pairs.isEmpty else {
            status = "没有可替换的批处理结果，请先完成批处理。"
            return
        }
        guard !isRunning else { return }

        isRunning = true
        progress = 0
        errorMessage = nil
        status = Self.progressStatus(prefix: "正在批量替换原文件", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var replaced = 0
            var failed = 0

            for (index, pair) in pairs.enumerated() {
                do {
                    try Self.overwriteFile(at: pair.input, with: pair.output)
                    lockStateByPath[pair.input.standardizedFileURL.path] = false
                    replaced += 1
                } catch {
                    failed += 1
                }

                let overall = Double(index + 1) / Double(pairs.count)
                Task { @MainActor in
                    self.progress = overall
                    self.status = Self.progressStatus(
                        prefix: "正在批量替换原文件 \(index + 1)/\(pairs.count)",
                        progress: overall
                    )
                }
            }

            let finalReplaced = replaced
            let finalFailed = failed
            Task { @MainActor in
                self.isRunning = false
                self.progress = 1
                if finalFailed == 0 {
                    self.clearAfterAction(message: "批量替换完成：\(finalReplaced) 个文件。")
                } else {
                    self.clearAfterAction(message: "批量替换完成：成功 \(finalReplaced) 个，失败 \(finalFailed) 个。")
                }
            }
        }
    }

    private func deleteSingleOriginal() {
        guard let inputURL else {
            status = "请先选择文件。"
            return
        }
        guard !isRunning else { return }

        isRunning = true
        progress = 0
        errorMessage = nil
        status = Self.progressStatus(prefix: "正在删除原文件", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try Self.removeFile(inputURL)
                Task { @MainActor in
                    self.isRunning = false
                    self.progress = 1
                    self.clearAfterAction(message: "已删除原文件：\(inputURL.lastPathComponent)")
                }
            } catch {
                Task { @MainActor in
                    self.isRunning = false
                    self.status = "删除失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteBatchOriginals() {
        guard !batchInputURLs.isEmpty else {
            status = "批处理列表为空。"
            return
        }
        guard !isRunning else { return }

        let urls = batchInputURLs
        isRunning = true
        progress = 0
        errorMessage = nil
        status = Self.progressStatus(prefix: "正在批量删除原文件", progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var deleted = 0
            var failed = 0

            for (index, url) in urls.enumerated() {
                do {
                    try Self.removeFile(url)
                    deleted += 1
                } catch {
                    failed += 1
                }

                let overall = Double(index + 1) / Double(urls.count)
                Task { @MainActor in
                    self.progress = overall
                    self.status = Self.progressStatus(
                        prefix: "正在批量删除原文件 \(index + 1)/\(urls.count)",
                        progress: overall
                    )
                }
            }

            let finalDeleted = deleted
            let finalFailed = failed
            Task { @MainActor in
                self.isRunning = false
                self.progress = 1
                if finalFailed == 0 {
                    self.clearAfterAction(message: "批量删除完成：\(finalDeleted) 个文件。")
                } else {
                    self.clearAfterAction(message: "批量删除完成：成功 \(finalDeleted) 个，失败 \(finalFailed) 个。")
                }
            }
        }
    }

    private func recordSingleProcessedOutput(input: URL, output: URL) {
        latestSingleProcessedInputPath = input.standardizedFileURL.path
        latestSingleProcessedOutputURL = output.standardizedFileURL
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

    private func processedBatchPairs() -> [(input: URL, output: URL)] {
        batchInputURLs.compactMap { input in
            let key = input.standardizedFileURL.path
            guard let output = outputByInputPath[key] else { return nil }
            let outputPath = output.standardizedFileURL.path
            guard outputPath != key else { return nil }
            guard FileManager.default.fileExists(atPath: output.path) else { return nil }
            return (input, output)
        }
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

    private nonisolated static func progressStatus(prefix: String, progress: Double) -> String {
        let clamped = max(0, min(1, progress))
        let percent = Int((clamped * 100).rounded())
        return "\(prefix)（\(percent)%）"
    }

    private nonisolated static func runOnMainAfterMinimumProgressDuration(
        startedAt: Date,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, minimumProgressDisplayDuration - elapsed)
        _ = Task {
            if remaining > 0 {
                let nanoseconds = UInt64((remaining * 1_000_000_000).rounded(.up))
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            await MainActor.run {
                action()
            }
        }
    }

    private func clearAfterAction(message: String) {
        clearInputs()
        status = "文件已完成处理。\(message)"
    }

    // 中文说明：统一使用 Data 构建预览，避免 iPad 文件提供器下 URL 懒加载失效。
    private func readPDFDocument(from url: URL) -> PDFDocument? {
        if let data = try? Self.readData(from: url),
           let document = PDFDocument(data: data) {
            return document
        }
        if let localCopy = ensurePreviewLocalCopy(for: url) {
            if let document = PDFDocument(url: localCopy) {
                return document
            }
            if let copiedData = try? Data(contentsOf: localCopy) {
                return PDFDocument(data: copiedData)
            }
        }
        return nil
    }

    private nonisolated static func readData(from url: URL) throws -> Data {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let coordinated = try coordinatedReadData(from: url) {
            return coordinated
        }
        return try Data(contentsOf: url)
    }

    private nonisolated static func coordinatedReadData(from url: URL) throws -> Data? {
        var coordinatorError: NSError?
        var readError: Error?
        var result: Data?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { coordinatedURL in
            do {
                if let mapped = try? Data(contentsOf: coordinatedURL, options: [.mappedIfSafe]) {
                    result = mapped
                } else {
                    result = try Data(contentsOf: coordinatedURL)
                }
            } catch {
                readError = error
            }
        }

        if let readError {
            throw readError
        }
        if coordinatorError != nil {
            return nil
        }
        return result
    }

    private nonisolated static func makePreviewLocalCopy(of sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let previewRoot = fileManager.temporaryDirectory
            .appendingPathComponent("pdf-preview-cache", isDirectory: true)
        try fileManager.createDirectory(at: previewRoot, withIntermediateDirectories: true)

        let pathExtension = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        let temporaryURL = previewRoot
            .appendingPathComponent("pdf-preview-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinatorError) { coordinatedURL in
            do {
                if fileManager.fileExists(atPath: temporaryURL.path) {
                    try fileManager.removeItem(at: temporaryURL)
                }
                try fileManager.copyItem(at: coordinatedURL, to: temporaryURL)
            } catch {
                copyError = error
            }
        }

        if let copyError {
            throw copyError
        }
        if let coordinatorError {
            throw coordinatorError
        }
        if !fileManager.fileExists(atPath: temporaryURL.path) {
            throw CocoaError(.fileNoSuchFile)
        }
        return temporaryURL
    }

    private nonisolated static func copyOutput(_ source: URL, toDirectory directory: URL, reservedPaths: inout Set<String>) throws {
        let fileManager = FileManager.default
        let preferred = directory.appendingPathComponent(source.lastPathComponent)
        let destination = resolveBatchOutputURL(for: preferred, reservedPaths: &reservedPaths)

        let hasSourceAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasSourceAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private nonisolated static func overwriteFile(at destination: URL, with source: URL) throws {
        let destinationPath = destination.standardizedFileURL.path
        let sourcePath = source.standardizedFileURL.path
        if destinationPath == sourcePath {
            return
        }

        let fileManager = FileManager.default
        let hasDestinationAccess = destination.startAccessingSecurityScopedResource()
        let hasSourceAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasDestinationAccess {
                destination.stopAccessingSecurityScopedResource()
            }
            if hasSourceAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private nonisolated static func removeFile(_ url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // 中文说明：为每次处理创建独立目录，避免多次操作互相覆盖。
    private nonisolated static func makeWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-unlock-ios-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // 中文说明：将输入 PDF 复制到沙盒临时目录后再处理，可减少权限与原文件锁定问题。
    private nonisolated static func copyInputPDF(from sourceURL: URL, to localInput: URL) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        if FileManager.default.fileExists(atPath: localInput.path) {
            try FileManager.default.removeItem(at: localInput)
        }
        try FileManager.default.copyItem(at: sourceURL, to: localInput)
    }

    private nonisolated static func outputFileName(for sourceURL: URL) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        return "\(base)_unlocked.pdf"
    }

    private nonisolated static func resolveBatchOutputURL(for preferred: URL, reservedPaths: inout Set<String>) -> URL {
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
            let existsOnDisk = FileManager.default.fileExists(atPath: candidate.path)
            if !usedInRun && !existsOnDisk {
                reservedPaths.insert(normalizedPath)
                return candidate
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

    private func handleModeChanged(for mode: IOSUnlockProcessingMode) {
        if mode == .batch {
            if batchInputURLs.isEmpty, let current = inputURL {
                batchInputURLs = [current]
                batchIndex = 0
            }
            if !batchInputURLs.isEmpty {
                switchToBatchIndex(min(batchIndex, batchInputURLs.count - 1))
            }
        } else {
            if let current = inputURL {
                let currentPath = current.standardizedFileURL.path
                for url in batchInputURLs where url.standardizedFileURL.path != currentPath {
                    releaseSecurityScope(for: url)
                    removePreviewLocalCopy(forPath: url.standardizedFileURL.path)
                    outputByInputPath.removeValue(forKey: url.standardizedFileURL.path)
                    lockStateByPath.removeValue(forKey: url.standardizedFileURL.path)
                }
                batchInputURLs = []
                batchIndex = 0
                openSingle(current)
            }
        }
    }

    private func openSingle(_ url: URL) {
        if let previous = inputURL,
           previous.standardizedFileURL.path != url.standardizedFileURL.path {
            let previousPath = previous.standardizedFileURL.path
            let stillTrackedInBatch = batchInputURLs.contains { $0.standardizedFileURL.path == previousPath }
            if !stillTrackedInBatch {
                releaseSecurityScope(forPath: previousPath)
                removePreviewLocalCopy(forPath: previousPath)
            }
        }

        retainSecurityScope(for: url)
        inputURL = url
        outputURL = outputByInputPath[url.standardizedFileURL.path]
        originalPreview = readPDFDocument(from: url)
        pageCount = originalPreview?.pageCount ?? 0
        currentPageNumber = clampPageNumber(currentPageNumber)
        if originalPreview == nil {
            status = "已选择：\(url.lastPathComponent)，但预览读取失败。"
        } else {
            status = "已选择：\(url.lastPathComponent)"
        }
        progress = 0
        previewScale = 1.0
        isCurrentFileLocked = isLockedDocument(url)
        if !isCurrentFileLocked {
            passwordErrorMessage = nil
        }
        refreshUnlockedPreview()
    }

    private func appendBatchInputs(_ urls: [URL]) {
        var known = Set(batchInputURLs.map { $0.standardizedFileURL.path })
        var additions: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if known.insert(path).inserted {
                additions.append(url)
            }
        }
        guard !additions.isEmpty else {
            status = "没有新增 PDF 文件。"
            return
        }
        let wasEmpty = batchInputURLs.isEmpty
        batchInputURLs.append(contentsOf: additions)
        if wasEmpty || inputURL == nil {
            switchToBatchIndex(0)
        } else {
            status = "已新增 \(additions.count) 个文件。"
        }
    }

    private func refreshCurrentDocumentState() {
        guard let inputURL else {
            originalPreview = nil
            unlockedPreview = nil
            pageCount = 0
            return
        }
        originalPreview = readPDFDocument(from: inputURL)
        outputURL = outputByInputPath[inputURL.standardizedFileURL.path]
        pageCount = originalPreview?.pageCount ?? 0
        currentPageNumber = clampPageNumber(currentPageNumber)
        isCurrentFileLocked = isLockedDocument(inputURL)
        if !isCurrentFileLocked {
            passwordErrorMessage = nil
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

        if let outputURL = outputByInputPath[inputURL.standardizedFileURL.path],
           let data = try? Self.readData(from: outputURL),
           let document = PDFDocument(data: data) {
            unlockedPreview = document
            pageCount = max(pageCount, document.pageCount)
            currentPageNumber = clampPageNumber(currentPageNumber)
            passwordErrorMessage = nil
            return
        }

        do {
            let document = try PDFUnlocker.makeUnlockedDocument(input: inputURL, password: normalizedPassword)
            unlockedPreview = document
            pageCount = max(pageCount, document.pageCount)
            currentPageNumber = clampPageNumber(currentPageNumber)
            passwordErrorMessage = nil
        } catch let error as PDFUnlockError {
            unlockedPreview = nil
            switch error {
            case .invalidPassword:
                passwordErrorMessage = "密码错误。"
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

        let locked = readPDFDocument(from: url)?.isLocked ?? false
        lockStateByPath[key] = locked
        return locked
    }

    private func normalizedPickedFiles(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            guard url.isFileURL else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                continue
            }
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    private func retainSecurityScope(for url: URL) {
        let key = url.standardizedFileURL.path
        guard scopedURLsByPath[key] == nil else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        scopedURLsByPath[key] = url
    }

    private func releaseSecurityScope(for url: URL) {
        releaseSecurityScope(forPath: url.standardizedFileURL.path)
    }

    private func releaseSecurityScope(forPath path: String) {
        guard let scopedURL = scopedURLsByPath.removeValue(forKey: path) else { return }
        scopedURL.stopAccessingSecurityScopedResource()
    }

    private func releaseAllSecurityScopes() {
        for (_, scopedURL) in scopedURLsByPath {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        scopedURLsByPath.removeAll()
    }

    private func ensurePreviewLocalCopy(for sourceURL: URL) -> URL? {
        let key = sourceURL.standardizedFileURL.path
        if let cached = previewLocalCopyByInputPath[key],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let copy = try? Self.makePreviewLocalCopy(of: sourceURL) else { return nil }
        previewLocalCopyByInputPath[key] = copy
        return copy
    }

    private func removePreviewLocalCopy(forPath path: String) {
        guard let cached = previewLocalCopyByInputPath.removeValue(forKey: path) else { return }
        try? FileManager.default.removeItem(at: cached)
    }

    private func clearPreviewLocalCopies() {
        for (_, cached) in previewLocalCopyByInputPath {
            try? FileManager.default.removeItem(at: cached)
        }
        previewLocalCopyByInputPath.removeAll()
    }

    private func adjustZoom(by delta: CGFloat) {
        let newValue = previewScale + delta
        previewScale = min(max(newValue, minPreviewScale), maxPreviewScale)
    }

    private func clampPageNumber(_ number: Int) -> Int {
        if pageCount == 0 { return max(1, number) }
        return max(1, min(number, pageCount))
    }
}
