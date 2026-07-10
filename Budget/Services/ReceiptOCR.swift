import Foundation
import Vision
import UIKit
import SwiftData

/// On-device receipt/statement OCR using the Vision framework. Extracts recognized text
/// lines from an image, then heuristically pulls out the total amount, merchant, and date.
/// Nothing leaves the device. Results are always a *draft* the user confirms.
enum ReceiptOCR {

    /// Recognize all text lines in an image (top-to-bottom).
    static func recognizeLines(in image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y } // top first
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    /// Parse a single receipt into a draft entry (amount = the "total").
    static func parseReceipt(from image: UIImage, in context: ModelContext) async -> (entry: ParsedEntry, lines: [String]) {
        let lines = await recognizeLines(in: image)
        var entry = ParsedEntry()

        // Merchant = first line with letters.
        entry.merchant = lines.first { $0.contains(where: \.isLetter) }?.trimmingCharacters(in: .whitespaces).capitalized

        // Total: prefer a line containing "total"; else the largest money-like number.
        let totalLine = lines.first { $0.lowercased().contains("total") || $0.lowercased().contains("итого") || $0.lowercased().contains("сумма") }
        if let totalLine, let amt = largestAmount(in: totalLine) {
            entry.amount = amt
        } else {
            entry.amount = lines.compactMap { largestAmount(in: $0) }.max()
        }

        // Currency symbol if present anywhere.
        let joined = lines.joined(separator: " ")
        if joined.contains("₸") || joined.lowercased().contains("kzt") || joined.lowercased().contains("тг") { entry.currencyCode = "KZT" }
        else if joined.contains("$") { entry.currencyCode = "USD" }
        else if joined.contains("€") { entry.currencyCode = "EUR" }

        if let m = entry.merchant, let learned = MerchantLearning.category(for: m, in: context) {
            entry.categoryID = learned
        }
        return (entry, lines)
    }

    /// Extract candidate transactions from a statement/screenshot: every line that has a
    /// money-like amount becomes a draft (merchant = the line's text minus the number).
    static func parseStatement(from image: UIImage, in context: ModelContext) async -> [ParsedEntry] {
        let lines = await recognizeLines(in: image)
        var entries: [ParsedEntry] = []
        for line in lines {
            guard let amt = largestAmount(in: line), amt > 0 else { continue }
            var e = ParsedEntry()
            e.amount = amt
            let merchant = line.replacingOccurrences(of: #"[0-9][0-9\s.,]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if merchant.count >= 2 { e.merchant = merchant.capitalized }
            if let m = e.merchant, let learned = MerchantLearning.category(for: m, in: context) { e.categoryID = learned }
            entries.append(e)
        }
        return entries
    }

    /// Largest money-like number in a string, parsed as KZT (no decimals) by default.
    private static func largestAmount(in text: String) -> Decimal? {
        let matches = text.matches(of: /[0-9][0-9\s.,]*[0-9]|[0-9]/)
        let values = matches.compactMap { AmountParser.parse(String($0.0), currencyCode: "KZT") }
        return values.max()
    }
}
