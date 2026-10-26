# ---------------------------------------------------------------------------
# Verificacao do formato observavel e dos valores do treinamento (M5).
# - Fonte ASCII puro, fragmento, constantes canonicas, sem biblioteca/aleatorio.
# - Conjunto de casos exatamente igual ao esperado (sem faltas nem extras).
# - Saida crua: form feed inicial, carga ASCII com LF, epilogo exato.
# - Oraculo independente: re-deriva S, argmax, MAXIMO16 e ALTERADOS a partir
#   das tabelas PARAM16 impressas; nao le .expected para decidir valores
#   (apenas para V10/V12).
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-training-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/training-tests",
    [string]$SourcePath = "src/treino.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat"
)

$ErrorActionPreference = "Stop"

$script:failures = 0
$script:checks = 0
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

function Get-Emb16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

$ENT = [int[]]@(9, 12, 13, 14)
$ALV = [int[]]@(12, 13, 14, 24)

function Get-Z256State {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada, [int]$Y)
    [long]$soma = 0
    for ($d = 0; $d -lt 4; $d++) {
        $soma += [long]$W[$Y][$d] * [long](Get-Emb16 $Entrada $d)
    }
    return $soma + 16 * [long]$B[$Y]
}

function Get-ArgmaxState {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada)
    $melhor = 0
    [long]$melhorValor = Get-Z256State $W $B $Entrada 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-Z256State $W $B $Entrada $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-SState {
    param([hashtable]$W, [hashtable]$B)
    [long]$soma = 0
    for ($i = 0; $i -lt 4; $i++) {
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-Z256State $W $B $ENT[$i] $y
            if ($y -eq $ALV[$i]) { $delta -= 256 }
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-MaxState {
    param([hashtable]$W, [hashtable]$B)
    $maxW = 0
    $maxB = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($d = 0; $d -lt 4; $d++) {
            $v = [Math]::Abs($W[$y][$d])
            if ($v -gt $maxW) { $maxW = $v }
        }
        $v = [Math]::Abs($B[$y])
        if ($v -gt $maxB) { $maxB = $v }
    }
    return @($maxW, $maxB)
}

function Get-AlteradosState {
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

function Get-PredState {
    param([hashtable]$W, [hashtable]$B)
    $parts = @()
    for ($i = 0; $i -lt 4; $i++) { $parts += (Get-ArgmaxState $W $B $ENT[$i]) }
    return ($parts -join " ")
}

function Get-AcertosState {
    param([hashtable]$W, [hashtable]$B)
    $total = 0
    for ($i = 0; $i -lt 4; $i++) {
        if ((Get-ArgmaxState $W $B $ENT[$i]) -eq $ALV[$i]) { $total++ }
    }
    return $total
}

function New-TableFromRows {
    param([string[]]$Rows)
    $w = @{}
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $parts = @($Rows[$y] -split " ")
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = [int]$parts[$d + 1] }
        $w[$y] = $row
        $b[$y] = [int]$parts[5]
    }
    return [pscustomobject]@{ W = $w; B = $b }
}

function Get-StateFromLines {
    param([string[]]$Lines)
    $w = @{}
    $b = @{}
    $seen = @{}
    for ($y = 0; $y -lt 25; $y++) { $w[$y] = New-Object 'int[]' 4 }
    foreach ($line in $Lines) {
        if ($line -match '^PARAM16=(0|[1-9][0-9]*) (-?[0-9]+) (-?[0-9]+) (-?[0-9]+) (-?[0-9]+) (-?[0-9]+)$') {
            $y = [int]$Matches[1]
            if ($y -lt 0 -or $y -gt 24) { continue }
            $seen[$y] = $true
            for ($d = 0; $d -lt 4; $d++) { $w[$y][$d] = [int]$Matches[$d + 2] }
            $b[$y] = [int]$Matches[6]
        }
    }
    return [pscustomobject]@{
        W = $w
        B = $b
        Count = $seen.Count
    }
}

function Get-ValueLine {
    param([string[]]$Lines, [string]$Tag)
    $matches = @($Lines | Where-Object { $_ -like "$Tag=*" })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0].Substring($Tag.Length + 1)
}

function Get-RoundHalfAway {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

# --- Tabelas canonicas (spec secao 4.2 e 8.3) ------------------------------

$initialRows = @(
    "0 -12 -7 -2 3 -4", "1 -5 0 5 10 3", "2 2 7 12 -8 1", "3 9 -11 -6 -1 -1",
    "4 -9 -4 1 6 -3", "5 -2 3 8 -12 4", "6 5 10 -10 -5 2", "7 12 -8 -3 2 0",
    "8 -6 -1 4 9 -2", "9 1 6 11 -9 -4", "10 8 -12 -7 -2 3", "11 -10 -5 0 5 1",
    "12 -3 2 7 12 -1", "13 4 9 -11 -6 -3", "14 11 -9 -4 1 4", "15 -7 -2 3 8 2",
    "16 0 5 10 -10 0", "17 7 12 -8 -3 -2", "18 -11 -6 -1 4 -4", "19 -4 1 6 11 3",
    "20 3 8 -12 -7 1", "21 10 -10 -5 0 -1", "22 -8 -3 2 7 -3", "23 -1 4 9 -11 4",
    "24 6 11 -9 -4 2"
)
$finalRows = @(
    "0 -1 0 -3 2 -1", "1 0 0 -2 3 0", "2 0 0 11 -10 2", "3 1 0 -3 2 -2",
    "4 0 0 -4 3 0", "5 -1 0 10 -11 2", "6 -1 0 -3 2 0", "7 1 0 -3 3 -1",
    "8 0 -1 -2 3 1", "9 0 0 9 -10 1", "10 1 0 -1 2 -1", "11 -1 0 -1 2 1",
    "12 8 -7 -3 3 2", "13 1 2 3 6 6", "14 1 8 -4 -2 2", "15 0 -1 -2 3 0",
    "16 0 1 10 -10 3", "17 0 0 -3 2 -1", "18 -1 -1 -3 4 0", "19 1 -1 -2 3 0",
    "20 -1 0 -4 3 0", "21 0 0 -3 3 -1", "22 0 0 -3 4 0", "23 -1 0 10 -10 3",
    "24 -9 -2 -4 0 4"
)
$initialParamLines = @(0..24 | ForEach-Object { "PARAM16=$($initialRows[$_])" })
$finalParamLines = @(0..24 | ForEach-Object { "PARAM16=$($finalRows[$_])" })

$rPairs = @(
    @(0, 64), @(31, 64), @(32, 64), @(33, 64), @(-31, 64), @(-32, 64), @(-33, 64),
    @(511, 1024), @(512, 1024), @(513, 1024),
    @(-511, 1024), @(-512, 1024), @(-513, 1024), @(1, 1024), @(-1, 1024)
)
$rLines = @($rPairs | ForEach-Object {
    "R=$($_[0]) $($_[1]) $(Get-RoundHalfAway $_[0] $_[1])"
})

$configLines = @(
    "INFO=TREINO 16 256 125 100",
    "TAXA=1/4",
    "GRADE=1/16",
    "EPOCAS=5",
    "ESCALA_PERDA=524288",
    "LIMITE_PARAM=48",
    "ORDEM=EXEMPLO"
)
$history5 = "HISTORICO=3674036 428488 107796 41544 30998 27804"

# --- Saidas esperadas por caso (independentes dos .expected) ---------------

$expected = @{}
$expected["trn_info"] = $configLines + @(
    "ERRO=EXEMPLOS_INVALIDOS", "ERRO=EXEMPLOS_INVALIDOS",
    "ERRO=EPOCAS_INVALIDAS", "ERRO=EPOCAS_INVALIDAS",
    "ERRO=ID_INVALIDO", "ERRO=ID_INVALIDO",
    "ERRO=SAIDA_INVALIDA", "ERRO=SAIDA_INVALIDA"
) + $rLines

$expected["trn_perda_inicial"] = @(
    "PERDA=3674036", "ACERTOS=0", "PRED=10 19 6 11"
) + $initialParamLines + @(
    "MAXIMO16=12 4", "ALTERADOS_W=0", "ALTERADOS_B=0"
)

$expected["trn_gradiente"] = @(
    "GRAD_EXATOS=125", "GRAD_TOTAL=125", "GRAD_SOMA=-8960"
) + $initialParamLines + @(
    "MAXIMO16=12 4", "ERRO=PARAMETROS_INVALIDOS", "PARAM16=12 -3 2 7 12 -1"
)

$expected["trn_epoca_1"] = @(
    "CODIGO=0", "HISTORICO=3674036 428488", "PERDA=428488", "ACERTOS=2",
    "PRED=14 1 14 24",
    "PARAM16=9 1 1 9 -10 0", "PARAM16=12 5 -5 -1 5 3",
    "PARAM16=13 -1 6 -1 3 0", "PARAM16=14 8 0 -5 0 4",
    "ALTERADOS_W=93", "ALTERADOS_B=20"
)

$expected["trn_cinco_epocas"] = @(
    "CODIGO=0", $history5, "PERDA=27804", "ACERTOS=4", "PRED=12 13 14 24",
    "PONTO_FIXO=OK", "CODIGO6=0"
)

$expected["trn_estado_final"] = @(
    "CODIGO=0", "PERDA=27804", "ACERTOS=4", "PRED=12 13 14 24"
) + $finalParamLines + @(
    "MAXIMO16=11 6", "ALTERADOS_W=91", "ALTERADOS_B=23"
)

$expected["trn_erros"] = @(
    "ERRO=EXEMPLOS_INVALIDOS", "INTACTO=OK",
    "ERRO=EPOCAS_INVALIDAS", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "ERRO=PARAMETROS_INVALIDOS", "PARAM16=0 49 -7 -2 3 -4", "INTACTO=OK",
    "CODIGO=5", "PARAM16=5 -45 -42 -40 -37 62"
)

$expected["trn_limites"] = @(
    "ERRO=EXEMPLOS_INVALIDOS", "ERRO=EXEMPLOS_INVALIDOS",
    "ERRO=EPOCAS_INVALIDAS", "ERRO=EPOCAS_INVALIDAS",
    "CODIGO=0", "HISTORICO=1298270 31576", "PERDA=31576", "ACERTOS=1", "PRED=12",
    "CODIGO=0", "HISTORICO=14696144 123992", "PERDA=123992", "ACERTOS=16",
    "PRED=12 13 14 24 12 13 14 24 12 13 14 24 12 13 14 24"
)

$expected["trn_determinismo_a"] = @(
    "CODIGO=0", $history5, "PERDA=27804", "ACERTOS=4", "PRED=12 13 14 24"
) + $finalParamLines + @("MAXIMO16=11 6")
$expected["trn_determinismo_b"] = $expected["trn_determinismo_a"]

$expected["trn_composicao"] = @(
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

$expected["trn_reinicializacao"] = @(
    "PARAM16=9 1 6 40 -9 -4",
    "PARAM16=9 1 6 11 -9 -4",
    "PERDA=3674036", "ACERTOS=0", "PRED=10 19 6 11"
)

$expectedCases = @(
    "trn_cinco_epocas", "trn_composicao", "trn_determinismo_a", "trn_determinismo_b",
    "trn_epoca_1", "trn_erros", "trn_estado_final", "trn_gradiente", "trn_info",
    "trn_limites", "trn_perda_inicial", "trn_reinicializacao"
)

# --- V1: fonte -------------------------------------------------------------

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
$sourceCode = (($sourceText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
if ($sourceText -match '(?m)^\s*programa\b') { $v1Errors += "o fragmento declara 'programa'" }
if ($sourceText -match '(?m)^\s*funcao\s+inicio\b') { $v1Errors += "o fragmento declara 'inicio'" }
if ($sourceText -match '(?m)^\s*inclua\b') { $v1Errors += "o fragmento inclui biblioteca" }
foreach ($forbidden in @("Matematica", "aleatorio", "tempo", "leia")) {
    if ($sourceCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $v1Errors += "o fragmento usa identificador proibido: $forbidden"
    }
}
foreach ($required in @(
    "TREINO_TAM_VOCAB = 25", "TREINO_DIM = 4", "TREINO_SAIDAS = 25",
    "TREINO_TOTAL_W = 100", "TREINO_TOTAL_B = 25", "TREINO_PARAMS = 125",
    "TREINO_MAX_EXEMPLOS = 16", "TREINO_MAX_EPOCAS = 256", "TREINO_GRADE = 16",
    "TREINO_ESCALA_PERDA = 524288", "TREINO_LIMITE = 48", "TREINO_EPOCAS = 5",
    "TREINO_TAXA_NUM = 1", "TREINO_TAXA_DEN = 4", "TREINO_DIV_W = 1024",
    "TREINO_DIV_B = 64"
)) {
    if ($sourceText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        $v1Errors += "fragmento nao contem: $required"
    }
}
Write-Check "V1 fonte: ASCII, fragmento, constantes, sem biblioteca/aleatorio" $v1Errors

# --- V2: conjunto de casos -------------------------------------------------

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
if ($expectedFiles.Count -ne 12) { $v2Errors += "arquivos .expected: $($expectedFiles.Count); esperado 12" }
Write-Check "V2 conjunto exato de 12 casos" $v2Errors
if ($v2Errors.Count -gt 0) { exit 1 }

Write-Host "=== Verificacao de bytes e valores do treinamento M5 ==="
Write-Host "Fonte:         $SourcePath"
Write-Host "Casos:         $GeneratedRoot"
Write-Host "Interpretador: $InterpreterPath"
Write-Host "Casos esperados: $($expectedCases.Count)"

# --- Execucao crua ---------------------------------------------------------

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
    $porPath = Join-Path $GeneratedRoot "$name.por"
    if (-not (Test-Path -LiteralPath $porPath)) {
        Write-Check $name @("arquivo ausente: $porPath")
        continue
    }
    $run = Invoke-CaseRaw $porPath
    $check = Test-RawCase $name $run.Bytes $run.Errors
    $runs[$name] = $run
    $linesByName[$name] = $check.Lines
    Write-Check $name $check.Errors
}

# --- V4: configuracao ------------------------------------------------------

$v4Errors = @()
if ($linesByName.ContainsKey("trn_info")) {
    $lines = $linesByName["trn_info"]
    foreach ($line in $configLines) {
        if (-not ($lines -ccontains $line)) { $v4Errors += "linha ausente em trn_info: [$line]" }
    }
    if ($lines.Count -lt 7 -or (($lines[0..6] -join "|") -cne ($configLines -join "|"))) {
        $v4Errors += "bloco de configuracao de trn_info diverge da spec"
    }
} else {
    $v4Errors += "trn_info nao executado"
}
Write-Check "V4 INFO, TAXA, GRADE, EPOCAS, ESCALA_PERDA, LIMITE_PARAM, ORDEM" $v4Errors

# --- V5/V7/V8: tabelas completas ------------------------------------------

function Test-FullTable {
    param([string]$Name, [string[]]$Lines, [string[]]$Rows, [bool]$HasLoss)
    $errors = @()
    $state = Get-StateFromLines $Lines
    if ($state.Count -ne 25) {
        return @("tabela PARAM16 incompleta: $($state.Count) linhas distintas; esperado 25")
    }
    for ($y = 0; $y -lt 25; $y++) {
        $actual = "PARAM16=$y $($state.W[$y] -join ' ') $($state.B[$y])"
        if ($actual -cne "PARAM16=$($Rows[$y])") {
            $errors += "linha ${y}: [$actual]; tabela diz [$($Rows[$y])]"
        }
    }
    if ($HasLoss) {
        $loss = Get-ValueLine $Lines "PERDA"
        if ($null -eq $loss) {
            $errors += "PERDA ausente"
        } elseif ([long]$loss -ne (Get-SState $state.W $state.B)) {
            $errors += "S re-derivado $(Get-SState $state.W $state.B) != PERDA $loss"
        }
    }
    $max = Get-MaxState $state.W $state.B
    $maxLine = Get-ValueLine $Lines "MAXIMO16"
    if ($null -eq $maxLine) {
        $errors += "MAXIMO16 ausente"
    } elseif ($maxLine -cne "$($max[0]) $($max[1])") {
        $errors += "MAXIMO16 impresso [$maxLine]; tabela diz [$($max[0]) $($max[1])]"
    }
    $alt = Get-AlteradosState $state.W $state.B
    $aw = Get-ValueLine $Lines "ALTERADOS_W"
    $ab = Get-ValueLine $Lines "ALTERADOS_B"
    if ($null -ne $aw -and [int]$aw -ne $alt[0]) { $errors += "ALTERADOS_W=$aw; tabela diz $($alt[0])" }
    if ($null -ne $ab -and [int]$ab -ne $alt[1]) { $errors += "ALTERADOS_B=$ab; tabela diz $($alt[1])" }
    $pred = Get-ValueLine $Lines "PRED"
    $acertos = Get-ValueLine $Lines "ACERTOS"
    if ($null -ne $pred -and $pred -cne (Get-PredState $state.W $state.B)) {
        $errors += "PRED impresso [$pred]; tabela diz [$(Get-PredState $state.W $state.B)]"
    }
    if ($null -ne $acertos -and [int]$acertos -ne (Get-AcertosState $state.W $state.B)) {
        $errors += "ACERTOS=$acertos; tabela diz $(Get-AcertosState $state.W $state.B)"
    }
    return $errors
}

$v5Errors = @()
foreach ($name in @("trn_perda_inicial", "trn_estado_final", "trn_determinismo_a", "trn_determinismo_b")) {
    if (-not $linesByName.ContainsKey($name)) { $v5Errors += "$name nao executado"; continue }
    $rows = if ($name -eq "trn_perda_inicial") { $initialRows } else { $finalRows }
    $v5Errors += Test-FullTable $name $linesByName[$name] $rows $true
}
Write-Check "V5 S re-derivado das tabelas completas e igual ao PERDA" $v5Errors

$v8Errors = @()
foreach ($name in @("trn_perda_inicial", "trn_estado_final")) {
    if (-not $linesByName.ContainsKey($name)) { $v8Errors += "$name nao executado"; continue }
    $rows = if ($name -eq "trn_perda_inicial") { $initialRows } else { $finalRows }
    $v8Errors += Test-FullTable $name $linesByName[$name] $rows $false
}
foreach ($name in @("trn_determinismo_a", "trn_determinismo_b")) {
    if (-not $linesByName.ContainsKey($name)) { $v8Errors += "$name nao executado"; continue }
    $state = Get-StateFromLines $linesByName[$name]
    if ($state.Count -ne 25) { $v8Errors += "${name}: tabela incompleta"; continue }
    $max = Get-MaxState $state.W $state.B
    $maxLine = Get-ValueLine $linesByName[$name] "MAXIMO16"
    if ($null -eq $maxLine -or $maxLine -cne "$($max[0]) $($max[1])") {
        $v8Errors += "${name}: MAXIMO16 incoerente com a tabela"
    }
}
Write-Check "V8 ALTERADOS_* e MAXIMO16 coerentes com a tabela final" $v8Errors

$v7Errors = @()
foreach ($name in @("trn_perda_inicial", "trn_estado_final", "trn_determinismo_a", "trn_determinismo_b")) {
    if (-not $linesByName.ContainsKey($name)) { $v7Errors += "$name nao executado"; continue }
    $state = Get-StateFromLines $linesByName[$name]
    if ($state.Count -ne 25) { $v7Errors += "${name}: tabela incompleta"; continue }
    $pred = Get-ValueLine $linesByName[$name] "PRED"
    if ($pred -cne (Get-PredState $state.W $state.B)) {
        $v7Errors += "${name}: PRED incoerente com a tabela"
    }
    $acertos = Get-ValueLine $linesByName[$name] "ACERTOS"
    if ([int]$acertos -ne (Get-AcertosState $state.W $state.B)) {
        $v7Errors += "${name}: ACERTOS incoerente com a tabela"
    }
}
Write-Check "V7 ACERTOS e PRED coerentes com a tabela" $v7Errors

# --- V6: historico ---------------------------------------------------------

$v6Errors = @()
$historySeen = 0
foreach ($name in $expectedCases) {
    if (-not $linesByName.ContainsKey($name)) { continue }
    foreach ($line in $linesByName[$name]) {
        if ($line -match '^HISTORICO=(.+)$') {
            $historySeen++
            $values = @($Matches[1] -split " " | ForEach-Object { [long]$_ })
            for ($i = 1; $i -lt $values.Count; $i++) {
                if ($values[$i] -ge $values[$i - 1]) {
                    $v6Errors += "${name}: HISTORICO nao e estritamente decrescente em $($i - 1)..$i"
                }
            }
            if ($values.Count -eq 6) {
                if (($values -join " ") -cne "3674036 428488 107796 41544 30998 27804") {
                    $v6Errors += "${name}: HISTORICO de 6 valores diverge da spec"
                }
            }
        }
    }
}
if ($historySeen -lt 5) { $v6Errors += "HISTORICO encontrado em $historySeen linhas; esperado ao menos 5" }
Write-Check "V6 HISTORICO estritamente decrescente e S5=27804" $v6Errors

# --- V9: gradiente ---------------------------------------------------------

$v9Errors = @()
if ($linesByName.ContainsKey("trn_gradiente")) {
    $lines = $linesByName["trn_gradiente"]
    if ((Get-ValueLine $lines "GRAD_EXATOS") -cne "125") { $v9Errors += "GRAD_EXATOS != 125" }
    if ((Get-ValueLine $lines "GRAD_TOTAL") -cne "125") { $v9Errors += "GRAD_TOTAL != 125" }
    if ((Get-ValueLine $lines "GRAD_SOMA") -cne "-8960") { $v9Errors += "GRAD_SOMA != -8960" }
    $v9Errors += Test-FullTable "trn_gradiente" $lines $initialRows $false
} else {
    $v9Errors += "trn_gradiente nao executado"
}
Write-Check "V9 GRAD_EXATOS=GRAD_TOTAL=125, GRAD_SOMA=-8960, estado restaurado" $v9Errors

# --- V10: determinismo -----------------------------------------------------

$v10Errors = @()
$pathA = Join-Path $GeneratedRoot "trn_determinismo_a.expected"
$pathB = Join-Path $GeneratedRoot "trn_determinismo_b.expected"
if (-not (Test-Path -LiteralPath $pathA) -or -not (Test-Path -LiteralPath $pathB)) {
    $v10Errors += "arquivos de determinismo ausentes"
} else {
    $bytesA = [IO.File]::ReadAllBytes($pathA)
    $bytesB = [IO.File]::ReadAllBytes($pathB)
    if (-not [Convert]::ToBase64String($bytesA).Equals([Convert]::ToBase64String($bytesB), [StringComparison]::Ordinal)) {
        $v10Errors += "trn_determinismo_a.expected difere de trn_determinismo_b.expected"
    }
}
if ($runs.ContainsKey("trn_determinismo_a") -and $runs.ContainsKey("trn_determinismo_b")) {
    if (-not [Convert]::ToBase64String($runs["trn_determinismo_a"].Bytes).Equals([Convert]::ToBase64String($runs["trn_determinismo_b"].Bytes), [StringComparison]::Ordinal)) {
        $v10Errors += "saidas dos processos A e B diferem"
    }
} else {
    $v10Errors += "processos A/B nao executados"
}
foreach ($name in @("trn_determinismo_a", "trn_determinismo_b")) {
    if (-not $runs.ContainsKey($name)) { continue }
    $second = Invoke-CaseRaw (Join-Path $GeneratedRoot "$name.por")
    if (-not [Convert]::ToBase64String($runs[$name].Bytes).Equals([Convert]::ToBase64String($second.Bytes), [StringComparison]::Ordinal)) {
        $v10Errors += "${name}: duas execucoes diferem"
    }
}
Write-Check "V10 determinismo A/B byte a byte" $v10Errors

# --- V11: composicao -------------------------------------------------------

$v11Errors = @()
if ($linesByName.ContainsKey("trn_composicao")) {
    $lines = $linesByName["trn_composicao"]
    if ($lines[0] -cne "IDS=9 12 13 14 24") { $v11Errors += "IDS da M1 ausente ou incorreto" }
    if (-not ($lines -ccontains "ALVOS=12 13 14 24")) { $v11Errors += "ALVOS incorreto" }
    if (-not ($lines -ccontains "EMB16=OK")) { $v11Errors += "EMB16=OK ausente" }
    if (-not ($lines -ccontains "COMPOE=OK")) { $v11Errors += "COMPOE=OK ausente" }
    $final = New-TableFromRows $finalRows
    $expectedArgmax = ("ARGMAX_REDE=" + ((0..3 | ForEach-Object { Get-ArgmaxState $final.W $final.B $ENT[$_] }) -join " "))
    if (-not ($lines -ccontains $expectedArgmax)) {
        $v11Errors += "ARGMAX_REDE nao reproduz o argmax da tabela final"
    }
    if (-not ($lines -ccontains ("ARGMAX_TREINO=" + (($expectedArgmax -split "=")[1])))) {
        $v11Errors += "ARGMAX_TREINO nao reproduz o argmax da tabela final"
    }
    $cells = @()
    for ($id = 0; $id -lt 25; $id++) {
        for ($d = 0; $d -lt 4; $d++) { $cells += (Get-Emb16 $id $d) }
    }
    if ($cells.Count -ne 100) { $v11Errors += "celulas da M3: $($cells.Count); esperado 100" }
} else {
    $v11Errors += "trn_composicao nao executado"
}
Write-Check "V11 composicao: IDs da M1, 100 celulas da M3, argmax coerente" $v11Errors

# --- V12: bytes de todos os .expected -------------------------------------

$v12Errors = @()
foreach ($name in $expectedCases) {
    $expectedPath = Join-Path $GeneratedRoot ($name + ".expected")
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        $v12Errors += "${name}: .expected ausente"
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($expectedPath)
    if ($bytes.Length -eq 0) { $v12Errors += "${name}: .expected vazio"; continue }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $v12Errors += "${name}: BOM no .expected"
    }
    if ($bytes[$bytes.Length - 1] -eq 0x0A) { $v12Errors += "${name}: .expected termina em LF" }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $v12Errors += "${name}: CR no .expected"; break }
        if ($b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) {
            $v12Errors += ("{0}: byte 0x{1:X2} no .expected" -f $name, $b)
            break
        }
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    foreach ($line in @($text -split "`n")) {
        if ($line -ne $line.Trim()) { $v12Errors += "${name}: espaco nas pontas em [$line]"; break }
    }
    $oracleText = @($expected[$name]) -join "`n"
    if ($text -cne $oracleText) { $v12Errors += "${name}: .expected difere do oraculo do verificador" }
}
Write-Check "V12 .expected sem LF final, CR, BOM ou espaco nas pontas" $v12Errors

Write-Host ""
Write-Host "Total: $script:checks verificacoes, $script:failures falha(s)"
if ($script:failures -gt 0) { exit 1 }
Write-Host "Formato e valores conforme."
exit 0
