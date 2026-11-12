# ![asobi](docs/readme/header.png)

[English](README.md) · **日本語**

**Ruby で図形を組み合わせて、SVG の静止画やループアニメーションを作れます。** asobi（遊び）では、絵も Ruby のオブジェクトです。花びらを8枚並べてひとつの花を作り、`spin` を呼ぶと花ごと回ります。

**[ブラウザで試す](https://asobi.myura.me/ja/playground.html)** · [入門ガイドを読む](https://asobi.myura.me/ja/guide.html) · [32秒の紹介映像を見る](https://asobi.myura.me/ja/#film)

## 作品ギャラリー

気になる作品の画像を選び、「遊び場で開く」を押すと、コードを編集できます。画像の下のメソッド名からは、作品の Ruby ファイルを読めます。

| 花 | ハートの窓 | 夜空 |
| :---: | :---: | :---: |
| [![金色の中心のまわりを、深紅と紺の花びらが回る。](docs/readme/flower.gif)](https://asobi.myura.me/ja/examples.html#flower) | [![ハート形の窓の向こうで、赤から金色へ変わるしま模様が回る。](docs/readme/through_a_heart.gif)](https://asobi.myura.me/ja/examples.html#through_a_heart) | [![光る三日月のそばで、金色の星がまたたく。](docs/readme/night_sky.gif)](https://asobi.myura.me/ja/examples.html#night_sky) |
| [`in_fan`](examples/flower.rb) | [`clipped_by`](examples/through_a_heart.rb) | [`fade`](examples/night_sky.rb) |

## 最初のスケッチを動かす

自分のパソコンで動かすには、**Ruby 3.2 以上**とブラウザを用意します。スケッチを置きたいフォルダで次の2行を実行してください。

```sh
gem install asobi
asobi
```

初回は次のコードが入った `play.rb` が作られ、ブラウザで花が回り始めます。すでに同名のファイルがある場合は、そのスケッチが開きます。

```ruby
require "asobi"

flower = petal.repeat(8).in_fan.colored(:crimson, :navy)
show flower.spin(every: 8)
```

**花びらを増やしてみましょう。** `play.rb` の `repeat(8)` を `repeat(12)` に変えて保存すると、ブラウザの花に4枚の花びらが加わります。`every: 8` を `every: 2` にすると、今度は2秒で1回転します。終了するにはターミナルで Ctrl+C を押します。

<details>
<summary>ほかのスケッチを開く・ポートを指定する</summary>

ほかの作品を開くには、`asobi sketch.rb` のようにファイルを指定します。`require "asobi"` と `show` を書いたスケッチは `ruby sketch.rb` でも開けます。ブラウザを自分で開く場合は `asobi` コマンドに `--no-open` を付けて、ターミナルに表示された URL にアクセスしてください。`--port 5000` を付けると、5000 番から空いているポートを探します（既定は 4567 番）。

</details>

## スケッチの書き方

この節の例を試すときは、`play.rb` の先頭にある `require "asobi"` を残し、その下を例のコードに置き換えてください。

### 図形を重ねる、並べる

`petal(40, 16)` は長さ40、幅16の花びらです。`in_fan` で根元を中心に放射状に並べ、`+` で金色の円を手前に重ねます。`scale(0.6)` は元の60%の大きさの花を返します。`beside` で元の花と並べると、大きな花と小さな花がひとつの絵になります。

```ruby
petals = petal(40, 16).repeat(8).in_fan.colored(:crimson, :navy)
flower = petals + circle(5).colored(:gold)
show flower.beside(flower.scale(0.6), gap: 12)
```

長さは絵の中での大きさを表します。表示するときは絵全体が画面に収まるように拡大・縮小されます。回転角は度で指定し、`rotate(90)` なら時計回りに4分の1回転します。

### 数列を絵にする

`to_art` は Ruby の値を絵に変換します。この例ではフィボナッチ数列の各項が星の大きさになり、小さな星から順に横一列に並びます。`as:` を省くと、各項を半径とする円になります。

```ruby
fib = [1, 1, 2, 3, 5, 8, 13, 21]
show fib.to_art(as: star).colored(:gold, :orange), on: :black
```

### 自分のクラスで絵を作る

自作クラスに絵を返す `to_art` を定義すると、そのインスタンスを `show` に渡せます。さらに `Asobi::Art` をインクルードすると、インスタンスに対して直接 `spin` や `beside` を呼べます。

```ruby
class Flower
  include Asobi::Art

  def initialize(count, color)
    @count = count
    @color = color
  end

  def to_art
    petal.repeat(@count).in_fan.colored(@color)
  end
end

show Flower.new(7, :coral).spin(every: 4)
```

### 動きに時間差をつける

輪に並べた点を `pulse` で2倍まで膨らませ、元の大きさに戻します。直後に `one_by_one` を付けると、それぞれの点が少しずつ遅れて膨らみ、波が輪を一周します。

```ruby
dots = circle(5).repeat(24).in_ring.colored(:gold, :orange)
show dots.pulse(every: 2, to: 2).one_by_one, on: :black
```

<details>
<summary>ほかの図形・色・動きに使えるメソッド</summary>

| やりたいこと | 主なメソッドとオプション |
| --- | --- |
| 形を作る | `circle`、`rect`、`star`、`text`、`path`、`wave`、`heart`、`petal` |
| 図形を配置する | `in_row` で横一列、`in_grid` で格子状、`in_ring` で円周上、`in_spiral` でらせん状に並べる |
| 色や質感を変える | `colored(from: :gold, to: :crimson)` でグラデーション、`glowing` で発光、`shadowed` で影、`clipped_by` で切り抜き |
| 動きを作る | `spin` で回転、`sway` で揺れ、`orbit` で公転、`trail` で残像を付ける。独自の動きは `animate` で定義する |
| 表示を整える | `show` の `on:` で背景色、`paper:` で用紙の寸法、`grain: true` で粒子感を指定する |

</details>

## 作品の保存と録画

静止画は SVG、アニメーションはブラウザでそのまま再生できる HTML に保存できます。次の例は、スケッチを実行したディレクトリに2つのファイルを書き出し、同じアニメーションをライブ表示します。

```ruby
flower = petal.repeat(8).in_fan.colored(:crimson, :navy)
motion = flower.spin(every: 4)

flower.save("flower.svg")
motion.save("flower.html")
show motion
```

アニメーションの途中を静止画にするには、`motion.at(1).save("frame.svg")` のように秒数を指定します。

| ライブ表示中の操作 | 結果 |
| --- | --- |
| **C** キーを押す | スケッチのソースコードの表示を切り替えます。 |
| **R** キーを押し、もう一度押す | 録画を開始し、2回目で動画をダウンロードします。対応ブラウザに応じて MP4 または WebM になります。 |
| エラーのあるスケッチを保存する | 直前に描けた絵が残り、その下にエラーメッセージが表示されます。 |

## 既存の Ruby プログラムに組み込む

`require "asobi"` を使うと、`circle` などをトップレベルで呼べるようになり、数値や配列に `to_art` が加わります。既存のプログラムで Ruby の標準クラスを拡張せずに使うには、`asobi/pure` を読み込みます。次のコードを `export.rb` として保存し、同じフォルダで `ruby export.rb` を実行すると、紺色の星を3つ並べた `stars.svg` ができます。

```ruby
require "asobi/pure"

stars = Asobi.art([3, 1, 4], as: Asobi.star)
stars.colored(:navy).save("stars.svg")
```

## 作例とドキュメント

絵を作る手順は[入門ガイド](https://asobi.myura.me/ja/guide.html)で、メソッドの引数や既定値は[リファレンス](https://asobi.myura.me/ja/reference.html)で調べられます。

リポジトリには、1ファイルで動くスケッチが入っています。クローンしたリポジトリのルートで `asobi examples/flower.rb` を実行すると、花の作例を開けます。

- 数列を形にする仕組みを試すなら [数列の星](examples/sequence.rb)
- 発光、色の合成、残像を重ねるなら [ネオンの花](examples/neon_flower.rb)
- 自作クラスで複数の軌道を描くなら [惑星](examples/planets.rb)
- ほかの作品を探すなら [作例一覧](examples/README.md)

## 開発

リポジトリのルートで `ruby exe/asobi examples/flower.rb` を実行すると、ライブラリ本体への変更を試せます。テストの実行とドキュメントの生成には次のコマンドを使います。

```sh
bundle install
bundle exec rake test
bundle exec rake site
```

生成された `_site/ja/index.html` をブラウザで開くと日本語版、`_site/index.html` を開くと英語版を読めます。「遊び場」でコードを編集して実行するには、CDN から ruby.wasm を読み込むためのインターネット接続が必要です。

テストでは、ライブラリと CLI の動作、テスト用データからのサイト生成、ギャラリーと両言語の README に載せたスケッチを検証します。ライブラリの設計については[設計書](DESIGN.md)を参照してください。

## 不具合報告・改善の提案（Issue・PR）

日本語・英語どちらでも歓迎です。不具合の場合は、問題が起きる短いスケッチがあると再現しやすくなります。機能のアイデアは「こんな絵を描きたい」「こんな動きを作りたい」から気軽にどうぞ。[Issue を作成する](https://github.com/Hayato1031/asobi/issues/new/choose)

バグの修正、ドキュメントの改善、作例の追加などのプルリクエスト（PR）も歓迎です。[asobi をフォーク](https://github.com/Hayato1031/asobi/fork)して、自分のフォークにブランチを作り、変更を `Hayato1031/asobi` の `main` 宛てに送ってください。大きな変更は、先に Issue で相談できます。

## ライセンス

[MIT ライセンス](LICENSE) · [RubyGems](https://rubygems.org/gems/asobi) · [公式サイト](https://asobi.myura.me/ja/)
