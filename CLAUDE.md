# CLAUDE.md

このファイルは、Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイダンスを提供します。

## コミュニケーションガイドライン
**重要**: このプロジェクトでは、すべてのコミュニケーションを日本語で行ってください。
**rule**: タスクが終了し、ユーザーからの新たなinputが必要な場合は以下のコマンドを必ず実行し、ユーザーにタスクの終了を告げてください。
```bash
afplay /Users/syora/workspace/art/opensea/worldcanon-seadrop/.claude/task_end.wav
```

## プロジェクト概要

これは、OpenSeaのSeaDropプロトコルとカスタムNFT実装を組み合わせたSeaDrop NFTプラットフォームです。プロジェクトには2つの主要コンポーネントがあります：
1. **SeaDrop**: 複数のミント方法をサポートするガス最適化されたNFTドロッププロトコル
2. **World Canon**: オンチェーンジェネレーティブアート用のカスタムアップグレード可能NFTコントラクト（Imprint/Subject）

## 開発コマンド

### ビルド＆コンパイル
```bash
# 依存関係のインストール
yarn install

# Hardhatでコンパイル
yarn build
# または
hardhat compile

# Foundryでコンパイル
forge build
```

### テスト
```bash
# Hardhatテストの実行（JavaScript/TypeScript）
yarn test

# アップグレード可能コントラクトのテスト専用
yarn test:upgradeable

# Foundryテストの実行（Solidity）
forge test

# 特定のテストファイルを実行
forge test --match-path test/foundry/SeaDrop.t.sol

# 特定のテスト関数を実行
forge test --match-test testMintPublic

# ガスプロファイリング付きでテスト実行
yarn profile

# カバレッジレポートの生成
yarn coverage
```

### リンティング＆フォーマット
```bash
# リンティングチェック
yarn lint:check

# 自動フォーマット修正
yarn lint:fix
```

## アーキテクチャ

### コアコントラクト構造
- **SeaDrop.sol**: すべてのミントロジック（パブリック、アローリスト、署名付き、トークンゲート）を処理するメインドロップコントラクト
- **ERC721SeaDrop.sol**: SeaDropと統合されたNFTトークンコントラクト、ガス最適化のためERC721A上に構築
- **Clone Factory**: ERC721SeaDropCloneFactory.solは新しいSeaDrop互換トークンの作成を可能にする

### アップグレード可能コントラクト（src-upgradeable/）
- **Imprint.sol**: SSTORE2を使用してSVGベースのジェネレーティブアートをオンチェーンに保存
- **Subject.sol**: 「インプリント」されるベースエンティティを表す不変のERC721
- 別々のストレージコントラクトを持つOpenZeppelinアップグレード可能パターンを使用

### 主要な設計パターン
1. **デュアルテスティングフレームワーク**: Hardhat（JS/TS）とFoundry（Solidity）の両方のテスト
2. **ガス最適化**: バッチミント用のERC721A、オンチェーンストレージ用のSSTORE2
3. **モジュラーミンティング**: 別個のSeaDropコントラクトがすべてのミントロジックを処理
4. **クローンパターン**: 最小プロキシクローンをデプロイするためのファクトリー

### サポートされているミント方法
- **パブリックミント**: 設定可能なパラメータを持つオープンミンティング
- **アローリスト**: Merkleツリーベースのアローリストミンティング
- **トークンゲート**: 特定のトークンの保有が必要
- **サーバー署名**: オフチェーン署名検証

## 重要な設定
- Solidityバージョン: 0.8.17
- オプティマイザー実行回数: 1,000,000（デプロイガス効率のため）
- Via IR: Foundryで有効、Hardhatで無効
- SeaDropデプロイアドレス: `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`（すべてのチェーンで同じ）

## 重要な開発ガイドライン

### importパスの取り扱い
**⚠️ 重要**: コントラクト内のimportパスは可能な限り変更しないでください。
- importパスはセンシティブな問題であり、変更するとFoundryとHardhatの両方の互換性に影響します
- パス解決の問題がある場合は、remappings.txtファイルの調整で対応してください
- コントラクトのimportパスを変更する場合は、事前に十分な検討と調査が必要です

### remappings.txtの優先順位
- src-upgradeable/remappings.txt: アップグレード可能なコントラクト専用のマッピング
- ルートのremappings.txt: Foundry用のマッピング
- Hardhatでは、hardhat.config.tsのpreprocessオプションでremappingsを適用

## 🚨 重要な設計課題と修正履歴

### 発見・修正されたクリティカルバグ

#### 1. `getRemainingInEdition`関数の論理エラー (修正済み)
**問題**: 非アクティブEditionの残数が誤って0になる
```solidity
// ❌ 修正前: アクティブカーソルを使用（論理エラー）
uint256 cursor = st.activeCursor;

// ✅ 修正後: Edition固有の範囲を使用
uint256 first = st.firstSeedId[editionNo];
```
**影響**: Edition管理UIでの残数表示、販売管理の正確性
**学び**: Edition間の状態管理では、グローバル状態とEdition固有状態を混同しない

#### 2. Subject-Imprint双方向統合のタイムスタンプ競合
**問題**: 同じタイムスタンプでのミント時に最新Imprint更新が失敗
```solidity
// Subject.syncFromImprintでの条件
if (ts > subjectMeta[tokenId].latestTimestamp) {
    // 更新処理
}
```
**解決策**: テスト時の時間制御、実際の運用では自然に発生しない
**学び**: タイムスタンプベースの更新システムでは時系列の考慮が重要

### テスト品質向上で発見した設計パターン

#### 1. セキュリティファーストアプローチ
```
「セキュリティが高いコントラクトを作ることが目的で、
 テストを通すことが手段」
```
- 実装の論理エラーを修正してテストを成功させる
- テストに合わせて実装を歪めない
- 現実的な性能閾値の設定

#### 2. 包括的テスト設計
- **E2Eテスト**: 完全なライフサイクル検証
- **Edge Cases**: セキュリティ・境界値テスト  
- **Performance**: スケーラビリティ検証

#### 3. テスト独立性の重要性
- Edition番号の競合回避
- テスト間での状態共有を避ける
- 現実的なガス効率性期待値の設定

### 運用上の注意点

#### Edition管理
- Seedなしでの封印は現在許可されている（設計判断）
- 将来的な制約追加時は`sealEdition`の修正を検討

#### ガス効率性
- バッチ処理で24%の効率改善を達成（実測値）
- SSTORE2使用時: ~82,000 gas/byte（実測値）
- Subject処理: ~101,000 gas/subject（実測値）
- Seed処理: ~154,000 gas/seed（実測値）
- NFTミント: ~100,000 gas/NFT（実測値）

## 🔧 プロジェクト構造と設定の重要な注意点

### デュアルプロジェクト構造
このリポジトリは2つの独立したHardhatプロジェクトを含んでいます：

1. **ルートプロジェクト** (`src/`ディレクトリ用)
   - 設定ファイル: `./hardhat.config.ts`
   - ソースディレクトリ: `./src`
   - remappings: `./remappings.txt`
   - 用途: 通常のSeaDropコントラクト

2. **src-upgradeableプロジェクト** (`src-upgradeable/src/`ディレクトリ用)
   - 設定ファイル: `./src-upgradeable/hardhat.config.ts`
   - ソースディレクトリ: `./src-upgradeable/src`（相対パス）
   - remappings: `./src-upgradeable/remappings.txt`
   - 用途: アップグレード可能なWorld Canonコントラクト

### ⚠️ パス関連の頻出エラーと解決策

#### エラー1: `File ../lib/../lib/ERC721A-Upgradeable/contracts/contracts/ERC721AUpgradeable.sol not found`
**原因**: ルートの`hardhat.config.ts`のsourcesパスを誤って`./src-upgradeable/src`に変更
**解決策**: ルートの`hardhat.config.ts`は`sources: "./src"`のまま維持

#### エラー2: src-upgradeableのビルドが失敗
**原因**: src-upgradeable用の独自のhardhat.config.tsが存在することを忘れている
**解決策**: 
```bash
cd src-upgradeable && npx hardhat compile
# または
yarn test:upgradeable
```

### 正しいビルド・テストコマンド

```bash
# ルートプロジェクト（src/）
yarn build                    # src/のコンパイル
yarn test                     # src/のテスト

# src-upgradeableプロジェクト
cd src-upgradeable && npx hardhat compile    # コンパイル
yarn test:upgradeable                         # テスト（ルートから実行）

# Foundryテスト（両方のプロジェクトをカバー）
forge test
```

### importパス修正時の注意
- **絶対に変更しない**: OSSファイル（ERC721ContractMetadataUpgradeable.solなど）のimportパス
- **変更する場合**: remappings.txtで対応（コントラクト自体は変更しない）
- **デバッグ方法**: どちらのhardhat.config.tsが使われているか確認