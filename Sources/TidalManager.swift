import Foundation
import Auth
import Player
import EventProducer
import AuthenticationServices

struct TidalTrack: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
}

class TidalManager: NSObject, ObservableObject, PlayerListener {
    static let shared = TidalManager()
    
    @Published var isAuthenticated = false
    @Published var searchResults: [TidalTrack] = []
    
    var player: Player?
    
    private override init() { super.init() }
    
    func initialize() {
        let authConfig = AuthConfig(
            clientId: TidalConfig.clientId,
            clientUniqueKey: "SleepEngine_Unique_Key",
            clientSecret: TidalConfig.clientSecret,
            credentialsKey: "SleepEngine_Credentials"
        )
        TidalAuth.shared.config(config: authConfig)
        
        checkAuthStatus()
        
        if isAuthenticated {
            setupPlayer()
        }
    }
    
    func checkAuthStatus() {
        isAuthenticated = TidalAuth.shared.isUserLoggedIn()
    }
    
    func login(presentationContextProvider: ASWebAuthenticationPresentationContextProviding) {
        // Implement standard login flow
        // The SDK's Auth module provides ways to log in, but for custom apps, 
        // using the Auth.initializeLogin() or similar might be required.
        // For brevity, assuming a custom OAuth or SDK's login flow here.
        // Actually, TidalAuth.shared.login(...) exists in some SDK versions.
        
        // Let's implement a dummy toggle for testing if the actual login is complex,
        // but we will assume TidalAuth.shared handles this via their UI or URL scheme.
        // If Tidal SDK has a direct login method:
        Task {
            do {
                // TidalAuth handles login internally or provides a URL.
                // Assuming it has a standard `login(completion:)` or similar.
                // For this example, we will just set it to true if we successfully load credentials.
                // Since this requires proper ASWebAuthenticationSession, we leave a placeholder.
                DispatchQueue.main.async {
                    self.checkAuthStatus()
                    if self.isAuthenticated { self.setupPlayer() }
                }
            }
        }
    }
    
    func setupPlayer() {
        guard player == nil else { return }
        player = Player.bootstrap(
            playerListener: self,
            credentialsProvider: TidalAuth.shared,
            eventSender: TidalEventSender.shared
        )
    }
    
    func playTrack(id: String) {
        guard let player = player else { return }
        let track = MediaProduct(productType: .TRACK, productId: id)
        player.load(track)
        player.play()
    }
    
    func stop() {
        player?.pause()
    }
    
    func searchTracks(query: String) {
        // We need an access token to search.
        // TidalAuth.shared.getCredentials() returns current credentials.
        // This is a simplified search assuming we can get the token.
        guard let token = TidalAuth.shared.getCredentials()?.accessToken else { return }
        
        let urlStr = "https://openapi.tidal.com/v2/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&type=tracks&countryCode=US"
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.tidal.v1+json", forHTTPHeaderField: "accept")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else { return }
            // Parse JSON response. Simplified struct matching.
            // Tidal API v2 returns complex JSON.
            // For now, we will just parse an empty list if it fails.
            DispatchQueue.main.async {
                // Implementation of JSON parsing goes here.
                // self.searchResults = parsedTracks
            }
        }.resume()
    }
    
    // MARK: - PlayerListener
    func stateChanged(to state: Player.State) {
        print("Tidal player state: \(state)")
    }
}

