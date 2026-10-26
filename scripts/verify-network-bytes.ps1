# ---------------------------------------------------------------------------
# Verificacao do formato observavel e dos valores da camada de saida (M4).
# - Fonte ASCII puro, fragmento, constantes canonicas, sem biblioteca/aleatorio.
# - Conjunto de casos exatamente igual ao esperado (sem faltas nem extras).
# - Saida crua: form feed inicial, carga ASCII com LF, epilogo exato.
# - Oraculo independente em aritmetica inteira (q, p, r, N); nao le .expected
#   para decidir valores (apenas para a checagem V12).
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-network-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/network-tests",
    [string]$SourcePath = "src/rede.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat"
)

$ErrorActionPreference = "Stop"

$script:failures = 0
$script:checks = 0
$invariant = [Globalization.CultureInfo]::InvariantCulture
$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"
$epilogueBytes = [Text.Encoding]::ASCII.GetBytes($epilogue)

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

# --- Oraculo inteiro -------------------------------------------------------

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

$script:P = New-Object 'int[]' 100
$script:R = New-Object 'int[]' 25
$script:Q = New-Object 'int[]' 100
for ($y = 0; $y -lt 25; $y++) {
    for ($d = 0; $d -lt 4; $d++) {
        $script:P[$y * 4 + $d] = (($y * 7 + $d * 5) % 25) - 12
    }
    $script:R[$y] = (($y * 7) % 9) - 4
}
for ($id = 0; $id -lt 25; $id++) {
    for ($d = 0; $d -lt 4; $d++) {
        $script:Q[$id * 4 + $d] = (($id * 7 + $d * 3) % 32) - 16
    }
}

function Get-NState {
    param([int[]]$PState, [int[]]$RState, [int[]]$QState, [int]$Id, [int]$Y)
    [long]$n = 16 * [long]$RState[$Y]
    for ($d = 0; $d -lt 4; $d++) {
        $n += [long]$PState[$Y * 4 + $d] * [long]$QState[$Id * 4 + $d]
    }
    return $n
}

function Get-ArgmaxState {
    param([int[]]$PState, [int[]]$RState, [int[]]$QState, [int]$Id)
    $best = 0
    $bestN = Get-NState $PState $RState $QState $Id 0
    for ($y = 1; $y -lt 25; $y++) {
        $n = Get-NState $PState $RState $QState $Id $y
        if ($n -gt $bestN) { $bestN = $n; $best = $y }
    }
    return $best
}

function Get-LogitsLine {
    param([int[]]$PState, [int[]]$RState, [int[]]$QState, [int]$Id)
    $parts = @()
    for ($y = 0; $y -lt 25; $y++) { $parts += (Format-N (Get-NState $PState $RState $QState $Id $y)) }
    return "LOGITS=$Id " + ($parts -join " ")
}

# --- Tabelas canonicas da spec --------------------------------------------

$wFlat = @(
    "-0.75", "-0.4375", "-0.125", "0.1875",
    "-0.3125", "0.0", "0.3125", "0.625",
    "0.125", "0.4375", "0.75", "-0.5",
    "0.5625", "-0.6875", "-0.375", "-0.0625",
    "-0.5625", "-0.25", "0.0625", "0.375",
    "-0.125", "0.1875", "0.5", "-0.75",
    "0.3125", "0.625", "-0.625", "-0.3125",
    "0.75", "-0.5", "-0.1875", "0.125",
    "-0.375", "-0.0625", "0.25", "0.5625",
    "0.0625", "0.375", "0.6875", "-0.5625",
    "0.5", "-0.75", "-0.4375", "-0.125",
    "-0.625", "-0.3125", "0.0", "0.3125",
    "-0.1875", "0.125", "0.4375", "0.75",
    "0.25", "0.5625", "-0.6875", "-0.375",
    "0.6875", "-0.5625", "-0.25", "0.0625",
    "-0.4375", "-0.125", "0.1875", "0.5",
    "0.0", "0.3125", "0.625", "-0.625",
    "0.4375", "0.75", "-0.5", "-0.1875",
    "-0.6875", "-0.375", "-0.0625", "0.25",
    "-0.25", "0.0625", "0.375", "0.6875",
    "0.1875", "0.5", "-0.75", "-0.4375",
    "0.625", "-0.625", "-0.3125", "0.0",
    "-0.5", "-0.1875", "0.125", "0.4375",
    "-0.0625", "0.25", "0.5625", "-0.6875",
    "0.375", "0.6875", "-0.5625", "-0.25"
)

$bFlat = @(
    "-0.25", "0.1875", "0.0625", "-0.0625", "-0.1875", "0.25", "0.125", "0.0",
    "-0.125", "-0.25", "0.1875", "0.0625", "-0.0625", "-0.1875", "0.25", "0.125",
    "0.0", "-0.125", "-0.25", "0.1875", "0.0625", "-0.0625", "-0.1875", "0.25", "0.125"
)

$argmaxFlat = @(
    0, 11, 19, 19, 24, 11, 1, 19, 2, 10, 11, 19, 19, 6, 11, 11, 19, 23, 10, 11, 19, 19, 6, 0, 11
)
$maxNFlat = @(
    218, 136, 158, 256, 439, 176, 108, 200, 397, 429, 146, 144, 242, 437, 186, 116, 186, 390, 442, 156, 130, 228, 437, 200, 126
)
$marginFlat = @(
    12, 38, 10, 26, 2, 12, 2, 22, 6, 38, 36, 6, 30, 2, 4, 14, 18, 6, 50, 28, 2, 30, 4, 4, 26
)
$maxLogitFlat = @(
    "0.8515625", "0.53125", "0.6171875", "1.0", "1.71484375", "0.6875", "0.421875", "0.78125",
    "1.55078125", "1.67578125", "0.5703125", "0.5625", "0.9453125", "1.70703125", "0.7265625",
    "0.453125", "0.7265625", "1.5234375", "1.7265625", "0.609375", "0.5078125", "0.890625",
    "1.70703125", "0.78125", "0.4921875"
)
$histogramExpected = @{ 0 = 2; 1 = 1; 2 = 1; 6 = 2; 10 = 2; 11 = 7; 19 = 8; 23 = 1; 24 = 1 }

$v7Errors = @()
for ($y = 0; $y -lt 25; $y++) {
    for ($d = 0; $d -lt 4; $d++) {
        $index = $y * 4 + $d
        $actual = Format-N (16 * [long]$script:P[$index])
        if ($actual -cne $wFlat[$index]) {
            $v7Errors += "W[$y][$d] = $actual; tabela diz $($wFlat[$index])"
        }
    }
    $actualBias = Format-N (16 * [long]$script:R[$y])
    if ($actualBias -cne $bFlat[$y]) {
        $v7Errors += "b[$y] = $actualBias; tabela diz $($bFlat[$y])"
    }
}

$rowKeys = @()
for ($y = 0; $y -lt 25; $y++) {
    $rowKeys += ((0..3 | ForEach-Object { $wFlat[$y * 4 + $_] }) -join ",")
}
if (@($rowKeys | Sort-Object -Unique).Count -ne 25) {
    $v7Errors += "as 25 linhas de W nao sao distintas"
}

$zeros = @()
$minN = [long]::MaxValue
$maxN = [long]::MinValue
$minPos = ""
$maxPos = ""
$histogram = @{}
for ($id = 0; $id -lt 25; $id++) {
    $best = 0
    $bestN = Get-NState $script:P $script:R $script:Q $id 0
    $secondN = [long]::MinValue
    for ($y = 1; $y -lt 25; $y++) {
        $n = Get-NState $script:P $script:R $script:Q $id $y
        if ($n -gt $bestN) { $secondN = $bestN; $bestN = $n; $best = $y }
        elseif ($n -gt $secondN) { $secondN = $n }
    }
    if ($best -ne $argmaxFlat[$id]) { $v7Errors += "argmax($id) = $best; tabela diz $($argmaxFlat[$id])" }
    if ($bestN -ne $maxNFlat[$id]) { $v7Errors += "max N($id) = $bestN; tabela diz $($maxNFlat[$id])" }
    if (($bestN - $secondN) -ne $marginFlat[$id]) { $v7Errors += "margem($id) incorreta" }
    if ((Format-N $bestN) -cne $maxLogitFlat[$id]) { $v7Errors += "logit maximo($id) incorreto" }
    if (-not $histogram.ContainsKey($best)) { $histogram[$best] = 0 }
    $histogram[$best]++

    for ($y = 0; $y -lt 25; $y++) {
        $n = Get-NState $script:P $script:R $script:Q $id $y
        if ($n -eq 0) { $zeros += "$id,$y" }
        if ($n -lt $minN) { $minN = $n; $minPos = "$id,$y" }
        if ($n -gt $maxN) { $maxN = $n; $maxPos = "$id,$y" }
        $text = Format-N $n
        if ($text -notmatch '^-?(0|[1-9][0-9]*)\.[0-9]{1,8}$') { $v7Errors += "logit fora da gramatica: $text" }
        if ($text -eq "-0.0") { $v7Errors += "logit -0.0 em ($id,$y)" }
    }
}
if (($zeros -join "|") -cne "9,5|16,4|21,16") { $v7Errors += "zeros canonicos: $($zeros -join ',')" }
if ($minN -ne -318 -or $minPos -ne "4,0") { $v7Errors += "menor logit/posicao incorretos: $minN em $minPos" }
if ($maxN -ne 442 -or $maxPos -ne "18,10") { $v7Errors += "maior logit/posicao incorretos: $maxN em $maxPos" }
if ($histogram.Keys.Count -ne 9) { $v7Errors += "classes de argmax: $($histogram.Keys.Count)" }
foreach ($k in $histogramExpected.Keys) {
    if (-not $histogram.ContainsKey($k) -or $histogram[$k] -ne $histogramExpected[$k]) {
        $v7Errors += "histograma da classe $k incorreto"
    }
}

# Formatador validado contra valores conhecidos.
foreach ($pair in @(
    @{ N = [long]1; Text = "0.00390625" },
    @{ N = [long]256; Text = "1.0" },
    @{ N = [long]0; Text = "0.0" },
    @{ N = [long]-318; Text = "-1.2421875" }
)) {
    if ((Format-N $pair.N) -cne $pair.Text) { $v7Errors += "formatador: $(Format-N $pair.N) != $($pair.Text)" }
}

# --- Saidas esperadas por caso (independentes dos .expected) ---------------

$expected = @{}
$expected["net_info"] = @("INFO=25 4 125", "LAYOUT=OK")

$paramLines = @()
$paramSpecs = @(
    @{ Kind = "P"; Y = 0;  D = 0 }, @{ Kind = "P"; Y = 0;  D = 3 }, @{ Kind = "P"; Y = 5; D = 2 },
    @{ Kind = "P"; Y = 12; D = 2 }, @{ Kind = "P"; Y = 24; D = 0 }, @{ Kind = "P"; Y = 24; D = 3 },
    @{ Kind = "B"; Y = 0 }, @{ Kind = "B"; Y = 5 }, @{ Kind = "B"; Y = 7 },
    @{ Kind = "B"; Y = 12 }, @{ Kind = "B"; Y = 16 }, @{ Kind = "B"; Y = 24 }
)
foreach ($spec in $paramSpecs) {
    if ($spec.Kind -eq "P") {
        $paramLines += "PARAM=$($spec.Y) $($spec.D) $(Format-N (16 * [long]$script:P[$spec.Y * 4 + $spec.D]))"
    } else {
        $paramLines += "BIAS=$($spec.Y) $(Format-N (16 * [long]$script:R[$spec.Y]))"
    }
}
$expected["net_parametros"] = $paramLines
$expected["net_logits_0"] = @(Get-LogitsLine $script:P $script:R $script:Q 0)
$expected["net_logits_24"] = @(Get-LogitsLine $script:P $script:R $script:Q 24)

$pointSpecs = @(
    @{ Id = 0; Y = 0 }, @{ Id = 0; Y = 10 }, @{ Id = 3; Y = 19 }, @{ Id = 4; Y = 24 },
    @{ Id = 9; Y = 5 }, @{ Id = 9; Y = 6 }, @{ Id = 16; Y = 4 }, @{ Id = 21; Y = 16 }
)
$expected["net_logit_pontual"] = @($pointSpecs | ForEach-Object {
    "LOGIT=$($_.Id) $($_.Y) $(Format-N (Get-NState $script:P $script:R $script:Q $_.Id $_.Y))"
})
$expected["net_argmax_todos"] = @(0..24 | ForEach-Object {
    "ARGMAX=$_ $(Get-ArgmaxState $script:P $script:R $script:Q $_)"
})
$expected["net_validadores"] = @(
    "VALIDO=ID 0", "VALIDO=SAIDA 1", "VALIDO=DIM 1",
    "VALIDO=ID 1", "VALIDO=SAIDA 0", "VALIDO=DIM 1",
    "VALIDO=ID 1", "VALIDO=SAIDA 1", "VALIDO=DIM 0",
    "VALIDO=ID 1", "VALIDO=SAIDA 1", "VALIDO=DIM 1",
    "VALIDO=ID 0", "VALIDO=SAIDA 0", "VALIDO=DIM 0"
)
$expected["net_erros"] = @(
    "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO",
    "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA",
    "ERRO=DIMENSAO_INVALIDA", "ERRO=DIMENSAO_INVALIDA",
    "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA",
    "ARGMAX=0 $(Get-ArgmaxState $script:P $script:R $script:Q 0)"
)

$pZero = New-Object 'int[]' 100
$rZero = New-Object 'int[]' 25
$arg1 = Get-ArgmaxState $pZero $rZero $script:Q 7
$rTie = $rZero.Clone()
$rTie[19] = 8
$rTie[24] = 8
$arg2 = Get-ArgmaxState $pZero $rTie $script:Q 7
$pRow = $pZero.Clone()
for ($d = 0; $d -lt 4; $d++) { $pRow[3 * 4 + $d] = 8; $pRow[7 * 4 + $d] = 8 }
$arg3 = Get-ArgmaxState $pRow $rZero $script:Q 7
$expected["net_empate"] = @("ARGMAX=7 $arg1", "ARGMAX=7 $arg2", "ARGMAX=7 $arg3")

$expected["net_atualizacao"] = @(
    "PARAM=5 2 $(Format-N (16 * [long]$script:P[5 * 4 + 2]))",
    "BIAS=5 $(Format-N (16 * [long]$script:R[5]))",
    "PARAM=5 2 1.7",
    "BIAS=5 -2.25",
    "PARAM=5 1 $(Format-N (16 * [long]$script:P[5 * 4 + 1]))",
    "PARAM=6 2 $(Format-N (16 * [long]$script:P[6 * 4 + 2]))",
    "LOGIT=9 6 $(Format-N (Get-NState $script:P $script:R $script:Q 9 6))"
)
$expected["net_reinicializacao"] = @(
    "PARAM=5 2 $(Format-N (16 * [long]$script:P[5 * 4 + 2]))",
    "BIAS=5 $(Format-N (16 * [long]$script:R[5]))",
    "ARGMAX=5 $(Get-ArgmaxState $script:P $script:R $script:Q 5)"
)
$expected["net_determinismo_a"] = @(0..24 | ForEach-Object { Get-LogitsLine $script:P $script:R $script:Q $_ })
$expected["net_determinismo_b"] = @(0..24 | ForEach-Object { Get-LogitsLine $script:P $script:R $script:Q $_ })
$expected["net_composicao"] = @(
    "IDS=1 9",
    "ARGMAX=1 $(Get-ArgmaxState $script:P $script:R $script:Q 1)",
    "ARGMAX=9 $(Get-ArgmaxState $script:P $script:R $script:Q 9)",
    "INFO=25 4 125"
)

$expectedCases = @(
    "net_argmax_todos", "net_atualizacao", "net_composicao", "net_determinismo_a",
    "net_determinismo_b", "net_empate", "net_erros", "net_info", "net_logit_pontual",
    "net_logits_0", "net_logits_24", "net_parametros", "net_reinicializacao",
    "net_validadores"
)

# --- Fonte ----------------------------------------------------------------

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { Fail "fragmento nao encontrado: $SourcePath" }
if (-not (Test-Path -LiteralPath $EmbeddingSourcePath -PathType Leaf)) { Fail "fragmento ausente: $EmbeddingSourcePath" }
if (-not (Test-Path -LiteralPath $TokenizerSourcePath -PathType Leaf)) { Fail "fragmento ausente: $TokenizerSourcePath" }

$v1Errors = @()
$sourceBytes = [IO.File]::ReadAllBytes($SourcePath)
if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) {
    $v1Errors += "BOM encontrado em $SourcePath"
}
foreach ($b in $sourceBytes) {
    if ($b -eq 0x09 -or $b -eq 0x0A -or $b -eq 0x0D) {
        if ($b -eq 0x0D) { $v1Errors += "CR encontrado em $SourcePath" }
        continue
    }
    if ($b -lt 0x20 -or $b -gt 0x7E) {
        $v1Errors += ("byte nao ASCII 0x{0:X2} em {1}" -f $b, $SourcePath)
        break
    }
}
if ($sourceBytes.Length -eq 0 -or $sourceBytes[$sourceBytes.Length - 1] -ne 0x0A) {
    $v1Errors += "a fonte nao termina em LF"
}
$sourceText = [Text.Encoding]::ASCII.GetString($sourceBytes)
if ($sourceText -match '(?m)^\s*programa\b') { $v1Errors += "o fragmento declara 'programa'" }
if ($sourceText -match '(?m)^\s*funcao\s+inicio\b') { $v1Errors += "o fragmento declara 'inicio'" }
if ($sourceText -match '(?m)^\s*inclua\b') { $v1Errors += "o fragmento inclui biblioteca" }
if ($sourceText -match 'aleatorio') { $v1Errors += "o fragmento usa aleatoriedade" }
foreach ($required in @(
    "REDE_TAM_VOCAB = 25", "REDE_ENTRADAS = 4", "REDE_SAIDAS = 25",
    "REDE_TOTAL = 100", "REDE_PARAMS = 125"
)) {
    if ($sourceText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        $v1Errors += "fragmento nao contem: $required"
    }
}
foreach ($forbidden in @("exp(", "softmax")) {
    if ($sourceText.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $v1Errors += "fragmento contem identificador proibido: $forbidden"
    }
}
Write-Check "V1 fonte: ASCII, fragmento, constantes, sem biblioteca/aleatorio" $v1Errors
Write-Check "V7 oraculo: W, b, argmax, margens, zeros, faixa e histograma" $v7Errors

if (-not (Test-Path -LiteralPath $InterpreterPath)) { Fail "interpretador nao encontrado: $InterpreterPath" }
if (-not (Test-Path -Path $GeneratedRoot)) { Fail "diretorio de casos nao encontrado: $GeneratedRoot" }

$expectedFiles = @(Get-ChildItem -Path $GeneratedRoot -Filter "*.expected" -File | Sort-Object Name)
$actualNames = @($expectedFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
$sortedExpected = @($expectedCases | Sort-Object)
$sortedActual = @($actualNames | Sort-Object)
$v2Errors = @()
if (($sortedActual -join "|") -cne ($sortedExpected -join "|")) {
    $v2Errors += "conjunto de casos diverge.`n  Esperado: " + ($sortedExpected -join ", ") + "`n  Obtido:   " + ($sortedActual -join ", ")
}
if ($expectedFiles.Count -ne 14) { $v2Errors += "arquivos .expected: $($expectedFiles.Count); esperado 14" }
Write-Check "V2 conjunto exato de 14 casos" $v2Errors
if ($v2Errors.Count -gt 0) { exit 1 }

Write-Host "=== Verificacao de bytes e valores da rede M4 ==="
Write-Host "Fonte:         $SourcePath"
Write-Host "Casos:         $GeneratedRoot"
Write-Host "Interpretador: $InterpreterPath"
Write-Host "Casos esperados: $($expectedCases.Count)"

# --- Execucao e validacao --------------------------------------------------

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

function Assert-LineGrammar {
    param([string]$Line, [string[]]$Errors)
    $number = '-?(0|[1-9][0-9]*)\.[0-9]{1,8}'
    $eq = $Line.IndexOf("=")
    if ($eq -lt 1) { $Errors += "linha sem '=': [$Line]"; return }
    $tag = $Line.Substring(0, $eq)
    $rest = $Line.Substring($eq + 1)
    $parts = @($rest -split " ")
    switch ($tag) {
        "INFO" {
            if ($Line -cne "INFO=25 4 125") { $Errors += "INFO invalido: [$Line]" }
        }
        "LAYOUT" {
            if ($Line -notmatch '^LAYOUT=(OK|ERRO)$') { $Errors += "LAYOUT invalido: [$Line]" }
        }
        "LOGITS" {
            if ($parts.Count -ne 26) { $Errors += "LOGITS com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^(0|[1-9][0-9]*)$') { $Errors += "ID invalido em [$Line]" }
            foreach ($v in $parts[1..25]) {
                if ($v -notmatch "^$number$") { $Errors += "numero fora da gramatica em [$Line]: $v" }
                elseif ($v -eq "-0.0") { $Errors += "-0.0 em [$Line]" }
            }
        }
        "LOGIT" {
            if ($parts.Count -ne 3) { $Errors += "LOGIT com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or $parts[1] -notmatch '^(0|[1-9][0-9]*)$') { $Errors += "indices invalidos em [$Line]" }
            if ($parts[2] -notmatch "^$number$") { $Errors += "numero fora da gramatica em [$Line]: $($parts[2])" }
            elseif ($parts[2] -eq "-0.0") { $Errors += "-0.0 em [$Line]" }
        }
        "ARGMAX" {
            if ($parts.Count -ne 2) { $Errors += "ARGMAX com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or $parts[1] -notmatch '^(0|[1-9][0-9]*)$') { $Errors += "indices invalidos em [$Line]" }
        }
        "PARAM" {
            if ($parts.Count -ne 3) { $Errors += "PARAM com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or $parts[1] -notmatch '^(0|[1-9][0-9]*)$') { $Errors += "indices invalidos em [$Line]" }
            if ($parts[2] -notmatch "^$number$") { $Errors += "numero fora da gramatica em [$Line]: $($parts[2])" }
            elseif ($parts[2] -eq "-0.0") { $Errors += "-0.0 em [$Line]" }
        }
        "BIAS" {
            if ($parts.Count -ne 2) { $Errors += "BIAS com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^(0|[1-9][0-9]*)$') { $Errors += "indice invalido em [$Line]" }
            if ($parts[1] -notmatch "^$number$") { $Errors += "numero fora da gramatica em [$Line]: $($parts[1])" }
            elseif ($parts[1] -eq "-0.0") { $Errors += "-0.0 em [$Line]" }
        }
        "VALIDO" {
            if ($Line -notmatch '^VALIDO=(ID|SAIDA|DIM) [01]$') { $Errors += "VALIDO invalido: [$Line]" }
        }
        "ERRO" {
            if ($Line -notmatch '^ERRO=(ID_INVALIDO|SAIDA_INVALIDA|DIMENSAO_INVALIDA)$') { $Errors += "ERRO invalido: [$Line]" }
        }
        default {
            $Errors += "linha fora do contrato: [$Line]"
        }
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
        Assert-LineGrammar $payloadLines[$i] $errors
    }

    # V12: o .expected gerado deve ser byte-identico a saida do oraculo.
    $expectedPath = Join-Path $GeneratedRoot ($Name + ".expected")
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        $errors += "arquivo .expected ausente: $expectedPath"
    } else {
        $expectedText = [IO.File]::ReadAllText($expectedPath)
        $oracleText = $expectedLines -join "`n"
        if ($expectedText -cne $oracleText) {
            $errors += "V12: .expected difere do oraculo"
        }
        $expectedBytes = [IO.File]::ReadAllBytes($expectedPath)
        if ($expectedBytes.Length -gt 0 -and $expectedBytes[$expectedBytes.Length - 1] -eq 0x0A) {
            $errors += "V12: .expected termina em LF"
        }
    }

    return [pscustomobject]@{ Errors = $errors; Lines = $payloadLines }
}

$runs = @{}
foreach ($name in $expectedCases) {
    $porPath = Join-Path $GeneratedRoot "$name.por"
    if (-not (Test-Path -LiteralPath $porPath)) {
        Write-Check $name @("arquivo ausente: $porPath")
        continue
    }
    $run = Invoke-CaseRaw $porPath
    $check = Test-RawCase $name $run.Bytes $run.Errors
    $runs[$name] = $run
    Write-Check $name $check.Errors
}

# V8: empates explicitos.
$v8Errors = @()
if ($runs.ContainsKey("net_empate")) {
    $check = Test-RawCase "net_empate" $runs["net_empate"].Bytes $runs["net_empate"].Errors
    if (($check.Lines -join "|") -cne "ARGMAX=7 0|ARGMAX=7 19|ARGMAX=7 3") {
        $v8Errors += "empates: $($check.Lines -join '|')"
    }
} else {
    $v8Errors += "net_empate nao executado"
}
Write-Check "V8 net_empate: 0, 19, 3" $v8Errors

# V9: sequencia exata de erros e estado intacto.
$v9Errors = @()
if ($runs.ContainsKey("net_erros")) {
    $check = Test-RawCase "net_erros" $runs["net_erros"].Bytes $runs["net_erros"].Errors
    if (($check.Lines -join "|") -cne ($expected["net_erros"] -join "|")) {
        $v9Errors += "sequencia de erros difere"
    }
    if ($check.Lines.Count -eq 0 -or $check.Lines[$check.Lines.Count - 1] -cne "ARGMAX=0 0") {
        $v9Errors += "ARGMAX=0 0 ausente no fim de net_erros"
    }
} else {
    $v9Errors += "net_erros nao executado"
}
Write-Check "V9 net_erros: 12 erros + ARGMAX=0 0" $v9Errors

# V10: composicao tokenizador + embeddings + rede.
$v10Errors = @()
if ($runs.ContainsKey("net_composicao")) {
    $check = Test-RawCase "net_composicao" $runs["net_composicao"].Bytes $runs["net_composicao"].Errors
    $text = $check.Lines -join "|"
    if ($check.Lines.Count -lt 1 -or $check.Lines[0] -cne "IDS=1 9") { $v10Errors += "IDS=1 9 ausente" }
    if ($text -notmatch 'ARGMAX=1 11') { $v10Errors += "ARGMAX=1 11 ausente" }
    if ($text -notmatch 'ARGMAX=9 10') { $v10Errors += "ARGMAX=9 10 ausente" }
} else {
    $v10Errors += "net_composicao nao executado"
}
Write-Check "V10 composicao: IDS=1 9 e dois argmax" $v10Errors

# V11: determinismo A/B em duas execucoes cada.
$v11Errors = @()
foreach ($name in @("net_determinismo_a", "net_determinismo_b")) {
    if (-not $runs.ContainsKey($name)) { $v11Errors += "$name nao executado"; continue }
    $second = Invoke-CaseRaw (Join-Path $GeneratedRoot "$name.por")
    $firstBytes = $runs[$name].Bytes
    if (-not [Convert]::ToBase64String($firstBytes).Equals([Convert]::ToBase64String($second.Bytes), [StringComparison]::Ordinal)) {
        $v11Errors += "${name}: execucoes 1 e 2 diferem"
    }
}
if ($runs.ContainsKey("net_determinismo_a") -and $runs.ContainsKey("net_determinismo_b")) {
    if (-not [Convert]::ToBase64String($runs["net_determinismo_a"].Bytes).Equals([Convert]::ToBase64String($runs["net_determinismo_b"].Bytes), [StringComparison]::Ordinal)) {
        $v11Errors += "processos A e B diferem"
    }
}
Write-Check "V11 determinismo A/B (duas execucoes cada)" $v11Errors

# V12: todos os .expected devem ser byte-identicos ao texto do oraculo.
$v12Errors = @()
foreach ($name in $expectedCases) {
    $expectedPath = Join-Path $GeneratedRoot ($name + ".expected")
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        $v12Errors += "${name}: .expected ausente"
        continue
    }
    $oracleText = @($expected[$name]) -join "`n"
    $expectedText = [IO.File]::ReadAllText($expectedPath)
    if ($expectedText -cne $oracleText) {
        $v12Errors += "${name}: .expected difere do oraculo"
    }
}
Write-Check "V12 .expected byte-identico ao oraculo" $v12Errors

Write-Host ""
Write-Host "Total: $script:checks verificacoes, $script:failures falha(s)"
if ($script:failures -gt 0) { exit 1 }
Write-Host "Formato e valores conforme."
exit 0
