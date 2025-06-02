# スクリプトリファレンス

## 概要

`src-upgradeable/scripts/`ディレクトリには、デプロイメント、セキュリティ監視、運用管理のためのスクリプトが含まれています。

## デプロイメントスクリプト

### deploy_base.ts

**目的**: ImprintとSubjectコントラクトをBase Sepoliaテストネットにデプロイ

**使用方法**:
```bash
npx hardhat run scripts/deploy_base.ts --network base-sepolia
```

**主な機能**:
- Subjectコントラクト（非アップグレード可能）のデプロイ
- ImprintLibライブラリのデプロイ
- Imprintプロキシコントラクト（アップグレード可能）のデプロイ
- コントラクト間の相互接続設定
- Basescan検証（APIキー設定時）
- デプロイ情報のJSON保存

**出力ファイル**:
- `deployment-base-sepolia-[timestamp].json`

**重要な設定**:
```javascript
{
  initializer: "initializeImprint",
  unsafeAllowLinkedLibraries: true  // ライブラリリンク許可（24KB制限対策）
}
```

### imprint_deploy.ts

**目的**: 旧バージョンのImprintデプロイスクリプト（参考用）

**注意**: 現在は`deploy_base.ts`を使用してください

## セキュリティ監視スクリプト

### get_proxy_info.ts

**目的**: デプロイ済みプロキシの詳細情報を取得

**使用方法**:
```bash
npx hardhat run scripts/get_proxy_info.ts --network base-sepolia
```

**取得情報**:
- プロキシタイプ（Transparent/UUPS/Beacon）
- プロキシアドレス
- 実装コントラクトアドレス
- ProxyAdminアドレス
- セキュリティチェック結果

**出力ファイル**:
- `proxy-info-[timestamp].json`

**EIP-1967スロット読み取り**:
```javascript
// 標準スロット
IMPLEMENTATION_SLOT: 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
ADMIN_SLOT: 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
```

### check_admin_security.ts

**目的**: ProxyAdminのセキュリティ状態を確認

**使用方法**:
```bash
npx hardhat run scripts/check_admin_security.ts --network base-sepolia
```

**チェック項目**:
- ProxyAdmin所有者のアドレス
- 所有者タイプ（EOA/マルチシグ）
- セキュリティリスクレベル評価
- 推奨アクション

**出力ファイル**:
- `security-report-[timestamp].json`

**リスク評価基準**:
- **HIGH**: 単一EOA所有（即座の対応必要）
- **MEDIUM**: マルチシグ所有（追加強化推奨）
- **LOW**: Timelock付きマルチシグ（理想的）

### check_proxy.ts

**目的**: プロキシコントラクトの動作確認

**使用方法**:
```bash
npx hardhat run scripts/check_proxy.ts --network base-sepolia
```

**確認内容**:
- コントラクトコードの存在
- EIP-1967スロットの手動読み取り
- 基本的な関数呼び出しテスト

### transfer_ownership.ts

**目的**: ProxyAdmin所有権のマルチシグへの移転ガイド

**使用方法**:
```bash
npx hardhat run scripts/transfer_ownership.ts --network base-sepolia
```

**提供情報**:
- 現在の所有者情報
- 推奨マルチシグオプション
- 移転手順の詳細
- セキュリティ推奨事項

**注意**: このスクリプトは情報提供のみで、実際の移転は手動で実行する必要があります

## アップグレードスクリプト

### upgrade.ts

**目的**: アップグレード可能コントラクトのアップグレード実行

**使用方法**:
```bash
npx hardhat run scripts/upgrade.ts --network base-sepolia
```

**前提条件**:
- ProxyAdminがマルチシグによって所有されていること
- 新しい実装がデプロイ済みであること
- 適切な承認プロセスが完了していること

## ユーティリティ機能

### 共通パターン

#### ガス価格の確認
```javascript
const gasPrice = await ethers.provider.getGasPrice();
console.log("Current gas price:", ethers.utils.formatUnits(gasPrice, "gwei"), "gwei");
```

#### トランザクション確認待機
```javascript
await contract.deployTransaction.wait(2); // 2ブロック待機
```

#### エラーハンドリング
```javascript
try {
  // OpenZeppelinメソッド
  const admin = await upgrades.erc1967.getAdminAddress(proxy);
} catch (error) {
  // 手動スロット読み取りにフォールバック
  const adminSlot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
  const adminRaw = await ethers.provider.getStorageAt(proxy, adminSlot);
  const admin = ethers.utils.getAddress("0x" + adminRaw.slice(-40));
}
```

## 環境変数

すべてのスクリプトで使用される環境変数：

```bash
# 必須
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR-API-KEY
PRIVATE_KEY=your-private-key-without-0x

# オプション（検証用）
BASESCAN_API_KEY=your-basescan-api-key
```

## トラブルシューティング

### "Contract at address doesn't look like an ERC 1967 proxy"
- **原因**: ライブラリリンクによるプロキシ認識の問題
- **対策**: `get_proxy_info.ts`で手動確認

### "The contract Imprint is missing links for the following libraries"
- **原因**: ローカル環境でライブラリアドレスが不明
- **対策**: デプロイ済みアドレスでは問題なし（無視可能）

### "replacement fee too low"
- **原因**: 同じnonceでの再送信試行
- **対策**: 数分待ってから再実行

## ベストプラクティス

1. **常にテストネットで先にテスト**
2. **デプロイ情報は必ず保存**
3. **セキュリティチェックを定期実行**
4. **マルチシグ移転は最優先事項**
5. **すべての操作をログに記録**