#if DEBUG
import Photos
import UIKit

struct DebugPhotoGenerationConfig {
    var totalCount: Int = 50
    var monthsBack: Int = 12  // 最大120ヶ月（10年）
    var distributeEvenly: Bool = true
    var photosPerDay: Int = 5  // 1日あたりの写真数（クラスタテスト用）
    var simulateClusters: Bool = true  // 時間的なクラスタをシミュレート
}

enum DebugPhotoServiceError: Error, LocalizedError {
    case notAuthorized
    case creationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "フォトライブラリへのアクセスが許可されていません"
        case .creationFailed(let error):
            return "写真の作成に失敗しました: \(error.localizedDescription)"
        }
    }
}

final class DebugPhotoService {
    static let shared = DebugPhotoService()

    private init() {}

    /// ダミー写真を生成してフォトライブラリに追加
    func addDummyPhotos(
        config: DebugPhotoGenerationConfig,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> Int {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw DebugPhotoServiceError.notAuthorized
        }

        var created = 0
        let calendar = Calendar.current

        if config.distributeEvenly {
            // カレンダーテスト用: 各月の複数日に、時間クラスタ付きで生成
            let daysPerMonth = max(1, config.totalCount / config.monthsBack / config.photosPerDay)

            for month in 1...config.monthsBack {
                for dayIndex in 0..<daysPerMonth {
                    if created >= config.totalCount { break }

                    // 月内の異なる日を選択（1日, 5日, 10日, 15日, 20日, 25日...）
                    let dayOfMonth = min(1 + dayIndex * 5, 28)

                    // その日のベース時刻を設定
                    var baseComponents = calendar.dateComponents([.year, .month], from: Date())
                    baseComponents.month! -= month
                    baseComponents.day = dayOfMonth
                    baseComponents.hour = 10 + (dayIndex % 8)  // 10時〜17時でばらつき

                    guard let baseDate = calendar.date(from: baseComponents) else { continue }

                    // クラスタをシミュレート: 数分間隔で複数枚
                    for photoIndex in 0..<config.photosPerDay {
                        if created >= config.totalCount { break }

                        let clusterDate: Date
                        if config.simulateClusters {
                            // 5分間隔でクラスタを形成（密度テスト用）
                            clusterDate = calendar.date(byAdding: .minute, value: photoIndex * 5, to: baseDate)!
                        } else {
                            // ランダムな時刻
                            let randomMinutes = Int.random(in: 0..<60 * 8)  // 8時間以内でランダム
                            clusterDate = calendar.date(byAdding: .minute, value: randomMinutes, to: baseDate)!
                        }

                        let image = generateDummyImage(index: created, date: clusterDate, clusterIndex: photoIndex)

                        do {
                            try await saveToLibrary(image: image, creationDate: clusterDate)
                            created += 1
                            progress?(created, config.totalCount)
                        } catch {
                            throw DebugPhotoServiceError.creationFailed(underlying: error)
                        }
                    }
                }
            }
        } else {
            // ランダム配置
            for i in 0..<config.totalCount {
                let daysBack = Int.random(in: 31...(config.monthsBack * 30))
                let date = calendar.date(byAdding: .day, value: -daysBack, to: Date())!
                let image = generateDummyImage(index: i, date: date, clusterIndex: 0)

                do {
                    try await saveToLibrary(image: image, creationDate: date)
                    created += 1
                    progress?(created, config.totalCount)
                } catch {
                    throw DebugPhotoServiceError.creationFailed(underlying: error)
                }
            }
        }

        return created
    }

    private func dateInMonth(monthsAgo: Int, dayOffset: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month], from: Date())
        components.month! -= monthsAgo
        components.day = min(1 + dayOffset, 28)
        return Calendar.current.date(from: components)!
    }

    private func generateDummyImage(index: Int, date: Date, clusterIndex: Int) -> UIImage {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let month = Calendar.current.component(.month, from: date)
            let day = Calendar.current.component(.day, from: date)

            // 日付に応じて色を変える（同じ日は同系色）
            UIColor(
                hue: CGFloat(month) / 12.0,
                saturation: 0.5 + CGFloat(day % 10) * 0.03,
                brightness: 0.85 - CGFloat(clusterIndex) * 0.05,
                alpha: 1.0
            ).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            // 日付（大きく）
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy/MM/dd"
            let dateText = dateFormatter.string(from: date)

            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 32),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let dateRect = CGRect(x: 20, y: 140, width: 360, height: 50)
            dateText.draw(in: dateRect, withAttributes: dateAttributes)

            // 時刻（クラスタ確認用）
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let timeText = timeFormatter.string(from: date)

            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraphStyle
            ]
            let timeRect = CGRect(x: 20, y: 190, width: 360, height: 40)
            timeText.draw(in: timeRect, withAttributes: timeAttributes)

            // インデックス（小さく）
            let indexText = "#\(index + 1) (cluster: \(clusterIndex + 1))"
            let indexAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                .paragraphStyle: paragraphStyle
            ]
            let indexRect = CGRect(x: 20, y: 240, width: 360, height: 30)
            indexText.draw(in: indexRect, withAttributes: indexAttributes)
        }
    }

    private func saveToLibrary(image: UIImage, creationDate: Date) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            request.creationDate = creationDate
        }
    }
}
#endif
