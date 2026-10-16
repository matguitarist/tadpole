// Mod pictures from Nexus (from Starseed): decoded once and kept, and the
// large picture at the top of the details panel.

import AppKit
import SwiftUI

/// Decoded images by URL, so switching between mods doesn't reload them.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var images: [URL: NSImage] = [:]
    private var loading: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { images[url] }

    func image(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        if let task = loading[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { images[url] = image }
        return image
    }
}

/// A picture as wide as its container, in its own shape: landscape pictures
/// fill the width; portrait ones are shown whole (up to 4:5), over a blurred
/// copy of themselves.
struct ShapedPicture: View {
    let url: URL
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    /// Tallest box for portrait pictures (width / height).
    private static let tallestAspect: CGFloat = 0.8

    var body: some View {
        Group {
            if let image, image.size.width > 0, image.size.height > 0 {
                let aspect = image.size.width / image.size.height
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 24)
                        .opacity(0.6)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(max(aspect, Self.tallestAspect), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
            }
        }
        .task(id: url) {
            image = ImageCache.shared.cached(url)
            if image == nil { image = await ImageCache.shared.image(for: url) }
        }
    }
}
