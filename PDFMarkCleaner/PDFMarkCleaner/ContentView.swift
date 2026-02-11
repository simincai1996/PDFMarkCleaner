import SwiftUI
import PDFKit
import AppKit

struct ContentView: View {
    @StateObject private var model = AppModel()
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("backgroundTheme") private var backgroundThemeRaw: String = BackgroundTheme.frost.rawValue

    private var localizer: Localizer {
        Localizer(language: AppLanguage(rawValue: appLanguageRaw) ?? .system)
    }

    private var backgroundTheme: BackgroundTheme {
        BackgroundTheme(rawValue: backgroundThemeRaw) ?? .frost
    }

    var body: some View {
        ZStack {
            GlassBackground(theme: backgroundTheme)
            HStack(spacing: 16) {
                Sidebar(model: model, localizer: localizer, advancedOptionsEnabled: enableAdvancedOptions)
                    .frame(width: 380)

                PreviewColumn(
                    title: localizer.t(.original),
                    subtitle: localizer.t(.beforeCleanup),
                    emptyText: localizer.t(.noPreview),
                    document: model.originalPreview,
                    scale: model.previewScale,
                    currentPageNumber: $model.currentPageNumber,
                    onPageChanged: nil
                )

                PreviewColumn(
                    title: localizer.t(.afterClean),
                    subtitle: localizer.t(.expectedResult),
                    emptyText: localizer.t(.noPreview),
                    document: model.cleanedPreview,
                    scale: model.previewScale,
                    currentPageNumber: $model.currentPageNumber,
                    onPageChanged: { page in
                        model.handleCleanedPageChanged(page)
                    }
                )
            }
            .padding(18)
        }
        .frame(minWidth: 1220, minHeight: 740)
        .onChange(of: enableAdvancedOptions) { _, enabled in
            if !enabled {
                model.processingMode = .single
            }
        }
    }
}

private struct GlassBackground: View {
    let theme: BackgroundTheme

    var body: some View {
        LinearGradient(
            colors: [
                theme.topColor,
                theme.bottomColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .blur(radius: 90)
                    .offset(x: -220, y: -180)
                Circle()
                    .fill(theme.accentColor.opacity(0.25))
                    .blur(radius: 130)
                    .offset(x: 260, y: 220)
                RoundedRectangle(cornerRadius: 120)
                    .fill(Color.white.opacity(0.12))
                    .blur(radius: 60)
                    .rotationEffect(.degrees(12))
                    .offset(x: -140, y: 200)
            }
        )
    }
}

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    let localizer: Localizer
    let advancedOptionsEnabled: Bool
    @State private var pageRangeInput = ""
    private let appIcon: NSImage = {
        let icon = NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.isTemplate = false
        return icon
    }()

    private let pageFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        return formatter
    }()

    private let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private let typeColumns = [
        GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)
    ]
    private let actionColumns = [
        GridItem(.flexible(), spacing: 8, alignment: .leading),
        GridItem(.flexible(), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(localizer.t(.appTitle))
                        .font(.title3)
                        .bold()
                }
                .padding(.top, 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    SidebarSection(title: localizer.t(.files)) {
                        VStack(alignment: .leading, spacing: 18) {
                            if advancedOptionsEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(localizer.t(.mode))
                                        .font(.subheadline)
                                        .bold()
                                    Picker("", selection: $model.processingMode) {
                                        Text(localizer.t(.single)).tag(ProcessingMode.single)
                                        Text(localizer.t(.batch)).tag(ProcessingMode.batch)
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            if advancedOptionsEnabled && model.isBatchMode {
                                HStack {
                                    Text(localizer.t(.input))
                                        .font(.subheadline)
                                        .bold()
                                    Spacer()
                                    Button(localizer.t(.selectPDFs)) { model.pickBatchInputs() }
                                        .disabled(model.isRunning)
                                    Button(localizer.t(.clear)) { model.clearSelection() }
                                        .disabled(model.batchInputURLs.isEmpty || model.isRunning)
                                }
                                Text(localizer.format(.filesSelected, model.batchInputURLs.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(model.batchInputURLs.enumerated()), id: \.offset) { index, url in
                                            Button {
                                                model.switchToBatchIndex(index)
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Text(url.lastPathComponent)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    if index == model.batchIndex {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 6)
                                            .background(index == model.batchIndex ? Color.white.opacity(0.6) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        }

                                        if model.batchInputURLs.isEmpty {
                                            Text(localizer.t(.noFileSelected))
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .background(ScrollViewStyleConfigurator())
                                .frame(maxHeight: 140)

                                Divider()

                                HStack {
                                    Text(localizer.t(.output))
                                        .font(.subheadline)
                                        .bold()
                                    Spacer()
                                    Button(localizer.t(.selectOutput)) { model.pickBatchOutputDirectory() }
                                        .disabled(model.batchInputURLs.isEmpty || model.isRunning)
                                    Button(localizer.t(.auto)) { model.batchOutputDirectory = nil }
                                        .disabled(model.batchOutputDirectory == nil)
                                }
                                Text(model.batchOutputDirectory?.lastPathComponent ?? localizer.t(.sameAsInputFolder))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    Text(localizer.t(.input))
                                        .font(.subheadline)
                                        .bold()
                                    Spacer()
                                    Button(localizer.t(.selectPDF)) { model.pickInput() }
                                        .disabled(model.isRunning)
                                    Button(localizer.t(.clear)) { model.clearSelection() }
                                        .disabled(model.inputURL == nil || model.isRunning)
                                }
                                Text(model.inputURL?.lastPathComponent ?? localizer.t(.noFileSelected))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Divider()

                                HStack {
                                    Text(localizer.t(.output))
                                        .font(.subheadline)
                                        .bold()
                                    Spacer()
                                    Button(localizer.t(.selectOutput)) { model.pickOutput() }
                                        .disabled(model.inputURL == nil || model.isRunning)
                                }
                                let name = model.outputURL?.lastPathComponent
                                    ?? model.suggestedOutputURL?.lastPathComponent
                                    ?? localizer.t(.auto)
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.action)) {
                        VStack(alignment: .leading, spacing: 10) {
                            let isBatch = advancedOptionsEnabled && model.isBatchMode
                            Button(model.isRunning ? localizer.t(.processing) : (isBatch ? localizer.t(.startBatch) : localizer.t(.start))) {
                                model.start()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canProcess || model.isRunning)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(columns: actionColumns, spacing: 8) {
                                Button(localizer.t(.save)) {
                                    model.saveAs()
                                }
                                .disabled(!model.canProcess || model.isRunning || isBatch)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(localizer.t(.exportMark)) {
                                    model.exportMarkedPages()
                                }
                                .disabled(model.inputURL == nil || model.isRunning)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(localizer.t(.replace)) {
                                    model.replaceOriginal()
                                }
                                .disabled(!model.canProcess || model.isRunning || isBatch)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(localizer.t(.deleteOriginal)) {
                                    model.deleteOriginal()
                                }
                                .disabled(model.inputURL == nil || model.isRunning || isBatch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if model.isRunning {
                                ProgressView(value: model.progress)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.annotationTypes)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button(localizer.t(.all)) { model.selectedTypes = Set(AnnotationKind.allCases) }
                                Button(localizer.t(.none)) { model.selectedTypes = [] }
                                Spacer()
                            }

                            LazyVGrid(columns: typeColumns, spacing: 6) {
                                ForEach(AnnotationKind.allCases) { kind in
                                    Toggle(kind.title, isOn: typeBinding(for: kind))
                                        .toggleStyle(.checkbox)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    if advancedOptionsEnabled && model.isBatchMode {
                        SidebarSection(title: localizer.t(.previewFile)) {
                            VStack(alignment: .leading, spacing: 10) {
                                let total = model.batchInputURLs.count
                                let current = total == 0 ? 0 : (model.batchIndex + 1)
                                let name = model.inputURL?.lastPathComponent ?? localizer.t(.noFileSelected)
                                HStack(spacing: 8) {
                                    Button {
                                        model.stepBatchItem(-1)
                                    } label: {
                                        Image(systemName: "chevron.left")
                                    }
                                    .frame(width: 28, height: 28)
                                    .disabled(model.batchIndex <= 0)

                                    Text("\(current)/\(total) \(name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    Button {
                                        model.stepBatchItem(1)
                                    } label: {
                                        Image(systemName: "chevron.right")
                                    }
                                    .frame(width: 28, height: 28)
                                    .disabled(model.batchIndex >= model.batchInputURLs.count - 1)
                                }
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.size)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(localizer.t(.current))
                                Spacer()
                                Text(sizeText(for: model.inputFileSizeBytes))
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(localizer.t(.estimated))
                                Spacer()
                                if model.isEstimatingSize {
                                    Text(localizer.t(.estimating))
                                        .foregroundStyle(.secondary)
                                } else if let estimated = model.estimatedFileSizeBytes {
                                    HStack(spacing: 6) {
                                        Text(sizeText(for: estimated))
                                            .foregroundStyle(.secondary)
                                        if model.isEstimateStale {
                                            Text(localizer.t(.outdated))
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                } else {
                                    Text("--")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button(model.isEstimateStale ? localizer.t(.estimateSize) : localizer.t(.reEstimate)) {
                                model.estimateSize()
                            }
                            .disabled(!model.canEstimate || model.isRunning || model.isEstimatingSize)
                            if model.isEstimatingSize {
                                ProgressView(value: model.estimateProgress)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.removePages)) {
                        VStack(alignment: .leading, spacing: 10) {
                            if advancedOptionsEnabled && model.isBatchMode {
                                Text(localizer.t(.allPages))
                                    .font(.subheadline)
                                    .bold()
                            } else {
                                Picker("", selection: $model.removalScope) {
                                    ForEach(RemovalScope.allCases) { scope in
                                        let label = scope == .all ? localizer.t(.allPages) : localizer.t(.selectedPages)
                                        Text(label).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()

                                if model.removalScope == .selected {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            TextField(localizer.t(.pagesPlaceholder), text: $pageRangeInput)
                                                .textFieldStyle(.roundedBorder)
                                            Button(localizer.t(.apply)) {
                                                model.applyPageRangeInput(pageRangeInput)
                                            }
                                            .disabled(model.inputURL == nil || model.isRunning)
                                        }

                                        HStack(spacing: 8) {
                                            Button(localizer.t(.selectAll)) { model.selectAllMarkedPages() }
                                                .disabled(model.markedPages.isEmpty)
                                            Button(localizer.t(.clear)) { model.clearSelectedPages() }
                                                .disabled(model.selectedPages.isEmpty)
                                            Spacer()
                                            Text(localizer.format(.selectedCount, model.selectedPages.count))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.navigation)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button {
                                    model.stepPage(-1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(model.currentPageNumber <= 1)

                                TextField(localizer.t(.page), value: pageBinding, formatter: pageFormatter)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(.roundedBorder)

                                Text("/ \(model.pageCount)")
                                    .foregroundStyle(.secondary)

                                Button {
                                    model.stepPage(1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(model.pageCount == 0 || model.currentPageNumber >= model.pageCount)

                                Spacer()
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.markedPages)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button(localizer.t(.prevMarked)) {
                                    model.goToPreviousMarkedPage()
                                }
                                .disabled(model.markedPages.isEmpty)

                                Button(localizer.t(.nextMarked)) {
                                    model.goToNextMarkedPage()
                                }
                                .disabled(model.markedPages.isEmpty)

                                Spacer()
                                Text(localizer.format(.markedCount, model.markedPages.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if model.isScanning {
                                ProgressView(value: model.scanProgress)
                                    .frame(maxWidth: .infinity)
                            }

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(model.markedPages, id: \.self) { page in
                                        HStack(spacing: 8) {
                                            if model.removalScope == .selected {
                                                Toggle("", isOn: pageSelectionBinding(for: page))
                                                    .toggleStyle(.checkbox)
                                                    .labelsHidden()
                                            }

                                            Button {
                                                model.setCurrentPageNumber(page)
                                            } label: {
                                                HStack {
                                                    Text("Page \(page)")
                                                    Spacer()
                                                    if page == model.currentPageNumber {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if model.markedPages.isEmpty && !model.isScanning {
                                        Text(localizer.t(.noMarksFound))
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(ScrollViewStyleConfigurator())
                            .frame(maxHeight: 180)
                        }
                    }

                    SidebarSection(title: localizer.t(.annotationCounts)) {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.isScanning {
                                HStack(spacing: 8) {
                                    ProgressView(value: model.scanProgress)
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            CountsBlock(title: localizer.t(.allPages), counts: model.documentTypeCounts, noneText: localizer.t(.none))
                            CountsBlock(title: localizer.t(.currentPage), counts: model.currentPageTypeCounts, noneText: localizer.t(.none))
                            if model.removalScope == .selected {
                                CountsBlock(title: localizer.t(.selectedPages), counts: model.selectedPagesTypeCounts, noneText: localizer.t(.none))
                            }
                        }
                    }

                    SidebarSection(title: localizer.t(.zoom)) {
                        HStack(spacing: 8) {
                            Button {
                                model.zoomOut()
                            } label: {
                                Image(systemName: "minus")
                            }
                            .disabled(model.originalPreview == nil)

                            Text("\(Int(model.previewScale * 100))%")
                                .frame(width: 52, alignment: .center)
                                .foregroundStyle(.secondary)

                            Button {
                                model.zoomIn()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(model.originalPreview == nil)

                            Button(localizer.t(.reset)) {
                                model.resetZoom()
                            }
                            .disabled(model.originalPreview == nil)

                            Spacer()
                        }
                    }

                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.trailing, 10)
                }
                .background(ScrollViewStyleConfigurator())
            }
            .onChange(of: model.inputURL) { _, _ in
                pageRangeInput = ""
            }
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { model.currentPageNumber },
            set: { model.setCurrentPageNumber($0) }
        )
    }

    private func typeBinding(for kind: AnnotationKind) -> Binding<Bool> {
        Binding(
            get: { model.selectedTypes.contains(kind) },
            set: { isOn in
                if isOn {
                    model.selectedTypes.insert(kind)
                } else {
                    model.selectedTypes.remove(kind)
                }
            }
        )
    }

    private func pageSelectionBinding(for page: Int) -> Binding<Bool> {
        Binding(
            get: { model.selectedPages.contains(page) },
            set: { isOn in
                if isOn {
                    model.selectedPages.insert(page)
                } else {
                    model.selectedPages.remove(page)
                }
            }
        )
    }

    private func sizeText(for bytes: Int64) -> String {
        if bytes <= 0 { return "--" }
        return sizeFormatter.string(fromByteCount: bytes)
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
            DashedDivider()
                .padding(.top, 6)
        }
    }
}

private struct DashedDivider: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
            }
            .stroke(
                Color.black.opacity(0.24),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4, 6])
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 1)
    }
}

private struct ScrollViewStyleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var view: NSView? = nsView
            var scrollView: NSScrollView?
            while let current = view, scrollView == nil {
                scrollView = current as? NSScrollView
                view = current.superview
            }
            guard let scrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.alphaValue = 0.25
            scrollView.horizontalScroller?.alphaValue = 0.25
        }
    }
}

private struct CountsBlock: View {
    let title: String
    let counts: [AnnotationKind: Int]
    let noneText: String

    private var total: Int {
        counts.values.reduce(0, +)
    }

    private var rows: [(AnnotationKind, Int)] {
        counts
            .filter { $0.value > 0 }
            .sorted { $0.key.title < $1.key.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                Text(noneText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.0) { kind, value in
                    HStack {
                        Text(kind.title)
                        Spacer()
                        Text("\(value)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct PreviewColumn: View {
    let title: String
    let subtitle: String
    let emptyText: String
    let document: PDFDocument?
    let scale: CGFloat
    @Binding var currentPageNumber: Int
    var onPageChanged: ((PDFPage) -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ZStack {
                    if document != nil {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
                            .background(Color.clear)
                    }

                    if let document {
                        PDFKitView(
                            document: document,
                            scale: scale,
                            currentPageNumber: $currentPageNumber,
                            onPageChanged: onPageChanged
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(6)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "doc")
                            Text(emptyText)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}
