import Foundation
import CryptoKit

class OpenAITTSService: ObservableObject {
    static let shared = OpenAITTSService()
    
    let apiKey = "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"
    
    @Published var isGenerating = false
    @Published var progress: Double = 0.0
    @Published var generatedCount = 0
    @Published var totalCount = 0
    
    func generateAffirmations(language: String, voice: String, model: String) async throws {
        let affirmations = language == "de" ? AffirmationData.germanAffirmations : AffirmationData.englishAffirmations
        
        DispatchQueue.main.async {
            self.isGenerating = true
            self.generatedCount = 0
            self.totalCount = affirmations.count
            self.progress = 0.0
        }
        
        for (index, text) in affirmations.enumerated() {
            let fileName = "\(language)_\(voice.lowercased())_\(index).mp3"
            let fileURL = getDocumentsDirectory().appendingPathComponent(fileName)
            
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try await downloadAudio(text: text, voice: voice.lowercased(), model: model, to: fileURL)
            }
            
            DispatchQueue.main.async {
                self.generatedCount += 1
                self.progress = Double(self.generatedCount) / Double(self.totalCount)
            }
        }
        
        DispatchQueue.main.async {
            self.isGenerating = false
            self.progress = 1.0
        }
    }
    
    private func downloadAudio(text: String, voice: String, model: String, to destination: URL) async throws {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": "mp3"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAITTS", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch audio from OpenAI"])
        }
        
        try data.write(to: destination)
    }
    
    func getAudioURL(for index: Int, language: String, voice: String) -> URL? {
        let fileName = "\(language)_\(voice.lowercased())_\(index).mp3"
        let fileURL = getDocumentsDirectory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
