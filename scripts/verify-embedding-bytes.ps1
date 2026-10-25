# ---------------------------------------------------------------------------
# Verificacao do formato observavel e dos valores dos embeddings (M3).
# - Fonte ASCII puro, fragmento (sem programa/inicio), constantes canonicas.
# - Conjunto de casos exatamente igual ao esperado (sem faltas nem extras).
# - Saida crua: form feed inicial, carga ASCII com LF, epilogo exato.
# - Oraculo independente: recalcula a formula da spec em [decimal], simula as
#   mutacoes de cada caso e compara valor a valor. Nao le .expected.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-embedding-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/embedding-tests",
    [string]$SourcePath = "src/embeddings.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat"
)

$ErrorActionPreference = "Stop"

$script:failures = 0
$script:checks = 0
$invariant = [Globalization.CultureInfo]::InvariantCulture
$numberPattern = '^-?(0|[1-9][0-9]*)\.[0-9]{1,4}$'
$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"

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

# --- Oraculo: formula da spec, em aritmetica decimal exata -----------------

function New-CanonicalState {
    $state = @{}
    for ($id = 0; $id -lt 25; $id++) {
        $values = New-Object 'decimal[]' 4
        for ($d = 0; $d -lt 4; $d++) {
            $q = (($id * 7 + $d * 3) % 32) - 16
            $values[$d] = [decimal]$q / [decimal]16
        }
        $state[$id] = $values
    }
    return $state
}

function Format-Number {
    param([decimal]$Value)
    return $Value.ToString("0.0###", $invariant)
}

function Format-VectorLine {
    param([int]$Id, [decimal[]]$Values)
    return "VETOR=$Id " + (($Values | ForEach-Object { Format-Number $_ }) -join " ")
}

function Format-PesoLine {
    param([int]$Id, [int]$D, [decimal[]]$Values)
    return "PESO=$Id $D " + (Format-Number $Values[$D])
}

function Format-SummaryLine {
    param([hashtable]$State)
    $all = @()
    foreach ($id in 0..24) { $all += $State[$id] }
    $min = $all[0]
    $max = $all[0]
    foreach ($v in $all) {
        if ($v -lt $min) { $min = $v }
        if ($v -gt $max) { $max = $v }
    }
    $distinct = 0
    for ($a = 0; $a -lt 25; $a++) {
        $isNew = $true
        for ($b = 0; $b -lt $a; $b++) {
            $same = $true
            for ($d = 0; $d -lt 4; $d++) {
                if ($State[$a][$d] -ne $State[$b][$d]) { $same = $false }
            }
            if ($same) { $isNew = $false }
        }
        if ($isNew) { $distinct++ }
    }
    return "RESUMO=25 100 " + (Format-Number $min) + " " + (Format-Number $max) + " " + $distinct
}

function Get-StateForCase {
    param([string]$Name)
    $state = New-CanonicalState
    if ($Name -eq "emb_atualizacao") {
        $state[5][2] = [decimal]0.5
        $state[5][3] = [decimal]1.7
    }
    return $state
}

function Get-ExpectedLines {
    param([string]$Name)
    $s = Get-StateForCase $Name
    switch ($Name) {
        "emb_info" { return @("INFO=25 4 100") }
        "emb_unk" { return @(Format-VectorLine 0 $s[0]) }
        "emb_id_1" { return @(Format-VectorLine 1 $s[1]) }
        "emb_id_24" { return @(Format-VectorLine 24 $s[24]) }
        "emb_amostra_vetores" {
            return @(
                (Format-VectorLine 4 $s[4])
                (Format-VectorLine 9 $s[9])
                (Format-VectorLine 17 $s[17])
            )
        }
        "emb_determinismo_a" { return @(0..24 | ForEach-Object { Format-VectorLine $_ $s[$_] }) }
        "emb_determinismo_b" { return @(0..24 | ForEach-Object { Format-VectorLine $_ $s[$_] }) }
        "emb_peso" {
            return @(
                (Format-PesoLine 0 0 $s[0])
                (Format-PesoLine 4 1 $s[4])
                (Format-PesoLine 9 0 $s[9])
                (Format-PesoLine 16 0 $s[16])
                (Format-PesoLine 24 3 $s[24])
                (Format-PesoLine 11 1 $s[11])
                (Format-PesoLine 3 2 $s[3])
            )
        }
        "emb_validadores" {
            return @(
                "VALIDO=0", "VALIDO=1", "VALIDO=1", "VALIDO=0",
                "VALIDO=0", "VALIDO=1", "VALIDO=1", "VALIDO=0"
            )
        }
        "emb_layout" { return @("LAYOUT=OK") }
        "emb_id_invalido_neg" { return @("ERRO=ID_INVALIDO") }
        "emb_id_invalido_25" { return @("ERRO=ID_INVALIDO") }
        "emb_dim_invalida_neg" { return @("ERRO=DIMENSAO_INVALIDA") }
        "emb_dim_invalida_4" { return @("ERRO=DIMENSAO_INVALIDA") }
        "emb_ambos_invalidos" { return @("ERRO=ID_INVALIDO") }
        "emb_apos_erro" {
            return @(
                "ERRO=ID_INVALIDO"
                (Format-VectorLine 0 $s[0])
            )
        }
        "emb_atualizacao" {
            return @(
                (Format-VectorLine 5 $s[5])
                (Format-VectorLine 6 $s[6])
            )
        }
        "emb_reinicializacao" { return @(Format-VectorLine 5 $s[5]) }
        "emb_resumo" { return @(Format-SummaryLine $s) }
        default { Fail "Caso sem oraculo definido: $Name" }
    }
}

# --- Fonte -----------------------------------------------------------------

$expectedCases = @(
    "emb_amostra_vetores",
    "emb_apos_erro",
    "emb_atualizacao",
    "emb_ambos_invalidos",
    "emb_determinismo_a",
    "emb_determinismo_b",
    "emb_dim_invalida_4",
    "emb_dim_invalida_neg",
    "emb_id_1",
    "emb_id_24",
    "emb_id_invalido_25",
    "emb_id_invalido_neg",
    "emb_info",
    "emb_layout",
    "emb_peso",
    "emb_reinicializacao",
    "emb_resumo",
    "emb_unk",
    "emb_validadores"
)

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    Fail "fragmento nao encontrado: $SourcePath"
}
$sourceBytes = [IO.File]::ReadAllBytes($SourcePath)
if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) {
    Fail "BOM encontrado em $SourcePath"
}
foreach ($b in $sourceBytes) {
    if ($b -eq 0x09 -or $b -eq 0x0A -or $b -eq 0x0D) { continue }
    if ($b -lt 0x20 -or $b -gt 0x7E) {
        Fail ("byte nao ASCII 0x{0:X2} em {1}" -f $b, $SourcePath)
    }
}
$sourceText = [Text.Encoding]::ASCII.GetString($sourceBytes)
if ($sourceText -match '(?m)^\s*programa\b') { Fail "o fragmento declara 'programa'" }
if ($sourceText -match '(?m)^\s*funcao\s+inicio\b') { Fail "o fragmento declara 'inicio'" }
if ($sourceText -match '(?m)^\s*inclua\b') { Fail "o fragmento inclui biblioteca" }
if ($sourceText -match 'aleatorio') { Fail "o fragmento usa aleatoriedade" }
foreach ($required in @("EMB_TAM_VOCAB = 25", "EMB_DIM = 4", "EMB_TOTAL = 100", "16.0")) {
    if ($sourceText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        Fail "fragmento nao contem: $required"
    }
}

if (-not (Test-Path -LiteralPath $InterpreterPath)) {
    Fail "interpretador nao encontrado: $InterpreterPath"
}
if (-not (Test-Path -Path $GeneratedRoot)) {
    Fail "diretorio de casos nao encontrado: $GeneratedRoot"
}

$expectedFiles = @(Get-ChildItem -Path $GeneratedRoot -Filter "*.expected" -File | Sort-Object Name)
$actualNames = @($expectedFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
$sortedExpected = @($expectedCases | Sort-Object)
$sortedActual = @($actualNames | Sort-Object)
if (($sortedActual -join "|") -cne ($sortedExpected -join "|")) {
    Fail ("conjunto de casos diverge.`n  Esperado: " + ($sortedExpected -join ", ") + "`n  Obtido:   " + ($sortedActual -join ", "))
}

Write-Host "=== Verificacao de bytes e valores dos embeddings M3 ==="
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

function Assert-NumericFields {
    param([string]$Line, [string[]]$Errors)
    $eq = $Line.IndexOf("=")
    if ($eq -lt 1) { $Errors += "linha sem '=': [$Line]"; return }
    $tag = $Line.Substring(0, $eq)
    $parts = @($Line.Substring($eq + 1) -split " ")
    switch ($tag) {
        "VETOR" {
            if ($parts.Count -ne 5) { $Errors += "VETOR com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^\d+$') { $Errors += "ID invalido em [$Line]" }
            foreach ($v in $parts[1..4]) {
                if ($v -notmatch $numberPattern) { $Errors += "numero fora da gramatica em [$Line]: $v" }
                else { [void][decimal]::Parse($v, $invariant) }
            }
        }
        "PESO" {
            if ($parts.Count -ne 3) { $Errors += "PESO com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -notmatch '^\d+$' -or $parts[1] -notmatch '^\d+$') { $Errors += "indices invalidos em [$Line]" }
            if ($parts[2] -notmatch $numberPattern) { $Errors += "numero fora da gramatica em [$Line]: $($parts[2])" }
            else { [void][decimal]::Parse($parts[2], $invariant) }
        }
        "RESUMO" {
            if ($parts.Count -ne 5) { $Errors += "RESUMO com $($parts.Count) campos apos '=': [$Line]"; return }
            if ($parts[0] -ne "25" -or $parts[1] -ne "100") { $Errors += "dimensoes do resumo invalidas: [$Line]" }
            foreach ($v in $parts[2..3]) {
                if ($v -notmatch $numberPattern) { $Errors += "numero fora da gramatica em [$Line]: $v" }
                else { [void][decimal]::Parse($v, $invariant) }
            }
            if ($parts[4] -notmatch '^\d+$') { $Errors += "distintos invalido em [$Line]" }
        }
        "INFO" {
            if ($Line -cne "INFO=25 4 100") { $Errors += "INFO invalido: [$Line]" }
        }
        "VALIDO" {
            if ($Line -notmatch '^VALIDO=[01]$') { $Errors += "VALIDO invalido: [$Line]" }
        }
        "LAYOUT" {
            if ($Line -notmatch '^LAYOUT=(OK|FAIL)$') { $Errors += "LAYOUT invalido: [$Line]" }
        }
        "ERRO" {
            if ($Line -notmatch '^ERRO=(ID_INVALIDO|DIMENSAO_INVALIDA)$') { $Errors += "ERRO invalido: [$Line]" }
        }
        default {
            $Errors += "linha fora do contrato: [$Line]"
        }
    }
}

$epilogueBytes = [Text.Encoding]::ASCII.GetBytes($epilogue)
$suffixLength = $epilogueBytes.Length

foreach ($name in $expectedCases) {
    $errors = @()
    $porPath = Join-Path $GeneratedRoot "$name.por"
    if (-not (Test-Path -LiteralPath $porPath)) {
        Write-Check $name @("arquivo ausente: $porPath")
        continue
    }

    $run = Invoke-CaseRaw $porPath
    if ($run.Errors.Length -gt 0) {
        $errors += ("stderr nao vazio: " + [Text.Encoding]::GetEncoding(1252).GetString($run.Errors))
    }
    $bytes = $run.Bytes
    if ($bytes.Length -lt 1 + $suffixLength) {
        $errors += "saida curta demais: $($bytes.Length) bytes"
    } else {
        if ($bytes[0] -ne 0x0C) { $errors += ("offset 0: 0x{0:X2}; esperado 0x0C" -f $bytes[0]) }
        $tailStart = $bytes.Length - $suffixLength
        for ($k = 0; $k -lt $suffixLength; $k++) {
            if ($bytes[$tailStart + $k] -ne $epilogueBytes[$k]) {
                $errors += ("epilogo diverge no byte {0}: 0x{1:X2}; esperado 0x{2:X2}" -f $k, $bytes[$tailStart + $k], $epilogueBytes[$k])
                break
            }
        }
        for ($i = 1; $i -lt $tailStart; $i++) {
            $b = $bytes[$i]
            if ($b -eq 0x0D) { $errors += "CR dentro da carga no offset $i"; break }
            if ($b -lt 0x20 -or $b -gt 0x7E) {
                if ($b -ne 0x0A) { $errors += ("byte fora da carga ASCII 0x{0:X2} no offset {1}" -f $b, $i); break }
            }
        }
        $payload = [Text.Encoding]::ASCII.GetString($bytes, 1, $tailStart - 1)
        if (-not $payload.EndsWith("`n")) {
            $errors += "carga nao termina em LF"
        } else {
            $body = $payload.Substring(0, $payload.Length - 1)
            $lines = @($body -split "`n")
            $expectedLines = @(Get-ExpectedLines $name)
            if ($lines.Count -ne $expectedLines.Count) {
                $errors += "numero de linhas: $($lines.Count); esperado $($expectedLines.Count)"
            }
            $limit = [Math]::Min($lines.Count, $expectedLines.Count)
            for ($i = 0; $i -lt $limit; $i++) {
                if ($lines[$i] -cne $expectedLines[$i]) {
                    $errors += "linha $($i + 1) difere.`n    Esperado: [$($expectedLines[$i])]`n    Obtido:   [$($lines[$i])]"
                }
                Assert-NumericFields $lines[$i] $errors
            }
        }
    }

    Write-Check $name $errors
}

Write-Host ""
Write-Host "Total: $script:checks verificacoes, $script:failures falha(s)"
if ($script:failures -gt 0) {
    exit 1
}
Write-Host "Formato e valores conforme."
exit 0
