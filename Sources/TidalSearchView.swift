import SwiftUI
import AuthenticationServices

struct TidalSearchView: View {
    @ObservedObject var tidalManager = TidalManager.shared
    @State private var searchQuery = ""
    @State private var searchAlbums = false
    @Environment(\.presentationMode) var presentationMode
    
    var onItemSelected: ((TidalMediaItem) -> Void)?
    
    init(onItemSelected: ((TidalMediaItem) -> Void)? = nil) {
        self.onItemSelected = onItemSelected
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if tidalManager.isAuthenticated {
                    Picker("Search Type", selection: $searchAlbums) {
                        Text("Tracks").tag(false)
                        Text("Albums").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    SearchBar(text: $searchQuery, onSearch: {
                        tidalManager.search(query: searchQuery, searchAlbums: searchAlbums)
                    })
                    
                    List(tidalManager.searchResults) { item in
                        Button(action: {
                            onItemSelected?(item)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title).font(.headline)
                                    Text(item.artist).font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                                if item.type == .album {
                                    Image(systemName: "square.stack")
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "music.note")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    if let userCode = tidalManager.loginUserCode, let uri = tidalManager.loginUri, let url = URL(string: uri) {
                        VStack(spacing: 20) {
                            Text("Please log in to TIDAL")
                                .font(.headline)
                            
                            Text("Visit the link below and enter this code:")
                                .multilineTextAlignment(.center)
                            
                            Text(userCode)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            
                            Link("Open Login Page", destination: url)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            
                            ProgressView("Waiting for authorization...")
                                .padding(.top)
                        }
                        .padding()
                    } else if tidalManager.isLoggingIn {
                        ProgressView("Initializing login...")
                            .padding()
                    } else {
                        VStack(spacing: 16) {
                            Text("You must connect to TIDAL first.")
                                .padding()
                            
                            Button("Connect to TIDAL") {
                                tidalManager.login()
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            
                            if let error = tidalManager.loginError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            }
                        }
                    }
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
