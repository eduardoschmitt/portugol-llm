<#
.SYNOPSIS
    Gera os 12 casos .por e .expected do treinamento em temp/training-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/treino.por (e, em trn_composicao, tambem src/tokenizador.por,
    src/embeddings.por e src/rede.por) a um driver. Os valores esperados sao
    recalculados aqui por um oraculo inteiro independente (W16, b16, e16, Z256,
    delta256, r(num,den)), sem [double] e sem ler a saida do .por. As tabelas
    canonicas da spec sao conferidas como literais. Tudo e gravado em UTF-8 sem
    BOM, LF.
#>

param(
    [string]$SourcePath = "src/treino.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$NetworkSourcePath = "src/rede.por",
    [string]$OutputRoot = "temp/training-tests"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-Utf8NoBom {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF-8 BOM encontrado em $Path"
    }
    $decoded = [Text.Encoding]::UTF8.GetString($bytes)
    $roundTrip = [Text.Encoding]::UTF8.GetBytes($decoded)
    if (-not [Convert]::ToBase64String($bytes).Equals([Convert]::ToBase64String($roundTrip), [StringComparison]::Ordinal)) {
        throw "Conteudo nao e UTF-8 valido: $Path"
    }
}

function Assert-AsciiLf {
    param([string]$Path)
    Assert-Utf8NoBom $Path
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { throw "Arquivo vazio: $Path" }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { throw "CR encontrado em $Path" }
        if ($b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) {
            throw ("Byte nao ASCII 0x{0:X2} em {1}" -f $b, $Path)
        }
    }
    if ($bytes[$bytes.Length - 1] -ne 0x0A) {
        throw "Arquivo nao termina em LF: $Path"
    }
}

function Add-PortugolIndent {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $indented = foreach ($line in $lines) {
        if ($line -eq "") { "" } else { "        " + $line }
    }
    return ($indented -join "`n")
}

# --- Oraculo inteiro independente -----------------------------------------

function Get-W16 {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = (($y * 7 + $d * 5) % 25) - 12 }
        $w[$y] = $row
    }
    return $w
}

function Get-B16 {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-W16 {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = $W[$y][$d] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-B16 {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-Emb16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

function Get-Z256 {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada, [int]$Y)
    [long]$soma = 0
    for ($d = 0; $d -lt 4; $d++) {
        $soma += [long]$W[$Y][$d] * [long](Get-Emb16 $Entrada $d)
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-Delta256 {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada, [int]$Y, [int]$Alvo)
    [long]$z = Get-Z256 $W $B $Entrada $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-Argmax {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada)
    $melhor = 0
    [long]$melhorValor = Get-Z256 $W $B $Entrada 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-Z256 $W $B $Entrada $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-LossS {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-Delta256 $W $B $Entradas[$i] $y $Alvos[$i]
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-Acertos {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($i = 0; $i -lt $N; $i++) {
        if ((Get-Argmax $W $B $Entradas[$i]) -eq $Alvos[$i]) { $total++ }
    }
    return $total
}

function Get-RoundHalfAway {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

function Get-GradienteW {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N, [int]$Y, [int]$D)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        $soma += (Get-Delta256 $W $B $Entradas[$i] $Y $Alvos[$i]) * [long](Get-Emb16 $Entradas[$i] $D)
    }
    return $soma
}

function Get-GradienteB {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N, [int]$Y)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        $soma += Get-Delta256 $W $B $Entradas[$i] $Y $Alvos[$i]
    }
    return 16 * $soma
}

function Get-Gradiente {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $exatos = 0
    [long]$soma = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($d = 0; $d -lt 4; $d++) {
            [long]$g = Get-GradienteW $W $B $Entradas $Alvos $N $y $d
            $original = $W[$y][$d]
            $W[$y][$d] = $original + 1
            [long]$mais = Get-LossS $W $B $Entradas $Alvos $N
            $W[$y][$d] = $original - 1
            [long]$menos = Get-LossS $W $B $Entradas $Alvos $N
            $W[$y][$d] = $original
            if (($mais - $menos) -eq (4 * $g)) { $exatos++ }
            $soma += $g
        }
        [long]$gb = Get-GradienteB $W $B $Entradas $Alvos $N $y
        $originalB = $B[$y]
        $B[$y] = $originalB + 1
        [long]$maisB = Get-LossS $W $B $Entradas $Alvos $N
        $B[$y] = $originalB - 1
        [long]$menosB = Get-LossS $W $B $Entradas $Alvos $N
        $B[$y] = $originalB
        if (($maisB - $menosB) -eq (4 * $gb)) { $exatos++ }
        $soma += $gb
    }
    return [pscustomobject]@{ Exatos = $exatos; Soma = $soma }
}

function Invoke-Training {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-LossS $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-Delta256 $W $B $Entradas[$i] $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($d = 0; $d -lt 4; $d++) {
                    [long]$novo = Get-RoundHalfAway (
                        1024 * [long]$W[$y][$d] - $delta[$y] * [long](Get-Emb16 $Entradas[$i] $d)) 1024
                    $W[$y][$d] = $novo
                    if ([Math]::Abs($novo) -gt 48) {
                        return [pscustomobject]@{ Code = 5; History = $history }
                    }
                }
                [long]$novoB = Get-RoundHalfAway (64 * [long]$B[$y] - $delta[$y]) 64
                $B[$y] = $novoB
                if ([Math]::Abs($novoB) -gt 48) {
                    return [pscustomobject]@{ Code = 5; History = $history }
                }
            }
        }
        $history[$ep] = Get-LossS $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history }
}

# --- Formatadores ----------------------------------------------------------

function Get-Param16Line {
    param([hashtable]$W, [hashtable]$B, [int]$Y)
    return "PARAM16=$Y $($W[$Y][0]) $($W[$Y][1]) $($W[$Y][2]) $($W[$Y][3]) $($B[$Y])"
}

function Get-MaxAbs {
    param([hashtable]$W, [hashtable]$B)
    $maxW = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($d = 0; $d -lt 4; $d++) {
            $v = [Math]::Abs($W[$y][$d])
            if ($v -gt $maxW) { $maxW = $v }
        }
    }
    $maxB = 0
    for ($y = 0; $y -lt 25; $y++) {
        $v = [Math]::Abs($B[$y])
        if ($v -gt $maxB) { $maxB = $v }
    }
    return @($maxW, $maxB)
}

function Get-StateLines {
    param([hashtable]$W, [hashtable]$B)
    $lines = @()
    for ($y = 0; $y -lt 25; $y++) { $lines += Get-Param16Line $W $B $y }
    $max = Get-MaxAbs $W $B
    $lines += "MAXIMO16=$($max[0]) $($max[1])"
    return $lines
}

function Get-Alterados {
    param([hashtable]$W, [hashtable]$B)
    $aw = 0
    $ab = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($d = 0; $d -lt 4; $d++) {
            if ($W[$y][$d] -ne ((($y * 7 + $d * 5) % 25) - 12)) { $aw++ }
        }
        if ($B[$y] -ne ((($y * 7) % 9) - 4)) { $ab++ }
    }
    return @($aw, $ab)
}

function Get-AlteradosLines {
    param([hashtable]$W, [hashtable]$B)
    $a = Get-Alterados $W $B
    return @("ALTERADOS_W=$($a[0])", "ALTERADOS_B=$($a[1])")
}

function Get-HistoryLine {
    param([long[]]$History)
    return "HISTORICO=" + (($History | ForEach-Object { $_.ToString() }) -join " ")
}

function Get-Avaliacao {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $parts = @()
    for ($i = 0; $i -lt $N; $i++) { $parts += (Get-Argmax $W $B $Entradas[$i]) }
    return @(
        "PERDA=$(Get-LossS $W $B $Entradas $Alvos $N)",
        "ACERTOS=$(Get-Acertos $W $B $Entradas $Alvos $N)",
        ("PRED=" + ($parts -join " "))
    )
}

function Format-Key {
    param([hashtable]$W, [hashtable]$B)
    $rows = @()
    for ($y = 0; $y -lt 25; $y++) { $rows += (Get-Param16Line $W $B $y) }
    $rows += (Get-AlteradosLines $W $B)
    return ($rows -join "|")
}

# --- Dados canonicos -------------------------------------------------------

$ENT = [int[]]@(9, 12, 13, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
$ALV = [int[]]@(12, 13, 14, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

$wInitialCanonical = @(
    "0 -12 -7 -2 3 -4", "1 -5 0 5 10 3", "2 2 7 12 -8 1", "3 9 -11 -6 -1 -1",
    "4 -9 -4 1 6 -3", "5 -2 3 8 -12 4", "6 5 10 -10 -5 2", "7 12 -8 -3 2 0",
    "8 -6 -1 4 9 -2", "9 1 6 11 -9 -4", "10 8 -12 -7 -2 3", "11 -10 -5 0 5 1",
    "12 -3 2 7 12 -1", "13 4 9 -11 -6 -3", "14 11 -9 -4 1 4", "15 -7 -2 3 8 2",
    "16 0 5 10 -10 0", "17 7 12 -8 -3 -2", "18 -11 -6 -1 4 -4", "19 -4 1 6 11 3",
    "20 3 8 -12 -7 1", "21 10 -10 -5 0 -1", "22 -8 -3 2 7 -3", "23 -1 4 9 -11 4",
    "24 6 11 -9 -4 2"
)
$wFinalCanonical = @(
    "0 -1 0 -3 2 -1", "1 0 0 -2 3 0", "2 0 0 11 -10 2", "3 1 0 -3 2 -2",
    "4 0 0 -4 3 0", "5 -1 0 10 -11 2", "6 -1 0 -3 2 0", "7 1 0 -3 3 -1",
    "8 0 -1 -2 3 1", "9 0 0 9 -10 1", "10 1 0 -1 2 -1", "11 -1 0 -1 2 1",
    "12 8 -7 -3 3 2", "13 1 2 3 6 6", "14 1 8 -4 -2 2", "15 0 -1 -2 3 0",
    "16 0 1 10 -10 3", "17 0 0 -3 2 -1", "18 -1 -1 -3 4 0", "19 1 -1 -2 3 0",
    "20 -1 0 -4 3 0", "21 0 0 -3 3 -1", "22 0 0 -3 4 0", "23 -1 0 10 -10 3",
    "24 -9 -2 -4 0 4"
)
$historyCanonical = @(3674036, 428488, 107796, 41544, 30998, 27804)
$rTable = @(
    @(0, 64), @(31, 64), @(32, 64), @(33, 64), @(-31, 64), @(-32, 64), @(-33, 64),
    @(511, 1024), @(512, 1024), @(513, 1024),
    @(-511, 1024), @(-512, 1024), @(-513, 1024), @(1, 1024), @(-1, 1024)
)
$rExpected = @($rTable | ForEach-Object {
    "R=$($_[0]) $($_[1]) $(Get-RoundHalfAway $_[0] $_[1])"
})
if (($rExpected -join "|") -cne
    "R=0 64 0|R=31 64 0|R=32 64 1|R=33 64 1|R=-31 64 0|R=-32 64 -1|R=-33 64 -1|R=511 1024 0|R=512 1024 1|R=513 1024 1|R=-511 1024 0|R=-512 1024 -1|R=-513 1024 -1|R=1 1024 0|R=-1 1024 0") {
    throw "tabela de r divergiu da spec"
}

# --- Conferencias do oraculo ----------------------------------------------

$initW = Get-W16
$initB = Get-B16
for ($y = 0; $y -lt 25; $y++) {
    $actual = Get-Param16Line $initW $initB $y
    if ($actual -cne "PARAM16=$($wInitialCanonical[$y])") {
        throw "tabela inicial divergiu: $actual"
    }
}

$W5 = Copy-W16 $initW
$B5 = Copy-B16 $initB
$run5 = Invoke-Training $W5 $B5 $ENT $ALV 4 5
if ($run5.Code -ne 0) { throw "treino canonico retornou $($run5.Code)" }
if (($run5.History -join " ") -cne ($historyCanonical -join " ")) {
    throw "historico canonico divergiu: $($run5.History -join ' ')"
}
for ($y = 0; $y -lt 25; $y++) {
    $actual = Get-Param16Line $W5 $B5 $y
    if ($actual -cne "PARAM16=$($wFinalCanonical[$y])") {
        throw "tabela final divergiu: $actual"
    }
}
$max5 = Get-MaxAbs $W5 $B5
if ($max5[0] -ne 11 -or $max5[1] -ne 6) { throw "MAXIMO16 final divergiu: $($max5 -join ' ')" }
$alt5 = Get-Alterados $W5 $B5
if ($alt5[0] -ne 91 -or $alt5[1] -ne 23) { throw "ALTERADOS final divergiu: $($alt5 -join ' ')" }
if ((Get-Avaliacao $W5 $B5 $ENT $ALV 4)[2] -cne "PRED=12 13 14 24") {
    throw "predicoes finais divergiram"
}

$Wg = Copy-W16 $initW
$Bg = Copy-B16 $initB
$grad = Get-Gradiente $Wg $Bg $ENT $ALV 4
if ($grad.Exatos -ne 125 -or $grad.Soma -ne -8960) {
    throw "gradiente divergiu: exatos=$($grad.Exatos) soma=$($grad.Soma)"
}
for ($y = 0; $y -lt 25; $y++) {
    if ((Get-Param16Line $Wg $Bg $y) -cne (Get-Param16Line $initW $initB $y)) {
        throw "gradiente nao restaurou a linha $y"
    }
}

$W1 = Copy-W16 $initW
$B1 = Copy-B16 $initB
$run1 = Invoke-Training $W1 $B1 $ENT $ALV 4 1
if ($run1.Code -ne 0 -or ($run1.History -join " ") -cne "3674036 428488") {
    throw "primeira epoca divergiu: $($run1.History -join ' ')"
}
$alt1 = Get-Alterados $W1 $B1
if (($alt1[0] + $alt1[1]) -ne 113) { throw "parametros alterados na epoca 1: $($alt1 -join ' ')" }

$Wn1 = Copy-W16 $initW
$Bn1 = Copy-B16 $initB
$runN1 = Invoke-Training $Wn1 $Bn1 ([int[]]@(9)) ([int[]]@(12)) 1 1
if (($runN1.History -join " ") -cne "1298270 31576") {
    throw "historico n=1 divergiu: $($runN1.History -join ' ')"
}
if ((Get-Acertos $Wn1 $Bn1 ([int[]]@(9)) ([int[]]@(12)) 1) -ne 1) {
    throw "acertos n=1 divergiu"
}

$repE = [int[]]@(9, 12, 13, 14, 9, 12, 13, 14, 9, 12, 13, 14, 9, 12, 13, 14)
$repA = [int[]]@(12, 13, 14, 24, 12, 13, 14, 24, 12, 13, 14, 24, 12, 13, 14, 24)
$Wn16 = Copy-W16 $initW
$Bn16 = Copy-B16 $initB
$runN16 = Invoke-Training $Wn16 $Bn16 $repE $repA 16 1
if (($runN16.History -join " ") -cne "14696144 123992") {
    throw "historico n=16 divergiu: $($runN16.History -join ' ')"
}
if ((Get-Acertos $Wn16 $Bn16 $repE $repA 16) -ne 16) {
    throw "acertos n=16 divergiu"
}

$Wo = Copy-W16 $initW
$Bo = Copy-B16 $initB
for ($d = 0; $d -lt 4; $d++) { $Wo[5][$d] = -48 }
$Bo[5] = 48
$runO = Invoke-Training $Wo $Bo ([int[]]@(12)) ([int[]]@(0)) 1 1
if ($runO.Code -ne 5) { throw "estouro retornou $($runO.Code); esperado 5" }
$overflowLine = Get-Param16Line $Wo $Bo 5
if ($overflowLine -cne "PARAM16=5 -45 -42 -40 -37 62") {
    throw "estado parcial do estouro divergiu: $overflowLine"
}

$W49 = Copy-W16 $initW
$B49 = Copy-B16 $initB
$W49[0][0] = 49
$line49 = Get-Param16Line $W49 $B49 0
if ($line49 -cne "PARAM16=0 49 -7 -2 3 -4") {
    throw "linha do cenario 49 divergiu: $line49"
}

# --- Fontes ----------------------------------------------------------------

$repoRoot = (Get-Location).Path
$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
$tokenizerFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TokenizerSourcePath))
$embeddingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $EmbeddingSourcePath))
$networkFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $NetworkSourcePath))
foreach ($path in @($sourceFull, $tokenizerFull, $embeddingFull, $networkFull)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Fragmento nao encontrado: $path" }
    Assert-AsciiLf $path
}

$treinoText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sourceFull))
$treinoCode = (($treinoText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
foreach ($forbidden in @("programa", "inicio", "inclua", "Matematica", "aleatorio", "tempo", "leia")) {
    if ($treinoCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "src/treino.por contem identificador proibido: $forbidden"
    }
}
foreach ($required in @(
    "TREINO_TAM_VOCAB = 25", "TREINO_DIM = 4", "TREINO_MAX_EXEMPLOS = 16",
    "TREINO_MAX_EPOCAS = 256", "TREINO_GRADE = 16", "TREINO_ESCALA_PERDA = 524288",
    "TREINO_LIMITE = 48", "TREINO_EPOCAS = 5", "TREINO_TAXA_NUM = 1",
    "TREINO_TAXA_DEN = 4", "TREINO_DIV_W = 1024", "TREINO_DIV_B = 64"
)) {
    if ($treinoText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "src/treino.por nao contem: $required"
    }
}

$treinoFragment = $treinoText.TrimEnd("`r", "`n")
$tokenizerFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($tokenizerFull)).TrimEnd("`r", "`n")
$embeddingFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($embeddingFull)).TrimEnd("`r", "`n")
$networkFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($networkFull)).TrimEnd("`r", "`n")

# --- Drivers ---------------------------------------------------------------

$setupCanonical = @'
inteiro w16[100]
inteiro b16[25]
treino_inicializar(w16, b16)
inteiro entradas[16]
inteiro alvos[16]
entradas[0] = 9
entradas[1] = 12
entradas[2] = 13
entradas[3] = 14
alvos[0] = 12
alvos[1] = 13
alvos[2] = 14
alvos[3] = 24
'@

$infoDriver = @'
inteiro w16[100]
inteiro b16[25]
treino_inicializar(w16, b16)
inteiro entradas[16]
inteiro alvos[16]
entradas[0] = 9
alvos[0] = 12
treino_imprimir_config()
treino_imprimir_validacao(entradas, alvos, 0, 5, w16, b16)
treino_imprimir_validacao(entradas, alvos, 17, 5, w16, b16)
treino_imprimir_validacao(entradas, alvos, 1, 0, w16, b16)
treino_imprimir_validacao(entradas, alvos, 1, 257, w16, b16)
entradas[0] = -1
treino_imprimir_validacao(entradas, alvos, 1, 5, w16, b16)
entradas[0] = 25
treino_imprimir_validacao(entradas, alvos, 1, 5, w16, b16)
treino_imprimir_param16(w16, b16, -1)
treino_imprimir_param16(w16, b16, 25)
escreva("R=", 0, " ", 64, " ", treino_div_arredondada(0, 64), "\n")
escreva("R=", 31, " ", 64, " ", treino_div_arredondada(31, 64), "\n")
escreva("R=", 32, " ", 64, " ", treino_div_arredondada(32, 64), "\n")
escreva("R=", 33, " ", 64, " ", treino_div_arredondada(33, 64), "\n")
escreva("R=", -31, " ", 64, " ", treino_div_arredondada(-31, 64), "\n")
escreva("R=", -32, " ", 64, " ", treino_div_arredondada(-32, 64), "\n")
escreva("R=", -33, " ", 64, " ", treino_div_arredondada(-33, 64), "\n")
escreva("R=", 511, " ", 1024, " ", treino_div_arredondada(511, 1024), "\n")
escreva("R=", 512, " ", 1024, " ", treino_div_arredondada(512, 1024), "\n")
escreva("R=", 513, " ", 1024, " ", treino_div_arredondada(513, 1024), "\n")
escreva("R=", -511, " ", 1024, " ", treino_div_arredondada(-511, 1024), "\n")
escreva("R=", -512, " ", 1024, " ", treino_div_arredondada(-512, 1024), "\n")
escreva("R=", -513, " ", 1024, " ", treino_div_arredondada(-513, 1024), "\n")
escreva("R=", 1, " ", 1024, " ", treino_div_arredondada(1, 1024), "\n")
escreva("R=", -1, " ", 1024, " ", treino_div_arredondada(-1, 1024), "\n")
'@

$perdaDriver = $setupCanonical + @'

treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
treino_imprimir_estado(w16, b16)
treino_imprimir_alterados(w16, b16)
'@

$gradDriver = $setupCanonical + @'

treino_imprimir_gradiente(w16, b16, entradas, alvos, 4)
treino_imprimir_estado(w16, b16)
w16[0] = 48
treino_imprimir_gradiente(w16, b16, entradas, alvos, 4)
w16[0] = -12
treino_imprimir_param16(w16, b16, 12)
'@

$epoca1Driver = $setupCanonical + @'

inteiro historico[2]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 1, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_historico(historico, 1)
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
treino_imprimir_param16(w16, b16, 9)
treino_imprimir_param16(w16, b16, 12)
treino_imprimir_param16(w16, b16, 13)
treino_imprimir_param16(w16, b16, 14)
treino_imprimir_alterados(w16, b16)
'@

$cincoDriver = $setupCanonical + @'

inteiro historico[6]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 5, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_historico(historico, 5)
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
inteiro copia_w[100]
inteiro copia_b[25]
inteiro i = 0
enquanto (i < 100)
{
    copia_w[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    copia_b[i] = b16[i]
    i = i + 1
}
inteiro historico6[2]
codigo = treino_executar(w16, b16, entradas, alvos, 4, 1, historico6)
logico fixo = verdadeiro
i = 0
enquanto (i < 100)
{
    se (w16[i] != copia_w[i])
    {
        fixo = falso
    }
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    se (b16[i] != copia_b[i])
    {
        fixo = falso
    }
    i = i + 1
}
se (fixo)
{
    escreva("PONTO_FIXO=OK\n")
}
senao
{
    escreva("PONTO_FIXO=FALHA\n")
}
escreva("CODIGO6=", codigo, "\n")
'@

$estadoFinalDriver = $setupCanonical + @'

inteiro historico[6]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 5, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
treino_imprimir_estado(w16, b16)
treino_imprimir_alterados(w16, b16)
'@

$determinismoDriver = $setupCanonical + @'

inteiro historico[6]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 5, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_historico(historico, 5)
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
treino_imprimir_estado(w16, b16)
'@

$errosDriver = $setupCanonical + @'

inteiro historico[6]
treino_imprimir_validacao(entradas, alvos, 0, 5, w16, b16)
se (treino_igual_a_inicial(w16, b16))
{
    escreva("INTACTO=OK\n")
}
senao
{
    escreva("INTACTO=FALHA\n")
}
treino_imprimir_validacao(entradas, alvos, 4, 0, w16, b16)
se (treino_igual_a_inicial(w16, b16))
{
    escreva("INTACTO=OK\n")
}
senao
{
    escreva("INTACTO=FALHA\n")
}
entradas[0] = -1
treino_imprimir_validacao(entradas, alvos, 4, 5, w16, b16)
se (treino_igual_a_inicial(w16, b16))
{
    escreva("INTACTO=OK\n")
}
senao
{
    escreva("INTACTO=FALHA\n")
}
entradas[0] = 9
alvos[0] = 25
treino_imprimir_validacao(entradas, alvos, 4, 5, w16, b16)
se (treino_igual_a_inicial(w16, b16))
{
    escreva("INTACTO=OK\n")
}
senao
{
    escreva("INTACTO=FALHA\n")
}
alvos[0] = 12
w16[0] = 49
treino_imprimir_validacao(entradas, alvos, 4, 5, w16, b16)
treino_imprimir_param16(w16, b16, 0)
w16[0] = -12
se (treino_igual_a_inicial(w16, b16))
{
    escreva("INTACTO=OK\n")
}
senao
{
    escreva("INTACTO=FALHA\n")
}
w16[20] = -48
w16[21] = -48
w16[22] = -48
w16[23] = -48
b16[5] = 48
entradas[0] = 12
alvos[0] = 0
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 1, 1, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_param16(w16, b16, 5)
'@

$limitesDriver = $setupCanonical + @'

treino_imprimir_validacao(entradas, alvos, 0, 1, w16, b16)
treino_imprimir_validacao(entradas, alvos, 17, 1, w16, b16)
treino_imprimir_validacao(entradas, alvos, 1, 0, w16, b16)
treino_imprimir_validacao(entradas, alvos, 1, 257, w16, b16)
entradas[0] = 9
alvos[0] = 12
inteiro historico[2]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 1, 1, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_historico(historico, 1)
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 1)
treino_inicializar(w16, b16)
inteiro i = 0
enquanto (i < 16)
{
    entradas[i] = 9
    alvos[i] = 12
    se (i % 4 == 1)
    {
        entradas[i] = 12
        alvos[i] = 13
    }
    se (i % 4 == 2)
    {
        entradas[i] = 13
        alvos[i] = 14
    }
    se (i % 4 == 3)
    {
        entradas[i] = 14
        alvos[i] = 24
    }
    i = i + 1
}
inteiro historico16[2]
codigo = treino_executar(w16, b16, entradas, alvos, 16, 1, historico16)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_historico(historico16, 1)
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 16)
'@

$reinitDriver = $setupCanonical + @'

w16[9 * 4 + 2] = 40
treino_imprimir_param16(w16, b16, 9)
treino_inicializar(w16, b16)
treino_imprimir_param16(w16, b16, 9)
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
'@

$compositionDriver = @'
tokenizar("se faca para ate pare")
real emb[100]
real pesos[100]
real vieses[25]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
inteiro w16[100]
inteiro b16[25]
treino_inicializar(w16, b16)
inteiro entradas[16]
inteiro alvos[16]
entradas[0] = 9
entradas[1] = 12
entradas[2] = 13
entradas[3] = 14
alvos[0] = 12
alvos[1] = 13
alvos[2] = 14
alvos[3] = 24
inteiro historico[6]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 5, historico)
escreva("CODIGO=", codigo, "\n")
treino_imprimir_avaliacao(w16, b16, entradas, alvos, 4)
treino_materializar(w16, b16, pesos, vieses)
escreva("ALVOS=12 13 14 24\n")
logico emb16_ok = verdadeiro
inteiro id = 0
enquanto (id < 25)
{
    inteiro d = 0
    enquanto (d < 4)
    {
        se (treino_emb16(id, d) / 16.0 != emb_obter(emb, id, d))
        {
            emb16_ok = falso
        }
        d = d + 1
    }
    id = id + 1
}
se (emb16_ok)
{
    escreva("EMB16=OK\n")
}
senao
{
    escreva("EMB16=FALHA\n")
}
escreva("ARGMAX_REDE=")
inteiro i = 0
enquanto (i < 4)
{
    se (i > 0)
    {
        escreva(" ")
    }
    escreva(rede_argmax(pesos, vieses, emb, entradas[i]))
    i = i + 1
}
escreva("\n")
escreva("ARGMAX_TREINO=")
i = 0
enquanto (i < 4)
{
    se (i > 0)
    {
        escreva(" ")
    }
    escreva(treino_argmax(w16, b16, entradas[i]))
    i = i + 1
}
escreva("\n")
logico compoe = verdadeiro
i = 0
enquanto (i < 4)
{
    se (rede_argmax(pesos, vieses, emb, entradas[i]) != alvos[i])
    {
        compoe = falso
    }
    se (treino_argmax(w16, b16, entradas[i]) != alvos[i])
    {
        compoe = falso
    }
    se (rede_argmax(pesos, vieses, emb, entradas[i]) != treino_argmax(w16, b16, entradas[i]))
    {
        compoe = falso
    }
    i = i + 1
}
se (compoe)
{
    escreva("COMPOE=OK\n")
}
senao
{
    escreva("COMPOE=FALHA\n")
}
'@

# --- Saidas esperadas ------------------------------------------------------

$configExpected = @(
    "INFO=TREINO 16 256 125 100",
    "TAXA=1/4",
    "GRADE=1/16",
    "EPOCAS=5",
    "ESCALA_PERDA=524288",
    "LIMITE_PARAM=48",
    "ORDEM=EXEMPLO"
)

$infoExpected = $configExpected + @(
    "ERRO=EXEMPLOS_INVALIDOS", "ERRO=EXEMPLOS_INVALIDOS",
    "ERRO=EPOCAS_INVALIDAS", "ERRO=EPOCAS_INVALIDAS",
    "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO",
    "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA"
) + $rExpected

$Wp = Copy-W16 $initW
$Bp = Copy-B16 $initB
$perdaExpected = (Get-Avaliacao $Wp $Bp $ENT $ALV 4) + (Get-StateLines $Wp $Bp) + (Get-AlteradosLines $Wp $Bp)

$gradExpected = @(
    "GRAD_EXATOS=125",
    "GRAD_TOTAL=125",
    "GRAD_SOMA=-8960"
) + (Get-StateLines $initW $initB) + @(
    "ERRO=PARAMETROS_INVALIDOS",
    (Get-Param16Line $initW $initB 12)
)

$epoca1Expected = @("CODIGO=0", (Get-HistoryLine $run1.History)) +
    (Get-Avaliacao $W1 $B1 $ENT $ALV 4) + @(
        (Get-Param16Line $W1 $B1 9),
        (Get-Param16Line $W1 $B1 12),
        (Get-Param16Line $W1 $B1 13),
        (Get-Param16Line $W1 $B1 14)
    ) + (Get-AlteradosLines $W1 $B1)

$cincoExpected = @("CODIGO=0", (Get-HistoryLine $run5.History)) +
    (Get-Avaliacao $W5 $B5 $ENT $ALV 4) + @("PONTO_FIXO=OK", "CODIGO6=0")

$estadoFinalExpected = @("CODIGO=0") + (Get-Avaliacao $W5 $B5 $ENT $ALV 4) + (Get-StateLines $W5 $B5) + (Get-AlteradosLines $W5 $B5)

$determinismoExpected = @("CODIGO=0", (Get-HistoryLine $run5.History)) +
    (Get-Avaliacao $W5 $B5 $ENT $ALV 4) + (Get-StateLines $W5 $B5)

$errosExpected = @(
    "ERRO=EXEMPLOS_INVALIDOS", "INTACTO=OK",
    "ERRO=EPOCAS_INVALIDAS", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "ERRO=PARAMETROS_INVALIDOS", $line49, "INTACTO=OK",
    "CODIGO=5", $overflowLine
)

$limitesExpected = @(
    "ERRO=EXEMPLOS_INVALIDOS", "ERRO=EXEMPLOS_INVALIDOS",
    "ERRO=EPOCAS_INVALIDAS", "ERRO=EPOCAS_INVALIDAS",
    "CODIGO=0", (Get-HistoryLine $runN1.History)
) + (Get-Avaliacao $Wn1 $Bn1 ([int[]]@(9)) ([int[]]@(12)) 1) + @(
    "CODIGO=0", (Get-HistoryLine $runN16.History)
) + (Get-Avaliacao $Wn16 $Bn16 $repE $repA 16)

$composicaoExpected = @(
    "IDS=9 12 13 14 24",
    "CODIGO=0",
    "PERDA=27804",
    "ACERTOS=4",
    "PRED=12 13 14 24",
    "ALVOS=12 13 14 24",
    "EMB16=OK",
    "ARGMAX_REDE=12 13 14 24",
    "ARGMAX_TREINO=12 13 14 24",
    "COMPOE=OK"
)

$Wr = Copy-W16 $initW
$Br = Copy-B16 $initB
$Wr[9][2] = 40
$reinitExpected = @(
    (Get-Param16Line $Wr $Br 9),
    (Get-Param16Line $initW $initB 9),
    "PERDA=3674036",
    "ACERTOS=0",
    "PRED=10 19 6 11"
)

# --- Casos -----------------------------------------------------------------

$cases = @(
    @{ Name = "trn_info"; Driver = $infoDriver; Expected = $infoExpected; Compose = "treino" },
    @{ Name = "trn_perda_inicial"; Driver = $perdaDriver; Expected = $perdaExpected; Compose = "treino" },
    @{ Name = "trn_gradiente"; Driver = $gradDriver; Expected = $gradExpected; Compose = "treino" },
    @{ Name = "trn_epoca_1"; Driver = $epoca1Driver; Expected = $epoca1Expected; Compose = "treino" },
    @{ Name = "trn_cinco_epocas"; Driver = $cincoDriver; Expected = $cincoExpected; Compose = "treino" },
    @{ Name = "trn_estado_final"; Driver = $estadoFinalDriver; Expected = $estadoFinalExpected; Compose = "treino" },
    @{ Name = "trn_erros"; Driver = $errosDriver; Expected = $errosExpected; Compose = "treino" },
    @{ Name = "trn_limites"; Driver = $limitesDriver; Expected = $limitesExpected; Compose = "treino" },
    @{ Name = "trn_determinismo_a"; Driver = $determinismoDriver; Expected = $determinismoExpected; Compose = "treino" },
    @{ Name = "trn_determinismo_b"; Driver = $determinismoDriver; Expected = $determinismoExpected; Compose = "treino" },
    @{ Name = "trn_composicao"; Driver = $compositionDriver; Expected = $composicaoExpected; Compose = "tokenizer+embeddings+rede+treino" },
    @{ Name = "trn_reinicializacao"; Driver = $reinitDriver; Expected = $reinitExpected; Compose = "treino" }
)

$expectedNames = @(
    "trn_cinco_epocas", "trn_composicao", "trn_determinismo_a", "trn_determinismo_b",
    "trn_epoca_1", "trn_erros", "trn_estado_final", "trn_gradiente", "trn_info",
    "trn_limites", "trn_perda_inicial", "trn_reinicializacao"
)
$names = @($cases | ForEach-Object { $_.Name })
if ($names.Count -ne $expectedNames.Count) {
    throw "Quantidade de casos: $($names.Count); esperado $($expectedNames.Count)"
}
if ((($names | Sort-Object) -join "|") -cne (($expectedNames | Sort-Object) -join "|")) {
    throw "Nomes de caso divergem da lista normativa"
}
if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
    throw "Nome de caso duplicado na tabela de casos"
}

$outFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
$tempFull = [IO.Path]::GetFullPath((Join-Path $repoRoot "temp"))
$tempPrefix = $tempFull.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outFull.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot deve ficar dentro de temp/: $outFull"
}

if (Test-Path -LiteralPath $outFull) {
    Remove-Item -LiteralPath $outFull -Recurse -Force
}
New-Item -ItemType Directory -Path $outFull -Force | Out-Null

foreach ($case in $cases) {
    $fragments = switch ($case.Compose) {
        "treino" { $treinoFragment }
        "tokenizer+embeddings+rede+treino" {
            $tokenizerFragment + "`n`n" + $embeddingFragment + "`n`n" + $networkFragment + "`n`n" + $treinoFragment
        }
        default { throw "Compose desconhecido: $($case.Compose)" }
    }

    $content = "programa`n{`n" +
        $fragments + "`n`n" +
        "    funcao inicio()`n" +
        "    {`n" +
        (Add-PortugolIndent $case.Driver) + "`n" +
        "    }`n" +
        "}`n"

    $expectedText = @($case.Expected) -join "`n"

    $porPath = Join-Path $outFull ($case.Name + ".por")
    $expectedPath = Join-Path $outFull ($case.Name + ".expected")

    [IO.File]::WriteAllText($porPath, $content, $utf8NoBom)
    [IO.File]::WriteAllText($expectedPath, $expectedText, $utf8NoBom)

    Assert-AsciiLf $porPath
    Assert-Utf8NoBom $expectedPath
    $expectedBytes = [IO.File]::ReadAllBytes($expectedPath)
    if ($expectedBytes.Length -eq 0) { throw "Expected vazio: $expectedPath" }
    if ($expectedBytes[$expectedBytes.Length - 1] -eq 0x0A) {
        throw "Arquivo .expected termina em LF: $expectedPath"
    }
    if ($expectedText.IndexOf("`r") -ge 0) { throw "CR em .expected: $expectedPath" }
    foreach ($line in @($case.Expected)) {
        if ($line -ne $line.Trim()) { throw "Espaco nas pontas em .expected: $expectedPath" }
        foreach ($b in [Text.Encoding]::ASCII.GetBytes($line)) {
            if ($b -lt 0x20 -or $b -gt 0x7E) { throw "Byte nao ASCII em .expected: $expectedPath" }
        }
    }
}

$generatedExpected = @(Get-ChildItem -Path $outFull -Filter "*.expected" -File)
$generatedPor = @(Get-ChildItem -Path $outFull -Filter "*.por" -File)
if ($generatedExpected.Count -ne 12 -or $generatedPor.Count -ne 12) {
    throw "Arquivos gerados: $($generatedPor.Count) .por e $($generatedExpected.Count) .expected; esperado 12/12"
}

Write-Host "Generated $($cases.Count) training cases in $OutputRoot"
