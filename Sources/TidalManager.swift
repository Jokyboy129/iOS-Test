import Foundation
import Combine
import Auth
import Player
import EventProducer
import AuthenticationServices

enum TidalMediaType: String, Codable {
    case track
    case album
}

struct TidalMediaItem: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let type: TidalMediaType
}

class TidalManager: NSObject, ObservableObject, PlayerListener {
    static let shared = TidalManager()
    
    @Published var isAuthenticated = false
    @Published var searchResults: [TidalMediaItem] = []
    
    @Published var loginUserCode: String?
    @Published var loginUri: String?
    @Published var isLoggingIn = false
    @Published var loginError: String?
    
    var player: Player?
    
    private var trackQueue: [String] = []
    private var originalQueue: [String] = []
    private var currentTrackId: String?
    
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
        isAuthenticated = TidalAuth.shared.isUserLoggedIn
    }
    
    func login() {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        Task {
            do {
                let response = try await TidalAuth.shared.initializeDeviceLogin()
                DispatchQueue.main.async {
                    self.loginUserCode = response.userCode
                    self.loginUri = response.verificationUriComplete ?? response.verificationUri
                }
                
                try await TidalAuth.shared.finalizeDeviceLogin(deviceCode: response.deviceCode)
                
                DispatchQueue.main.async {
                    self.checkAuthStatus()
                    if self.isAuthenticated { self.setupPlayer() }
                    self.isLoggingIn = false
                    self.loginUserCode = nil
                    self.loginUri = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.loginError = error.localizedDescription
                    self.isLoggingIn = false
                    self.loginUserCode = nil
                    self.loginUri = nil
                }
                print("Tidal login failed: \(error)")
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
    
    func playMedia(path: String) {
        if path.hasPrefix("album:") {
            let albumId = String(path.dropFirst(6))
            playAlbum(id: albumId)
        } else {
            originalQueue = [path]
            trackQueue = [path]
            playNextInQueue()
        }
    }
    
    private func playAlbum(id: String) {
        Task {
            do {
                let credentials = try await TidalAuth.shared.getCredentials(apiErrorSubStatus: nil)
                guard let token = credentials.token else { return }
                
                let urlStr = "https://openapi.tidal.com/v2/albums/\(id)/items?countryCode=US"
                guard let url = URL(string: urlStr) else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.tidal.v1+json", forHTTPHeaderField: "accept")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["data"] as? [[String: Any]] else {
                    return
                }
                
                var trackIds: [String] = []
                for item in items {
                    if let itemType = item["type"] as? String, itemType == "tracks", let trackId = item["id"] as? String {
                        trackIds.append(trackId)
                    }
                }
                
                if trackIds.isEmpty, let included = json["included"] as? [[String: Any]] {
                    for item in included {
                        if let itemType = item["type"] as? String, itemType == "tracks", let trackId = item["id"] as? String {
                            trackIds.append(trackId)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.originalQueue = trackIds
                    self.trackQueue = trackIds
                    self.playNextInQueue()
                }
            } catch {
                print("Failed to fetch album tracks: \(error)")
            }
        }
    }
    
    private func playNextInQueue() {
        if trackQueue.isEmpty {
            trackQueue = originalQueue // Loop queue!
        }
        guard !trackQueue.isEmpty else { return }
        
        let nextId = trackQueue.removeFirst()
        playTrack(id: nextId)
    }
    
    func playTrack(id: String) {
        guard let player = player else { return }
        let track = MediaProduct(productType: .TRACK, productId: id)
        currentTrackId = id
        player.load(track)
        player.play()
    }
    
    func stop() {
        player?.pause()
        trackQueue.removeAll()
        originalQueue.removeAll()
        currentTrackId = nil
    }
    
    func search(query: String, searchAlbums: Bool = false) {
        // We need an access token to search.
        Task {
            do {
                let credentials = try await TidalAuth.shared.getCredentials(apiErrorSubStatus: nil)
                guard let token = credentials.token else { return }
                
                let typeStr = searchAlbums ? "albums" : "tracks"
                let urlStr = "https://openapi.tidal.com/v2/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&type=\(typeStr)&countryCode=US"
                guard let url = URL(string: urlStr) else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.tidal.v1+json", forHTTPHeaderField: "accept")
                
                URLSession.shared.dataTask(with: request) { data, _, error in
                    guard let data = data, error == nil else { return }
                    
                    do {
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let included = json["included"] as? [[String: Any]] else {
                            return
                        }
                        
                        var itemsData: [[String: Any]] = []
                        var artistsMap: [String: String] = [:]
                        
                        for item in included {
                            guard let type = item["type"] as? String,
                                  let id = item["id"] as? String,
                                  let attributes = item["attributes"] as? [String: Any] else { continue }
                            
                            if type == typeStr {
                                itemsData.append(item)
                            } else if type == "artists" {
                                if let name = attributes["name"] as? String {
                                    artistsMap[id] = name
                                }
                            }
                        }
                        
                        var results: [TidalMediaItem] = []
                        for itemData in itemsData {
                            guard let id = itemData["id"] as? String,
                                  let attributes = itemData["attributes"] as? [String: Any],
                                  let title = attributes["title"] as? String else { continue }
                            
                            var artistName = "Unknown Artist"
                            if let relationships = itemData["relationships"] as? [String: Any],
                               let artists = relationships["artists"] as? [String: Any],
                               let artistsData = artists["data"] as? [[String: Any]],
                               let firstArtist = artistsData.first,
                               let artistId = firstArtist["id"] as? String,
                               let name = artistsMap[artistId] {
                                artistName = name
                            }
                            
                            let mediaType: TidalMediaType = searchAlbums ? .album : .track
                            results.append(TidalMediaItem(id: id, title: title, artist: artistName, type: mediaType))
                        }
                        
                        DispatchQueue.main.async {
                            self.searchResults = results
                        }
                    } catch {
                        print("Failed to parse search response: \(error)")
                    }
                }.resume()
            } catch {
                print("Tidal search failed: \(error)")
            }
        }
    }
    
    // MARK: - PlayerListener
    func stateChanged(to state: State) {
        print("Tidal player state: \(state)")
    }
    
    func ended(_ mediaProduct: MediaProduct) {
        print("Tidal player ended track")
        DispatchQueue.main.async {
            self.playNextInQueue()
        }
    }
    
    func mediaTransitioned(to mediaProduct: MediaProduct, with playbackContext: PlaybackContext) {
        print("Tidal player transitioned")
    }
    
    func failed(with error: PlayerError) {
        print("Tidal player failed: \(error)")
    }
    
    func mediaServicesWereReset() {
        print("Tidal player media services were reset")
    }
}

