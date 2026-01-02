import Photos
import SwiftUI

struct ThumbnailGridView: View {
    let assets: [PHAsset]
    let totalCount: Int?

    @State private var thumbnails: [String: UIImage] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private let thumbnailSize = CGSize(width: 100, height: 100)

    init(assets: [PHAsset], totalCount: Int? = nil) {
        self.assets = assets
        self.totalCount = totalCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let total = totalCount, total > assets.count {
                Text("最初の\(assets.count)枚を表示中（全\(total)枚）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        ThumbnailCell(
                            asset: asset,
                            thumbnail: thumbnails[asset.localIdentifier],
                            size: thumbnailSize
                        )
                        .task {
                            await loadThumbnail(for: asset)
                        }
                    }
                }
            }
        }
    }

    private func loadThumbnail(for asset: PHAsset) async {
        guard thumbnails[asset.localIdentifier] == nil else { return }

        if let image = await PhotoService.shared.loadThumbnail(for: asset, targetSize: thumbnailSize) {
            thumbnails[asset.localIdentifier] = image
        }
    }
}

struct ThumbnailCell: View {
    let asset: PHAsset
    let thumbnail: UIImage?
    let size: CGSize

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

#Preview {
    ThumbnailGridView(assets: [])
}
