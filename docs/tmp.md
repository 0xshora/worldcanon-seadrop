🐞 現在抱えているバグ & 仕様逸脱メモ

#	症状 / 発生箇所	原因	影響
B-1	forge build 時に Warning (8760) — 同名宣言	syncFromImprint の引数 subjectName が外部関数 subjectName(uint256) と衝突	将来 IDE 補完や NatSpec で混乱。静的解析ツールで Error 判定されるケースあり
B-2	ユニットテスト testSyncFromImprintCreatesSubject() 失敗	_nameHashToIdPlus1 を Assembly 直読み → slot 算出が不安定／Getter 未実装	テストだけでなく、外部ツールから「名前→tokenId」を取れない
B-3	依然として setImprintContract() が 二重定義（重複関数）	手動マージの際に古い定義が残存	コンパイラはエラーにはしないが、リファクタ時に衝突リスク
B-4	mintInitial() で 重複 Subject 名を許容	正規化ハッシュ重複チェックが require == 0 されていなかった行が一部残存	同名 Subject が初期 1000 件に混入する恐れ
B-5	tokenURI() が imprintContract==0 でも latestImprintId>0 を参照可	ガード不足	imprint 未設定時に外部コールでリバート
B-6	Getter 不在によりストレージを Assembly 参照	保守性低下・レイアウト変更に弱い	テスト失敗・監査指摘対象
B-7	(Imprint.sol) world-canon 連携・pause 機構など TODO項目が未実装	仕様タスク残	機能不足／SeaDrop 本番前に要対応


⸻

🔧 修正方法（パッチ指示）

Bug	修正内容
B-1	syncFromImprint(string calldata subjName, …) の 引数名を subjName に変更。
B-2 / B-6	subjectIdByName(string) view Getter を追加 solidity\nfunction subjectIdByName(string calldata name) external view returns (bool ok,uint256 id) { uint256 p = _nameHashToIdPlus1[name.normHash()]; return (p!=0, p==0?0:p-1); }\n → テストは Assembly 直読みをこの Getter へ差替え。
B-3	下段に残った重複 setImprintContract を 削除。
B-4	mintInitial ループ内にrequire(_nameHashToIdPlus1[h]==0,"dup subject"); を追加。
B-5	tokenURI → `imageURI = (m.latestImprintId==0
B-7	実装タスク（下表参照）で対応。


⸻

✍️ 今後実装が必要なもの（High-priority TODO）

タスク	概要	影響範囲
T-1 worldCanon 連携完了	Imprint.setWorldCanon()（一度だけ）＋ mintSeaDrop 内で Subject.syncFromImprint 呼び出し	Imprint.sol & Subject.sol
T-2 Mint Pause / Edition Close	mintPaused & setMintPaused(bool)、closeActiveEdition()	Imprint.sol
T-3 Re-entrancy 整合 fix	mintSeaDrop で メタ先書き → Subject.sync → _safeMint の順序に改修	Imprint.sol
T-4 280 bytes 上限チェック	addSeeds: require(desc.length≤280,"desc>280B")	Imprint.sol
T-5 Per-address 25 枚ガード	require(_numberMinted(to)+quantity≤25,"over 25")	Imprint.sol
T-6 O(1) remainingInEdition	unclaimedCount を Seed 登録／Claim で増減管理	Imprint.sol
T-7 NatSpec コメント追加	外部 / public 関数へ簡易説明	Subject.sol & Imprint.sol
T-8 テスト補完	上記変更をカバーする Foundry テスト	Subject.t.sol, Imprint.t.sol


⸻

作業の優先順
	1.	バグ B-1〜B-6 を即時パッチ → テスト Green に戻す
	2.	T-1〜T-6 を実装しながら対応テスト追加
	3.	ドキュメント & NatSpec 整備（T-7）
	4.	ガス・バイトコード最終チェック → リリースブランチへマージ

これで当面の不整合を解消し、残タスクを明文化できます。


---

📝 Subject ↔ Imprint 連携 TODO リスト

#	タスク	具体内容	完了条件
L-1	setWorldCanon() 実装	Imprint.sol に address public worldCanon; とfunction setWorldCanon(address)（onlyOwner・一度だけ）を追加。	- 2 回目呼び出しで revert("already set")- Foundry テスト worldCanonSetOnce() が Green
L-2	メタ先書き → Subject 同期 → safeMint 順序	mintSeaDrop 内部を1. firstTokenId = _nextTokenId()2. Seed → meta → descPtr を先に書く3. Subject(worldCanon).syncFromImprint(...) ループ呼び出し4. _safeMint(to, quantity) 実行	- コントラクト受取 (ERC721Holder) でミント成功- tokenURI が即時取得可能
L-3	syncFromImprint() 呼び出しパラメータ	solidity\nsubj.syncFromImprint(\n    s.subjectName,\n    tokenId,\n    editionHeader.timestamp\n);\n	- 新規 Subject 自動生成- 既存 Subject は timestamp 比較で更新
L-4	重複 Subject 逆引き	Subject.subjectIdByName(string) Getter で(exists, id) を返却。Imprint 側では使わないがテスト支援。	Getter が戻り値を正しく返し、gas 0 (view)
L-5	ユニットテスト追加	Imprint.t.sol に1. testWorldCanonSetOnce()2. testMintSyncsSubject()：SeaDrop ミント後に Subject.latestImprintId が更新される3. testOlderTimestampIgnored()	forge test 全緑。カバレッジ >90%
L-6	ドキュメント更新	docs/README.md に Edition → Seed → Mint → Subject 更新 のシーケンス図を追記。	図とフローが要件と一致
L-7	NatSpec	syncFromImprint, setWorldCanon, subjectIdByName, mintSeaDrop に概要・@notice を追加。	forge build --doc で警告なし

優先順: L-1 → L-2 → L-3 → L-5 → L-4 → L-6 → L-7
完了したらチェックボックス - [x] を忘れずに更新してください。