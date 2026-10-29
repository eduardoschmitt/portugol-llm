# ---------------------------------------------------------------------------
# Verificacao do corpus textual e do treino M8.
# - Corpus: 165 bytes, SHA-256, ASCII/LF, 5 linhas x 5 tokens.
# - Fonte ASCII puro, constantes canonicas, reuso de M1/M3/M7 sem duplicacao.
# - 16 casos .por com codificacao contratada; saida crua (form feed + epilogo).
# - Oraculo inteiro independente: tokenizacao, extracao, init, c16, Z256,
#   delta256, treino, perda, margens, ordem inversa, ablacoes, geracao.
# - V1 confere os 18 hashes congelados, o diff aditivo de test.ps1 e o escopo.
# - V18 executa a regressao completa: suite 116/116, autoteste e M1-M7.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-corpus-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/corpus-tests",
    [string]$SourcePath = "src/corpus.por",
    [string]$CorpusPath = "corpus/m8-corpus-v1.txt",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat",
    [string]$SpecPath = "docs/corpus-spec.md",
    [string]$PlanPath = "docs/corpus-plan.md"
)

$ErrorActionPreference = "Stop"

$script:failures = 0
$script:checks = 0
$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"
$epilogueBytes = [Text.Encoding]::ASCII.GetBytes($epilogue)

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

function Write-Check {
    param([string]$Name, [string[]]$Errors)
    $script:checks++
    if ($Errors.Count -eq 0) {
        Write-Host "[PASS] $Name"
    } else {
        $script:failures++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        foreach ($e in $Errors) { Write-Host "  $e" -ForegroundColor Gray }
    }
}

function Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

# --- Oraculo inteiro independente -------------------------------------------

$script:CorpWords = @(
    "UNK", "programa", "funcao", "inicio", "inteiro", "real", "logico",
    "cadeia", "vazio", "se", "senao", "enquanto", "faca", "para", "ate",
    "passo", "retorne", "escreva", "leia", "e", "ou", "nao", "verdadeiro",
    "falso", "pare"
)

function Get-CorpWord {
    param([int]$Id)
    return $script:CorpWords[$Id]
}

function Get-CorpWordId {
    param([string]$Word)
    for ($i = 0; $i -lt $script:CorpWords.Count; $i++) {
        if ($script:CorpWords[$i] -ceq $Word) { return $i }
    }
    return -1
}

function Get-CorpTokenize {
    param([string]$Line)
    if ($Line.Length -eq 0) {
        return [pscustomobject]@{ Code = 2; Ids = @(); Token = 0 }
    }
    if ($Line.IndexOf("`t") -ge 0 -or $Line.IndexOf("`r") -ge 0 -or $Line.IndexOf("`n") -ge 0) {
        return [pscustomobject]@{ Code = 2; Ids = @(); Token = 0 }
    }
    if ($Line[0] -eq ' ' -or $Line[$Line.Length - 1] -eq ' ' -or $Line.Contains("  ")) {
        return [pscustomobject]@{ Code = 2; Ids = @(); Token = 0 }
    }
    $parts = @($Line.Split(' '))
    $ids = @()
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $id = Get-CorpWordId $parts[$i]
        if ($id -lt 0) {
            return [pscustomobject]@{ Code = 3; Ids = @(); Token = $i + 1 }
        }
        $ids += $id
    }
    if ($parts.Count -lt 4) {
        return [pscustomobject]@{ Code = 6; Ids = @(); Token = $parts.Count }
    }
    if ($parts.Count -gt 8) {
        return [pscustomobject]@{ Code = 7; Ids = @(); Token = $parts.Count }
    }
    if ($ids[$ids.Count - 1] -ne 24) {
        return [pscustomobject]@{ Code = 4; Ids = @(); Token = 0 }
    }
    for ($i = 0; $i -lt $ids.Count - 1; $i++) {
        if ($ids[$i] -eq 24) {
            return [pscustomobject]@{ Code = 5; Ids = @(); Token = $i + 1 }
        }
    }
    return [pscustomobject]@{ Code = 0; Ids = [int[]]$ids; Token = 0 }
}

function Get-CorpExtract {
    param([string[]]$Lines)
    if ($Lines.Count -eq 0) {
        return [pscustomobject]@{ Code = 1; Entradas = @(); Alvos = @(); N = 0; Line = 0; Token = 0 }
    }
    if ($Lines.Count -gt 6) {
        return [pscustomobject]@{ Code = 8; Entradas = @(); Alvos = @(); N = 0; Line = 0; Token = 0 }
    }
    $ent = @()
    $alv = @()
    for ($li = 0; $li -lt $Lines.Count; $li++) {
        $tk = Get-CorpTokenize $Lines[$li]
        if ($tk.Code -ne 0) {
            return [pscustomobject]@{ Code = $tk.Code; Entradas = @(); Alvos = @(); N = 0; Line = $li + 1; Token = $tk.Token }
        }
        $ids = $tk.Ids
        for ($i = 3; $i -lt $ids.Count; $i++) {
            $a = $ids[$i - 3]; $b = $ids[$i - 2]; $c = $ids[$i - 1]; $t = $ids[$i]
            for ($j = 0; $j -lt $alv.Count; $j++) {
                if ($ent[$j * 3] -eq $a -and $ent[$j * 3 + 1] -eq $b -and $ent[$j * 3 + 2] -eq $c) {
                    $code = if ($alv[$j] -eq $t) { 9 } else { 10 }
                    return [pscustomobject]@{ Code = $code; Entradas = @(); Alvos = @(); N = 0; Line = $li + 1; Token = $i + 1 }
                }
            }
            $ent += $a; $ent += $b; $ent += $c
            $alv += $t
        }
    }
    return [pscustomobject]@{ Code = 0; Entradas = [int[]]$ent; Alvos = [int[]]$alv; N = $alv.Count; Line = 0; Token = 0 }
}

# --- Oraculo: estado, forward, treino e geracao ------------------------------

function New-CorpW {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($k = 0; $k -lt 3; $k++) {
            for ($d = 0; $d -lt 4; $d++) {
                if ($k -lt 2) { $row[$k * 4 + $d] = 0 }
                else { $row[$k * 4 + $d] = ((($y * 7) + ($d * 5)) % 25) - 12 }
            }
        }
        $w[$y] = $row
    }
    return $w
}

function New-CorpB {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-CorpW {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($p = 0; $p -lt 12; $p++) { $row[$p] = $W[$y][$p] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-CorpB {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-CorpE16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

function Get-CorpC16 {
    param([int[]]$Seq)
    $c = New-Object 'int[]' 12
    for ($k = 0; $k -lt 3; $k++) {
        $pos = $Seq.Count - 3 + $k
        if ($pos -ge 0) {
            for ($d = 0; $d -lt 4; $d++) {
                $c[$k * 4 + $d] = Get-CorpE16 $Seq[$pos] $d
            }
        }
    }
    return $c
}

function Get-CorpC16FromExample {
    param([int[]]$Entradas, [int]$N)
    return Get-CorpC16 ([int[]]@($Entradas[$N * 3], $Entradas[$N * 3 + 1], $Entradas[$N * 3 + 2]))
}

function Get-CorpZ256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y)
    [long]$soma = 0
    for ($p = 0; $p -lt 12; $p++) {
        $soma += [long]$W[$Y][$p] * [long]$C[$p]
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-CorpDelta256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y, [int]$Alvo)
    [long]$z = Get-CorpZ256 $W $B $C $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-CorpArgmax {
    param([hashtable]$W, [hashtable]$B, [int[]]$C)
    $melhor = 0
    [long]$melhorValor = Get-CorpZ256 $W $B $C 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-CorpZ256 $W $B $C $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-CorpLoss {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-CorpDelta256 $W $B $c $y $Alvos[$i]
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-CorpRound {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(([double]$absoluto + [double][long]($Denominador / 2)) / [double]$Denominador)
    return $sinal * $quociente
}

function Invoke-CorpTrain {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-CorpLoss $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            [int[]]$c = Get-CorpC16FromExample $Entradas $i
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-CorpDelta256 $W $B $c $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($p = 0; $p -lt 12; $p++) {
                    [long]$novo = Get-CorpRound (2048 * [long]$W[$y][$p] - $delta[$y] * [long]$c[$p]) 2048
                    $W[$y][$p] = $novo
                    if ([Math]::Abs($novo) -gt 16) {
                        return [pscustomobject]@{ Code = 5; History = $history }
                    }
                }
                [long]$novoB = Get-CorpRound (128 * [long]$B[$y] - $delta[$y]) 128
                $B[$y] = $novoB
                if ([Math]::Abs($novoB) -gt 16) {
                    return [pscustomobject]@{ Code = 5; History = $history }
                }
            }
        }
        $history[$ep] = Get-CorpLoss $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history }
}

function Get-CorpAccuracy {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        if ((Get-CorpArgmax $W $B $c) -eq $Alvos[$i]) { $total++ }
    }
    return $total
}

function Get-CorpPred {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int]$N)
    $out = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        $out += (Get-CorpArgmax $W $B $c)
    }
    return $out
}

function Get-CorpMargins {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $out = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        [long]$zAlvo = Get-CorpZ256 $W $B $c $Alvos[$i]
        [long]$segundo = -1000000
        for ($y = 0; $y -lt 25; $y++) {
            if ($y -ne $Alvos[$i]) {
                [long]$z = Get-CorpZ256 $W $B $c $y
                if ($z -gt $segundo) { $segundo = $z }
            }
        }
        $out += ($zAlvo - $segundo)
    }
    return $out
}

function Get-CorpGeneration {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $total = $Prefixo.Count
    for ($i = 0; $i -lt $total; $i++) { $saida[$i] = $Prefixo[$i] }
    if ($saida[$total - 1] -eq 24) {
        return [pscustomobject]@{ Saida = $saida; Total = $total }
    }
    while ($total -lt $Maximo) {
        [int[]]$seq = @($saida[0..($total - 1)])
        [int[]]$c = Get-CorpC16 $seq
        $proximo = Get-CorpArgmax $W $B $c
        $saida[$total] = $proximo
        $total++
        if ($proximo -eq 24) { break }
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
}

function Get-CorpGenLines {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $g = Get-CorpGeneration $W $B $Prefixo $Maximo
    $ids = @($g.Saida[0..($g.Total - 1)])
    $parada = if ($ids[$ids.Count - 1] -eq 24) { "PARE" } else { "MAXIMO" }
    $texto = (@($ids | ForEach-Object { Get-CorpWord $_ }) -join " ")
    return @(
        ("GERADO=" + ($ids -join " ")),
        "N=$($g.Total)",
        "PASSOS=$($g.Total - $Prefixo.Count)",
        "PARADA=$parada",
        "TEXTO=$texto"
    )
}

function Get-CorpParamLine {
    param([hashtable]$W, [hashtable]$B, [int]$Y)
    return "PARAM16=$Y " + ($W[$Y] -join " ") + " " + $B[$Y]
}

function Get-CorpParamLines {
    param([hashtable]$W, [hashtable]$B)
    $lines = @()
    for ($y = 0; $y -lt 25; $y++) { $lines += Get-CorpParamLine $W $B $y }
    return $lines
}

function Get-CorpMaxima {
    param([hashtable]$W, [hashtable]$B)
    $mw = 0; $mb = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($p = 0; $p -lt 12; $p++) {
            if ([Math]::Abs($W[$y][$p]) -gt $mw) { $mw = [Math]::Abs($W[$y][$p]) }
        }
        if ([Math]::Abs($B[$y]) -gt $mb) { $mb = [Math]::Abs($B[$y]) }
    }
    return "MAXIMO16=$mw $mb"
}

# --- Fontes, corpus e valores canonicos -------------------------------------

$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
$corpusFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $CorpusPath))
foreach ($path in @($sourceFull, $corpusFull)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "arquivo nao encontrado: $path" }
}

$corpusBytes = [IO.File]::ReadAllBytes($corpusFull)
$corpusSha256 = (Get-FileHash -LiteralPath $corpusFull -Algorithm SHA256).Hash.ToLowerInvariant()
$corpusText = [Text.Encoding]::ASCII.GetString($corpusBytes)
$corpusLines = @($corpusText.TrimEnd("`n").Split("`n"))
$ext = Get-CorpExtract $corpusLines
$ENT = [int[]]$ext.Entradas
$ALV = [int[]]$ext.Alvos

$sourceText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sourceFull))

$initW = New-CorpW
$initB = New-CorpB
$s0 = Get-CorpLoss $initW $initB $ENT $ALV 10

$finalW = Copy-CorpW $initW
$finalB = Copy-CorpB $initB
$train = Invoke-CorpTrain $finalW $finalB $ENT $ALV 10 4
$traj = $train.History
$pred = Get-CorpPred $finalW $finalB $ENT 10
$margins = Get-CorpMargins $finalW $finalB $ENT $ALV 10
$paramLines = Get-CorpParamLines $finalW $finalB
$maxLine = Get-CorpMaxima $finalW $finalB
$acc = Get-CorpAccuracy $finalW $finalB $ENT $ALV 10

$changedW = 0; $changedB = 0
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 12; $p++) {
        if ($finalW[$y][$p] -ne $initW[$y][$p]) { $changedW++ }
    }
    if ($finalB[$y] -ne $initB[$y]) { $changedB++ }
}

$revEnt = New-Object 'int[]' 30
$revAlv = New-Object 'int[]' 10
for ($i = 0; $i -lt 10; $i++) {
    $src = 9 - $i
    for ($k = 0; $k -lt 3; $k++) { $revEnt[$i * 3 + $k] = $ENT[$src * 3 + $k] }
    $revAlv[$i] = $ALV[$src]
}
$revW = Copy-CorpW $initW
$revB = Copy-CorpB $initB
$revTrain = Invoke-CorpTrain $revW $revB $revEnt $revAlv 10 4
$revTraj = $revTrain.History
$revAcc = Get-CorpAccuracy $revW $revB $revEnt $revAlv 10
$revPred = Get-CorpPred $revW $revB $revEnt 10
$revMax = Get-CorpMaxima $revW $revB
$diffParams = 0
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 12; $p++) {
        if ($finalW[$y][$p] -ne $revW[$y][$p]) { $diffParams++ }
    }
    if ($finalB[$y] -ne $revB[$y]) { $diffParams++ }
}

$capLines = @(
    "programa inicio inteiro real logico cadeia vazio pare",
    "funcao inicio logico real cadeia vazio inteiro pare",
    "se verdadeiro faca leia escreva retorne passo pare",
    "enquanto falso faca escreva leia retorne passo pare",
    "para real ate passo leia faca escreva pare",
    "se falso senao leia retorne escreva passo pare"
)
$capExt = Get-CorpExtract $capLines
$capEnt = [int[]]$capExt.Entradas
$capAlv = [int[]]$capExt.Alvos
$capS0 = Get-CorpLoss $initW $initB $capEnt $capAlv 30
$capW = Copy-CorpW $initW
$capB = Copy-CorpB $initB
$capTrain = Invoke-CorpTrain $capW $capB $capEnt $capAlv 30 1
$capS1 = $capTrain.History[1]
$capMax = Get-CorpMaxima $capW $capB

$stressW = Copy-CorpW $initW
$stressB = Copy-CorpB $initB
$stress = Invoke-CorpTrain $stressW $stressB $ENT $ALV 10 32
$s32 = $stress.History[32]
$stressMax = Get-CorpMaxima $stressW $stressB
$stressAcc = Get-CorpAccuracy $stressW $stressB $ENT $ALV 10

$ablW = Copy-CorpW $finalW
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 8; $p++) { $ablW[$y][$p] = 0 }
}
$ablLastAcc = Get-CorpAccuracy $ablW $finalB $ENT $ALV 10
$ablLastS = Get-CorpLoss $ablW $finalB $ENT $ALV 10
$ablOldW = Copy-CorpW $finalW
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 8; $p -lt 12; $p++) { $ablOldW[$y][$p] = 0 }
}
$ablOldAcc = Get-CorpAccuracy $ablOldW $finalB $ENT $ALV 10
$ablOldS = Get-CorpLoss $ablOldW $finalB $ENT $ALV 10

$heldLines = @(
    "para inteiro ate passo pare",
    "programa inicio leia falso pare",
    "se falso faca escreva pare",
    "funcao inicio retorne verdadeiro pare",
    "enquanto falso faca escreva pare"
)
$heldAcc = 0
$heldTotal = 0
foreach ($line in $heldLines) {
    $tk = Get-CorpTokenize $line
    for ($i = 3; $i -lt $tk.Ids.Count; $i++) {
        [int[]]$hseq = @($tk.Ids[$i - 3], $tk.Ids[$i - 2], $tk.Ids[$i - 1])
        [int[]]$hc = Get-CorpC16 $hseq
        if ((Get-CorpArgmax $finalW $finalB $hc) -eq $tk.Ids[$i]) { $heldAcc++ }
        $heldTotal++
    }
}

$first6Ent = New-Object 'int[]' 18
$first6Alv = New-Object 'int[]' 6
for ($i = 0; $i -lt 6; $i++) {
    for ($k = 0; $k -lt 3; $k++) { $first6Ent[$i * 3 + $k] = $ENT[$i * 3 + $k] }
    $first6Alv[$i] = $ALV[$i]
}
$h6W = Copy-CorpW $initW
$h6B = Copy-CorpB $initB
$h6 = Invoke-CorpTrain $h6W $h6B $first6Ent $first6Alv 6 4

# --- Tabelas canonicas da spec (conferencia do oraculo) --------------------

$frozenParams = @(
    "PARAM16=0 -2 -2 -4 0 3 1 0 1 -3 0 -1 -1 0",
    "PARAM16=1 -2 1 0 1 -1 -1 3 1 -1 2 1 5 2",
    "PARAM16=2 1 1 1 -1 -1 -2 -1 -5 2 -2 3 -4 -2",
    "PARAM16=3 1 -1 1 0 2 1 -1 0 3 -3 2 -1 -1",
    "PARAM16=4 -1 -1 0 0 1 2 2 2 -2 1 -1 3 1",
    "PARAM16=5 1 1 2 -2 0 0 -4 -3 -1 -3 2 -7 -2",
    "PARAM16=6 0 0 -1 -2 1 0 -3 3 -3 3 -5 -2 0",
    "PARAM16=7 3 0 1 2 1 -1 1 0 4 -4 4 0 -1",
    "PARAM16=8 0 0 -1 0 -1 -2 4 1 -2 2 0 3 3",
    "PARAM16=9 1 2 0 -1 -1 0 -4 -5 2 -2 2 -6 -3",
    "PARAM16=10 2 -1 3 1 1 0 -1 2 3 -3 2 -1 0",
    "PARAM16=11 -2 -1 -1 0 1 1 2 1 -3 1 0 3 1",
    "PARAM16=12 -2 1 -1 1 -3 -3 4 1 0 1 1 6 5",
    "PARAM16=13 1 0 -1 -2 2 1 -4 1 -3 3 -5 -3 -1",
    "PARAM16=14 2 0 2 1 1 -1 0 0 3 -3 3 2 0",
    "PARAM16=15 -3 0 -1 0 -2 0 2 1 -2 2 0 5 3",
    "PARAM16=16 1 1 -1 0 -2 0 -1 -4 1 -2 2 -6 -2",
    "PARAM16=17 2 -5 -3 -2 4 3 1 0 0 2 -3 1 -1",
    "PARAM16=18 1 0 -2 3 -3 0 -4 0 -4 0 1 4 6",
    "PARAM16=19 -1 0 1 2 -3 -1 3 2 0 1 1 6 3",
    "PARAM16=20 0 -1 -1 -3 2 1 -2 1 -3 4 -5 -3 -1",
    "PARAM16=21 4 -3 2 3 0 0 1 0 6 -3 3 1 -2",
    "PARAM16=22 -5 -1 -1 -2 0 1 3 1 -3 0 2 2 2",
    "PARAM16=23 -1 0 -1 4 3 -2 -4 -2 0 -3 3 -9 0",
    "PARAM16=24 -1 2 -2 -1 -1 3 3 -3 2 2 -8 -6 4"
)

$frozenIds = @(
    @(1, 3, 17, 22, 24),
    @(2, 3, 17, 23, 24),
    @(9, 22, 12, 17, 24),
    @(9, 23, 10, 18, 24),
    @(11, 22, 12, 18, 24)
)

$canonicalErrors = @()
if ($ext.Code -ne 0 -or $ext.N -ne 10) { $canonicalErrors += "extracao canonica: Code=$($ext.Code) N=$($ext.N)" }
if ($s0 -ne 8404936) { $canonicalErrors += "S0: $s0" }
if (($traj -join " ") -cne "8404936 1341188 651091 509249 436118") {
    $canonicalErrors += "historico: $($traj -join ' ')"
}
if ($acc -ne 10) { $canonicalErrors += "acertos: $acc" }
if (($pred -join " ") -cne "22 24 23 24 17 24 18 24 18 24") {
    $canonicalErrors += "PRED: $($pred -join ' ')"
}
if (($margins -join " ") -cne "11 350 17 119 4 102 161 115 125 224") {
    $canonicalErrors += "margens: $($margins -join ' ')"
}
if ($changedW -ne 253 -or $changedB -ne 22) {
    $canonicalErrors += "alterados: W=$changedW B=$changedB"
}
if (($paramLines -join "`n") -cne ($frozenParams -join "`n")) {
    $canonicalErrors += "tabela PARAM16 divergente"
}
if ($maxLine -cne "MAXIMO16=9 6") { $canonicalErrors += "maximos finais: $maxLine" }
if (($revTraj -join " ") -cne "8404936 1941318 727037 491309 377464") {
    $canonicalErrors += "historico inverso: $($revTraj -join ' ')"
}
if ($revAcc -ne 8) { $canonicalErrors += "acertos inversos: $revAcc" }
if (($revPred -join " ") -cne "24 17 24 18 24 17 24 22 24 22") {
    $canonicalErrors += "PRED inverso: $($revPred -join ' ')"
}
if ($revMax -cne "MAXIMO16=7 4") { $canonicalErrors += "maximos inversos: $revMax" }
if ($diffParams -ne 213) { $canonicalErrors += "DIF_PARAMS: $diffParams" }
if ($capExt.N -ne 30) { $canonicalErrors += "capacidade N: $($capExt.N)" }
if ($capS0 -ne 19563100) { $canonicalErrors += "capacidade S0: $capS0" }
if ($capS1 -ne 3361748) { $canonicalErrors += "capacidade S1: $capS1" }
if ($capMax -cne "MAXIMO16=7 5") { $canonicalErrors += "capacidade maxima: $capMax" }
if ($s32 -ne 310777) { $canonicalErrors += "S32: $s32" }
if ($stressMax -cne "MAXIMO16=12 10") { $canonicalErrors += "maximos E=32: $stressMax" }
if ($stressAcc -ne 10) { $canonicalErrors += "acertos E=32: $stressAcc" }
if ($ablLastAcc -ne 5 -or $ablLastS -ne 1058696) { $canonicalErrors += "ablacao ultimo: $ablLastAcc/$ablLastS" }
if ($ablOldAcc -ne 8 -or $ablOldS -ne 1180874) { $canonicalErrors += "ablacao antigos: $ablOldAcc/$ablOldS" }
if ($heldTotal -ne 10 -or $heldAcc -ne 1) { $canonicalErrors += "sonda fora do corpus: $heldAcc/$heldTotal" }
if ($h6.Code -ne 0) { $canonicalErrors += "treino H6 retornou $($h6.Code)" }

# --- Saidas esperadas por caso ----------------------------------------------

$idsLines = @()
foreach ($row in $frozenIds) { $idsLines += "IDS=" + ($row -join " ") }
for ($i = 0; $i -lt 5; $i++) {
    $tk = Get-CorpTokenize $corpusLines[$i]
    if ($tk.Code -ne 0 -or ($tk.Ids -join " ") -cne ($frozenIds[$i] -join " ")) {
        $canonicalErrors += "IDs canonicos da linha $($i + 1): $($tk.Ids -join ' ')"
    }
}

$expected = @{}

$expected["corp_integridade"] = @($idsLines) + @("CORPUS=OK LINHAS=5 TOKENS=25 EXEMPLOS=10")

$expected["corp_tokenizacao"] = @()
for ($i = 0; $i -lt 5; $i++) {
    $expected["corp_tokenizacao"] += $idsLines[$i]
    $expected["corp_tokenizacao"] += $idsLines[$i]
}
$expected["corp_tokenizacao"] += "M1_IDS=OK"

$expected["corp_janelas"] = @()
for ($i = 0; $i -lt 10; $i++) {
    $expected["corp_janelas"] += "EXEMPLO=$i CTX=$($ENT[$i * 3]) $($ENT[$i * 3 + 1]) $($ENT[$i * 3 + 2]) ALVO=$($ALV[$i])"
}
$expected["corp_janelas"] += "N=10"

$expected["corp_fronteiras"] = @(
    "EXEMPLO=0 CTX=1 3 17 ALVO=24",
    "EXEMPLO=1 CTX=9 22 12 ALVO=18",
    "EXEMPLO=2 CTX=22 12 18 ALVO=24",
    "EXEMPLO=3 CTX=11 23 10 ALVO=16",
    "EXEMPLO=4 CTX=23 10 16 ALVO=15",
    "EXEMPLO=5 CTX=10 16 15 ALVO=24",
    "N=6",
    "SOMA=6",
    "FRONTEIRAS=OK"
)

$expected["corp_unk"] = @(
    "ERRO=3 LINHA=0 TOKEN=4",
    "IDS_INTACTOS=OK",
    "ERRO=3 LINHA=3 TOKEN=4",
    "BUFFERS_INTACTOS=OK"
)

$invExpected = @("ERRO=1 LINHA=0 TOKEN=0")
$invCases = @(
    " programa inicio escreva pare",
    "Programa inicio",
    "programa inicio escreva",
    "programa inicio escreva verdadeiro falso leia retorne passo pare",
    "programa inicio escreva verdadeiro",
    "programa pare escreva pare",
    "programa`tinicio escreva pare"
)
foreach ($case in $invCases) {
    $r = Get-CorpExtract @($case)
    $invExpected += "ERRO=$($r.Code) LINHA=$($r.Line) TOKEN=$($r.Token)"
}
$invExpected += "ERRO=8 LINHA=0 TOKEN=0"
$r8 = Get-CorpExtract @("programa inicio inteiro real logico cadeia vazio pare")
$invExpected += "LIMITE=$($r8.Code) N=$($r8.N)"
$expected["corp_invalido"] = $invExpected

$expected["corp_duplicados"] = @(
    "ERRO=9 LINHA=2 TOKEN=4",
    "BUFFERS_INTACTOS=OK",
    "ERRO=10 LINHA=2 TOKEN=4",
    "BUFFERS_INTACTOS=OK"
)

$expected["corp_capacidade"] = @(
    "N=30",
    "UNICOS=OK",
    "S0=19563100",
    "HISTORICO=19563100 3361748",
    "LOTES=5",
    "MAXIMO16=7 5"
)

$expected["corp_lotes"] = @(
    ("H6_DIRETO=" + ($h6.History -join " ")),
    ("H6_LOTES=" + ($h6.History -join " ")),
    "IGUAL6=OK",
    ("H10_LOTES=" + ($traj -join " "))
)

$expected["corp_treino"] = @()
$expected["corp_treino"] += "HISTORICO=" + ($traj -join " ")
$expected["corp_treino"] += "PERDA=436118"
$expected["corp_treino"] += "ACERTOS=10"
$expected["corp_treino"] += "PRED=" + ($pred -join " ")
$expected["corp_treino"] += "MARGENS=" + ($margins -join " ")
$expected["corp_treino"] += "ALTERADOS_W=253"
$expected["corp_treino"] += "ALTERADOS_B=22"
$expected["corp_treino"] += $paramLines
$expected["corp_treino"] += "MAXIMO16=9 6"

$revLoss = Get-CorpLoss $revW $revB $revEnt $revAlv 10
$expected["corp_ordem"] = @()
$expected["corp_ordem"] += "ORDEM=DIRETA"
$expected["corp_ordem"] += "HISTORICO=" + ($traj -join " ")
$expected["corp_ordem"] += "PERDA=436118"
$expected["corp_ordem"] += "ACERTOS=10"
$expected["corp_ordem"] += "PRED=" + ($pred -join " ")
$expected["corp_ordem"] += "MAXIMO16=9 6"
$expected["corp_ordem"] += "ORDEM=INVERSA"
$expected["corp_ordem"] += "HISTORICO=" + ($revTraj -join " ")
$expected["corp_ordem"] += "PERDA=$revLoss"
$expected["corp_ordem"] += "ACERTOS=8"
$expected["corp_ordem"] += "PRED=" + ($revPred -join " ")
$expected["corp_ordem"] += "MAXIMO16=7 4"
$expected["corp_ordem"] += "DIF_PARAMS=213"
if ($revLoss -ne 377464) { $canonicalErrors += "perda inversa: $revLoss" }

$frozenGeracao = @(
    "GERADO=1 3 17 22 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=programa inicio escreva verdadeiro pare",
    "GERADO=9 22 12 17 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=se verdadeiro faca escreva pare",
    "GERADO=11 22 12 18 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=enquanto verdadeiro faca leia pare",
    "GERADO=9 23 10 18 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=se falso senao leia pare",
    "GERADO=2 3 17 23 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=funcao inicio escreva falso pare",
    "GERADO=22 12 24", "N=3", "PASSOS=0", "PARADA=PARE",
    "TEXTO=verdadeiro faca pare",
    "GERADO=1 3 17 22", "N=4", "PASSOS=1", "PARADA=MAXIMO",
    "TEXTO=programa inicio escreva verdadeiro",
    "GERADO=1 3 12 12 19 18 24", "N=7", "PASSOS=5", "PARADA=PARE",
    "TEXTO=programa inicio faca faca e leia pare"
)
$expected["corp_geracao"] = @()
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 64
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(9, 22, 12)) 64
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(11, 22, 12)) 64
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(9, 23, 10)) 64
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(2, 3, 17)) 64
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(22, 12, 24)) 64
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 4
$expected["corp_geracao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3)) 64
if (($expected["corp_geracao"] -join "`n") -cne ($frozenGeracao -join "`n")) {
    $canonicalErrors += "geracao divergente da spec"
}

$expected["corp_determinismo_a"] = @()
$expected["corp_determinismo_a"] += $paramLines
$expected["corp_determinismo_a"] += "MAXIMO16=9 6"
$expected["corp_determinismo_a"] += "HISTORICO=" + ($traj -join " ")
$expected["corp_determinismo_a"] += "PERDA=436118"
$expected["corp_determinismo_a"] += "ACERTOS=10"
$expected["corp_determinismo_a"] += "PRED=" + ($pred -join " ")
$expected["corp_determinismo_a"] += "MARGENS=" + ($margins -join " ")
$expected["corp_determinismo_a"] += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 64
$expected["corp_determinismo_b"] = $expected["corp_determinismo_a"]

$expected["corp_composicao"] = @()
for ($i = 0; $i -lt 5; $i++) {
    $expected["corp_composicao"] += $idsLines[$i]
    $expected["corp_composicao"] += $idsLines[$i]
}
$expected["corp_composicao"] += "M1_IDS=OK"
$expected["corp_composicao"] += "M3_OK=100"
$expected["corp_composicao"] += "M7_OK=10"
$expected["corp_composicao"] += "M8_OK=10"
$expected["corp_composicao"] += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 64

$expected["corp_pureza"] = @(
    "PARAMS_INTACTOS=OK",
    "IDS_INTACTOS=OK",
    "SAIDA_INTACTA=OK",
    "ERROS=11 12 13 14"
)

# --- V1: hashes congelados, diff aditivo e escopo ---------------------------

$v1Errors = @()
$frozenHashes = [ordered]@{
    "src/tokenizador.por"                 = "6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f"
    "src/embeddings.por"                  = "6f06aa820d163d3c1636383803b86105bf54cd85"
    "src/rede.por"                        = "fa9367a79bd2aefc373d30a94cfca2b7c86d9958"
    "src/treino.por"                      = "f5121423dd0aac6469b59b24b13d8a85b2c0d64d"
    "src/gerador.por"                     = "532e60cc52cef03fbd60c2a9d2b530472c73ded1"
    "src/contexto.por"                    = "9da552861c58d145a1d1c52442e0c27a4c42ce2e"
    "scripts/build-tests.ps1"             = "1cfb01202586a83c4d7ec08ff738a8e90fb19044"
    "scripts/verify-bytes.ps1"            = "851afbbad494778f019bf2ce70e82b0b575ab443"
    "scripts/build-embedding-tests.ps1"   = "94d1a3819b76b4d614f4422bf00b0cd2c008daaf"
    "scripts/verify-embedding-bytes.ps1"  = "4f3aa68e499a9dc3289d22ebae5b8d1c18086651"
    "scripts/build-network-tests.ps1"     = "998e91b2896e9ec40bc1814990a0a53ae740fb3e"
    "scripts/verify-network-bytes.ps1"    = "1f46800852fed34d840206ca97bc84badd109b31"
    "scripts/build-training-tests.ps1"    = "c587e161e19d353af23f0cb9d055119b288c2675"
    "scripts/verify-training-bytes.ps1"   = "f59fee82d337e13f619360e63d6e928aef8e0f6b"
    "scripts/build-generation-tests.ps1"  = "e712064d631e6fbf2711943ec65da6812223427f"
    "scripts/verify-generation-bytes.ps1" = "e1807a8d6469ecaba0d2ad724c9e58b6a2689b3a"
    "scripts/build-context-tests.ps1"     = "e9dd6d1ba2b54eb4caade4391a3da12cb555f29d"
    "scripts/verify-context-bytes.ps1"    = "463fe02275926f9942f9b61c506b0ad26450f78c"
}
$hashPaths = @($frozenHashes.Keys)
$actualHashes = @(& git -C $repoRoot hash-object -- $hashPaths 2>$null)
if ($actualHashes.Count -ne $hashPaths.Count) {
    $v1Errors += "git hash-object retornou $($actualHashes.Count) hashes; esperado $($hashPaths.Count)"
} else {
    for ($i = 0; $i -lt $hashPaths.Count; $i++) {
        $want = $frozenHashes[$hashPaths[$i]]
        if ($actualHashes[$i] -cne $want) {
            $v1Errors += "$($hashPaths[$i]): $($actualHashes[$i]); esperado $want"
        }
    }
}

$testPath = Join-Path $repoRoot "scripts/test.ps1"
if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
    $v1Errors += "scripts/test.ps1 ausente"
} else {
    $testBytes = [IO.File]::ReadAllBytes($testPath)
    if ($testBytes.Length -lt 4 -or $testBytes[0] -ne 0xEF -or $testBytes[1] -ne 0xBB -or $testBytes[2] -ne 0xBF) {
        $v1Errors += "test.ps1 sem BOM UTF-8"
    }
    foreach ($b in $testBytes) {
        if ($b -eq 0x0D) { $v1Errors += "test.ps1 com CR"; break }
    }
    if ($testBytes[$testBytes.Length - 1] -ne 0x7D) {
        $v1Errors += ("test.ps1 ultimo byte 0x{0:X2}; esperado 0x7D" -f $testBytes[$testBytes.Length - 1])
    }
    $testText = [Text.Encoding]::UTF8.GetString($testBytes, 3, $testBytes.Length - 3)
    $testLines = @($testText -split "`n")
    $lineCount = if ($testLines[$testLines.Count - 1] -eq "") { $testLines.Count - 1 } else { $testLines.Count }
    if ($lineCount -ne 402) { $v1Errors += "test.ps1 com $lineCount linhas; esperado 402" }
    $marker = "    # Gerar e anexar os casos do treinamento com corpus textual (M8). Diretorio"
    $blockStart = [Array]::IndexOf($testLines, $marker)
    if ($blockStart -lt 0) {
        $v1Errors += "bloco aditivo M8 ausente em test.ps1"
    } else {
        $block = @($testLines[($blockStart - 1)..($blockStart + 23)])
        if ($block.Count -ne 25) { $v1Errors += "bloco aditivo com $($block.Count) linhas; esperado 25" }
        if ($testLines[$blockStart - 1] -ne "") { $v1Errors += "bloco aditivo sem linha em branco anterior" }
        if ($testLines[$blockStart + 23] -ne "    }") { $v1Errors += "bloco aditivo nao termina em fechamento de foreach" }
        foreach ($needle in @(
            "build-corpus-tests.ps1", "corpusRoot = `"temp/corpus-tests`"",
            "corpusGenerated", "no corpus test cases found"
        )) {
            if (-not (($block -join "`n").Contains($needle))) {
                $v1Errors += "bloco aditivo nao contem: $needle"
            }
        }
        $reconstructed = @()
        if ($blockStart - 2 -ge 0) { $reconstructed += $testLines[0..($blockStart - 2)] }
        if ($blockStart + 24 -le $testLines.Count - 1) {
            $reconstructed += $testLines[($blockStart + 24)..($testLines.Count - 1)]
        }
        $reconPath = Join-Path $repoRoot "temp/m8-reconstructed-test.ps1"
        $reconText = ($reconstructed -join "`n")
        [IO.File]::WriteAllText($reconPath, $reconText, (New-Object System.Text.UTF8Encoding($true)))
        $reconHash = (& git -C $repoRoot hash-object -- "temp/m8-reconstructed-test.ps1" 2>$null)
        if ($reconHash -cne "b5f2f03255de984807f3d4d1c4d46d33d238958c") {
            $v1Errors += "test.ps1 sem o bloco nao reconstroi o hash de HEAD: $reconHash"
        }
        $ifIndex = -1
        for ($i = 0; $i -lt $testLines.Count; $i++) {
            if ($testLines[$i] -eq "if (-not `$SelfTest) {") { $ifIndex = $i }
        }
        if ($ifIndex -lt 0 -or $blockStart -le $ifIndex) {
            $v1Errors += "bloco aditivo fora de if (-not `$SelfTest)"
        }
        $selfIndex = [Array]::IndexOf($testLines, "if (`$SelfTest) {")
        if ($selfIndex -lt 0 -or $blockStart -ge $selfIndex) {
            $v1Errors += "bloco aditivo depois de if (`$SelfTest)"
        }
    }
}

$allowedStatus = @(
    " M scripts/test.ps1",
    " M scripts/verify-context-bytes.ps1",
    "?? corpus/",
    "?? docs/corpus-plan.md",
    "?? docs/corpus-spec.md",
    "?? scripts/build-corpus-tests.ps1",
    "?? scripts/verify-corpus-bytes.ps1",
    "?? src/corpus.por"
)
$statusLines = @(& git -C $repoRoot status --short 2>$null | ForEach-Object { $_.TrimEnd() })
$unexpected = @($statusLines | Where-Object { $allowedStatus -notcontains $_ })
if ($unexpected.Count -gt 0) {
    $v1Errors += "git status fora do escopo: " + ($unexpected -join " | ")
}
Write-Check "V1 18 hashes congelados, diff aditivo de test.ps1 e escopo do git status" $v1Errors

# --- V2: conjunto de casos e codificacao ------------------------------------

if (-not (Test-Path -LiteralPath $InterpreterPath)) { Fail "interpretador nao encontrado: $InterpreterPath" }
$generatedFull = Join-Path $repoRoot $GeneratedRoot
if (-not (Test-Path -Path $generatedFull)) { Fail "diretorio de casos nao encontrado: $generatedFull" }

$expectedCases = @(
    "corp_capacidade", "corp_composicao", "corp_determinismo_a", "corp_determinismo_b",
    "corp_duplicados", "corp_fronteiras", "corp_geracao", "corp_integridade",
    "corp_invalido", "corp_janelas", "corp_lotes", "corp_ordem", "corp_pureza",
    "corp_tokenizacao", "corp_treino", "corp_unk"
)

$expectedFiles = @(Get-ChildItem -Path $generatedFull -Filter "*.expected" -File | Sort-Object Name)
$actualNames = @($expectedFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
$porFiles = @(Get-ChildItem -Path $generatedFull -Filter "*.por" -File)
$v2Errors = @()
if ((($actualNames | Sort-Object) -join "|") -cne (($expectedCases | Sort-Object) -join "|")) {
    $v2Errors += "conjunto de casos diverge.`n  Esperado: " + ($expectedCases -join ", ") + "`n  Obtido:   " + ($actualNames -join ", ")
}
if ($expectedFiles.Count -ne 16) { $v2Errors += "arquivos .expected: $($expectedFiles.Count); esperado 16" }
if ($porFiles.Count -ne 16) { $v2Errors += "arquivos .por: $($porFiles.Count); esperado 16" }

foreach ($file in $expectedFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -eq 0) { $v2Errors += "$($file.Name): vazio"; continue }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $v2Errors += "$($file.Name): BOM"
    }
    if ($bytes[$bytes.Length - 1] -eq 0x0A) { $v2Errors += "$($file.Name): LF final" }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $v2Errors += "$($file.Name): CR"; break }
        if ($b -gt 0x7E) { $v2Errors += ("$($file.Name): byte 0x{0:X2}" -f $b); break }
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    foreach ($line in @($text -split "`n")) {
        if ($line -ne $line.Trim()) { $v2Errors += "$($file.Name): espaco nas pontas"; break }
    }
}
foreach ($file in $porFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -eq 0) { $v2Errors += "$($file.Name): vazio"; continue }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $v2Errors += "$($file.Name): BOM"
    }
    if ($bytes[$bytes.Length - 1] -ne 0x0A) { $v2Errors += "$($file.Name): nao termina em LF" }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $v2Errors += "$($file.Name): CR"; break }
        if ($b -gt 0x7E) { $v2Errors += ("$($file.Name): byte nao ASCII 0x{0:X2}" -f $b); break }
    }
}

foreach ($doc in @($SpecPath, $PlanPath)) {
    $docPath = Join-Path $repoRoot $doc
    if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) {
        $v2Errors += "$doc ausente"
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($docPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $v2Errors += "$doc com BOM"
    }
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 0x0A) {
        $v2Errors += "$doc nao termina em LF"
    } elseif ($bytes.Length -ge 2 -and $bytes[$bytes.Length - 2] -eq 0x0A) {
        $v2Errors += "$doc termina com mais de um LF"
    }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $v2Errors += "$doc com CR"; break }
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void]$strict.GetString($bytes)
    } catch {
        $v2Errors += "$doc nao e UTF-8 valido"
    }
}

$sourceBytes = [IO.File]::ReadAllBytes($sourceFull)
if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) {
    $v2Errors += "src/corpus.por com BOM"
}
if ($sourceBytes.Length -eq 0 -or $sourceBytes[$sourceBytes.Length - 1] -ne 0x0A) {
    $v2Errors += "src/corpus.por nao termina em LF"
}
foreach ($b in $sourceBytes) {
    if ($b -eq 0x0D) { $v2Errors += "src/corpus.por com CR"; break }
    if ($b -gt 0x7E) { $v2Errors += ("src/corpus.por byte nao ASCII 0x{0:X2}" -f $b); break }
}

foreach ($script in @("scripts/build-corpus-tests.ps1", "scripts/verify-corpus-bytes.ps1")) {
    $scriptPath = Join-Path $repoRoot $script
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $v2Errors += "$script ausente"
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($scriptPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $v2Errors += "$script com BOM"
    }
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 0x0A) {
        $v2Errors += "$script nao termina em LF"
    }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $v2Errors += "$script com CR"; break }
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void]$strict.GetString($bytes)
    } catch {
        $v2Errors += "$script nao e UTF-8 valido"
    }
}
Write-Check "V2 conjunto de 16 casos, .por/.expected, docs, fonte e scripts com codificacao contratada" $v2Errors
if ($v2Errors.Count -gt 0) { exit 1 }

Write-Host "=== Verificacao do corpus textual e do treino M8 ==="
Write-Host "Fonte:         $SourcePath"
Write-Host "Corpus:        $CorpusPath"
Write-Host "Casos:         $GeneratedRoot"
Write-Host "Interpretador: $InterpreterPath"
Write-Host "Casos esperados: $($expectedCases.Count)"

# --- V3: bytes e conteudo do corpus -----------------------------------------

$v3Errors = @()
if ($corpusBytes.Length -ne 165) { $v3Errors += "bytes: $($corpusBytes.Length); esperado 165" }
if ($corpusSha256 -cne "d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113") {
    $v3Errors += "SHA-256: $corpusSha256"
}
$lfCount = 0
foreach ($b in $corpusBytes) {
    if ($b -eq 0x0A) {
        $lfCount++
    } elseif ($b -lt 0x20 -or $b -gt 0x7E) {
        $v3Errors += ("byte invalido 0x{0:X2}" -f $b)
        break
    }
}
if ($lfCount -ne 5) { $v3Errors += "LF: $lfCount; esperado 5" }
if ($corpusBytes[$corpusBytes.Length - 1] -ne 0x0A) { $v3Errors += "corpus sem LF final" }
$frozenCorpus = @(
    "programa inicio escreva verdadeiro pare",
    "funcao inicio escreva falso pare",
    "se verdadeiro faca escreva pare",
    "se falso senao leia pare",
    "enquanto verdadeiro faca leia pare"
)
if ($corpusLines.Count -ne 5) { $v3Errors += "linhas: $($corpusLines.Count); esperado 5" }
if (($corpusLines -join "`n") -cne ($frozenCorpus -join "`n")) {
    $v3Errors += "conteudo do corpus divergente da spec"
}
$tokenTotal = 0
foreach ($line in $corpusLines) {
    $parts = @($line.Split(' '))
    if ($parts.Count -ne 5) { $v3Errors += "linha com $($parts.Count) tokens: [$line]" }
    foreach ($part in $parts) {
        if ($part -ceq "UNK" -or (Get-CorpWordId $part) -le 0) {
            $v3Errors += "token desconhecido no corpus: [$part]"
        }
    }
    $tokenTotal += $parts.Count
}
if ($tokenTotal -ne 25) { $v3Errors += "tokens: $tokenTotal; esperado 25" }
if ($ext.Code -ne 0 -or $ext.N -ne 10) {
    $v3Errors += "extracao: Code=$($ext.Code) N=$($ext.N); esperado 0/10"
}
Write-Check "V3 corpus 165 bytes, SHA-256, 5x5 tokens, ASCII/LF e 10 exemplos" $v3Errors

# --- Execucao crua ----------------------------------------------------------

function Invoke-CaseRaw {
    param([string]$Path)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $InterpreterPath
    $psi.Arguments = "`"$Path`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.WriteLine(" ")
    $proc.StandardInput.Close()

    $outStream = New-Object System.IO.MemoryStream
    $errStream = New-Object System.IO.MemoryStream
    $proc.StandardOutput.BaseStream.CopyTo($outStream)
    $proc.StandardError.BaseStream.CopyTo($errStream)
    $proc.WaitForExit()

    return [pscustomobject]@{
        Bytes  = $outStream.ToArray()
        Errors = $errStream.ToArray()
    }
}

function Test-RawCase {
    param([string]$Name, [byte[]]$Bytes, [byte[]]$ErrBytes)
    $errors = @()
    if ($ErrBytes.Length -gt 0) {
        $errors += ("stderr nao vazio: " + [Text.Encoding]::GetEncoding(1252).GetString($ErrBytes))
    }

    $payloadLines = @()
    if ($Bytes.Length -lt (1 + $epilogueBytes.Length)) {
        $errors += "saida curta demais: $($Bytes.Length) bytes"
        return [pscustomobject]@{ Errors = $errors; Lines = $payloadLines }
    }
    if ($Bytes[0] -ne 0x0C) {
        $errors += ("offset 0: 0x{0:X2}; esperado 0x0C" -f $Bytes[0])
    }

    $tailStart = $Bytes.Length - $epilogueBytes.Length
    for ($k = 0; $k -lt $epilogueBytes.Length; $k++) {
        if ($Bytes[$tailStart + $k] -ne $epilogueBytes[$k]) {
            $errors += ("epilogo diverge no byte {0}: 0x{1:X2}; esperado 0x{2:X2}" -f $k, $Bytes[$tailStart + $k], $epilogueBytes[$k])
            break
        }
    }
    for ($i = 1; $i -lt $tailStart; $i++) {
        $b = $Bytes[$i]
        if ($b -eq 0x0D) { $errors += "CR dentro da carga no offset $i"; break }
        if ($b -lt 0x20 -or $b -gt 0x7E) {
            if ($b -ne 0x0A) { $errors += ("byte fora da carga ASCII 0x{0:X2} no offset {1}" -f $b, $i); break }
        }
    }

    $payload = [Text.Encoding]::ASCII.GetString($Bytes, 1, $tailStart - 1)
    if (-not $payload.EndsWith("`n")) {
        $errors += "carga nao termina em LF"
    } else {
        $body = $payload.Substring(0, $payload.Length - 1)
        $payloadLines = @($body -split "`n")
    }

    $expectedLines = @($expected[$Name])
    if ($payloadLines.Count -ne $expectedLines.Count) {
        $errors += "numero de linhas: $($payloadLines.Count); esperado $($expectedLines.Count)"
    }
    $limit = [Math]::Min($payloadLines.Count, $expectedLines.Count)
    for ($i = 0; $i -lt $limit; $i++) {
        if ($payloadLines[$i] -cne $expectedLines[$i]) {
            $errors += "linha $($i + 1) difere.`n    Esperado: [$($expectedLines[$i])]`n    Obtido:   [$($payloadLines[$i])]"
        }
    }

    return [pscustomobject]@{ Errors = $errors; Lines = $payloadLines }
}

$runs = @{}
$linesByName = @{}
foreach ($name in $expectedCases) {
    $porPath = Join-Path $generatedFull "$name.por"
    if (-not (Test-Path -LiteralPath $porPath)) { Fail "arquivo ausente: $porPath" }
    $run = Invoke-CaseRaw $porPath
    $check = Test-RawCase $name $run.Bytes $run.Errors
    $runs[$name] = $run
    $linesByName[$name] = $check.Lines
    if ($check.Errors.Count -gt 0) {
        foreach ($e in $check.Errors) { Write-Host "  ${name}: $e" -ForegroundColor Gray }
    }
}

function Compare-Lines {
    param([string]$Name, [string[]]$Want)
    $errors = @()
    if (-not $linesByName.ContainsKey($Name)) {
        return @("$Name nao executado")
    }
    $got = @($linesByName[$Name])
    if ($got.Count -ne $Want.Count) {
        $errors += "${Name}: $($got.Count) linhas; esperado $($Want.Count)"
    }
    $limit = [Math]::Min($got.Count, $Want.Count)
    for ($i = 0; $i -lt $limit; $i++) {
        if ($got[$i] -cne $Want[$i]) {
            $errors += "${Name} linha $($i + 1): esperado [$($Want[$i])]; obtido [$($got[$i])]"
        }
    }
    return $errors
}

# --- V4: integridade do corpus ---------------------------------------------

$v4Errors = @(Compare-Lines "corp_integridade" $expected["corp_integridade"])

# --- V5: tokenizacao -------------------------------------------------------

$v5Errors = @(Compare-Lines "corp_tokenizacao" $expected["corp_tokenizacao"])

# --- V6: janelas -----------------------------------------------------------

$v6Errors = @(Compare-Lines "corp_janelas" $expected["corp_janelas"])

# --- V7: fronteiras --------------------------------------------------------

$v7Errors = @(Compare-Lines "corp_fronteiras" $expected["corp_fronteiras"])

# --- V8: UNK ---------------------------------------------------------------

$v8Errors = @(Compare-Lines "corp_unk" $expected["corp_unk"])

# --- V9: entradas invalidas ------------------------------------------------

$v9Errors = @(Compare-Lines "corp_invalido" $expected["corp_invalido"])

# --- V10: duplicados -------------------------------------------------------

$v10Errors = @(Compare-Lines "corp_duplicados" $expected["corp_duplicados"])

# --- V11: capacidade -------------------------------------------------------

$v11Errors = @(Compare-Lines "corp_capacidade" $expected["corp_capacidade"])
if ($capExt.N -ne 30) { $v11Errors += "oraculo: N=$($capExt.N); esperado 30" }
if ($capS0 -ne 19563100) { $v11Errors += "oraculo: S0=$capS0" }
if ($capS1 -ne 3361748) { $v11Errors += "oraculo: S1=$capS1" }
if ($capMax -cne "MAXIMO16=7 5") { $v11Errors += "oraculo: $capMax" }

# --- V12: lotes ------------------------------------------------------------

$v12Errors = @(Compare-Lines "corp_lotes" $expected["corp_lotes"])
if ($h6.Code -ne 0) { $v12Errors += "oraculo: treino H6 retornou $($h6.Code)" }

# --- V13: treino canonico --------------------------------------------------

$v13Errors = @(Compare-Lines "corp_treino" $expected["corp_treino"])
$v13Errors += $canonicalErrors

# --- V14: ordem direta e inversa ------------------------------------------

$v14Errors = @(Compare-Lines "corp_ordem" $expected["corp_ordem"])
if ($diffParams -ne 213) { $v14Errors += "oraculo: DIF_PARAMS=$diffParams" }

# --- V15: geracao ----------------------------------------------------------

$v15Errors = @(Compare-Lines "corp_geracao" $expected["corp_geracao"])

# --- V16: determinismo -----------------------------------------------------

$v16Errors = @(Compare-Lines "corp_determinismo_a" $expected["corp_determinismo_a"])
$v16Errors += @(Compare-Lines "corp_determinismo_b" $expected["corp_determinismo_b"])
$bytesA = $runs["corp_determinismo_a"].Bytes
$bytesB = $runs["corp_determinismo_b"].Bytes
if ($bytesA.Length -ne $bytesB.Length) {
    $v16Errors += "A/B com tamanhos diferentes: $($bytesA.Length) e $($bytesB.Length)"
} else {
    for ($i = 0; $i -lt $bytesA.Length; $i++) {
        if ($bytesA[$i] -ne $bytesB[$i]) {
            $v16Errors += "A/B divergem no byte $i"
            break
        }
    }
}

# --- V17: composicao e pureza ---------------------------------------------

$v17Errors = @(Compare-Lines "corp_composicao" $expected["corp_composicao"])
$v17Errors += @(Compare-Lines "corp_pureza" $expected["corp_pureza"])

# --- V18: regressao completa ----------------------------------------------

$v18Errors = @()
$psExe = (Get-Process -Id $PID).Path
$suiteLog = Join-Path $repoRoot "temp/m8-verify-suite.log"
$suiteOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts/test.ps1") 2>&1 | Out-String
$suiteCode = $LASTEXITCODE
[IO.File]::WriteAllText($suiteLog, $suiteOut, (New-Object System.Text.UTF8Encoding($false)))
if ($suiteCode -ne 0) { $v18Errors += "suite saiu com $suiteCode" }
if ($suiteOut -notmatch 'Passed:\s+116') { $v18Errors += "suite nao reportou 116 PASS" }
if ($suiteOut -notmatch 'Failed:\s+0') { $v18Errors += "suite nao reportou 0 FAIL" }
if ($suiteOut -notmatch 'Total:\s+116') { $v18Errors += "suite nao reportou Total 116" }

$selfLog = Join-Path $repoRoot "temp/m8-verify-selftest.log"
$selfOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts/test.ps1") -SelfTest 2>&1 | Out-String
$selfCode = $LASTEXITCODE
[IO.File]::WriteAllText($selfLog, $selfOut, (New-Object System.Text.UTF8Encoding($false)))
if ($selfCode -ne 1) { $v18Errors += "autoteste saiu com $selfCode; esperado 1" }
if ($selfOut -notmatch 'Passed:\s+0') { $v18Errors += "autoteste nao reportou 0 PASS" }
if ($selfOut -notmatch 'Failed:\s+1') { $v18Errors += "autoteste nao reportou 1 FAIL" }

$verifiers = @(
    @{ Script = "verify-bytes.ps1"; Checks = 21 },
    @{ Script = "verify-embedding-bytes.ps1"; Checks = 19 },
    @{ Script = "verify-network-bytes.ps1"; Checks = 22 },
    @{ Script = "verify-training-bytes.ps1"; Checks = 23 },
    @{ Script = "verify-generation-bytes.ps1"; Checks = 13 },
    @{ Script = "verify-context-bytes.ps1"; Checks = 16 }
)
foreach ($v in $verifiers) {
    $path = Join-Path $repoRoot ("scripts/" + $v.Script)
    $log = Join-Path $repoRoot ("temp/m8-verify-" + $v.Script + ".log")
    $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $path 2>&1 | Out-String
    $code = $LASTEXITCODE
    [IO.File]::WriteAllText($log, $out, (New-Object System.Text.UTF8Encoding($false)))
    if ($code -ne 0) { $v18Errors += "$($v.Script) saiu com $code" }
    $countOk = ($out -match ("Checks:\s+" + $v.Checks)) -or
        ($out -match ("Total:\s+" + $v.Checks + "\s+verificacoes,\s+0\s+falha"))
    if (-not $countOk) { $v18Errors += "$($v.Script) nao reportou $($v.Checks) verificacoes" }
    if ($out -notmatch 'Failures:\s+0' -and $out -notmatch 'verificacoes,\s+0\s+falha') {
        $v18Errors += "$($v.Script) nao reportou zero falhas"
    }
}

# --- Resumo ----------------------------------------------------------------

Write-Check "V4 integridade do corpus (5 linhas, 25 tokens, 10 exemplos)" $v4Errors
Write-Check "V5 tokenizacao canonica e IDs da M1" $v5Errors
Write-Check "V6 janelas K=3 (10 exemplos na ordem do corpus)" $v6Errors
Write-Check "V7 fronteiras de linha (nenhuma janela entre linhas)" $v7Errors
Write-Check "V8 UNK rejeitado sem tocar nos buffers" $v8Errors
Write-Check "V9 entradas invalidas e precedencia de erros" $v9Errors
Write-Check "V10 contextos duplicados e conflitos" $v10Errors
Write-Check "V11 capacidade N=30, S0/S1 e lotes" $v11Errors
Write-Check "V12 lotes 6+4 equivalentes a passagem global" $v12Errors
Write-Check "V13 treino canonico, margens, parametros e 253/22" $v13Errors
Write-Check "V14 ordem direta/inversa e 213 diferencas" $v14Errors
Write-Check "V15 geracao, PARE/MAXIMO e projecao de texto" $v15Errors
Write-Check "V16 determinismo A = B byte a byte" $v16Errors
Write-Check "V17 composicao M1/M3/M7/M8 e pureza" $v17Errors
Write-Check "V18 suite 116/116, autoteste 0/1 e verificadores M1-M7" $v18Errors

Write-Host ""
Write-Host "=== Resultado ==="
Write-Host "Checks:   $script:checks"
Write-Host "Failures: $script:failures"
Write-Host "Casos:    $($expectedCases.Count) executados"

if ($script:failures -gt 0) {
    Write-Host "Verificacao do corpus M8 FALHOU." -ForegroundColor Red
    exit 1
}
Write-Host "Verificacao do corpus M8 aprovada." -ForegroundColor Green
exit 0
