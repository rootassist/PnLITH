# PnLITH - PowerShell版ブロック積みゲーム

本ソフトウェア『PnLITH』は、佐々木太朗（Taroh Sasaki）氏による『NLITH 2.2』(1988)の動作をPowerShellで再現した移植版です。
『NLITH』の規約に基づき、名称を「PnLITH」としています（PはPowerShell版の意味）。
『PnLITH』のゲームのアルゴリズムは原典である『NLITH』を踏襲していますが、起動オプションや環境変数の取り扱いに違いがあり、また新たな機能を追加しています。パニック機能は実装しておりません。
『NLITH 2.2』の配布ファイルはNLITH22の下にあります。(オリジナルの配布ファイルであるNLITH22.ARCと、アーカイバーをZIP形式に変更したNLITH22.ZIP)

> （参考）NLITH 2.2のNLITH.MAN：
> 本プログラムは、その全部が完全な形であるときのみ本プログラムとみなされます。したがって、本プログラムの名前の下に、改変されたプログラムを再配布することは、禁止されます。

---

## 改訂履歴

- Ver 1.0
  - 初期バージョン

---

## 動作環境

- PowerShell 5.1以降（Windows 10/11 標準搭載）または PowerShell 7.x
- Windows Terminal または conhost.exe
- 画面サイズ: 80列×24行以上

---

## 画面構成

```
列:  0         wellx_beg  wellx_end       62        79
行:
 0:   [                                   ]
 1-6: [ロゴ "Pn" ]|  ゲーム  |  NEXT表示枠 (-NextBlock時)
 7:   [          ]|フィールド|  メッセージウィンドウ
 8-12:[ロゴ "LI" ]| (ウェル) |
13:   [          ]|          |  Aprox. Phase : xx (-PMoon時)
14:   [ロゴ "TH" ]|          |  * training mode *
15:   [ロゴ "TH" ]|          |  holy point: NNN
16:   [ロゴ "TH" ]|          |  evil point: NNN
17:   [ロゴ "TH" ]|          |
18:   [ロゴ "TH" ]|          |  score: NNNNNN
19:   [          ]|          |  blocks: NNN
20:   [          ]|          |  lines: NNN
21:   [          ]+----------+
22:   [                      ] 確認プロンプト表示エリア
```

- **ゲームフィールド（ウェル）**: ブロックが落下するエリア。`-Width` と `-Depth` で大きさを変更可能
- **ロゴ**: ウェル左側に表示（`t`/`T`キーまたは `-NoLogo`で非表示）
- **ネクストブロック表示**: `-NextBlock`指定時のみ、右上にNext枠を表示
- **メッセージウィンドウ**: 右側中段にゲームイベントのメッセージを表示
- **ステータス表示**: 右側にスコア、ブロック数、消去ライン数、holy/evilポイントを表示
- **月齢表示**: `-PMoon`指定時のみ、月齢の概算値を表示

---

## 使用ファイル

| ファイル          | 形式                        | 説明                                           |
| :---------------- | :-------------------------- | :--------------------------------------------- |
| `pnlith.ps1`    | PowerShell スクリプト       | 本体                                           |
| `config.nlt`    | Shift-JIS テキスト          | ブロック定義、キーエイリアス、表示設定         |
| `strings.nlt`   | NLT暗号化されたテキスト     | ゲーム中のメッセージ文字列                     |
| `record.json`   | JSON (UTF-8) (無ければ作成) | 通常モードのハイスコア記録（最大21件）         |
| `recordtr.json` | (同上)                      | トレーニングモードのハイスコア記録（最大21件） |
| `recordcr.json` | (同上)                      | 直近7日間の記録（最大21件）                    |

以下はconfig.nltのサンプルです。名前をconfig.nltに変更して利用してください

- configm.nlt: モノクロ用
- confign.nlt: ブロックが記号文字
- configg.nlt: ブロックが漢字

以下はstrings.nltのサンプルです。名前をstrings.nltに変更して利用してください

- stringsn.nlt: オリジナルのメッセージ
- stringsg.nlt: より「分かりやすい」メッセージ

### ファイル検索順序

`config.nlt` および `strings.nlt` は以下の順序で検索されます:

1. `-FilePath` で指定されたディレクトリ
2. `pnlith.ps1` と同じディレクトリ

`record.json`、`recordtr.json`、`recordcr.json` は `pnlith.ps1` と同じディレクトリに保存されます。

---

## 起動方法

コマンドプロンプトまたはPowerShellを開き、以下のコマンドを入力して実行します。

```powershell
powershell -File (パス名)\pnlith.ps1 [オプション]
```

パス名には、使用ファイル一式を置いた絶対パスを指定してください。  
PowerShellを起動して該当フォルダに移動済みの場合は

```powershell
.\pnlith.ps1 
```

と指定できます

**実行がブロックされる場合**

PowerShellのセキュリティ設定（実行ポリシー）によって起動がブロックされる場合は、以下のように -ExecutionPolicy Bypass を追加して実行を許可してください。

```powershell
powershell -ExecutionPolicy Bypass -File (パス名)\pnlith.ps1 [オプション]
```

PowerShellを起動して該当フォルダに移動済みの場合は、Set-ExecutionPolicyで実行を許可してから起動してください。

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\pnlith.ps1 
```

**Windows Terminalで画面表示が崩れる場合（重要）**

Windows Terminalで実行すると、ブロックの反転表示が半分欠けるなど、正常に描画されない場合があります。
これを回避し、従来のコンソール画面で正しく表示させるには、先頭に conhost を付けて以下のように指定してください。

```powershell
conhost powershell -File (パス名)\pnlith.ps1 [オプション]
```

※実行ポリシーのブロックも同時に回避する場合は

```powershell
conhost powershell -ExecutionPolicy Bypass -File (パス名)\pnlith.ps1 [オプション] 
```

と入力してください

## 起動オプション

| オプション         | 型     | 既定値 |    範囲    | 説明                               |
| :----------------- | :----- | :----: | :--------: | :--------------------------------- |
| `-Width`         | int    |   10   |   6〜20   | フィールド幅                       |
| `-Depth`         | int    |   20   |   6〜22   | フィールド深さ                     |
| `-BlockSize`     | int    |   0   |    0〜5    | ブロックサイズ（0=既定）           |
| `-Speed`         | int    |  400  |     —     | 落下速度（ミリ秒、小さいほど速い） |
| `-Height`        | int    |   0   |     —     | 初期ゴミ高さ                       |
| `-Training`      | switch |   —   |     —     | トレーニングモード                 |
| `-Jump`          | switch |   —   |     —     | ジャンプモード                     |
| `-ReverseRotate` | switch |   —   |     —     | 回転方向を逆にする                 |
| `-NoColor`       | switch |   —   |     —     | カラー表示を無効にする             |
| `-NoLogo`        | switch |   —   |     —     | ロゴ表示を無効にする               |
| `-NoBell`        | switch |   —   |     —     | ベル音を無効にする                 |
| `-ShowScores`    | switch |   —   |     —     | ハイスコア一覧を表示して終了       |
| `-Player`        | string |   ""   | 最大16文字 | プレイヤー名（後述）               |
| `-FilePath`      | string |   ""   |     —     | 設定ファイルの検索パス             |
| `-NextBlock`     | switch |   —   |     —     | 次のブロックを表示                 |
| `-PMoon`         | switch |   —   |     —     | 月齢の概算値を表示                 |
| `-NewMoon`       | string |   ""   |  ISO 8601  | 基準新月の日時（後述）             |

### 起動例（使用ファイル一式をC:\WORKに置いた場合）

```powershell
# 既定設定で開始
PowerShell -File C:\WORK\pnlith.ps1                          
# トレーニングモード
PowerShell -File C:\WORK\pnlith.ps1 -Training                
# フィールドと速度を指定
PowerShell -File C:\WORK\pnlith.ps1 -Width 12 -Depth 18 -Speed 300 
# ハイスコア表示
PowerShell -File C:\WORK\pnlith.ps1 -ShowScores              
# プレイヤー名と初期ゴミ高さを指定
PowerShell -File C:\WORK\pnlith.ps1 -Player "TARO" -Height 5   
# Windows11のWindows Terminalで実行する場合
conhost PowerShell -File C:\WORK\pnlith.ps1                  
# Windows11のWindows Terminalで実行し、スクリプトの実行を許可する場合
conhost PowerShell -ExecutionPolicy Unrestricted -File C:\WORK\pnlith.ps1                              
```

### プレイヤー名のデフォルト

`-Player` を省略した場合、プレイヤー名は以下の優先順位で決定されます:

1. 環境変数 `USERNAME`（Windowsログインユーザー名）を自動取得
2. `USERNAME` が空または `"guest"` の場合は、画面上で入力を求められる

最大16文字。スペースはアンダースコア `_` に変換されます。

---

## 操作キー

### 矢印キー

| キー | 動作               |
| :--- | :----------------- |
| ←   | ブロックを左に移動 |
| →   | ブロックを右に移動 |
| ↓   | ブロックを落下     |
| ↑   | ブロックを回転     |

### 文字キー（既定のキーエイリアス）

| 動作   | 割り当てキー                  |
| :----- | :---------------------------- |
| 左移動 | `4` `h` `H`             |
| 右移動 | `6` `l` `L`             |
| 落下   | `2` `j` `J` `Space`   |
| 回転   | `5` `Tab` `Enter`       |
| 祈り   | `8` `k` `K` `p` `P` |
| 終了   | `q` `Q` `Ctrl+C`        |

### 機能キー

| 動作                 | 割り当てキー |
| :------------------- | :----------- |
| ベル音の切替         | `g` `G`  |
| ロゴ表示の切替       | `t` `T`  |
| カラー表示の切替     | `f` `F`  |
| 画面再描画           | `r` `R`  |
| ジャンプモードの切替 | `e` `E`  |

### キーエイリアスのカスタマイズ

`config.nlt` にて `alias` 行を記述することでキー割り当てを変更できます。(後述)

---

## holy/evil point と「祈り」について

- 「邪悪なこと」をするとevil pointが増えます。evil pointが増えるとブロックが「操作しづらく」なったりします。
- 「祈り」を行うと、holy pointが減りますが、evil pointが減るかもしれません。またブロックが変形するかもしれません。

〈注〉思い通りに動かないからといって直ちにバグとは判断しないでください。

---

## 月齢と満月・新月

月齢がゲームに影響を及ぼします。満月に近いほど「有利」に働きます。

`-PMoon` オプションを指定すると、画面右側に月齢の概算値が表示されます。

月齢は朔望月方式（平均朔望月周期 29.530588853日）により算出され、ゲーム開始時の月の状態が5段階で判定されます。

| 状態     | メッセージ                                   |
| :------- | :------------------------------------------- |
| 満月前後 | ゲーム開始時に「満月」メッセージが表示される |
| 新月前後 | ゲーム開始時に「新月」メッセージが表示される |

満月・新月のメッセージは `-PMoon` を指定していなくても、メッセージウィンドウに表示されます。

### 基準新月の変更

月齢計算の基準新月はデフォルトで `2025-12-20T01:43:00Z` ですが、`-NewMoon` オプションでISO 8601形式の日時を指定することで変更できます。朔望月方式は平均周期に基づくため、長期間経過すると実際の月相とのずれが生じます。より正確な月齢を得たい場合は、直近の天文学的新月の日時を指定してください。

```powershell
.\pnlith.ps1 -PMoon -NewMoon "2026-01-18T19:52:00Z"
```

日付の形式が正しくない場合は、デフォルトの基準新月でゲームを開始するかどうかの確認メッセージが表示されます。

---

## config.nlt の書式（NLITHに準拠）

`config.nlt` はShift-JISプレーンテキストのファイルです。
各行は以下のいずれかの形式で記述します。`#` で始まる行はコメントとして無視されます。

### ブロック外観設定

```
NAME = ATTR, CHARACTER
```

- **NAME**: ブロック名（`o1`, `i2`, `i3`, `l3`, `i4`, `j4`, `j4r`, `t4`, `o4`, `z4`, `z4r`, `i5`, `x5`, `t5`, `u5`, `w5`, `l5`, `z5`, `z5r`, `j5`, `j5r`, `n5`, `n5r`, `y5`, `y5r`, `f5`, `f5r`, `p5`, `p5r`）
- **ATTR**: 色指定。色名（`ewh`, `ere`, `egr`, `eye`, `ebl`, `epu`, `etu`, `evwh`, `evre`, `evgr`, `evye`, `evbl`, `evpu`, `evtu`）または数値コード
- **CHARACTER**: 表示文字（2文字、例: `[]`, `XX`）

ブロック名と形状

```
 o1      []

 i2      []
         []

 i3      []   l3    []
         []         [][]
         []

 i4      []   j4      []  j4r    []
         []           []         []
         []         [][]         [][]
         []

 t4  [][][]   o4    [][]  z4   [][]     z4r    [][]
       []           [][]         [][]        [][]

 i5      []   x5    []    t5   [][][]   u5   []  []
         []       [][][]         []          [][][]
         []         []           []
         []
         []

 w5  []      l5   []      z5    [][]    z5r    [][]
     [][]         []              []           []
       [][]       [][][]          [][]       [][]

 j5      []  j5r    []    n5        []  n5r    []
         []         []              []         []
         []         []            [][]         [][]
       [][]         [][]          []             []

 y5      []  y5r    []    f5      [][]  n5r  [][]
       [][]         [][]        [][]           [][]
         []         []            []           []
         []         []

 p5    [][]  p5r    [][]
       [][]         [][]
       []             []
```

色指定

| 色名 | 色             |
| :--- | :------------- |
| ebl  | BLue           |
| ere  | REd            |
| egr  | GReen          |
| etu  | TUrquoise      |
| eye  | YEllow         |
| epu  | PUrple         |
| ewh  | WHite          |
| ev?? | (上記の反転色) |

#### 虫(worm)の外観設定

```
NAME = ATTR, CHARACTER
```

- **NAME**: 虫の属性
- **ATTR**: 色指定。色名（`ewh`, `ere`, `egr`, `eye`, `ebl`, `epu`, `etu`, `evwh`, `evre`, `evgr`, `evye`, `evbl`, `evpu`, `evtu`）または数値コード
- **CHARACTER**: 表示文字（2文字、例: `[]`, `XX`）

| 虫の属性 | 内容                       |
| :------- | :------------------------- |
| wal      | 生存中の色(色指定のみ有効) |
| whd      | 頭の文字と死亡時の色       |
| wbd      | 胴体の文字と死亡時の色     |
| wsp      | 魂の化石の文字と色         |

### キーの定義

```
alias <キー指定> <アクション>
```

アクションとしては次のものが定義できます

- **キー指定**: 単一文字（`a`, `space` 等）、Ctrl+キー（`^A`）、16進数（`\x1B`）、10進数（`\27`）
- **アクション**: `left`, `right`, `drop`, `rota`, `pray`, `quit`, `beep`, `logo`, `colour`, `redraw`, `jump`

| アクション名 | アクション       |
| :----------- | :--------------- |
| left         | ブロック左移動   |
| right        | ブロック左移動   |
| drop         | ブロック落下     |
| rota         | ブロック回転     |
| pray         | 祈る             |
| quit         | ゲーム中止       |
| beep         | サウンドon / off |
| logo         | ロゴ表示on / off |
| colour       | カラーon / off   |
| redraw       | 画面再描画       |
| jump         | jump機能on / off |

### スイッチ設定

```
SWITCH yes|no
```

| スイッチ   | 説明                            |
| :--------- | :------------------------------ |
| `beep`   | ベル音の有効/無効               |
| `logo`   | ロゴ表示の有効/無効             |
| `colour` | カラー表示の有効/無効           |
| `jump`   | ジャンプモードの有効/無効       |
| `next`   | ネクストブロック表示の有効/無効 |
| `moon`   | 月齢表示の有効/無効             |

### 設定例

```
# ブロックの外観

i4 = egr, XX
t4 = epu, \/

# キーバインド

alias a left
alias d right
alias w rota
alias s drop

# スイッチ

beep yes
colour yes
next no
moon no
```

---

## 謝辞

オリジナルのnlithを開発された佐々木太良氏に深く感謝いたします。

## ライセンス

### PnLITH

MIT License

Copyright (c) 2026 rootassist. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### 原典について

本ソフトウェアは『NLITH 2.2』(c) 1988 Taroh Sasaki（佐々木太朗）のアルゴリズムを元に、PowerShellで新規に実装した移植版です。
NLITHの配布規約における「一部利用の許可」に基づき、別名（PnLITH）で公開しています。

- 原典の著作権は佐々木太朗氏に帰属します
- PnLITHの動作について、原作者の佐々木氏は一切関知しません
- 月齢計算は朔望月方式による独自実装であり、原典が使用していたNetHack由来のアルゴリズムは使用していません

なお、以下は原典である『NLITH 2.2』(c) 1988 Taroh Sasaki（佐々木太朗）に含まれるNLITH.MANにある「配布について（重要）」の記述です。

> 　無料にての流通を保証しているのですから、最低限以下の項目は遵守して下さい。　本プログラムは完全なPDSです。自由に配布して下さい。光学的・磁気的・電気的・物理的・化学的・音楽的・文学歴史の20的・白魔術＆黒魔術的等、いかなる手段にてもコピーは自由です。金銭を伴う販売等も自由ですが、本プログラムの配布を妨げるいかなる行為も禁止されます。　2次配布に際しては、本プログラムを含むファイル群一式は、本ドキュメント・各ファイル群・実行ファイルのアーカイブ（原配布状態に含まれている場合はソースも）、すべてのファイルを含む形態で、なおかつ改変されていない状態で再配布して下さい。アーカイバの種類は自由です。　アーカイブの内容が元配布状態と異なっているかどうかを被再配布者が知る術はないでしょうが、一次配布は多くの人が証人となりうる場所に掲載されています。　本ドキュメントは、必要とする人が容易に理解できる形であれば、再編されていても構いません。但し、最低限本ドキュメントに記載してある事項は非再配布者の理解できる形で収録して下さい。　本プログラムは、その全部が完全な形であるときのみ本プログラムとみなされます。したがって、本プログラムの名前の下に、改変されたプログラムを再配布することは、禁止されます。　バージョンアップへの対応は、再配布者が責任を持って行なって下さい。　本プログラムの一部を無断で流用することは構いません。しかし、本プログラムまたはその一部を使用したために生じた事故等について、原作者は一切の責任を問われないものとします。　原配布状態では、ソースを付加していない場合があります。これは、ソースを必要としない人が多い状況での配布を鑑みてのことです。その実行ファイルを二次配布する場合には、なるべく原作者にソース再配布の必要・不必要をご相談下さい。　これらの規定に反する場合は、当該国・州の法律・条例に反しない範囲で使用権を剥奪されるものとしますが、被再配布者がこれらの規定を知らずに配布を受けていた場合は、その使用権まで剥奪されることはないものとします。
