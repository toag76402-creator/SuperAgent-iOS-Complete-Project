import Foundation

enum ToolRegistry {
    static let registeredTools: Set<AgentToolName> = [
        .analyzeCurrentScreen, .analyzeSelectedImage, .openURL,
        .copyToClipboard, .saveNote, .createReminder, .readAppStatus
    ]

    static let approvalRequiredTools: Set<AgentToolName> = [
        .openURL, .copyToClipboard, .createReminder
    ]

    static func promptDescription(hasImage: Bool) -> String {
        let imageState = hasImage ? "An image is attached to this request." : "No image is attached."
        return """
        You may use only these allow-listed tools, one at a time: analyzeCurrentScreen, analyzeSelectedImage, openURL, copyToClipboard, saveNote, createReminder, readAppStatus.
        Never invent tools, arguments, credentials, capabilities, or results. If a tool is unavailable or rejected, say so honestly.
        Tool argument shapes: analyzeCurrentScreen={}, analyzeSelectedImage={}, readAppStatus={}, openURL={\"url\":\"https://example.com\"}, copyToClipboard={\"text\":\"...\"}, saveNote={\"title\":\"...\",\"content\":\"...\"}, createReminder={\"title\":\"...\",\"dueDate\":\"ISO-8601 optional\"}.
        Return exactly one JSON object when requesting a tool, with this shape: {\"type\":\"tool_call\",\"name\":\"readAppStatus\",\"arguments\":{}}.
        When finished, return {\"type\":\"final\",\"text\":\"your answer\"}. Do not say an action succeeded until the tool result says success.
        openURL, copyToClipboard, and createReminder always require explicit in-app user approval. Never try to bypass a denial.
        saveNote writes only a new local note inside this app. It cannot overwrite existing files.
        runShortcut, sendWebhook, and callServerAPI are not enabled; do not request them.
        Respect iOS permissions, privacy, cancellation, and timeouts. Respond in Kurdish Sorani unless asked otherwise.
        \(imageState)
        """
    }

    static func validate(_ call: AgentToolCall, hasImage: Bool) -> String? {
        guard let name = AgentToolName(rawValue: call.name), registeredTools.contains(name) else {
            return "ئەم tool ـە ناسراو یان چالاک نییە؛ تەنها tool ـە تۆمارکراوەکان بەکاردەهێنرێن."
        }
        let args = call.arguments
        switch name {
        case .analyzeCurrentScreen, .analyzeSelectedImage:
            guard args.isEmpty else { return "ئەم tool ـە argument وەرناگرێت." }
            guard hasImage else { return "هیچ وێنەیەک لەم داواکارییەدا نییە." }
        case .readAppStatus:
            guard args.isEmpty else { return "readAppStatus argument وەرناگرێت." }
        case .openURL:
            guard Set(args.keys) == ["url"], let raw = args["url"], raw.count <= 2048,
                  let components = URLComponents(string: raw),
                  components.scheme?.lowercased() == "https",
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil else {
                return "URL ناپەسەندە؛ تەنها URLی HTTPSی پاک و بێ username/password ڕێگەپێدراوە."
            }
        case .copyToClipboard:
            guard Set(args.keys) == ["text"], let text = args["text"],
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 2000 else {
                return "copyToClipboard دەقی 1 تا 2000 پیت وەرگرێت."
            }
        case .saveNote:
            guard Set(args.keys) == ["title", "content"],
                  let title = args["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 80,
                  let content = args["content"], content.count <= 10000 else {
                return "saveNote پێویستی بە titleی 1–80 پیت و contentی کەمتر لە 10000 پیتە."
            }
            let forbidden = CharacterSet(charactersIn: "/\\\\:\n\r\0")
            guard title.rangeOfCharacter(from: forbidden) == nil,
                  title != ".", title != ".." else {
                return "ناونیشانی تێبینی ناتوانێت path یان ناوی فایلێکی ناپەسەند تێدا بێت."
            }
        case .createReminder:
            guard Set(args.keys).isSubset(of: ["title", "dueDate"]),
                  let title = args["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 180 else {
                return "createReminder پێویستی بە ناونیشانی بیرخستنەوەی 1–180 پیتە."
            }
            if let due = args["dueDate"], ISO8601DateFormatter().date(from: due) == nil {
                return "dueDate دەبێت بە شێوەی ISO-8601 بێت؛ بۆ نموونە 2026-10-14T18:00:00Z."
            }
        case .runShortcut, .sendWebhook, .callServerAPI:
            return "ئەم tool ـە لەم وەشانەدا ناچالاکە و هیچ کاری دەرەکی ناکات."
        }
        return nil
    }

    static func requiresApproval(_ call: AgentToolCall) -> Bool {
        guard let name = AgentToolName(rawValue: call.name) else { return false }
        return approvalRequiredTools.contains(name)
    }
}
