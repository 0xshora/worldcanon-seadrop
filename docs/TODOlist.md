## TODO

### 注意
- 各項目を終えたら **`- [x]`** に変更し、必ずユニットテストを追加 → `forge test --match-path test/foundry/Subject.t.sol && forge test --match-path ./test/foundry/Imprint.t.sol` が Green になることを確認してください。
- `./docs/README.md` が要件定義書です。これを遵守するように実装してください。
- `./docs/TODOlist.md` が残タスクチェックリストです。これを完了するように実装してください。
- `./src-upgradeable/src/Imprint.sol`が`Imprint`の実装ファイルです。これを編集してください。
- `./test/foundry/Imprint.t.sol`が`Imprint`のユニットテストファイルです。これを編集してください。
- `./src-upgradeable/src/Subject.sol`が`Subject`の実装ファイルです。これを編集してください。
- `./test/foundry/Subject.t.sol`が`Subject`のユニットテストファイルです。これを編集してください。
- それ以外のファイルを編集しないでください。

### ✅ 残タスクチェックリスト

- [x] **読み取りヘルパ**  
  - `getSeed(seedId)`・`remainingInEdition(ed)`・`tokenMeta(tokenId)` を `view` で追加。  
  - **Test:** 返値が正しい & ガス測定（`vm.recordGas` など）。

- [x] **worldCanon 連携（Subject⇄Imprint）**  
  - `setWorldCanon(address)` を `onlyOwner` & **一度だけ** 設定可能に。  
  - `mintSeaDrop` で Subject コントラクトへ `setLatestImprint(tokenId)` 等を呼び出す。  
  - **Test:** 二度目の設定は revert／Mint 後 Subject.latest が正しく更新される。

- [x] **ETH / ERC20 引き出し**  
  - `withdraw(address payable to)` と `withdrawToken(address token, address to)` を `onlyOwner` で実装。  
  - **Test:** ノンオーナーは revert／受取アドレス残高が増える。
  - クラスを継承しているため、やる必要があるかを先に確認すること。

- [x] **Mint Pause & Edition Close**  
  - `bool mintPaused` と `setMintPaused(bool)`。  
  - `closeActiveEdition()` で `activeEdition = 0` & `activeCursor = 0`。  
  - **Test:** Pause 中は mintSeaDrop が revert。Close 後は再度 Edition 設定が必要。

- [x] **Edition Size 表示**  
  - `editionSize(uint64 ed) returns (uint256)` を実装（`lastSeedId - firstSeedId + 1`）。  
  - **Test:** Seal 後でも正値が返る。

- [x] **supportsInterface 拡張**  
  - 新規 `ISubjectAware` など追加時は `supportsInterface` に反映。  
  - **Test:** `IERC165.supportsInterface` が true を返す。

- [ ] **バイナリサイズ削減**  
  - `foundry.toml` に `optimizer = true, runs = 200`。  
  - SVG 定数を外部ライブラリ or オフチェーンに。  
  - **Test:** `forge build` で bytecode < 24 576 bytes（Spurious Dragon 制限）。

- [ ] **テスト強化**  
  - すべての新規関数・revert パスを網羅。  
  - **Test:** `forge test -vv` が全緑。

- [ ] **NatSpec & Docs**  
  - External 関数に NatSpec コメントを追加。  
  - `README.md` に Edition → Seed → Mint フロー図を貼る。