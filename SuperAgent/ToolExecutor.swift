import Foundation
import UIKit
import EventKit

final class ToolExecutor {
    private let eventStore = EKEventStore()

    func execute(
        _ call: AgentToolCall,
        hasImage: Bool,
        isBroadcasting: Bool,
        approved: Bool,
        completion: @escaping (AgentToolResult?, ToolApprovalRequest?) -> Void
    ) {
        let gate = ToolOutcomeGate(completion)
        let finish: (AgentToolResult?, ToolApprovalRequest?) -> Void = { result, approval in
            gate.finish(result, approval)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + AgentLoop.toolTimeout) {
            finish(.failure("کاتی 30 چرکەی tool بەسەرچوو؛ ئەنجامی سەرکەوتوو وەردەست نییە."), nil)
        }
        if let validation = ToolRegistry.validate(call, hasImage: hasImage) {
            finish(.failure(validation), nil)
            return
        }
        guard let name = AgentToolName(rawValue: call.name) else {
            finish(.failure("Tool ناشناسە."), nil)
            return
        }
        if ToolRegistry.requiresApproval(call), !approved {
            let details: String
            switch name {
            case .openURL: details = "بەستەر: \(call.arguments["url"] ?? "")"
            case .copyToClipboard: details = "دەقی کۆپیکراو: \(call.arguments["text"] ?? "")"
            case .createReminder:
                details = "ناونیشان: \(call.arguments["title"] ?? "")\nکات: \(call.arguments["dueDate"] ?? "کات دیاری نەکراوە")"
            default: details = name.title
            }
            finish(nil, ToolApprovalRequest(title: name.title, details: details))
            return
        }

        switch name {
        case .readAppStatus:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "نازانراو"
            finish(.success("SuperAgent v\(version). لایڤی شاشە: \(isBroadcasting ? "چالاکە" : "ناچالاکە")."), nil)
        case .analyzeCurrentScreen, .analyzeSelectedImage:
            finish(.success("وێنەکە لەم turn ـەدا پێشتر بۆ مۆدێل نێردراوە؛ tool خۆی شیکاریی جیاواز یان هەڵوێستێکی تر دروست نەکرد."), nil)
        case .saveNote:
            saveNote(title: call.arguments["title"] ?? "", content: call.arguments["content"] ?? "", completion: finish)
        case .copyToClipboard:
            DispatchQueue.main.async {
                UIPasteboard.general.string = call.arguments["text"] ?? ""
                finish(.success("دەقەکە بە پەسەندکردنی بەکارهێنەر کۆپی کرا."), nil)
            }
        case .openURL:
            guard let raw = call.arguments["url"], let url = URL(string: raw) else {
                finish(.failure("URL دروست نییە."), nil)
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { opened in
                    finish(opened ? .success("iOS بەستەرەکەی کردەوە: \(url.host ?? "HTTPS")") : .failure("iOS نەیتوانی ئەم بەستەرە بکاتەوە."), nil)
                }
            }
        case .createReminder:
            createReminder(
                title: call.arguments["title"] ?? "",
                dueDate: call.arguments["dueDate"],
                shouldContinue: { gate.isPending() },
                completion: finish
            )
        case .runShortcut, .sendWebhook, .callServerAPI:
            finish(.failure("ئەم tool ـە ڕێک نەخراوە، هیچ کاری دەرەکی ئەنجام نەدرا."), nil)
        }
    }

    private func saveNote(title: String, content: String, completion: @escaping (AgentToolResult?, ToolApprovalRequest?) -> Void) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(.failure("شوێنی پاشەکەوتکردنی تێبینی بەردەست نییە."), nil)
            return
        }
        let safeTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let fileURL = documents.appendingPathComponent("\(safeTitle).txt")
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(.failure("فایلێک بەو ناوە پێشتر هەیە؛ هیچ فایلێک نەگۆڕدرا."), nil)
            return
        }
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            completion(.success("تێبینییە نوێیەکە لە ناو Documentsی ئەپدا پاشەکەوت کرا: \(fileURL.lastPathComponent)."), nil)
        } catch {
            completion(.failure("پاشەکەوتکردنی تێبینی سەرکەوتوو نەبوو."), nil)
        }
    }

    private func createReminder(
        title: String,
        dueDate: String?,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping (AgentToolResult?, ToolApprovalRequest?) -> Void
    ) {
        let save: (Bool, Error?) -> Void = { [weak self] granted, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard shouldContinue() else { return }
                guard granted, error == nil else {
                    completion(.failure("دەسەڵاتی Reminders پێنەدرا یان هەڵە ڕوویدا؛ بیرخستنەوە دروست نەکرا."), nil)
                    return
                }
                let reminder = EKReminder(eventStore: self.eventStore)
                reminder.title = title
                reminder.calendar = self.eventStore.defaultCalendarForNewReminders()
                if let dueDate, let date = ISO8601DateFormatter().date(from: dueDate) {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                }
                do {
                    try self.eventStore.save(reminder, commit: true)
                    completion(.success("بیرخستنەوە بە پەسەندکردنی تۆ لە Reminders دروست کرا."), nil)
                } catch {
                    completion(.failure("Reminders نەیتوانی بیرخستنەوەکە پاشەکەوت بکات."), nil)
                }
            }
        }
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToReminders(completion: save)
        } else {
            eventStore.requestAccess(to: .reminder, completion: save)
        }
    }
}

private final class ToolOutcomeGate {
    private let lock = NSLock()
    private var finished = false
    private let completion: (AgentToolResult?, ToolApprovalRequest?) -> Void

    init(_ completion: @escaping (AgentToolResult?, ToolApprovalRequest?) -> Void) { self.completion = completion }

    func isPending() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !finished
    }

    func finish(_ result: AgentToolResult?, _ approval: ToolApprovalRequest?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        DispatchQueue.main.async { self.completion(result, approval) }
    }
}
