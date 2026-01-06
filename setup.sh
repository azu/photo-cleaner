#!/bin/bash
# Photo Cleaner セットアップスクリプト

echo "Photo Cleaner セットアップ"
echo "=========================="

# Team IDを自動検出（証明書のOUフィールドから取得）
detect_team_id() {
    security find-certificate -c "Apple Development" -p 2>/dev/null | \
        openssl x509 -noout -subject 2>/dev/null | \
        grep -o 'OU=[A-Z0-9]\{10\}' | head -1 | sed 's/OU=//'
}

# LocalConfig.xcconfig を作成
if [ ! -f "LocalConfig.xcconfig" ]; then
    TEAM_ID=$(detect_team_id)

    if [ -n "$TEAM_ID" ]; then
        # Team IDを自動設定
        sed "s/YOUR_TEAM_ID_HERE/$TEAM_ID/" LocalConfig.xcconfig.template > LocalConfig.xcconfig
        echo "✓ LocalConfig.xcconfig を作成しました"
        echo "✓ DEVELOPMENT_TEAM = $TEAM_ID を自動設定しました"
        echo ""
        echo "次のステップ:"
        echo "1. open PhotoCleaner.xcodeproj"
        echo "2. ビルド (⌘R)"
    else
        # Team IDが見つからない場合は手動設定
        cp LocalConfig.xcconfig.template LocalConfig.xcconfig
        echo "✓ LocalConfig.xcconfig を作成しました"
        echo ""
        echo "⚠ コード署名証明書が見つかりませんでした"
        echo ""
        echo "次のステップ:"
        echo "1. LocalConfig.xcconfig を編集して DEVELOPMENT_TEAM を設定"
        echo "   例: DEVELOPMENT_TEAM = ABCD1234EF"
        echo ""
        echo "   Team IDの確認方法:"
        echo "   https://developer.apple.com/account → Membership → Team ID"
        echo ""
        echo "2. open PhotoCleaner.xcodeproj"
        echo "3. ビルド (⌘R)"
    fi
else
    echo "✓ LocalConfig.xcconfig は既に存在します"
fi
