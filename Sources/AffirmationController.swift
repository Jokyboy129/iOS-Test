import Foundation
import AVFoundation

class AffirmationController: ObservableObject {
    static let shared = AffirmationController()
    
    @Published var isEnabled = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "affirmationsEnabled")
            if isEnabled { startLoop() } else { stopLoop() }
        }
    }
    
    @Published var delayMinutes: Double = 1.0 {
        didSet { UserDefaults.standard.set(delayMinutes, forKey: "affirmationDelay") }
    }
    
    @Published var panMode: Int = 0 { // 0: Center, 1: Left, 2: Right, 3: Random
        didSet { UserDefaults.standard.set(panMode, forKey: "affirmationPanMode") }
    }
    
    @Published var selectedVoice: String = "alloy" {
        didSet { UserDefaults.standard.set(selectedVoice, forKey: "affirmationVoice") }
    }
    
    @Published var language: String = "de" { // "en" or "de"
        didSet { UserDefaults.standard.set(language, forKey: "affirmationLanguage") }
    }
    
    private var playbackTask: Task<Void, Never>?
    
    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "affirmationsEnabled")
        delayMinutes = UserDefaults.standard.object(forKey: "affirmationDelay") as? Double ?? 1.0
        panMode = UserDefaults.standard.integer(forKey: "affirmationPanMode")
        selectedVoice = UserDefaults.standard.string(forKey: "affirmationVoice") ?? "alloy"
        language = UserDefaults.standard.string(forKey: "affirmationLanguage") ?? "de"
    }
    
    func startLoop() {
        playbackTask?.cancel()
        playbackTask = Task {
            // Initial delay before starting
            try? await Task.sleep(nanoseconds: UInt64(delayMinutes * 60 * 1_000_000_000))
            
            let count = language == "de" ? AffirmationData.germanAffirmations.count : AffirmationData.englishAffirmations.count
            guard count > 0 else { return }
            
            var indices = Array(0..<count)
            indices.shuffle() // Play randomly
            
            for index in indices {
                if Task.isCancelled { break }
                
                if let url = OpenAITTSService.shared.getAudioURL(for: index, language: language, voice: selectedVoice) {
                    await playAudio(url: url)
                }
                
                // Wait for the delay
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(delayMinutes * 60 * 1_000_000_000))
                }
            }
            
            // Loop restarts if still enabled
            if isEnabled && !Task.isCancelled {
                startLoop()
            }
        }
    }
    
    func stopLoop() {
        playbackTask?.cancel()
        playbackTask = nil
        AudioEngineManager.shared.affirmationPlayerNode.stop()
    }
    
    private func playAudio(url: URL) async {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let node = AudioEngineManager.shared.affirmationPlayerNode
        
        switch panMode {
        case 0: node.pan = 0.0 // Center
        case 1: node.pan = -1.0 // Left
        case 2: node.pan = 1.0 // Right
        case 3: node.pan = Float.random(in: -1.0...1.0) // Random
        default: node.pan = 0.0
        }
        
        AudioEngineManager.shared.updateVolumes()
        
        return await withCheckedContinuation { continuation in
            node.scheduleFile(file, at: nil) {
                continuation.resume()
            }
            if !node.isPlaying {
                node.play()
            }
        }
    }
}
