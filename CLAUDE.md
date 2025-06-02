# CLAUDE.md

このファイルは、Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイダンスを提供します。

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