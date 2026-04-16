import SwiftUI

struct RemoteImageView: View {
    let url: String
    
    var body: some View {
        let _ = print("RemoteImageView: Rendering URL: \(url)")
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .empty:
                let _ = print("RemoteImageView: State EMPTY for \(url)")
                ZStack {
                    Color.secondary.opacity(0.1)
                    ProgressView()
                }
            case .success(let image):
                let _ = print("RemoteImageView: State SUCCESS for \(url)")
                image
                    .resizable()
            case .failure(let error):
                let _ = print("RemoteImageView: State FAILURE for \(url) - Error: \(error.localizedDescription)")
                fallbackImage
            @unknown default:
                let _ = print("RemoteImageView: State UNKNOWN for \(url)")
                fallbackImage
            }
        }
    }
    
    private var fallbackImage: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            Image(systemName: "bicycle")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.3))
        }
    }
}
