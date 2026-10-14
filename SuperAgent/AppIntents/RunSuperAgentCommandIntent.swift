import AppIntents

@available(iOS 16.0, *)
struct RunSuperAgentCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "فەرمانی SuperAgent بەڕێوەبەرە"
    static var description = IntentDescription("فەرمانێکی نوێ دەخاتە نۆرە و ئەپی SuperAgent دەکاتەوە.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "فەرمان")
    var command: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AskSuperAgentIntent.queue(command)
        return .result(dialog: "فەرمانەکە نێردرا بۆ ئەپەکە؛ هیچ کردارێک تا گەڕاندنەوەی ئەنجامی ڕاستەقینەی tool سەرکەوتوو ناژمێردرێت.")
    }
}
