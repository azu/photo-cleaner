#!/bin/bash
# Photo Cleaner セットアップスクリプト

echo "Photo Cleaner セットアップ"
echo "=========================="

# LocalConfig.xcconfig を作成
if [ ! -f "LocalConfig.xcconfig" ]; then
    cp LocalConfig.xcconfig.template LocalConfig.xcconfig
    echo "✓ LocalConfig.xcconfig を作成しました"
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
else
    echo "✓ LocalConfig.xcconfig は既に存在します"
fi
