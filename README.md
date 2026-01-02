# Photo Cleaner

Amazon Photosにバックアップ済みの古い写真をiPhoneから削除し、ストレージを解放するiOSアプリ。

## 機能

- 指定日数（デフォルト: 2年）以上前の写真を削除
- お気に入り・Keepアルバム内の写真は保護
- 月ごとのカレンダー型コンタクトシートを自動生成（振り返り用）
- 密度ベースで各日の代表写真を選択（撮影が集中した時間帯から）
- 動画は削除対象外（写真のみ）

## セットアップ

### 1. クローンとセットアップ

```bash
git clone https://github.com/azu/photo-cleaner.git
cd photo-cleaner
./setup.sh
```

### 2. Team IDを設定

`LocalConfig.xcconfig` を編集:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
```

Team IDは [Apple Developer Account](https://developer.apple.com/account) → Membership で確認できます。

### 3. Xcodeでxcconfigを設定（初回のみ）

1. `open PhotoCleaner.xcodeproj`
2. プロジェクト設定 → Info タブ
3. Configurations セクション
4. Debug / Release 両方に `Config` を選択

### 4. ビルド

⌘R でビルド・実行

## 要件

- Xcode 15以上
- iOS 17以上

## 使い方

1. アプリ起動 → フォトライブラリへのアクセスを許可
2. 自動スキャンで削除対象を確認
3. 設定で猶予日数やコンタクトシート生成を調整
4. 「削除を実行する」で削除（システム確認ダイアログあり）

削除された写真は「最近削除した項目」に30日間保持されます。

## License

MIT
