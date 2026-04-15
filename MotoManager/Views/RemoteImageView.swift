import SwiftUI

struct RemoteImageView: View {
    let url: String
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else if isLoading {
                ZStack {
                    Color.secondary.opacity(0.1)
                    ProgressView()
                }
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    Image(systemName: "bicycle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard image == nil && !isLoading else { return }
        
        isLoading = true
        Task {
            do {
                let data = try await NetworkManager.shared.fetchImage(url: url)
                if let uiImage = UIImage(data: data) {
                    self.image = uiImage
                }
            } catch {
                print("Error loading image \(url): \(error)")
            }
            isLoading = false
        }
    }
}
