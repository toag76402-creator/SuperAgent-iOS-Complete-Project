import Foundation
import CoreFoundation

enum AgentToolName: String, Codable, CaseIterable {
    case analyzeCurrentScreen
    case analyzeSelectedImage
    case openURL
    case copyToClipboard
    case saveNote
    case createReminder
    case runShortcut
    case sendWebhook
    case callServerAPI
    case readAppStatus

    var title: String {
        switch self {
        case .analyzeCurrentScreen: return "شیکردنەوەی شاشەی ئێستا"
        case .analyzeSelectedImage: return "شیکردنەوەی وێنەی هەڵبژێردراو"
        case .openURL: return "کردنەوەی بەستەر"
        case .copyToClipboard: return "کۆپیکردن بۆ clipboard"
        case .saveNote: return "پاشەکەوتکردنی تێبینی"
        case .createReminder: return "دروستکردنی بیرخستنەوە"
        case .runShortcut: return "بەڕێوەبردنی Shortcut"
        case .sendWebhook: return "ناردنی webhook"
        case .callServerAPI: return "بانگکردنی APIی سێرڤەر"
        case .readAppStatus: return "خوێندنەوەی دۆخی ئەپ"
        }
    }
}

struct AgentToolCall {
    let name: String
    let arguments: [String: String]

    init(name: String, arguments: [String: String] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    init?(jsonName: String, rawArguments: Any?) {
        guard jsonName.count <= 64 else { return nil }
        var values: [String: String] = [:]
        if let dictionary = rawArguments as? [String: Any] {
            guard dictionary.count <= 12 else { return nil }
            for (key, value) in dictionary {
                guard key.count <= 64 else { return nil }
                if let string = value as? String {
                    values[key] = string
                } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                    values[key] = number.stringValue
                } else {
                    return nil
                }
            }
        } else if rawArguments != nil {
            return nil
        }
        self.name = jsonName
        self.arguments = values
    }
}

struct AgentToolResult {
    let succeeded: Bool
    let message: String

    static func success(_ message: String) -> AgentToolResult {
        AgentToolResult(succeeded: true, message: message)
    }

    static func failure(_ message: String) -> AgentToolResult {
        AgentToolResult(succeeded: false, message: message)
    }
}
