<#
.SYNOPSIS
    PnLITH - PowerShell版ブロック積みゲーム
.DESCRIPTION
    NLITH 2.2 (1988, Taroh Sasaki) の動作をPowerShellで再現したものです。
    ライセンス上の制約により、アプリケーション名はPnLITHとしています。
.EXAMPLE
    .\pnlith.ps1
    .\pnlith.ps1 -Training
    .\pnlith.ps1 -Width 12 -Depth 18 -Speed 300
    .\pnlith.ps1 -ShowScores
#>
[CmdletBinding()]
param(
    [ValidateRange(6, 20)][int]$Width = 10,
    [ValidateRange(6, 22)][int]$Depth = 20,
    [ValidateRange(0, 5)][int]$BlockSize = 0,
    [int]$Speed = 400,
    [int]$Height = 0,
    [switch]$Training,
    [switch]$Jump,
    [switch]$ReverseRotate,
    [switch]$NoColor,
    [switch]$NoLogo,
    [switch]$NoBell,
    [switch]$NextBlock,
    [switch]$PMoon,
    [switch]$ShowScores,
    [ValidateLength(0, 16)][string]$Player = "",
    [string]$FilePath = "",
    [string]$NewMoon = ""         # 基準新月 (ISO 8601形式、例: 2025-12-20T01:43:00Z)
)

#region 定数
# ウェル（フィールド）サイズ制約
$script:WELLWIDTH_MIN = 6
$script:WELLWIDTH_MAX = 20
$script:WELLWIDTH_DEF = 10
$script:WELLDEPTH_MIN = 6
$script:WELLDEPTH_MAX = 22
$script:WELLDEPTH_DEF = 20
$script:WELL_BOTTOM_MAX = 22           # ウェル底面の画面Y座標上限
$script:SCR_X = 80                     # 画面幅（列数）

# ブロック定義上限
$script:MAXLITHN = 5                   # ブロック最大タイル数
$script:MAXINIINFO = 29                # ブロックパターン数
$script:MAXROTINFO = 91                # 回転パターン数

# ブロックサイズ範囲
$script:LITHN_MIN = 1
$script:LITHN_MAX = 5
$script:LITHN_DEF = 4                  # トレーニング時の既定サイズ

# ゲームパラメータ
$script:WORMLEN_MAX = 20               # ワーム最大長
$script:SCORESTEP_INI = 5              # スコア加算初期値
$script:TIMER_MIN = 50                 # 落下速度の最速値（ms）
$script:IGARV_FACTOR = 5              # 初期ゴミ配置確率（/10）
$script:P_NAME_MAX = 16                # プレイヤー名最大長
$script:HMAX = 21                      # ハイスコア保存件数上限

# メッセージ関連
$script:MSGBUF_MAX = 30                # メッセージバッファ上限
$script:CURRENT_DAYS = 7              # 直近記録の保持日数
$script:MSGX_BASE = 62                 # メッセージウィンドウ左上X
$script:MSGY_BASE = 8                  # メッセージウィンドウ左上Y
$script:MSGX = 16                      # メッセージウィンドウ幅
$script:MSGY = 3                       # メッセージウィンドウ高さ（行数）
$script:MSG_MAX = 17                   # メッセージ番号の上限
$script:KIND_MAX = 15                  # バリエーション数上限

# 機能コード（aliasmap用）
$script:FN_NULL   = 0
$script:FN_LEFT   = 1                  # 左移動
$script:FN_RIGHT  = 2                  # 右移動
$script:FN_DROP   = 3                  # 落下
$script:FN_ROTA   = 4                  # 回転
$script:FN_PRAY   = 5                  # 祈り（ポリリス）
$script:FN_QUIT   = 6                  # 終了
$script:FN_PANIC  = 7                  # パニック（未使用）
$script:FN_INVOKE = 8                  # シェル起動（未使用）
$script:FN_REDRAW = 9                  # 画面再描画
$script:FN_BEEP   = 10                 # ベル音切替
$script:FN_LOGO   = 11                 # ロゴ表示切替
$script:FN_COLOUR = 12                 # カラー切替
$script:FN_JUMP   = 13                 # ジャンプモード切替

$script:BLANK = 0x20                   # 空白セル（スペース文字コード）

# ネクストブロックプレビューウィンドウ
$script:NEXTX_BASE  = 62              # プレビューウィンドウ左上X座標
$script:NEXTY_BASE  = 1              # プレビューウィンドウ左上Y座標
$script:NEXTX_INNER = 12             # 内側幅（文字数）
$script:NEXTY_INNER = 5              # 内側高さ（行数）
#endregion

#region 型定義
class Lith {
    [int[]]$X = @(0,0,0,0,0)
    [int[]]$Y = @(0,0,0,0,0)
    [int]$RotIndex
    [string]$Ch
    [int]$Attr
    [int]$TileCount
    [Lith] Clone() {
        $n = [Lith]::new()
        $n.X = $this.X.Clone(); $n.Y = $this.Y.Clone()
        $n.RotIndex = $this.RotIndex; $n.Ch = $this.Ch
        $n.Attr = $this.Attr; $n.TileCount = $this.TileCount
        return $n
    }
}
class RotInfo {
    [int[]]$DX = @(0,0,0,0,0)
    [int[]]$DY = @(0,0,0,0,0)
    [int]$NextRot
}
class IniInfo {
    [int[]]$X = @(0,0,0,0,0)
    [int[]]$Y = @(0,0,0,0,0)
    [int]$FirstRotIndex
    [string]$Ch
    [int]$Attr
    [int]$TileCount
    [string]$Name
}
#endregion

#region グローバル変数
# --- 起動パラメータから設定 ---
$script:wellwidth = $Width                 # ウェル幅（ブロック単位、後で×2して文字単位に変換）
$script:welldepth = $Depth                 # ウェル深さ
$script:genn = $BlockSize                  # ブロックサイズ指定（0=確率分布）
$script:inittimer = $Speed                 # 初期落下速度（ms）
$script:height = $Height                   # 初期ゴミ高さ
$script:istraining = [bool]$Training       # トレーニングモード
$script:isjump = [bool]$Jump              # ジャンプモード（瞬間落下の途中経過を表示しない）
$script:rotincr = if ($ReverseRotate) { 3 } else { 1 }  # 回転増分（1=時計, 3=反時計）
$script:coloured = -not [bool]$NoColor     # カラー表示フラグ
$script:logotype = -not [bool]$NoLogo      # ロゴ表示フラグ
$script:belsw = -not [bool]$NoBell         # ベル音フラグ
$script:scoreonly = [bool]$ShowScores      # スコア表示のみモード
$script:player = $Player                   # プレイヤー名
$script:filepath = $FilePath               # 設定ファイル検索パス
$script:newmoon = $NewMoon                 # 基準新月（ISO 8601形式、空=デフォルト）

# --- ウェル座標系（Initialize-Var2で計算） ---
$script:wellx_beg = 0                     # ウェル左端の画面X座標
$script:wellx_end = 0                     # ウェル右端の画面X座標
$script:well_top = 0                      # ウェル上端の画面Y座標
$script:well_bottom = 0                   # ウェル下端の画面Y座標

# --- ゲーム状態 ---
$script:scorestep = $script:SCORESTEP_INI  # 現在のスコア加算値（確率で増加）
$script:blocks = 0                         # 積んだブロック数
$script:erasedlines = 0                    # 消した行数
$script:lithn = 0                          # 現在のブロックタイル数
$script:looptimer = 0                      # 現在の落下速度（ms、ゲーム中に加速）
$script:moveone = 0                        # 移動回数カウンタ（evilpoint計算用）
$script:holypoint = 0                      # 善行ポイント（祈り成功率・ボーナスに影響）
$script:evilpoint = 0                      # 悪行ポイント（妨害発生率に影響）
$script:score = [long]0                    # 現在のスコア
$script:orgscore = [long]0                 # ボーナス加算前スコア
$script:pmoonidx = 0                          # 月齢指数（0=満月, 4=新月）
$script:fallen = $false                    # 瞬間落下済みフラグ
$script:wizard = $false                    # ウィザードモード
$script:gameRunning = $false               # ゲーム実行中フラグ
$script:moving = $null                     # 操作中のブロック（Lith型）

# --- マップ（フィールドデータ） ---
$script:map = $null                        # map[x, y] = 文字コード（BLANK=空, -1=全角後半）
$script:mapattr = $null                    # mapattr[x, y] = 色属性コード

# --- ワーム ---
$script:wormx = New-Object int[] 21        # ワーム各セグメントのX座標
$script:wormy = New-Object int[] 21        # ワーム各セグメントのY座標
$script:wormlen = 0                        # ワーム現在長（0=不在）
$script:wormhead = '%'                     # ワーム頭文字
$script:wormbody = '*'                     # ワーム胴体文字
$script:wormspilit = '+'                   # ワーム分裂片文字
$script:wormalcolour = 0                   # ワーム生存色（EWH: 白）
$script:wormcolour = 45                    # ワーム死亡色（EVPU: 紫）
$script:wormspcolour = 36                  # ワーム分裂片色（ETU: 水色）

# --- メッセージ ---
$script:msg = $null                        # msg[番号][バリエーション] = 3行文字列配列
$script:msgkind = New-Object int[] ($script:MSG_MAX + 1)  # 各番号のバリエーション数
$script:msgbuf = @()                       # 未表示メッセージ番号のバッファ
$script:lastmsgno = -1                     # 最後に表示したメッセージ番号
$script:hasStrings = $false                # strings.nlt読み込み済みフラグ

# --- 入力・ブロック定義 ---
$script:aliasmap = New-Object int[] 128    # キーコード→機能コード変換テーブル
$script:iniinfo = @()                      # ブロック初期パターン配列（29種）
$script:rotinfo = @()                      # 回転情報配列（91種）

# ブロック生成確率テーブル: N=1(5%), N=2(5%), N=3(10%), N=4(50%), N=5(30%)
$script:factn = @(5, 10, 20, 70, 100)
# 各タイル数の開始インデックス
$script:basinfo = @(0, 1, 2, 4, 11)
# 各タイル数のパターン数
$script:patinfo = @(1, 1, 2, 7, 18)

# --- ネクストブロックプレビュー ---
$script:nextlith   = $null           # 次のブロック（Lith型、パターン選択＋回転済み、ウェル配置前）
$script:nextn       = 0               # 次のブロックのタイル数
$script:shownext    = [bool]$NextBlock # プレビュー表示フラグ（既定=非表示）

# --- 月齢表示 ---
$script:moonage     = 0               # 月齢の概算値（0〜29）
$script:showmoon    = [bool]$PMoon    # 月齢表示フラグ（既定=非表示）
#endregion

#region 色制御
# ESCAPEシーケンス色コード → ConsoleColor マッピング
# 30番台=前景色、40番台=反転色（背景色+前景黒）
$script:ColorMap = @{
    0  = [ConsoleColor]::White        # リセット/白
    31 = [ConsoleColor]::Red          # ERE: 赤
    32 = [ConsoleColor]::Green        # EGR: 緑
    33 = [ConsoleColor]::Yellow       # EYE: 黄
    34 = [ConsoleColor]::Blue         # EBL: 青
    35 = [ConsoleColor]::Magenta      # EPU: 紫
    36 = [ConsoleColor]::Cyan         # ETU: 水色
    7  = [ConsoleColor]::White        # EVWH: 反転白
    41 = [ConsoleColor]::DarkRed      # EVRE: 反転赤
    42 = [ConsoleColor]::DarkGreen    # EVGR: 反転緑
    43 = [ConsoleColor]::DarkYellow   # EVYE: 反転黄
    44 = [ConsoleColor]::DarkBlue     # EVBL: 反転青
    45 = [ConsoleColor]::DarkMagenta  # EVPU: 反転紫
    46 = [ConsoleColor]::DarkCyan     # EVTU: 反転水色
}
# config.nlt用の色名→コード変換
$script:ColorNameMap = @{
    "ewh" = 0;  "ere" = 31; "egr" = 32; "eye" = 33
    "ebl" = 34; "epu" = 35; "etu" = 36
    "evwh" = 7;  "evre" = 41; "evgr" = 42; "evye" = 43
    "evbl" = 44; "evpu" = 45; "evtu" = 46
}

# C版 colour() 相当 — コンソール色を設定
function Set-GameColour {
    param([int]$Code)
    if (-not $script:coloured) { return }
    if ($Code -eq 0) {
        [Console]::ResetColor()
    } elseif ($script:ColorMap.ContainsKey($Code)) {
        if ($Code -ge 40 -or $Code -eq 7) {
            # 反転色: 背景色+前景黒
            [Console]::BackgroundColor = $script:ColorMap[$Code]
            [Console]::ForegroundColor = [ConsoleColor]::Black
        } else {
            # 通常色: 前景色のみ
            [Console]::ForegroundColor = $script:ColorMap[$Code]
        }
    }
}

# 色付き文字出力 — Set-GameColour + Write + ResetColor
function Write-ColorText {
    param([string]$Text, [int]$Attr)
    if ($script:coloured -and $script:ColorMap.ContainsKey($Attr)) {
        Set-GameColour $Attr
        [Console]::Write($Text)
        [Console]::ResetColor()
    } else {
        [Console]::Write($Text)
    }
}
#endregion

#region NLT暗号復号
# NLTファイルの暗号化データを復号
# パス1: 0xFFエスケープ復号 (0xFF 0xFF→0xFF, 0xFF xx→xx & 0x7F)
# パス2: XORチェーン復号（隣接バイト同士でXOR）
# 結果: Shift-JISプレーンテキスト文字列
function Invoke-NltDecrypt {
    param([byte[]]$Source)
    # パス1: エスケープシーケンス復号
    $unesc = [System.Collections.Generic.List[byte]]::new()
    $i = 0
    while ($i -lt $Source.Length) {
        if ($Source[$i] -eq 0xFF) {
            $i++
            if ($i -lt $Source.Length) {
                if ($Source[$i] -eq 0xFF) { $unesc.Add(0xFF) }
                else { $unesc.Add($Source[$i] -band 0x7F) }
            }
        } else {
            $unesc.Add($Source[$i])
        }
        $i++
    }
    # パス2: XORチェーン復号
    $bytes = $unesc.ToArray()
    for ($j = 0; $j -lt $bytes.Length - 1; $j++) {
        $bytes[$j] = $bytes[$j] -bxor $bytes[$j + 1]
    }
    if ($bytes.Length -ge 2) {
        return [System.Text.Encoding]::GetEncoding(932).GetString($bytes, 0, $bytes.Length - 1)
    }
    return ""
}

# NLTバイナリファイル読み込み
# バイト構造: [0x1A][length][data...][checksum]...
# checksum = データ部全バイトの合計（下位8ビット）
function Read-NltFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $allBytes = [System.IO.File]::ReadAllBytes($Path)
    $records = @()
    $pos = 1  # 先頭の0x1Aをスキップ
    while ($pos -lt $allBytes.Length) {
        if ($pos -ge $allBytes.Length) { break }
        $len = [int]$allBytes[$pos]
        $pos++
        if ($len -eq 0 -or ($pos + $len) -gt $allBytes.Length) { break }
        $data = $allBytes[$pos..($pos + $len - 1)]
        $pos += $len
        if ($pos -lt $allBytes.Length) {
            $checksum = [int]$allBytes[$pos]
            $pos++
            $sum = 0
            foreach ($b in $data) { $sum = ($sum + $b) -band 0xFF }
            if ($sum -ne $checksum) { continue }  # チェックサム不一致→スキップ
        }
        $dec = Invoke-NltDecrypt $data
        if ($dec) { $records += $dec }
    }
    return $records
}
#endregion

#region 設定ファイル読み込み
# config.nlt読み込み — 検索順序: FilePath → スクリプトディレクトリ
# 先頭バイト0x1Aで自動判定（NLT暗号化 / Shift-JISプレーンテキスト）
function Read-Config {
    $configPath = $null
    if ($script:filepath -and (Test-Path (Join-Path $script:filepath "config.nlt"))) {
        $configPath = Join-Path $script:filepath "config.nlt"
    } elseif (Test-Path (Join-Path $PSScriptRoot "config.nlt")) {
        $configPath = Join-Path $PSScriptRoot "config.nlt"
    }
    if (-not $configPath) { return }

    $allBytes = [System.IO.File]::ReadAllBytes($configPath)
    if ($allBytes.Length -eq 0) { return }

    if ($allBytes[0] -eq 0x1A) {
        $records = Read-NltFile $configPath             # NLT暗号化
    } else {
        $text = [System.Text.Encoding]::GetEncoding(932).GetString($allBytes)
        $records = $text -split "`r?`n"                 # Shift-JISプレーンテキスト
    }

    foreach ($line in $records) {
        $line = $line.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }

        if ($line -match '^(\w+)\s*=\s*(.+)$') {
            # ブロック外観設定: name=attr[,ch]
            Apply-BlockConfig $Matches[1].ToLower() $Matches[2]
        } elseif ($line -match '^alias\s+(.+)\s+(\w+)$') {
            # キーバインド設定: alias <key> <action>
            Apply-AliasConfig $Matches[1].Trim() $Matches[2].ToLower()
        } elseif ($line -match '^(beep|logo|colour|jump|next|moon)\s+(yes|no)$') {
            # フラグ設定: beep/logo/colour/jump/next/moon yes/no
            $val = ($Matches[2] -eq 'yes')
            switch ($Matches[1].ToLower()) {
                'beep'   { $script:belsw = $val }
                'logo'   { $script:logotype = $val }
                'colour' { $script:coloured = $val }
                'jump'   { $script:isjump = $val }
                'next'   { $script:shownext = $val }
                'moon'   { $script:showmoon = $val }
            }
        }
    }
}

# ブロック外観設定を反映 — 色はColorNameMapまたは数値、ワーム設定はwal/whd/wbd/wsp
function Apply-BlockConfig {
    param([string]$Name, [string]$Rest)
    $parts = $Rest -split ','
    $attrStr = $parts[0].Trim().ToLower()
    $ch = if ($parts.Length -ge 2) { $parts[1].Trim() } else { $null }

    # 色コード解決
    $attr = -1
    if ($script:ColorNameMap.ContainsKey($attrStr)) { $attr = $script:ColorNameMap[$attrStr] }
    elseif ($attrStr -match '^\d+$') { $attr = [int]$attrStr }

    # ワーム設定（特殊扱い）
    switch ($Name) {
        'wal' { if ($attr -ge 0) { $script:wormalcolour = $attr }; return }
        'whd' { if ($ch) { $script:wormhead = $ch[0] }; return }
        'wbd' { if ($ch) { $script:wormbody = $ch[0] }; return }
        'wsp' { if ($ch) { $script:wormspilit = $ch[0] }; return }
    }

    # ブロック設定: iniinfoのNameで検索
    for ($i = 0; $i -lt $script:iniinfo.Count; $i++) {
        if ($script:iniinfo[$i].Name -eq $Name) {
            if ($attr -ge 0) { $script:iniinfo[$i].Attr = $attr }
            if ($ch) {
                if ($ch.Length -ge 2) { $script:iniinfo[$i].Ch = $ch.Substring(0, 2) }
                else { $script:iniinfo[$i].Ch = $ch }
            }
            return
        }
    }
}

# キーバインド設定を反映 — ^X(Ctrl), \xHH(16進), \DDD(10進), 単一文字
function Apply-AliasConfig {
    param([string]$KeySpec, [string]$Action)
    $keyCode = -1
    if ($KeySpec -match '^\^(.)$') {
        $keyCode = [int][char]$Matches[1] - [int][char]'A' + 1   # ^A=1 ... ^Z=26
    } elseif ($KeySpec -match '^\\x([0-9a-fA-F]+)$') {
        $keyCode = [Convert]::ToInt32($Matches[1], 16)
    } elseif ($KeySpec -match '^\\(\d+)$') {
        $keyCode = [int]$Matches[1]
    } elseif ($KeySpec.Length -eq 1) {
        $keyCode = [int][char]$KeySpec
    }
    if ($keyCode -lt 0 -or $keyCode -ge 128) { return }

    $fn = switch ($Action) {
        'null'{0} 'left'{1} 'right'{2} 'drop'{3} 'rotate'{4} 'pray'{5} 'quit'{6}
        'redraw'{9} 'beep'{10} 'colour'{12} 'jump'{13} default{0}
    }
    $script:aliasmap[$keyCode] = $fn
}
#endregion

#region メッセージファイル読み込み
function Read-Strings {
    $stringsPath = $null
    if ($script:filepath -and (Test-Path (Join-Path $script:filepath "strings.nlt"))) {
        $stringsPath = Join-Path $script:filepath "strings.nlt"
    } elseif (Test-Path (Join-Path $PSScriptRoot "strings.nlt")) {
        $stringsPath = Join-Path $PSScriptRoot "strings.nlt"
    }
    if (-not $stringsPath) { $script:hasStrings = $false; return }
    # 先頭バイトで暗号化/プレーンテキストを判定
    $allBytes = [System.IO.File]::ReadAllBytes($stringsPath)
    if ($allBytes.Length -eq 0) { $script:hasStrings = $false; return }
    if ($allBytes[0] -eq 0x1A) {
        $records = Read-NltFile $stringsPath
    } else {
        $text = [System.Text.Encoding]::GetEncoding(932).GetString($allBytes)
        $records = $text -split "`r?`n"
    }
    $script:msg = @{}
    for ($m = 0; $m -le $script:MSG_MAX; $m++) { $script:msg[$m] = @(); $script:msgkind[$m] = 0 }
    $msgno = 0; $kind = 0; $lineNo = 0; $currentLines = @("","","")
    foreach ($line in $records) {
        if ($line.StartsWith('#')) { continue }
        if ($line.StartsWith('-')) {
            if ($lineNo -gt 0 -or $currentLines[0] -ne "") { Save-MsgVar $msgno $kind $currentLines; $kind++ }
            $script:msgkind[$msgno] = $kind; $msgno++; $kind = 0; $lineNo = 0; $currentLines = @("","","")
        } elseif ($line.StartsWith(',')) {
            Save-MsgVar $msgno $kind $currentLines; $kind++; $lineNo = 0; $currentLines = @("","","")
        } elseif ($line.StartsWith('>')) {
            if ($lineNo -lt $script:MSGY) {
                $text = $line.Substring(1)
                $dw = Get-DisplayWidth $text
                if ($dw -gt $script:MSGX) {
                    $out = ""; $cw = 0
                    foreach ($c in $text.ToCharArray()) {
                        $charW = if ([int]$c -gt 0xFF) { 2 } else { 1 }
                        if (($cw + $charW) -gt $script:MSGX) { break }
                        $out += $c; $cw += $charW
                    }
                    $text = $out
                }
                $currentLines[$lineNo] = $text; $lineNo++
            }
        }
    }
    if ($lineNo -gt 0 -or $currentLines[0] -ne "") { Save-MsgVar $msgno $kind $currentLines; $kind++ }
    if ($msgno -le $script:MSG_MAX) { $script:msgkind[$msgno] = $kind }
    $script:hasStrings = $true
}

function Save-MsgVar {
    param([int]$MsgNo, [int]$Kind, [string[]]$Lines)
    if ($MsgNo -gt $script:MSG_MAX -or $Kind -ge $script:KIND_MAX) { return }
    while ($script:msg[$MsgNo].Count -le $Kind) { $script:msg[$MsgNo] += ,@("","","") }
    $script:msg[$MsgNo][$Kind] = $Lines.Clone()
}
#endregion

#region データ初期化
function Initialize-BlockData {
    $script:iniinfo = @()
    $a = { param($x,$y,$r,$ch,$at,$tc,$nm)
        $o=[IniInfo]::new(); $o.X=$x; $o.Y=$y; $o.FirstRotIndex=$r
        $o.Ch=$ch; $o.Attr=$at; $o.TileCount=$tc; $o.Name=$nm; $o
    }
    # N=1
    $script:iniinfo += (& $a @(0,0,0,0,0) @(0,0,0,0,0) 0 "[]" 33 1 "o1")
    # N=2
    $script:iniinfo += (& $a @(0,1,0,0,0) @(0,0,0,0,0) 1 "[]" 35 2 "i2")
    # N=3
    $script:iniinfo += (& $a @(0,1,2,0,0) @(0,0,0,0,0) 3 "[]" 34 3 "i3")
    $script:iniinfo += (& $a @(0,1,1,0,0) @(1,1,0,0,0) 5 "[]" 31 3 "l3")
    # N=4
    $script:iniinfo += (& $a @(0,1,2,3,0) @(0,0,0,0,0) 9  "[]" 32 4 "i4")
    $script:iniinfo += (& $a @(0,1,2,2,0) @(1,1,1,0,0) 11 "[]" 31 4 "j4")
    $script:iniinfo += (& $a @(0,0,1,2,0) @(0,1,1,1,0) 15 "[]" 34 4 "j4r")
    $script:iniinfo += (& $a @(0,1,1,2,0) @(1,1,0,1,0) 19 "[]" 35 4 "t4")
    $script:iniinfo += (& $a @(0,1,0,1,0) @(1,1,0,0,0) 23 "[]" 33 4 "o4")
    $script:iniinfo += (& $a @(0,1,1,2,0) @(1,1,0,0,0) 24 "[]" 0  4 "z4")
    $script:iniinfo += (& $a @(0,1,1,2,0) @(0,0,1,1,0) 26 "[]" 36 4 "z4r")
    # N=5
    $script:iniinfo += (& $a @(0,0,0,0,0) @(0,1,2,3,4)     28 "[]" 46 5 "i5")
    $script:iniinfo += (& $a @(0,1,1,1,2) @(0,1,0,-1,0)    30 "[]" 45 5 "x5")
    $script:iniinfo += (& $a @(0,1,1,1,2) @(0,0,-1,-2,0)   31 "[]" 41 5 "t5")
    $script:iniinfo += (& $a @(0,0,1,2,2) @(0,-1,-1,0,-1)  35 "[]" 42 5 "u5")
    $script:iniinfo += (& $a @(0,0,1,1,2) @(0,-1,-1,-2,-2) 39 "[]" 7  5 "w5")
    $script:iniinfo += (& $a @(0,0,0,1,2) @(0,-1,-2,-2,-2) 43 "[]" 45 5 "l5")
    $script:iniinfo += (& $a @(0,1,1,1,2) @(0,0,-1,-2,-2)  47 "[]" 43 5 "z5")
    $script:iniinfo += (& $a @(0,1,1,1,2) @(0,2,1,0,2)     49 "[]" 46 5 "z5r")
    $script:iniinfo += (& $a @(0,1,1,1,1) @(0,3,2,1,0)     51 "[]" 42 5 "j5")
    $script:iniinfo += (& $a @(0,0,0,0,1) @(0,-1,-2,-3,-3) 55 "[]" 7  5 "j5r")
    $script:iniinfo += (& $a @(0,0,1,1,1) @(0,-1,2,1,0)    59 "[]" 41 5 "n5")
    $script:iniinfo += (& $a @(0,0,0,1,1) @(0,-1,-2,-2,-3) 63 "[]" 44 5 "n5r")
    $script:iniinfo += (& $a @(0,1,1,1,1) @(0,1,0,-1,-2)   67 "[]" 43 5 "y5")
    $script:iniinfo += (& $a @(0,0,0,0,1) @(0,-1,-2,-3,-1) 71 "[]" 45 5 "y5r")
    $script:iniinfo += (& $a @(0,1,1,1,2) @(0,1,0,-1,1)    75 "[]" 42 5 "f5")
    $script:iniinfo += (& $a @(0,1,1,1,2) @(0,0,-1,-2,-1)  79 "[]" 46 5 "f5r")
    $script:iniinfo += (& $a @(0,0,0,1,1) @(0,-1,-2,0,-1)  83 "[]" 7  5 "p5")
    $script:iniinfo += (& $a @(0,0,1,1,1) @(0,-1,0,-1,-2)  87 "[]" 45 5 "p5r")
}

function Initialize-RotData {
    $script:rotinfo = @()
    $r = { param($dx,$dy,$n) $o=[RotInfo]::new(); $o.DX=$dx; $o.DY=$dy; $o.NextRot=$n; $o }
    $script:rotinfo += (& $r @(0,0,0,0,0) @(0,0,0,0,0) 0)   #0 o1
    $script:rotinfo += (& $r @(1,0,0,0,0) @(1,0,0,0,0) 2)   #1 i2(0)
    $script:rotinfo += (& $r @(-1,0,1,0,0) @(-1,0,1,0,0) 1) #2 i2(1)
    $script:rotinfo += (& $r @(1,0,-1,0,0) @(1,0,-1,0,0) 4) #3 i3(0)
    $script:rotinfo += (& $r @(-1,0,1,0,0) @(-1,0,1,0,0) 3) #4 i3(1)
    $script:rotinfo += (& $r @(1,0,-1,0,0) @(0,-1,0,0,0) 6) #5 l3(0)
    $script:rotinfo += (& $r @(0,-1,0,0,0) @(-1,0,1,0,0) 7) #6 l3(1)
    $script:rotinfo += (& $r @(-1,0,1,0,0) @(0,1,0,0,0) 8)  #7 l3(2)
    $script:rotinfo += (& $r @(0,1,0,0,0) @(1,0,-1,0,0) 5)  #8 l3(3)
    $script:rotinfo += (& $r @(2,1,0,-1,0) @(2,1,0,-1,0) 10)  #9 i4(0)
    $script:rotinfo += (& $r @(-2,-1,0,1,0) @(-2,-1,0,1,0) 9) #10 i4(1)
    $script:rotinfo += (& $r @(1,0,-1,-2,0) @(1,0,-1,0,0) 12) #11 j4(0)
    $script:rotinfo += (& $r @(1,0,-1,0,0) @(-2,-1,0,1,0) 13) #12 j4(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,0) @(0,1,2,1,0) 14)  #13 j4(2)
    $script:rotinfo += (& $r @(0,1,2,1,0) @(1,0,-1,-2,0) 11)  #14 j4(3)
    $script:rotinfo += (& $r @(1,2,1,0,0) @(2,1,0,-1,0) 16)   #15 j4r(0)
    $script:rotinfo += (& $r @(1,0,-1,-2,0) @(-1,-2,-1,0,0) 17) #16 j4r(1)
    $script:rotinfo += (& $r @(0,-1,0,1,0) @(-1,0,1,2,0) 18) #17 j4r(2)
    $script:rotinfo += (& $r @(-2,-1,0,1,0) @(0,1,0,-1,0) 15) #18 j4r(3)
    $script:rotinfo += (& $r @(1,0,-1,-1,0) @(1,0,1,-1,0) 20) #19 t4(0)
    $script:rotinfo += (& $r @(1,0,1,-1,0) @(-2,-1,0,0,0) 21) #20 t4(1)
    $script:rotinfo += (& $r @(-1,0,1,1,0) @(0,1,0,2,0) 22)   #21 t4(2)
    $script:rotinfo += (& $r @(-1,0,-1,1,0) @(1,0,-1,-1,0) 19) #22 t4(3)
    $script:rotinfo += (& $r @(0,0,0,0,0) @(0,0,0,0,0) 23)    #23 o4
    $script:rotinfo += (& $r @(0,-1,0,-1,0) @(-1,0,1,2,0) 25) #24 z4(0)
    $script:rotinfo += (& $r @(0,1,0,1,0) @(1,0,-1,-2,0) 24)  #25 z4(1)
    $script:rotinfo += (& $r @(1,0,1,0,0) @(2,1,0,-1,0) 27)   #26 z4r(0)
    $script:rotinfo += (& $r @(-1,0,-1,0,0) @(-2,-1,0,1,0) 26) #27 z4r(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,2) @(2,1,0,-1,-2) 29) #28 i5(0)
    $script:rotinfo += (& $r @(2,1,0,-1,-2) @(-2,-1,0,1,2) 28) #29 i5(1)
    $script:rotinfo += (& $r @(0,0,0,0,0) @(0,0,0,0,0) 30)    #30 x5
    $script:rotinfo += (& $r @(2,1,0,-1,0) @(0,-1,0,1,-2) 32)  #31 t5(0)
    $script:rotinfo += (& $r @(0,-1,0,1,-2) @(-2,-1,0,1,0) 33) #32 t5(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,0) @(0,1,0,-1,2) 34)  #33 t5(2)
    $script:rotinfo += (& $r @(0,1,0,-1,2) @(2,1,0,-1,0) 31)   #34 t5(3)
    $script:rotinfo += (& $r @(1,0,-1,-1,-2) @(1,2,1,-1,0) 36) #35 u5(0)
    $script:rotinfo += (& $r @(1,2,1,-1,0) @(-1,0,1,1,2) 37)   #36 u5(1)
    $script:rotinfo += (& $r @(-1,0,1,1,2) @(-1,-2,-1,1,0) 38) #37 u5(2)
    $script:rotinfo += (& $r @(-1,-2,-1,1,0) @(1,0,-1,-1,-2) 35) #38 u5(3)
    $script:rotinfo += (& $r @(2,1,0,-1,-2) @(0,1,0,1,0) 40)   #39 w5(0)
    $script:rotinfo += (& $r @(0,1,0,1,0) @(-2,-1,0,1,2) 41)   #40 w5(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,2) @(0,-1,0,-1,0) 42) #41 w5(2)
    $script:rotinfo += (& $r @(0,-1,0,-1,0) @(2,1,0,-1,-2) 39) #42 w5(3)
    $script:rotinfo += (& $r @(2,1,0,-1,-2) @(0,1,2,1,0) 44)   #43 l5(0)
    $script:rotinfo += (& $r @(0,1,2,1,0) @(-2,-1,0,1,2) 45)   #44 l5(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,2) @(0,-1,-2,-1,0) 46) #45 l5(2)
    $script:rotinfo += (& $r @(0,-1,-2,-1,0) @(2,1,0,-1,-2) 43) #46 l5(3)
    $script:rotinfo += (& $r @(2,1,0,-1,-2) @(0,-1,0,1,0) 48)  #47 z5(0)
    $script:rotinfo += (& $r @(-2,-1,0,1,2) @(0,1,0,-1,0) 47)  #48 z5(1)
    $script:rotinfo += (& $r @(0,1,0,-1,0) @(2,-1,0,1,-2) 50)  #49 z5r(0)
    $script:rotinfo += (& $r @(0,-1,0,1,0) @(-2,1,0,-1,2) 49)  #50 z5r(1)
    $script:rotinfo += (& $r @(0,2,1,0,-1) @(2,-2,-1,0,1) 52)  #51 j5(0)
    $script:rotinfo += (& $r @(2,-2,-1,0,1) @(1,-1,0,1,2) 53)  #52 j5(1)
    $script:rotinfo += (& $r @(1,-1,0,1,2) @(-2,2,1,0,-1) 54)  #53 j5(2)
    $script:rotinfo += (& $r @(-3,1,0,-1,-2) @(-1,1,0,-1,-2) 51) #54 j5(3)
    $script:rotinfo += (& $r @(1,0,-1,-2,-3) @(-1,0,1,2,1) 56) #55 j5r(0)
    $script:rotinfo += (& $r @(-1,0,1,2,1) @(-2,-1,0,1,2) 57)  #56 j5r(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,2) @(1,0,-1,-2,-1) 58) #57 j5r(2)
    $script:rotinfo += (& $r @(2,1,0,-1,0) @(2,1,0,-1,-2) 55)  #58 j5r(3)
    $script:rotinfo += (& $r @(0,-1,1,0,-1) @(1,2,-2,-1,0) 60) #59 n5(0)
    $script:rotinfo += (& $r @(1,2,-2,-1,0) @(0,1,-1,0,1) 61)  #60 n5(1)
    $script:rotinfo += (& $r @(0,1,-1,0,1) @(-1,-2,2,1,0) 62)  #61 n5(2)
    $script:rotinfo += (& $r @(-1,-2,2,1,0) @(0,-1,1,0,-1) 59) #62 n5(3)
    $script:rotinfo += (& $r @(2,1,0,-1,-2) @(-1,0,1,0,1) 64)  #63 n5r(0)
    $script:rotinfo += (& $r @(-1,0,1,0,1) @(-2,-1,0,1,2) 65)  #64 n5r(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,2) @(1,0,-1,0,-1) 66) #65 n5r(2)
    $script:rotinfo += (& $r @(1,0,-1,0,-1) @(2,1,0,-1,-2) 63) #66 n5r(3)
    $script:rotinfo += (& $r @(2,2,1,0,-1) @(0,-2,-1,0,1) 68)  #67 y5(0)
    $script:rotinfo += (& $r @(0,-2,-1,0,1) @(-1,-1,0,1,2) 69) #68 y5(1)
    $script:rotinfo += (& $r @(-1,-1,0,1,2) @(0,2,1,0,-1) 70)  #69 y5(2)
    $script:rotinfo += (& $r @(-1,1,0,-1,-2) @(1,1,0,-1,-2) 67) #70 y5(3)
    $script:rotinfo += (& $r @(1,0,-1,-2,-1) @(-1,0,1,2,-1) 72) #71 y5r(0)
    $script:rotinfo += (& $r @(-1,0,1,2,-1) @(-2,-1,0,1,0) 73) #72 y5r(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,0) @(1,0,-1,-2,1) 74) #73 y5r(2)
    $script:rotinfo += (& $r @(2,1,0,-1,2) @(2,1,0,-1,0) 71)   #74 y5r(3)
    $script:rotinfo += (& $r @(1,1,0,-1,0) @(1,-1,0,1,-2) 76)  #75 f5(0)
    $script:rotinfo += (& $r @(1,-1,0,1,-2) @(-1,-1,0,1,0) 77) #76 f5(1)
    $script:rotinfo += (& $r @(-1,-1,0,1,0) @(-1,1,0,-1,2) 78) #77 f5(2)
    $script:rotinfo += (& $r @(-1,1,0,-1,2) @(1,1,0,-1,0) 75)  #78 f5(3)
    $script:rotinfo += (& $r @(2,1,0,-1,-1) @(0,-1,0,1,-1) 80) #79 f5r(0)
    $script:rotinfo += (& $r @(0,-1,0,1,-1) @(-2,-1,0,1,1) 81) #80 f5r(1)
    $script:rotinfo += (& $r @(-2,-1,0,1,1) @(0,1,0,-1,1) 82)  #81 f5r(2)
    $script:rotinfo += (& $r @(0,1,0,-1,1) @(2,1,0,-1,-1) 79)  #82 f5r(3)
    $script:rotinfo += (& $r @(1,0,-1,0,-1) @(-1,0,1,-2,-1) 84) #83 p5(0)
    $script:rotinfo += (& $r @(0,1,2,-1,0) @(-1,0,1,0,1) 85)   #84 p5(1)
    $script:rotinfo += (& $r @(-1,0,1,0,1) @(1,0,-1,2,1) 86)   #85 p5(2)
    $script:rotinfo += (& $r @(0,-1,-2,1,0) @(1,0,-1,0,-1) 83) #86 p5(3)
    $script:rotinfo += (& $r @(1,0,0,-1,-2) @(0,1,-1,0,1) 88)  #87 p5r(0)
    $script:rotinfo += (& $r @(0,1,-1,0,1) @(-2,-1,-1,0,1) 89) #88 p5r(1)
    $script:rotinfo += (& $r @(-1,0,0,1,2) @(0,-1,1,0,-1) 90)  #89 p5r(2)
    $script:rotinfo += (& $r @(0,-1,1,0,-1) @(2,1,1,0,-1) 87)  #90 p5r(3)
}
#endregion

#region 回転適用
# ブロックに回転情報を1ステップ分適用（C版 rrotlith 相当）
# DX は×2（文字単位）で適用、NextRotで次の回転インデックスへ遷移
function Invoke-RRotLith {
    param([ref]$LithRef)
    $lith = $LithRef.Value
    $rot = $script:rotinfo[$lith.RotIndex]
    for ($i = 0; $i -lt $lith.TileCount; $i++) {
        $lith.X[$i] += $rot.DX[$i] * 2   # X座標は文字単位なので×2
        $lith.Y[$i] += $rot.DY[$i]
    }
    $lith.RotIndex = $rot.NextRot
}
#endregion

#region 画面描画
# タイル1個を描画 — ゲーム座標→画面座標変換（Y軸反転: screenY = well_bottom - gameY）
function Draw-Tile {
    param([int]$GameX, [int]$GameY, [string]$Ch, [int]$Attr)
    $sx = $script:wellx_beg + $GameX
    $sy = $script:well_bottom - $GameY
    if ($sx -ge 0 -and $sy -ge 0 -and $sx -lt $script:SCR_X -and $sy -lt 24) {
        [Console]::SetCursorPosition($sx, $sy)
        Write-ColorText $Ch $Attr
    }
}

# タイル1個を消去（2文字分の空白）
function Erase-Tile {
    param([int]$GameX, [int]$GameY)
    $sx = $script:wellx_beg + $GameX
    $sy = $script:well_bottom - $GameY
    if ($sx -ge 0 -and $sy -ge 0 -and $sx -lt $script:SCR_X -and $sy -lt 24) {
        [Console]::SetCursorPosition($sx, $sy)
        [Console]::Write("  ")
    }
}

# ブロック全体を描画
function Draw-Lith {
    param([Lith]$L)
    for ($i = 0; $i -lt $L.TileCount; $i++) { Draw-Tile $L.X[$i] $L.Y[$i] $L.Ch $L.Attr }
}

# ブロック全体を消去
function Erase-Lith {
    param([Lith]$L)
    for ($i = 0; $i -lt $L.TileCount; $i++) { Erase-Tile $L.X[$i] $L.Y[$i] }
}
# フィールド上の固定ブロック（ガベージ）を再描画
# map[x+1]==-1 なら全角1文字、それ以外はASCII 2文字
function Draw-Garvages {
    param([int]$StartY = 0)
    for ($y = $StartY; $y -lt $script:welldepth; $y++) {
        for ($x = 0; $x -lt $script:wellwidth; $x += 2) {
            $sx = $script:wellx_beg + $x
            $sy = $script:well_bottom - $y
            [Console]::SetCursorPosition($sx, $sy)
            if ($script:map[$x, $y] -ne $script:BLANK -and $script:map[$x, $y] -ne 0) {
                if ($script:map[($x + 1), $y] -eq -1) {
                    $ch = [string][char]$script:map[$x, $y]
                    Write-ColorText $ch $script:mapattr[$x, $y]
                } else {
                    $c1 = [char]$script:map[$x, $y]
                    $c2 = [char]$script:map[($x + 1), $y]
                    Write-ColorText "$c1$c2" $script:mapattr[$x, $y]
                }
            } else {
                [Console]::Write("  ")
            }
        }
    }
}

# ウェルのフレーム描画: 左壁"|", 右壁"|", 底面"+---...---+"
function Draw-Frame {
    for ($y = $script:well_top; $y -le $script:well_bottom; $y++) {
        [Console]::SetCursorPosition($script:wellx_beg - 1, $y)
        [Console]::Write("|")
        [Console]::SetCursorPosition($script:wellx_end, $y)
        [Console]::Write("|")
    }
    [Console]::SetCursorPosition($script:wellx_beg - 1, $script:well_bottom + 1)
    [Console]::Write("+" + ("-" * $script:wellwidth) + "+")
}

# スコア情報を画面右側に表示
function Show-Score {
    $bx = $script:MSGX_BASE
    if ($script:showmoon) {
        [Console]::SetCursorPosition($bx, 14)
        [Console]::Write("Aprox. Phase : {0:D2}" -f $script:moonage)
    }
    if ($script:istraining) {
        [Console]::SetCursorPosition($bx, 15)
        [Console]::Write("* training mode *")
    }
    [Console]::SetCursorPosition($bx, 16)
    [Console]::Write("holy point : {0,-4}" -f $script:holypoint)
    [Console]::SetCursorPosition($bx, 17)
    [Console]::Write("evil point : {0,-4}" -f $script:evilpoint)
    [Console]::SetCursorPosition($bx, 19)
    [Console]::Write("score  : {0,-7}" -f $script:score)
    [Console]::SetCursorPosition($bx, 20)
    [Console]::Write("blocks : {0,-4}" -f $script:blocks)
    [Console]::SetCursorPosition($bx, 21)
    [Console]::Write("lines  : {0,-4}" -f $script:erasedlines)
}

# メッセージウィンドウ枠描画（16×3文字）
function Draw-MsgWindow {
    if (-not $script:hasStrings -or $script:istraining) { return }
    $bx = $script:MSGX_BASE
    $by = $script:MSGY_BASE
    [Console]::SetCursorPosition($bx, $by)
    [Console]::Write("+" + ("-" * $script:MSGX) + "+")
    for ($row = 1; $row -le $script:MSGY; $row++) {
        [Console]::SetCursorPosition($bx, $by + $row)
        [Console]::Write("|" + (" " * $script:MSGX) + "|")
    }
    [Console]::SetCursorPosition($bx, $by + $script:MSGY + 1)
    [Console]::Write("+" + ("-" * $script:MSGX) + "+")
}

# ネクストブロックプレビューウィンドウの描画
function Draw-NextPreview {
    if (-not $script:shownext) { return }

    $bx = $script:NEXTX_BASE     # 62
    $by = $script:NEXTY_BASE     # 0
    $iw = $script:NEXTX_INNER    # 12
    $ih = $script:NEXTY_INNER    # 5

    # --- 枠描画 + 内側クリア ---
    [Console]::SetCursorPosition($bx, $by)
    [Console]::Write("+" + ("-" * $iw) + "+")
    for ($row = 1; $row -le $ih; $row++) {
        [Console]::SetCursorPosition($bx, $by + $row)
        [Console]::Write("|" + (" " * $iw) + "|")
    }
    [Console]::SetCursorPosition($bx, $by + $ih + 1)
    [Console]::Write("+" + ("-" * $iw) + "+")

    # nextblock が未生成の場合は枠のみ
    if ($null -eq $script:nextlith) { return }

    # --- "NEXT" ラベル描画 ---
    [Console]::SetCursorPosition($bx + 1, $by + 1)
    [Console]::Write("NEXT")

    # --- ブロック座標の正規化 ---
    $lith = $script:nextlith
    $ln = $lith.TileCount
    $xs = $lith.X[0..($ln-1)]
    $ys = $lith.Y[0..($ln-1)]
    $minX = ($xs | Measure-Object -Minimum).Minimum
    $maxX = ($xs | Measure-Object -Maximum).Maximum
    $minY = ($ys | Measure-Object -Minimum).Minimum
    $maxY = ($ys | Measure-Object -Maximum).Maximum

    # ブロック寸法（文字単位: 各タイルは2文字幅）
    $blockW = $maxX - $minX + 2    # +2 はタイル幅（Chの2文字分）
    $blockH = $maxY - $minY + 1

    # 描画可能高さ: ブロック高さが5の場合はラベル行も使用
    $drawH = if ($blockH -ge 5) { $ih } else { $ih - 1 }
    $drawStartY = if ($blockH -ge 5) { $by + 1 } else { $by + 2 }

    # 内側領域の中央にオフセット計算
    $offsetX = $bx + 1 + [Math]::Floor(($iw - $blockW) / 2)
    $offsetY = $drawStartY + [Math]::Floor(($drawH - [Math]::Min($blockH, $drawH)) / 2)

    # --- タイル描画 ---
    for ($i = 0; $i -lt $ln; $i++) {
        $nx = $lith.X[$i] - $minX
        $ny = $maxY - $lith.Y[$i]    # Y軸反転（画面座標は下向き正）

        # クリッピング
        if ($ny -ge $drawH) { continue }

        $sx = $offsetX + $nx
        $sy = $offsetY + $ny

        if ($sx -ge 0 -and $sy -ge 0 -and ($sx + 1) -lt $script:SCR_X -and $sy -lt 24) {
            [Console]::SetCursorPosition($sx, $sy)
            Write-ColorText $lith.Ch $lith.Attr
        }
    }
}

# プレビューウィンドウ内側クリア
function Erase-NextPreview {
    $bx = $script:NEXTX_BASE + 1
    $by = $script:NEXTY_BASE + 1
    $blank = " " * $script:NEXTX_INNER
    for ($row = 0; $row -lt $script:NEXTY_INNER; $row++) {
        [Console]::SetCursorPosition($bx, $by + $row)
        [Console]::Write($blank)
    }
}

# 文字列の表示幅を計算（全角=2, 半角=1）
function Get-DisplayWidth {
    param([string]$Str)
    $w = 0
    foreach ($c in $Str.ToCharArray()) {
        if ([int]$c -gt 0xFF) { $w += 2 } else { $w++ }
    }
    return $w
}

# メッセージウィンドウにメッセージを表示（最大3行）
# 表示幅ベースでパディング・切り詰めを行う
function Show-Message {
    param([string[]]$Lines)
    if (-not $script:hasStrings -or $script:istraining) { return }
    $bx = $script:MSGX_BASE + 1
    $by = $script:MSGY_BASE + 1
    for ($row = 0; $row -lt $script:MSGY; $row++) {
        [Console]::SetCursorPosition($bx, $by + $row)
        $text = if ($row -lt $Lines.Count) { $Lines[$row] } else { "" }
        $dw = Get-DisplayWidth $text
        if ($dw -gt $script:MSGX) {
            # 表示幅がボックス幅を超える場合は切り詰め
            $out = ""
            $cw = 0
            foreach ($c in $text.ToCharArray()) {
                $charW = if ([int]$c -gt 0xFF) { 2 } else { 1 }
                if (($cw + $charW) -gt $script:MSGX) { break }
                $out += $c
                $cw += $charW
            }
            [Console]::Write($out)
            $pad = $script:MSGX - $cw
            if ($pad -gt 0) { [Console]::Write(" " * $pad) }
        } else {
            [Console]::Write($text)
            $pad = $script:MSGX - $dw
            if ($pad -gt 0) { [Console]::Write(" " * $pad) }
        }
    }
}
# PnLITHロゴをASCIIアートで表示
# Pn(水色/36), LI(緑/32), TH(緑/32), クレジット(赤/31)
function Draw-Logo {
    if (-not $script:logotype) { return }
    # Pn: 行0〜7
    $pn = @(
        "                 ",
        "  #####          ",
        "  ##   ##        ",
        "  ##   ## ###### ",
        "  #####   ##   ##",
        "  ##      ##   ##",
        "  ##      ##   ##",
        "                 "
    )
    for ($i = 0; $i -lt $pn.Count; $i++) {
        [Console]::SetCursorPosition(0, 1 + $i)
        Write-ColorText $pn[$i] 36
    }
    # LI: 行9〜13
    $li = @(
        "  ##       ##### ",
        "  ##         ##  ",
        "  ##         ##  ",
        "  ##         ##  ",
        "  #######  ##### "
    )
    for ($i = 0; $i -lt $li.Count; $i++) {
        [Console]::SetCursorPosition(0, 9 + $i)
        Write-ColorText $li[$i] 32
    }
    # TH: 行15〜19
    $th = @(
        "  ####### ##   ## ",
        "    ##    ##   ## ",
        "    ##    ####### ",
        "    ##    ##   ## ",
        "    ##    ##   ## "
    )
    for ($i = 0; $i -lt $th.Count; $i++) {
        [Console]::SetCursorPosition(0, 15 + $i)
        Write-ColorText $th[$i] 32
    }
    # クレジット
    [Console]::SetCursorPosition(2, 21)
    Write-ColorText "Based on 'NLITH'" 31
    [Console]::SetCursorPosition(2, 22)
    Write-ColorText " by Taroh" 31
}

# 画面全体の完全再描画 — 全角文字のクリア残り対策で明示的に空白上書き
function Redraw-Screen {
    [Console]::SetCursorPosition(0, 0)
    $blank = " " * [Console]::WindowWidth
    for ($row = 0; $row -lt [Console]::WindowHeight; $row++) {
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write($blank)
    }
    [Console]::SetCursorPosition(0, 0)
    Draw-Logo
    Draw-Frame
    Draw-MsgWindow
    Draw-Garvages 0
    if ($script:moving) { Draw-Lith $script:moving }
    if ($script:wormlen -gt 0) { Draw-Worm }
    Show-Score
    if ($script:shownext) { Draw-NextPreview }
}
#endregion

#region ブロック操作
# 衝突判定（C版 collision 相当）
# 各タイルの2文字幅（tx, tx+1）についてウェル境界とマップ内容をチェック
function Test-Collision {
    param([Lith]$Test)
    for ($i = 0; $i -lt $Test.TileCount; $i++) {
        $tx = $Test.X[$i]
        $ty = $Test.Y[$i]
        if ($ty -lt 0 -or $ty -ge $script:welldepth) { return $true }
        if ($tx -lt 0 -or ($tx + 1) -ge $script:wellwidth) { return $true }
        if ($script:map[$tx, $ty] -ne $script:BLANK -and $script:map[$tx, $ty] -ne 0) { return $true }
        if ($script:map[($tx+1), $ty] -ne $script:BLANK -and $script:map[($tx+1), $ty] -ne 0) { return $true }
    }
    return $false
}

# ネクストブロックのパターン選択＋ランダム回転（ウェル配置なし）
# $script:nextlith に Lith を格納する
function New-SelectNextLith {
    # タイル数決定（New-GeneLith と同一ロジック）
    if ($script:istraining) { $ln = $script:LITHN_DEF }
    elseif ($script:genn -gt 0) { $ln = $script:genn }
    else {
        $rv = Get-Random -Minimum 0 -Maximum 100
        for ($n = 0; $n -lt 5; $n++) { if ($rv -lt $script:factn[$n]) { $ln = $n + 1; break } }
    }
    $script:nextn = $ln

    # パターン選択
    $pat = $script:basinfo[$ln - 1] + (Get-Random -Minimum 0 -Maximum $script:patinfo[$ln - 1])
    $ini = $script:iniinfo[$pat]

    # Lith 初期化
    $lith = [Lith]::new()
    for ($i = 0; $i -lt $ln; $i++) {
        $lith.X[$i] = $ini.X[$i] * 2   # ブロック単位→文字単位
        $lith.Y[$i] = $ini.Y[$i]
    }
    $lith.RotIndex = $ini.FirstRotIndex
    $lith.Ch = $ini.Ch
    $lith.Attr = $ini.Attr
    $lith.TileCount = $ln

    # ランダム回転（0〜3回）
    $rc = Get-Random -Minimum 0 -Maximum 4
    for ($i = 0; $i -lt $rc; $i++) { Invoke-RRotLith ([ref]$lith) }

    $script:nextlith = $lith
}

# ブロック生成（C版 genelith 相当）
# nextblock からブロックを取り出してウェルに配置、次のnextblockを事前生成
function New-GeneLith {
    for ($retry = 0; $retry -lt 5; $retry++) {
        # nextblock が未生成なら生成（ゲーム開始直後）
        if ($null -eq $script:nextlith) {
            New-SelectNextLith
        }

        # nextblock からブロック情報を取得
        $ln = $script:nextlith.TileCount
        $script:lithn = $ln
        $script:moving = $script:nextlith.Clone()

        # 初期位置計算（ウェル上部にセンタリング配置）
        $xs = $script:moving.X[0..($ln-1)]
        $ys = $script:moving.Y[0..($ln-1)]
        $maxX = ($xs | Measure-Object -Maximum).Maximum
        $minX = ($xs | Measure-Object -Minimum).Minimum
        $maxY = ($ys | Measure-Object -Maximum).Maximum
        $biasY = $script:welldepth - $maxY - 1
        $hw = [Math]::Floor($script:wellwidth / 2)
        $sp = [Math]::Floor(($maxX - $minX) / 2)
        $rng = [Math]::Max(1, $hw - $sp)
        $biasX = (Get-Random -Minimum 0 -Maximum $rng) * 2 - $minX
        for ($i = 0; $i -lt $ln; $i++) {
            $script:moving.X[$i] += $biasX
            $script:moving.Y[$i] += $biasY
        }

        if (-not (Test-Collision $script:moving)) {
            Draw-Lith $script:moving

            # 次のブロックを事前生成 + プレビュー更新
            New-SelectNextLith
            if ($script:shownext) { Draw-NextPreview }

            return $true
        }

        # 衝突時: nextblock を破棄して新しいブロックで再試行
        $script:nextlith = $null
    }
    return $false  # 5回失敗 → ゲームオーバー
}

# ブロック1段落下（C版 droplith 相当）
# IsDraw=$true: 描画あり（通常落下）, $false: 描画なし（jumpモード中）
# 戻り値: $true=落下成功, $false=着地
function Invoke-DropLith {
    param([bool]$IsDraw = $true)
    $test = $script:moving.Clone()
    for ($i = 0; $i -lt $test.TileCount; $i++) { $test.Y[$i]-- }
    if (Test-Collision $test) { return $false }
    if ($IsDraw) { Erase-Lith $script:moving }
    $script:moving = $test
    if ($IsDraw) { Draw-Lith $script:moving }
    return $true
}

# ブロック左右移動（C版 swinglith 相当）
# Vector: -2(左) or +2(右)
# Evil判定で確率的に反対方向に移動することがある
function Invoke-SwingLith {
    param([int]$Vector)
    $evil = 0
    if (Test-IsEvil 100) {
        $evil = ((Get-Random -Minimum 0 -Maximum 2) * 2 - 1) * 2
        Invoke-DispStrings 6    # evil移動メッセージ
    }
    $after = $script:moving.Clone()
    for ($i = 0; $i -lt $after.TileCount; $i++) { $after.X[$i] += $Vector + $evil }
    if (Test-Collision $after) { return $false }

    Erase-Lith $script:moving
    $script:moving = $after
    Draw-Lith $script:moving

    # 軒下チェック: 下にブロックがあればボーナス
    $underEaves = $false
    for ($i = 0; $i -lt $script:moving.TileCount; $i++) {
        $by2 = $script:moving.Y[$i] - 1
        if ($by2 -ge 0) {
            $bx2 = $script:moving.X[$i]
            if (($script:map[$bx2,$by2] -ne $script:BLANK -and $script:map[$bx2,$by2] -ne 0) -or
                ($script:map[($bx2+1),$by2] -ne $script:BLANK -and $script:map[($bx2+1),$by2] -ne 0)) {
                if (-not (Test-IsWormAliveCell $bx2 $by2)) {
                    $underEaves = $true
                    break
                }
            }
        }
    }
    if ($underEaves) {
        Invoke-UpScore
        Invoke-UpScore
        Invoke-DispStrings 17   # 軒下メッセージ
    } elseif ($script:fallen) {
        Invoke-DispStrings 16   # 落下後の移動メッセージ
    }
    return $true
}

# ブロック回転（C版 rotlith 相当）
# Evil判定で確率的に不規則な回転(0〜3回)になることがある
function Invoke-RotLith {
    $after = $script:moving.Clone()
    if (Test-IsEvil 80) {
        $rn = Get-Random -Minimum 0 -Maximum 4
        Invoke-DispStrings 9    # evil回転メッセージ
    } else {
        $rn = $script:rotincr   # 通常: 1(時計) or 3(反時計)
    }
    for ($rv2 = 0; $rv2 -lt $rn; $rv2++) { Invoke-RRotLith ([ref]$after) }
    if (Test-Collision $after) { return $false }

    Erase-Lith $script:moving
    $script:moving = $after
    Draw-Lith $script:moving

    # 軒下チェック: 回転後に下にブロックがあればボーナス（×4スコア）
    $underEaves = $false
    for ($i = 0; $i -lt $script:moving.TileCount; $i++) {
        $by2 = $script:moving.Y[$i] - 1
        if ($by2 -ge 0) {
            $bx2 = $script:moving.X[$i]
            if (($script:map[$bx2,$by2] -ne $script:BLANK -and $script:map[$bx2,$by2] -ne 0) -or
                ($script:map[($bx2+1),$by2] -ne $script:BLANK -and $script:map[($bx2+1),$by2] -ne 0)) {
                if (-not (Test-IsWormAliveCell $bx2 $by2)) {
                    $underEaves = $true
                    break
                }
            }
        }
    }
    if ($underEaves) {
        for ($b = 0; $b -lt 4; $b++) { Invoke-UpScore }
        Invoke-DispStrings 17   # 軒下メッセージ
    }
    return $true
}

# ブロック瞬間落下（C版 falllith 相当）
# jumpモード: 描画を抑止して一括落下
# 通常モード: 1段ごとに描画+15msウェイト（アニメーション）
# 落下高さに基づくボーナス（holypoint/score）とワーム圧殺チェック
function Invoke-FallLith {
    if ($script:isjump) { Erase-Lith $script:moving }

    $fh = $script:moving.Y[0]
    while (Invoke-DropLith (-not $script:isjump)) {
        if (-not $script:isjump) { Start-Sleep -Milliseconds 15 }
    }
    $fh -= $script:moving.Y[0]   # 落下高さ

    if ($script:isjump) { Draw-Lith $script:moving }
    if ($fh -gt 0) { $script:fallen = $true }

    # 落下ボーナス（jumpモードは確率2倍）
    $dH = if ($script:isjump) { 80 } else { 160 }
    $dS = if ($script:isjump) { 20 } else { 40 }
    if ((Get-Random -Minimum 0 -Maximum $dH) -lt $fh) {
        Invoke-DispStrings 13
        $script:holypoint++
    }
    if ((Get-Random -Minimum 0 -Maximum $dS) -lt $fh) {
        Invoke-DispStrings 3
        $script:score++
    }

    # ワーム圧殺チェック: 全タイルが地面に着いている場合
    if ($script:wormlen -gt 0) {
        $allOn = $true
        for ($i = 0; $i -lt $script:moving.TileCount; $i++) {
            $ty2 = $script:moving.Y[$i]
            $tx2 = $script:moving.X[$i]
            if ($ty2 -gt 0) {
                $bl = $script:map[$tx2, ($ty2-1)]
                if (($bl -eq $script:BLANK -or $bl -eq 0) -and -not (Test-IsWormAliveCell $tx2 ($ty2-1))) {
                    $allOn = $false
                    break
                }
            }
        }
        if ($allOn -and (Get-Random -Minimum 0 -Maximum 100) -lt ($fh * $script:lithn)) {
            Kill-Worm
            $script:evilpoint++
            Invoke-DispStrings 4   # ワーム圧殺メッセージ
        }
    }
}

# 祈り/ポリリス（C版 polylith 相当）
# Holy判定成功時に同タイル数の別パターンにランダム変形、holypoint -= 4
function Invoke-PolyLith {
    $pat = $script:basinfo[$script:lithn-1] + (Get-Random -Minimum 0 -Maximum $script:patinfo[$script:lithn-1])
    if (-not (Test-IsHoly)) { return }
    Invoke-DispStrings 10   # 祈り成功メッセージ

    # 別パターンを生成
    $ini = $script:iniinfo[$pat]
    $nl = [Lith]::new()
    for ($i = 0; $i -lt $script:lithn; $i++) {
        $nl.X[$i] = $ini.X[$i] * 2
        $nl.Y[$i] = $ini.Y[$i]
    }
    $nl.RotIndex = $ini.FirstRotIndex
    $nl.Ch = $ini.Ch
    $nl.Attr = $ini.Attr
    $nl.TileCount = $script:lithn

    # ランダム回転
    $rc = Get-Random -Minimum 0 -Maximum 4
    for ($i = 0; $i -lt $rc; $i++) { Invoke-RRotLith ([ref]$nl) }

    # 現在位置に合わせて配置
    $bx2 = $script:moving.X[0] - $nl.X[0]
    $by2 = $script:moving.Y[0] - $nl.Y[0]
    for ($i = 0; $i -lt $script:lithn; $i++) {
        $nl.X[$i] += $bx2
        $nl.Y[$i] += $by2
    }

    if (-not (Test-Collision $nl)) {
        $script:holypoint -= 4
        if ($script:holypoint -lt 0) { $script:holypoint = 0 }
        Erase-Lith $script:moving
        $script:moving = $nl
        Draw-Lith $script:moving
    }
}
#endregion

#region フィールド操作
# ブロック固定（C版 setgarvage 相当）
# - マップにブロックの文字コードと色属性を書き込み
# - 2文字幅: Ch.Length>=2→ASCII2文字, それ以外→全角1文字(後半=-1マーカー)
# - 下に空白があるタイルをカウント(brankcount)→evilpoint加算
function Set-Garvage {
    $maxH = 0
    for ($i = 0; $i -lt $script:moving.TileCount; $i++) {
        $mx = $script:moving.X[$i]
        $my = $script:moving.Y[$i]
        if ($script:moving.Ch.Length -ge 2) {
            # ASCII 2文字（例: "[]"）
            $script:map[$mx, $my] = [int]$script:moving.Ch[0]
            $script:map[($mx+1), $my] = [int]$script:moving.Ch[1]
        } else {
            # 全角1文字（例: "◇"）— 文字コードを前半セルに、-1を後半マーカーに
            $script:map[$mx, $my] = [int][char]$script:moving.Ch[0]
            $script:map[($mx+1), $my] = -1
        }
        $script:mapattr[$mx, $my] = $script:moving.Attr
        $script:mapattr[($mx+1), $my] = $script:moving.Attr
        if ($my -gt $maxH) { $maxH = $my }
    }

    # 下に空白があるタイル数をカウント → evilpoint加算
    $bc = 0
    for ($i = 0; $i -lt $script:moving.TileCount; $i++) {
        $mx = $script:moving.X[$i]
        $my = $script:moving.Y[$i]
        if ($my -gt 0) {
            if ($script:map[$mx,($my-1)] -eq $script:BLANK -or $script:map[$mx,($my-1)] -eq 0) { $bc++ }
            if ($script:map[($mx+1),($my-1)] -eq $script:BLANK -or $script:map[($mx+1),($my-1)] -eq 0) { $bc++ }
        }
    }
    $script:evilpoint += [Math]::Floor($bc / 2)
    if ($bc -gt 0) { Invoke-DispStrings 1 }          # 空白の上に置いたメッセージ
    if ($maxH -gt $script:welldepth - $script:MAXLITHN - 2) {
        Invoke-DispStrings 5   # 危険高さ警告メッセージ
    }
}

# 行消去チェック・実行（C版 checkstack 相当）
# 各行について全セルが充填済みかチェック → 完成行を削除し上の行をシフト
function Invoke-CheckStack {
    Invoke-DispStrings 7   # "put a block" メッセージ
    $yf = -1               # 最初に消去した行番号（再描画用）
    $y = 0
    while ($y -lt $script:welldepth) {
        $complete = $true
        $wc = 0            # wizard時の空白許容カウンタ
        for ($x = 0; $x -lt $script:wellwidth; $x++) {
            $cell = $script:map[$x, $y]
            if ($cell -eq $script:BLANK -or $cell -eq 0) {
                if (Test-IsWormAliveCell $x $y) { continue }
                if ($script:wizard -and $wc -lt 2) { $wc++; continue }
                $complete = $false; break
            }
        }
        if ($complete) {
            if ($script:belsw) { try { [Console]::Beep(800, 100) } catch {} }
            $script:holypoint += 2
            $script:erasedlines++
            Invoke-UpScore
            if ($yf -eq -1) { $yf = $y }
            for ($ym = $y; $ym -lt ($script:welldepth - 1); $ym++) {
                for ($x = 0; $x -lt $script:wellwidth; $x++) {
                    $script:map[$x,$ym] = $script:map[$x,($ym+1)]
                    $script:mapattr[$x,$ym] = $script:mapattr[$x,($ym+1)]
                }
            }
            for ($x = 0; $x -lt $script:wellwidth; $x++) {
                $script:map[$x,($script:welldepth-1)] = $script:BLANK
                $script:mapattr[$x,($script:welldepth-1)] = 0
            }
            for ($wi = 0; $wi -lt $script:wormlen; $wi++) {
                if ($script:wormy[$wi] -gt $y) { $script:wormy[$wi]-- }
            }
            if ($y -gt 0) {
                $sc = 0
                for ($x = 0; $x -lt $script:wellwidth; $x++) {
                    if ($script:map[$x,($y-1)] -eq $script:BLANK -or $script:map[$x,($y-1)] -eq 0) {
                        $ab = $true
                        for ($cy = $y; $cy -lt $script:welldepth; $cy++) {
                            if ($script:map[$x,$cy] -ne $script:BLANK -and $script:map[$x,$cy] -ne 0) { $ab=$false; break }
                        }
                        if ($ab) { $sc++ }
                    }
                }
                $sc = [Math]::Floor($sc / 2)
                $script:evilpoint -= $sc; $script:holypoint += $sc
                if ($sc -gt 0) { Invoke-DispStrings 8 }
            }
        } else { $y++ }
    }
    if ($yf -ge 0) { Draw-Garvages $yf }

    $script:blocks++
    $script:holypoint++

    # 移動回数による悪行判定: 基準値を超えた分がevilpointに
    $script:moveone -= ([Math]::Floor($script:wellwidth / 4) + 2)
    if ($script:moveone -gt 0) {
        $script:evilpoint += [Math]::Floor($script:moveone / 2)
        Invoke-DispStrings 2   # 移動しすぎメッセージ
    }
    $script:moveone = 0
    Invoke-UpScore
    Show-Score

    # 速度上昇: トレーニング→確率1/1, 通常→確率1/8
    if ($script:istraining) { Invoke-SpeedUp 1 2 } else { Invoke-SpeedUp 8 2 }
}

# 初期ガベージ配置（C版 wipegarvage 相当）
# マップを新規作成しBLANKで初期化、height行まで50%確率でブロック配置
function Initialize-WipeGarvage {
    $script:map = New-Object 'int[,]' 40, 22
    $script:mapattr = New-Object 'int[,]' 40, 22
    # 全セルをBLANKで初期化
    for ($y = 0; $y -lt $script:WELLDEPTH_MAX; $y++) {
        for ($x = 0; $x -lt ($script:WELLWIDTH_MAX * 2); $x++) {
            $script:map[$x,$y] = $script:BLANK
            $script:mapattr[$x,$y] = 0
        }
    }
    # 初期ゴミ配置（height行まで、IGARV_FACTOR/10 = 50%の確率）
    for ($y = 0; $y -lt $script:height; $y++) {
        for ($x = 0; $x -lt $script:wellwidth; $x += 2) {
            if ((Get-Random -Minimum 0 -Maximum 10) -lt $script:IGARV_FACTOR) {
                $pat = Get-Random -Minimum 0 -Maximum $script:MAXINIINFO
                $ini = $script:iniinfo[$pat]
                if ($ini.Ch.Length -ge 2) {
                    $script:map[$x,$y] = [int]$ini.Ch[0]
                    $script:map[($x+1),$y] = [int]$ini.Ch[1]
                } else {
                    $script:map[$x,$y] = [int][char]$ini.Ch[0]
                    $script:map[($x+1),$y] = -1
                }
                $script:mapattr[$x,$y] = $ini.Attr
                $script:mapattr[($x+1),$y] = $ini.Attr
            }
        }
    }
}
#endregion

#region ワームシステム
# ワーム出現・移動制御（トレーニングモード除外）
function Move-WormOne {
    if ($script:istraining) { return }
    if ($script:wormlen -gt 0) { Move-Worm }
    elseif ($script:wizard -or (Get-Random -Minimum 0 -Maximum 500) -le $script:erasedlines) { New-GeneWorm }
}

# ワーム生成（C版 geneworm 相当）
# 左端(xH=1,xB=0) or 右端からランダムに選び、下から空き位置を探す
function New-GeneWorm {
    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
        $xH = 1
        $xB = 0
    } else {
        $xH = $script:wellwidth - 2
        $xB = $script:wellwidth - 1
    }
    $found = $false
    for ($y = 0; $y -lt $script:welldepth; $y++) {
        if (($script:map[$xH,$y] -eq $script:BLANK -or $script:map[$xH,$y] -eq 0) -and
            -not (Test-Flying $xH $y)) {
            $script:wormy[0] = $y
            $script:wormy[1] = $y
            $script:wormx[0] = $xH
            $script:wormx[1] = $xB
            $found = $true
            break
        }
    }
    if (-not $found) { $script:wormlen = 0; return }

    $script:wormlen = 2
    $script:map[$script:wormx[0],$script:wormy[0]] = [int][char]$script:wormhead
    $script:mapattr[$script:wormx[0],$script:wormy[0]] = $script:wormalcolour
    $script:map[$script:wormx[1],$script:wormy[1]] = [int][char]$script:wormbody
    $script:mapattr[$script:wormx[1],$script:wormy[1]] = $script:wormalcolour
    Draw-Worm
}

# ワーム移動（C版 moveworm 相当）
# 確率的方向選択: 上5%, 下75%, 右10%, 左10%
# 10%の確率で成長（最大WORMLEN_MAX）、スネーク式移動
function Move-Worm {
    $hx = $script:wormx[0]
    $hy = $script:wormy[0]

    # 4方向の移動可否判定
    $cU = Test-WormMove $hx ($hy+1)
    $cD = Test-WormMove $hx ($hy-1)
    $cR = Test-WormMove ($hx+1) $hy
    $cL = Test-WormMove ($hx-1) $hy
    if (-not ($cU -or $cD -or $cR -or $cL)) { Kill-Worm; return }

    # 確率的方向選択
    $nx = $hx
    $ny = $hy
    do {
        $d = Get-Random -Minimum 0 -Maximum 100
        if ($cU -and $d -lt 5)    { $ny = $hy + 1; break }
        if ($cD -and $d -lt 80)   { $ny = $hy - 1; break }
        if ($cR -and $d -lt 90)   { $nx = $hx + 1; break }
        if ($cL)                  { $nx = $hx - 1; break }
    } while ($true)

    # 成長判定（10%確率）or 末尾セグメント消去
    $ti = $script:wormlen - 1
    if ($script:wormlen -lt $script:WORMLEN_MAX -and (Get-Random -Minimum 0 -Maximum 10) -eq 0) {
        $script:wormlen++
    } else {
        $tx = $script:wormx[$ti]
        $ty = $script:wormy[$ti]
        $script:map[$tx,$ty] = $script:BLANK
        $script:mapattr[$tx,$ty] = 0
        Erase-WormSeg $tx $ty
    }

    # スネーク式移動: 各セグメントを後ろにシフト
    $script:map[$hx,$hy] = [int][char]$script:wormbody
    for ($i = $script:wormlen - 1; $i -ge 1; $i--) {
        $script:wormx[$i] = $script:wormx[$i-1]
        $script:wormy[$i] = $script:wormy[$i-1]
    }
    $script:wormx[0] = $nx
    $script:wormy[0] = $ny
    $script:map[$nx,$ny] = [int][char]$script:wormhead
    $script:mapattr[$nx,$ny] = $script:wormalcolour
    Draw-Worm
}

# ワーム移動可能判定 — 境界チェック + マップ空き + 飛行中でない
function Test-WormMove {
    param([int]$X, [int]$Y)
    if ($X -lt 0 -or $X -ge $script:wellwidth -or $Y -lt 0 -or $Y -ge $script:welldepth) { return $false }
    if ($script:map[$X,$Y] -ne $script:BLANK -and $script:map[$X,$Y] -ne 0) { return $false }
    if (Test-Flying $X $Y) { return $false }
    return $true
}

# ワーム死亡（C版 killworm 相当）
# - 全体を死亡色に変更
# - 隣接セル(X XOR 1)に分裂片を配置
# - checkstackで死骸による行消去チェック
function Kill-Worm {
    for ($i = 0; $i -lt $script:wormlen; $i++) {
        $wx = $script:wormx[$i]
        $wy = $script:wormy[$i]
        $script:mapattr[$wx,$wy] = $script:wormcolour
        # 隣接セルに分裂片配置
        $ax = $wx -bxor 1
        if ($ax -ge 0 -and $ax -lt $script:wellwidth) {
            if ($script:map[$ax,$wy] -eq $script:BLANK -or $script:map[$ax,$wy] -eq 0) {
                $script:map[$ax,$wy] = [int][char]$script:wormspilit
                $script:mapattr[$ax,$wy] = $script:wormspcolour
                $ssx = $script:wellx_beg + $ax
                $ssy = $script:well_bottom - $wy
                if ($ssx -ge 0 -and $ssy -ge 0) {
                    [Console]::SetCursorPosition($ssx, $ssy)
                    Write-ColorText ([string]$script:wormspilit) $script:wormspcolour
                }
            }
        }
    }
    Draw-WormColor $script:wormcolour
    $script:wormlen = 0
    Invoke-CheckStack
}

# ワーム描画（生存色）
function Draw-Worm { Draw-WormColor $script:wormalcolour }

# ワーム描画（指定色） — i=0:頭文字, i>0:胴体文字
function Draw-WormColor {
    param([int]$Color)
    for ($i = 0; $i -lt $script:wormlen; $i++) {
        $wx = $script:wormx[$i]
        $wy = $script:wormy[$i]
        $sx = $script:wellx_beg + $wx
        $sy = $script:well_bottom - $wy
        if ($sx -ge 0 -and $sy -ge 0) {
            [Console]::SetCursorPosition($sx, $sy)
            $ch = if ($i -eq 0) { [string]$script:wormhead } else { [string]$script:wormbody }
            Write-ColorText $ch $Color
        }
    }
}

# ワーム単一セグメント消去
function Erase-WormSeg {
    param([int]$X, [int]$Y)
    $sx = $script:wellx_beg + $X
    $sy = $script:well_bottom - $Y
    if ($sx -ge 0 -and $sy -ge 0) {
        [Console]::SetCursorPosition($sx, $sy)
        [Console]::Write(" ")
    }
}

# 飛行ブロック判定 — 指定座標が操作中ブロックの位置か
function Test-Flying {
    param([int]$X, [int]$Y)
    if (-not $script:moving) { return $false }
    for ($i = 0; $i -lt $script:moving.TileCount; $i++) {
        if (($X -band (-bnot 1)) -eq $script:moving.X[$i] -and $Y -eq $script:moving.Y[$i]) { return $true }
    }
    return $false
}

# 生存ワームセル判定 — mapattr が生存色(wormalcolour)かチェック
function Test-IsWormAliveCell {
    param([int]$X, [int]$Y)
    if ($script:wormlen -eq 0) { return $false }
    for ($i = 0; $i -lt $script:wormlen; $i++) {
        if ($script:wormx[$i] -eq $X -and $script:wormy[$i] -eq $Y) {
            if ($script:mapattr[$X,$Y] -eq $script:wormalcolour) { return $true }
        }
    }
    return $false
}
#endregion

#region ポイント・スコア
# スコア加算（C版 upscore 相当）— score += scorestep, 10%確率でscorestep++
function Invoke-UpScore {
    $script:score += $script:scorestep
    if ((Get-Random -Minimum 0 -Maximum 10) -eq 0) { $script:scorestep++ }
}

# Evil判定（C版 isevil 相当）— evilpoint > random(fact + pmoonidx*8) で発生
# 満月(pmoonidx=0)ほどevilになりにくい、新月(pmoonidx=4)ほどevilになりやすい
function Test-IsEvil {
    param([int]$Fact)
    if ($script:istraining -or $script:wizard) { return $false }
    if ($script:evilpoint -le (Get-Random -Minimum 0 -Maximum ($Fact + $script:pmoonidx * 8))) { return $false }
    return $true
}

# Holy判定・祈り処理（C版 isholy 相当）
# 1. holypointを確率的に減少
# 2. holy/evil浄化試行（確率的にevilpoint減少）
# 戻り値: $true=polylith変形成功
function Test-IsHoly {
    if ($script:istraining) { return $false }

    # holypointの確率的減少
    $script:holypoint -= (Get-Random -Minimum 0 -Maximum 4)
    if ($script:holypoint -lt 0) { $script:holypoint = 0 }

    # 祈り成功判定（満月ほど成功しやすい）
    if (-not $script:wizard -and
        $script:holypoint -lt (Get-Random -Minimum 0 -Maximum (100 + $script:pmoonidx * 8))) {
        Invoke-DispStrings 12   # "failed" メッセージ
        return $false
    }

    # evil浄化試行
    if ((Get-Random -Minimum 0 -Maximum (24 - $script:pmoonidx)) -lt 8) {
        $iv = Get-Random -Minimum 0 -Maximum 10
        $script:holypoint -= $iv * ((Get-Random -Minimum 0 -Maximum 4) + 1)
        if ($script:holypoint -lt 0) { $script:holypoint = 0 }
        $script:evilpoint -= $iv
        if ($script:evilpoint -lt 0) { $script:evilpoint = 0 }
        Invoke-DispStrings 11   # "succeeded" メッセージ
        return $false
    }
    return $true
}

# ゲーム速度上昇 — random(Fact)==0 の確率で looptimer -= Value（TIMER_MIN以上を保証）
function Invoke-SpeedUp {
    param([int]$Fact, [int]$Value)
    if ((Get-Random -Minimum 0 -Maximum $Fact) -eq 0) {
        $nt = $script:looptimer - $Value
        if ($nt -ge $script:TIMER_MIN) { $script:looptimer = $nt }
    }
}

# ボーナス計算（ゲーム終了時）— score += holypoint*10 - evilpoint*40
function Add-Bonus {
    $script:orgscore = $script:score
    if (-not $script:istraining) {
        $script:score += $script:holypoint * 10 - $script:evilpoint * 40
    }
}
#endregion

#region 月齢計算
function Get-MoonPhase {
    if ($script:wizard) { $script:pmoonidx = 0; return }
    # 朔望月方式 月齢計算
    # 基準新月: -NewMoon指定時はその値、未指定時は 2025-12-20 01:43 UTC (天文学的新月)
    # 平均朔望月: 29.530588853日
    if ($script:newmoon.Length -gt 0) {
        $refDate = ([DateTime]::Parse($script:newmoon)).ToUniversalTime()
    } else {
        $refDate = [DateTime]::new(2025, 12, 20, 1, 43, 0, [DateTimeKind]::Utc)
    }
    $synodicMonth = 29.530588853
    $totalDays = ([DateTime]::UtcNow - $refDate).TotalDays
    $script:moonage = [int][Math]::Floor($totalDays % $synodicMonth)
    $phase = $totalDays / $synodicMonth
    $pPhase = $phase - [Math]::Floor($phase)
    # pmoonidx: 0=満月(pPhase≈0.5), 4=新月(pPhase≈0.0/1.0)
    $rawPmoon = [Math]::Abs(($pPhase - 0.5) * 8)
    $script:pmoonidx = [int][Math]::Round($rawPmoon)
    if ($script:pmoonidx -gt 4) { $script:pmoonidx = 4 }
}
# 月齢メッセージ + 初期速度調整
# pmoonidx==0(満月): "full moon tonight", pmoonidx==4(新月): "new moon tonight"
# 満月ほど初期速度が速くなる
function Invoke-MoonMsg {
    if ($script:pmoonidx -eq 0) { Invoke-DispStrings 14 }       # 満月メッセージ
    elseif ($script:pmoonidx -eq 4) { Invoke-DispStrings 15 }   # 新月メッセージ
    Invoke-SpeedUp 1 ($script:pmoonidx * 20 + (Get-Random -Minimum 0 -Maximum 20))
    Invoke-FlushStrings 1
}
#endregion

#region メッセージ表示
# メッセージバッファへ追加（最大MSGBUF_MAX件）
function Invoke-DispStrings {
    param([int]$MsgNo)
    if (-not $script:hasStrings -or $script:istraining) { return }
    if ($script:msgbuf.Count -lt $script:MSGBUF_MAX) { $script:msgbuf += $MsgNo }
}

# メッセージフラッシュ表示 — バッファから確率的に1件取得して表示
# Fact: 表示確率の分母（wizard時は常に表示）
function Invoke-FlushStrings {
    param([int]$Fact = 10)
    if (-not $script:hasStrings -or $script:istraining) { return }
    $mn = 0
    if ($script:msgbuf.Count -gt 0) {
        if ((Get-Random -Minimum 0 -Maximum $Fact) -eq 0 -or $script:wizard) {
            $mn = $script:msgbuf[(Get-Random -Minimum 0 -Maximum $script:msgbuf.Count)]
        }
    }
    $script:msgbuf = @()
    if ($mn -eq $script:lastmsgno) { return }
    $script:lastmsgno = $mn
    if ($script:msgkind[$mn] -le 0) { return }
    $kd = Get-Random -Minimum 0 -Maximum $script:msgkind[$mn]
    if ($script:msg.ContainsKey($mn) -and $kd -lt $script:msg[$mn].Count) {
        Show-Message $script:msg[$mn][$kd]
    }
}
#endregion

#region 入力処理
# 入力コマンドディスパッチ
# 矢印キー: aliasmap対象外（直接処理）
# 文字キー: aliasmap[]経由で機能コードに変換
function Invoke-GameCommand {
    param([System.ConsoleKeyInfo]$KeyInfo)

    # 矢印キー直接処理
    switch ($KeyInfo.Key) {
        "LeftArrow"  { $script:moveone++; Invoke-SwingLith -2; Show-Score; return }
        "RightArrow" { $script:moveone++; Invoke-SwingLith  2; Show-Score; return }
        "DownArrow"  { Invoke-FallLith; Show-Score; return }
        "UpArrow"    { $script:moveone++; Invoke-RotLith; Show-Score; return }
    }

    # 文字キー → aliasmap → 機能コード
    $ch = [int]$KeyInfo.KeyChar
    if ($ch -lt 0 -or $ch -ge 128) { return }
    $fn = $script:aliasmap[$ch]
    switch ($fn) {
        $script:FN_LEFT   { $script:moveone++; Invoke-SwingLith -2; Show-Score }
        $script:FN_RIGHT  { $script:moveone++; Invoke-SwingLith  2; Show-Score }
        $script:FN_DROP   { Invoke-FallLith; Show-Score }
        $script:FN_ROTA   { $script:moveone++; Invoke-RotLith; Show-Score }
        $script:FN_PRAY   { $script:moveone++; Invoke-PolyLith; Show-Score }
        $script:FN_QUIT   {
            $script:moveone += 2
            if (Invoke-Query "Really quit? (y/n)") { $script:gameRunning = $false }
        }
        $script:FN_BEEP   { $script:belsw = -not $script:belsw }
        $script:FN_LOGO   { $script:logotype = -not $script:logotype; Redraw-Screen }
        $script:FN_COLOUR { $script:coloured = -not $script:coloured; Redraw-Screen }
        $script:FN_REDRAW { Redraw-Screen }
        $script:FN_JUMP   { $script:isjump = -not $script:isjump }
    }
}

# y/n確認ダイアログ — y/Y→$true, n/N/ESC→$false
function Invoke-Query {
    param([string]$Message)
    [Console]::SetCursorPosition($script:MSGX_BASE, 23)
    [Console]::Write($Message)
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $c = $key.KeyChar
            if ($c -eq 'y' -or $c -eq 'Y') {
                [Console]::SetCursorPosition($script:MSGX_BASE, 23)
                [Console]::Write(" " * $Message.Length)
                return $true
            } elseif ($c -eq 'n' -or $c -eq 'N' -or $key.Key -eq "Escape") {
                [Console]::SetCursorPosition($script:MSGX_BASE, 23)
                [Console]::Write(" " * $Message.Length)
                return $false
            }
        }
        Start-Sleep -Milliseconds 50
    }
}
#endregion

#region ハイスコア管理
# スコア保存 — record.json(通常) / recordtr.json(トレーニング)に記録
# 同一プレイヤー名は最大5件まで、全体で最大HMAX件をスコア降順で保持
function Save-Score {
    $recordFile = if ($script:istraining) { "recordtr.json" } else { "record.json" }
    $recordPath = Join-Path $PSScriptRoot $recordFile

    # 既存レコード読み込み
    $records = @()
    if (Test-Path $recordPath) {
        try {
            $records = @(foreach ($r in (Get-Content $recordPath -Raw | ConvertFrom-Json)) { $r })
        } catch { $records = @() }
    }

    # 新規レコード作成
    $today = Get-Date
    $newRecord = [PSCustomObject]@{
        Name     = $script:player
        Score    = $script:score
        OrgScore = $script:orgscore
        Blocks   = $script:blocks
        Lines    = $script:erasedlines
        Year     = $today.Year
        Month    = $today.Month
        Day      = $today.Day
    }
    $records += $newRecord

    # 同一プレイヤー名は最大5件まで
    $byPlayer = $records | Group-Object -Property Name
    $filtered = @()
    foreach ($group in $byPlayer) {
        $filtered += $group.Group | Sort-Object -Property Score -Descending | Select-Object -First 5
    }

    # スコア降順、最大HMAX件
    $filtered = $filtered | Sort-Object -Property Score -Descending | Select-Object -First $script:HMAX
    $filtered | ConvertTo-Json -Depth 3 | Set-Content $recordPath -Encoding UTF8

    # 直近記録も保存（トレーニング以外）
    if (-not $script:istraining) { Save-CurrentScore $newRecord }
}

# 直近記録保存 — recordcr.json にCURRENT_DAYS日以内のスコアを保持
function Save-CurrentScore {
    param($NewRecord)
    $crPath = Join-Path $PSScriptRoot "recordcr.json"

    # 既存レコード読み込み
    $records = @()
    if (Test-Path $crPath) {
        try {
            $records = @(foreach ($r in (Get-Content $crPath -Raw | ConvertFrom-Json)) { $r })
        } catch { $records = @() }
    }
    $records += $NewRecord

    # 期限切れレコードを除去
    $today = Get-Date
    $records = $records | Where-Object {
        try {
            $recDate = Get-Date -Year $_.Year -Month $_.Month -Day $_.Day
            ($today - $recDate).Days -le $script:CURRENT_DAYS
        }
        catch { $false }
    }

    $records = $records | Sort-Object -Property Score -Descending | Select-Object -First $script:HMAX
    $records | ConvertTo-Json -Depth 3 | Set-Content $crPath -Encoding UTF8
}

# ハイスコア一覧表示画面 — 直近記録 + 永久ベスト記録
function Show-ScoresDisplay {
    [Console]::Clear()

    # 直近記録
    $crPath = Join-Path $PSScriptRoot "recordcr.json"
    if (Test-Path $crPath) {
        [Console]::WriteLine("=== Lately Records (Last $($script:CURRENT_DAYS) days) ===")
        [Console]::WriteLine()
        Show-ScoreList $crPath
        [Console]::WriteLine()
    }

    # 永久記録
    $recPath = Join-Path $PSScriptRoot "record.json"
    if (Test-Path $recPath) {
        [Console]::WriteLine("=== Best Records ===")
        [Console]::WriteLine()
        Show-ScoreList $recPath
    }

    [Console]::WriteLine()
    [Console]::Write("Press any key to continue...")
    $null = [Console]::ReadKey($true)
}

# スコアリスト表示 — JSONファイルからランキング形式で出力
# 自分のスコアは反転白(色コード7)でハイライト
function Show-ScoreList {
    param([string]$Path)
    try {
        $records = @(foreach ($r in (Get-Content $Path -Raw | ConvertFrom-Json)) { $r })
    } catch { return }

    $rank = 1
    foreach ($rec in $records) {
        $highlight = ($rec.Name -eq $script:player)
        if ($highlight) { Set-GameColour 7 }   # 反転白

        $line = "{0,2}. {1,7} / {2,7} ({3,4}blocks, {4,3}lines) {5}" -f `
            $rank, $rec.Score, $rec.OrgScore, $rec.Blocks, $rec.Lines, $rec.Name
        [Console]::WriteLine($line)

        if ($highlight) { [Console]::ResetColor() }
        $rank++
    }
}
#endregion

#region 初期化
# 初期化フェーズ1 — ワーム色の初期値設定
function Initialize-Var1 {
    $script:wormalcolour = 0     # ワーム生存色 (EWH)
    $script:wormcolour   = 45    # ワーム死亡色 (EVPU)
    $script:wormspcolour = 36    # ワーム分裂片色 (ETU)
}

# 初期化フェーズ2 — フィールド座標計算、設定ファイル読み込み
function Initialize-Var2 {
    # wellwidthを×2（ブロック単位→文字単位）
    $script:wellwidth *= 2

    # well座標を計算（+1で画面全体を1行下げる）
    $script:well_bottom = $script:welldepth + 1
    if ($script:well_bottom -gt $script:WELL_BOTTOM_MAX) {
        $script:well_bottom = $script:WELL_BOTTOM_MAX
    }
    $script:well_top = $script:well_bottom - $script:welldepth + 1
    $script:wellx_beg = [Math]::Floor(($script:SCR_X - 2 - $script:wellwidth) / 2)
    $script:wellx_end = $script:wellx_beg + $script:wellwidth

    # 初期ブロック高さの上限チェック
    if ($script:height -ge $script:welldepth - $script:MAXLITHN) {
        $script:height = $script:welldepth - $script:MAXLITHN - 1
    }

    Initialize-DefaultKeymap    # デフォルトキーマッピングの設定
    Read-Config                 # 設定ファイル読み込み
    Read-Strings                # メッセージファイル読み込み

    # ワーム色の衝突チェック（同色なら変更）
    if ($script:wormalcolour -eq $script:wormcolour) {
        $script:wormcolour = 45  # EVPU
    }
}
# デフォルトキーマッピング初期化
# Ctrl+文字キーはデフォルトでは使用しない（config.nltのalias定義で自由に利用可能）
# TAB(9), ENTER(13), Ctrl+C(3) は独立した物理キーまたは特殊用途のため残す
function Initialize-DefaultKeymap {
    for ($i = 0; $i -lt 128; $i++) { $script:aliasmap[$i] = 0 }
    # LEFT: 4, h, H
    $script:aliasmap[[int][char]'4'] = 1
    $script:aliasmap[[int][char]'h'] = 1
    $script:aliasmap[[int][char]'H'] = 1
    # RIGHT: 6, l, L
    $script:aliasmap[[int][char]'6'] = 2
    $script:aliasmap[[int][char]'l'] = 2
    $script:aliasmap[[int][char]'L'] = 2
    # DROP: 2, j, J, Space
    $script:aliasmap[[int][char]'2'] = 3
    $script:aliasmap[[int][char]'j'] = 3
    $script:aliasmap[[int][char]'J'] = 3
    $script:aliasmap[[int][char]' '] = 3
    # ROTATE: 5, TAB(9), ENTER(13)
    $script:aliasmap[[int][char]'5'] = 4
    $script:aliasmap[9] = 4
    $script:aliasmap[13] = 4
    # PRAY: 8, k, K, p, P
    $script:aliasmap[[int][char]'8'] = 5
    $script:aliasmap[[int][char]'k'] = 5
    $script:aliasmap[[int][char]'K'] = 5
    $script:aliasmap[[int][char]'p'] = 5
    $script:aliasmap[[int][char]'P'] = 5
    # QUIT: q, Q, Ctrl+C(3)
    $script:aliasmap[[int][char]'q'] = 6
    $script:aliasmap[[int][char]'Q'] = 6
    $script:aliasmap[3] = 6
    # 機能キー: r/R=REDRAW, g/G=BEEP, t/T=LOGO, f/F=COLOUR, e/E=JUMP
    $script:aliasmap[[int][char]'r'] = 9
    $script:aliasmap[[int][char]'R'] = 9
    $script:aliasmap[[int][char]'g'] = 10
    $script:aliasmap[[int][char]'G'] = 10
    $script:aliasmap[[int][char]'t'] = 11
    $script:aliasmap[[int][char]'T'] = 11
    $script:aliasmap[[int][char]'f'] = 12
    $script:aliasmap[[int][char]'F'] = 12
    $script:aliasmap[[int][char]'e'] = 13
    $script:aliasmap[[int][char]'E'] = 13
}

# ゲーム変数初期化（C版 setvar 相当）
function Set-GameVar {
    $script:looptimer   = $script:inittimer
    $script:scorestep   = $script:SCORESTEP_INI
    $script:score       = 0
    $script:orgscore    = 0
    $script:blocks      = 0
    $script:erasedlines = 0
    $script:holypoint   = 0
    $script:evilpoint   = 0
    $script:moveone     = 0
    $script:wormlen     = 0
    $script:fallen      = $false
    $script:moving      = $null
    $script:nextlith   = $null
    $script:nextn       = 0
    $script:lastmsgno   = -1
    $script:msgbuf      = @()
    Get-MoonPhase
}

# プレイヤー名取得 — 起動オプション未指定時はUSERNAME、guestなら手動入力
function Get-PlayerName {
    if ($script:player.Length -gt 0) { return }

    $script:player = $env:USERNAME
    if (-not $script:player -or $script:player -eq "guest") {
        [Console]::SetCursorPosition(0, 23)
        [Console]::Write("Who are you : ")
        $script:player = ""
        while ($true) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Enter" -and $script:player.Length -gt 0) { break }
                if ($key.Key -eq "Backspace" -and $script:player.Length -gt 0) {
                    $script:player = $script:player.Substring(0, $script:player.Length - 1)
                    [Console]::SetCursorPosition(14 + $script:player.Length, 23)
                    [Console]::Write(" ")
                    [Console]::SetCursorPosition(14 + $script:player.Length, 23)
                } elseif ($key.KeyChar -ge ' ' -and $script:player.Length -lt $script:P_NAME_MAX) {
                    $ch = $key.KeyChar
                    if ($ch -eq ' ') { $ch = '_' }   # スペースはアンダースコアに変換
                    $script:player += $ch
                    [Console]::Write($ch)
                }
            }
            Start-Sleep -Milliseconds 50
        }
        # クエリ行クリア
        [Console]::SetCursorPosition(0, 23)
        [Console]::Write(" " * 40)
    }
}
#endregion

#region ゲームフロー
# 入力待ち＋タイマーループ（C版 movelithone 相当）
# looptimerミリ秒間キー入力を受け付け、タイマー満了で1段落下
# 戻り値: $true=まだ落下可能, $false=着地またはquit
function Invoke-MoveLithOne {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.ElapsedMilliseconds -lt $script:looptimer) {
        # キー入力処理
        while ([Console]::KeyAvailable) {
            $keyInfo = [Console]::ReadKey($true)
            Invoke-GameCommand $keyInfo
            if (-not $script:gameRunning) { return $false }
        }
        Start-Sleep -Milliseconds 15
    }

    # タイマー満了 → ブロック1段落下
    return (Invoke-DropLith $true)
}

# メインゲームループ
# ブロック生成→落下→固定→行消去 を繰り返し、ゲームオーバーまで続行
function Start-Game {
    $replay = $true

    while ($replay) {
        Set-GameVar                 # ゲーム変数初期化
        Initialize-WipeGarvage      # フィールドクリア + 初期ブロック配置
        Redraw-Screen               # 画面全体再描画
        Invoke-MoonMsg              # 月齢メッセージ + 初期スピード調整

        $script:gameRunning = $true

        # ブロック生成ループ
        while ($script:gameRunning -and (New-GeneLith)) {
            $dropping = $true
            # ブロック落下ループ
            while ($dropping) {
                Move-WormOne                        # ワーム移動
                $dropping = Invoke-MoveLithOne       # 入力待ち + タイマー
            }
            if (-not $script:gameRunning) { break }

            Set-Garvage                 # ブロック固定
            Invoke-CheckStack           # 行消去チェック
            Invoke-FlushStrings 10      # メッセージ表示
        }

        # qキーによる途中終了の場合はスコア保存・表示をスキップして即終了
        if (-not $script:gameRunning) { break }

        Complete-Game
        $replay = Invoke-Query "Play again? (y/n)"
    }
}

# ゲーム終了処理 — ボーナス加算、GAME OVER表示、スコア保存
function Complete-Game {
    Add-Bonus

    # ゲームオーバー表示
    [Console]::SetCursorPosition($script:wellx_beg, $script:well_top - 1)
    Write-ColorText "  GAME OVER  " 31   # 赤
    Show-Score

    # ハイスコア記録（wizard/genn=1の場合は記録しない）
    if (-not $script:wizard -and $script:genn -ne 1) { Save-Score }

    Start-Sleep -Milliseconds 1500

    # ハイスコア表示
    if (Invoke-Query "Show scores? (y/n)") {
        Show-ScoresDisplay
        Redraw-Screen
    }
}

# コンソールサイズチェック — 最低80x24が必要
function Test-ConsoleSize {
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight
    if ($w -lt 80 -or $h -lt 24) {
        [Console]::ForegroundColor = [ConsoleColor]::Red
        [Console]::WriteLine("Console size too small. Minimum 80x24 required (current: ${w}x${h})")
        [Console]::ResetColor()
        exit 1
    }
    # バッファサイズをウィンドウサイズに合わせる（スクロール防止）
    try {
        [Console]::BufferWidth = [Console]::WindowWidth
        [Console]::BufferHeight = [Console]::WindowHeight
    } catch {}
}
#endregion

#region エントリポイント
# メイン関数 — 初期化→ゲーム実行→後始末
function Main {
    # 初期化シーケンス
    Test-ConsoleSize

    # -NewMoon パラメータのバリデーション
    if ($script:newmoon.Length -gt 0) {
        try {
            [void][DateTime]::Parse($script:newmoon)
        }
        catch {
            # "日付の形式が正しくないため2025-12-20T01:43:00Zを基準新月としてゲームを開始しますか(y/n)"
            # Shift-JIS (CP932) バイト列で保持し、コンソールのコードページに変換して出力
            [byte[]]$sjisBytes = @(
                0x93,0xFA,0x95,0x74,0x82,0xCC,0x8C,0x60,0x8E,0xAE,0x82,0xAA,0x90,0xB3,
                0x82,0xB5,0x82,0xAD,0x82,0xC8,0x82,0xA2,0x82,0xBD,0x82,0xDF,0x32,0x30,
                0x32,0x35,0x2D,0x31,0x32,0x2D,0x32,0x30,0x54,0x30,0x31,0x3A,0x34,0x33,
                0x3A,0x30,0x30,0x5A,0x82,0xF0,0x8A,0xEE,0x8F,0x80,0x90,0x56,0x8C,0x8E,
                0x82,0xC6,0x82,0xB5,0x82,0xC4,0x83,0x51,0x81,0x5B,0x83,0x80,0x82,0xF0,
                0x8A,0x4A,0x8E,0x6E,0x82,0xB5,0x82,0xDC,0x82,0xB7,0x82,0xA9,0x28,0x79,
                0x2F,0x6E,0x29
            )
            $sjisEnc = [System.Text.Encoding]::GetEncoding(932)
            $msgStr = $sjisEnc.GetString($sjisBytes)
            $outEnc = [System.Text.Encoding]::GetEncoding([Console]::OutputEncoding.WindowsCodePage)
            $outBytes = $outEnc.GetBytes($msgStr + "`n")
            [Console]::OpenStandardOutput().Write($outBytes, 0, $outBytes.Length)
            while ($true) {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
                        $script:newmoon = ""
                        break
                    }
                    elseif ($key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
                        return
                    }
                }
                Start-Sleep -Milliseconds 50
            }
        }
    }

    Initialize-Var1
    Initialize-BlockData
    Initialize-RotData
    Initialize-Var2

    # -ShowScores オプション: ハイスコア表示のみで終了
    if ($script:scoreonly) {
        Show-ScoresDisplay
        return
    }

    Get-PlayerName

    # コンソール状態を退避
    $origCursor = $true
    $origCtrlC = $false
    try { $origCursor = [Console]::CursorVisible } catch {}
    try { $origCtrlC = [Console]::TreatControlCAsInput } catch {}

    # カーソル非表示、Ctrl+C入力モード
    [Console]::CursorVisible = $false
    [Console]::TreatControlCAsInput = $true

    try {
        Start-Game
    }
    finally {
        # コンソール状態を復元
        try { [Console]::CursorVisible = $origCursor } catch {}
        try { [Console]::TreatControlCAsInput = $origCtrlC } catch {}
        [Console]::ResetColor()
        [Console]::Clear()
        [Console]::SetCursorPosition(0, 0)
    }
}

# 実行
Main
#endregion
