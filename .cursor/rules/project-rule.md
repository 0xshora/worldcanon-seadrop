# rule
- 機能を追加した場合は必ずユニットテストを追加し、`forge test --match-path test/foundry/Subject.t.sol && forge test --match-path ./test/foundry/Imprint.t.sol` が Green になることを確認してください。
- `./docs/README.md` が要件定義書です。これを遵守するように実装してください。
- `./docs/TODOlist.md` が残タスクチェックリストです。これを完了するように実装してください。
- `./src-upgradeable/src/Imprint.sol`が`Imprint`の実装ファイルです。これを編集してください。
- `./test/foundry/Imprint.t.sol`が`Imprint`のユニットテストファイルです。これを編集してください。
- `./src-upgradeable/src/Subject.sol`が`Subject`の実装ファイルです。これを編集してください。
- `./test/foundry/Subject.t.sol`が`Subject`のユニットテストファイルです。これを編集してください。
- **それ以外のファイルを編集しないでください。**