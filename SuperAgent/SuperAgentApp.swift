import SwiftUI

@main
struct SuperAgentApp: App {
    @StateObject private var config = AgentConfig.shared
    @StateObject private var brain = AgentBrain()
    
    var body: some Scene {
        WindowGroup {
            ContentView(brain: brain, config: config)
                .preferredColorScheme(.dark)
        }
    }
}
