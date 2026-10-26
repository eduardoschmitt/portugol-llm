<#
.SYNOPSIS
    Gera os 14 casos .por e .expected da rede neural em temp/network-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/embeddings.por e src/rede.por (e, em net_composicao, tambem
    src/tokenizador.por) a um driver. Os valores esperados sao recalculados
    aqui em aritmetica inteira (q, p, r, N), sem [double], e conferidos contra
    as tabelas canonicas da spec. Tudo e gravado em UTF-8 sem BOM, LF.
#>

param(
    [string]$SourcePath = "src/rede.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$OutputRoot = "temp/network-tests"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$invariant = [Globalization.CultureInfo]::InvariantCulture

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

function Assert-AsciiLfFragment {
    param([string]$Path)
    Assert-Utf8NoBom $Path
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { throw "Fragmento vazio: $Path" }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { throw "CR encontrado em $Path" }
        if ($b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) {
            throw ("Byte nao ASCII 0x{0:X2} em {1}" -f $b, $Path)
        }
    }
    if ($bytes[$bytes.Length - 1] -ne 0x0A) {
        throw "Fragmento nao termina em LF: $Path"
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

# --- Oraculo inteiro (nunca [double]) --------------------------------------

function Format-N {
    param([long]$N)
    $sign = if ($N -lt 0) { "-" } else { "" }
    $a = [Math]::Abs($N)
    $whole = [long][Math]::Floor($a / 256)
    $rest = [long]($a % 256)
    if ($rest -eq 0) { return "$sign$whole.0" }
    $frac = ([long]$rest * 390625).ToString($invariant).PadLeft(8, '0').TrimEnd('0')
    return "$sign$whole.$frac"
}

function Get-QTable {
    $q = @{}
    for ($id = 0; $id -lt 25; $id++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = (($id * 7 + $d * 3) % 32) - 16 }
        $q[$id] = $row
    }
    return $q
}

function Get-PTable {
    $p = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = (($y * 7 + $d * 5) % 25) - 12 }
        $p[$y] = $row
    }
    return $p
}

function Get-RTable {
    $r = @{}
    for ($y = 0; $y -lt 25; $y++) { $r[$y] = (($y * 7) % 9) - 4 }
    return $r
}

function Get-N {
    param([hashtable]$P, [hashtable]$R, [hashtable]$Q, [int]$Id, [int]$Y)
    [long]$n = 16 * [long]$R[$Y]
    for ($d = 0; $d -lt 4; $d++) { $n += [long]$P[$Y][$d] * [long]$Q[$Id][$d] }
    return $n
}

function Get-Argmax {
    param([hashtable]$P, [hashtable]$R, [hashtable]$Q, [int]$Id)
    $best = 0
    $bestN = Get-N $P $R $Q $Id 0
    for ($y = 1; $y -lt 25; $y++) {
        $n = Get-N $P $R $Q $Id $y
        if ($n -gt $bestN) { $bestN = $n; $best = $y }
    }
    return $best
}

function Get-LogitsLine {
    param([hashtable]$P, [hashtable]$R, [hashtable]$Q, [int]$Id)
    $parts = @()
    for ($y = 0; $y -lt 25; $y++) { $parts += (Format-N (Get-N $P $R $Q $Id $y)) }
    return "LOGITS=$Id " + ($parts -join " ")
}

function Copy-PTable {
    param([hashtable]$P)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = $P[$y][$d] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-RTable {
    param([hashtable]$R)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $R[$y] }
    return $copy
}

# --- Tabelas canonicas da spec (protecao contra erro de transcricao) ------

$wCanonical = @(
    @("-0.75", "-0.4375", "-0.125", "0.1875"),
    @("-0.3125", "0.0", "0.3125", "0.625"),
    @("0.125", "0.4375", "0.75", "-0.5"),
    @("0.5625", "-0.6875", "-0.375", "-0.0625"),
    @("-0.5625", "-0.25", "0.0625", "0.375"),
    @("-0.125", "0.1875", "0.5", "-0.75"),
    @("0.3125", "0.625", "-0.625", "-0.3125"),
    @("0.75", "-0.5", "-0.1875", "0.125"),
    @("-0.375", "-0.0625", "0.25", "0.5625"),
    @("0.0625", "0.375", "0.6875", "-0.5625"),
    @("0.5", "-0.75", "-0.4375", "-0.125"),
    @("-0.625", "-0.3125", "0.0", "0.3125"),
    @("-0.1875", "0.125", "0.4375", "0.75"),
    @("0.25", "0.5625", "-0.6875", "-0.375"),
    @("0.6875", "-0.5625", "-0.25", "0.0625"),
    @("-0.4375", "-0.125", "0.1875", "0.5"),
    @("0.0", "0.3125", "0.625", "-0.625"),
    @("0.4375", "0.75", "-0.5", "-0.1875"),
    @("-0.6875", "-0.375", "-0.0625", "0.25"),
    @("-0.25", "0.0625", "0.375", "0.6875"),
    @("0.1875", "0.5", "-0.75", "-0.4375"),
    @("0.625", "-0.625", "-0.3125", "0.0"),
    @("-0.5", "-0.1875", "0.125", "0.4375"),
    @("-0.0625", "0.25", "0.5625", "-0.6875"),
    @("0.375", "0.6875", "-0.5625", "-0.25")
)

$bCanonical = @(
    "-0.25", "0.1875", "0.0625", "-0.0625", "-0.1875", "0.25", "0.125", "0.0",
    "-0.125", "-0.25", "0.1875", "0.0625", "-0.0625", "-0.1875", "0.25", "0.125",
    "0.0", "-0.125", "-0.25", "0.1875", "0.0625", "-0.0625", "-0.1875", "0.25", "0.125"
)

$argmaxCanonical = @(
    0, 11, 19, 19, 24, 11, 1, 19, 2, 10, 11, 19, 19, 6, 11, 11, 19, 23, 10, 11, 19, 19, 6, 0, 11
)
$maxNCanonical = @(
    218, 136, 158, 256, 439, 176, 108, 200, 397, 429, 146, 144, 242, 437, 186, 116, 186, 390, 442, 156, 130, 228, 437, 200, 126
)
$marginCanonical = @(
    12, 38, 10, 26, 2, 12, 2, 22, 6, 38, 36, 6, 30, 2, 4, 14, 18, 6, 50, 28, 2, 30, 4, 4, 26
)
$maxLogitCanonical = @(
    "0.8515625", "0.53125", "0.6171875", "1.0", "1.71484375", "0.6875", "0.421875", "0.78125",
    "1.55078125", "1.67578125", "0.5703125", "0.5625", "0.9453125", "1.70703125", "0.7265625",
    "0.453125", "0.7265625", "1.5234375", "1.7265625", "0.609375", "0.5078125", "0.890625",
    "1.70703125", "0.78125", "0.4921875"
)
$zeroCanonical = @("9,5", "16,4", "21,16")
$histogramCanonical = @{ 0 = 2; 1 = 1; 2 = 1; 6 = 2; 10 = 2; 11 = 7; 19 = 8; 23 = 1; 24 = 1 }

# --- Conferencias do oraculo ----------------------------------------------

$P = Get-PTable
$R = Get-RTable
$Q = Get-QTable

for ($y = 0; $y -lt 25; $y++) {
    for ($d = 0; $d -lt 4; $d++) {
        $actual = Format-N (16 * [long]$P[$y][$d])
        if ($actual -cne $wCanonical[$y][$d]) {
            throw "W[$y][$d] = $actual; tabela diz $($wCanonical[$y][$d])"
        }
    }
    $actualBias = Format-N (16 * [long]$R[$y])
    if ($actualBias -cne $bCanonical[$y]) {
        throw "b[$y] = $actualBias; tabela diz $($bCanonical[$y])"
    }
}

$rowKeys = @()
for ($y = 0; $y -lt 25; $y++) {
    $rowKeys += ((0..3 | ForEach-Object { $wCanonical[$y][$_] }) -join ",")
}
if (@($rowKeys | Sort-Object -Unique).Count -ne 25) {
    throw "As 25 linhas de W nao sao distintas"
}

$zeros = @()
$minN = [long]::MaxValue
$maxN = [long]::MinValue
$minPos = ""
$maxPos = ""
$allFormatted = @()
$histogram = @{}
for ($id = 0; $id -lt 25; $id++) {
    $best = 0
    $bestN = Get-N $P $R $Q $id 0
    $secondN = [long]::MinValue
    for ($y = 1; $y -lt 25; $y++) {
        $n = Get-N $P $R $Q $id $y
        if ($n -gt $bestN) { $secondN = $bestN; $bestN = $n; $best = $y }
        elseif ($n -gt $secondN) { $secondN = $n }
    }
    if ($best -ne $argmaxCanonical[$id]) {
        throw "argmax($id) = $best; tabela diz $($argmaxCanonical[$id])"
    }
    if ($bestN -ne $maxNCanonical[$id]) {
        throw "max N($id) = $bestN; tabela diz $($maxNCanonical[$id])"
    }
    $margin = $bestN - $secondN
    if ($margin -ne $marginCanonical[$id]) {
        throw "margem($id) = $margin; tabela diz $($marginCanonical[$id])"
    }
    $bestText = Format-N $bestN
    if ($bestText -cne $maxLogitCanonical[$id]) {
        throw "logit maximo($id) = $bestText; tabela diz $($maxLogitCanonical[$id])"
    }
    if (-not $histogram.ContainsKey($best)) { $histogram[$best] = 0 }
    $histogram[$best]++

    for ($y = 0; $y -lt 25; $y++) {
        $n = Get-N $P $R $Q $id $y
        if ($n -eq 0) { $zeros += "$id,$y" }
        if ($n -lt $minN) { $minN = $n; $minPos = "$id,$y" }
        if ($n -gt $maxN) { $maxN = $n; $maxPos = "$id,$y" }
        $text = Format-N $n
        if ($text -notmatch '^-?(0|[1-9][0-9]*)\.[0-9]{1,8}$') {
            throw "logit fora da gramatica de 8 casas: $text"
        }
        if ($text -eq "-0.0") { throw "logit formatado como -0.0" }
        $allFormatted += $text
    }
}

if (($zeros -join "|") -cne ($zeroCanonical -join "|")) {
    throw "zeros canonicos: $($zeros -join ","); tabela diz $($zeroCanonical -join ",")"
}
if ($minN -ne -318) { throw "menor N = $minN; esperado -318" }
if ($minPos -ne "4,0") { throw "posicao do menor N = $minPos; esperado 4,0" }
if ($maxN -ne 442) { throw "maior N = $maxN; esperado 442" }
if ($maxPos -ne "18,10") { throw "posicao do maior N = $maxPos; esperado 18,10" }
if ((Format-N $minN) -ne "-1.2421875") { throw "menor logit incorreto" }
if ((Format-N $maxN) -ne "1.7265625") { throw "maior logit incorreto" }
if ($allFormatted.Count -ne 625) { throw "logits formatados: $($allFormatted.Count); esperado 625" }
if ($histogram.Keys.Count -ne 9) { throw "classes de argmax: $($histogram.Keys.Count); esperado 9" }
foreach ($k in $histogramCanonical.Keys) {
    if (-not $histogram.ContainsKey($k) -or $histogram[$k] -ne $histogramCanonical[$k]) {
        throw "histograma da classe $k incorreto"
    }
}

# Formatador validado contra valores conhecidos antes de gerar casos.
$formatterChecks = @(
    @{ N = [long]1;     Text = "0.00390625" },
    @{ N = [long]256;   Text = "1.0" },
    @{ N = [long]0;     Text = "0.0" },
    @{ N = [long]-318;  Text = "-1.2421875" }
)
foreach ($check in $formatterChecks) {
    if ((Format-N $check.N) -cne $check.Text) {
        throw "formatador: $(Format-N $check.N) != $($check.Text)"
    }
}

# --- Fontes ----------------------------------------------------------------

$repoRoot = (Get-Location).Path
$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
$embeddingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $EmbeddingSourcePath))
$tokenizerFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TokenizerSourcePath))
foreach ($path in @($sourceFull, $embeddingFull, $tokenizerFull)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Fragmento nao encontrado: $path" }
    Assert-AsciiLfFragment $path
}

$redeText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sourceFull))
$embeddingText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($embeddingFull))
$tokenizerText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($tokenizerFull))

foreach ($fragment in @(
    @{ Name = "rede"; Text = $redeText },
    @{ Name = "embeddings"; Text = $embeddingText }
)) {
    if ($fragment.Text -match '(?m)^\s*programa\b') { throw "$($fragment.Name) declara 'programa'" }
    if ($fragment.Text -match '(?m)^\s*funcao\s+inicio\b') { throw "$($fragment.Name) declara 'inicio'" }
    if ($fragment.Text -match '(?m)^\s*inclua\b') { throw "$($fragment.Name) inclui biblioteca" }
}
foreach ($required in @(
    "REDE_TAM_VOCAB = 25", "REDE_ENTRADAS = 4", "REDE_SAIDAS = 25",
    "REDE_TOTAL = 100", "REDE_PARAMS = 125"
)) {
    if ($redeText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "src/rede.por nao contem: $required"
    }
}
foreach ($forbidden in @("aleatorio", "exp(", "softmax", "aleatoria")) {
    if ($redeText.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "src/rede.por contem identificador proibido: $forbidden"
    }
}

$redeFragment = $redeText.TrimEnd("`r", "`n")
$embeddingFragment = $embeddingText.TrimEnd("`r", "`n")
$tokenizerFragment = $tokenizerText.TrimEnd("`r", "`n")

# --- Drivers ---------------------------------------------------------------

$initAll = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
'@

$zeroAll = @'
inteiro i = 0
enquanto (i < 100)
{
    pesos[i] = 0.0
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    vieses[i] = 0.0
    i = i + 1
}
'@

$tieDriver = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
inteiro i = 0
enquanto (i < 100)
{
    pesos[i] = 0.0
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    vieses[i] = 0.0
    i = i + 1
}
rede_imprimir_argmax(pesos, vieses, emb, 7)
vieses[19] = 0.5
vieses[24] = 0.5
rede_imprimir_argmax(pesos, vieses, emb, 7)
inicializar_rede(pesos, vieses)
i = 0
enquanto (i < 100)
{
    pesos[i] = 0.0
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    vieses[i] = 0.0
    i = i + 1
}
inteiro d = 0
enquanto (d < 4)
{
    pesos[3 * 4 + d] = 0.5
    pesos[7 * 4 + d] = 0.5
    d = d + 1
}
rede_imprimir_argmax(pesos, vieses, emb, 7)
'@

$updateDriver = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
rede_imprimir_peso(pesos, 5, 2)
rede_imprimir_bias(vieses, 5)
rede_definir_peso(pesos, 5, 2, 1.7)
rede_definir_bias(vieses, 5, 0.0 - 2.25)
rede_imprimir_peso(pesos, 5, 2)
rede_imprimir_bias(vieses, 5)
rede_imprimir_peso(pesos, 5, 1)
rede_imprimir_peso(pesos, 6, 2)
rede_imprimir_logit(pesos, vieses, emb, 9, 6)
'@

$reinitDriver = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
rede_definir_peso(pesos, 5, 2, 1.7)
rede_definir_bias(vieses, 5, 0.0 - 2.25)
inicializar_rede(pesos, vieses)
rede_imprimir_peso(pesos, 5, 2)
rede_imprimir_bias(vieses, 5)
rede_imprimir_argmax(pesos, vieses, emb, 5)
'@

$errorDriver = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
rede_imprimir_logits(pesos, vieses, emb, -1)
rede_imprimir_argmax(pesos, vieses, emb, 25)
rede_imprimir_logit(pesos, vieses, emb, -1, 0)
rede_imprimir_logit(pesos, vieses, emb, -1, 25)
rede_imprimir_logit(pesos, vieses, emb, 0, -1)
rede_imprimir_logit(pesos, vieses, emb, 0, 25)
rede_imprimir_peso(pesos, 25, 0)
rede_imprimir_peso(pesos, 0, -1)
rede_imprimir_peso(pesos, 0, 4)
rede_imprimir_peso(pesos, -1, 4)
rede_imprimir_bias(vieses, -1)
rede_imprimir_bias(vieses, 25)
rede_imprimir_argmax(pesos, vieses, emb, 0)
'@

$determinismDriver = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
inteiro id = 0
enquanto (id < 25)
{
    rede_imprimir_logits(pesos, vieses, emb, id)
    id = id + 1
}
'@

$compositionDriver = @'
real pesos[100]
real vieses[25]
real emb[100]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
tokenizar("programa se")
rede_imprimir_argmax(pesos, vieses, emb, 1)
rede_imprimir_argmax(pesos, vieses, emb, 9)
rede_imprimir_info()
'@

# --- Saidas esperadas ------------------------------------------------------

$paramPairs = @(
    @{ Line = "PARAM=0 0";  Value = Format-N (16 * [long]$P[0][0]) }
    @{ Line = "PARAM=0 3";  Value = Format-N (16 * [long]$P[0][3]) }
    @{ Line = "PARAM=5 2";  Value = Format-N (16 * [long]$P[5][2]) }
    @{ Line = "PARAM=12 2"; Value = Format-N (16 * [long]$P[12][2]) }
    @{ Line = "PARAM=24 0"; Value = Format-N (16 * [long]$P[24][0]) }
    @{ Line = "PARAM=24 3"; Value = Format-N (16 * [long]$P[24][3]) }
    @{ Line = "BIAS=0";     Value = Format-N (16 * [long]$R[0]) }
    @{ Line = "BIAS=5";     Value = Format-N (16 * [long]$R[5]) }
    @{ Line = "BIAS=7";     Value = Format-N (16 * [long]$R[7]) }
    @{ Line = "BIAS=12";    Value = Format-N (16 * [long]$R[12]) }
    @{ Line = "BIAS=16";    Value = Format-N (16 * [long]$R[16]) }
    @{ Line = "BIAS=24";    Value = Format-N (16 * [long]$R[24]) }
)
$paramExpected = @($paramPairs | ForEach-Object { "$($_.Line) $($_.Value)" })

$pointPairs = @(
    @{ Id = 0;  Y = 0 }, @{ Id = 0;  Y = 10 }, @{ Id = 3; Y = 19 }, @{ Id = 4; Y = 24 },
    @{ Id = 9;  Y = 5 }, @{ Id = 9;  Y = 6 },  @{ Id = 16; Y = 4 }, @{ Id = 21; Y = 16 }
)
$pointExpected = @($pointPairs | ForEach-Object {
    "LOGIT=$($_.Id) $($_.Y) " + (Format-N (Get-N $P $R $Q $_.Id $_.Y))
})

$validatorExpected = @()
foreach ($pair in @(
    @{ Id = -1; Y = 0;  D = 0 }, @{ Id = 0; Y = -1; D = 0 }, @{ Id = 0; Y = 0; D = -1 },
    @{ Id = 24; Y = 24; D = 3 }, @{ Id = 25; Y = 25; D = 4 }
)) {
    $validatorExpected += "VALIDO=ID " + $(if ($pair.Id -ge 0 -and $pair.Id -lt 25) { 1 } else { 0 })
    $validatorExpected += "VALIDO=SAIDA " + $(if ($pair.Y -ge 0 -and $pair.Y -lt 25) { 1 } else { 0 })
    $validatorExpected += "VALIDO=DIM " + $(if ($pair.D -ge 0 -and $pair.D -lt 4) { 1 } else { 0 })
}

$errorExpected = @(
    "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO",
    "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA",
    "ERRO=DIMENSAO_INVALIDA", "ERRO=DIMENSAO_INVALIDA",
    "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA",
    "ARGMAX=0 $(Get-Argmax $P $R $Q 0)"
)

# Empates: simulacao explicita do estado, em inteiros.
$pZero = Copy-PTable $P
$rZero = Copy-RTable $R
for ($y = 0; $y -lt 25; $y++) {
    $rZero[$y] = 0
    for ($d = 0; $d -lt 4; $d++) { $pZero[$y][$d] = 0 }
}
$tie1 = Get-Argmax $pZero $rZero $Q 7
$rTie = Copy-RTable $rZero
$rTie[19] = 8
$rTie[24] = 8
$tie2 = Get-Argmax $pZero $rTie $Q 7
$pRow = Copy-PTable $pZero
for ($d = 0; $d -lt 4; $d++) { $pRow[3][$d] = 8; $pRow[7][$d] = 8 }
$tie3 = Get-Argmax $pRow $rZero $Q 7
$tieExpected = @("ARGMAX=7 $tie1", "ARGMAX=7 $tie2", "ARGMAX=7 $tie3")
if (($tieExpected -join "|") -cne "ARGMAX=7 0|ARGMAX=7 19|ARGMAX=7 3") {
    throw "simulacao de empate divergiu: $($tieExpected -join '|')"
}

$updateExpected = @(
    "PARAM=5 2 $(Format-N (16 * [long]$P[5][2]))",
    "BIAS=5 $(Format-N (16 * [long]$R[5]))",
    "PARAM=5 2 1.7",
    "BIAS=5 -2.25",
    "PARAM=5 1 $(Format-N (16 * [long]$P[5][1]))",
    "PARAM=6 2 $(Format-N (16 * [long]$P[6][2]))",
    "LOGIT=9 6 $(Format-N (Get-N $P $R $Q 9 6))"
)

$reinitExpected = @(
    "PARAM=5 2 $(Format-N (16 * [long]$P[5][2]))",
    "BIAS=5 $(Format-N (16 * [long]$R[5]))",
    "ARGMAX=5 $(Get-Argmax $P $R $Q 5)"
)

$determinismExpected = @(0..24 | ForEach-Object { Get-LogitsLine $P $R $Q $_ })

$compositionExpected = @(
    "IDS=1 9",
    "ARGMAX=1 $(Get-Argmax $P $R $Q 1)",
    "ARGMAX=9 $(Get-Argmax $P $R $Q 9)",
    "INFO=25 4 125"
)

$cases = @(
    @{
        Name     = "net_info"
        Driver   = @'
real pesos[100]
real vieses[25]
inicializar_rede(pesos, vieses)
rede_imprimir_info()
rede_imprimir_layout()
'@
        Expected = @("INFO=25 4 125", "LAYOUT=OK")
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_parametros"
        Driver   = @'
real pesos[100]
real vieses[25]
inicializar_rede(pesos, vieses)
rede_imprimir_peso(pesos, 0, 0)
rede_imprimir_peso(pesos, 0, 3)
rede_imprimir_peso(pesos, 5, 2)
rede_imprimir_peso(pesos, 12, 2)
rede_imprimir_peso(pesos, 24, 0)
rede_imprimir_peso(pesos, 24, 3)
rede_imprimir_bias(vieses, 0)
rede_imprimir_bias(vieses, 5)
rede_imprimir_bias(vieses, 7)
rede_imprimir_bias(vieses, 12)
rede_imprimir_bias(vieses, 16)
rede_imprimir_bias(vieses, 24)
'@
        Expected = $paramExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_logits_0"
        Driver   = $initAll + "`nrede_imprimir_logits(pesos, vieses, emb, 0)"
        Expected = @(Get-LogitsLine $P $R $Q 0)
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_logits_24"
        Driver   = $initAll + "`nrede_imprimir_logits(pesos, vieses, emb, 24)"
        Expected = @(Get-LogitsLine $P $R $Q 24)
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_logit_pontual"
        Driver   = $initAll + "`n" + (($pointPairs | ForEach-Object {
            "rede_imprimir_logit(pesos, vieses, emb, $($_.Id), $($_.Y))"
        }) -join "`n")
        Expected = $pointExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_argmax_todos"
        Driver   = $initAll + "`n" + ((0..24 | ForEach-Object {
            "rede_imprimir_argmax(pesos, vieses, emb, $_)"
        }) -join "`n")
        Expected = @(0..24 | ForEach-Object { "ARGMAX=$_ $($argmaxCanonical[$_])" })
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_validadores"
        Driver   = @'
rede_imprimir_validadores(-1, 0, 0)
rede_imprimir_validadores(0, -1, 0)
rede_imprimir_validadores(0, 0, -1)
rede_imprimir_validadores(24, 24, 3)
rede_imprimir_validadores(25, 25, 4)
'@
        Expected = $validatorExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_erros"
        Driver   = $errorDriver
        Expected = $errorExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_empate"
        Driver   = $tieDriver
        Expected = $tieExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_atualizacao"
        Driver   = $updateDriver
        Expected = $updateExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_reinicializacao"
        Driver   = $reinitDriver
        Expected = $reinitExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_determinismo_a"
        Driver   = $determinismDriver
        Expected = $determinismExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_determinismo_b"
        Driver   = $determinismDriver
        Expected = $determinismExpected
        Compose  = "embeddings+rede"
    }
    @{
        Name     = "net_composicao"
        Driver   = $compositionDriver
        Expected = $compositionExpected
        Compose  = "tokenizer+embeddings+rede"
    }
)

$expectedNames = @(
    "net_argmax_todos", "net_atualizacao", "net_composicao", "net_determinismo_a",
    "net_determinismo_b", "net_empate", "net_erros", "net_info", "net_logit_pontual",
    "net_logits_0", "net_logits_24", "net_parametros", "net_reinicializacao",
    "net_validadores"
)
$names = @($cases | ForEach-Object { $_.Name })
if ($names.Count -ne $expectedNames.Count) {
    throw "Quantidade de casos: $($names.Count); esperado $($expectedNames.Count)"
}
$sortedNames = (($names | Sort-Object) -join "|")
$sortedExpectedNames = (($expectedNames | Sort-Object) -join "|")
if ($sortedNames -cne $sortedExpectedNames) {
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
        "embeddings+rede" { $embeddingFragment + "`n`n" + $redeFragment }
        "tokenizer+embeddings+rede" { $tokenizerFragment + "`n`n" + $embeddingFragment + "`n`n" + $redeFragment }
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

    Assert-AsciiLfFragment $porPath
    Assert-Utf8NoBom $expectedPath
    $expectedBytes = [IO.File]::ReadAllBytes($expectedPath)
    if ($expectedBytes.Length -gt 0 -and $expectedBytes[$expectedBytes.Length - 1] -eq 0x0A) {
        throw "Arquivo .expected termina em LF: $expectedPath"
    }
    if ($expectedText.IndexOf("`r") -ge 0) { throw "CR em .expected: $expectedPath" }
    foreach ($token in @($expectedText -split "\s+")) {
        if ($token -ceq "-0.0") { throw "-0.0 em .expected: $expectedPath" }
    }
}

$generatedExpected = @(Get-ChildItem -Path $outFull -Filter "*.expected" -File)
$generatedPor = @(Get-ChildItem -Path $outFull -Filter "*.por" -File)
if ($generatedExpected.Count -ne 14 -or $generatedPor.Count -ne 14) {
    throw "Arquivos gerados: $($generatedPor.Count) .por e $($generatedExpected.Count) .expected; esperado 14/14"
}

Write-Host "Generated $($cases.Count) network cases in $OutputRoot"
