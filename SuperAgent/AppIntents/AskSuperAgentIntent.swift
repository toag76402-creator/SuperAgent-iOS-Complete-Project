import AppIntents
import Foundation

@available(iOS 16.0, *)
struct AskSuperAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "پرسیار لە SuperAgent بکە"
    static var description = IntentDescription("داواکارییەک بۆ SuperAgent بنێرە و ئەپەکە بکەرەوە.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "داواکاری")
    var request: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try Self.queue(request)
        return .result(dialog: "فەرمانەکەت گەیەندرا؛ SuperAgent دەکرێتەوە بۆ جێبەجێکردنی.")
    }

    static func queue(_ raw: String) throws {
        guard let defaults = UserDefaults(suiteName: "group.com.custom.superagent.ai") else {
            throw NSError(domain: "SuperAgentIntent", code: 2, userInfo: [NSLocalizedDescriptionKey: "App Group بەردەست نییە."])
        }
        guard PendingCommandQueue.enqueue(raw, in: defaults) else {
            throw NSError(domain: "SuperAgentIntent", code: 1, userInfo: [NSLocalizedDescriptionKey: "داواکاری بەتاڵە، زۆر درێژە، یان فەرمانێکی تر هێشتا لە نۆرەدایە."])
        }
    }
}
