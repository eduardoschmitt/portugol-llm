<#
.SYNOPSIS
    Portugol test runner - executes .por test cases and validates output.
.DESCRIPTION
    Discovers test cases in tests/ directory, runs them via portugol-console.bat,
    and validates output against expected results. Handles interpreter quirks:
    - Always returns exit code 0 (cannot rely on process exit code)
    - Outputs form feed character at start
    - Outputs "Programa finalizado" and "Pressione ENTER para continuar" at end
    - Requires input piped to avoid blocking on ENTER prompt
#>

param(
    [string]$TestsRoot = "tests",
    [switch]$SelfTest,
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat"
)

$ErrorActionPreference = "Stop"

# Test result tracking
$passed = 0
$failed = 0
$results = @()

function Write-Header {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Result {
    param([string]$Name, [bool]$Passed, [string]$Details = "")
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "[$status] $Name" -ForegroundColor $color
    if ($Details) { Write-Host "  $Details" -ForegroundColor Gray }
    $script:results += [pscustomobject]@{ Name = $Name; Passed = $Passed; Details = $Details }
}

function Normalize-Output {
    param([string]$Output)
    # Remove form feed character
    $Output = $Output -replace '^\f', ''
    # Remove trailing "Programa finalizado" and "Pressione ENTER para continuar" (success case) - MUST BE FIRST
    $Output = $Output -replace "`r?`nPrograma finalizado`r?`n`r?`nPressione ENTER para continuar`r?$", ''
    # Remove "Pressione ENTER para continuar" and surrounding newlines (error case)
    $Output = $Output -replace "`r?`n?Pressione ENTER para continuar`r?`n", ''
    $Output = $Output -replace "`r?`n$", ''
    return $Output.Trim()
}

function Run-PortugolTest {
    param(
        [string]$TestFile,
        # Usar [object] em vez de [string] para preservar $null — parâmetros [string]
        # convertem $null para "" silenciosamente, tornando a distinção impossível.
        [object]$ExpectedOutput = $null,
        [object]$ExpectedError  = $null,
        # Recebe o caminho do interpretador explicitamente para permitir o cenário
        # "unavailable-interpreter" sem depender da variável de escopo externo.
        [string]$InterpreterPath = $script:InterpreterPath
    )

    $testName = [IO.Path]::GetFileNameWithoutExtension($TestFile)
    $fullPath = Resolve-Path -Path $TestFile -ErrorAction SilentlyContinue

    # For tests expecting "file not found" error, don't require file to exist
    $expectMissingFile = $ExpectedError -and $ExpectedError -match "não existe"
    if (-not $fullPath -and -not $expectMissingFile) {
        Write-Result $testName $false "Test file not found: $TestFile"
        return $false
    }

    # Use provided path or resolved path
    $interpreterArg = if ($fullPath) { $fullPath.ProviderPath } else { $TestFile }

    if (-not (Test-Path -Path $InterpreterPath)) {
        $notFoundMsg = "Interpreter not found: $InterpreterPath"
        # Permite que o caso de teste "unavailable-interpreter" valide a detecção
        # de interpretador ausente como uma condição esperada.
        if ($ExpectedError -ne $null -and $notFoundMsg -match [regex]::Escape([string]$ExpectedError)) {
            Write-Result $testName $true "Condição esperada confirmada: $ExpectedError"
            return $true
        }
        Write-Result $testName $false $notFoundMsg
        return $false
    }

    # Run interpreter with piped input to avoid blocking on "Pressione ENTER"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $InterpreterPath
    $psi.Arguments = "`"$interpreterArg`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    # O interpretador (JVM bundled do Portugol Studio) usa a página de código ANSI
    # da plataforma para stdout/stderr — não a página OEM do console.
    # Evidência: bytes capturados via Latin-1 lossless mostram 0xE3='ã', 0xE7='ç',
    # que correspondem a CP1252 (ANSI), não a CP850 (OEM).
    # Detectamos a página ANSI dinamicamente para não assumir um valor fixo.
    $ansiPage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
    $interpreterEncoding = [System.Text.Encoding]::GetEncoding($ansiPage)
    $psi.StandardOutputEncoding = $interpreterEncoding
    $psi.StandardErrorEncoding  = $interpreterEncoding

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.WriteLine(" ")
    $proc.StandardInput.Close()
    $output = $proc.StandardOutput.ReadToEnd()
    $errOutput = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode

    # Combine stdout and stderr for analysis
    $output = $output + $errOutput

    $cleanOutput = Normalize-Output $output

    # Determine test type and validate
    if ($ExpectedOutput -ne $null) {
        # Positive test: expect specific output
        if ($cleanOutput -ceq $ExpectedOutput) {
            Write-Result $testName $true
            return $true
        } else {
            Write-Result $testName $false "Output mismatch.`nExpected: [$ExpectedOutput]`nActual:   [$cleanOutput]"
            return $false
        }
    } elseif ($ExpectedError -ne $null) {
        # Negative test: expect error message in output
        if ($cleanOutput -match [regex]::Escape($ExpectedError)) {
            Write-Result $testName $true "Expected error detected: $ExpectedError"
            return $true
        } else {
            Write-Result $testName $false "Expected error not found.`nExpected error: $ExpectedError`nActual output: [$cleanOutput]"
            return $false
        }
    } else {
        # No expectation defined - treat as failure
        Write-Result $testName $false "No expectation defined for test"
        return $false
    }
}

# Main execution
Write-Header "Portugol Test Runner"

# Verify interpreter exists
if (-not (Test-Path -Path $InterpreterPath)) {
    Write-Error "Interpreter not found at: $InterpreterPath"
    exit 1
}

Write-Host "Interpreter: $InterpreterPath"
Write-Host "Tests root:  $TestsRoot"

# Define test cases explicitly
$testCases = @(
    @{
        Name = "smoke"
        File = "tests/smoke.por"
        ExpectedOutput = "PORTUGOL_OK`nRESULTADO=30"
    }
    @{
        Name = "division-by-zero"
        File = "tests/falha.por"
        ExpectedError = "divisão por zero"
    }
    @{
        Name = "syntax-error"
        File = "tests/syntax_error.por"
        ExpectedError = "expressão não foi iniciada corretamente"
    }
    @{
        Name = "nonexistent-file"
        File = "tests/nao_existe.por"
        ExpectedError = "não existe"
    }
    @{
        Name = "unavailable-interpreter"
        File = "tests/smoke.por"
        InterpreterPath = "C:\Nonexistent\portugol-console.bat"
        ExpectedError = "Interpreter not found"
    }
)

# Gerar e anexar os casos do tokenizador (M1). O autoteste ignora os gerados.
if (-not $SelfTest) {
    $builderPath = Join-Path $PSScriptRoot "build-tests.ps1"
    try {
        & $builderPath
    } catch {
        Write-Host "ERROR: test builder failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $generatedRoot = "temp/tests"
    $generated = @(Get-ChildItem -Path $generatedRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($generated.Count -eq 0) {
        Write-Host "ERROR: no generated test cases found in $generatedRoot" -ForegroundColor Red
        exit 1
    }

    foreach ($expectedFile in $generated) {
        $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
        $testCases += @{
            Name = $caseName
            File = "$generatedRoot/$caseName.por"
            ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
        }
    }

    # Gerar e anexar os casos de embeddings (M3). Diretorio proprio para nao
    # interferir na verificacao de bytes da M1, que varre temp/tests.
    $embeddingBuilder = Join-Path $PSScriptRoot "build-embedding-tests.ps1"
    try {
        & $embeddingBuilder
    } catch {
        Write-Host "ERROR: embedding test builder failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $embeddingRoot = "temp/embedding-tests"
    $embeddingGenerated = @(Get-ChildItem -Path $embeddingRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($embeddingGenerated.Count -eq 0) {
        Write-Host "ERROR: no embedding test cases found in $embeddingRoot" -ForegroundColor Red
        exit 1
    }

    foreach ($expectedFile in $embeddingGenerated) {
        $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
        $testCases += @{
            Name = $caseName
            File = "$embeddingRoot/$caseName.por"
            ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
        }
    }

    # Gerar e anexar os casos da rede neural (M4). Diretorio proprio para nao
    # interferir nas verificacoes de bytes da M1 nem da M3.
    $networkBuilder = Join-Path $PSScriptRoot "build-network-tests.ps1"
    try {
        & $networkBuilder
    } catch {
        Write-Host "ERROR: network test builder failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $networkRoot = "temp/network-tests"
    $networkGenerated = @(Get-ChildItem -Path $networkRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($networkGenerated.Count -eq 0) {
        Write-Host "ERROR: no network test cases found in $networkRoot" -ForegroundColor Red
        exit 1
    }

    foreach ($expectedFile in $networkGenerated) {
        $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
        $testCases += @{
            Name = $caseName
            File = "$networkRoot/$caseName.por"
            ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
        }
    }
}

if ($SelfTest) {
    # Este modo deve falhar com exit code 1: comprova que o runner
    # rejeita uma saída diferente da esperada.
    $testCases = @(
        @{
            Name = "unexpected-output"
            File = "tests/unexpected.por"
            ExpectedOutput = "THIS_WILL_NOT_MATCH"
        }
    )
}

foreach ($tc in $testCases) {
    $interpreter = if ($tc.ContainsKey('InterpreterPath')) { $tc.InterpreterPath } else { $InterpreterPath }
    $file = $tc.File
    $expectedOut = if ($tc.ContainsKey('ExpectedOutput')) { $tc.ExpectedOutput } else { $null }
    $expectedErr = if ($tc.ContainsKey('ExpectedError')) { $tc.ExpectedError } else { $null }

    $result = Run-PortugolTest -TestFile $file -ExpectedOutput $expectedOut -ExpectedError $expectedErr -InterpreterPath $interpreter
    if ($result) { $passed++ } else { $failed++ }
}

# Summary
Write-Header "Summary"
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"
Write-Host "Total:  $($passed + $failed)"

if ($failed -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $results | Where-Object { -not $_.Passed } | ForEach-Object { Write-Host "  - $($_.Name): $($_.Details)" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "`nAll tests passed." -ForegroundColor Green
    exit 0
}