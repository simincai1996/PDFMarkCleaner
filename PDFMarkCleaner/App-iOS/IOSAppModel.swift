import Foundation
import PDFKit
import Combine
import PDFMarkCore

enum IOSProcessingMode: String, CaseIterable, Identifiable {
    case single
    case batch

    var id: String { rawValue }
}

enum IOSRemovalScope: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }
}

@MainActor
final class IOSAppModel: ObservableObject, @unchecked Sendable {
    @Published var processingMode: IOSProcessingMode = .single {
        didSet { handleModeChanged() }
    }
    @Published var removalScope: IOSRemovalScope = .all {
        didSet {
            if isBatchMode && removalScope != .all {
                removalScope = .all
                return
            }
            if removalScope == .all {
                clearSelectedPages()
            }
        }
    }
    @Published var batchInputURLs: [URL] = []
    @Published var batchIndex: Int = 0
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var batchOutputURLs: [URL] = []
    @Published var selectedTypes: Set<AnnotationKind> = Set(AnnotationKind.allCases)
    @Published var pageRangeInput = ""
    @Published private(set) var selectedPages: Set<Int> = []
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var status: String = "请选择 PDF 文件。"
    @Published var originalPreview: PDFDocument?
    @Published var cleanedPreview: PDFDocument?
    @Published var pageCount: Int = 0
    @Published var errorMessage: String?

    private var outputByInputPath: [String: URL] = [:]

    var isBatchMode: Bool {
        processingMode == .batch
    }

    var canProcess: Bool {
        guard !isRunning else { return false }
        guard !selectedTypes.isEmpty else { return false }
        if isBatchMode {
            return !batchInputURLs.isEmpty
        }
        guard inputURL != nil else { return false }
        if removalScope == .selected {
            return !selectedPages.isEmpty
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
        if isBatchMode {
            return batchReplaceReadyCount > 0
        }
        return inputURL != nil && outputURL != nil
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

    var currentBatchOutputURL: URL? {
        guard let inputURL else { return nil }
        return outputByInputPath[inputURL.standardizedFileURL.path]
    }

    func handlePickedFiles(_ urls: [URL]) {
        let pdfURLs = normalizedPDFURLs(from: urls)
        guard !pdfURLs.isEmpty else {
            status = "请选择 PDF 文件。"
            return
        }

        if processingMode == .batch || pdfURLs.count > 1 {
            processingMode = .batch
            appendBatchInputs(pdfURLs)
            return
        }

        openSingle(pdfURLs[0])
    }

    func toggleType(_ kind: AnnotationKind, enabled: Bool) {
        if enabled {
            selectedTypes.insert(kind)
        } else {
            selectedTypes.remove(kind)
        }
    }

    func selectAllTypes() {
        selectedTypes = Set(AnnotationKind.allCases)
    }

    func clearAllTypes() {
        selectedTypes.removeAll()
    }

    func switchToBatchIndex(_ index: Int) {
        guard batchInputURLs.indices.contains(index) else { return }
        batchIndex = index
        inputURL = batchInputURLs[index]
        refreshCurrentDocumentState()
        status = "批处理文件：\(index + 1)/\(batchInputURLs.count)"
    }

    func removeBatchInput(at index: Int) {
        guard !isRunning else { return }
        guard batchInputURLs.indices.contains(index) else { return }

        let removed = batchInputURLs.remove(at: index)
        outputByInputPath.removeValue(forKey: removed.standardizedFileURL.path)
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
        inputURL = nil
        outputURL = nil
        batchInputURLs = []
        batchOutputURLs = []
        batchIndex = 0
        pageCount = 0
        selectedPages = []
        pageRangeInput = ""
        originalPreview = nil
        cleanedPreview = nil
        progress = 0
        outputByInputPath.removeAll()
        status = "请选择 PDF 文件。"
    }

    func selectAllPages() {
        guard pageCount > 0 else { return }
        selectedPages = Set(1...pageCount)
        pageRangeInput = "1-\(pageCount)"
        status = "已选择全部页面：\(pageCount) 页。"
    }

    func clearSelectedPages() {
        selectedPages = []
        pageRangeInput = ""
    }

    func applyPageRangeInput() {
        guard removalScope == .selected else {
            status = "请先切换到“指定页面”。"
            return
        }
        guard pageCount > 0 else {
            status = "当前文件没有可用页面。"
            return
        }

        let trimmed = pageRangeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearSelectedPages()
            status = "已清空页面范围。"
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
                let lower = max(1, min(start, end))
                let upper = min(pageCount, max(start, end))
                if lower > upper {
                    invalidCount += 1
                    continue
                }
                for page in lower...upper {
                    result.insert(page)
                }
            } else {
                invalidCount += 1
            }
        }

        selectedPages = result
        if result.isEmpty {
            status = "未解析出有效页码。"
        } else if invalidCount == 0 {
            status = "已选择 \(result.count) 页。"
        } else {
            status = "已选择 \(result.count) 页，忽略 \(invalidCount) 个无效片段。"
        }
    }

    func process() {
        if isBatchMode {
            processBatch()
            return
        }
        processSingle()
    }

    func prepareSingleExportPayload() -> (data: Data, filename: String)? {
        guard let outputURL else {
            status = "请先完成处理，再执行另存。"
            return nil
        }

        do {
            let data = try Self.readData(from: outputURL)
            let filename = outputURL.lastPathComponent
            return (data, filename)
        } catch {
            status = "读取导出文件失败：\(error.localizedDescription)"
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func markSingleSaveAsCompleted(destination: URL) {
        status = "已另存：\(destination.lastPathComponent)"
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
        status = "正在批量另存..."

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
                }
            }

            let finalCopied = copied
            let finalFailed = failed
            Task { @MainActor in
                self.isRunning = false
                self.progress = 1
                if finalFailed == 0 {
                    self.status = "批量另存完成：\(finalCopied) 个文件。"
                } else {
                    self.status = "批量另存完成：成功 \(finalCopied) 个，失败 \(finalFailed) 个。"
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

    private func processSingle() {
        guard let sourceURL = inputURL else { return }
        guard !selectedTypes.isEmpty else {
            status = "请至少选择一种注释类型。"
            return
        }
        if removalScope == .selected && selectedPages.isEmpty {
            status = "请先设置页面范围。"
            return
        }

        let types = selectedTypes
        let pages = removalScope == .selected ? selectedPages : nil
        isRunning = true
        progress = 0
        errorMessage = nil
        status = "正在清理注释..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let workDirectory = try Self.makeWorkDirectory()
                let localInput = workDirectory.appendingPathComponent("input.pdf")
                try Self.copyInputPDF(from: sourceURL, to: localInput)
                let output = workDirectory.appendingPathComponent(Self.outputFileName(for: sourceURL))

                try PDFAnnotationStripper.strip(
                    input: localInput,
                    output: output,
                    selectedTypes: types,
                    pagesToProcess: pages,
                    progress: { p in
                        Task { @MainActor in
                            self.progress = p
                        }
                    }
                )

                let cleaned = PDFDocument(url: output)
                Task { @MainActor in
                    self.outputURL = output
                    self.outputByInputPath[sourceURL.standardizedFileURL.path] = output
                    self.cleanedPreview = cleaned
                    self.progress = 1
                    self.status = "清理完成，可直接分享导出。"
                    self.isRunning = false
                }
            } catch {
                Task { @MainActor in
                    self.status = "处理失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    private func processBatch() {
        guard !batchInputURLs.isEmpty else {
            status = "请先选择批处理文件。"
            return
        }
        guard !selectedTypes.isEmpty else {
            status = "请至少选择一种注释类型。"
            return
        }

        let urls = batchInputURLs
        let types = selectedTypes
        isRunning = true
        progress = 0
        errorMessage = nil
        status = "正在批处理..."
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

                    try PDFAnnotationStripper.strip(
                        input: localInput,
                        output: output,
                        selectedTypes: types,
                        pagesToProcess: nil,
                        progress: { p in
                            let overall = (Double(index) + p) / Double(urls.count)
                            Task { @MainActor in
                                self.progress = overall
                            }
                        }
                    )

                    outputs.append(output)
                    Task { @MainActor in
                        self.outputByInputPath[sourceURL.standardizedFileURL.path] = output
                    }
                }

                let finalOutputs = outputs
                Task { @MainActor in
                    self.batchOutputURLs = finalOutputs
                    self.progress = 1
                    self.isRunning = false
                    self.status = "批处理完成，共 \(finalOutputs.count) 个文件。"
                    self.refreshCurrentDocumentState()
                }
            } catch {
                Task { @MainActor in
                    self.isRunning = false
                    self.status = "批处理失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func replaceSingleOriginal() {
        guard let inputURL, let outputURL else {
            status = "请先完成处理，再替代原文件。"
            return
        }
        guard !isRunning else { return }

        isRunning = true
        progress = 0
        errorMessage = nil
        status = "正在替代原文件..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try Self.overwriteFile(at: inputURL, with: outputURL)
                Task { @MainActor in
                    self.isRunning = false
                    self.progress = 1
                    self.status = "已替代原文件：\(inputURL.lastPathComponent)"
                    self.refreshCurrentDocumentState()
                }
            } catch {
                Task { @MainActor in
                    self.isRunning = false
                    self.status = "替代失败：\(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func replaceBatchOriginals() {
        let pairs = processedBatchPairs()
        guard !pairs.isEmpty else {
            status = "没有可替代的批处理结果，请先完成批处理。"
            return
        }
        guard !isRunning else { return }

        isRunning = true
        progress = 0
        errorMessage = nil
        status = "正在批量替代原文件..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var replaced = 0
            var failed = 0

            for (index, pair) in pairs.enumerated() {
                do {
                    try Self.overwriteFile(at: pair.input, with: pair.output)
                    replaced += 1
                } catch {
                    failed += 1
                }

                let overall = Double(index + 1) / Double(pairs.count)
                Task { @MainActor in
                    self.progress = overall
                }
            }

            let finalReplaced = replaced
            let finalFailed = failed
            Task { @MainActor in
                self.isRunning = false
                self.progress = 1
                if finalFailed == 0 {
                    self.status = "批量替代完成：\(finalReplaced) 个文件。"
                } else {
                    self.status = "批量替代完成：成功 \(finalReplaced) 个，失败 \(finalFailed) 个。"
                }
                self.refreshCurrentDocumentState()
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
        status = "正在删除原文件..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try Self.removeFile(inputURL)
                Task { @MainActor in
                    self.isRunning = false
                    self.clearInputs()
                    self.status = "已删除原文件：\(inputURL.lastPathComponent)"
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
        status = "正在批量删除原文件..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var deleted = 0
            var failed = 0
            var deletedPaths = Set<String>()

            for (index, url) in urls.enumerated() {
                do {
                    try Self.removeFile(url)
                    deleted += 1
                    deletedPaths.insert(url.standardizedFileURL.path)
                } catch {
                    failed += 1
                }

                let overall = Double(index + 1) / Double(urls.count)
                Task { @MainActor in
                    self.progress = overall
                }
            }

            let finalDeleted = deleted
            let finalFailed = failed
            let finalDeletedPaths = deletedPaths
            Task { @MainActor in
                self.isRunning = false
                self.progress = 1

                if !finalDeletedPaths.isEmpty {
                    self.batchInputURLs.removeAll { finalDeletedPaths.contains($0.standardizedFileURL.path) }
                    for path in finalDeletedPaths {
                        self.outputByInputPath.removeValue(forKey: path)
                    }
                }

                if self.batchInputURLs.isEmpty {
                    self.clearInputs()
                    self.processingMode = .batch
                } else {
                    let nextIndex = min(self.batchIndex, self.batchInputURLs.count - 1)
                    self.switchToBatchIndex(nextIndex)
                }

                if finalFailed == 0 {
                    self.status = "批量删除完成：\(finalDeleted) 个文件。"
                } else {
                    self.status = "批量删除完成：成功 \(finalDeleted) 个，失败 \(finalFailed) 个。"
                }
            }
        }
    }

    // 中文说明：iOS 文件选择器返回的 URL 可能是安全域 URL，需要在访问期间显式开启权限。
    private func readPDFDocument(from url: URL) -> PDFDocument? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return PDFDocument(url: url)
    }

    private func processedBatchPairs() -> [(input: URL, output: URL)] {
        batchInputURLs.compactMap { input in
            let key = input.standardizedFileURL.path
            guard let output = outputByInputPath[key] else { return nil }
            return (input, output)
        }
    }

    private nonisolated static func readData(from url: URL) throws -> Data {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
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
            .appendingPathComponent("pdf-mark-ios-\(UUID().uuidString)", isDirectory: true)
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
        return "\(base)_cleaned.pdf"
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

    private func handleModeChanged() {
        if isBatchMode {
            removalScope = .all
            clearSelectedPages()
            if batchInputURLs.isEmpty, let current = inputURL {
                batchInputURLs = [current]
                batchIndex = 0
            }
            if !batchInputURLs.isEmpty {
                switchToBatchIndex(min(batchIndex, batchInputURLs.count - 1))
            }
        }
    }

    private func openSingle(_ url: URL) {
        inputURL = url
        outputURL = outputByInputPath[url.standardizedFileURL.path]
        originalPreview = readPDFDocument(from: url)
        if let outputURL {
            cleanedPreview = PDFDocument(url: outputURL)
        } else {
            cleanedPreview = nil
        }
        pageCount = originalPreview?.pageCount ?? 0
        if removalScope == .selected {
            clearSelectedPages()
        }
        status = "已选择：\(url.lastPathComponent)"
        progress = 0
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
            cleanedPreview = nil
            pageCount = 0
            return
        }
        originalPreview = readPDFDocument(from: inputURL)
        outputURL = outputByInputPath[inputURL.standardizedFileURL.path]
        if let outputURL {
            cleanedPreview = PDFDocument(url: outputURL)
        } else {
            cleanedPreview = nil
        }
        pageCount = originalPreview?.pageCount ?? 0
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
}
