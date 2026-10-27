# ---------------------------------------------------------------------------
# Verificacao do formato observavel e dos valores da geracao autoregressiva (M6).
# - Fonte ASCII puro, fragmento, constantes canonicas, sem biblioteca/aleatorio.
# - Conjunto de casos exatamente igual ao esperado (sem faltas nem extras).
# - Saida crua: form feed inicial, carga ASCII com LF, epilogo exato.
# - Oraculo independente: re-deriva argmax, cadeias, mapas e blocos a partir das
#   tabelas canonicas e da tabela treinada da M5; nao le .expected para decidir
#   valores (apenas para V10/V12).
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-generation-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/generation-tests",
    [string]$SourcePath = "src/gerador.por",
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

function Get-Emb16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

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

function Get-Geracao {
    param([hashtable]$W, [hashtable]$B, [int]$Semente, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $saida[0] = $Semente
    $total = 1
    while ($total -lt $Maximo) {
        if ($saida[$total - 1] -eq 24) { break }
        $saida[$total] = Get-ArgmaxState $W $B $saida[$total - 1]
        $total++
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
}

function Get-Ciclo {
    param([int[]]$Saida, [int]$Total)
    for ($p = 1; $p -lt $Total; $p++) {
        $ok = $true
        for ($i = $p; $i -lt $Total; $i++) {
            if ($Saida[$i] -ne $Saida[$i - $p]) { $ok = $false }
        }
        if ($ok) { return $p }
    }
    return $Total
}

function Get-Palavra {
    param([int]$Id)
    $palavras = @(
        "UNK", "programa", "funcao", "inicio", "inteiro", "real", "logico",
        "cadeia", "vazio", "se", "senao", "enquanto", "faca", "para", "ate",
        "passo", "retorne", "escreva", "leia", "e", "ou", "nao", "verdadeiro",
        "falso", "pare"
    )
    return $palavras[$Id]
}

function Get-GeracaoLines {
    param([hashtable]$W, [hashtable]$B, [int]$Semente, [int]$Maximo)
    $g = Get-Geracao $W $B $Semente $Maximo
    $ids = @($g.Saida[0..($g.Total - 1)])
    $parada = if ($ids[$ids.Count - 1] -eq 24) { "PARE" } else { "MAXIMO" }
    $texto = (@($ids | ForEach-Object { Get-Palavra $_ }) -join " ")
    $lines = @()
    $lines += "GERADO=" + ($ids -join " ")
    $lines += "N=$($g.Total)"
    $lines += "PASSOS=$($g.Total - 1)"
    $lines += "PARADA=$parada"
    $lines += "TEXTO=$texto"
    return $lines
}

function Get-MapaLines {
    param([hashtable]$W, [hashtable]$B, [int]$Maximo)
    $lines = @()
    for ($s = 0; $s -lt 25; $s++) {
        $g = Get-Geracao $W $B $s $Maximo
        $ids = @($g.Saida[0..($g.Total - 1)])
        $lines += "MAPA=$s " + ($ids -join " ")
    }
    return $lines
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

# --- Tabelas canonicas (spec M5 secao 4.2 e 8.3) ---------------------------

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
$init = New-TableFromRows $initialRows
$final = New-TableFromRows $finalRows
$maxFinal = Get-MaxState $final.W $final.B
$maxFinalLine = "MAXIMO16=$($maxFinal[0]) $($maxFinal[1])"
if ($maxFinalLine -cne "MAXIMO16=11 6") { Fail "tabela final embutida produz $maxFinalLine; esperado MAXIMO16=11 6" }

# --- Saidas esperadas por caso (independentes dos .expected) ---------------

$expected = @{}

$infoLines = @(
    "INFO=GERADOR 25 64 4 125",
    "TOKEN_PARADA=24",
    "TOKEN_UNK=0",
    "LIMITE_MAXIMO=64"
)
foreach ($pair in @(@(0, 1), @(24, 64), @(-1, 0), @(25, 65))) {
    $token = $pair[0]
    $limite = $pair[1]
    $tokenOk = if ($token -ge 0 -and $token -lt 25) { 1 } else { 0 }
    $limiteOk = if ($limite -ge 1 -and $limite -le 64) { 1 } else { 0 }
    $infoLines += "VALIDO=TOKEN $token $tokenOk"
    $infoLines += "VALIDO=LIMITE $limite $limiteOk"
}
$expected["gen_info"] = $infoLines

$expected["gen_canonico"] = Get-GeracaoLines $init.W $init.B 9 8

$g19 = Get-Geracao $init.W $init.B 19 8
$g0 = Get-Geracao $init.W $init.B 0 5
$expected["gen_ciclo"] = @()
$expected["gen_ciclo"] += Get-GeracaoLines $init.W $init.B 19 8
$expected["gen_ciclo"] += "CICLO=$(Get-Ciclo $g19.Saida $g19.Total)"
$expected["gen_ciclo"] += Get-GeracaoLines $init.W $init.B 0 5
$expected["gen_ciclo"] += "CICLO=$(Get-Ciclo $g0.Saida $g0.Total)"

$expected["gen_treinado_cadeia"] = Get-GeracaoLines $final.W $final.B 9 16
$expected["gen_treinado_parada"] = Get-GeracaoLines $final.W $final.B 14 16
$expected["gen_unk"] = Get-GeracaoLines $final.W $final.B 0 16
$expected["gen_inicial_pare"] = Get-GeracaoLines $final.W $final.B 24 16

$expected["gen_limites"] = @()
$expected["gen_limites"] += Get-GeracaoLines $final.W $final.B 9 1
$expected["gen_limites"] += Get-GeracaoLines $final.W $final.B 9 4
$expected["gen_limites"] += Get-GeracaoLines $final.W $final.B 9 5
$expected["gen_limites"] += Get-GeracaoLines $final.W $final.B 9 64
$expected["gen_limites"] += Get-GeracaoLines $init.W $init.B 9 64

$expected["gen_erros"] = @(
    "ERRO=TOKEN_INVALIDO", "ERRO=TOKEN_INVALIDO",
    "ERRO=LIMITE_INVALIDO", "ERRO=LIMITE_INVALIDO",
    "ERRO=TOKEN_INVALIDO",
    "ERRO=PARAMETROS_INVALIDOS", "ERRO=PARAMETROS_INVALIDOS",
    "ERRO=TOKEN_INVALIDO",
    "INTACTO=OK", "SAIDA_INTACTA=OK"
)

$allWords = @()
for ($t = 0; $t -lt 25; $t++) { $allWords += Get-Palavra $t }
$textoLines = @("TEXTO=" + ($allWords -join " "))
$textoLines += "TEXTO="
$textoLines += "TEXTO=" + ((@(0, 0, 0, 0, 0, 0) | ForEach-Object { Get-Palavra $_ }) -join " ")
$textoLines += "ERRO=SEQUENCIA_INVALIDA"
$textoLines += "ERRO=SEQUENCIA_INVALIDA"
$textoLines += "ERRO=SEQUENCIA_INVALIDA"
for ($t = 0; $t -lt 25; $t++) { $textoLines += "PALAVRA=$t $(Get-Palavra $t)" }
$textoLines += "ERRO=ID_INVALIDO"
$textoLines += "ERRO=ID_INVALIDO"
$expected["gen_texto"] = $textoLines

$expected["gen_mapa_treinado"] = Get-MapaLines $final.W $final.B 16

$determinismoLines = @()
for ($y = 0; $y -lt 25; $y++) { $determinismoLines += "PARAM16=$($finalRows[$y])" }
$determinismoLines += $maxFinalLine
foreach ($s in @(0, 4, 9, 14, 19, 24)) {
    $determinismoLines += Get-GeracaoLines $final.W $final.B $s 16
}
$expected["gen_determinismo_a"] = $determinismoLines
$expected["gen_determinismo_b"] = $determinismoLines

$expected["gen_composicao"] = @(
    "IDS=9 12 13 14 24",
    "ALVOS=12 13 14 24",
    "EMB16=OK",
    "ARGMAX_REDE=12 13 14 24",
    "ARGMAX_TREINO=12 13 14 24"
) + (Get-GeracaoLines $final.W $final.B 9 16) + @(
    "PARAMS_INTACTOS=OK",
    "COMPOE=OK"
)

$expectedCases = @(
    "gen_canonico", "gen_ciclo", "gen_composicao", "gen_determinismo_a",
    "gen_determinismo_b", "gen_erros", "gen_info", "gen_inicial_pare",
    "gen_limites", "gen_mapa_treinado", "gen_texto", "gen_treinado_cadeia",
    "gen_treinado_parada", "gen_unk"
)

# --- V1: fonte -------------------------------------------------------------

$v1Errors = @()
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { Fail "fragmento nao encontrado: $SourcePath" }
$sourceBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $SourcePath).ProviderPath)
if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) {
    $v1Errors += "fonte com BOM"
}
foreach ($b in $sourceBytes) {
    if ($b -eq 0x0D) { $v1Errors += "fonte com CR"; break }
    if ($b -gt 0x7E) { $v1Errors += ("byte nao ASCII 0x{0:X2}" -f $b); break }
}
$sourceText = [Text.Encoding]::ASCII.GetString($sourceBytes)
$sourceCode = (($sourceText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
$sourceCode = [regex]::Replace($sourceCode, '"[^"]*"', '""')
foreach ($forbidden in @(
    "programa", "inicio", "inclua", "Matematica", "aleatorio", "tempo",
    "leia", "softmax", "exp(", "temperatura", "top_", "real"
)) {
    if ($sourceCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $v1Errors += "identificador proibido na fonte: $forbidden"
    }
}
$deps = @([regex]::Matches($sourceCode, 'treino_[a-z0-9_]+') |
    ForEach-Object { $_.Value } | Sort-Object -Unique)
if (($deps -join "|") -cne "treino_argmax|treino_params_validos") {
    $v1Errors += "dependencias inesperadas da M5: $($deps -join ', ')"
}
foreach ($required in @(
    "GERADOR_TAM_VOCAB = 25", "GERADOR_DIM = 4", "GERADOR_SAIDAS = 25",
    "GERADOR_PARAMS = 125", "GERADOR_MAX_TOKENS = 64", "GERADOR_TOKEN_UNK = 0",
    "GERADOR_TOKEN_PARADA = 24"
)) {
    if ($sourceText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        $v1Errors += "constante ausente: $required"
    }
}
Write-Check "V1 fonte ASCII, LF, sem BOM, sem biblioteca/aleatorio/real, dependencias limitadas a M5" $v1Errors

# --- V2: conjunto de casos -------------------------------------------------

if (-not (Test-Path -LiteralPath $InterpreterPath)) { Fail "interpretador nao encontrado: $InterpreterPath" }
if (-not (Test-Path -Path $GeneratedRoot)) { Fail "diretorio de casos nao encontrado: $GeneratedRoot" }

$expectedFiles = @(Get-ChildItem -Path $GeneratedRoot -Filter "*.expected" -File | Sort-Object Name)
$actualNames = @($expectedFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
$porFiles = @(Get-ChildItem -Path $GeneratedRoot -Filter "*.por" -File)
$v2Errors = @()
if ((($actualNames | Sort-Object) -join "|") -cne (($expectedCases | Sort-Object) -join "|")) {
    $v2Errors += "conjunto de casos diverge.`n  Esperado: " + ($expectedCases -join ", ") + "`n  Obtido:   " + ($actualNames -join ", ")
}
if ($expectedFiles.Count -ne 14) { $v2Errors += "arquivos .expected: $($expectedFiles.Count); esperado 14" }
if ($porFiles.Count -ne 14) { $v2Errors += "arquivos .por: $($porFiles.Count); esperado 14" }
Write-Check "V2 conjunto exatamente igual aos 14 casos gen_*" $v2Errors
if ($v2Errors.Count -gt 0) { exit 1 }

Write-Host "=== Verificacao de bytes e valores da geracao M6 ==="
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
$v3Errors = @()
foreach ($name in $expectedCases) {
    $porPath = Join-Path $GeneratedRoot "$name.por"
    if (-not (Test-Path -LiteralPath $porPath)) {
        $v3Errors += "arquivo ausente: $porPath"
        continue
    }
    $run = Invoke-CaseRaw ((Resolve-Path -LiteralPath $porPath).ProviderPath)
    $check = Test-RawCase $name $run.Bytes $run.Errors
    $runs[$name] = $run
    $linesByName[$name] = $check.Lines
    $v3Errors += @($check.Errors | ForEach-Object { "${name}: $_" })
}
Write-Check "V3 bytes crus de todos os casos: form feed, carga ASCII/LF, epilogo e valores re-derivados" $v3Errors

# --- V4: configuracao ------------------------------------------------------

$v4Errors = @()
if ($linesByName.ContainsKey("gen_info")) {
    $lines = $linesByName["gen_info"]
    foreach ($line in @($infoLines[0..3])) {
        if (-not ($lines -ccontains $line)) { $v4Errors += "linha ausente em gen_info: [$line]" }
    }
    if ($lines.Count -ne 12 -or (($lines[0..11] -join "|") -cne ($infoLines -join "|"))) {
        $v4Errors += "bloco de configuracao/validadores de gen_info diverge da spec"
    }
} else {
    $v4Errors += "gen_info nao executado"
}
Write-Check "V4 INFO, TOKEN_PARADA, TOKEN_UNK, LIMITE_MAXIMO e 8 validadores" $v4Errors

# --- V5: cadeias treinadas -------------------------------------------------

$v5Errors = @()
$trainedCases = @(
    @{ Name = "gen_treinado_cadeia"; Seed = 9; Maximo = 16 },
    @{ Name = "gen_treinado_parada"; Seed = 14; Maximo = 16 },
    @{ Name = "gen_unk"; Seed = 0; Maximo = 16 },
    @{ Name = "gen_inicial_pare"; Seed = 24; Maximo = 16 },
    @{ Name = "gen_mapa_treinado"; Seed = -1; Maximo = 16 }
)
foreach ($case in $trainedCases) {
    if (-not $linesByName.ContainsKey($case.Name)) { $v5Errors += "$($case.Name) nao executado"; continue }
    $want = if ($case.Seed -ge 0) {
        Get-GeracaoLines $final.W $final.B $case.Seed $case.Maximo
    } else {
        Get-MapaLines $final.W $final.B $case.Maximo
    }
    $got = @($linesByName[$case.Name])
    if (($got -join "`n") -cne ($want -join "`n")) {
        $v5Errors += "$($case.Name): cadeia(s) diverge(m) da tabela treinada da M5"
    }
}
Write-Check "V5 cadeias treinadas re-derivadas da tabela final da M5" $v5Errors

# --- V6: N, PASSOS, PARADA e limite ---------------------------------------

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

$blocksByCase = @{
    "gen_canonico" = @(8)
    "gen_ciclo" = @(8, 5)
    "gen_treinado_cadeia" = @(16)
    "gen_treinado_parada" = @(16)
    "gen_unk" = @(16)
    "gen_inicial_pare" = @(16)
    "gen_limites" = @(1, 4, 5, 64, 64)
    "gen_composicao" = @(16)
    "gen_determinismo_a" = @(16, 16, 16, 16, 16, 16)
    "gen_determinismo_b" = @(16, 16, 16, 16, 16, 16)
}

$v6Errors = @()
foreach ($name in @($blocksByCase.Keys | Sort-Object)) {
    if (-not $linesByName.ContainsKey($name)) { $v6Errors += "$name nao executado"; continue }
    $blocks = @(Get-Blocks $linesByName[$name])
    $maximos = @($blocksByCase[$name])
    if ($blocks.Count -ne $maximos.Count) {
        $v6Errors += "${name}: $($blocks.Count) blocos; esperado $($maximos.Count)"
        continue
    }
    for ($b = 0; $b -lt $blocks.Count; $b++) {
        $block = $blocks[$b]
        $maximo = $maximos[$b]
        $idsText = $block[0].Substring("GERADO=".Length)
        $ids = @($idsText -split " ")
        $nText = $block[1].Substring("N=".Length)
        $passosText = $block[2].Substring("PASSOS=".Length)
        $parada = $block[3].Substring("PARADA=".Length)
        if ($idsText -match '^ | $|  ') { $v6Errors += "${name}[$b]: GERADO com espaco extra" }
        foreach ($idText in $ids) {
            if ($idText -notmatch '^(0|[1-9][0-9]*)$' -or [int]$idText -gt 24) {
                $v6Errors += "${name}[$b]: ID invalido [$idText]"
            }
        }
        if ($nText -notmatch '^(0|[1-9][0-9]*)$') {
            $v6Errors += "${name}[$b]: N nao numerico [$nText]"
            continue
        }
        $n = [int]$nText
        if ($n -ne $ids.Count) { $v6Errors += "${name}[$b]: N=$n mas GERADO tem $($ids.Count) IDs" }
        if ($n -lt 1 -or $n -gt $maximo) { $v6Errors += "${name}[$b]: N=$n fora de 1..$maximo" }
        if ($passosText -ne "$($n - 1)") { $v6Errors += "${name}[$b]: PASSOS=$passosText; esperado $($n - 1)" }
        $last = [int]$ids[$ids.Count - 1]
        $wantParada = if ($last -eq 24) { "PARE" } else { "MAXIMO" }
        if ($parada -cne $wantParada) {
            $v6Errors += "${name}[$b]: PARADA=$parada; esperado $wantParada para ultimo ID $last"
        }
        if ($n -lt $maximo -and $last -ne 24) {
            $v6Errors += "${name}[$b]: parou antes do limite sem token 24"
        }
        $texto = $block[4].Substring("TEXTO=".Length)
        $words = @($texto -split " ")
        if ($texto -ne "" -and $words.Count -ne $n) {
            $v6Errors += "${name}[$b]: TEXTO com $($words.Count) palavras; esperado $n"
        }
        if ($texto -eq "") { $v6Errors += "${name}[$b]: TEXTO= vazio" }
    }
}
Write-Check "V6 N/PASSOS/PARADA/TEXTO coerentes com GERADO e com o limite" $v6Errors

# --- V7: cadeias canonicas e ciclos ---------------------------------------

$v7Errors = @()
$canonicoWant = Get-GeracaoLines $init.W $init.B 9 8
if ($linesByName.ContainsKey("gen_canonico")) {
    if ((@($linesByName["gen_canonico"]) -join "`n") -cne ($canonicoWant -join "`n")) {
        $v7Errors += "gen_canonico diverge do bloco congelado"
    }
} else { $v7Errors += "gen_canonico nao executado" }
if ($linesByName.ContainsKey("gen_ciclo")) {
    $want = @()
    $want += Get-GeracaoLines $init.W $init.B 19 8
    $want += "CICLO=$(Get-Ciclo $g19.Saida $g19.Total)"
    $want += Get-GeracaoLines $init.W $init.B 0 5
    $want += "CICLO=$(Get-Ciclo $g0.Saida $g0.Total)"
    $got = @($linesByName["gen_ciclo"])
    if (($got -join "`n") -cne ($want -join "`n")) {
        $v7Errors += "gen_ciclo diverge do ciclo canonico"
    }
    if ((Get-Ciclo $g19.Saida $g19.Total) -ne 2) { $v7Errors += "ciclo 19 nao tem periodo 2" }
    if ((Get-Ciclo $g0.Saida $g0.Total) -ne 1) { $v7Errors += "ciclo 0 nao tem periodo 1" }
} else { $v7Errors += "gen_ciclo nao executado" }
Write-Check "V7 gen_canonico e gen_ciclo: cadeias canonicas, periodos 2 e 1" $v7Errors

# --- V8: UNK, pare, parada e precedencia ----------------------------------

$v8Errors = @()
$v8Want = @{
    "gen_unk" = Get-GeracaoLines $final.W $final.B 0 16
    "gen_inicial_pare" = Get-GeracaoLines $final.W $final.B 24 16
    "gen_treinado_parada" = Get-GeracaoLines $final.W $final.B 14 16
}
foreach ($name in @($v8Want.Keys | Sort-Object)) {
    if (-not $linesByName.ContainsKey($name)) { $v8Errors += "$name nao executado"; continue }
    if ((@($linesByName[$name]) -join "`n") -cne (@($v8Want[$name]) -join "`n")) {
        $v8Errors += "$name diverge do oraculo"
    }
}
if ($linesByName.ContainsKey("gen_limites")) {
    $want = @()
    $want += Get-GeracaoLines $final.W $final.B 9 1
    $want += Get-GeracaoLines $final.W $final.B 9 4
    $want += Get-GeracaoLines $final.W $final.B 9 5
    $want += Get-GeracaoLines $final.W $final.B 9 64
    $want += Get-GeracaoLines $init.W $init.B 9 64
    $got = @($linesByName["gen_limites"])
    if (($got -join "`n") -cne ($want -join "`n")) {
        $v8Errors += "gen_limites diverge do oraculo"
    }
    if ($got.Count -ne 25) { $v8Errors += "gen_limites com $($got.Count) linhas; esperado 25" }
    if ($got.Count -ge 15 -and $got[13] -cne "PARADA=PARE") {
        $v8Errors += "precedencia PARE/MAXIMO nao observada em maximo=5"
    }
    if ($got.Count -ge 5 -and $got[3] -cne "PARADA=MAXIMO") {
        $v8Errors += "maximo=1 deveria terminar em MAXIMO"
    }
} else { $v8Errors += "gen_limites nao executado" }
Write-Check "V8 UNK, semente 24, parada antecipada e precedencia PARE sobre MAXIMO" $v8Errors

# --- V9: erros e preservacao ----------------------------------------------

$v9Errors = @()
$errosWant = @(
    "ERRO=TOKEN_INVALIDO", "ERRO=TOKEN_INVALIDO",
    "ERRO=LIMITE_INVALIDO", "ERRO=LIMITE_INVALIDO",
    "ERRO=TOKEN_INVALIDO",
    "ERRO=PARAMETROS_INVALIDOS", "ERRO=PARAMETROS_INVALIDOS",
    "ERRO=TOKEN_INVALIDO",
    "INTACTO=OK", "SAIDA_INTACTA=OK"
)
if ($linesByName.ContainsKey("gen_erros")) {
    $got = @($linesByName["gen_erros"])
    if (($got -join "`n") -cne ($errosWant -join "`n")) {
        $v9Errors += "gen_erros diverge da ordem de precedencia ou da preservacao"
    }
    if (-not ($got -ccontains "INTACTO=OK")) { $v9Errors += "INTACTO=OK ausente" }
    if (-not ($got -ccontains "SAIDA_INTACTA=OK")) { $v9Errors += "SAIDA_INTACTA=OK ausente" }
} else { $v9Errors += "gen_erros nao executado" }
Write-Check "V9 erros na ordem TOKEN>LIMITE>PARAMETROS, INTACTO e SAIDA_INTACTA" $v9Errors

# --- V10: determinismo -----------------------------------------------------

$v10Errors = @()
$pathA = Join-Path $GeneratedRoot "gen_determinismo_a.expected"
$pathB = Join-Path $GeneratedRoot "gen_determinismo_b.expected"
if (-not (Test-Path -LiteralPath $pathA) -or -not (Test-Path -LiteralPath $pathB)) {
    $v10Errors += "arquivos de determinismo ausentes"
} else {
    $bytesA = [IO.File]::ReadAllBytes($pathA)
    $bytesB = [IO.File]::ReadAllBytes($pathB)
    if (-not [Convert]::ToBase64String($bytesA).Equals([Convert]::ToBase64String($bytesB), [StringComparison]::Ordinal)) {
        $v10Errors += "gen_determinismo_a.expected difere de gen_determinismo_b.expected"
    }
}
if ($runs.ContainsKey("gen_determinismo_a") -and $runs.ContainsKey("gen_determinismo_b")) {
    $bytesA = $runs["gen_determinismo_a"].Bytes
    $bytesB = $runs["gen_determinismo_b"].Bytes
    if (-not [Convert]::ToBase64String($bytesA).Equals([Convert]::ToBase64String($bytesB), [StringComparison]::Ordinal)) {
        $v10Errors += "saidas dos processos A e B diferem"
    }
    $porA = Join-Path $GeneratedRoot "gen_determinismo_a.por"
    $porB = Join-Path $GeneratedRoot "gen_determinismo_b.por"
    $runA2 = Invoke-CaseRaw ((Resolve-Path -LiteralPath $porA).ProviderPath)
    $runB2 = Invoke-CaseRaw ((Resolve-Path -LiteralPath $porB).ProviderPath)
    if (-not [Convert]::ToBase64String($runA2.Bytes).Equals([Convert]::ToBase64String($bytesA), [StringComparison]::Ordinal)) {
        $v10Errors += "segunda execucao de A difere da primeira"
    }
    if (-not [Convert]::ToBase64String($runB2.Bytes).Equals([Convert]::ToBase64String($bytesB), [StringComparison]::Ordinal)) {
        $v10Errors += "segunda execucao de B difere da primeira"
    }
    if ($runA2.Errors.Length -gt 0 -or $runB2.Errors.Length -gt 0) {
        $v10Errors += "stderr nao vazio na segunda execucao de A/B"
    }
} else {
    $v10Errors += "processos A/B nao executados"
}
Write-Check "V10 determinismo A/B nos .expected e em segunda execucao" $v10Errors

# --- V11: composicao -------------------------------------------------------

$v11Errors = @()
if ($linesByName.ContainsKey("gen_composicao")) {
    $got = @($linesByName["gen_composicao"])
    if (($got -join "`n") -cne (@($expected["gen_composicao"]) -join "`n")) {
        $v11Errors += "gen_composicao diverge do oraculo"
    }
    $rede = @($got | Where-Object { $_ -like "ARGMAX_REDE=*" })
    $treino = @($got | Where-Object { $_ -like "ARGMAX_TREINO=*" })
    if ($rede.Count -ne 1 -or $treino.Count -ne 1) {
        $v11Errors += "linhas ARGMAX_REDE/ARGMAX_TREINO ausentes ou duplicadas"
    } else {
        $redeValue = $rede[0].Substring("ARGMAX_REDE=".Length)
        $treinoValue = $treino[0].Substring("ARGMAX_TREINO=".Length)
        if ($redeValue -cne $treinoValue) { $v11Errors += "ARGMAX_REDE [$redeValue] != ARGMAX_TREINO [$treinoValue]" }
        if ($treinoValue -cne "12 13 14 24") { $v11Errors += "ARGMAX_TREINO [$treinoValue] != 12 13 14 24" }
    }
    if (-not ($got -ccontains "IDS=9 12 13 14 24")) { $v11Errors += "IDS da M1 ausente ou divergente" }
    if (-not ($got -ccontains "EMB16=OK")) { $v11Errors += "EMB16=OK ausente" }
    if (-not ($got -ccontains "PARAMS_INTACTOS=OK")) { $v11Errors += "PARAMS_INTACTOS=OK ausente" }
    if (-not ($got -ccontains "COMPOE=OK")) { $v11Errors += "COMPOE=OK ausente" }
} else { $v11Errors += "gen_composicao nao executado" }
Write-Check "V11 composicao M1->M3->M4->M5->M6 e PARAMS_INTACTOS" $v11Errors

# --- V12: arquivos .expected ----------------------------------------------

$v12Errors = @()
foreach ($file in $expectedFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -eq 0) { $v12Errors += "$($file.Name): vazio"; continue }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $v12Errors += "$($file.Name): BOM"
    }
    if ($bytes[$bytes.Length - 1] -eq 0x0A) { $v12Errors += "$($file.Name): LF final" }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $v12Errors += "$($file.Name): CR"; break }
        if ($b -gt 0x7E) { $v12Errors += ("$($file.Name): byte 0x{0:X2}" -f $b); break }
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $lines = @($text -split "`n")
    foreach ($line in $lines) {
        if ($line -ne $line.Trim()) { $v12Errors += "$($file.Name): espaco nas pontas"; break }
    }
    if ($lines[$lines.Count - 1] -eq "TEXTO=") {
        $v12Errors += "$($file.Name): termina com TEXTO= vazio"
    }
    if ($lines.Count -eq 0 -or $lines[0].Length -eq 0) { $v12Errors += "$($file.Name): primeira linha vazia" }
}
Write-Check "V12 .expected sem LF final, CR, BOM, espaco nas pontas ou TEXTO= final" $v12Errors

# --- V13: mapa completo dos 25 inicios ------------------------------------

$v13Errors = @()
if ($linesByName.ContainsKey("gen_mapa_treinado")) {
    $got = @($linesByName["gen_mapa_treinado"])
    if ($got.Count -ne 25) { $v13Errors += "gen_mapa_treinado com $($got.Count) linhas; esperado 25" }
    $seen = @{}
    foreach ($line in $got) {
        if ($line -notmatch '^MAPA=(0|[1-9][0-9]*) (.+)$') {
            $v13Errors += "linha fora do formato: [$line]"
            continue
        }
        $seed = [int]$Matches[1]
        if ($seed -lt 0 -or $seed -gt 24) { $v13Errors += "semente fora de 0..24: $seed"; continue }
        if ($seen.ContainsKey($seed)) { $v13Errors += "semente repetida: $seed" }
        $seen[$seed] = $true
        $ids = @($Matches[2] -split " ")
        if ([int]$ids[0] -ne $seed) { $v13Errors += "MAPA=$seed comeca em $($ids[0])" }
        if ([int]$ids[$ids.Count - 1] -ne 24) { $v13Errors += "MAPA=$seed nao termina em 24" }
        if ($ids.Count -gt 5) { $v13Errors += "MAPA=$seed tem $($ids.Count) tokens; esperado <= 5" }
        $oracle = Get-Geracao $final.W $final.B $seed 16
        $wantIds = @($oracle.Saida[0..($oracle.Total - 1)])
        if (($ids -join " ") -cne ($wantIds -join " ")) {
            $v13Errors += "MAPA=$seed diverge do oraculo"
        }
    }
    if ($seen.Count -ne 25) { $v13Errors += "sementes cobertas: $($seen.Count); esperado 25" }
} else { $v13Errors += "gen_mapa_treinado nao executado" }
Write-Check "V13 mapa completo dos 25 inicios no estado treinado" $v13Errors

# --- Resumo ----------------------------------------------------------------

Write-Host ""
Write-Host "=== Resultado ==="
Write-Host "Checks:   $script:checks"
Write-Host "Failures: $script:failures"
Write-Host "Casos:    $($expectedCases.Count) executados"

if ($script:failures -gt 0) {
    Write-Host "Verificacao da geracao M6 FALHOU." -ForegroundColor Red
    exit 1
}
Write-Host "Verificacao da geracao M6 aprovada." -ForegroundColor Green
exit 0
