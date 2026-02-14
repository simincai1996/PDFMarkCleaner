import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    var document: PDFDocument?
    var scale: CGFloat
    @Binding var currentPageNumber: Int
    var onPageChanged: ((PDFPage) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.backgroundColor = NSColor.windowBackgroundColor
        view.document = document
        styleScrollbars(in: view)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: view
        )

        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self

        if nsView.document !== document {
            nsView.document = document
        }

        applyScale(to: nsView)
        syncPageIfNeeded(in: nsView)
        styleScrollbars(in: nsView)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: Notification.Name.PDFViewPageChanged,
            object: nsView
        )
    }

    private func applyScale(to view: PDFView) {
        guard view.document != nil else { return }
        let base = view.scaleFactorForSizeToFit
        let target = max(0.1, base * scale)
        view.autoScales = false
        view.scaleFactor = target
    }

    private func syncPageIfNeeded(in view: PDFView) {
        guard let doc = view.document else { return }
        let desired = currentPageNumber
        if desired < 1 || desired > doc.pageCount { return }

        let current: Int
        if let page = view.currentPage {
            current = doc.index(for: page) + 1
        } else {
            current = -1
        }

        if current != desired, let page = doc.page(at: desired - 1) {
            view.go(to: page)
        }
    }

    private func styleScrollbars(in view: PDFView) {
        guard let scrollView = view.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else {
            return
        }

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.alphaValue = 0.25
        scrollView.horizontalScroller?.alphaValue = 0.25
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let doc = view.document,
                  let page = view.currentPage else { return }

            let pageNumber = doc.index(for: page) + 1
            if pageNumber > 0, pageNumber != parent.currentPageNumber {
                parent.currentPageNumber = pageNumber
            }

            parent.onPageChanged?(page)
        }
    }
}
