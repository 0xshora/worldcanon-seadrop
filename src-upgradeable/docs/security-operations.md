# セキュリティ運用ガイド

## 概要

このドキュメントは、デプロイ済みコントラクトのセキュリティ管理と運用手順について説明します。

## 現在のセキュリティ状態

### ⚠️ 高リスク：単一キー所有

現在、ProxyAdminコントラクトは単一のEOA（Externally Owned Account）によって所有されています。これは以下のリスクを伴います：

- **秘密鍵漏洩リスク**: 一つの秘密鍵が漏洩すれば、コントラクト全体が乗っ取られる
- **運用ミスリスク**: 誤ったアップグレードによる資金ロック
- **単一障害点**: キー紛失でアップグレード不可能に

## 緊急対応手順

### Phase 1: 即座のリスク軽減（24時間以内）

#### 1. 秘密鍵の保護
```bash
# 現在の秘密鍵を安全な場所に移動
- ハードウェアウォレット（Ledger/Trezor）
- セキュアなKey Management Service
- 物理的に安全な場所での保管
```

#### 2. アップグレード凍結
```
⚠️ 重要：マルチシグ設定完了まで、一切のアップグレードを実行しない
```

#### 3. 現状の文書化
```bash
# プロキシ情報の取得と保存
npx hardhat run scripts/get_proxy_info.ts --network base-sepolia

# セキュリティ状態の記録
npx hardhat run scripts/check_admin_security.ts --network base-sepolia
```

### Phase 2: マルチシグへの移行（1週間以内）

#### 1. マルチシグウォレットの設定

**推奨オプション：**

a) **Gnosis Safe（推奨）**
```bash
# Base Sepoliaでの設定
1. https://app.safe.global にアクセス
2. Base Sepoliaネットワークを選択
3. 新しいSafeを作成
4. 署名者と閾値を設定（例：3/5マルチシグ）
```

b) **既存のマルチシグ使用**
```bash
# チームで既に使用しているマルチシグがある場合
# そのアドレスを使用
```

#### 2. 所有権の移転

```bash
# 移転手順の確認
npx hardhat run scripts/transfer_ownership.ts --network base-sepolia

# 実際の移転（現在の所有者の秘密鍵が必要）
# 1. マルチシグアドレスを確認
# 2. transferOwnership関数を実行
# 3. 新しい所有者を確認
```

#### 3. 移転の検証
```javascript
// 検証スクリプトの実行
const proxyAdmin = await ethers.getContractAt("ProxyAdmin", PROXY_ADMIN_ADDRESS);
const newOwner = await proxyAdmin.owner();
console.log("New owner:", newOwner); // マルチシグアドレスであることを確認
```

### Phase 3: ガバナンス強化（1ヶ月以内）

#### 1. TimelockControllerの導入
```solidity
// アップグレードに遅延を導入
// 例：48時間の遅延期間
TimelockController timelock = new TimelockController(
    48 hours,     // 最小遅延
    proposers,    // 提案者リスト
    executors,    // 実行者リスト
    admin         // 管理者
);
```

#### 2. アップグレード手順の文書化
- 提案プロセス
- レビュープロセス
- 承認基準
- 実行手順
- ロールバック計画

## セキュリティ監視スクリプト

### 1. プロキシ情報の定期確認
```bash
# プロキシの構成を確認
npx hardhat run scripts/get_proxy_info.ts --network base-sepolia

# 出力項目：
- プロキシアドレス
- 実装アドレス
- 管理者アドレス
- プロキシタイプ
```

### 2. 所有権状態の監視
```bash
# ProxyAdmin所有者の確認
npx hardhat run scripts/check_admin_security.ts --network base-sepolia

# 確認項目：
- 現在の所有者
- 所有者タイプ（EOA/コントラクト）
- セキュリティリスク評価
```

### 3. プロキシ動作確認
```bash
# プロキシ経由でのコントラクト呼び出しテスト
npx hardhat run scripts/check_proxy.ts --network base-sepolia
```

## アップグレード手順（マルチシグ設定後）

### 1. 新しい実装のデプロイ
```javascript
// 新しい実装コントラクトをデプロイ
const NewImprint = await ethers.getContractFactory("ImprintV2", {
  libraries: {
    ImprintLib: IMPRINT_LIB_ADDRESS
  }
});
const newImplementation = await NewImprint.deploy();
await newImplementation.deployed();
```

### 2. アップグレード提案
```javascript
// マルチシグでアップグレード提案を作成
// Gnosis Safeの場合：
// 1. Safe UIでトランザクションを作成
// 2. ProxyAdmin.upgrade(proxy, newImplementation)を呼び出し
// 3. 必要な署名を収集
```

### 3. アップグレード実行
```javascript
// 必要な署名が集まったら実行
// TimelockControllerがある場合は遅延期間後に実行
```

### 4. 検証
```javascript
// アップグレード後の確認
const proxy = await ethers.getContractAt("Imprint", PROXY_ADDRESS);
const version = await proxy.version(); // 新しいバージョンを確認
```

## 緊急時対応

### 秘密鍵漏洩の疑いがある場合
1. **即座にProxyAdminの所有権を新しいアドレスに移転**
2. **すべてのペンディングトランザクションを確認**
3. **コントラクトの状態を監査**

### 悪意のあるアップグレードが実行された場合
1. **影響範囲の特定**
2. **ユーザーへの通知**
3. **可能な場合はロールバック検討**
4. **法的措置の検討**

## ベストプラクティス

### 1. 定期的な監査
- 月次でセキュリティ状態を確認
- 四半期ごとに外部監査を検討

### 2. アクセス管理
- マルチシグの署名者リストを定期的にレビュー
- 不要になった署名者は削除
- 新しい署名者の追加は慎重に

### 3. 文書化
- すべての変更を記録
- アップグレード理由を明確に
- 決定プロセスを透明に

### 4. テスト
- 本番環境での実行前に必ずテストネットで検証
- アップグレードスクリプトの自動テスト
- ロールバック手順のテスト

## 連絡先とサポート

### 緊急連絡先
- セキュリティチーム: [連絡先を記入]
- 技術サポート: [連絡先を記入]
- 法務チーム: [連絡先を記入]

### 外部リソース
- OpenZeppelin Defender: https://defender.openzeppelin.com/
- Gnosis Safe: https://app.safe.global/
- Base Documentation: https://docs.base.org/