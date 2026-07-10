#if canImport(FoundationModels)
import FoundationModels
import SwiftData
import Foundation

/// On-device natural-language parsing via Apple's Foundation Models (Apple Intelligence).
/// Available only on iOS 26+ and Apple-Intelligence-capable devices; `NLParser.parseSmart`
/// gates on availability and falls back to the heuristic parser everywhere else. Fully
/// on-device — no network, nothing leaves the phone.
@available(iOS 26.0, *)
enum FoundationModelsParser {

    static func isAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func parse(_ text: String, in context: ModelContext) async -> ParsedEntry? {
        guard isAvailable() else { return nil }
        let instructions = """
        You extract structured expense/income data from a short phrase.
        Reply with ONLY a JSON object, no prose, using this exact shape:
        {"amount": number, "currency": "3-letter ISO or KZT", "kind": "expense" or "income", "merchant": "string", "category": "one word"}
        If a field is unknown, omit it.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            return decode(response.content, in: context)
        } catch {
            return nil
        }
    }

    private static func decode(_ json: String, in context: ModelContext) -> ParsedEntry? {
        // Pull the JSON object out of any surrounding text.
        guard let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}") else { return nil }
        let slice = String(json[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var entry = ParsedEntry()
        if let amount = obj["amount"] as? Double { entry.amount = Decimal(safe: amount) }
        else if let s = obj["amount"] as? String { entry.amount = Decimal(string: s) }
        if let cur = obj["currency"] as? String { entry.currencyCode = cur.uppercased() }
        if let kind = obj["kind"] as? String, kind.lowercased() == "income" { entry.kind = .income }
        if let merchant = obj["merchant"] as? String, !merchant.isEmpty { entry.merchant = merchant }

        // Map the model's free-text category onto an existing category slug.
        if let catText = (obj["category"] as? String)?.lowercased() {
            let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            if let match = categories.first(where: { $0.id == catText || $0.name.lowercased() == catText || catText.contains($0.id) }) {
                entry.categoryID = match.id
            }
        }
        // Fall back to learned merchant mapping.
        if entry.categoryID == nil, let m = entry.merchant, let learned = MerchantLearning.category(for: m, in: context) {
            entry.categoryID = learned
        }
        return entry
    }
}
#endif
