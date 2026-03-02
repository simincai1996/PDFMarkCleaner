import Foundation
import PDFKit

public enum PDFUnlockError: LocalizedError, Equatable {
    case openFailed
    case passwordRequired
    case invalidPassword
    case emptyDocument
    case saveFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .openFailed:
            return "Failed to open PDF."
        case .passwordRequired:
            return "Password is required for this PDF."
        case .invalidPassword:
            return "Invalid password."
        case .emptyDocument:
            return "PDF has no pages."
        case .saveFailed:
            return "Failed to save PDF."
        case .cancelled:
            return "Operation cancelled."
        }
    }
}

public struct PDFUnlocker {
    public static func makeUnlockedDocument(input: URL, password: String?) throws -> PDFDocument {
        let source = try loadUnlockedSource(input: input, password: password)
        return try clonedDocument(from: source)
    }

    public static func unlock(
        input: URL,
        output: URL,
        password: String?,
        progress: @escaping (Double) -> Void,
        shouldCancel: (() -> Bool)? = nil
    ) throws {
        let source = try loadUnlockedSource(input: input, password: password)
        let unlocked = try clonedDocument(
            from: source,
            progress: progress,
            shouldCancel: shouldCancel
        )

        if !unlocked.write(to: output) {
            throw PDFUnlockError.saveFailed
        }
    }

    private static func loadUnlockedSource(input: URL, password: String?) throws -> PDFDocument {
        guard let source = PDFDocument(url: input) else {
            throw PDFUnlockError.openFailed
        }

        if source.isLocked {
            guard let password, !password.isEmpty else {
                throw PDFUnlockError.passwordRequired
            }
            guard source.unlock(withPassword: password) else {
                throw PDFUnlockError.invalidPassword
            }
        }

        if source.pageCount == 0 {
            throw PDFUnlockError.emptyDocument
        }

        return source
    }

    private static func clonedDocument(
        from source: PDFDocument,
        progress: ((Double) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> PDFDocument {
        let total = source.pageCount
        if total == 0 {
            throw PDFUnlockError.emptyDocument
        }

        progress?(0)

        let result = PDFDocument()
        if let attributes = source.documentAttributes {
            result.documentAttributes = attributes
        }

        for index in 0..<total {
            if shouldCancel?() == true {
                throw PDFUnlockError.cancelled
            }

            guard let page = source.page(at: index),
                  let pageCopy = page.copy() as? PDFPage else {
                throw PDFUnlockError.openFailed
            }
            result.insert(pageCopy, at: result.pageCount)

            let value = Double(index + 1) / Double(total)
            progress?(value)
        }

        if result.pageCount == 0 {
            throw PDFUnlockError.emptyDocument
        }

        return result
    }
}
