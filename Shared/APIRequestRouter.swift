import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APIProviderKind: Equatable {
    case openRouter
    case gemini
    case custom

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .gemini: return "Google Gemini"
        case .custom: return "Custom API"
        }
    }
}

struct APIRequestRoute {
    let provider: APIProviderKind
    let apiKey: String
    let model: String
    let url: URL

    var safeEndpoint: String {
        APIRequestRouter.redactedEndpoint(from: url)
    }
}

enum APIRequestRouter {
    static let openRouterEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    static let geminiBaseURL = "https://generativelanguage.googleapis.com"
    static let defaultOpenRouterModel = "google/gemini-2.5-flash"
    static let defaultGeminiModel = "gemini-3.8-flash"
    static let defaultCustomEndpoint = "https://ollama.com/v1/chat/completions"
    static let defaultCustomModel = "gemma4:31b"

    static func normalizedAPIKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBearer = trimmed.replacingOccurrences(
            of: #"(?i)^Bearer\s+"#,
            with: "",
            options: .regularExpression
        )
        return withoutBearer.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’ \n\r\t"))
    }

    static func normalizedEndpoint(_ raw: String) -> String {
        var endpoint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while endpoint.hasSuffix("%60") { endpoint.removeLast(3) }
        while endpoint.hasSuffix("`") { endpoint.removeLast() }
        return endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedModelText(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func detectedProvider(for rawAPIKey: String, endpoint rawEndpoint: String = "") -> APIProviderKind {
        let key = normalizedAPIKey(rawAPIKey)
        let endpointHost = URLComponents(string: normalizedEndpoint(rawEndpoint))?.host?.lowercased()
        if endpointHost == "openrouter.ai" { return .openRouter }
        if endpointHost == "generativelanguage.googleapis.com" { return .gemini }
        // An explicitly configured non-default host wins over a key prefix. This
        // permits an Ollama/custom-compatible endpoint even if an old Gemini key remains saved.
        if let endpointHost, !endpointHost.isEmpty { return .custom }
        if key.hasPrefix("sk-or-v1-") { return .openRouter }
        if key.hasPrefix("AIza") { return .gemini }
        return .custom
    }

    static func defaultEndpoint(for provider: APIProviderKind) -> String {
        switch provider {
        case .openRouter: return openRouterEndpoint
        case .gemini: return geminiEndpoint(for: defaultGeminiModel)
        case .custom: return defaultCustomEndpoint
        }
    }

    private static func geminiEndpoint(for model: String) -> String {
        "\(geminiBaseURL)/v1beta/models/\(model):generateContent"
    }

    static func modelForSettings(_ rawModel: String, provider: APIProviderKind) -> String {
        let model = normalizedModelText(rawModel)
        switch provider {
        case .openRouter:
            guard model.contains("/") else { return defaultOpenRouterModel }
            return model
        case .gemini:
            if model.isEmpty || model == "gemini-2.5-pro" || model == "gemini-3.1-pro-preview" {
                return defaultGeminiModel
            }
            if model.hasPrefix("models/") {
                return String(model.dropFirst("models/".count))
            }
            if model.contains("/") {
                let suffix = model.split(separator: "/").last.map(String.init) ?? ""
                return suffix.hasPrefix("gemini-") ? suffix : defaultGeminiModel
            }
            return model.hasPrefix("gemini-") ? model : defaultGeminiModel
        case .custom:
            return model.isEmpty ? defaultCustomModel : model
        }
    }

    static func resolve(apiKey rawAPIKey: String, endpoint rawEndpoint: String, model rawModel: String) -> APIRequestRoute? {
        let apiKey = normalizedAPIKey(rawAPIKey)
        guard !apiKey.isEmpty else { return nil }
        let provider = detectedProvider(for: apiKey, endpoint: rawEndpoint)
        let model = modelForSettings(rawModel, provider: provider)

        let endpoint: String
        switch provider {
        case .openRouter:
            endpoint = openRouterEndpoint
        case .gemini:
            let allowedModelCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
            guard !model.isEmpty, model.unicodeScalars.allSatisfy(allowedModelCharacters.contains) else { return nil }
            endpoint = geminiEndpoint(for: model)
        case .custom:
            endpoint = normalizedEndpoint(rawEndpoint)
        }

        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return APIRequestRoute(provider: provider, apiKey: apiKey, model: model, url: url)
    }

    static func makePayload(
        route: APIRequestRoute,
        temperature: Double,
        messages: [[String: Any]]
    ) -> [String: Any]? {
        switch route.provider {
        case .openRouter, .custom:
            return [
                "model": route.model,
                "temperature": temperature,
                "messages": messages
            ]
        case .gemini:
            return makeGeminiGenerateContentPayload(temperature: temperature, messages: messages)
        }
    }

    static func configure(_ request: inout URLRequest, route: APIRequestRoute, body: Data) {
        request.url = route.url
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if route.provider == .gemini {
            request.setValue(route.apiKey, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
    }

    static func responseText(from data: Data, provider: APIProviderKind) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if provider == .gemini {
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    static func errorDetails(from data: Data, apiKey: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let error = json["error"] as? [String: Any]
            let message = (error?["message"] as? String)
                ?? (json["message"] as? String)
                ?? (error?["status"] as? String)
                ?? "The provider returned an error without a message."
            return String(message.replacingOccurrences(of: apiKey, with: "[hidden]").prefix(240))
        }
        let body = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: apiKey, with: "[hidden]")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? "The provider returned a non-JSON response." : String(body.prefix(180))
    }

    static func httpErrorMessage(statusCode: Int, data: Data, route: APIRequestRoute) -> String {
        let details = errorDetails(from: data, apiKey: route.apiKey)
        if statusCode == 429 && route.provider == .gemini {
            return "هەڵەی API (HTTP 429): سنووری quota ـی Google Gemini بۆ ئەم پڕۆژە/مۆدێلە تێپەڕیوە. کلیل یان Endpoint ناتوانێت quota زیاد بکات؛ لە AI Studio سنووری خۆت بپشکنە یان چاوەڕێی نوێبوونەوە بکە.\n\(details)\nURL: \(route.safeEndpoint)"
        }
        return "هەڵەی API (HTTP \(statusCode)): \(details)\nURL: \(route.safeEndpoint)"
    }

    static func redactedEndpoint(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let sensitiveNames: Set<String> = ["key", "api_key", "apikey", "token", "access_token", "authorization"]
        components.queryItems = components.queryItems?.map { item in
            if sensitiveNames.contains(item.name.lowercased()) {
                return URLQueryItem(name: item.name, value: "[REDACTED]")
            }
            return item
        }
        return components.string ?? url.absoluteString
    }

    private static func makeGeminiGenerateContentPayload(
        temperature: Double,
        messages: [[String: Any]]
    ) -> [String: Any]? {
        var systemParts: [[String: Any]] = []
        var contents: [[String: Any]] = []

        for message in messages {
            let role = (message["role"] as? String ?? "user").lowercased()
            guard let content = message["content"],
                  let parts = geminiParts(from: content),
                  !parts.isEmpty else { continue }

            if role == "system" || role == "developer" {
                systemParts.append(contentsOf: parts)
            } else if role == "assistant" {
                let preface = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !preface.isEmpty {
                    systemParts.append(["text": "Preferred response opening, when appropriate: \(preface)"])
                }
            } else {
                contents.append(["role": "user", "parts": parts])
            }
        }

        guard !contents.isEmpty else { return nil }
        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": ["temperature": temperature],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]
        if !systemParts.isEmpty {
            payload["systemInstruction"] = ["parts": systemParts]
        }
        return payload
    }

    private static func geminiParts(from content: Any) -> [[String: Any]]? {
        if let text = content as? String { return [["text": text]] }
        guard let items = content as? [[String: Any]] else { return nil }
        var parts: [[String: Any]] = []
        for item in items {
            if let text = item["text"] as? String {
                parts.append(["text": text])
                continue
            }
            guard item["type"] as? String == "image_url" else { continue }
            guard let imageObject = item["image_url"] as? [String: Any],
                  let imageURL = imageObject["url"] as? String,
                  imageURL.hasPrefix("data:") else { return nil }
            guard let comma = imageURL.firstIndex(of: ",") else { return nil }
            let header = String(imageURL[..<comma])
            let base64 = String(imageURL[imageURL.index(after: comma)...])
            let mimeType = header.dropFirst("data:".count).split(separator: ";").first.map(String.init) ?? "image/jpeg"
            guard !base64.isEmpty else { return nil }
            parts.append(["inlineData": ["mimeType": mimeType, "data": base64]])
        }
        return parts
    }
}
