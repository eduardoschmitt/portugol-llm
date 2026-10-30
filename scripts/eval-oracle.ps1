<#
.SYNOPSIS
    Oraculos independentes O1 (inteiro) e O2 (BigInteger) da avaliacao M9.

.DESCRIPTION
    O1 reimplementa init, treino, forward, argmax, perda, metricas e o relatorio
    de bytes sem importar funcoes do modulo .por. O2 audita a agregacao de S,
    m_b e M com precisao arbitraria. O3 e um conjunto de literais manuais
    conferido no verificador.

    Uso como biblioteca:
        . ./scripts/eval-oracle.ps1 -Quiet

    Uso direto:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/eval-oracle.ps1 -SelfCheck
#>

param(
    [switch]$Quiet,
    [switch]$SelfCheck,
    [string]$Case = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$script:EvalOracleRoot = Split-Path -Parent $PSScriptRoot
if (-not $script:EvalOracleRoot) { $script:EvalOracleRoot = (Get-Location).Path }
. (Join-Path $script:EvalOracleRoot "scripts/eval-datasets.ps1") -Quiet

$script:EvalWords = @(
    "UNK", "programa", "funcao", "inicio", "inteiro", "real", "logico",
    "cadeia", "vazio", "se", "senao", "enquanto", "faca", "para", "ate",
    "passo", "retorne", "escreva", "leia", "e", "ou", "nao", "verdadeiro",
    "falso", "pare"
)

function Get-EvalWord {
    param([int]$Id)
    return $script:EvalWords[$Id]
}

# --- Estado, forward e treino ------------------------------------------------

function New-EvalW {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($k = 0; $k -lt 3; $k++) {
            for ($d = 0; $d -lt 4; $d++) {
                if ($k -lt 2) { $row[$k * 4 + $d] = 0 }
                else { $row[$k * 4 + $d] = (($y * 7 + $d * 5) % 25) - 12 }
            }
        }
        $w[$y] = $row
    }
    return $w
}

function New-EvalB {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-EvalW {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($p = 0; $p -lt 12; $p++) { $row[$p] = $W[$y][$p] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-EvalB {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-EvalE16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

function Get-EvalC16 {
    param([int[]]$Seq)
    $c = New-Object 'int[]' 12
    for ($k = 0; $k -lt 3; $k++) {
        $pos = $Seq.Count - 3 + $k
        if ($pos -ge 0) {
            for ($d = 0; $d -lt 4; $d++) {
                $c[$k * 4 + $d] = Get-EvalE16 $Seq[$pos] $d
            }
        }
    }
    return $c
}

function Get-EvalC16FromExample {
    param([int[]]$Entradas, [int]$N)
    return Get-EvalC16 ([int[]]@($Entradas[$N * 3], $Entradas[$N * 3 + 1], $Entradas[$N * 3 + 2]))
}

function Get-EvalZ256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y)
    [long]$soma = 0
    for ($p = 0; $p -lt 12; $p++) {
        $soma += [long]$W[$Y][$p] * [long]$C[$p]
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-EvalDelta256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y, [int]$Alvo)
    [long]$z = Get-EvalZ256 $W $B $C $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-EvalArgmax {
    param([hashtable]$W, [hashtable]$B, [int[]]$C)
    $melhor = 0
    [long]$melhorValor = Get-EvalZ256 $W $B $C 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-EvalZ256 $W $B $C $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-EvalExampleS {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int]$I, [int]$Alvo)
    [int[]]$c = Get-EvalC16FromExample $Entradas $I
    [long]$soma = 0
    for ($y = 0; $y -lt 25; $y++) {
        [long]$delta = Get-EvalDelta256 $W $B $c $y $Alvo
        $soma += $delta * $delta
    }
    return $soma
}

function Get-EvalLoss {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        $soma += Get-EvalExampleS $W $B $Entradas $i $Alvos[$i]
    }
    return $soma
}

function Get-EvalRound {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

function Invoke-EvalTrain {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-EvalLoss $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            [int[]]$c = Get-EvalC16FromExample $Entradas $i
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-EvalDelta256 $W $B $c $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($p = 0; $p -lt 12; $p++) {
                    [long]$novo = Get-EvalRound (2048 * [long]$W[$y][$p] - $delta[$y] * [long]$c[$p]) 2048
                    $W[$y][$p] = [int]$novo
                    if ([Math]::Abs($novo) -gt 16) {
                        return [pscustomobject]@{ Code = 5; History = $history }
                    }
                }
                [long]$novoB = Get-EvalRound (128 * [long]$B[$y] - $delta[$y]) 128
                $B[$y] = [int]$novoB
                if ([Math]::Abs($novoB) -gt 16) {
                    return [pscustomobject]@{ Code = 5; History = $history }
                }
            }
        }
        $history[$ep] = Get-EvalLoss $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history }
}

function Get-EvalChecksum {
    param([hashtable]$W, [hashtable]$B)
    [long]$soma = 0
    for ($i = 0; $i -lt 300; $i++) {
        $soma += ($i + 1) * [long]$W[[int][Math]::Floor($i / 12)][$i % 12]
    }
    for ($i = 0; $i -lt 25; $i++) {
        $soma += ($i + 1) * [long]$B[$i]
    }
    return $soma
}

# --- Metricas ----------------------------------------------------------------

function Get-EvalBp {
    param([int]$Acertos, [int]$N)
    if ($N -lt 1) { return -1 }
    return Get-EvalRound (10000 * [long]$Acertos) ([long]$N)
}

function Get-EvalMilesimos {
    param([long]$S, [int]$N)
    if ($N -lt 1 -or $N -gt 6 -or $S -lt 0) { return -1 }
    [long]$den = 131072 * [long]$N
    [long]$q = [long][Math]::Floor($S / $den)
    [long]$r = $S % $den
    return 1000 * $q + [long][Math]::Floor((1000 * $r) / $den)
}

function Get-EvalMediaMilesimos {
    param([object[]]$Batches, [int]$N)
    [long]$soma = 0
    foreach ($b in $Batches) {
        [long]$m = Get-EvalMilesimos $b.S $b.N
        $soma += $m * $b.N
    }
    return [long][Math]::Floor($soma / $N)
}

function Get-EvalMetrics {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int[]]$Conf)
    $batches = @()
    for ($base = 0; $base -lt $N; $base += 6) {
        $tam = [Math]::Min(6, $N - $base)
        [long]$s = 0
        for ($j = 0; $j -lt $tam; $j++) {
            $s += Get-EvalExampleS $W $B $Entradas ($base + $j) $Alvos[$base + $j]
        }
        $batches += [pscustomobject]@{ N = $tam; S = $s }
    }
    $preds = New-Object 'int[]' $N
    $oks = New-Object 'int[]' $N
    $zp = New-Object 'long[]' $N
    $zt = New-Object 'long[]' $N
    $mz = New-Object 'long[]' $N
    $acertos = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-EvalC16FromExample $Entradas $i
        $p = Get-EvalArgmax $W $B $c
        $preds[$i] = $p
        if ($p -eq $Alvos[$i]) {
            $acertos++
            $oks[$i] = 1
        }
        $zp[$i] = Get-EvalZ256 $W $B $c $p
        $zt[$i] = Get-EvalZ256 $W $B $c $Alvos[$i]
        $mz[$i] = $zp[$i] - $zt[$i]
        if ($Conf -ne $null) {
            $Conf[$Alvos[$i] * 25 + $p]++
        }
    }
    return [pscustomobject]@{
        N = $N
        Acertos = $acertos
        Bp = (Get-EvalBp $acertos $N)
        Batches = $batches
        Milesimos = (Get-EvalMediaMilesimos $batches $N)
        Preds = $preds
        Oks = $oks
        ZP = $zp
        ZT = $zt
        MZ = $mz
    }
}

function Get-EvalBaselineMetrics {
    param([int[]]$Preds, [int[]]$Alvos, [int]$N, [int[]]$Conf)
    $oks = New-Object 'int[]' $N
    $acertos = 0
    for ($i = 0; $i -lt $N; $i++) {
        if ($Preds[$i] -eq $Alvos[$i]) {
            $acertos++
            $oks[$i] = 1
        }
        if ($Conf -ne $null) {
            $Conf[$Alvos[$i] * 25 + $Preds[$i]]++
        }
    }
    return [pscustomobject]@{
        N = $N
        Acertos = $acertos
        Bp = (Get-EvalBp $acertos $N)
        Batches = @()
        Milesimos = -1
        Preds = $Preds
        Oks = $oks
    }
}

# --- Emissao de linhas -------------------------------------------------------

function Get-EvalStateLines {
    param([hashtable]$W, [hashtable]$B, [string]$PrefixW, [string]$PrefixB)
    $lines = @()
    for ($y = 0; $y -lt 25; $y++) {
        $lines += ("$PrefixW $y " + (($W[$y]) -join " "))
    }
    $bvals = @()
    for ($y = 0; $y -lt 25; $y++) { $bvals += [string]$B[$y] }
    $lines += ("$PrefixB " + ($bvals -join " "))
    return $lines
}

function Get-EvalConfLines {
    param([string]$Estado, [string]$Conjunto, [int[]]$Conf)
    $lines = @()
    for ($alvo = 0; $alvo -lt 25; $alvo++) {
        for ($pred = 0; $pred -lt 25; $pred++) {
            $q = $Conf[$alvo * 25 + $pred]
            if ($q -gt 0) {
                $lines += "CONF $Estado $Conjunto $alvo $pred $q"
            }
        }
    }
    return $lines
}

function Get-EvalExLine {
    param([string]$Estado, [string]$Conjunto, [int]$Indice, [int]$Pos,
          [int[]]$Entradas, [int]$I, [int]$Alvo, [int]$Pred, [int]$Ok,
          [long]$ZP, [long]$ZT, [long]$MZ, [int]$AlvoTreino, [int]$Tipo)
    $tipoTexto = "-"
    if ($Tipo -eq 1) { $tipoTexto = "VISTO" }
    elseif ($Tipo -eq 0) { $tipoTexto = "INEDITO" }
    return "EX $Estado $Conjunto $Indice $Pos $($Entradas[$I * 3]) $($Entradas[$I * 3 + 1]) $($Entradas[$I * 3 + 2]) $Alvo $Pred $Ok $ZP $ZT $MZ $AlvoTreino $tipoTexto $(Get-EvalWord $Alvo) $(Get-EvalWord $Pred)"
}

function Get-EvalReportSet {
    param([string]$Estado, [string]$Conjunto, [hashtable]$W, [hashtable]$B,
          [int[]]$Entradas, [int[]]$Alvos, [int]$N,
          [int[]]$Tipo, [int[]]$AlvoTreino, [int]$Layout,
          [int]$ImprimirEx, [int]$DerivarSemPare)
    $conf = New-Object 'int[]' 625
    $m = Get-EvalMetrics $W $B $Entradas $Alvos $N $conf
    $lines = @(
        "CHECK $Estado MUTACAO OK",
        "CHECK $Estado ACERTOS OK",
        "RESUMO $Estado $Conjunto $N $($m.Acertos) $($m.Bp) $($m.Milesimos)"
    )
    $batchIndex = 0
    foreach ($batch in $m.Batches) {
        $batchIndex++
        $lines += "PERDA $Estado $Conjunto $batchIndex $($batch.N) $($batch.S)"
    }
    if ($ImprimirEx -eq 1) {
        for ($i = 0; $i -lt $N; $i++) {
            $indice = $i + 1
            $pos = 0
            if ($Layout -eq 1) {
                $indice = [int][Math]::Floor($i / 4) + 1
                $pos = $i % 4
            }
            $lines += Get-EvalExLine $Estado $Conjunto $indice $pos $Entradas $i `
                $Alvos[$i] $m.Preds[$i] $m.Oks[$i] $m.ZP[$i] $m.ZT[$i] $m.MZ[$i] `
                $AlvoTreino[$i] $Tipo[$i]
        }
    }
    $lines += Get-EvalConfLines $Estado $Conjunto $conf
    if ($DerivarSemPare -eq 1) {
        $np = 0; $na = 0
        for ($i = 0; $i -lt $N; $i++) {
            if ($Alvos[$i] -ne 24) {
                $np++
                if ($m.Oks[$i] -eq 1) { $na++ }
            }
        }
        $lines += "RESUMO $Estado C_SEM_PARE $np $na $(Get-EvalBp $na $np) -1"
    }
    return [pscustomobject]@{ Lines = $lines; Metrics = $m; Conf = $conf }
}

function Get-EvalReportB {
    param([string]$Estado, [hashtable]$W, [hashtable]$B,
          [int[]]$Entradas, [int[]]$Alvos, [int[]]$Tipo, [int]$ImprimirEx)
    $conf = New-Object 'int[]' 625
    $m = Get-EvalMetrics $W $B $Entradas $Alvos 20 $conf
    $vistos = 0; $ineditos = 0
    for ($i = 0; $i -lt 20; $i++) {
        if ($m.Preds[$i] -eq $Alvos[$i]) {
            if ($Tipo[$i] -eq 1) { $vistos++ } else { $ineditos++ }
        }
    }
    $lines = @(
        "CHECK $Estado MUTACAO OK",
        "CHECK $Estado ACERTOS OK",
        "RESUMO $Estado B 20 $($m.Acertos) $($m.Bp) $($m.Milesimos)",
        "RESUMO $Estado B_VISTO 10 $vistos $(Get-EvalBp $vistos 10) -1",
        "RESUMO $Estado B_INEDITO 10 $ineditos $(Get-EvalBp $ineditos 10) -1"
    )
    $batchIndex = 0
    foreach ($batch in $m.Batches) {
        $lines += "PERDA $Estado B $($batchIndex + 1) $($batch.N) $($batch.S)"
        $batchIndex++
    }
    if ($ImprimirEx -eq 1) {
        for ($i = 0; $i -lt 20; $i++) {
            $lines += Get-EvalExLine $Estado "B" ([int][Math]::Floor($i / 4) + 1) ($i % 4) `
                $Entradas $i $Alvos[$i] $m.Preds[$i] $m.Oks[$i] $m.ZP[$i] $m.ZT[$i] $m.MZ[$i] -1 $Tipo[$i]
        }
    }
    $lines += Get-EvalConfLines $Estado "B" $conf
    return [pscustomobject]@{ Lines = $lines; Metrics = $m; Conf = $conf }
}

function Get-EvalBaselineReportSet {
    param([string]$Estado, [string]$Conjunto, [int[]]$Entradas, [int[]]$Preds,
          [int[]]$Alvos, [int]$N, [int[]]$Tipo, [int[]]$AlvoTreino,
          [int]$Layout, [int]$ImprimirEx, [int]$DerivarSemPare)
    $conf = New-Object 'int[]' 625
    $m = Get-EvalBaselineMetrics $Preds $Alvos $N $conf
    $lines = @(
        "CHECK $Estado MUTACAO NA",
        "CHECK $Estado ACERTOS OK",
        "RESUMO $Estado $Conjunto $N $($m.Acertos) $($m.Bp) -1"
    )
    if ($ImprimirEx -eq 1) {
        for ($i = 0; $i -lt $N; $i++) {
            $indice = $i + 1
            $pos = 0
            if ($Layout -eq 1) {
                $indice = [int][Math]::Floor($i / 4) + 1
                $pos = $i % 4
            }
            $lines += Get-EvalExLine $Estado $Conjunto $indice $pos $Entradas $i `
                $Alvos[$i] $m.Preds[$i] $m.Oks[$i] 0 0 0 $AlvoTreino[$i] $Tipo[$i]
        }
    }
    $lines += Get-EvalConfLines $Estado $Conjunto $conf
    if ($DerivarSemPare -eq 1) {
        $np = 0; $na = 0
        for ($i = 0; $i -lt $N; $i++) {
            if ($Alvos[$i] -ne 24) {
                $np++
                if ($m.Oks[$i] -eq 1) { $na++ }
            }
        }
        $lines += "RESUMO $Estado C_SEM_PARE $np $na $(Get-EvalBp $na $np) -1"
    }
    return [pscustomobject]@{ Lines = $lines; Metrics = $m; Conf = $conf }
}

function Get-EvalBaselineReportB {
    param([string]$Estado, [int[]]$Entradas, [int[]]$Preds,
          [int[]]$Alvos, [int[]]$Tipo, [int]$ImprimirEx)
    $conf = New-Object 'int[]' 625
    $m = Get-EvalBaselineMetrics $Preds $Alvos 20 $conf
    $vistos = 0; $ineditos = 0
    for ($i = 0; $i -lt 20; $i++) {
        if ($m.Oks[$i] -eq 1) {
            if ($Tipo[$i] -eq 1) { $vistos++ } else { $ineditos++ }
        }
    }
    $lines = @(
        "CHECK $Estado MUTACAO NA",
        "CHECK $Estado ACERTOS OK",
        "RESUMO $Estado B 20 $($m.Acertos) $($m.Bp) -1",
        "RESUMO $Estado B_VISTO 10 $vistos $(Get-EvalBp $vistos 10) -1",
        "RESUMO $Estado B_INEDITO 10 $ineditos $(Get-EvalBp $ineditos 10) -1"
    )
    if ($ImprimirEx -eq 1) {
        for ($i = 0; $i -lt 20; $i++) {
            $lines += Get-EvalExLine $Estado "B" ([int][Math]::Floor($i / 4) + 1) ($i % 4) `
                $Entradas $i $Alvos[$i] $m.Preds[$i] $m.Oks[$i] 0 0 0 -1 $Tipo[$i]
        }
    }
    $lines += Get-EvalConfLines $Estado "B" $conf
    return [pscustomobject]@{ Lines = $lines; Metrics = $m; Conf = $conf }
}

# --- Casos -------------------------------------------------------------------

function Get-EvalDatasetSets {
    $d = Get-EvalDataset
    $b = Get-EvalSequenceSet -Seq $d.BSeq -Count 5 -Modo 1
    $c = Get-EvalSequenceSet -Seq $d.CSeq -Count 8 -Modo 0
    return [pscustomobject]@{
        D = $d
        B = $b
        C = $c
    }
}

function Get-EvalHeaderLines {
    param([string]$Estado, [int]$Treino, [hashtable]$W, [hashtable]$B, [int]$ComEstado)
    $lines = @("AVAL V1", "ESTADO $Estado", "TREINO $Treino")
    if ($ComEstado -eq 1) {
        $lines += Get-EvalStateLines $W $B "W16" "B16"
    }
    return $lines
}

function Get-EvalFooterLines {
    param([hashtable]$W, [hashtable]$B, [int]$ComEstado)
    $lines = @()
    if ($ComEstado -eq 1) {
        $lines += Get-EvalStateLines $W $B "W16_FIM" "B16_FIM"
    }
    $lines += "FIM"
    return $lines
}

function Get-EvalMinusOne {
    param([int]$N)
    $a = New-Object 'int[]' $N
    for ($i = 0; $i -lt $N; $i++) { $a[$i] = -1 }
    return $a
}

function Get-EvalCanonicalLines {
    param([switch]$ComDelta)
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $W = New-EvalW
    $B = New-EvalB
    $tr = Invoke-EvalTrain $W $B $d.TrainEnt $d.TrainAlv 10 4
    if ($tr.Code -ne 0) { throw "Treino canonico retornou $($tr.Code)" }
    if (($tr.History -join " ") -cne "8404936 1341188 651091 509249 436118") {
        throw "Historico canonico divergente: $($tr.History -join ' ')"
    }

    $lines = @()
    $lines += Get-EvalHeaderLines "CANONICO" 10 $W $B 1

    $semTipoA = Get-EvalMinusOne 10
    $semExtraA = Get-EvalMinusOne 10
    $rA = Get-EvalReportSet "CANONICO" "A" $W $B $d.AEnt $d.AAlv 10 $semTipoA $semExtraA 0 1 0
    $lines += $rA.Lines

    $rB = Get-EvalReportB "CANONICO" $W $B $sets.B.Ent $sets.B.Alv $sets.B.Tipo 1
    $lines += $rB.Lines

    $semTipoC = Get-EvalMinusOne 32
    $semExtraC = Get-EvalMinusOne 32
    $rC = Get-EvalReportSet "CANONICO" "C" $W $B $sets.C.Ent $sets.C.Alv 32 $semTipoC $semExtraC 1 1 1
    $lines += $rC.Lines

    $semTipoD = Get-EvalMinusOne 10
    $rD = Get-EvalReportSet "CANONICO" "D" $W $B $d.DEnt $d.DAlv 10 $semTipoD $d.DOrig 0 1 0
    $lines += $rD.Lines

    if ($ComDelta) {
        $memA = New-Object 'int[]' 10
        $memB = New-Object 'int[]' 20
        $memC = New-Object 'int[]' 32
        $memD = New-Object 'int[]' 10
        [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $d.AEnt $d.AAlv 10 $memA)
        [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $sets.B.Ent $sets.B.Alv 20 $memB)
        [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $sets.C.Ent $sets.C.Alv 32 $memC)
        [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $d.DEnt $d.DAlv 10 $memD)
        $mMemA = Get-EvalBaselineMetrics $memA $d.AAlv 10 $null
        $mMemB = Get-EvalBaselineMetrics $memB $sets.B.Alv 20 $null
        $mMemC = Get-EvalBaselineMetrics $memC $sets.C.Alv 32 $null
        $mMemD = Get-EvalBaselineMetrics $memD $d.DAlv 10 $null

        $bpMemBV = Get-EvalBp (Count-EvalSeen $memB $sets.B.Alv $sets.B.Tipo 1) 10
        $bpMemBI = Get-EvalBp (Count-EvalSeen $memB $sets.B.Alv $sets.B.Tipo 0) 10
        $bpCanBV = Get-EvalBp (Count-EvalSeen $rB.Metrics.Preds $sets.B.Alv $sets.B.Tipo 1) 10
        $bpCanBI = Get-EvalBp (Count-EvalSeen $rB.Metrics.Preds $sets.B.Alv $sets.B.Tipo 0) 10

        $W0 = New-EvalW
        $B0 = New-EvalB
        $dummyConf = New-Object 'int[]' 625
        $m0C = Get-EvalMetrics $W0 $B0 $sets.C.Ent $sets.C.Alv 32 $dummyConf

        $lines += "DELTA_BP A $($rA.Metrics.Bp) $($mMemA.Bp) $($rA.Metrics.Bp - $mMemA.Bp)"
        $lines += "DELTA_BP B $($rB.Metrics.Bp) $($mMemB.Bp) $($rB.Metrics.Bp - $mMemB.Bp)"
        $lines += "DELTA_BP B_VISTO $bpCanBV $bpMemBV $($bpCanBV - $bpMemBV)"
        $lines += "DELTA_BP B_INEDITO $bpCanBI $bpMemBI $($bpCanBI - $bpMemBI)"
        $lines += "DELTA_BP C $($rC.Metrics.Bp) $($mMemC.Bp) $($rC.Metrics.Bp - $mMemC.Bp)"
        $lines += "DELTA_BP C $($rC.Metrics.Bp) $($m0C.Bp) $($rC.Metrics.Bp - $m0C.Bp)"
        $lines += "DELTA_BP D $($rD.Metrics.Bp) $($mMemD.Bp) $($rD.Metrics.Bp - $mMemD.Bp)"
    }

    $lines += Get-EvalFooterLines $W $B 1
    return $lines
}

function Count-EvalSeen {
    param([int[]]$Preds, [int[]]$Alvos, [int[]]$Tipo, [int]$Classe)
    $n = 0
    for ($i = 0; $i -lt $Preds.Length; $i++) {
        if ($Tipo[$i] -eq $Classe -and $Preds[$i] -eq $Alvos[$i]) { $n++ }
    }
    return $n
}

function Get-EvalLookupPreds {
    param([int[]]$TrainE, [int[]]$TrainT, [int]$NTreino,
          [int[]]$Entradas, [int[]]$Alvos, [int]$N, [int[]]$Preds)
    for ($i = 0; $i -lt $N; $i++) {
        $pred = 24
        for ($j = 0; $j -lt $NTreino; $j++) {
            if ($TrainE[$j * 3] -eq $Entradas[$i * 3] -and
                $TrainE[$j * 3 + 1] -eq $Entradas[$i * 3 + 1] -and
                $TrainE[$j * 3 + 2] -eq $Entradas[$i * 3 + 2]) {
                $pred = $TrainT[$j]
                break
            }
        }
        $Preds[$i] = $pred
    }
    return 0
}

function Get-EvalNonTrainedLines {
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $W = New-EvalW
    $B = New-EvalB
    $lines = @()
    $lines += Get-EvalHeaderLines "NAO_TREINADO" 0 $W $B 1
    $lines += (Get-EvalReportSet "NAO_TREINADO" "A" $W $B $d.AEnt $d.AAlv 10 (Get-EvalMinusOne 10) (Get-EvalMinusOne 10) 0 1 0).Lines
    $lines += (Get-EvalReportB "NAO_TREINADO" $W $B $sets.B.Ent $sets.B.Alv $sets.B.Tipo 1).Lines
    $lines += (Get-EvalReportSet "NAO_TREINADO" "C" $W $B $sets.C.Ent $sets.C.Alv 32 (Get-EvalMinusOne 32) (Get-EvalMinusOne 32) 1 1 1).Lines
    $lines += (Get-EvalReportSet "NAO_TREINADO" "D" $W $B $d.DEnt $d.DAlv 10 (Get-EvalMinusOne 10) $d.DOrig 0 1 0).Lines
    $lines += Get-EvalFooterLines $W $B 1
    return $lines
}

function Get-EvalBaselinesLines {
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $lines = @()
    foreach ($estado in @("MEMORIZACAO", "MAJORITARIO")) {
        $lines += "AVAL V1"
        $lines += "ESTADO $estado"
        $lines += "TREINO 10"
        $predA = New-Object 'int[]' 10
        $predB = New-Object 'int[]' 20
        $predC = New-Object 'int[]' 32
        $predD = New-Object 'int[]' 10
        if ($estado -ceq "MEMORIZACAO") {
            [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $d.AEnt $d.AAlv 10 $predA)
            [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $sets.B.Ent $sets.B.Alv 20 $predB)
            [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $sets.C.Ent $sets.C.Alv 32 $predC)
            [void](Get-EvalLookupPreds $d.TrainEnt $d.TrainAlv 10 $d.DEnt $d.DAlv 10 $predD)
        } else {
            for ($i = 0; $i -lt 10; $i++) { $predA[$i] = 24 }
            for ($i = 0; $i -lt 20; $i++) { $predB[$i] = 24 }
            for ($i = 0; $i -lt 32; $i++) { $predC[$i] = 24 }
            for ($i = 0; $i -lt 10; $i++) { $predD[$i] = 24 }
        }
        $lines += (Get-EvalBaselineReportSet $estado "A" $d.AEnt $predA $d.AAlv 10 (Get-EvalMinusOne 10) (Get-EvalMinusOne 10) 0 0 0).Lines
        $lines += (Get-EvalBaselineReportB $estado $sets.B.Ent $predB $sets.B.Alv $sets.B.Tipo 0).Lines
        $lines += (Get-EvalBaselineReportSet $estado "C" $sets.C.Ent $predC $sets.C.Alv 32 (Get-EvalMinusOne 32) (Get-EvalMinusOne 32) 1 0 1).Lines
        $lines += (Get-EvalBaselineReportSet $estado "D" $d.DEnt $predD $d.DAlv 10 (Get-EvalMinusOne 10) $d.DOrig 0 0 0).Lines
        $lines += "FIM"
    }
    return $lines
}

function Get-EvalControlLabelLines {
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $W = New-EvalW
    $B = New-EvalB
    $pt = New-Object 'int[]' 10
    for ($i = 0; $i -lt 10; $i++) { $pt[$i] = ($d.TrainAlv[$i] % 24) + 1 }
    $tr = Invoke-EvalTrain $W $B $d.TrainEnt $pt 10 4
    if ($tr.Code -ne 0) { throw "Treino rotulo permutado retornou $($tr.Code)" }
    $lines = @()
    $lines += Get-EvalHeaderLines "ROTULO_PERMUTADO" 10 $W $B 1
    $lines += (Get-EvalReportSet "ROTULO_PERMUTADO" "A" $W $B $d.AEnt $pt 10 (Get-EvalMinusOne 10) (Get-EvalMinusOne 10) 0 0 0).Lines
    $lines += (Get-EvalReportSet "ROTULO_PERMUTADO" "C" $W $B $sets.C.Ent $sets.C.Alv 32 (Get-EvalMinusOne 32) (Get-EvalMinusOne 32) 1 0 1).Lines
    $lines += Get-EvalFooterLines $W $B 1
    return $lines
}

function Get-EvalControlOrderLines {
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $revE = New-Object 'int[]' 30
    $revT = New-Object 'int[]' 10
    for ($i = 0; $i -lt 10; $i++) {
        $src = 9 - $i
        for ($k = 0; $k -lt 3; $k++) { $revE[$i * 3 + $k] = $d.TrainEnt[$src * 3 + $k] }
        $revT[$i] = $d.TrainAlv[$src]
    }
    $W = New-EvalW
    $B = New-EvalB
    $tr = Invoke-EvalTrain $W $B $revE $revT 10 4
    if ($tr.Code -ne 0) { throw "Treino ordem inversa retornou $($tr.Code)" }
    $lines = @()
    $lines += Get-EvalHeaderLines "ORDEM_INVERSA" 10 $W $B 1
    $lines += (Get-EvalReportSet "ORDEM_INVERSA" "A" $W $B $d.AEnt $d.AAlv 10 (Get-EvalMinusOne 10) (Get-EvalMinusOne 10) 0 0 0).Lines
    $lines += (Get-EvalReportSet "ORDEM_INVERSA" "C" $W $B $sets.C.Ent $sets.C.Alv 32 (Get-EvalMinusOne 32) (Get-EvalMinusOne 32) 1 0 1).Lines
    $lines += Get-EvalFooterLines $W $B 1
    return $lines
}

function Get-EvalPermutationLines {
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $W = New-EvalW
    $B = New-EvalB
    $tr = Invoke-EvalTrain $W $B $d.TrainEnt $d.TrainAlv 10 4
    if ($tr.Code -ne 0) { throw "Treino canonico retornou $($tr.Code)" }
    $lines = @()
    $lines += Get-EvalHeaderLines "CANONICO" 10 $W $B 1
    $dummyConf = New-Object 'int[]' 625
    $m = Get-EvalMetrics $W $B $sets.C.Ent $sets.C.Alv 32 $dummyConf
    $alterados = 0
    $mudancasTotal = 0
    for ($i = 0; $i -lt 32; $i++) {
        $ta = $sets.C.Ent[$i * 3]
        $tb = $sets.C.Ent[$i * 3 + 1]
        $tc = $sets.C.Ent[$i * 3 + 2]
        $orig = $m.Preds[$i]
        $perms = @(
            @($ta, $tb, $tc), @($ta, $tc, $tb), @($tb, $ta, $tc),
            @($tb, $tc, $ta), @($tc, $ta, $tb), @($tc, $tb, $ta)
        )
        $preds = @()
        foreach ($p in $perms) {
            $preds += Get-EvalArgmax $W $B (Get-EvalC16 ([int[]]$p))
        }
        $mud = 0
        for ($k = 1; $k -lt 6; $k++) {
            if ($preds[$k] -ne $orig) { $mud++ }
        }
        if ($mud -gt 0) { $alterados++ }
        $mudancasTotal += $mud
        $lines += "PERM $($i + 1) $ta $tb $tc $orig $($preds[0]) $($preds[1]) $($preds[2]) $($preds[3]) $($preds[4]) $($preds[5]) $mud"
    }
    $lines += "PERM_RESUMO 32 $alterados $mudancasTotal"
    $lines += "CHECK CANONICO MUTACAO OK"
    $lines += "CHECK CANONICO ACERTOS OK"
    $lines += Get-EvalFooterLines $W $B 1
    return $lines
}

function Get-EvalLimitsLines {
    $sets = Get-EvalDatasetSets
    $d = $sets.D
    $lines = @("AVAL V1", "LIMITES")
    # IDs
    $ok = New-Object 'int[]' 3
    $ok[0] = 1; $ok[1] = 3; $ok[2] = 17
    $alv = New-Object 'int[]' 1
    $alv[0] = 22
    $bad = New-Object 'int[]' 3
    $bad[0] = 25; $bad[1] = 3; $bad[2] = 17
    $neg = New-Object 'int[]' 3
    $neg[0] = -1; $neg[1] = 3; $neg[2] = 17
    $lines += "IDS n=0 " + [int](Test-EvalIds $ok $alv 0)
    $lines += "IDS n=65 " + [int](Test-EvalIds $ok $alv 65)
    $lines += "IDS id=25 " + [int](Test-EvalIds $bad $alv 1)
    $lines += "IDS id=-1 " + [int](Test-EvalIds $neg $alv 1)
    $lines += "IDS validos " + [int](Test-EvalIds $ok $alv 1)
    $lines += "DIV 10 3 " + (Eval-DivFloor 10 3)
    $lines += "DIV 0 5 " + (Eval-DivFloor 0 5)
    $lines += "DIV 5 0 " + (Eval-DivFloor 5 0)
    $lines += "DIV -1 3 " + (Eval-DivFloor -1 3)
    $lines += "MILES 0 1 " + (Eval-Milesimos 0 1)
    $lines += "MILES 1 1 " + (Eval-Milesimos 1 1)
    $lines += "MILES 321126400 1 " + (Eval-Milesimos 321126400 1)
    $lines += "MILES 1926758400 6 " + (Eval-Milesimos 1926758400 6)
    $lines += "MILES 1 0 " + (Eval-Milesimos 1 0)
    $W = New-EvalW
    $B = New-EvalB
    $lines += "CHECKSUM " + (Get-EvalChecksum $W $B)
    $conf = New-Object 'int[]' 625
    $saida = New-Object 'int[]' 16
    $lines += "AVALIAR n=0 " + (Test-EvalAvaliar $W $B $d.TrainEnt $d.TrainAlv 0 $conf $saida)
    $lines += "AVALIAR n=65 " + (Test-EvalAvaliar $W $B $d.TrainEnt $d.TrainAlv 65 $conf $saida)
    $badE = New-Object 'int[]' 30
    for ($i = 0; $i -lt 30; $i++) { $badE[$i] = $d.TrainEnt[$i] }
    $badE[0] = 25
    $lines += "AVALIAR id=25 " + (Test-EvalAvaliar $W $B $badE $d.TrainAlv 10 $conf $saida)
    $negE = New-Object 'int[]' 30
    for ($i = 0; $i -lt 30; $i++) { $negE[$i] = $d.TrainEnt[$i] }
    $negE[0] = -1
    $lines += "AVALIAR id=-1 " + (Test-EvalAvaliar $W $B $negE $d.TrainAlv 10 $conf $saida)
    $badW = Copy-EvalW $W
    $badW[0][0] = 17
    $lines += "AVALIAR params " + (Test-EvalAvaliar $badW $B $d.TrainEnt $d.TrainAlv 10 $conf $saida)
    $lines += "RELATORIO modo 3 " + (Test-EvalModo 3)
    $lines += "COPIAR tam=7 " + (Test-EvalCopiar $d.TrainEnt $d.TrainAlv 0 7)
    $lines += "COPIAR tam=6 " + (Test-EvalCopiar $d.TrainEnt $d.TrainAlv 0 6)
    $lines += "FIM"
    return $lines
}

function Test-EvalIds {
    param([int[]]$Ent, [int[]]$Alv, [int]$N)
    if ($N -lt 1 -or $N -gt 64) { return 0 }
    for ($i = 0; $i -lt $N * 3; $i++) {
        if ($Ent[$i] -lt 0 -or $Ent[$i] -gt 24) { return 0 }
    }
    for ($i = 0; $i -lt $N; $i++) {
        if ($Alv[$i] -lt 0 -or $Alv[$i] -gt 24) { return 0 }
    }
    return 1
}

function Eval-DivFloor {
    param([int]$Num, [int]$Den)
    if ($Den -le 0 -or $Num -lt 0) { return -1 }
    return [int][Math]::Floor($Num / $Den)
}

function Eval-Milesimos {
    param([long]$S, [int]$N)
    if ($N -lt 1 -or $N -gt 6 -or $S -lt 0 -or $S -gt 1926758400) { return -1 }
    return Get-EvalMilesimos $S $N
}

function Test-EvalAvaliar {
    param([hashtable]$W, [hashtable]$B, [int[]]$Ent, [int[]]$Alv, [int]$N,
          [int[]]$Conf, [int[]]$Saida)
    if ($N -lt 1 -or $N -gt 64) { return 21 }
    if (-not (Test-EvalIds $Ent $Alv $N)) { return 22 }
    if ((Get-EvalMaxAbs $W $B) -gt 16) { return 23 }
    return 0
}

function Get-EvalMaxAbs {
    param([hashtable]$W, [hashtable]$B)
    $m = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($p = 0; $p -lt 12; $p++) {
            if ([Math]::Abs($W[$y][$p]) -gt $m) { $m = [Math]::Abs($W[$y][$p]) }
        }
        if ([Math]::Abs($B[$y]) -gt $m) { $m = [Math]::Abs($B[$y]) }
    }
    return $m
}

function Test-EvalModo {
    param([int]$Modo)
    if ($Modo -lt 0 -or $Modo -gt 2) { return 24 }
    return 0
}

function Test-EvalCopiar {
    param([int[]]$Ent, [int[]]$Alv, [int]$Base, [int]$Tam)
    if ($Tam -lt 0 -or $Tam -gt 6) { return 26 }
    return 0
}

function Get-EvalExpected {
    param([string]$Name)
    switch ($Name) {
        "eval_nao_treinado" { return (Get-EvalNonTrainedLines) }
        "eval_treinado" { return (Get-EvalCanonicalLines -ComDelta) }
        "eval_determinismo_a" { return (Get-EvalCanonicalLines -ComDelta) }
        "eval_determinismo_b" { return (Get-EvalCanonicalLines -ComDelta) }
        "eval_baselines" { return (Get-EvalBaselinesLines) }
        "eval_controle_rotulo" { return (Get-EvalControlLabelLines) }
        "eval_controle_ordem" { return (Get-EvalControlOrderLines) }
        "eval_ordem_permutacoes" { return (Get-EvalPermutationLines) }
        "eval_limites" { return (Get-EvalLimitsLines) }
        default { throw "Caso desconhecido: $Name" }
    }
}

# --- O2: agregacao com BigInteger --------------------------------------------

function Get-EvalMilesimosBig {
    param([System.Numerics.BigInteger]$S, [int]$N)
    if ($N -lt 1 -or $N -gt 6) { return [System.Numerics.BigInteger]::MinusOne }
    $den = [System.Numerics.BigInteger](131072 * $N)
    return ([System.Numerics.BigInteger]1000 * $S) / $den
}

function Get-EvalMediaBig {
    param([object[]]$Batches, [int]$N)
    $soma = [System.Numerics.BigInteger]::Zero
    foreach ($b in $Batches) {
        $m = Get-EvalMilesimosBig ([System.Numerics.BigInteger]$b.S) $b.N
        $soma += $m * [System.Numerics.BigInteger]$b.N
    }
    return $soma / [System.Numerics.BigInteger]$N
}

function Assert-EvalO2 {
    param([object[]]$Batches, [int]$N, [long]$Milesimos)
    $errs = @()
    $soma = [System.Numerics.BigInteger]::Zero
    foreach ($b in $Batches) {
        $soma += [System.Numerics.BigInteger]$b.S
        $m2 = Get-EvalMilesimosBig ([System.Numerics.BigInteger]$b.S) $b.N
        $m1 = Get-EvalMilesimos $b.S $b.N
        if ($m2 -ne [System.Numerics.BigInteger]$m1) {
            $errs += "m_b O1=$m1 O2=$m2 (n=$($b.N))"
        }
    }
    $m2 = Get-EvalMediaBig $Batches $N
    if ($m2 -ne [System.Numerics.BigInteger]$Milesimos) {
        $errs += "M O1=$Milesimos O2=$m2"
    }
    return [pscustomobject]@{ Errors = $errs; TotalS = $soma }
}

# --- Entrada direta ----------------------------------------------------------

if ($SelfCheck) {
    $lines = Get-EvalExpected "eval_treinado"
    [Console]::Out.Write((($lines -join "`n") + "`n"))
    exit 0
}

if ($Case -ne "") {
    $lines = Get-EvalExpected $Case
    $text = (($lines -join "`n") + "`n")
    if ($OutputPath -ne "") {
        [IO.File]::WriteAllText($OutputPath, $text, (New-Object System.Text.ASCIIEncoding))
    } else {
        [Console]::Out.Write($text)
    }
    exit 0
}
