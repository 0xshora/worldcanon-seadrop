# World Canon

**README / 要件定義書**

---

## 0. 目的

- 現在世界を **多視点で記録** するオンチェーン・クロニクルを構築する。  
  _Subject_（＝対象語）は不変 ID として鋳造し、複数の _Imprint_ NFT が「LLM（ChatGPT-4o、Claude-3.7 など）がその Subject をどのように描写したか」を時系列で記録する。

### 構成

- **シリーズ名** : **World Canon**
- **Subject**(ERC-721): … 概念・語・フレーズなどの〈題材〉。不変なIDを持つ。
- **Imprint**(ERC-721A) : 各LLMが世界を表現するために1000個のsubjectを選び、それらについての痕跡の記録。

### 各NFTのtitle例

- **Subject** : "#42 - Happiness"
- **Imprint** : "#058 – Happiness (ChatGPT-4o, 2025-05-05)"

Imprint の日付フォーマットは ISO-8601（YYYY-MM-DD）で統一する。

### LLMへのプロンプト(WIP)

各エディションの作成時には、以下のプロンプトを各モデルに与えることによって、出力を得る。

#### Step 1: Subjectの選択

LLMには、次のプロンプトを与えることにより、1,000件のSubject名を取得する。

```
You are the designated chronicler of the present world.
To help future intelligences grasp our world in all its facts and values, select 1,000 representative subjects spanning the tangible and the intangible.
For each subject, write a description no longer than 280 characters.

First, output only the 1,000 subject names (any order, no duplicates).
```

#### Step 2: Imprintの生成

LLMに次のプロンプトを与えることにより、各SubjectについてのImprintを生成する。

```
You are the designated chronicler of the present world.
To help future intelligences grasp our world in all its facts and values, select 1,000 representative subjects spanning the tangible and the intangible.

Describe the selected subject in no more than 280 characters: {subject}.
```

#### 注意：Normalization & Duplicate Guard

Edition 取り込み時は次の **Normalization フロー** を順番に適用し、正規化後の文字列で重複判定を行う。

| #   | ステップ         | 処理内容                                          |
| --- | ---------------- | ------------------------------------------------- |
| 1   | **Unicode NFKC** | 全角↔半角など互換文字を正規化                    |
| 2   | **小文字化**     | `toLowerCase()`                                   |
| 3   | **前後空白削除** | `trim()`                                          |
| 4   | **内部空白整形** | 連続スペース → 1 つに縮約（`/\\s+/g` → " ")       |
| 5   | **禁止記号除去** | 絵文字・制御文字など SVG 生成を阻害する文字を除外 |

---

## 1. 機能概要

| レイヤー          | トークン   | 規格         | 役割                      | 変更可否          | 譲渡可否 |
| ----------------- | ---------- | ------------ | ------------------------- | ----------------- | -------- |
| **Subject**       | 概念カード | **ERC-721**  | 初期 1,000 枚＋追加可     | 名前固定・ID 不変 | **可**   |
| **Imprint**       | 時代痕跡   | **ERC-721A** | _SUBJECT × モデル × 番号_ | ミント後不変      | **可**   |

- **視点レイヤー方式**: モデルごとに IMPRINT ストリームを生成
- **オンチェーン・オールイン**: IPFS を用いず、説明文・SVG を完全オンチェーン格納
- **SVG** テンプレートはコントラクト内 `library` に固定し、  
  可変部分（text / model / date）だけを `bytes` 連結してガス圧縮

---

## 2. ユーザーストーリー

| 役割                        | 目的                     | 主要アクション                               |
| --------------------------- | ------------------------ | -------------------------------------------- |
| **キュレーター（=運営者）** | 概念とテキスト品質を統制 | `createImprintSeed()` / 直接 `mintImprint()` |
| **コレクター**              | 時代の痕跡を所有・転売   | `claimImprint()` または 2次市場購入          |
| **研究者**                  | LLM 言語変遷を解析       | Subgraph から CSV/JSON Export                |

---

## 3. スマートコントラクト仕様（SeaDrop & SSTORE2 対応版）

### 3.1 Subject.sol `ERC721`

| フィールド         | 型        | 説明                           |
| ------------------ | --------- | ------------------------------ |
| `name`             | `string`  | 概念名                         |
| `tokenId`          | `uint256` | Subject ID                     |
| `latestImprintId`  | `uint256` | 現行 IMPRINT ポインタ          |
| `added_edition_no` | `uint256` | Subjectが追加されたEdition番号 |

```solidity
function mintInitial(string[] calldata names) external onlyOwner;          // 1000 枚一括
function addSubjects(
    string[] calldata names,
    uint64   editionNo
) external onlyOwner;   // 将来的にはmultisigに移行.
function setLatest(uint256 tokenId,uint256 imprintId) external onlyOwner;// 自動更新

/// ────────── 内部構造 ──────────
struct SubjectMeta {
    uint64  addedEditionNo;
    uint256 latestImprintId;
}

mapping(uint256 => SubjectMeta) public subjectMeta; // tokenId -> SubjectMeta
```

### 3.2 Imprint.sol `SeaDropERC721A`

- 継承: SeaDropERC721A（OpenSea 公式）
- 1 アドレスあたり Mint 上限: 25 (maxTotalMintableByAddress = 25)
- データ本体: SSTORE2 で保存し、ポインタを構造体に保持

#### ストレージ構造

```solidity
/// ────────── EditionHeader ──────────
struct EditionHeader {
    uint256 editionNo;        // グローバル通番
    string  model;            // 例 "GPT-4o"
    uint64  timestamp;        // 一括生成時のtimestamp Dateに変更？
    bool    sealed;           // 追加禁止フラグ
}
mapping(uint256 => EditionHeader) public editionHeaders;

/// ────────── Imprint NFT (ページ) ──────────
struct ImprintInfo {
    uint256 editionNo;        // 紐づくヘッダ
    uint256 subjectId;        // Subject の tokenId (= Subject ID)
    string  subjectName;      // Subjectの名前
    uint32  localIndex;       // Edition内のlocalindex
    address descPtr;          // SSTORE2 ポインタ（description）
}
mapping(uint256 => ImprintInfo) public imprintInfo;
```

```solidity
// ────────── コントラクトデプロイ時に実行 ──────────
bytes constant SVG_PREFIX = abi.encodePacked(
    '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350">',
    '<rect width="100%" height="100%" fill="black"/>',
    '<foreignObject x="10" y="10" width="330" height="330">',
    '<div xmlns="http://www.w3.org/1999/xhtml" ',
    'style="color:white;font:20px/1.4 \'Courier New\',monospace;',
    'overflow-wrap:anywhere;">'
);
bytes constant SVG_SUFFIX = '</div></foreignObject></svg>';

address constant SVG_PREFIX_PTR = SSTORE2.write(SVG_PREFIX);
address constant SVG_SUFFIX_PTR = SSTORE2.write(SVG_SUFFIX);

// ────────── ImprintSeed 登録 (既存ロジック) ──────────
function createImprintSeed(
    uint256 editionNo,
    uint256 subjectId,
    string  calldata subjectName,
    bytes   calldata description,      // 最大 280 UTF-8 bytes
) external onlyOwner {
    address descPtr = SSTORE2.write(description);   // description だけ保存
    seeds[nextSeedId++] = ImprintSeed({
        editionNo:  editionNo,
        subjectId:  subjectId,
        subjectName: subjectName,
        descPtr:    descPtr,
        claimed:    false
    });
}

// ────────── SVG 動的生成 ──────────
function _buildSVG(address descPtr) internal view returns (string memory) {
    bytes memory prefix = SSTORE2.read(SVG_PREFIX_PTR);
    bytes memory body   = SSTORE2.read(descPtr);      // LLM 出力
    bytes memory suffix = SSTORE2.read(SVG_SUFFIX_PTR);
    return string(abi.encodePacked(prefix, body, suffix));
}

// tokenURI 内で呼び出し
function tokenURI(uint256 id) public view override returns (string memory) {
    ImprintInfo memory im = imprintInfo[id];
    EditionHeader memory eh = editionHeaders[im.editionNo];

    string memory svg = _buildSVG(im.descPtr);

    return _buildJson(eh.model, eh.timestamp, im.subjectName, svg);
}

// パブリックMint
function mintPublic(address minter,uint256 quantity)
    external
    payable
    override
    seaDropOnly
```

### 3.4 アップグレード設計

- Subject: 非アップグレード（immutable）
- Imprint: UUPS Proxy
  - upgradeAuthority = TimeLock(48h)
  - storage gap 50 slots 予約
  - `onlyProxy` modifier を公開 upgrade 関数に付与

### 3.5 SubjectへのImrpintからの反映.

`Subject.sol` の **`tokenURI(uint256 tokenId)`** では、内部  
`subjectMeta[tokenId].latestImprintId` を取得し、下記の手順で `image` フィールドを組み立てる。

1. **最新 Imprint ID を取得**  

```solidity
uint256 latest = subjectMeta[tokenId].latestImprintId;
```

2. Imprint コントラクトから純粋 SVG Data-URI を取得
```solidity
string memory imageURI = latest == 0
    ? _placeholderSVG(subjectNames[tokenId])          // 初期表示用
    : Imprint(imprintAddr).tokenImage(latest);     // ← ここで取得
```

3. JSON メタデータに image としてセット
```solidity
return Metadata.encode({
    name: subjectNames[tokenId],
    attributes: [
      { "trait_type":"Token ID", "value": tokenId },
      { "trait_type":"Latest Imprint ID", "value": latest }
    ],
    image: imageURI                                    // ← 画像がここに入る
});
```


`tokenImage()` は Imprint 側で
`data:image/svg+xml;base64,…` 形式の 完全な SVG を返すため、
Marketplace や Wallet は Subject トークンだけを読み込むだけで
最新 Imprint のビジュアルを自動表示 できる。


---

## 4. token ID

| NFT           | rules of token ID                        |
| ------------- | ---------------------------------------- |
| Subject       | 0 - 999, 追加する場合は1000+で連番       |
| Imprint       | 自動連番. 別でlocalindexをつける.(0-999) |

---

## 5. デプロイ & 開発手順

1. **ローカル開発**

   1. `forge test` でユニットテスト
   2. `hardhat node` を起動し、`hardhat run script/simulate.ts --network localhost`  
      → Base L2 を想定したシミュレーションを実施

2. **デプロイスクリプト**  
    `scripts/deploy.ts` の順序を  
    (a) Subject ── ERC-721
   (b) Imprint ── DropERC721A
   とし、**EditionHeader** のストレージは Imprint コントラクト内で管理。  
    L2(Base) へ `hardhat run script/deploy.ts --network base_mainnet` でデプロイ。（最初はlocal, 次にtestnetで。）

## 6. Subgraph スキーマ

| エンティティ      | フィールド                                           |
| ----------------- | ---------------------------------------------------- |
| **Subject**       | `id, name, addedEditionNo, latestImprintId`          |
| **EditionHeader** | `editionNo, model, timestamp, sealed`                |
| **Imprint**       | `id, editionNo, subjectId, subjectName, description` |

> **備考**  
> フロントエンドを現状計画しないため、Subgraph は _Optional_ コンポーネントとする。  
> 将来コミュニティが解析・UI 開発を行う場合に備え、ABI とイベント設計だけは
> ドキュメント化し、第三者が自由に Subgraph を立ち上げられるようにする。

## 7. commands

追記予定.

---

## 8. ディレクトリ構造

```bash
.
├── contracts
├── data # LLMの出力先.
│   ├── chatgpt4o
│   └── claude3.7
├── docs # document類
├── README.md
├── test
└── scripts # deploy, inferenceなど.
```

---

## 9. 参考文献・参考作品

1. On Kawara – _Today Series_ (1966–)
2. Sol LeWitt – _Sentences on Conceptual Art_ (1968)／_Wall Drawings_ (1968–)
3. Lawrence Weiner – _STATEMENTS_ (1968)
4. Joseph Kosuth – _Art as Idea as Idea_／_One and Three Chairs_ (1965)
5. Art & Language – _Index 01_ (1972)
6. Alvin Lucier – _I Am Sitting in a Room_ (1969)
7. Douglas Huebler – _Variable Pieces_／_Duration Pieces_ (1969–)
8. Hanne Darboven – _Kulturgeschichte 1880–1983_ (1980)
9. Hans Haacke – _Condensation Cube_ (1963)
10. Jenny Holzer – _Truisms_ (1977–)
11. Gordon Matta-Clark – _Building Cuts_ (1974–)
12. Olafur Eliasson – _The Weather Project_ (2003)
