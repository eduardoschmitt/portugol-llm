<#
.SYNOPSIS
    Gera os casos .por e .expected do tokenizador em temp/tests/.
.DESCRIPTION
    Fonte unica de verdade para (construcao da entrada + saida esperada).
    Cada caso e gerado concatenando src/tokenizador.por (fragmento) com um
    driver que chama tokenizar(). Tudo e escrito em UTF-8 sem BOM e os bytes
    gravados sao validados, conforme D13.
#>

param(
    [string]$SourcePath = "src/tokenizador.por",
    [string]$OutputRoot = "temp/tests"
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

function Add-PortugolIndent {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $indented = foreach ($line in $lines) {
        if ($line -eq "") { "" } else { "        " + $line }
    }
    return ($indented -join "`n")
}

function Assert-ByteSequence {
    param([string]$Path, [byte[]]$Expected, [string]$Label)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($Expected.Length -eq 0 -or $bytes.Length -lt $Expected.Length) {
        throw "Sequencia $Label ausente em $Path"
    }
    for ($i = 0; $i -le ($bytes.Length - $Expected.Length); $i++) {
        $match = $true
        for ($k = 0; $k -lt $Expected.Length; $k++) {
            if ($bytes[$i + $k] -ne $Expected[$k]) { $match = $false; break }
        }
        if ($match) { return }
    }
    throw "Sequencia $Label ausente em $Path"
}

# Tabela da spec secao 3.3, na ordem dos IDs 1..24. Fonte unica do caso
# vocabulario_completo (entrada e saida esperada saem deste array).
$vocabulary = @(
    "programa", "funcao", "inicio", "inteiro", "real", "logico", "cadeia", "vazio",
    "se", "senao", "enquanto", "faca", "para", "ate", "passo", "retorne",
    "escreva", "leia", "e", "ou", "nao", "verdadeiro", "falso", "pare"
)
if ($vocabulary.Count -ne 24) {
    throw "Vocabulario deve ter 24 palavras, encontrado $($vocabulary.Count)"
}

# Literais acentuados construidos por code point para manter este script ASCII
# puro (Windows PowerShell 5.1 le arquivos sem BOM como ANSI).
$atilde = [string][char]0xE3
$ccedil = [string][char]0xE7

# Fonte unica dos dois casos de determinismo: entradas e saidas identicas,
# executadas em processos separados (arquivos gerados byte a byte iguais).
$determinismDriver = 'tokenizar("programa se x 42 se")'
$determinismExpected = "IDS=1 9 0 0 9"

# Casos ativos. Driver = corpo de inicio(); Expected = linha logica exata.
$cases = @(
    @{
        Name     = "vazio"
        Driver   = 'tokenizar("")'
        Expected = "IDS="
    }
    @{
        Name     = "so_separadores"
        Driver   = 'tokenizar(" \t\r\n\t ")'
        Expected = "IDS="
    }
    @{
        Name     = "limite_chars_16385"
        Driver   = @'
cadeia s = "a"
inteiro i = 0
enquanto (i < 14)
{
    s = s + s
    i = i + 1
}
tokenizar(s + "a")
'@
        Expected = "ERRO=ENTRADA_LONGA"
    }
    @{
        Name     = "fora_da_tabela"
        Driver   = 'tokenizar("x 42 @ resultado")'
        Expected = "IDS=0 0 0 0"
    }
    @{
        Name     = "unk_isolado"
        Driver   = 'tokenizar("x")'
        Expected = "IDS=0"
    }
    @{
        Name     = "bordas_e_consecutivos"
        Driver   = 'tokenizar("  se\t\tfaca ")'
        Expected = "IDS=9 12"
    }
    @{
        Name     = "separador_estrito"
        Driver   = 'tokenizar("se,faca se faca")'
        Expected = "IDS=0 9 12"
    }
    @{
        Name     = "caixa"
        Driver   = 'tokenizar("se Se SE")'
        Expected = "IDS=9 0 0"
    }
    @{
        Name     = "acentos"
        Driver   = 'tokenizar("nao na' + $atilde + 'o funcao fun' + $ccedil + $atilde + 'o")'
        Expected = "IDS=21 0 2 0"
    }
    @{
        Name     = "vocabulario_completo"
        Driver   = 'tokenizar("' + ($vocabulary -join ' ') + '")'
        Expected = "IDS=" + ((1..$vocabulary.Count) -join ' ')
    }
    @{
        Name     = "pontuacao"
        Driver   = 'tokenizar("se, (se) se, faca inicio() x=1")'
        Expected = "IDS=0 0 0 12 0 0"
    }
    @{
        Name     = "cardinalidade"
        Driver   = 'tokenizar("programa { se x } resultado")'
        Expected = "IDS=1 0 9 0 0 0"
    }
    @{
        Name     = "exemplo_spec"
        Driver   = 'tokenizar("programa { funcao inicio() { escreva(\"OI\") } }")'
        Expected = "IDS=1 0 2 0 0 0 0 0"
    }
    @{
        Name     = "limite_tokens_1024"
        Driver   = @'
cadeia s = "se"
inteiro i = 0
enquanto (i < 10)
{
    s = s + " " + s
    i = i + 1
}
tokenizar(s)
'@
        Expected = "IDS=" + ((1..1024 | ForEach-Object { 9 }) -join ' ')
    }
    @{
        Name     = "limite_tokens_1025"
        Driver   = @'
cadeia s = "se"
inteiro i = 0
enquanto (i < 10)
{
    s = s + " " + s
    i = i + 1
}
tokenizar(s + " se")
'@
        Expected = "ERRO=TOKENS_DEMAIS"
    }
    @{
        Name     = "limite_ambos"
        Driver   = @'
cadeia s = "x "
inteiro i = 0
enquanto (i < 13)
{
    s = s + s
    i = i + 1
}
tokenizar(s + "x")
'@
        Expected = "ERRO=ENTRADA_LONGA"
    }
    @{
        Name     = "limite_chars_16384"
        Driver   = @'
cadeia s = "a"
inteiro i = 0
enquanto (i < 14)
{
    s = s + s
    i = i + 1
}
tokenizar(s)
'@
        Expected = "IDS=0"
    }
    @{
        Name     = "longo_so_separadores"
        Driver   = @'
cadeia s = " \t\r\n"
inteiro i = 0
enquanto (i < 12)
{
    s = s + s
    i = i + 1
}
tokenizar(s)
'@
        Expected = "IDS="
    }
    @{
        Name     = "determinismo_a"
        Driver   = $determinismDriver
        Expected = $determinismExpected
    }
    @{
        Name     = "determinismo_b"
        Driver   = $determinismDriver
        Expected = $determinismExpected
    }
)

$names = @($cases | ForEach-Object { $_.Name })
$uniqueNames = @($names | Sort-Object -Unique)
if ($uniqueNames.Count -ne $names.Count) {
    throw "Nome de caso duplicado na tabela de casos"
}

$repoRoot = (Get-Location).Path
$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
    throw "Fragmento nao encontrado: $sourceFull"
}

$fragment = [IO.File]::ReadAllText($sourceFull)
if ($fragment -match '(?m)^\s*programa\b') {
    throw "O fragmento nao pode declarar 'programa': $sourceFull"
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
    $porPath = Join-Path $outFull ($case.Name + ".por")
    $expectedPath = Join-Path $outFull ($case.Name + ".expected")

    $content = "programa`n{`n" +
        $fragment.TrimEnd("`r", "`n") + "`n`n" +
        "    funcao inicio()`n" +
        "    {`n" +
        (Add-PortugolIndent $case.Driver) + "`n" +
        "    }`n" +
        "}`n"

    [IO.File]::WriteAllText($porPath, $content, $utf8NoBom)
    [IO.File]::WriteAllText($expectedPath, $case.Expected, $utf8NoBom)

    Assert-Utf8NoBom $porPath
    Assert-Utf8NoBom $expectedPath

    if ($case.Driver.IndexOf([char]0xE3) -ge 0) {
        Assert-ByteSequence $porPath ([byte[]](0xC3, 0xA3)) "C3 A3 (a com til)"
    }
    if ($case.Driver.IndexOf([char]0xE7) -ge 0) {
        Assert-ByteSequence $porPath ([byte[]](0xC3, 0xA7)) "C3 A7 (c com cedilha)"
    }
}

Write-Host "Generated $($cases.Count) cases in $OutputRoot"
