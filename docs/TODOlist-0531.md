# TODO List - World Canon Project (2025-05-31)

要件定義書 (docs/README.md) と現在の実装状況を比較したTODOリストです。

## 🚀 優先度: 高

### 1. コントラクトのデプロイメント準備
- [ ] **Foundryのoptimizer設定を調整**
  - 現在: optimizer runs = 1,000,000 (ガス効率重視)
  - 要件: バイナリサイズ削減のための設定変更が必要
  - `foundry.toml`でoptimizer runsを200-800程度に調整

- [ ] **デプロイスクリプトの完成**
  - [ ] Base testnetへのデプロイスクリプト作成
  - [ ] Base mainnetへのデプロイスクリプト作成
  - [ ] 環境変数の設定ドキュメント作成

### 2. LLMデータ生成・取り込み機能
- [ ] **LLMプロンプト実行スクリプトの作成**
  - [ ] Step 1: 1,000件のSubject名取得スクリプト
  - [ ] Step 2: 各SubjectのImprint生成スクリプト
  - [ ] ChatGPT-4o用のAPI統合
  - [ ] Claude-3.7用のAPI統合

- [ ] **データ管理ディレクトリ構造の実装**
  ```
  data/
  ├── chatgpt4o/
  │   ├── subjects.json
  │   └── imprints/
  └── claude3.7/
      ├── subjects.json
      └── imprints/
  ```

### 3. SeaDrop設定とミント機能
- [ ] **SeaDropコントラクトとの統合設定**
  - [ ] PublicDrop設定の実装
  - [ ] AllowList設定の実装（必要に応じて）
  - [ ] ミント価格・期間の設定

## 📋 優先度: 中

### 4. 関数のNatSpecドキュメンテーション
- [ ] Subject.solの全external関数にNatSpec追加
- [ ] Imprint.solの全external関数にNatSpec追加
- [ ] インターフェースファイルのドキュメント整備

### 5. テストカバレッジの向上
- [ ] **エッジケーステスト**
  - [ ] 最大文字数(280文字)境界テスト
  - [ ] Unicode正規化の包括的テスト
  - [ ] 重複Subjectの検出テスト

- [ ] **ガスプロファイリング**
  - [ ] 大量ミント時のガス計測
  - [ ] SSTORE2読み書きのガス最適化検証

### 6. 管理機能の実装
- [ ] **Withdrawable機能の実装**
  - [ ] ETH引き出し機能
  - [ ] ERC20トークン引き出し機能（誤送信対策）
  
- [ ] **Multisig移行準備**
  - [ ] Owner権限をMultisigに移行するドキュメント
  - [ ] 緊急時のPause/Unpause権限設計

## 🔍 優先度: 低

### 7. Subgraph開発（Optional）
- [ ] **スキーマ定義**
  - [ ] Subject, EditionHeader, Imprintエンティティ
  - [ ] イベントマッピング

- [ ] **デプロイメント**
  - [ ] The Graph Hosted Serviceへのデプロイ手順
  - [ ] クエリ例のドキュメント化

### 8. フロントエンド（将来的な拡張）
- [ ] 読み取り専用UIの設計書
- [ ] OpenSea等マーケットプレイスでの表示確認

### 9. ドキュメント整備
- [ ] **コマンドリファレンス** (docs/README.md section 7)
  - [ ] ビルドコマンド一覧
  - [ ] テストコマンド一覧
  - [ ] デプロイコマンド一覧

- [ ] **アーキテクチャ図**
  - [ ] コントラクト間の関係図
  - [ ] データフロー図

## ✅ 完了済み

### コアコントラクト実装
- [x] Subject.sol (ERC721)
  - [x] mintInitial() - 初期1,000枚一括ミント
  - [x] addSubjects() - 追加Subject登録
  - [x] setLatest() - 最新Imprint ID更新
  - [x] 名前の正規化・重複チェック機能
  - [x] プレースホルダーSVG生成

- [x] Imprint.sol (ERC721A + SeaDrop)
  - [x] Upgradeable実装
  - [x] EditionHeader管理
  - [x] Seed事前登録システム
  - [x] SSTORE2によるdescription保存
  - [x] SVG動的生成（ImprintDescriptor経由）
  - [x] Subject連携（自動sync）

### サポート機能
- [x] LibNormalize.sol - 文字列正規化ライブラリ
- [x] ImprintDescriptor.sol - SVGテンプレート管理
- [x] ImprintViews.sol - ガス効率的なview関数
- [x] アップグレード可能な設計（TransparentProxy）

### テスト
- [x] Subject.t.sol - Subjectコントラクトの単体テスト
- [x] Imprint.t.sol - Imprintコントラクトの単体テスト
- [x] アップグレードテスト
- [x] Subject-Imprint統合テスト

## 📝 備考

- 現在の実装は要件定義のコア機能をほぼカバーしている
- 主な残作業は、デプロイメント準備とLLMデータ取り込み機能
- SeaDrop統合は基本実装済みだが、具体的なDrop設定が必要
- ガス最適化とバイナリサイズのトレードオフを検討する必要あり