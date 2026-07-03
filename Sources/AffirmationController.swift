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
    
    @Published var language: String = "de" { // "en" or "de"
        didSet { 
            UserDefaults.standard.set(language, forKey: "affirmationLanguage")
            updateAvailableAffirmationsCount()
        }
    }
    
    @Published var style: String = "normal" { // "normal" or "whisper"
        didSet { 
            UserDefaults.standard.set(style, forKey: "affirmationStyle")
            updateAvailableAffirmationsCount()
        }
    }
    
    @Published var availableAffirmationsCount: Int = 0
    
    private var playbackTask: Task<Void, Never>?
    private var availableURLs: [URL] = []
    
    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "affirmationsEnabled")
        delayMinutes = UserDefaults.standard.object(forKey: "affirmationDelay") as? Double ?? 1.0
        panMode = UserDefaults.standard.integer(forKey: "affirmationPanMode")
        language = UserDefaults.standard.string(forKey: "affirmationLanguage") ?? "de"
        style = UserDefaults.standard.string(forKey: "affirmationStyle") ?? "normal"
        
        cleanupOldAIFiles()
        updateAvailableAffirmationsCount()
        
        if isEnabled {
            startLoop()
        }
    }
    
    private func cleanupOldAIFiles() {
        let fileManager = FileManager.default
        guard let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: docDir, includingPropertiesForKeys: nil)
            for fileURL in fileURLs where fileURL.pathExtension == "mp3" {
                // The AI files were named like "de_alloy_0.mp3"
                if fileURL.lastPathComponent.contains("_alloy_") || 
                   fileURL.lastPathComponent.contains("_echo_") || 
                   fileURL.lastPathComponent.contains("_fable_") || 
                   fileURL.lastPathComponent.contains("_onyx_") || 
                   fileURL.lastPathComponent.contains("_nova_") || 
                   fileURL.lastPathComponent.contains("_shimmer_") {
                    try fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Error cleaning up old AI files: \(error)")
        }
    }
    
    private func updateAvailableAffirmationsCount() {
        var urls: [URL] = []
        var index = 1
        
        while true {
            var foundURL: URL? = nil
            
            // Check lowercase extensions first
            if let url = Bundle.main.url(forResource: "\(index)", withExtension: "wav", subdirectory: "affirmations/\(language)/\(style)") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "mp3", subdirectory: "affirmations/\(language)/\(style)") {
                foundURL = url
            } 
            // Check uppercase extensions
            else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "WAV", subdirectory: "affirmations/\(language)/\(style)") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "MP3", subdirectory: "affirmations/\(language)/\(style)") {
                foundURL = url
            }
            // Fallbacks for flattened structures
            else if let url = Bundle.main.url(forResource: "\(language)_\(index)", withExtension: "wav") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(language)_\(index)", withExtension: "mp3") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(language)_\(index)", withExtension: "WAV") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(language)_\(index)", withExtension: "MP3") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "wav") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "mp3") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "WAV") {
                foundURL = url
            } else if let url = Bundle.main.url(forResource: "\(index)", withExtension: "MP3") {
                foundURL = url
            }
            
            if let url = foundURL {
                urls.append(url)
                index += 1
            } else {
                break
            }
        }
        
        availableURLs = urls
        availableAffirmationsCount = availableURLs.count
    }
    
    func startLoop() {
        playbackTask?.cancel()
        playbackTask = Task {
            // Initial delay before starting
            try? await Task.sleep(nanoseconds: UInt64(delayMinutes * 60 * 1_000_000_000))
            
            updateAvailableAffirmationsCount()
            guard availableAffirmationsCount > 0 else { return }
            
            var shuffledURLs = availableURLs
            shuffledURLs.shuffle() // Play randomly
            
            for url in shuffledURLs {
                if Task.isCancelled { break }
                
                await playAudio(url: url)
                
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
        Task {
            AudioEngineManager.shared.affirmationPlayerNode.stop()
        }
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
