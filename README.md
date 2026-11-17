# beadview

beads（`bd`）を使っている全リポジトリについて、**着手中 / 最近閉じたもの / 着手できるもの** を一画面に出す。
誰が何をいつから触っているか、何がどんな理由で閉じたかを見るためのもの。

**読み取り専用。** bd は必ず `--readonly` で呼び、`--json` の出力だけを読む。

```sh
ln -s "$PWD/exe/beadview" ~/.local/bin/beadview   # インストール（Ruby 3.3 以上、標準ライブラリのみ）
beadview                      # ghq list で見つかる .beads/ を持つリポジトリ全部
beadview --repo team_wiki     # 絞る（複数可）
beadview --days 7             # 最近閉じたものを7日分
beadview --json               # JSON で出す
beadview --no-cache           # bd history のキャッシュ（~/.cache/beadview）を使わない
beadview --no-pr              # gh で PR の状態を引かない（オフラインのとき）
```

- 「いつから」は `bd history` から最後に in_progress になった時刻を出す。updated_at が変わるまでキャッシュする
- 閉じた人は events journal（`bd events tail`）に記録があればそれ、無ければ担当者を `名前?` として推測表示する
- bead のタイトル・notes・閉じた理由に書かれた `#123` を、そのリポジトリ（origin）の PR として `gh` で引き、行末に状態を出す
  - **閉じ忘れ?**: 着手中なのに、書かれた PR がすべて片付き、1つ以上マージされている
  - **マージ待ち**: 閉じたのに、書かれた PR がまだ開いている（閉じた時期は問わない）
  - beads が持つのは「作業を終えた」まで。「マージされた」は GitHub にしか無いので、その差をここで埋める
