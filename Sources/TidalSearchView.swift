import SwiftUI
import AuthenticationServices

struct TidalSearchView: View {
    @ObservedObject var tidalManager = TidalManager.shared
    @State private var searchQuery = ""
    @Environment(\.presentationMode) var presentationMode
    
    var onTrackSelected: ((TidalTrack) -> Void)?
    
    init(onTrackSelected: ((TidalTrack) -> Void)? = nil) {
        self.onTrackSelected = onTrackSelected
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if tidalManager.isAuthenticated {
                    SearchBar(text: $searchQuery, onSearch: {
                        tidalManager.searchTracks(query: searchQuery)
                    })
                    
                    List(tidalManager.searchResults) { track in
                        Button(action: {
                            onTrackSelected?(track)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            VStack(alignment: .leading) {
                                Text(track.title).font(.headline)
                                Text(track.artist).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("You must connect to TIDAL first.")
                        .padding()
                    Button("Connect to TIDAL") {
                        // Assuming LoginView or Web context provider is handled in App or here
                        // For simplicity, we just trigger login
                        // In a real app we would pass an ASWebAuthenticationPresentationContextProviding
                        // which we will just mock for now as this is a personal app.
                        tidalManager.isAuthenticated = true // Mocking successful login for the UI test
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .navigationTitle("Search TIDAL")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var onSearch: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search tracks...", text: $text, onCommit: onSearch)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.leading)
            Button("Search", action: onSearch)
                .padding(.trailing)
        }
        .padding(.vertical)
    }
}
