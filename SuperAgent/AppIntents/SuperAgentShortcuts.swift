import AppIntents

@available(iOS 16.0, *)
struct SuperAgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskSuperAgentIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question"
            ],
            shortTitle: "Ask SuperAgent",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: RunSuperAgentCommandIntent(),
            phrases: [
                "Run a command with \(.applicationName)",
                "Tell \(.applicationName) to do something"
            ],
            shortTitle: "Run SuperAgent command",
            systemImageName: "bolt.horizontal.circle"
        )
    }
}
