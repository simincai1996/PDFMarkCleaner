import SwiftUI
import PDFKit
import AppKit

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            GlassBackground()
            HStack(spacing: 16) {
                Sidebar(model: model)
                    .frame(width: 340)

                PreviewColumn(
                    title: "Original",
                    subtitle: "Before cleanup",
                    document: model.originalPreview,
                    scale: model.previewScale,
                    currentPageNumber: $model.currentPageNumber,
                    onPageChanged: nil
                )

                PreviewColumn(
                    title: "After Clean",
                    subtitle: "Expected result",
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
    }
}

private struct GlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.88, green: 0.93, blue: 0.98)
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
                    .fill(Color.blue.opacity(0.25))
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
    @State private var pageRangeInput = ""

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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("PDF Mark Cleaner")
                        .font(.title3)
                        .bold()

                    SidebarSection(title: "Files") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Input")
                                    .font(.subheadline)
                                    .bold()
                                Spacer()
                                Button("Select PDF") { model.pickInput() }
                                    .disabled(model.isRunning)
                                Button("Clear") { model.clearSelection() }
                                    .disabled(model.inputURL == nil || model.isRunning)
                            }
                            Text(model.inputURL?.lastPathComponent ?? "No file selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Divider()

                            HStack {
                                Text("Output")
                                    .font(.subheadline)
                                    .bold()
                                Spacer()
                                Button("Select Output") { model.pickOutput() }
                                    .disabled(model.inputURL == nil || model.isRunning)
                            }
                            let name = model.outputURL?.lastPathComponent
                                ?? model.suggestedOutputURL?.lastPathComponent
                                ?? "Auto"
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    SidebarSection(title: "Action") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button(model.isRunning ? "Processing..." : "Start") {
                                model.start()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canProcess || model.isRunning)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(columns: actionColumns, spacing: 8) {
                                Button("Save") {
                                    model.saveAs()
                                }
                                .disabled(!model.canProcess || model.isRunning)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button("Export Mark") {
                                    model.exportMarkedPages()
                                }
                                .disabled(model.inputURL == nil || model.isRunning)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button("Replace") {
                                    model.replaceOriginal()
                                }
                                .disabled(!model.canProcess || model.isRunning)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button("Delete Original") {
                                    model.deleteOriginal()
                                }
                                .disabled(model.inputURL == nil || model.isRunning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if model.isRunning {
                                ProgressView(value: model.progress)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    SidebarSection(title: "Annotation Types") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button("All") { model.selectedTypes = Set(AnnotationKind.allCases) }
                                Button("None") { model.selectedTypes = [] }
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

                    SidebarSection(title: "Size") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Current")
                                Spacer()
                                Text(sizeText(for: model.inputFileSizeBytes))
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Estimated")
                                Spacer()
                                if model.isEstimatingSize {
                                    Text("Estimating...")
                                        .foregroundStyle(.secondary)
                                } else if let estimated = model.estimatedFileSizeBytes {
                                    HStack(spacing: 6) {
                                        Text(sizeText(for: estimated))
                                            .foregroundStyle(.secondary)
                                        if model.isEstimateStale {
                                            Text("Outdated")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                } else {
                                    Text("--")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button(model.isEstimateStale ? "Estimate Size" : "Re-estimate") {
                                model.estimateSize()
                            }
                            .disabled(!model.canEstimate || model.isRunning || model.isEstimatingSize)
                            if model.isEstimatingSize {
                                ProgressView(value: model.estimateProgress)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    SidebarSection(title: "Remove Pages") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $model.removalScope) {
                                ForEach(RemovalScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if model.removalScope == .selected {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        TextField("Pages (1-5,8,10)", text: $pageRangeInput)
                                            .textFieldStyle(.roundedBorder)
                                        Button("Apply") {
                                            model.applyPageRangeInput(pageRangeInput)
                                        }
                                        .disabled(model.inputURL == nil || model.isRunning)
                                    }

                                    HStack(spacing: 8) {
                                        Button("Select All") { model.selectAllMarkedPages() }
                                            .disabled(model.markedPages.isEmpty)
                                        Button("Clear") { model.clearSelectedPages() }
                                            .disabled(model.selectedPages.isEmpty)
                                        Spacer()
                                        Text("Selected: \(model.selectedPages.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    SidebarSection(title: "Navigation") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button {
                                    model.stepPage(-1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(model.currentPageNumber <= 1)

                                TextField("Page", value: pageBinding, formatter: pageFormatter)
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

                    SidebarSection(title: "Marked Pages") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button("Prev Marked") {
                                    model.goToPreviousMarkedPage()
                                }
                                .disabled(model.markedPages.isEmpty)

                                Button("Next Marked") {
                                    model.goToNextMarkedPage()
                                }
                                .disabled(model.markedPages.isEmpty)

                                Spacer()
                                Text("Marked: \(model.markedPages.count)")
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
                                        Text("No marks found")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                        }
                    }

                    SidebarSection(title: "Annotation Counts") {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.isScanning {
                                HStack(spacing: 8) {
                                    ProgressView(value: model.scanProgress)
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            CountsBlock(title: "All Pages", counts: model.documentTypeCounts)
                            CountsBlock(title: "Current Page", counts: model.currentPageTypeCounts)
                            if model.removalScope == .selected {
                                CountsBlock(title: "Selected Pages", counts: model.selectedPagesTypeCounts)
                            }
                        }
                    }

                    SidebarSection(title: "Zoom") {
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

                            Button("Reset") {
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
            }
            .background(ScrollViewStyleConfigurator())
            .scrollIndicators(.visible)
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
                Color.black.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 6])
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
            guard let scrollView = nsView.enclosingScrollView else { return }
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
                Text("None")
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
                            Text("No preview")
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
