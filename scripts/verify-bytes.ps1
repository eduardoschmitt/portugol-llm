# ---------------------------------------------------------------------------
# Verificacao do formato observavel do tokenizador M1 (P1 aprovado).
# - Form feed (0x0C) no offset 0.
# - Carga ASCII imprimivel, terminada por exatamente um LF (0x0A).
# - Nenhum CR (0x0D) dentro da carga.
# - Epilogo conhecido do interpretador, byte a byte, sem bytes extras.
# - Tabela de id_do_campo com exatamente 24 entradas, na ordem da spec.
# - Fonte ASCII puro.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/tests",
    [string]$SourcePath = "src/tokenizador.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat"
)

$ErrorActionPreference = "Stop"

$script:failures = 0
$script:checks = 0

function Write-Check {
    param([string]$Name, [string[]]$Errors)
    $script:checks++
    if ($Errors.Count -eq 0) {
        Write-Host "[PASS] $Name"
    } else {
        $script:failures++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        foreach ($e in $Errors) { Write-Host "  $e" -ForegroundColor Red }
    }
}

function Get-FirstIndex {
    param([byte[]]$Bytes, [byte]$Value)
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq $Value) { return $i }
    }
    return -1
}

function Get-AsciiBytes {
    param([string]$Text)
    return [Text.Encoding]::ASCII.GetBytes($Text)
}

function Assert-SourceContract {
    $errors = @()
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return @("Fonte nao encontrada: $SourcePath")
    }

    $bytes = [IO.File]::ReadAllBytes($SourcePath)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -gt 0x7F) {
            $errors += ("Byte nao ASCII 0x{0:X2} no offset {1}" -f $bytes[$i], $i)
            break
        }
    }

    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $pattern = 'mesmo_conteudo\(texto, ini, fim, "([a-z]+)"\)\)\s*\{\s*retorne (\d+)\s*\}'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 24) {
        $errors += "Tabela de id_do_campo com $($matches.Count) entradas; esperado 24"
    }

    $expected = @(
        "programa", "funcao", "inicio", "inteiro", "real", "logico", "cadeia", "vazio",
        "se", "senao", "enquanto", "faca", "para", "ate", "passo", "retorne",
        "escreva", "leia", "e", "ou", "nao", "verdadeiro", "falso", "pare"
    )
    $ids = @{}
    for ($i = 0; $i -lt $matches.Count -and $i -lt $expected.Count; $i++) {
        $word = $matches[$i].Groups[1].Value
        $id = [int]$matches[$i].Groups[2].Value
        if ($word -ne $expected[$i]) {
            $errors += "Entrada $($i + 1): palavra '$word', esperado '$($expected[$i])'"
        }
        if ($id -ne ($i + 1)) {
            $errors += "Entrada $($i + 1) ('$word'): ID $id, esperado $($i + 1)"
        }
        $ids[$id] = $word
    }
    if ($ids.Count -ne 24) {
        $errors += "IDs unicos: $($ids.Count); esperado 24"
    }
    foreach ($id in $ids.Keys) {
        if ($id -lt 1 -or $id -gt 24) {
            $errors += "ID fora de 1..24: $id"
        }
    }

    return $errors
}

function Invoke-RawCase {
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

    # Ler bytes crus, sem decodificacao de pagina de codigo.
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

function Assert-RawFormat {
    param([byte[]]$Bytes, [string]$ExpectedText)
    $errors = @()

    if ($Bytes.Length -lt 2) {
        return @("Saida curta demais: $($Bytes.Length) bytes")
    }
    if ($Bytes[0] -ne 0x0C) {
        $errors += ("Offset 0: 0x{0:X2}; esperado 0x0C" -f $Bytes[0])
    }

    $lf = Get-FirstIndex $Bytes 0x0A
    if ($lf -lt 1) {
        return @("LF terminador nao encontrado depois do offset 0")
    }

    for ($i = 1; $i -lt $lf; $i++) {
        $b = $Bytes[$i]
        if ($b -eq 0x0D) {
            $errors += "CR (0x0D) dentro da carga no offset $i"
            break
        }
        if ($b -lt 0x20 -or $b -gt 0x7E) {
            $errors += ("Byte nao imprimivel 0x{0:X2} na carga, offset {1}" -f $b, $i)
            break
        }
    }

    $payload = [Text.Encoding]::ASCII.GetString($Bytes, 1, $lf - 1)
    if ($payload -cnotmatch '^(IDS=(\d+( \d+)*)?|ERRO=(ENTRADA_LONGA|TOKENS_DEMAIS))$') {
        $errors += "Carga fora do contrato: [$payload]"
    }
    if ($null -ne $ExpectedText -and $payload -cne $ExpectedText) {
        $errors += "Carga difere do .expected.`n    Esperado: [$ExpectedText]`n    Obtido:   [$payload]"
    }

    $epilogue = Get-AsciiBytes ("`n`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n")
    $epilogueLength = $epilogue.Length
    $available = $Bytes.Length - $lf
    if ($available -ne $epilogueLength) {
        $errors += "Epilogo com $available bytes; esperado $epilogueLength"
    } else {
        for ($k = 0; $k -lt $epilogueLength; $k++) {
            if ($Bytes[$lf + $k] -ne $epilogue[$k]) {
                $errors += ("Epilogo diverge no byte {0}: 0x{1:X2}; esperado 0x{2:X2}" -f $k, $Bytes[$lf + $k], $epilogue[$k])
                break
            }
        }
    }

    return $errors
}

Write-Host "=== Verificacao de bytes do tokenizador M1 ==="
Write-Host "Fonte:       $SourcePath"
Write-Host "Casos:       $GeneratedRoot"
Write-Host "Interpretador: $InterpreterPath"

Write-Check "fonte: ASCII puro e tabela de 24 entradas" (Assert-SourceContract)

if (-not (Test-Path -LiteralPath $InterpreterPath)) {
    Write-Host "ERROR: interpretador nao encontrado: $InterpreterPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -Path $GeneratedRoot)) {
    Write-Host "ERROR: diretorio de casos nao encontrado: $GeneratedRoot" -ForegroundColor Red
    exit 1
}

$expectedFiles = @(Get-ChildItem -Path $GeneratedRoot -Filter "*.expected" -File | Sort-Object Name)
if ($expectedFiles.Count -eq 0) {
    Write-Host "ERROR: nenhum caso gerado em $GeneratedRoot" -ForegroundColor Red
    exit 1
}

foreach ($expectedFile in $expectedFiles) {
    $name = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
    $porPath = Join-Path $GeneratedRoot ($name + ".por")
    if (-not (Test-Path -LiteralPath $porPath)) {
        Write-Check $name @("Arquivo .por ausente: $porPath")
        continue
    }

    $expectedText = [IO.File]::ReadAllText($expectedFile.FullName)
    $raw = Invoke-RawCase (Resolve-Path -LiteralPath $porPath).ProviderPath
    $errors = @()
    if ($raw.Errors.Length -ne 0) {
        $errors += "stderr com $($raw.Errors.Length) bytes; esperado 0"
    }
    $errors += Assert-RawFormat $raw.Bytes $expectedText
    Write-Check $name $errors
}

Write-Host "`nTotal: $($script:checks) verificacoes, $($script:failures) falha(s)"
if ($script:failures -gt 0) { exit 1 }
Write-Host "Formato de bytes conforme."
exit 0
