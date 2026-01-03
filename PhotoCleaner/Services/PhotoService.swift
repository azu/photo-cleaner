import Photos
import UIKit

enum PhotoServiceError: Error, LocalizedError {
    case notAuthorized
    case albumCreationFailed
    case deletionFailed(underlying: Error)
    case noAssets

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "フォトライブラリへのアクセスが許可されていません"
        case .albumCreationFailed:
            return "アルバムの作成に失敗しました"
        case .deletionFailed(let error):
            return "削除に失敗しました: \(error.localizedDescription)"
        case .noAssets:
            return "削除対象の写真がありません"
        }
    }
}

/// 削除候補を遅延評価で保持する構造体
struct DeletionCandidates {
    let fetchResult: PHFetchResult<PHAsset>
    let albumAssetIDs: Set<String>  // Keepアルバム内（削除対象外）
    let keepAssetIDs: Set<String>   // コンタクトシート生成用の代表写真
    let candidateCount: Int  // 削除対象数（= deletionCount）

    /// 削除対象数（Keepアルバム以外の全て）
    var deletionCount: Int {
        candidateCount
    }

    var totalCount: Int {
        fetchResult.count
    }

    /// イテレータでアクセス（メモリ効率的）
    func enumerateCandidates(_ block: @escaping (PHAsset, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var index = 0
        fetchResult.enumerateObjects { asset, _, stop in
            if !self.albumAssetIDs.contains(asset.localIdentifier) {
                block(asset, index, stop)
                index += 1
            }
        }
    }

    /// プレビュー用に先頭N件を取得
    func prefixAssets(_ count: Int) -> [PHAsset] {
        var assets: [PHAsset] = []
        assets.reserveCapacity(min(count, candidateCount))
        enumerateCandidates { asset, _, stop in
            assets.append(asset)
            if assets.count >= count {
                stop.pointee = true
            }
        }
        return assets
    }

    /// 削除対象のIDをバッチで取得（Keepアルバム以外の全て）
    func enumerateDeletionTargetIDs(batchSize: Int = 1000, handler: @escaping ([String]) -> Bool) {
        var batch: [String] = []
        batch.reserveCapacity(batchSize)

        fetchResult.enumerateObjects { asset, _, stop in
            let id = asset.localIdentifier
            // Keepアルバム内の写真のみ除外（コンタクトシート生成後は代表写真も削除）
            if !self.albumAssetIDs.contains(id) {
                batch.append(id)
                if batch.count >= batchSize {
                    let shouldContinue = handler(batch)
                    batch.removeAll(keepingCapacity: true)
                    if !shouldContinue {
                        stop.pointee = true
                    }
                }
            }
        }

        // 残りを処理
        if !batch.isEmpty {
            _ = handler(batch)
        }
    }
}

final class PhotoService {
    static let shared = PhotoService()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func checkAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Fetch Deletion Candidates

    /// 削除候補をPHFetchResultベースで取得（メモリ効率的）
    func fetchDeletionCandidates(olderThan days: Int, generateContactSheet: Bool, protectedAlbumNames: [String] = ["Keep"]) async throws -> DeletionCandidates {
        let status = checkAuthorizationStatus()
        guard status == .authorized || status == .limited else {
            throw PhotoServiceError.notAuthorized
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate < %@ AND isFavorite == NO",
            cutoffDate as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        let albumAssetIDs = fetchProtectedAlbumAssetIDs(albumNames: protectedAlbumNames)

        #if DEBUG
        print("DEBUG: cutoffDate = \(cutoffDate)")
        print("DEBUG: days = \(days)")
        print("DEBUG: fetchResult.count (before album filter) = \(fetchResult.count)")
        print("DEBUG: albumAssetIDs.count = \(albumAssetIDs.count)")
        #endif

        // Keepサンプルを選択 + カウントを同時に計算（1回のイテレーションで）
        let (keepAssetIDs, candidateCount) = sampleKeepAssetIDsAndCount(
            from: fetchResult,
            excludingAlbumIDs: albumAssetIDs,
            generateContactSheet: generateContactSheet
        )

        #if DEBUG
        print("DEBUG: candidateCount (after album filter) = \(candidateCount)")
        print("DEBUG: keepAssetIDs.count (for contact sheet) = \(keepAssetIDs.count)")
        print("DEBUG: deletionCount = \(candidateCount) (all candidates will be deleted)")
        #endif

        return DeletionCandidates(
            fetchResult: fetchResult,
            albumAssetIDs: albumAssetIDs,
            keepAssetIDs: keepAssetIDs,
            candidateCount: candidateCount
        )
    }

    /// 保護対象アルバムに所属するアセットIDを取得
    private func fetchProtectedAlbumAssetIDs(albumNames: [String]) -> Set<String> {
        var assetIDs = Set<String>()

        for albumName in albumNames {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
            let albums = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: fetchOptions
            )

            guard let album = albums.firstObject else {
                continue
            }

            let assets = PHAsset.fetchAssets(in: album, options: nil)
            assets.enumerateObjects { asset, _, _ in
                assetIDs.insert(asset.localIdentifier)
            }

            #if DEBUG
            print("DEBUG: Protected album '\(albumName)' contains \(assets.count) assets")
            #endif
        }

        #if DEBUG
        print("DEBUG: Total protected assets = \(assetIDs.count)")
        #endif

        return assetIDs
    }

    // MARK: - Album List

    /// ユーザーのアルバム一覧を取得
    func fetchUserAlbums() -> [String] {
        var albumNames: [String] = []

        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )

        userAlbums.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle {
                albumNames.append(title)
            }
        }

        return albumNames.sorted()
    }

    // MARK: - Sampling for Keep (Density-based)

    /// 日ごとの密度情報を追跡する構造体
    private struct DayClusterInfo {
        var maxDensity: Int = 0
        var representativeId: String = ""
        // 現在追跡中のクラスタ
        var currentClusterCount: Int = 0
        var currentClusterLastTime: Date?
        var currentClusterRepresentativeId: String = ""
    }

    /// クラスタ判定の閾値（秒）
    private static let clusterThresholdSeconds: TimeInterval = 30 * 60  // 30分

    /// 密度ベースで各日から代表を1枚選択 + カウント（シングルパス）
    private func sampleKeepAssetIDsAndCount(
        from fetchResult: PHFetchResult<PHAsset>,
        excludingAlbumIDs albumAssetIDs: Set<String>,
        generateContactSheet: Bool
    ) -> (keepIDs: Set<String>, candidateCount: Int) {
        var candidateCount = 0

        guard generateContactSheet else {
            // カウントのみ
            fetchResult.enumerateObjects { asset, _, _ in
                if !albumAssetIDs.contains(asset.localIdentifier) {
                    candidateCount += 1
                }
            }
            return ([], candidateCount)
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"

        // 月 → 日 → クラスタ情報
        var dayInfoByMonth: [String: [String: DayClusterInfo]] = [:]
        var previousDay: String?
        var previousTime: Date?

        fetchResult.enumerateObjects { asset, _, _ in
            guard !albumAssetIDs.contains(asset.localIdentifier) else { return }
            candidateCount += 1

            guard let creationDate = asset.creationDate else { return }

            let dayKey = dayFormatter.string(from: creationDate)
            let monthKey = String(dayKey.prefix(7))  // "yyyy-MM"

            // 月のエントリを初期化
            if dayInfoByMonth[monthKey] == nil {
                dayInfoByMonth[monthKey] = [:]
            }

            // 日のエントリを初期化
            if dayInfoByMonth[monthKey]?[dayKey] == nil {
                dayInfoByMonth[monthKey]?[dayKey] = DayClusterInfo()
            }

            let isSameDay = (previousDay == dayKey)
            let isWithinCluster: Bool
            if isSameDay, let prevTime = previousTime {
                isWithinCluster = creationDate.timeIntervalSince(prevTime) <= Self.clusterThresholdSeconds
            } else {
                isWithinCluster = false
            }

            if isSameDay && isWithinCluster {
                // 同じクラスタ継続
                dayInfoByMonth[monthKey]?[dayKey]?.currentClusterCount += 1
            } else {
                // 前のクラスタを確定（同じ日の場合のみ）
                if isSameDay, let info = dayInfoByMonth[monthKey]?[dayKey] {
                    if info.currentClusterCount > info.maxDensity {
                        dayInfoByMonth[monthKey]?[dayKey]?.maxDensity = info.currentClusterCount
                        dayInfoByMonth[monthKey]?[dayKey]?.representativeId = info.currentClusterRepresentativeId
                    }
                }
                // 新しいクラスタ開始
                dayInfoByMonth[monthKey]?[dayKey]?.currentClusterCount = 1
                dayInfoByMonth[monthKey]?[dayKey]?.currentClusterRepresentativeId = asset.localIdentifier
            }

            dayInfoByMonth[monthKey]?[dayKey]?.currentClusterLastTime = creationDate
            previousDay = dayKey
            previousTime = creationDate
        }

        // 最後のクラスタを確定
        for (monthKey, days) in dayInfoByMonth {
            for (dayKey, info) in days {
                if info.currentClusterCount > info.maxDensity {
                    dayInfoByMonth[monthKey]?[dayKey]?.maxDensity = info.currentClusterCount
                    dayInfoByMonth[monthKey]?[dayKey]?.representativeId = info.currentClusterRepresentativeId
                }
            }
        }

        // 各日の代表IDを収集
        var keepIDs = Set<String>()
        for (_, days) in dayInfoByMonth {
            for (_, info) in days {
                if !info.representativeId.isEmpty {
                    keepIDs.insert(info.representativeId)
                }
            }
        }

        #if DEBUG
        print("DEBUG: dayInfoByMonth.count (unique months) = \(dayInfoByMonth.count)")
        for (month, days) in dayInfoByMonth.sorted(by: { $0.key < $1.key }) {
            let daysWithPhotos = days.filter { !$0.value.representativeId.isEmpty }.count
            print("DEBUG: Month \(month): \(daysWithPhotos) days with photos")
        }
        print("DEBUG: Total keepIDs = \(keepIDs.count)")
        #endif

        return (keepIDs, candidateCount)
    }

    /// Keep対象のアセットを取得（IDから復元）
    func fetchKeepAssets(ids: Set<String>) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    /// Keep対象のアセットを月ごとにグループ化して取得
    func fetchKeepAssetsByMonth(ids: Set<String>) -> [String: [PHAsset]] {
        guard !ids.isEmpty else { return [:] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assetsByMonth: [String: [PHAsset]] = [:]

        result.enumerateObjects { asset, _, _ in
            let monthKey = formatter.string(from: asset.creationDate ?? Date())
            if assetsByMonth[monthKey] == nil {
                assetsByMonth[monthKey] = []
            }
            assetsByMonth[monthKey]?.append(asset)
        }

        return assetsByMonth
    }

    // MARK: - Album Operations

    func getOrCreateAlbum(named name: String) async throws -> PHAssetCollection {
        // Check if album already exists
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let existingAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )

        if let existing = existingAlbums.firstObject {
            return existing
        }

        // Create new album
        var albumPlaceholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            albumPlaceholder = request.placeholderForCreatedAssetCollection
        }

        guard let placeholder = albumPlaceholder,
              let album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [placeholder.localIdentifier],
                options: nil
              ).firstObject else {
            throw PhotoServiceError.albumCreationFailed
        }

        return album
    }

    func saveToKeepAlbum(assets: [PHAsset], albumName: String) async throws {
        guard !assets.isEmpty else { return }

        let album = try await getOrCreateAlbum(named: albumName)

        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets(assets as NSFastEnumeration)
        }
    }

    // MARK: - Deletion

    /// DeletionCandidatesから削除を実行（バッチ処理でメモリ効率的）
    func batchDelete(candidates: DeletionCandidates) async throws {
        guard candidates.deletionCount > 0 else {
            throw PhotoServiceError.noAssets
        }

        // IDを収集（文字列のみなのでメモリ効率的）
        var allIDs: [String] = []
        allIDs.reserveCapacity(candidates.deletionCount)

        candidates.enumerateDeletionTargetIDs(batchSize: 5000) { batch in
            allIDs.append(contentsOf: batch)
            return true
        }

        // PHAssetをバッチでフェッチして削除（1回の確認ダイアログで済むように）
        // PHAsset.fetchAssetsは内部で効率的に処理される
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)

        guard fetchResult.count > 0 else {
            throw PhotoServiceError.noAssets
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
        } catch {
            throw PhotoServiceError.deletionFailed(underlying: error)
        }
    }

    // MARK: - Thumbnail Loading

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Storage Calculation

    /// サンプリングベースでサイズを推定（メモリ効率的）
    func estimateTotalSize(of candidates: DeletionCandidates, sampleSize: Int = 100) async -> Int64 {
        let sampleAssets = candidates.prefixAssets(sampleSize)
        guard !sampleAssets.isEmpty else { return 0 }

        var sampleTotal: Int64 = 0
        for asset in sampleAssets {
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    sampleTotal += size
                }
            }
        }

        let avgSize = sampleTotal / Int64(sampleAssets.count)
        let totalCount = candidates.deletionCount
        return avgSize * Int64(totalCount)
    }

    /// 配列版（少量の場合に使用）
    func calculateTotalSize(of assets: [PHAsset]) async -> Int64 {
        var totalSize: Int64 = 0

        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
            }
        }

        return totalSize
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Contact Sheet Generation

    /// 月ごとのカレンダー型コンタクトシートを生成（iPhone縦長比率: 4列×8行）
    func generateContactSheet(
        for monthKey: String,  // "yyyy-MM"
        assets: [PHAsset],
        cellSize: CGSize = CGSize(width: 240, height: 240)
    ) async -> UIImage? {
        let columns = 4
        let rows = 8
        let headerHeight: CGFloat = 120  // ノッチ対応で上部余白増
        let footerHeight: CGFloat = 80   // 下部余白（角丸対応）
        let sideMargin: CGFloat = 24     // 左右余白
        let padding: CGFloat = 6

        let contentWidth = CGFloat(columns) * (cellSize.width + padding) - padding
        let totalWidth = contentWidth + sideMargin * 2
        let totalHeight = headerHeight + CGFloat(rows) * (cellSize.height + padding) - padding + footerHeight

        // 月の情報を取得
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        guard let monthDate = dateFormatter.date(from: monthKey) else { return nil }

        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: monthDate)!

        // 日付ごとにアセットをマッピング
        var assetsByDay: [Int: PHAsset] = [:]
        for asset in assets {
            if let date = asset.creationDate {
                let day = calendar.component(.day, from: date)
                assetsByDay[day] = asset
            }
        }

        // サムネイルを事前読み込み
        var thumbnails: [Int: UIImage] = [:]
        for (day, asset) in assetsByDay {
            if let thumb = await loadThumbnail(for: asset, targetSize: cellSize) {
                thumbnails[day] = thumb
            }
        }

        // 画像を描画
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
        return renderer.image { ctx in
            // 背景
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: totalWidth, height: totalHeight)))

            // ヘッダー（月タイトル）
            let titleFormatter = DateFormatter()
            titleFormatter.dateFormat = "yyyy年M月"
            let title = titleFormatter.string(from: monthDate)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
            let titleRect = CGRect(x: sideMargin, y: 50, width: totalWidth - sideMargin * 2, height: 50)
            title.draw(in: titleRect, withAttributes: titleAttributes)

            // 日付セル（4列×8行、左上から順番に1〜31）
            for day in 1...range.count {
                let index = day - 1
                let col = index % columns
                let row = index / columns

                let x = sideMargin + CGFloat(col) * (cellSize.width + padding)
                let y = headerHeight + CGFloat(row) * (cellSize.height + padding)
                let cellRect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)

                if let thumbnail = thumbnails[day] {
                    // サムネイル描画
                    thumbnail.draw(in: cellRect)

                    // 日付オーバーレイ
                    let overlay = CGRect(x: x, y: y, width: 36, height: 28)
                    UIColor.black.withAlphaComponent(0.6).setFill()
                    UIBezierPath(roundedRect: overlay, cornerRadius: 4).fill()

                    let dayText = "\(day)"
                    let dayAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 16),
                        .foregroundColor: UIColor.white
                    ]
                    dayText.draw(in: CGRect(x: x + 6, y: y + 5, width: 28, height: 20), withAttributes: dayAttrs)
                } else {
                    // プレースホルダー
                    UIColor.systemGray5.setFill()
                    UIBezierPath(roundedRect: cellRect, cornerRadius: 8).fill()

                    let dayText = "\(day)"
                    let placeholderAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                        .foregroundColor: UIColor.systemGray3
                    ]
                    let textSize = dayText.size(withAttributes: placeholderAttrs)
                    let textX = x + (cellSize.width - textSize.width) / 2
                    let textY = y + (cellSize.height - textSize.height) / 2
                    dayText.draw(at: CGPoint(x: textX, y: textY), withAttributes: placeholderAttrs)
                }
            }
        }
    }

    /// コンタクトシートをフォトライブラリに保存（日付をその月の1日に設定）
    func saveContactSheetToLibrary(image: UIImage, albumName: String, monthKey: String) async throws {
        let album = try await getOrCreateAlbum(named: albumName)

        // 月の1日を作成日として設定
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        let monthDate = dateFormatter.date(from: monthKey) ?? Date()

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            request.creationDate = monthDate
            guard let placeholder = request.placeholderForCreatedAsset,
                  let albumRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumRequest.addAssets([placeholder] as NSFastEnumeration)
        }
    }

    /// Keep対象から月ごとにコンタクトシートを生成して保存
    func generateAndSaveContactSheets(keepAssetIDs: Set<String>, albumName: String) async throws -> Int {
        let assetsByMonth = fetchKeepAssetsByMonth(ids: keepAssetIDs)
        var savedCount = 0

        for (monthKey, assets) in assetsByMonth.sorted(by: { $0.key < $1.key }) {
            if let contactSheet = await generateContactSheet(for: monthKey, assets: assets) {
                try await saveContactSheetToLibrary(image: contactSheet, albumName: albumName, monthKey: monthKey)
                savedCount += 1
            }
        }

        return savedCount
    }
}
