# Photo Cleaner iOS App - Design Doc

## 概要

Amazon Photosにバックアップ済みの写真をiPhoneから自動的に削除するiOSアプリ。お気に入りやアルバム所属の写真は保護し、月ごとに1枚を自動でKeepアルバムに残して振り返りを担保する。

## コンセプト

**操作は最小限：** 起動 → 確認 → 削除ボタン → システム確認OK → 完了

ユーザーが行う操作は「削除ボタンを押す」と「システム確認でOKを押す」の2回のみ。

## 技術的制約

### 削除確認ダイアログは必須

iOSのセキュリティ仕様により、`PHAssetChangeRequest.deleteAssets()`を呼び出すとシステムの確認ダイアログが必ず表示される。これは回避できない。ただしバッチ削除なら何枚でも確認は1回のみ。

### Amazon Photos連携の制約

Amazon PhotosにはパブリックAPIが存在しないため、「N日以前の写真はバックアップ済みとみなす」ルールで代替する。

## 機能仕様

### 1. 削除候補の自動抽出

以下の条件すべてを満たす写真を自動で削除候補とする：

| 条件 | 判定方法 |
|------|----------|
| 撮影日がN日以上前 | `PHAsset.creationDate` |
| お気に入りではない | `PHAsset.isFavorite == false` |
| どのアルバムにも属していない | `PHAssetCollection`をスキャン |

```swift
func fetchDeletionCandidates(olderThan days: Int) -> PHFetchResult<PHAsset> {
    let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
        format: "creationDate < %@ AND isFavorite == NO",
        cutoffDate as NSDate
    )
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    
    return PHAsset.fetchAssets(with: .image, options: options)
}

func filterOutAlbumAssets(_ assets: PHFetchResult<PHAsset>) -> [PHAsset] {
    let albumAssetIDs = fetchAllAlbumAssetIDs()
    var candidates: [PHAsset] = []
    
    assets.enumerateObjects { asset, _, _ in
        if !albumAssetIDs.contains(asset.localIdentifier) {
            candidates.append(asset)
        }
    }
    return candidates
}
```

### 2. 日付サンプリング（振り返り用）

削除実行前に、月ごとに1枚を自動で「Keep」アルバムに保存する。

```swift
func sampleForKeep(from candidates: [PHAsset]) -> [PHAsset] {
    // 月ごとにグループ化
    let grouped = Dictionary(grouping: candidates) { asset -> String in
        let date = asset.creationDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    // 各月から1枚をランダムに選択
    return grouped.compactMap { _, assets in
        assets.randomElement()
    }
}

func saveToKeepAlbum(assets: [PHAsset]) async throws {
    let album = try await getOrCreateAlbum(named: "Keep")
    
    try await PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCollectionChangeRequest(for: album)
        request?.addAssets(assets as NSFastEnumeration)
    }
}
```

### 3. バッチ削除

Keepに保存した写真を除外し、残りをまとめて削除する。

```swift
func batchDelete(assets: [PHAsset], excluding keepAssets: [PHAsset]) async throws {
    let keepIDs = Set(keepAssets.map { $0.localIdentifier })
    let toDelete = assets.filter { !keepIDs.contains($0.localIdentifier) }
    
    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.deleteAssets(toDelete as NSFastEnumeration)
    }
    // ここでシステム確認ダイアログが1回表示される
}
```

### 4. 処理フロー

```
┌─────────────────────────────────────────────────────────┐
│ 1. アプリ起動                                            │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│ 2. 自動抽出                                              │
│    - N日以上前の写真を取得                                │
│    - お気に入り・アルバム所属を除外                        │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│ 3. サンプリング                                          │
│    - 月ごとに1枚を「Keep」アルバムに保存                   │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│ 4. プレビュー表示                                        │
│    - 削除予定: XXX枚                                     │
│    - Keep保存: XX枚                                      │
│    - サムネイルグリッド（確認用）                          │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│ 5. ユーザー操作: 「削除」ボタンをタップ                    │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│ 6. システム確認ダイアログ（iOS標準）                       │
│    「XXX枚の写真を削除しますか？」                         │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│ 7. 完了                                                  │
│    - 削除完了メッセージ                                   │
│    - 解放された容量を表示                                 │
└─────────────────────────────────────────────────────────┘
```

## 画面構成

### メイン画面（1画面のみ）

```
┌─────────────────────────────────────┐
│  Photo Cleaner            ⚙️        │
├─────────────────────────────────────┤
│                                     │
│   🗑️ 削除対象: 1,234枚              │
│   📁 Keep保存: 12枚（月1枚）         │
│   💾 解放予定: 2.3GB                │
│                                     │
├─────────────────────────────────────┤
│ ┌─────┬─────┬─────┬─────┐          │
│ │     │     │     │     │          │
│ ├─────┼─────┼─────┼─────┤          │
│ │     │     │     │     │  サムネイル│
│ ├─────┼─────┼─────┼─────┤  プレビュー│
│ │     │     │     │     │          │
│ └─────┴─────┴─────┴─────┘          │
│                                     │
├─────────────────────────────────────┤
│                                     │
│   ┌─────────────────────────────┐   │
│   │     🗑️ 削除を実行する        │   │
│   └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

### 設定画面

| 設定 | デフォルト値 | 説明 |
|------|-------------|------|
| バックアップ猶予日数 | 30日 | この日数以上前の写真のみ対象 |
| 月あたりのKeep枚数 | 1枚 | 振り返り用に残す枚数 |
| Keepアルバム名 | "Keep" | 保存先アルバム名 |

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
├─────────────────────────────────────────────────────────┤
│          MainView          │        SettingsView         │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                   CleanerViewModel                       │
│  - candidates: [PHAsset]                                │
│  - keepSamples: [PHAsset]                               │
│  - state: .idle | .scanning | .ready | .deleting        │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                     PhotoService                         │
│  - fetchDeletionCandidates()                            │
│  - sampleForKeep()                                      │
│  - saveToKeepAlbum()                                    │
│  - batchDelete()                                        │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                        PhotoKit                          │
└─────────────────────────────────────────────────────────┘
```

## ディレクトリ構成

```
PhotoCleaner/
├── PhotoCleanerApp.swift
├── Views/
│   ├── MainView.swift
│   ├── ThumbnailGridView.swift
│   └── SettingsView.swift
├── ViewModels/
│   └── CleanerViewModel.swift
├── Services/
│   └── PhotoService.swift
├── Models/
│   └── AppSettings.swift
└── Info.plist
```

## 必要な権限

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>写真を整理・削除するためにフォトライブラリへのアクセスが必要です</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>振り返り用の写真をKeepアルバムに保存するために必要です</string>
```

## 配布方法

SideStore経由でサイドロード。

1. 初回のみPC/MacでSideStoreをインストール
2. Xcodeでビルドした`.ipa`をSideStoreで署名・インストール
3. 7日ごとに自動再署名（iPhone単体、同一Wi-Fi上）

## 既知の制限事項

1. **削除確認ダイアログは必ず表示される** - iOSの仕様、バッチでも1回は必須
2. **Amazon Photosとの自動連携は不可** - 日付ベースで代替
3. **削除は「最近削除した項目」に移動** - 30日後に完全削除
4. **iCloud共有ライブラリは対象外** - iOS 16以降でアクセス制限あり