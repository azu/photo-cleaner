import Photos
import SwiftUI

enum CleanerState: Equatable {
    case idle
    case requestingPermission
    case scanning
    case ready
    case savingKeep
    case deleting
    case completed(deletedCount: Int, freedBytes: Int64)
    case error(String)

    static func == (lhs: CleanerState, rhs: CleanerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.requestingPermission, .requestingPermission),
             (.scanning, .scanning),
             (.ready, .ready),
             (.savingKeep, .savingKeep),
             (.deleting, .deleting):
            return true
        case (.completed(let lc, let lb), .completed(let rc, let rb)):
            return lc == rc && lb == rb
        case (.error(let le), .error(let re)):
            return le == re
        default:
            return false
        }
    }
}

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var state: CleanerState = .idle
    @Published var deletionCandidates: DeletionCandidates?
    @Published var previewAssets: [PHAsset] = []  // プレビュー用の先頭N件
    @Published var estimatedFreeBytes: Int64 = 0
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let photoService = PhotoService.shared
    private let previewLimit = 100

    var deletionCount: Int {
        deletionCandidates?.deletionCount ?? 0
    }

    /// コンタクトシート生成予定数（日数から概算）
    var estimatedContactSheetCount: Int {
        guard let candidates = deletionCandidates else { return 0 }
        // 1日1枚なので、20日で1ヶ月として概算
        return max(0, candidates.keepAssetIDs.count / 20)
    }

    var isActionEnabled: Bool {
        state == .ready && deletionCount > 0
    }

    // MARK: - Authorization

    func checkAuthorization() async {
        authorizationStatus = photoService.checkAuthorizationStatus()

        if authorizationStatus == .notDetermined {
            state = .requestingPermission
            authorizationStatus = await photoService.requestAuthorization()
        }

        switch authorizationStatus {
        case .authorized, .limited:
            await scan()
        case .denied, .restricted:
            state = .error("フォトライブラリへのアクセスが許可されていません。設定アプリから許可してください。")
        case .notDetermined:
            state = .idle
        @unknown default:
            state = .error("不明な権限状態です")
        }
    }

    // MARK: - Scanning

    func scan() async {
        await scan(settings: nil)
    }

    func scan(settings: AppSettings?) async {
        let effectiveSettings = settings ?? .default

        state = .scanning
        deletionCandidates = nil
        previewAssets = []
        estimatedFreeBytes = 0

        do {
            // DeletionCandidatesを取得（PHFetchResultベース、メモリ効率的）
            let candidates = try await photoService.fetchDeletionCandidates(
                olderThan: effectiveSettings.backupGraceDays,
                generateContactSheet: effectiveSettings.generateContactSheet,
                protectedAlbumNames: effectiveSettings.protectedAlbumNames
            )
            deletionCandidates = candidates

            // プレビュー用に先頭N件だけ取得
            previewAssets = candidates.prefixAssets(previewLimit)

            // サンプリングベースでサイズを推定
            estimatedFreeBytes = await photoService.estimateTotalSize(of: candidates)

            state = .ready
        } catch let error as PhotoServiceError {
            state = .error(error.localizedDescription)
        } catch {
            state = .error("スキャン中にエラーが発生しました: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    func executeCleanup(settings: AppSettings) async {
        guard state == .ready, let candidates = deletionCandidates else { return }

        // Generate and save contact sheets (if enabled)
        if settings.generateContactSheet && !candidates.keepAssetIDs.isEmpty {
            state = .savingKeep
            do {
                let sheetCount = try await photoService.generateAndSaveContactSheets(
                    keepAssetIDs: candidates.keepAssetIDs,
                    albumName: settings.keepAlbumName
                )
                #if DEBUG
                print("DEBUG: Generated \(sheetCount) contact sheets")
                #endif
            } catch {
                state = .error("コンタクトシートの保存に失敗しました: \(error.localizedDescription)")
                return
            }
        }

        // Delete remaining photos
        state = .deleting
        let countToDelete = deletionCount
        let bytesToFree = estimatedFreeBytes

        do {
            try await photoService.batchDelete(candidates: candidates)
            state = .completed(deletedCount: countToDelete, freedBytes: bytesToFree)
        } catch let error as PhotoServiceError {
            if case .noAssets = error {
                state = .completed(deletedCount: 0, freedBytes: 0)
            } else {
                state = .error(error.localizedDescription)
            }
        } catch {
            // User cancelled the deletion dialog
            state = .ready
        }
    }

    // MARK: - Reset

    func reset() {
        state = .idle
        deletionCandidates = nil
        previewAssets = []
        estimatedFreeBytes = 0
    }
}
