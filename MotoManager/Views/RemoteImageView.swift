import SwiftUI

struct RemoteImageView: View {
    let url: String

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if loadFailed {
                fallbackImage
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    ProgressView()
                }
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        loadFailed = false

        // Disk cache first — keeps images visible offline.
        if let data = ImageCache.shared.data(for: url),
           let cached = UIImage(data: data) {
            self.image = cached
            return
        }

        guard let requestURL = URL(string: url) else {
            loadFailed = true
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            ImageCache.shared.save(data, for: url)
            if let downloaded = UIImage(data: data) {
                self.image = downloaded
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
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
