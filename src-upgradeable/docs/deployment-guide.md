# デプロイメントガイド

## 概要

このドキュメントは、World Canon（Imprint/Subject）コントラクトのBase Sepoliaテストネットへのデプロイ手順と、デプロイ後の運用管理について説明します。

## 前提条件

### 必要な環境
- Node.js 18.18.2以上
- Hardhat
- 必要な環境変数（`.env`ファイル）
  - `BASE_SEPOLIA_RPC_URL`: Base Sepolia RPCエンドポイント
  - `PRIVATE_KEY`: デプロイヤーの秘密鍵
  - `BASESCAN_API_KEY`: Basescan検証用APIキー（オプション）

### コントラクト構成
- **Subject**: 不変のERC721コントラクト（非アップグレード可能）
- **Imprint**: アップグレード可能なERC721SeaDropコントラクト（Transparentプロキシ）
- **ImprintLib**: Imprintコントラクト用のライブラリ

## デプロイ手順

### 1. 環境設定
```bash
# src-upgradeableディレクトリに移動
cd src-upgradeable

# 環境変数の設定
cp ../.env.example ../.env
# .envファイルを編集して実際の値を設定
```

### 2. コンパイル
```bash
npx hardhat compile
```

### 3. デプロイ実行
```bash
npx hardhat run scripts/deploy_base.ts --network base-sepolia
```

### 4. デプロイスクリプトの動作

#### 実行される処理：
1. **Subject コントラクトのデプロイ**
   - 通常のコントラクトとして直接デプロイ
   - トランザクション確認待機（2ブロック）

2. **ImprintLib ライブラリのデプロイ**
   - 現在のガス価格表示
   - ライブラリコントラクトのデプロイ
   - トランザクション確認待機（2ブロック）

3. **Imprint プロキシコントラクトのデプロイ**
   - OpenZeppelin Transparentプロキシパターン使用
   - ライブラリリンク（`unsafeAllowLinkedLibraries: true`）
   - 初期化関数：`initializeImprint`

4. **プロキシアドレスの取得**
   - OpenZeppelinメソッドを試行
   - 失敗時は手動でEIP-1967スロット読み取り

5. **コントラクト間の接続設定**
   - Subject.setImprintContract()
   - Imprint.setWorldCanon()

6. **Basescan検証**（APIキー設定時のみ）
   - Subjectコントラクトの検証
   - Imprint実装コントラクトの検証

## デプロイ後の確認

### 1. プロキシ情報の確認
```bash
npx hardhat run scripts/get_proxy_info.ts --network base-sepolia
```

出力される情報：
- プロキシタイプ（TransparentUpgradeableProxy）
- プロキシアドレス
- 実装コントラクトアドレス
- ProxyAdminアドレス

### 2. セキュリティ状態の確認
```bash
npx hardhat run scripts/check_admin_security.ts --network base-sepolia
```

確認項目：
- ProxyAdmin所有者
- 所有者タイプ（EOA/マルチシグ）
- セキュリティリスク評価

### 3. プロキシ動作確認
```bash
npx hardhat run scripts/check_proxy.ts --network base-sepolia
```

## 重要な注意事項

### ライブラリリンクについて
- **理由**: コントラクトサイズが24KB制限を超過（27KB）
- **対策**: `unsafeAllowLinkedLibraries: true`フラグを使用
- **リスク**: アップグレード時に手動でライブラリ互換性確認が必要

### セキュリティ考慮事項
1. **ProxyAdmin所有権**
   - デプロイ直後は単一のEOAが所有（高リスク）
   - 速やかにマルチシグウォレットへ移転すべき

2. **アップグレード管理**
   - マルチシグ設定前のアップグレードは禁止
   - アップグレード手順の文書化必須
   - テストネットでの事前検証必須

## トラブルシューティング

### プロキシアドレス取得エラー
- **症状**: "Error retrieving admin/implementation address"
- **原因**: ネットワーク遅延またはRPC制限
- **対策**: `get_proxy_info.ts`スクリプトで手動確認

### Basescan検証エラー
- **症状**: "You are trying to verify a contract in 'base-sepolia', but no API token was found"
- **原因**: BASESCAN_API_KEYが未設定
- **対策**: 
  1. https://basescan.org/apis でAPIキー取得
  2. `.env`ファイルに設定

### デプロイ情報の保存
- デプロイ情報は`deployment-base-sepolia-[timestamp].json`に自動保存
- プロキシ情報は`proxy-info-[timestamp].json`に保存
- セキュリティレポートは`security-report-[timestamp].json`に保存

## 次のステップ

1. **セキュリティ強化**
   - ProxyAdminをマルチシグに移転（`transfer_ownership.ts`参照）
   - ガバナンス構造の確立

2. **運用準備**
   - アップグレード手順の文書化
   - 緊急時対応手順の策定
   - モニタリング体制の構築

3. **本番環境への移行**
   - Base Mainnet用の設定追加
   - より厳格なセキュリティ要件の適用