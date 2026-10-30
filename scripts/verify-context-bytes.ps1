# ---------------------------------------------------------------------------
# Verificacao do formato observavel e dos valores do contexto multi-token (M7).
# - Fonte ASCII puro, fragmento, constantes canonicas, sem biblioteca/aleatorio.
# - Conjunto de casos exatamente igual ao esperado (sem faltas nem extras).
# - Saida crua: form feed inicial, carga ASCII com LF, epilogo exato.
# - Oraculo independente: re-deriva init, c16, Z256, treino, perda, margens,
#   ablacoes e geracao a partir das formulas da spec; nao le .expected para
#   decidir valores (apenas V2/V13).
# - V1 confere os 15 hashes congelados e o diff puramente aditivo de test.ps1.
# - V16 executa a regressao completa: pureza, suite 100/100, M1-M6 e autoteste.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-context-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/context-tests",
    [string]$SourcePath = "src/contexto.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat",
    [string]$SpecPath = "docs/context-spec.md",
    [string]$PlanPath = "docs/context-plan.md"
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

# --- Oraculo inteiro independente (formulas da spec M7) ---------------------

function New-CtxW {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($k = 0; $k -lt 3; $k++) {
            for ($d = 0; $d -lt 4; $d++) {
                if ($k -eq 2) {
                    $row[$k * 4 + $d] = (($y * 7 + $d * 5) % 25) - 12
                } else {
                    $row[$k * 4 + $d] = 0
                }
            }
        }
        $w[$y] = $row
    }
    return $w
}

function New-CtxB {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-CtxW {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($p = 0; $p -lt 12; $p++) { $row[$p] = $W[$y][$p] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-CtxB {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-CtxEmb16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

function Get-CtxC16 {
    param([int[]]$Seq)
    $c = New-Object 'int[]' 12
    for ($k = 0; $k -lt 3; $k++) {
        $pos = $Seq.Count - 3 + $k
        if ($pos -ge 0) {
            for ($d = 0; $d -lt 4; $d++) {
                $c[$k * 4 + $d] = Get-CtxEmb16 $Seq[$pos] $d
            }
        }
    }
    return $c
}

function Get-CtxC16FromExample {
    param([int[]]$Entradas, [int]$N)
    return Get-CtxC16 ([int[]]@($Entradas[$N * 3], $Entradas[$N * 3 + 1], $Entradas[$N * 3 + 2]))
}

function Get-CtxZ256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y)
    [long]$soma = 0
    for ($p = 0; $p -lt 12; $p++) {
        $soma += [long]$W[$Y][$p] * [long]$C[$p]
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-CtxDelta256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y, [int]$Alvo)
    [long]$z = Get-CtxZ256 $W $B $C $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-CtxArgmax {
    param([hashtable]$W, [hashtable]$B, [int[]]$C)
    $melhor = 0
    [long]$melhorValor = Get-CtxZ256 $W $B $C 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-CtxZ256 $W $B $C $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-CtxLoss {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-CtxDelta256 $W $B $c $y $Alvos[$i]
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-CtxRound {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

function Invoke-CtxTrain {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-CtxLoss $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            [int[]]$c = Get-CtxC16FromExample $Entradas $i
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-CtxDelta256 $W $B $c $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($p = 0; $p -lt 12; $p++) {
                    [long]$novo = Get-CtxRound (
                        2048 * [long]$W[$y][$p] - $delta[$y] * [long]$c[$p]) 2048
                    $W[$y][$p] = [int]$novo
                    if ([Math]::Abs($novo) -gt 16) {
                        return [pscustomobject]@{ Code = 5; History = $history; W = $W; B = $B }
                    }
                }
                [long]$novoB = Get-CtxRound (128 * [long]$B[$y] - $delta[$y]) 128
                $B[$y] = [int]$novoB
                if ([Math]::Abs($novoB) -gt 16) {
                    return [pscustomobject]@{ Code = 5; History = $history; W = $W; B = $B }
                }
            }
        }
        $history[$ep] = Get-CtxLoss $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history; W = $W; B = $B }
}

function Get-CtxGeneration {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $total = $Prefixo.Count
    for ($i = 0; $i -lt $total; $i++) { $saida[$i] = $Prefixo[$i] }
    if ($saida[$total - 1] -eq 24) {
        return [pscustomobject]@{ Saida = $saida; Total = $total }
    }
    while ($total -lt $Maximo) {
        [int[]]$seq = @($saida[0..($total - 1)])
        [int[]]$c = Get-CtxC16 $seq
        $proximo = Get-CtxArgmax $W $B $c
        $saida[$total] = $proximo
        $total++
        if ($proximo -eq 24) { break }
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
}

function Get-CtxPalavra {
    param([int]$Id)
    $palavras = @(
        "UNK", "programa", "funcao", "inicio", "inteiro", "real", "logico",
        "cadeia", "vazio", "se", "senao", "enquanto", "faca", "para", "ate",
        "passo", "retorne", "escreva", "leia", "e", "ou", "nao", "verdadeiro",
        "falso", "pare"
    )
    return $palavras[$Id]
}

function Get-CtxGeracaoLines {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $g = Get-CtxGeneration $W $B $Prefixo $Maximo
    $ids = @($g.Saida[0..($g.Total - 1)])
    $parada = if ($ids[$ids.Count - 1] -eq 24) { "PARE" } else { "MAXIMO" }
    $texto = (@($ids | ForEach-Object { Get-CtxPalavra $_ }) -join " ")
    $lines = @()
    $lines += "GERADO=" + ($ids -join " ")
    $lines += "N=$($g.Total)"
    $lines += "PASSOS=$($g.Total - $Prefixo.Count)"
    $lines += "PARADA=$parada"
    $lines += "TEXTO=$texto"
    return $lines
}

function Get-CtxParamLines {
    param([hashtable]$W, [hashtable]$B)
    $lines = @()
    for ($y = 0; $y -lt 25; $y++) {
        $lines += "PARAM16=$y " + ($W[$y] -join " ") + " " + $B[$y]
    }
    return $lines
}

function Get-CtxContextLine {
    param([int[]]$Seq)
    [int[]]$c = Get-CtxC16 $Seq
    return "CTX16=$($Seq.Count) " + ($c -join " ")
}

function Get-CtxMaxLine {
    param([hashtable]$W, [hashtable]$B)
    $maxW = 0
    $maxB = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($p = 0; $p -lt 12; $p++) {
            if ([Math]::Abs($W[$y][$p]) -gt $maxW) { $maxW = [Math]::Abs($W[$y][$p]) }
        }
        if ([Math]::Abs($B[$y]) -gt $maxB) { $maxB = [Math]::Abs($B[$y]) }
    }
    return "MAXIMO16=$maxW $maxB"
}

function Get-CtxMargins {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $out = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        [long]$zAlvo = Get-CtxZ256 $W $B $c $Alvos[$i]
        [long]$segundo = -1000000
        for ($y = 0; $y -lt 25; $y++) {
            if ($y -ne $Alvos[$i]) {
                [long]$z = Get-CtxZ256 $W $B $c $y
                if ($z -gt $segundo) { $segundo = $z }
            }
        }
        $out += ($zAlvo - $segundo)
    }
    return $out
}

function Get-CtxAblation {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N, [string]$Modo)
    $x = Copy-CtxW $W
    for ($y = 0; $y -lt 25; $y++) {
        for ($p = 0; $p -lt 12; $p++) {
            if ($Modo -eq "ultimo" -and $p -lt 8) { $x[$y][$p] = 0 }
            if ($Modo -eq "antigos" -and $p -ge 8) { $x[$y][$p] = 0 }
        }
    }
    $acertos = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        if ((Get-CtxArgmax $x $B $c) -eq $Alvos[$i]) { $acertos++ }
    }
    return [pscustomobject]@{ Acertos = $acertos; S = (Get-CtxLoss $x $B $Entradas $Alvos $N) }
}

function Get-CtxMaxUltimo {
    param([int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($t = 0; $t -lt 25; $t++) {
        $melhor = 0
        for ($i = 0; $i -lt $N; $i++) {
            if ($Entradas[$i * 3 + 2] -eq $t) {
                $cont = 0
                for ($j = 0; $j -lt $N; $j++) {
                    if ($Entradas[$j * 3 + 2] -eq $t -and $Alvos[$j] -eq $Alvos[$i]) { $cont++ }
                }
                if ($cont -gt $melhor) { $melhor = $cont }
            }
        }
        $total += $melhor
    }
    return $total
}

function Get-CtxBagKey {
    param([int[]]$Entradas, [int]$I)
    $a = $Entradas[$I * 3]
    $b = $Entradas[$I * 3 + 1]
    $c = $Entradas[$I * 3 + 2]
    if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
    if ($b -gt $c) { $t = $b; $b = $c; $c = $t }
    if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
    return $a * 625 + $b * 25 + $c
}

function Get-CtxMaxBag {
    param([int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($i = 0; $i -lt $N; $i++) {
        $primeiro = $true
        for ($j = 0; $j -lt $i; $j++) {
            if ((Get-CtxBagKey $Entradas $j) -eq (Get-CtxBagKey $Entradas $i)) { $primeiro = $false }
        }
        if ($primeiro) {
            $melhor = 0
            for ($j = 0; $j -lt $N; $j++) {
                if ((Get-CtxBagKey $Entradas $j) -eq (Get-CtxBagKey $Entradas $i)) {
                    $cont = 0
                    for ($k = 0; $k -lt $N; $k++) {
                        if ((Get-CtxBagKey $Entradas $k) -eq (Get-CtxBagKey $Entradas $i) -and
                            $Alvos[$k] -eq $Alvos[$j]) { $cont++ }
                    }
                    if ($cont -gt $melhor) { $melhor = $cont }
                }
            }
            $total += $melhor
        }
    }
    return $total
}

function Get-CtxAltered {
    param([hashtable]$W, [hashtable]$B)
    $aw = 0
    $ab = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($k = 0; $k -lt 3; $k++) {
            for ($d = 0; $d -lt 4; $d++) {
                $esperado = if ($k -eq 2) { (($y * 7 + $d * 5) % 25) - 12 } else { 0 }
                if ($W[$y][$k * 4 + $d] -ne $esperado) { $aw++ }
            }
        }
        if ($B[$y] -ne ((($y * 7) % 9) - 4)) { $ab++ }
    }
    return @($aw, $ab)
}

# --- Oraculo M5 (para a composicao V14) -------------------------------------

function New-M5W {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = (($y * 7 + $d * 5) % 25) - 12 }
        $w[$y] = $row
    }
    return $w
}

function New-M5B {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-M5W {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = $W[$y][$d] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-M5B {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-M5Z {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada, [int]$Y)
    [long]$soma = 0
    for ($d = 0; $d -lt 4; $d++) {
        $soma += [long]$W[$Y][$d] * [long](Get-CtxEmb16 $Entrada $d)
    }
    return $soma + 16 * [long]$B[$Y]
}

function Get-M5Argmax {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada)
    $melhor = 0
    [long]$melhorValor = Get-M5Z $W $B $Entrada 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-M5Z $W $B $Entrada $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-M5Gen {
    param([hashtable]$W, [hashtable]$B, [int]$Semente, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $saida[0] = $Semente
    $total = 1
    while ($total -lt $Maximo) {
        if ($saida[$total - 1] -eq 24) { break }
        $saida[$total] = Get-M5Argmax $W $B $saida[$total - 1]
        $total++
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
}

function Invoke-M5Train {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            $entrada = $Entradas[$i]
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                [long]$z = Get-M5Z $W $B $entrada $y
                $delta[$y] = if ($y -eq $Alvos[$i]) { $z - 256 } else { $z }
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($d = 0; $d -lt 4; $d++) {
                    [long]$novo = Get-CtxRound (
                        1024 * [long]$W[$y][$d] - $delta[$y] * [long](Get-CtxEmb16 $entrada $d)) 1024
                    $W[$y][$d] = [int]$novo
                    if ([Math]::Abs($novo) -gt 16) { return $false }
                }
                [long]$novoB = Get-CtxRound (64 * [long]$B[$y] - $delta[$y]) 64
                $B[$y] = [int]$novoB
                if ([Math]::Abs($novoB) -gt 16) { return $false }
            }
        }
    }
    return $true
}

# --- Tabelas canonicas (spec M7 7.6 e 7.7; M5 7.7) ----------------------

$initialRows = @(
    "0 0 0 0 0 0 0 0 0 -12 -7 -2 3 -4",
    "1 0 0 0 0 0 0 0 0 -5 0 5 10 3",
    "2 0 0 0 0 0 0 0 0 2 7 12 -8 1",
    "3 0 0 0 0 0 0 0 0 9 -11 -6 -1 -1",
    "4 0 0 0 0 0 0 0 0 -9 -4 1 6 -3",
    "5 0 0 0 0 0 0 0 0 -2 3 8 -12 4",
    "6 0 0 0 0 0 0 0 0 5 10 -10 -5 2",
    "7 0 0 0 0 0 0 0 0 12 -8 -3 2 0",
    "8 0 0 0 0 0 0 0 0 -6 -1 4 9 -2",
    "9 0 0 0 0 0 0 0 0 1 6 11 -9 -4",
    "10 0 0 0 0 0 0 0 0 8 -12 -7 -2 3",
    "11 0 0 0 0 0 0 0 0 -10 -5 0 5 1",
    "12 0 0 0 0 0 0 0 0 -3 2 7 12 -1",
    "13 0 0 0 0 0 0 0 0 4 9 -11 -6 -3",
    "14 0 0 0 0 0 0 0 0 11 -9 -4 1 4",
    "15 0 0 0 0 0 0 0 0 -7 -2 3 8 2",
    "16 0 0 0 0 0 0 0 0 0 5 10 -10 0",
    "17 0 0 0 0 0 0 0 0 7 12 -8 -3 -2",
    "18 0 0 0 0 0 0 0 0 -11 -6 -1 4 -4",
    "19 0 0 0 0 0 0 0 0 -4 1 6 11 3",
    "20 0 0 0 0 0 0 0 0 3 8 -12 -7 1",
    "21 0 0 0 0 0 0 0 0 10 -10 -5 0 -1",
    "22 0 0 0 0 0 0 0 0 -8 -3 2 7 -3",
    "23 0 0 0 0 0 0 0 0 -1 4 9 -11 4",
    "24 0 0 0 0 0 0 0 0 6 11 -9 -4 2"
)
$finalRows = @(
    "0 2 -2 -2 0 2 -3 0 1 -6 -1 -3 -1 -2",
    "1 0 1 0 1 0 -2 2 3 -3 2 1 5 5",
    "2 0 2 2 0 0 2 1 0 0 3 10 -9 2",
    "3 -2 -4 2 1 0 0 -2 -2 7 -8 -4 0 -2",
    "4 1 -1 -1 0 3 -2 2 2 -5 1 -4 3 -1",
    "5 -1 1 1 -1 0 -1 0 0 -2 2 9 -11 2",
    "6 -1 3 -2 -2 -3 2 -2 -3 1 4 -3 1 -2",
    "7 0 -5 2 2 -1 1 -1 -2 8 -5 -2 2 -1",
    "8 1 0 0 1 2 -1 1 2 -3 1 -1 5 1",
    "9 -7 2 0 1 1 5 0 1 2 4 9 -9 2",
    "10 -1 -3 2 1 0 -4 -2 -3 7 -5 -4 -1 1",
    "11 2 4 -3 -3 3 -4 4 1 -3 -4 -3 3 3",
    "12 1 2 2 1 1 0 2 3 -2 2 1 6 2",
    "13 0 1 0 -3 -2 4 -3 -2 1 4 -5 0 -5",
    "14 6 -7 3 2 -4 1 4 -1 2 -1 -4 0 -2",
    "15 1 1 1 0 0 -2 2 1 -4 0 -1 5 3",
    "16 1 2 -1 0 0 1 0 1 0 2 11 -10 0",
    "17 -1 3 -1 -1 -1 4 -1 -3 2 4 -3 2 -5",
    "18 2 0 -2 -1 2 -4 1 1 -5 -1 -5 2 0",
    "19 0 3 1 0 -1 -2 2 3 -2 1 2 7 5",
    "20 -1 1 -3 -2 -1 2 -2 -4 1 3 -5 0 -4",
    "21 -2 -5 2 3 -1 1 -3 -2 7 -6 -3 0 -2",
    "22 1 0 0 0 2 -2 1 2 -5 1 -2 3 0",
    "23 0 2 0 -1 -1 0 0 0 -1 2 10 -10 3",
    "24 0 3 -2 -1 -1 8 -4 -5 0 2 -4 4 0"
)
$m5FinalRows = @(
    "0 -1 0 -3 2 -1", "1 0 0 -2 3 0", "2 0 0 11 -10 2", "3 1 0 -3 2 -2",
    "4 0 0 -4 3 0", "5 -1 0 10 -11 2", "6 -1 0 -3 2 0", "7 1 0 -3 3 -1",
    "8 0 -1 -2 3 1", "9 0 0 9 -10 1", "10 1 0 -1 2 -1", "11 -1 0 -1 2 1",
    "12 8 -7 -3 3 2", "13 1 2 3 6 6", "14 1 8 -4 -2 2", "15 0 -1 -2 3 0",
    "16 0 1 10 -10 3", "17 0 0 -3 2 -1", "18 -1 -1 -3 4 0", "19 1 -1 -2 3 0",
    "20 -1 0 -4 3 0", "21 0 0 -3 3 -1", "22 0 0 -3 4 0", "23 -1 0 10 -10 3",
    "24 -9 -2 -4 0 4"
)
$traj7Frozen = @(6728768, 465936, 282923, 216490, 193677, 183943, 167288, 153027)

$ENT = [int[]]@(9, 12, 13, 12, 13, 14, 12, 9, 13, 9, 13, 12, 13, 12, 9, 14, 12, 13)
$ALV = [int[]]@(14, 24, 10, 24, 11, 9)

$initW = New-CtxW
$initB = New-CtxB
for ($y = 0; $y -lt 25; $y++) {
    $row = "$y " + ($initW[$y] -join " ") + " " + $initB[$y]
    if ($row -cne $initialRows[$y]) { Fail "oraculo inicial diverge em y=$y. Obtido [$row]" }
}

$finalW = Copy-CtxW $initW
$finalB = Copy-CtxB $initB
$train7 = Invoke-CtxTrain $finalW $finalB $ENT $ALV 6 7
if ($train7.Code -ne 0) { Fail "oraculo de treino retornou codigo $($train7.Code)" }
$traj7 = $train7.History
for ($e = 0; $e -le 7; $e++) {
    if ($traj7[$e] -ne $traj7Frozen[$e]) {
        Fail "oraculo: S$e = $($traj7[$e]); esperado $($traj7Frozen[$e])"
    }
}
for ($y = 0; $y -lt 25; $y++) {
    $row = "$y " + ($finalW[$y] -join " ") + " " + $finalB[$y]
    if ($row -cne $finalRows[$y]) { Fail "oraculo final diverge em y=$y. Obtido [$row]" }
}

$margins = Get-CtxMargins $finalW $finalB $ENT $ALV 6
if (($margins -join " ") -cne "142 151 156 174 201 167") {
    Fail "oraculo: margens [$(($margins -join ' '))]"
}
$ablFull = Get-CtxAblation $finalW $finalB $ENT $ALV 6 "full"
$ablUltimo = Get-CtxAblation $finalW $finalB $ENT $ALV 6 "ultimo"
$ablAntigos = Get-CtxAblation $finalW $finalB $ENT $ALV 6 "antigos"
if ($ablFull.Acertos -ne 6 -or $ablFull.S -ne 153027) { Fail "oraculo: ablacao full" }
if ($ablUltimo.Acertos -ne 1 -or $ablUltimo.S -ne 916888) { Fail "oraculo: ablacao ultimo" }
if ($ablAntigos.Acertos -ne 6 -or $ablAntigos.S -ne 717503) { Fail "oraculo: ablacao antigos" }
if ((Get-CtxMaxUltimo $ENT $ALV 6) -ne 4) { Fail "oraculo: limite ultimo" }
if ((Get-CtxMaxBag $ENT $ALV 6) -ne 2) { Fail "oraculo: limite bag" }

$genCadeia = Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 64
$frozenCadeia = @(
    "GERADO=9 12 13 14 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=se faca para ate pare"
)
if (($genCadeia -join "`n") -cne ($frozenCadeia -join "`n")) { Fail "oraculo: cadeia congelada" }

$gen64 = Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9)) 64
$frozen64 = "GERADO=9 10 11 14"
for ($i = 0; $i -lt 30; $i++) { $frozen64 += " 11 19" }
if ($gen64[0] -cne $frozen64) { Fail "oraculo: bloco de 64 tokens" }
if ($gen64[1] -cne "N=64" -or $gen64[2] -cne "PASSOS=63" -or $gen64[3] -cne "PARADA=MAXIMO") {
    Fail "oraculo: cauda do bloco de 64 tokens"
}

$m5W = New-M5W
$m5B = New-M5B
if (-not (Invoke-M5Train $m5W $m5B ([int[]]@(9, 12, 13, 14)) ([int[]]@(12, 13, 14, 24)) 4 5)) {
    Fail "oraculo: treino M5 falhou"
}
for ($y = 0; $y -lt 25; $y++) {
    $row = "$y " + ($m5W[$y] -join " ") + " " + $m5B[$y]
    if ($row -cne $m5FinalRows[$y]) { Fail "oraculo M5 diverge em y=$y. Obtido [$row]" }
}
$m5Chain = Get-M5Gen $m5W $m5B 9 16
$m5ChainIds = @($m5Chain.Saida[0..($m5Chain.Total - 1)])
if (($m5ChainIds -join " ") -cne "9 12 13 14 24") { Fail "oraculo M5: cadeia [$($m5ChainIds -join ' ')]" }

# 32 epocas: usado por V15.
$limW = Copy-CtxW $initW
$limB = Copy-CtxB $initB
$train32 = Invoke-CtxTrain $limW $limB $ENT $ALV 6 32
if ($train32.Code -ne 0) { Fail "oraculo: treino de 32 epocas retornou $($train32.Code)" }
if ($train32.History.Count -ne 33) { Fail "oraculo: historico de 32 epocas com $($train32.History.Count) valores" }

# --- Saidas esperadas por caso --------------------------------------------

$configLines = @(
    "INFO=CTX 3 12 325 300",
    "TAXA=1/8",
    "GRADE=1/16",
    "EPOCAS=7",
    "ESCALA_PERDA=131072",
    "LIMITE_PARAM=16",
    "ORDEM=EXEMPLO"
)

function Get-CtxPredLine {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $pred = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        $pred += (Get-CtxArgmax $W $B $c)
    }
    return "PRED=" + ($pred -join " ")
}

$expected = @{}

# ctx_init
$initPredLine = Get-CtxPredLine $initW $initB $ENT $ALV 6
$initAcc = 0
for ($i = 0; $i -lt 6; $i++) {
    [int[]]$c = Get-CtxC16FromExample $ENT $i
    if ((Get-CtxArgmax $initW $initB $c) -eq $ALV[$i]) { $initAcc++ }
}
$expected["ctx_init"] = @()
$expected["ctx_init"] += $configLines
$expected["ctx_init"] += Get-CtxParamLines $initW $initB
$expected["ctx_init"] += Get-CtxMaxLine $initW $initB
$expected["ctx_init"] += "PERDA=$(Get-CtxLoss $initW $initB $ENT $ALV 6)"
$expected["ctx_init"] += "ACERTOS=$initAcc"
$expected["ctx_init"] += $initPredLine

# ctx_contexto_k
$expected["ctx_contexto_k"] = @()
$expected["ctx_contexto_k"] += Get-CtxContextLine ([int[]]@(13))
$expected["ctx_contexto_k"] += Get-CtxContextLine ([int[]]@(9, 13))
$expected["ctx_contexto_k"] += Get-CtxContextLine ([int[]]@(9, 12, 13))
$expected["ctx_contexto_k"] += Get-CtxContextLine ([int[]]@(12, 9, 12, 13))
$expected["ctx_contexto_k"] += Get-CtxContextLine ([int[]]@(1, 2, 3, 4, 5))
$padOk = $true
for ($t = 0; $t -lt 25; $t++) {
    [int[]]$c = Get-CtxC16 ([int[]]@($t))
    for ($p = 0; $p -lt 8; $p++) { if ($c[$p] -ne 0) { $padOk = $false } }
    $naoZero = 0
    for ($p = 8; $p -lt 12; $p++) { if ($c[$p] -ne 0) { $naoZero++ } }
    if ($naoZero -eq 0) { $padOk = $false }
}
$padLine = if ($padOk) { "PAD_DISTINTO=OK" } else { "PAD_DISTINTO=FALHA" }
$expected["ctx_contexto_k"] += $padLine

# ctx_contexto_ordem
$perms = @(
    [int[]]@(9, 12, 13),
    [int[]]@(12, 9, 13),
    [int[]]@(9, 13, 12),
    [int[]]@(13, 12, 9)
)
$expected["ctx_contexto_ordem"] = @()
$vectors = @()
foreach ($perm in $perms) {
    $expected["ctx_contexto_ordem"] += Get-CtxContextLine $perm
    $vectors += ,((Get-CtxC16 $perm) -join " ")
}
$distintos = @($vectors | Sort-Object -Unique).Count
$expected["ctx_contexto_ordem"] += "ORDEM_DISTINTOS=$distintos"
$mesmo = @()
foreach ($idx in @(0, 2, 5)) {
    [int[]]$c = Get-CtxC16FromExample $ENT $idx
    $mesmo += (Get-CtxArgmax $finalW $finalB $c)
}
$expected["ctx_contexto_ordem"] += "MESMO_ULTIMO=" + ($mesmo -join " ")

# ctx_treino
$finalPredLine = Get-CtxPredLine $finalW $finalB $ENT $ALV 6
$altered = Get-CtxAltered $finalW $finalB
$expected["ctx_treino"] = @()
$expected["ctx_treino"] += Get-CtxParamLines $finalW $finalB
$expected["ctx_treino"] += Get-CtxMaxLine $finalW $finalB
$expected["ctx_treino"] += "HISTORICO=" + ($traj7 -join " ")
$expected["ctx_treino"] += "PERDA=$(Get-CtxLoss $finalW $finalB $ENT $ALV 6)"
$expected["ctx_treino"] += "ACERTOS=6"
$expected["ctx_treino"] += $finalPredLine
$expected["ctx_treino"] += "ALTERADOS_W=$($altered[0])"
$expected["ctx_treino"] += "ALTERADOS_B=$($altered[1])"
$expected["ctx_treino"] += "MARGENS=" + ($margins -join " ")

# ctx_ponto_fixo
$probeW = Copy-CtxW $finalW
$probeB = Copy-CtxB $finalB
$train8 = Invoke-CtxTrain $probeW $probeB $ENT $ALV 6 1
if ($train8.Code -ne 0) { Fail "oraculo: oitava epoca retornou $($train8.Code)" }
$changedW = 0
$changedB = 0
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 12; $p++) { if ($probeW[$y][$p] -ne $finalW[$y][$p]) { $changedW++ } }
    if ($probeB[$y] -ne $finalB[$y]) { $changedB++ }
}
$expected["ctx_ponto_fixo"] = @(
    "S7=153027",
    "S8=$($train8.History[1])",
    "MUDOU_W=$changedW",
    "MUDOU_B=$changedB"
)

# ctx_ablation
$expected["ctx_ablation"] = @(
    "ABL_FULL=$($ablFull.Acertos)",
    "ABL_FULL_S=$($ablFull.S)",
    "ABL_ULTIMO=$($ablUltimo.Acertos)",
    "ABL_ULTIMO_S=$($ablUltimo.S)",
    "ABL_ANTIGOS=$($ablAntigos.Acertos)",
    "ABL_ANTIGOS_S=$($ablAntigos.S)",
    "ABL_ULTIMO_MAX=$(Get-CtxMaxUltimo $ENT $ALV 6)",
    "ABL_BAG_MAX=$(Get-CtxMaxBag $ENT $ALV 6)"
)

# Geracao
$expected["ctx_geracao_cadeia"] = Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 64
$expected["ctx_geracao_limites"] = @()
$expected["ctx_geracao_limites"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 4
$expected["ctx_geracao_limites"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 3
$expected["ctx_geracao_limites"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(24)) 64
$expected["ctx_geracao_limites"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(12, 24)) 64
$expected["ctx_geracao_semente"] = @()
$expected["ctx_geracao_semente"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9)) 10
$expected["ctx_geracao_semente"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(12)) 10

# ctx_erros_treino: codigos derivados da precedencia n > epocas > ids > parametros.
function Get-CtxTrainCode {
    param([int]$N, [int]$Epocas, [int]$Ent0, [int]$Alvo0, [int]$W0, [int]$B0)
    if ($N -lt 1 -or $N -gt 6) { return 1 }
    if ($Epocas -lt 1 -or $Epocas -gt 32) { return 2 }
    if ($Ent0 -lt 0 -or $Ent0 -gt 24 -or $Alvo0 -lt 0 -or $Alvo0 -gt 24) { return 3 }
    if ([Math]::Abs($W0) -gt 16 -or [Math]::Abs($B0) -gt 16) { return 4 }
    return 0
}
function Get-CtxTrainErroLabel {
    param([int]$Code)
    switch ($Code) {
        1 { return "ERRO=EXEMPLOS_INVALIDOS" }
        2 { return "ERRO=EPOCAS_INVALIDAS" }
        3 { return "ERRO=ID_INVALIDO" }
        4 { return "ERRO=PARAMETROS_INVALIDOS" }
        5 { return "ERRO=ESTOURO_NUMERICO" }
    }
    return "VALIDO=OK"
}
$trainCalls = @(
    @(0, 7, 9, 14, 0, -4), @(7, 7, 9, 14, 0, -4),
    @(6, 0, 9, 14, 0, -4), @(6, 33, 9, 14, 0, -4),
    @(6, 7, 25, 14, 0, -4), @(6, 7, 9, -1, 0, -4),
    @(6, 7, 9, 14, 17, -4), @(6, 7, 9, 14, 0, -17),
    @(0, 0, 9, 14, 0, -4), @(6, 0, 25, 14, 0, -4),
    @(6, 7, 25, 14, 17, -4)
)
$expected["ctx_erros_treino"] = @()
foreach ($call in $trainCalls) {
    $code = Get-CtxTrainCode $call[0] $call[1] $call[2] $call[3] $call[4] $call[5]
    $expected["ctx_erros_treino"] += Get-CtxTrainErroLabel $code
    $expected["ctx_erros_treino"] += "INTACTO=OK"
}
$expected["ctx_erros_treino"] += "VALIDO=OK"
$overflowW = @{}
for ($y = 0; $y -lt 25; $y++) {
    $row = New-Object 'int[]' 12
    for ($p = 0; $p -lt 12; $p++) { $row[$p] = -16 }
    $overflowW[$y] = $row
}
$overflowB = @{}
for ($y = 0; $y -lt 25; $y++) { $overflowB[$y] = 0 }
$overflowEnt = New-Object 'int[]' 18
$overflowEnt[0] = 9
$overflowEnt[1] = 9
$overflowEnt[2] = 9
$overflowAlv = New-Object 'int[]' 6
$overflowAlv[0] = 0
$overflow = Invoke-CtxTrain $overflowW $overflowB $overflowEnt $overflowAlv 1 1
$expected["ctx_erros_treino"] += Get-CtxTrainErroLabel $overflow.Code
$expected["ctx_erros_treino"] += "PARCIAL_W0=$($overflow.W[0][0])"
$expected["ctx_erros_treino"] += "PARCIAL_W1=$($overflow.W[0][1])"
$expected["ctx_erros_treino"] += "PARCIAL_W299=$($overflow.W[24][11])"
$expected["ctx_erros_treino"] += "PARCIAL_B0=$($overflow.B[0])"
$expected["ctx_erros_treino"] += "PARCIAL_B24=$($overflow.B[24])"

# ctx_erros_geracao
function Get-CtxGerCode {
    param([int]$NPrefixo, [int]$Maximo, [int]$W0, [bool]$IdValido, [bool]$PareAntes)
    if ($NPrefixo -lt 1 -or $NPrefixo -gt 3 -or -not $IdValido -or $PareAntes) { return 1 }
    if ($Maximo -lt 1 -or $Maximo -gt 64 -or $Maximo -lt $NPrefixo) { return 2 }
    if ([Math]::Abs($W0) -gt 16) { return 3 }
    return 0
}
function Get-CtxGerErroLabel {
    param([int]$Code)
    switch ($Code) {
        1 { return "ERRO=PREFIXO_INVALIDO" }
        2 { return "ERRO=MAXIMO_INVALIDO" }
        3 { return "ERRO=PARAMETROS_INVALIDOS" }
    }
    return "VALIDO=OK"
}
$gerCalls = @(
    @(0, 64, 0, $true, $false), @(4, 64, 0, $true, $false),
    @(1, 64, 0, $false, $false), @(2, 64, 0, $true, $true),
    @(1, 0, 0, $true, $false), @(1, 65, 0, $true, $false),
    @(3, 2, 0, $true, $false), @(1, 64, 17, $true, $false),
    @(0, 0, 0, $true, $false), @(1, 0, 0, $true, $false)
)
$expected["ctx_erros_geracao"] = @()
foreach ($call in $gerCalls) {
    $code = Get-CtxGerCode $call[0] $call[1] $call[2] $call[3] $call[4]
    $expected["ctx_erros_geracao"] += Get-CtxGerErroLabel $code
    $expected["ctx_erros_geracao"] += "SAIDA_INTACTA=OK"
}
$expected["ctx_erros_geracao"] += "PARAMS_INTACTOS=OK"
$expected["ctx_erros_geracao"] += "SAIDA_INTACTA=OK"

# ctx_determinismo_a/b
$expected["ctx_determinismo_a"] = @()
$expected["ctx_determinismo_a"] += Get-CtxParamLines $finalW $finalB
$expected["ctx_determinismo_a"] += Get-CtxMaxLine $finalW $finalB
$expected["ctx_determinismo_a"] += "HISTORICO=" + ($traj7 -join " ")
$expected["ctx_determinismo_a"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 64
$expected["ctx_determinismo_a"] += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9)) 10
$expected["ctx_determinismo_b"] = $expected["ctx_determinismo_a"]

# ctx_composicao
$m4ok = 0
$m5ok = 0
$m6ok = 0
$m5InitW = New-M5W
$m5InitB = New-M5B
for ($t = 0; $t -lt 25; $t++) {
    [int[]]$c = Get-CtxC16 ([int[]]@($t))
    $m7pred = Get-CtxArgmax $initW $initB $c
    if ($m7pred -eq (Get-M5Argmax $m5InitW $m5InitB $t)) { $m5ok++ }
    if ($m7pred -eq (Get-M5Argmax $m5InitW $m5InitB $t)) { $m4ok++ }
    $m5gen = Get-M5Gen $m5InitW $m5InitB $t 16
    $m5ids = @($m5gen.Saida[0..($m5gen.Total - 1)])
    $m7gen = Get-CtxGeneration $initW $initB ([int[]]@($t)) 16
    $m7ids = @($m7gen.Saida[0..($m7gen.Total - 1)])
    if (($m5ids -join " ") -ceq ($m7ids -join " ")) { $m6ok++ }
}
$expected["ctx_composicao"] = @(
    "IDS=9 12 13 14 24",
    "E16_OK=100",
    "M4_OK=$m4ok",
    "M5_OK=$m5ok",
    "M6_OK=$m6ok",
    ("M6_CADEIA=" + ($m5ChainIds -join " ")),
    "COMPOE=OK"
)

# ctx_limites
$expected["ctx_limites"] = @()
$expected["ctx_limites"] += "HISTORICO=" + ($train32.History -join " ")
$limAcc = 0
for ($i = 0; $i -lt 6; $i++) {
    [int[]]$c = Get-CtxC16FromExample $ENT $i
    if ((Get-CtxArgmax $limW $limB $c) -eq $ALV[$i]) { $limAcc++ }
}
$expected["ctx_limites"] += "ACERTOS=$limAcc"
$expected["ctx_limites"] += Get-CtxGeracaoLines $limW $limB ([int[]]@(9)) 64

# ctx_params_intactos
$expected["ctx_params_intactos"] = @("PARAMS_INTACTOS=OK", "SAIDA_INTACTA=OK")

$expectedCases = @(
    "ctx_ablation", "ctx_composicao", "ctx_contexto_k", "ctx_contexto_ordem",
    "ctx_determinismo_a", "ctx_determinismo_b", "ctx_erros_geracao",
    "ctx_erros_treino", "ctx_geracao_cadeia", "ctx_geracao_limites",
    "ctx_geracao_semente", "ctx_init", "ctx_limites", "ctx_params_intactos",
    "ctx_ponto_fixo", "ctx_treino"
)

# --- V1: hashes congelados e diff aditivo --------------------------------

$v1Errors = @()
$frozenHashes = [ordered]@{
    "src/tokenizador.por"                 = "6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f"
    "src/embeddings.por"                  = "6f06aa820d163d3c1636383803b86105bf54cd85"
    "src/rede.por"                        = "fa9367a79bd2aefc373d30a94cfca2b7c86d9958"
    "src/treino.por"                      = "f5121423dd0aac6469b59b24b13d8a85b2c0d64d"
    "src/gerador.por"                     = "532e60cc52cef03fbd60c2a9d2b530472c73ded1"
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
    if ($lineCount -lt 377) { $v1Errors += "test.ps1 com $lineCount linhas; esperado >= 377" }
    $marker = "    # Gerar e anexar os casos de contexto multi-token (M7). Diretorio proprio"
    $blockStart = [Array]::IndexOf($testLines, $marker)
    if ($blockStart -lt 0) {
        $v1Errors += "bloco aditivo M7 ausente em test.ps1"
    } else {
        $block = @($testLines[$blockStart..($blockStart + 23)])
        if ($block.Count -ne 24) { $v1Errors += "bloco aditivo com $($block.Count) linhas; esperado 24" }
        foreach ($needle in @(
            "build-context-tests.ps1", "contextRoot = `"temp/context-tests`"",
            "contextGenerated", "no context test cases found"
        )) {
            if (-not (($block -join "`n").Contains($needle))) {
                $v1Errors += "bloco aditivo nao contem: $needle"
            }
        }
        $selfIndex = [Array]::IndexOf($testLines, "if (`$SelfTest) {")
        if ($selfIndex -lt 0) {
            $v1Errors += "if (`$SelfTest) ausente em test.ps1"
        } elseif ($selfIndex - 2 -le $blockStart -or $testLines[$selfIndex - 2] -ne "}") {
            $v1Errors += "fechamento de if (-not `$SelfTest) ausente depois do bloco M7"
        } else {
            $reconstructed = @()
            if ($blockStart -gt 0) { $reconstructed += $testLines[0..($blockStart - 1)] }
            $reconstructed += $testLines[($selfIndex - 2)..($testLines.Count - 1)]
            $reconPath = Join-Path $repoRoot "temp/m7-reconstructed-test.ps1"
            $reconText = ($reconstructed -join "`n")
            [IO.File]::WriteAllText($reconPath, $reconText, (New-Object System.Text.UTF8Encoding($true)))
            $reconHash = (& git -C $repoRoot hash-object -- "temp/m7-reconstructed-test.ps1" 2>$null)
            if ($reconHash -cne "2a37138ae53c5454806f2e7db0ec1fd3e356edb5") {
                $v1Errors += "test.ps1 sem os blocos M7/M8 nao reconstroi o hash pre-M7: $reconHash"
            }
        }
        $ifIndex = -1
        for ($i = 0; $i -lt $testLines.Count; $i++) {
            if ($testLines[$i] -eq "if (-not `$SelfTest) {") { $ifIndex = $i }
        }
        if ($ifIndex -lt 0 -or $blockStart -le $ifIndex) {
            $v1Errors += "bloco aditivo fora de if (-not `$SelfTest)"
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
    "?? src/corpus.por",
    "?? docs/evaluation-plan.md",
    "?? docs/evaluation-spec.md",
    "?? scripts/build-evaluation-tests.ps1",
    "?? scripts/eval-datasets.ps1",
    "?? scripts/eval-oracle.ps1",
    "?? scripts/test-evaluation.ps1",
    "?? scripts/verify-evaluation-bytes.ps1",
    "?? src/avaliacao.por",
    " M scripts/verify-corpus-bytes.ps1"
)
$statusLines = @(& git -C $repoRoot status --short 2>$null | ForEach-Object { $_.TrimEnd() })
$unexpected = @($statusLines | Where-Object { $allowedStatus -notcontains $_ })
if ($unexpected.Count -gt 0) {
    $v1Errors += "git status fora do escopo: " + ($unexpected -join " | ")
}
Write-Check "V1 15 hashes congelados, diff aditivo de test.ps1 e escopo do git status" $v1Errors

# --- V2: conjunto de casos e codificacao ---------------------------------

if (-not (Test-Path -LiteralPath $InterpreterPath)) { Fail "interpretador nao encontrado: $InterpreterPath" }
$generatedFull = Join-Path $repoRoot $GeneratedRoot
if (-not (Test-Path -Path $generatedFull)) { Fail "diretorio de casos nao encontrado: $generatedFull" }

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
Write-Check "V2 conjunto de 16 casos, .por/.expected e docs com codificacao contratada" $v2Errors
if ($v2Errors.Count -gt 0) { exit 1 }

Write-Host "=== Verificacao de bytes e valores do contexto M7 ==="
Write-Host "Fonte:         $SourcePath"
Write-Host "Casos:         $GeneratedRoot"
Write-Host "Interpretador: $InterpreterPath"
Write-Host "Casos esperados: $($expectedCases.Count)"

# --- Execucao crua --------------------------------------------------------

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
$rawFailures = 0
foreach ($name in $expectedCases) {
    $check = Test-RawCase $name $runs[$name].Bytes $runs[$name].Errors
    if ($check.Errors.Count -gt 0) { $rawFailures++ }
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

# --- V3: config -----------------------------------------------------------

$v3Errors = @()
$v3Errors += Compare-Lines "ctx_init" (@($configLines) + @($expected["ctx_init"][7..($expected["ctx_init"].Count - 1)]))
$sourceText = [IO.File]::ReadAllText((Join-Path $repoRoot $SourcePath), [Text.Encoding]::ASCII)
foreach ($req in @(
    "CTX_K = 3", "CTX_ENTRADAS = 12", "CTX_PARAMS = 325", "CTX_TOTAL_W = 300",
    "CTX_TAXA_NUM = 1", "CTX_TAXA_DEN = 8", "CTX_GRADE = 16", "CTX_EPOCAS = 7",
    "CTX_ESCALA_PERDA = 131072", "CTX_LIMITE = 16"
)) {
    if ($sourceText.IndexOf($req, [StringComparison]::Ordinal) -lt 0) { $v3Errors += "constante ausente na fonte: $req" }
}
Write-Check "V3 7 linhas de config e constantes canonicas" $v3Errors

# --- V4: tabela inicial ---------------------------------------------------

$v4Errors = @(Compare-Lines "ctx_init" $expected["ctx_init"])
$initParams = Get-CtxParamLines $initW $initB
$gotInit = @($linesByName["ctx_init"][7..31])
if (($gotInit -join "`n") -cne ($initParams -join "`n")) { $v4Errors += "tabela inicial nao confere" }
if ($linesByName["ctx_init"][32] -cne "MAXIMO16=12 4") { $v4Errors += "MAXIMO16 inicial diferente de 12 4" }
Write-Check "V4 tabela inicial de 25 linhas e MAXIMO16=12 4" $v4Errors

# --- V5: avaliacao inicial ------------------------------------------------

$v5Errors = @()
if ($linesByName["ctx_init"][33] -cne "PERDA=6728768") { $v5Errors += "S0 != 6728768" }
if ($linesByName["ctx_init"][34] -cne "ACERTOS=0") { $v5Errors += "acertos iniciais != 0" }
if ($linesByName["ctx_init"][35] -cne "PRED=6 11 6 19 10 6") { $v5Errors += "PRED inicial diverge" }
Write-Check "V5 S0, acertos e PRED iniciais" $v5Errors

# --- V6: contextos de 1..5 tokens ----------------------------------------

$v6Errors = @(Compare-Lines "ctx_contexto_k" $expected["ctx_contexto_k"])
for ($i = 0; $i -lt 5; $i++) {
    $line = $linesByName["ctx_contexto_k"][$i]
    if ($line -notmatch '^CTX16=[1-5] (-?[0-9]+ ){11}-?[0-9]+$') {
        $v6Errors += "linha CTX16 fora do formato: [$line]"
    }
}
Write-Check "V6 janela de 1..5 tokens, padding zero e PAD_DISTINTO" $v6Errors

# --- V7: ordem ------------------------------------------------------------

$v7Errors = @(Compare-Lines "ctx_contexto_ordem" $expected["ctx_contexto_ordem"])
$orderVectors = @()
for ($i = 0; $i -lt 4; $i++) {
    $orderVectors += ($linesByName["ctx_contexto_ordem"][$i].Substring(7))
}
if (@($orderVectors | Sort-Object -Unique).Count -ne 4) { $v7Errors += "permutacoes colidem" }
if ($linesByName["ctx_contexto_ordem"][4] -cne "ORDEM_DISTINTOS=4") { $v7Errors += "ORDEM_DISTINTOS != 4" }
if ($linesByName["ctx_contexto_ordem"][5] -cne "MESMO_ULTIMO=14 10 9") { $v7Errors += "MESMO_ULTIMO diverge" }
Write-Check "V7 quatro permutacoes distintas e grupo do ultimo 13" $v7Errors

# --- V8: treino -----------------------------------------------------------

$v8Errors = @(Compare-Lines "ctx_treino" $expected["ctx_treino"])
$trajLine = $linesByName["ctx_treino"][26]
if ($trajLine -cne "HISTORICO=" + ($traj7 -join " ")) { $v8Errors += "HISTORICO diverge da trajetoria" }
for ($e = 1; $e -le 7; $e++) {
    if ($traj7[$e] -ge $traj7[$e - 1] -and $e -lt 8) { $v8Errors += "trajetoria nao decresce em S$e" }
}
if ($linesByName["ctx_treino"][26 + 1] -cne "PERDA=153027") { $v8Errors += "PERDA final != 153027" }
if ($linesByName["ctx_treino"][30] -cne "ALTERADOS_W=249") { $v8Errors += "ALTERADOS_W != 249" }
if ($linesByName["ctx_treino"][31] -cne "ALTERADOS_B=24") { $v8Errors += "ALTERADOS_B != 24" }
if ($linesByName["ctx_treino"][32] -cne "MARGENS=142 151 156 174 201 167") { $v8Errors += "MARGENS divergem" }
Write-Check "V8 trajetoria S0..S7, tabela final, margens e alterados" $v8Errors

# --- V9: ponto fixo -------------------------------------------------------

$v9Errors = @(Compare-Lines "ctx_ponto_fixo" $expected["ctx_ponto_fixo"])
$s7Value = $linesByName["ctx_ponto_fixo"][0].Substring(3)
$s8Value = $linesByName["ctx_ponto_fixo"][1].Substring(3)
if ($s7Value -cne $s8Value) { $v9Errors += "S7 != S8" }
if ($linesByName["ctx_ponto_fixo"][2] -cne "MUDOU_W=0") { $v9Errors += "MUDOU_W != 0" }
if ($linesByName["ctx_ponto_fixo"][3] -cne "MUDOU_B=0") { $v9Errors += "MUDOU_B != 0" }
Write-Check "V9 oitava epoca e ponto fixo exato" $v9Errors

# --- V10: abstencoes ------------------------------------------------------

$v10Errors = @(Compare-Lines "ctx_ablation" $expected["ctx_ablation"])
if ($linesByName["ctx_ablation"][0] -cne "ABL_FULL=6") { $v10Errors += "ablacao full != 6" }
if ($linesByName["ctx_ablation"][4] -cne "ABL_ANTIGOS=6") { $v10Errors += "ablacao antigos != 6" }
if ($linesByName["ctx_ablation"][2] -cne "ABL_ULTIMO=1") { $v10Errors += "ablacao ultimo != 1" }
if ($linesByName["ctx_ablation"][6] -cne "ABL_ULTIMO_MAX=4") { $v10Errors += "limite ultimo != 4" }
if ($linesByName["ctx_ablation"][7] -cne "ABL_BAG_MAX=2") { $v10Errors += "limite bag != 2" }
Write-Check "V10 abstencoes e limites superiores 4/6 e 2/6" $v10Errors

# --- V11: geracao ---------------------------------------------------------

function Get-Blocks {
    param([string[]]$Lines)
    $blocks = @()
    for ($i = 0; $i -le $Lines.Count - 5; $i++) {
        if ($Lines[$i] -like "GERADO=*" -and $Lines[$i + 1] -like "N=*" -and
            $Lines[$i + 2] -like "PASSOS=*" -and $Lines[$i + 3] -like "PARADA=*" -and
            $Lines[$i + 4] -like "TEXTO=*") {
            $blocks += ,@($Lines[$i..($i + 4)])
            $i += 4
        }
    }
    return $blocks
}

$v11Errors = @()
$v11Errors += Compare-Lines "ctx_geracao_cadeia" $expected["ctx_geracao_cadeia"]
$v11Errors += Compare-Lines "ctx_geracao_limites" $expected["ctx_geracao_limites"]
$v11Errors += Compare-Lines "ctx_geracao_semente" $expected["ctx_geracao_semente"]
$blockSpecs = @{
    "ctx_geracao_cadeia" = @("3:64")
    "ctx_geracao_limites" = @("3:4", "3:3", "1:64", "2:64")
    "ctx_geracao_semente" = @("1:10", "1:10")
    "ctx_determinismo_a" = @("3:64", "1:10")
    "ctx_determinismo_b" = @("3:64", "1:10")
}
foreach ($name in @($blockSpecs.Keys | Sort-Object)) {
    $blocks = @(Get-Blocks $linesByName[$name])
    $specs = @($blockSpecs[$name])
    if ($blocks.Count -ne $specs.Count) {
        $v11Errors += "${name}: $($blocks.Count) blocos; esperado $($specs.Count)"
        continue
    }
    for ($b = 0; $b -lt $blocks.Count; $b++) {
        $specParts = $specs[$b] -split ":"
        $nPref = [int]$specParts[0]
        $maximo = [int]$specParts[1]
        $idsText = $blocks[$b][0].Substring("GERADO=".Length)
        $ids = @($idsText -split " ")
        $n = [int]$blocks[$b][1].Substring("N=".Length)
        $passos = $blocks[$b][2].Substring("PASSOS=".Length)
        $parada = $blocks[$b][3].Substring("PARADA=".Length)
        if ($idsText -match '^ | $|  ') { $v11Errors += "${name}[$b]: espaco extra em GERADO" }
        if ($n -ne $ids.Count) { $v11Errors += "${name}[$b]: N=$n com $($ids.Count) IDs" }
        if ($n -lt $nPref -or $n -gt $maximo) { $v11Errors += "${name}[$b]: N=$n fora de $nPref..$maximo" }
        $last = [int]$ids[$ids.Count - 1]
        if ($passos -ne "$($n - $nPref)") { $v11Errors += "${name}[$b]: PASSOS=$passos; esperado $($n - $nPref)" }
        $wantParada = if ($last -eq 24) { "PARE" } else { "MAXIMO" }
        if ($parada -cne $wantParada) { $v11Errors += "${name}[$b]: PARADA=$parada; esperado $wantParada" }
        if ($n -lt $maximo -and $last -ne 24) { $v11Errors += "${name}[$b]: parou antes do limite sem 24" }
        foreach ($idText in $ids) {
            if ($idText -notmatch '^(0|[1-9][0-9]*)$' -or [int]$idText -gt 24) {
                $v11Errors += "${name}[$b]: ID invalido [$idText]"
            }
        }
    }
}
if ((@($gen64[0] -split " ")).Count -ne 64) { $v11Errors += "bloco de 64 tokens nao tem 64 campos" }
Write-Check "V11 blocos de geracao, 64 tokens, N/PASSOS/PARADA" $v11Errors

# --- V12: erros e preservacao --------------------------------------------

$v12Errors = @()
$v12Errors += Compare-Lines "ctx_erros_treino" $expected["ctx_erros_treino"]
$v12Errors += Compare-Lines "ctx_erros_geracao" $expected["ctx_erros_geracao"]
$treinoLines = @($linesByName["ctx_erros_treino"])
$gerLines = @($linesByName["ctx_erros_geracao"])
if ($treinoLines[23] -cne "ERRO=ESTOURO_NUMERICO") { $v12Errors += "testemunho de estouro ausente" }
if ($treinoLines[24] -cne "PARCIAL_W0=-20") { $v12Errors += "estado parcial W0 != -20" }
if ($treinoLines[25] -cne "PARCIAL_W1=-16") { $v12Errors += "estado parcial W1 != -16" }
if ($treinoLines[26] -cne "PARCIAL_W299=-16") { $v12Errors += "estado parcial W299 != -16" }
if ($treinoLines[27] -cne "PARCIAL_B0=0") { $v12Errors += "estado parcial B0 != 0" }
if ($treinoLines[28] -cne "PARCIAL_B24=0") { $v12Errors += "estado parcial B24 != 0" }
if (-not ($treinoLines -ccontains "VALIDO=OK")) { $v12Errors += "VALIDO=OK ausente" }
if (-not ($gerLines -ccontains "PARAMS_INTACTOS=OK")) { $v12Errors += "PARAMS_INTACTOS=OK ausente" }
$intactCount = @($gerLines | Where-Object { $_ -ceq "SAIDA_INTACTA=OK" }).Count
if ($intactCount -ne 11) { $v12Errors += "SAIDA_INTACTA=OK aparece $intactCount vezes; esperado 11" }
Write-Check "V12 codigos, precedencia, estado parcial e buffers intactos" $v12Errors

# --- V13: determinismo ----------------------------------------------------

$v13Errors = @()
$pathA = Join-Path $generatedFull "ctx_determinismo_a.expected"
$pathB = Join-Path $generatedFull "ctx_determinismo_b.expected"
$bytesEA = [IO.File]::ReadAllBytes($pathA)
$bytesEB = [IO.File]::ReadAllBytes($pathB)
if (-not [Convert]::ToBase64String($bytesEA).Equals([Convert]::ToBase64String($bytesEB), [StringComparison]::Ordinal)) {
    $v13Errors += "ctx_determinismo_a.expected difere de b"
}
if (-not [Convert]::ToBase64String($runs["ctx_determinismo_a"].Bytes).Equals(
        [Convert]::ToBase64String($runs["ctx_determinismo_b"].Bytes), [StringComparison]::Ordinal)) {
    $v13Errors += "saidas A e B diferem"
}
$runA2 = Invoke-CaseRaw (Join-Path $generatedFull "ctx_determinismo_a.por")
$runB2 = Invoke-CaseRaw (Join-Path $generatedFull "ctx_determinismo_b.por")
if (-not [Convert]::ToBase64String($runA2.Bytes).Equals(
        [Convert]::ToBase64String($runs["ctx_determinismo_a"].Bytes), [StringComparison]::Ordinal)) {
    $v13Errors += "segunda execucao de A difere da primeira"
}
if (-not [Convert]::ToBase64String($runB2.Bytes).Equals(
        [Convert]::ToBase64String($runs["ctx_determinismo_b"].Bytes), [StringComparison]::Ordinal)) {
    $v13Errors += "segunda execucao de B difere da primeira"
}
if ($runA2.Errors.Length -gt 0 -or $runB2.Errors.Length -gt 0) { $v13Errors += "stderr nao vazio na segunda execucao" }
Write-Check "V13 A e B byte a byte, em duas execucoes" $v13Errors

# --- V14: composicao ------------------------------------------------------

$v14Errors = @(Compare-Lines "ctx_composicao" $expected["ctx_composicao"])
$comp = @($linesByName["ctx_composicao"])
if ($comp[0] -cne "IDS=9 12 13 14 24") { $v14Errors += "IDS da M1 diverge" }
if ($comp[1] -cne "E16_OK=100") { $v14Errors += "e16 nao cobre 25x4" }
if ($comp[2] -cne "M4_OK=25") { $v14Errors += "M4_OK != 25" }
if ($comp[3] -cne "M5_OK=25") { $v14Errors += "M5_OK != 25" }
if ($comp[4] -cne "M6_OK=25") { $v14Errors += "M6_OK != 25" }
if ($comp[5] -cne "M6_CADEIA=9 12 13 14 24") { $v14Errors += "M6_CADEIA diverge da M5 treinada" }
if ($comp[6] -cne "COMPOE=OK") { $v14Errors += "COMPOE=OK ausente" }
Write-Check "V14 composicao M1-M6: IDs, e16, argmax, mapa e cadeia" $v14Errors

# --- V15: limites ---------------------------------------------------------

$v15Errors = @(Compare-Lines "ctx_limites" $expected["ctx_limites"])
$limLines = @($linesByName["ctx_limites"])
$histText = $limLines[0].Substring("HISTORICO=".Length)
$histFields = @($histText -split " ")
if ($histFields.Count -ne 33) { $v15Errors += "HISTORICO com $($histFields.Count) valores; esperado 33" }
for ($e = 0; $e -le 7; $e++) {
    if ([long]$histFields[$e] -ne $traj7Frozen[$e]) { $v15Errors += "HISTORICO[$e] diverge" }
}
for ($e = 8; $e -le 32; $e++) {
    if ([long]$histFields[$e] -ne 153027) { $v15Errors += "HISTORICO[$e] != 153027" }
}
if ($limLines[1] -cne "ACERTOS=6") { $v15Errors += "ACERTOS apos 32 epocas != 6" }
if ($limLines[3] -cne "N=64") { $v15Errors += "N != 64" }
if ($limLines[4] -cne "PASSOS=63") { $v15Errors += "PASSOS != 63" }
if ($limLines[5] -cne "PARADA=MAXIMO") { $v15Errors += "PARADA != MAXIMO" }
Write-Check "V15 n=6, 32 epocas, 33 valores e maximo=64" $v15Errors

# --- V16: pureza e regressao completa ------------------------------------

$v16Errors = @()
$cleanCode = (($sourceText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
$cleanCode = [regex]::Replace($cleanCode, '"[^"]*"', '""')
foreach ($forbidden in @(
    "programa", "inicio", "inclua", "Matematica", "aleatorio", "tempo",
    "leia", "softmax", "exp(", "temperatura", "top_", "real"
)) {
    if ($cleanCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $v16Errors += "identificador proibido na fonte: $forbidden"
    }
}
foreach ($dep in @("treino_", "gerador_", "emb_", "rede_", "tokenizar")) {
    if ($cleanCode.IndexOf($dep, [StringComparison]::Ordinal) -ge 0) {
        $v16Errors += "dependencia externa na fonte: $dep"
    }
}

function Get-CtxBlocks {
    param([string]$Text)
    $result = @()
    $idx = 0
    while (($idx = $Text.IndexOf("funcao ", $idx, [StringComparison]::Ordinal)) -ge 0) {
        $paren = $Text.IndexOf("(", $idx)
        if ($paren -lt 0) { break }
        $prefix = $Text.Substring($idx + 7, $paren - ($idx + 7)).Trim()
        $parts = $prefix -split '\s+'
        $fname = $parts[$parts.Count - 1]
        $brace = $Text.IndexOf("{", $paren)
        if ($brace -lt 0) { break }
        $depth = 0
        $end = $brace
        for ($j = $brace; $j -lt $Text.Length; $j++) {
            $ch = $Text[$j]
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { $end = $j; break } }
        }
        $result += [pscustomobject]@{
            Name = $fname
            Body = $Text.Substring($idx, $end - $idx + 1)
        }
        $idx = $end + 1
    }
    return $result
}

$assignmentFunctions = @()
foreach ($fn in @(Get-CtxBlocks $cleanCode)) {
    if ($fn.Body -match 'w16\[[^\]]+\]\s*=\s*[^=]' -or $fn.Body -match 'b16\[[^\]]+\]\s*=\s*[^=]') {
        $assignmentFunctions += $fn.Name
    }
}
$assignmentFunctions = @($assignmentFunctions | Sort-Object -Unique)
if (($assignmentFunctions -join "|") -cne "ctx_executar|ctx_inicializar") {
    $v16Errors += "funcoes que escrevem parametros: [$($assignmentFunctions -join ', ')]"
}
if (-not ($sourceText.Contains("funcao ctx_inicializar(inteiro w16[], inteiro b16[])"))) {
    $v16Errors += "ctx_inicializar ausente"
}

function Get-SuiteSummaryErrors {
    param([string]$Output)
    $result = @()
    $passed = $null
    $failed = $null
    $total = $null
    if ($Output -match 'Passed:\s+(\d+)') { $passed = [int]$Matches[1] }
    if ($Output -match 'Failed:\s+(\d+)') { $failed = [int]$Matches[1] }
    if ($Output -match 'Total:\s+(\d+)') { $total = [int]$Matches[1] }
    if ($null -eq $passed -or $null -eq $failed -or $null -eq $total) {
        return @("suite sem Passed/Failed/Total numericos")
    }
    if ($failed -ne 0) { $result += "suite reportou $failed FAIL" }
    if ($passed -lt 100) { $result += "suite reportou $passed PASS; esperado >= 100" }
    if ($total -lt 100) { $result += "suite reportou Total $total; esperado >= 100" }
    if ($total -ne ($passed + $failed)) {
        $result += "Total $total diferente de Passed $passed + Failed $failed"
    }
    return $result
}

$psExe = (Get-Process -Id $PID).Path
$suiteLog = Join-Path $repoRoot "temp/m7-verify-suite.log"
$suiteOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts/test.ps1") 2>&1 | Out-String
$suiteCode = $LASTEXITCODE
[IO.File]::WriteAllText($suiteLog, $suiteOut, (New-Object System.Text.UTF8Encoding($false)))
if ($suiteCode -ne 0) { $v16Errors += "suite saiu com $suiteCode" }
$v16Errors += @(Get-SuiteSummaryErrors $suiteOut)

$selfLog = Join-Path $repoRoot "temp/m7-verify-selftest.log"
$selfOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts/test.ps1") -SelfTest 2>&1 | Out-String
$selfCode = $LASTEXITCODE
[IO.File]::WriteAllText($selfLog, $selfOut, (New-Object System.Text.UTF8Encoding($false)))
if ($selfCode -ne 1) { $v16Errors += "autoteste saiu com $selfCode; esperado 1" }
if ($selfOut -notmatch 'Passed:\s+0') { $v16Errors += "autoteste nao reportou 0 PASS" }
if ($selfOut -notmatch 'Failed:\s+1') { $v16Errors += "autoteste nao reportou 1 FAIL" }

$verifiers = @(
    @{ Script = "verify-bytes.ps1"; Checks = 21 },
    @{ Script = "verify-embedding-bytes.ps1"; Checks = 19 },
    @{ Script = "verify-network-bytes.ps1"; Checks = 22 },
    @{ Script = "verify-training-bytes.ps1"; Checks = 23 },
    @{ Script = "verify-generation-bytes.ps1"; Checks = 13 }
)
foreach ($v in $verifiers) {
    $path = Join-Path $repoRoot ("scripts/" + $v.Script)
    $log = Join-Path $repoRoot ("temp/m7-verify-" + $v.Script + ".log")
    $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $path 2>&1 | Out-String
    $code = $LASTEXITCODE
    [IO.File]::WriteAllText($log, $out, (New-Object System.Text.UTF8Encoding($false)))
    if ($code -ne 0) { $v16Errors += "$($v.Script) saiu com $code" }
    $countOk = ($out -match ("Checks:\s+" + $v.Checks)) -or
        ($out -match ("Total:\s+" + $v.Checks + "\s+verificacoes,\s+0\s+falha"))
    if (-not $countOk) { $v16Errors += "$($v.Script) nao reportou $($v.Checks) verificacoes" }
    if ($out -notmatch 'Failures:\s+0' -and $out -notmatch 'verificacoes,\s+0\s+falha') {
        $v16Errors += "$($v.Script) nao reportou zero falhas"
    }
}
Write-Check "V16 pureza estatica, suite 100/100, autoteste 1 FAIL e M1-M6" $v16Errors

# --- Resumo ---------------------------------------------------------------

Write-Host ""
Write-Host "=== Resultado ==="
Write-Host "Checks:   $script:checks"
Write-Host "Failures: $script:failures"
Write-Host "Casos:    $($expectedCases.Count) executados"

if ($script:failures -gt 0) {
    Write-Host "Verificacao do contexto M7 FALHOU." -ForegroundColor Red
    exit 1
}
Write-Host "Verificacao do contexto M7 aprovada." -ForegroundColor Green
exit 0
