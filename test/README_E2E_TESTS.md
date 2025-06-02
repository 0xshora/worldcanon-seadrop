# 🧪 World Canon E2E & Performance Test Suite

## 📋 概要

このディレクトリには、World Canonプロジェクトの包括的なE2E（End-to-End）テストとパフォーマンステストが含まれています。従来の単体テストを補完し、実際のユーザーシナリオと大規模運用での動作を検証します。

## 🗂️ テストファイル構成

### 📊 E2Eテスト（End-to-End Tests）

#### 1. `WorldCanonE2E.t.sol` (Foundry/Solidity)
**完全ライフサイクルテスト**
- ✅ GPT-4oからClaude-3.7への時代遷移シミュレーション
- ✅ マルチユーザー同時ミント競争
- ✅ LLM出力からNFT可視化までの完全統合フロー
- ✅ Subject ↔ Imprint 動的連携の検証

#### 2. `WorldCanonE2E.spec.ts` (Hardhat/TypeScript)
**マーケットプレイス統合テスト**
- 🎨 OpenSea互換メタデータ検証
- 💰 収益分配と経済モデルテスト
- 🔄 時間経過による多世代AI進化シミュレーション
- 📱 ウォレット・マーケットプレイス表示確認

### ⚠️ エッジケース & セキュリティテスト

#### 3. `WorldCanonEdgeCases.t.sol`
**境界値とエラーハンドリング**
- 🔢 最大容量（1000件）でのEdition作成テスト
- 🎯 ミント制限（25枚）境界値テスト
- ⚠️ 不正操作に対するエラーハンドリング
- 🛡️ アクセス制御とセキュリティ脆弱性テスト
- 🔄 再入攻撃防止の検証
- 🔄 アップグレード時のデータ保持確認

### ⚡ パフォーマンス & スケーラビリティテスト

#### 4. `WorldCanonPerformance.t.sol`
**ガス効率性とスケーラビリティ**
- ⚡ バッチサイズ別ガス最適化テスト
- 💾 SSTORE2効率性 vs 従来ストレージ比較
- 🏗️ 大量Subject処理（1000件）ストレステスト
- 📚 複数Edition大量Seed処理テスト
- 🚀 高頻度同時ミントパフォーマンステスト

## 🚀 テスト実行方法

### 🔧 前提条件

```bash
# 依存関係のインストール
yarn install

# コントラクトのコンパイル
yarn build
forge build
```

### ⚡ クイック実行

```bash
# 全E2Eテストの実行
forge test --match-path "test/foundry/WorldCanon*.t.sol" -vv

# 特定テストスイートの実行
forge test --match-path "test/foundry/WorldCanonE2E.t.sol" -vv
forge test --match-path "test/foundry/WorldCanonEdgeCases.t.sol" -vv
forge test --match-path "test/foundry/WorldCanonPerformance.t.sol" -vv

# HardhatE2Eテストの実行
yarn test test/WorldCanonE2E.spec.ts
```

### 📊 詳細実行（ガス分析付き）

```bash
# ガスレポート付き実行
forge test --match-path "test/foundry/WorldCanonPerformance.t.sol" --gas-report -vv

# トレース付き実行（デバッグ用）
forge test --match-path "test/foundry/WorldCanonE2E.t.sol" -vvv

# 特定テスト関数の実行
forge test --match-test "testCompleteLifecycleGPT4oToClaude3" -vv
```

### 🔍 カバレッジ分析

```bash
# カバレッジレポートの生成
yarn coverage

# Foundryカバレッジ
forge coverage --report summary --report lcov
```

## 📈 テストシナリオ詳細

### 🌍 Complete Lifecycle Scenario
```
Phase 1: Subject初期セットアップ (50件のテスト用Subject)
         ↓
Phase 2: GPT-4o Edition作成・封印・アクティブ化
         ↓  
Phase 3: パブリックミント（collector1が5枚購入）
         ↓
Phase 4: Subject.tokenURI動的更新確認
         ↓
Phase 5: Claude-3.7 Edition作成
         ↓
Phase 6: 時代遷移ミント（collector2が3枚購入）
         ↓
Phase 7: 時代遷移完全性検証
```

### 🏁 Multi-User Concurrent Scenario
```
Setup: GPT-4o Edition (50 Seeds)
       ↓
User1: 25枚ミント（制限まで）
User2: 25枚ミント（完売）
User3: 1枚ミント試行 → SoldOut Error
```

### 💰 Revenue Distribution Scenario
```
Setup: 0.1 ETH/NFT, 5% Fee
       ↓
Mint: 3 NFTs = 0.3 ETH total
      ↓
Distribution: 
- Fee: 0.015 ETH
- Creator: 0.285 ETH
```

## 🎯 パフォーマンス指標

### ⚡ ガス効率性目標

| 操作 | 目標ガス使用量 | 実測値 |
|------|----------------|--------|
| Subject mint (1件) | < 100,000 gas | ✅ |
| Imprint mint (1件) | < 150,000 gas | ✅ |
| Seed追加 (バッチ100件) | < 5,000,000 gas | ✅ |
| Edition作成 | < 200,000 gas | ✅ |

### 📊 スケーラビリティ目標

| 規模 | 処理時間 | 成功基準 |
|------|----------|----------|
| Subject 1000件処理 | < 10分 | ✅ |
| Edition 5個 × Seeds 200件 | < 15分 | ✅ |
| 同時ミント 75NFT | < 2分 | ✅ |

## 🐛 デバッグとトラブルシューティング

### ⚠️ よくある問題

1. **ガス制限エラー**
   ```bash
   # より高いガス制限で実行
   forge test --gas-limit 30000000 --match-path "test/foundry/WorldCanonPerformance.t.sol"
   ```

2. **メモリ不足エラー**
   ```bash
   # バッチサイズを小さくしてテスト
   # コード内のbatchSizeを調整
   ```

3. **プロキシ関連エラー**
   ```bash
   # プロキシの状態をリセット
   forge test --match-test "testUpgradeDataPersistence" --fork-url $FORK_URL
   ```

### 🔍 ログ分析

```bash
# 詳細ログ付き実行
forge test --match-path "test/foundry/WorldCanonE2E.t.sol" -vvvv | tee test_output.log

# ガス使用量の抽出
grep "Gas:" test_output.log
```

## 📚 関連ドキュメント

- [📋 要件定義](../docs/README.md)
- [🏗️ アーキテクチャガイド](../docs/SeaDropDeployment.md)
- [🔧 デプロイガイド](../src-upgradeable/docs/deployment-guide.md)
- [🛡️ セキュリティ仕様](../src-upgradeable/docs/security-operations.md)

## 🤝 コントリビューション

新しいテストシナリオの追加やパフォーマンス改善の提案は、以下の手順で行ってください：

1. **新しいテストファイル作成時**
   ```bash
   # ブランチ作成
   git checkout -b feature/new-test-scenario
   
   # テスト作成
   # test/foundry/NewScenario.t.sol
   
   # テスト実行・検証
   forge test --match-path "test/foundry/NewScenario.t.sol" -vv
   ```

2. **既存テスト拡張時**
   - 該当テストファイルに新しい関数を追加
   - コメントでテスト内容を明確化
   - パフォーマンス指標の更新

3. **プルリクエスト作成時**
   - テストカバレッジの確認
   - ガス使用量の分析結果を添付
   - 新機能の動作確認レポート

---

🌟 **World Canon E2E Test Suite** は、分散型AIアートプラットフォームの品質と信頼性を保証する重要なコンポーネントです。定期的な実行と継続的な改善により、ユーザーエクスペリエンスの向上を支援します。