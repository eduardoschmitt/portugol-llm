<#
.SYNOPSIS
    Executa os casos da avaliacao M9 e compara bytes.
.DESCRIPTION
    Cada caso .por concatenado pelo builder e executado no interpretador do
    Portugol Studio. A saida crua perde um 0x0C inicial e o epilogo exato
    `\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n`; o
    restante deve ser byte a byte igual ao .expected gerado pelo O1.

    Tambem verifica:
    - eval_separacao contra eval-datasets.ps1;
    - ASCII/LF, sem CR e sem espacos a direita;
    - determinismo A/B (bytes e SHA-256 iguais);
    - stderr vazio em todos os casos.

    Uso:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-evaluation.ps1
#>

param(
    [string]$CasesRoot = "temp/evaluation-tests",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat",
    [string]$DatasetsPath = "scripts/eval-datasets.ps1",
    [string]$LogPath = "temp/eval-run.log"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

$casesRootFull = Join-Path $root $CasesRoot
$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"

function Get-EvalCaseOutput {
    param([string]$Path)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $InterpreterPath
    $psi.Arguments = '"' + $Path + '"'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.WriteLine(' ')
    $proc.StandardInput.Close()
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return [pscustomobject]@{ Output = $out; Error = $err; ExitCode = $proc.ExitCode }
}

function ConvertTo-EvalNormalizedBytes {
    param([string]$Output)
    $text = $Output
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0x0C) {
        $text = $text.Substring(1)
    }
    if ($text.EndsWith($epilogue)) {
        $text = $text.Substring(0, $text.Length - $epilogue.Length)
    }
    return [Text.Encoding]::ASCII.GetBytes($text)
}

function Test-EvalContractBytes {
    param([byte[]]$Bytes)
    $errors = New-Object System.Collections.Generic.List[string]
    if ($Bytes.Length -eq 0) {
        $errors.Add("vazio")
        return $errors
    }
    if ($Bytes[$Bytes.Length - 1] -ne 0x0A) {
        $errors.Add("sem LF final")
    }
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $b = $Bytes[$i]
        if ($b -eq 0x0D) { $errors.Add("contem CR"); break }
        if ($b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) {
            $errors.Add(("byte fora de ASCII/LF: 0x{0:X2} em {1}" -f $b, $i))
            break
        }
    }
    $text = [Text.Encoding]::ASCII.GetString($Bytes)
    foreach ($line in $text.TrimEnd("`n").Split("`n")) {
        if ($line.EndsWith(" ") -or $line.EndsWith("`t")) {
            $errors.Add("espaco a direita: '$line'")
            break
        }
    }
    return $errors
}

function Get-EvalSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Test-EvalBytesEqual {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) {
        if ($A[$i] -ne $B[$i]) { return $false }
    }
    return $true
}

function Assert-EvalSeparacao {
    $expectedPath = Join-Path $casesRootFull "eval_separacao.expected"
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        return @("eval_separacao.expected ausente; rode build-evaluation-tests.ps1")
    }
    $saved = $null
    try {
        $script:EvalDatasetsQuiet = $true
        . (Join-Path $root $DatasetsPath) -Quiet
        $r = Assert-EvalDataset
        $lines = New-Object System.Collections.Generic.List[string]
        if ($r.Errors.Count -eq 0) { $lines.Add("SEPARACAO=OK") }
        else {
            $lines.Add("SEPARACAO=FALHA")
            foreach ($e in $r.Errors) { $lines.Add("ERRO=$e") }
        }
        $lines.Add("HOLDOUT_BYTES=$($r.Bytes)")
        $lines.Add("HOLDOUT_LINHAS=$($r.Lines)")
        $lines.Add("HOLDOUT_SHA256=$($r.Sha256)")
        $lines.Add("A=$($r.A) B_VISTO=$($r.BSeen) B_INEDITO=$($r.BUnseen) C=$($r.C) C_SEM_PARE=$($r.CSemPare) D=$($r.D)")
        $lines.Add("VAZAMENTOS_CONTEXTO=$($r.CLeaks)")
        $lines.Add("VAZAMENTOS_SUFIXO2=$($r.SuffixLeaks)")
        $lines.Add("ALVOS24 A=$($r.A24) B=$($r.B24) C=$($r.C24) D=$($r.D24)")
        $lines.Add("MEMORIZACAO A=$($r.MemA) B=$($r.MemB) C=$($r.MemC) D=$($r.MemD)")
        $actual = (($lines -join "`n") + "`n")
    } catch {
        return @("eval_separacao: $($_.Exception.Message)")
    }
    $expected = [IO.File]::ReadAllText($expectedPath)
    if ($actual -cne $expected) {
        return @("eval_separacao: saida difere do .expected")
    }
    return @()
}

$results = New-Object System.Collections.Generic.List[object]
$log = New-Object System.Collections.Generic.List[string]

# Separacao (PowerShell).
$errors = Assert-EvalSeparacao
$results.Add([pscustomobject]@{ Name = "eval_separacao"; Ok = ($errors.Count -eq 0); Errors = $errors })
$log.Add(("eval_separacao {0}" -f $(if ($errors.Count -eq 0) { "PASS" } else { "FAIL: " + ($errors -join "; ") })))

$porCases = @(
    "eval_nao_treinado",
    "eval_treinado",
    "eval_baselines",
    "eval_controle_rotulo",
    "eval_controle_ordem",
    "eval_ordem_permutacoes",
    "eval_limites",
    "eval_determinismo_a",
    "eval_determinismo_b"
)

$outputs = @{}
foreach ($name in $porCases) {
    $porPath = Join-Path $casesRootFull "$name.por"
    $expectedPath = Join-Path $casesRootFull "$name.expected"
    $caseErrors = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $porPath)) { $caseErrors.Add("$name.por ausente") }
    if (-not (Test-Path -LiteralPath $expectedPath)) { $caseErrors.Add("$name.expected ausente") }
    if ($caseErrors.Count -eq 0) {
        $expectedBytes = [IO.File]::ReadAllBytes($expectedPath)
        $expectedErrors = Test-EvalContractBytes $expectedBytes
        foreach ($e in $expectedErrors) { $caseErrors.Add(".expected: $e") }
        $run = Get-EvalCaseOutput $porPath
        if ($run.Error.Length -gt 0) { $caseErrors.Add("stderr: $($run.Error.Trim())") }
        $actualBytes = ConvertTo-EvalNormalizedBytes $run.Output
        $actualErrors = Test-EvalContractBytes $actualBytes
        foreach ($e in $actualErrors) { $caseErrors.Add("saida: $e") }
        if ($actualBytes.Length -ne $expectedBytes.Length) {
            $caseErrors.Add("bytes: $($actualBytes.Length); esperado $($expectedBytes.Length)")
        } elseif (-not (Test-EvalBytesEqual $actualBytes $expectedBytes)) {
            $caseErrors.Add("conteudo difere do .expected")
        }
        $outputs[$name] = $actualBytes
    }
    $results.Add([pscustomobject]@{ Name = $name; Ok = ($caseErrors.Count -eq 0); Errors = $caseErrors })
    $log.Add(("{0} {1}" -f $name, $(if ($caseErrors.Count -eq 0) { "PASS" } else { "FAIL: " + ($caseErrors -join "; ") })))
}

# Determinismo A/B.
if ($outputs.ContainsKey("eval_determinismo_a") -and $outputs.ContainsKey("eval_determinismo_b")) {
    $ha = Get-EvalSha256 $outputs["eval_determinismo_a"]
    $hb = Get-EvalSha256 $outputs["eval_determinismo_b"]
    $detErrors = @()
    if ($ha -cne $hb) { $detErrors += "SHA-256 A=$ha B=$hb" }
    if (-not (Test-EvalBytesEqual $outputs["eval_determinismo_a"] $outputs["eval_determinismo_b"])) {
        $detErrors += "bytes A e B diferem"
    }
    $results.Add([pscustomobject]@{ Name = "eval_determinismo_bytes"; Ok = ($detErrors.Count -eq 0); Errors = $detErrors })
    $log.Add(("eval_determinismo_bytes {0} sha={1}" -f $(if ($detErrors.Count -eq 0) { "PASS" } else { "FAIL" }), $ha))
}

$passed = @($results | Where-Object { $_.Ok }).Count
$total = $results.Count
$log.Add(("RESULT Passed: {0} Total: {1}" -f $passed, $total))

$logPathFull = Join-Path $root $LogPath
$logDir = Split-Path -Parent $logPathFull
if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    [void](New-Item -ItemType Directory -Path $logDir)
}
[IO.File]::WriteAllText($logPathFull, (($log -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))

foreach ($r in $results) {
    if (-not $r.Ok) {
        Write-Host ("FAIL {0}" -f $r.Name)
        foreach ($e in $r.Errors) { Write-Host ("  {0}" -f $e) }
    }
}
Write-Host ("Passed: {0}" -f $passed)
Write-Host ("Total: {0}" -f $total)
if ($passed -ne $total) { exit 1 }
exit 0
