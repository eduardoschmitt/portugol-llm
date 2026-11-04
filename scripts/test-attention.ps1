<#
.SYNOPSIS
    Executa os casos da atencao causal minima (M10) e compara bytes.
.DESCRIPTION
    Cada caso .por concatenado pelo builder e executado no interpretador do
    Portugol Studio. A saida crua perde um 0x0C inicial e o epilogo exato
    `\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n`; o
    restante deve ser byte a byte igual ao .expected gerado pelo O1.

    T1-T14 sao 14 verificacoes. T11 roda dois arquivos (at_determinismo_a e
    at_determinismo_b), compara cada um com o .expected e exige bytes e
    SHA-256 identicos entre os dois.

    Tambem verifica ASCII/LF, ausencia de CR e de espacos a direita, stderr
    vazio e exit code 0 em todas as execucoes.

    Uso:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-attention.ps1
#>

param(
    [string]$CasesRoot = "temp/attention-tests",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat",
    [string]$LogPath = "temp/attention-run.log"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

$casesRootFull = Join-Path $root $CasesRoot
$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"

function Get-AtCaseOutput {
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

function ConvertTo-AtNormalizedBytes {
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

function Test-AtContractBytes {
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

function Get-AtSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Test-AtBytesEqual {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) {
        if ($A[$i] -ne $B[$i]) { return $false }
    }
    return $true
}

function Invoke-AtFile {
    param([string]$Name, [string]$ExpectedName)
    $errors = New-Object System.Collections.Generic.List[string]
    $bytes = $null
    $porPath = Join-Path $casesRootFull "$Name.por"
    $expectedPath = Join-Path $casesRootFull "$ExpectedName.expected"
    if (-not (Test-Path -LiteralPath $porPath)) {
        $errors.Add("$Name.por ausente")
        return [pscustomobject]@{ Errors = $errors; Bytes = $bytes }
    }
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        $errors.Add("$ExpectedName.expected ausente")
        return [pscustomobject]@{ Errors = $errors; Bytes = $bytes }
    }
    $expectedBytes = [IO.File]::ReadAllBytes($expectedPath)
    foreach ($e in (Test-AtContractBytes $expectedBytes)) { $errors.Add(".expected: $e") }
    $run = Get-AtCaseOutput $porPath
    if ($run.Error.Length -gt 0) { $errors.Add("stderr: $($run.Error.Trim())") }
    if ($run.ExitCode -ne 0) { $errors.Add("exit code $($run.ExitCode)") }
    $actualBytes = ConvertTo-AtNormalizedBytes $run.Output
    $bytes = $actualBytes
    foreach ($e in (Test-AtContractBytes $actualBytes)) { $errors.Add("saida: $e") }
    if ($actualBytes.Length -ne $expectedBytes.Length) {
        $errors.Add("bytes: $($actualBytes.Length); esperado $($expectedBytes.Length)")
    } elseif (-not (Test-AtBytesEqual $actualBytes $expectedBytes)) {
        $errors.Add("conteudo difere do .expected")
    }
    return [pscustomobject]@{ Errors = $errors; Bytes = $bytes }
}

$results = New-Object System.Collections.Generic.List[object]
$log = New-Object System.Collections.Generic.List[string]

$checks = @(
    [pscustomobject]@{ Name = "at_limites"; Files = @("at_limites") },
    [pscustomobject]@{ Name = "at_mascara"; Files = @("at_mascara") },
    [pscustomobject]@{ Name = "at_padding"; Files = @("at_padding") },
    [pscustomobject]@{ Name = "at_pesos"; Files = @("at_pesos") },
    [pscustomobject]@{ Name = "at_exemplo"; Files = @("at_exemplo") },
    [pscustomobject]@{ Name = "at_nao_treinado"; Files = @("at_nao_treinado") },
    [pscustomobject]@{ Name = "at_uniforme"; Files = @("at_uniforme") },
    [pscustomobject]@{ Name = "at_recencia"; Files = @("at_recencia") },
    [pscustomobject]@{ Name = "at_treinado"; Files = @("at_treinado") },
    [pscustomobject]@{ Name = "at_ordem"; Files = @("at_ordem") },
    [pscustomobject]@{ Name = "at_determinismo"; Files = @("at_determinismo_a", "at_determinismo_b") },
    [pscustomobject]@{ Name = "at_causal_futuro"; Files = @("at_causal_futuro") },
    [pscustomobject]@{ Name = "at_overflow"; Files = @("at_overflow") },
    [pscustomobject]@{ Name = "at_layout"; Files = @("at_layout") }
)

$outputs = @{}
foreach ($check in $checks) {
    $caseErrors = New-Object System.Collections.Generic.List[string]
    foreach ($file in $check.Files) {
        $r = Invoke-AtFile $file $file
        foreach ($e in $r.Errors) { $caseErrors.Add("$file`: $e") }
        if ($null -ne $r.Bytes) { $outputs[$file] = $r.Bytes }
    }
    if ($check.Name -ceq "at_determinismo") {
        if ($outputs.ContainsKey("at_determinismo_a") -and $outputs.ContainsKey("at_determinismo_b")) {
            $ha = Get-AtSha256 $outputs["at_determinismo_a"]
            $hb = Get-AtSha256 $outputs["at_determinismo_b"]
            if ($ha -cne $hb) { $caseErrors.Add("SHA-256 A=$ha B=$hb") }
            if (-not (Test-AtBytesEqual $outputs["at_determinismo_a"] $outputs["at_determinismo_b"])) {
                $caseErrors.Add("bytes A e B diferem")
            }
        } else {
            $caseErrors.Add("saidas A/B ausentes")
        }
    }
    $results.Add([pscustomobject]@{ Name = $check.Name; Ok = ($caseErrors.Count -eq 0); Errors = $caseErrors })
    $log.Add(("{0} {1}" -f $check.Name, $(if ($caseErrors.Count -eq 0) { "PASS" } else { "FAIL: " + ($caseErrors -join "; ") })))
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
