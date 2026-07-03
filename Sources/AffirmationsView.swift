import SwiftUI

struct AffirmationsView: View {
    @ObservedObject var controller = AffirmationController.shared
    @ObservedObject var engine = AudioEngineManager.shared
    
    var body: some View {
        NavigationView {
            Form {
                if controller.availableAffirmationsCount == 0 {
                    Section {
                        Text("This version contains no affirmations")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Playback Settings")) {
                    Toggle("Enable Affirmations", isOn: $controller.isEnabled)
                    
                    VStack {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text(String(format: "%.0f%%", engine.affirmationVolume * 100))
                        }
                        Slider(value: $engine.affirmationVolume, in: 0...1)
                    }
                    
                    VStack {
                        HStack {
                            Text("Delay Between Affirmations")
                            Spacer()
                            Text(String(format: "%.1f min", controller.delayMinutes))
                        }
                        Slider(value: $controller.delayMinutes, in: 0.2...10.0, step: 0.1)
                    }
                    
                    Picker("Panning", selection: $controller.panMode) {
                        Text("Center").tag(0)
                        Text("Left").tag(1)
                        Text("Right").tag(2)
                        Text("Random").tag(3)
                    }
                    
                    Picker("Playback Language", selection: $controller.language) {
                        Text("German").tag("de")
                        Text("English").tag("en")
                    }
                    
                    Picker("Playback Style", selection: $controller.style) {
                        Text("Normal").tag("normal")
                        Text("Whisper").tag("whisper")
                    }
                }
            }
            .navigationTitle("Affirmations")
        }
    }
}
