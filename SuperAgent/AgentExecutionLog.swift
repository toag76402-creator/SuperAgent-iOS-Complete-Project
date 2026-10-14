import Foundation
import Combine

final class AgentExecutionLog: ObservableObject {
    @Published private(set) var entries: [String] = []
    private let limit = 40

    func record(tool: String, succeeded: Bool) {
        let safeName = String(tool.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(64))
        let status = succeeded ? "سەرکەوتوو" : "سەرنەکەوتوو/ڕەتکراوە"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        DispatchQueue.main.async {
            self.entries.insert("\(timestamp) — \(safeName): \(status)", at: 0)
            if self.entries.count > self.limit { self.entries = Array(self.entries.prefix(self.limit)) }
        }
    }
}
