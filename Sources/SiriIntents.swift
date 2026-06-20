import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct StartSleepEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Sleep Engine"
    static var description = IntentDescription("Starts playing the soundscape in Sleep Engine.")
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = AudioEngineManager.shared
        if !engine.isPlaying {
            engine.play()
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct SleepEngineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: StartSleepEngineIntent(),
                phrases: [
                    "Start \(.applicationName)",
                    "Play sounds with \(.applicationName)",
                    "Start my soundscape in \(.applicationName)",
                    "Play \(.applicationName)"
                ],
                shortTitle: "Start Sleep Engine",
                systemImageName: "play.fill"
            )
        ]
    }
}
