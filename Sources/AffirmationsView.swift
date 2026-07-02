import SwiftUI

struct AffirmationsView: View {
    @ObservedObject var ttsService = OpenAITTSService.shared
    @ObservedObject var controller = AffirmationController.shared
    @ObservedObject var engine = AudioEngineManager.shared
    
    @State private var showingGenerateAlert = false
    @State private var selectedLanguageToGenerate = "de"
    @State private var selectedVoiceToGenerate = "alloy"
    @State private var selectedModelToGenerate = "tts-1"
    
    let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Generation")) {
                    Picker("Language", selection: $selectedLanguageToGenerate) {
                        Text("German").tag("de")
                        Text("English").tag("en")
                    }
                    
                    Picker("Voice", selection: $selectedVoiceToGenerate) {
                        ForEach(voices, id: \.self) { voice in
                            Text(voice.capitalized).tag(voice)
                        }
                    }
                    
                    Picker("Quality Model", selection: $selectedModelToGenerate) {
                        Text("Standard (tts-1)").tag("tts-1")
                        Text("High Def (tts-1-hd)").tag("tts-1-hd")
                    }
                    
                    Button(action: {
                        showingGenerateAlert = true
                    }) {
                        HStack {
                            Text("Generate Affirmations Audio")
                            Spacer()
                            if ttsService.isGenerating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(ttsService.isGenerating)
                    .alert(isPresented: $showingGenerateAlert) {
                        Alert(
                            title: Text("Generate Audio?"),
                            message: Text("This will download affirmations using your OpenAI API key."),
                            primaryButton: .default(Text("Start")) {
                                Task {
                                    try? await ttsService.generateAffirmations(
                                        language: selectedLanguageToGenerate,
                                        voice: selectedVoiceToGenerate,
                                        model: selectedModelToGenerate
                                    )
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    }
                    
                    if ttsService.isGenerating {
                        VStack {
                            ProgressView(value: ttsService.progress)
                            Text("\(ttsService.generatedCount) / \(ttsService.totalCount) downloaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                    
                    Picker("Playback Voice", selection: $controller.selectedVoice) {
                        ForEach(voices, id: \.self) { voice in
                            Text(voice.capitalized).tag(voice)
                        }
                    }
                }
            }
            .navigationTitle("Affirmations")
        }
    }
}
