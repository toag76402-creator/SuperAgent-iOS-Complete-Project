import Foundation
import SwiftUI

struct CustomMacro: Identifiable, Codable {
    var id = UUID()
    var title: String
    var promptCommand: String
}

final class AgentConfig: ObservableObject {
    static let shared = AgentConfig()
    static let appGroupIdentifier = "group.com.custom.superagent.ai"
    static let defaultAPIEndpoint = APIRequestRouter.openRouterEndpoint
    static let defaultAPIModel = APIRequestRouter.defaultOpenRouterModel
    static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }

    static let safeSystemPrompt = """
    [SYSTEM INSTRUCTION: TECHNICAL SIMULATION MODE]
    You are SuperAgent, a technical data-processing and simulation assistant for iOS.

    CORE PARAMETERS:
    1. Produce direct, structured technical output based on the user's input.
    2. Clearly distinguish simulated results from actions actually completed by an app tool.
    3. Break complex requests into concrete, executable sub-tasks.
    4. Keep explanations concise; do not add lectures or unrelated commentary.
    5. For iOS automation, provide valid URL schemes, App Intents, or Shortcuts examples when appropriate.
    6. Use only tools explicitly listed by the app, validate their arguments, and never invent capabilities, credentials, coordinates, or successful results.
    7. Obtain explicit confirmation for external, privacy-sensitive, destructive, financial, or irreversible actions.
    8. Respect iOS permissions, sandbox restrictions, cancellation, and timeouts.
    9. Respond in Kurdish Sorani unless the user requests another language.

    AWAITING INPUT.
    """

    @Published var apiEndpoint: String {
        didSet {
            let cleaned = APIRequestRouter.normalizedEndpoint(apiEndpoint)
            if cleaned != apiEndpoint { apiEndpoint = cleaned }
            UserDefaults.standard.set(cleaned, forKey: "apiEndpoint")
            Self.sharedDefaults?.set(cleaned, forKey: "apiEndpoint")
        }
    }
    @Published var apiKey: String {
        didSet {
            let cleaned = APIRequestRouter.normalizedAPIKey(apiKey)
            if cleaned != apiKey { apiKey = cleaned }
            UserDefaults.standard.set(cleaned, forKey: "apiKey")
            Self.sharedDefaults?.set(cleaned, forKey: "apiKey")
            applyDetectedProviderDefaults()
        }
    }
    @Published var selectedModel: String {
        didSet {
            let cleaned = APIRequestRouter.normalizedModelText(selectedModel)
            if cleaned != selectedModel { selectedModel = cleaned }
            UserDefaults.standard.set(cleaned, forKey: "selectedModel")
            Self.sharedDefaults?.set(cleaned, forKey: "selectedModel")
        }
    }
    @Published var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: "temperature") }
    }
    @Published var coreSystemPrompt: String {
        didSet { UserDefaults.standard.set(coreSystemPrompt, forKey: "coreSystemPrompt") }
    }
    @Published var autoAnalyzeScreenshots: Bool {
        didSet { UserDefaults.standard.set(autoAnalyzeScreenshots, forKey: "autoAnalyzeScreenshots") }
    }
    @Published var customMacros: [CustomMacro] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(customMacros) {
                UserDefaults.standard.set(data, forKey: "customMacros")
            }
        }
    }

    var detectedProvider: APIProviderKind {
        APIRequestRouter.detectedProvider(for: apiKey, endpoint: apiEndpoint)
    }

    init() {
        let defaults = UserDefaults.standard
        let shared = Self.sharedDefaults
        let savedKey = APIRequestRouter.normalizedAPIKey(
            shared?.string(forKey: "apiKey") ?? defaults.string(forKey: "apiKey") ?? ""
        )
        let savedEndpoint = APIRequestRouter.normalizedEndpoint(
            shared?.string(forKey: "apiEndpoint") ?? defaults.string(forKey: "apiEndpoint") ?? ""
        )
        let candidateEndpoint = savedEndpoint.isEmpty ? Self.defaultAPIEndpoint : savedEndpoint
        let provider = APIRequestRouter.detectedProvider(for: savedKey, endpoint: candidateEndpoint)
        let endpoint = provider == .custom ? candidateEndpoint : APIRequestRouter.defaultEndpoint(for: provider)
        let savedModel = APIRequestRouter.normalizedModelText(
            shared?.string(forKey: "selectedModel") ?? defaults.string(forKey: "selectedModel") ?? ""
        )
        let fallbackModel: String
        switch provider {
        case .openRouter: fallbackModel = APIRequestRouter.defaultOpenRouterModel
        case .gemini: fallbackModel = APIRequestRouter.defaultGeminiModel
        case .custom: fallbackModel = APIRequestRouter.defaultCustomModel
        }
        let model = APIRequestRouter.modelForSettings(savedModel.isEmpty ? fallbackModel : savedModel, provider: provider)

        self.apiEndpoint = endpoint
        self.apiKey = savedKey
        self.selectedModel = model
        self.temperature = defaults.object(forKey: "temperature") as? Double ?? 0.15
        let storedPrompt = defaults.string(forKey: "coreSystemPrompt") ?? ""
        if storedPrompt.localizedCaseInsensitiveContains("unrestricted") || storedPrompt.localizedCaseInsensitiveContains("self-modifying") {
            self.coreSystemPrompt = Self.safeSystemPrompt
        } else {
            self.coreSystemPrompt = storedPrompt.isEmpty ? Self.safeSystemPrompt : storedPrompt
        }
        self.autoAnalyzeScreenshots = defaults.object(forKey: "autoAnalyzeScreenshots") as? Bool ?? false

        defaults.set(endpoint, forKey: "apiEndpoint")
        defaults.set(savedKey, forKey: "apiKey")
        defaults.set(model, forKey: "selectedModel")
        shared?.set(endpoint, forKey: "apiEndpoint")
        shared?.set(savedKey, forKey: "apiKey")
        shared?.set(model, forKey: "selectedModel")
        defaults.removeObject(forKey: "forceOverrideRules")
        defaults.removeObject(forKey: "assistantPrefill")
        defaults.removeObject(forKey: "forcePrefillEnabled")

        if let data = defaults.data(forKey: "customMacros"),
           let saved = try? JSONDecoder().decode([CustomMacro].self, from: data) {
            self.customMacros = saved.filter { !$0.title.localizedCaseInsensitiveContains("override") && !$0.promptCommand.localizedCaseInsensitiveContains("ignore all prior") }
        } else {
            self.customMacros = [
                CustomMacro(title: "🎯 شیکاریی BOTB", promptCommand: "ئەم وێنەیە بە وردی شیکار بکە و دڵنیایی/نادڵنیایی ڕوون بکە.")
            ]
        }
    }

    func normalizeAPISettings() {
        apiKey = APIRequestRouter.normalizedAPIKey(apiKey)
        apiEndpoint = APIRequestRouter.normalizedEndpoint(apiEndpoint)
        selectedModel = APIRequestRouter.normalizedModelText(selectedModel)
        applyDetectedProviderDefaults()
    }

    private func applyDetectedProviderDefaults() {
        let provider = APIRequestRouter.detectedProvider(for: apiKey, endpoint: apiEndpoint)
        if provider == .custom {
            if apiEndpoint.isEmpty { apiEndpoint = APIRequestRouter.defaultCustomEndpoint }
            if selectedModel.isEmpty { selectedModel = APIRequestRouter.defaultCustomModel }
            return
        }
        let endpoint = APIRequestRouter.defaultEndpoint(for: provider)
        let model = APIRequestRouter.modelForSettings(selectedModel, provider: provider)
        if apiEndpoint != endpoint { apiEndpoint = endpoint }
        if selectedModel != model { selectedModel = model }
    }
}
