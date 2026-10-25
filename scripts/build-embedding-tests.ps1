<#
.SYNOPSIS
    Gera os casos .por e .expected dos embeddings em temp/embedding-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/embeddings.por (fragmento) a um driver que chama a API. Os valores
    esperados sao recalculados aqui pela formula da spec, em aritmetica exata,
    e conferidos contra a tabela canonica. Tudo e gravado em UTF-8 sem BOM.
#>

param(
    [string]$SourcePath = "src/embeddings.por",
    [string]$OutputRoot = "temp/embedding-tests"
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

function Add-PortugolIndent {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $indented = foreach ($line in $lines) {
        if ($line -eq "") { "" } else { "        " + $line }
    }
    return ($indented -join "`n")
}

function Format-EmbReal {
    param([double]$Value)
    # Mesmo formato observado na sonda E0/P7: ponto decimal, 1 a 4 casas,
    # sem zeros a direita alem da primeira casa.
    return $Value.ToString("0.0###", $invariant)
}

function Get-CanonicalRow {
    param([int]$Id)
    $values = @()
    for ($d = 0; $d -lt 4; $d++) {
        $q = (($Id * 7 + $d * 3) % 32) - 16
        $values += ($q / 16.0)
    }
    return $values
}

function Format-VectorLine {
    param([int]$Id, [double[]]$Values)
    $parts = @()
    foreach ($v in $Values) { $parts += (Format-EmbReal $v) }
    return "VETOR=$Id " + ($parts -join " ")
}

# Tabela canonica recalculada pela formula (independe de .expected anteriores).
$canonical = @{}
for ($id = 0; $id -lt 25; $id++) {
    $canonical[$id] = Get-CanonicalRow $id
}

# Conferencias da propria tabela, antes de gerar qualquer arquivo.
$allValues = @()
foreach ($id in 0..24) { $allValues += $canonical[$id] }
if ($allValues.Count -ne 100) { throw "Tabela canonica com $($allValues.Count) valores; esperado 100" }
if (($allValues | Measure-Object -Minimum).Minimum -ne -1.0) { throw "Minimo canonico diferente de -1.0" }
if (($allValues | Measure-Object -Maximum).Maximum -ne 0.9375) { throw "Maximo canonico diferente de 0.9375" }
$rowKeys = @($canonical.Keys | ForEach-Object { ($canonical[$_] | ForEach-Object { Format-EmbReal $_ }) -join "," } | Sort-Object -Unique)
if ($rowKeys.Count -ne 25) { throw "Linhas canonicas distintas: $($rowKeys.Count); esperado 25" }

$summaryExpected = "RESUMO=25 100 " +
    (Format-EmbReal (($allValues | Measure-Object -Minimum).Minimum)) + " " +
    (Format-EmbReal (($allValues | Measure-Object -Maximum).Maximum)) + " " +
    $rowKeys.Count

$initDriver = "real w[100]`ninicializar_embeddings(w)"

$determinismDriver = @'
real w[100]
inicializar_embeddings(w)
inteiro id = 0
enquanto (id < 25)
{
    emb_imprimir_vetor(w, id)
    id = id + 1
}
'@

$determinismExpected = (@(0..24 | ForEach-Object { Format-VectorLine $_ $canonical[$_] }) -join "`n")

function Format-PesoLine {
    param([int]$Id, [int]$D, [double[]]$Values)
    return "PESO=$Id $D " + (Format-EmbReal $Values[$D])
}

$pesoPairs = @(
    [pscustomobject]@{ Id = 0;  D = 0 }
    [pscustomobject]@{ Id = 4;  D = 1 }
    [pscustomobject]@{ Id = 9;  D = 0 }
    [pscustomobject]@{ Id = 16; D = 0 }
    [pscustomobject]@{ Id = 24; D = 3 }
    [pscustomobject]@{ Id = 11; D = 1 }
    [pscustomobject]@{ Id = 3;  D = 2 }
)
$pesoDriver = $initDriver + "`n" +
    (($pesoPairs | ForEach-Object { "emb_imprimir_peso(w, $($_.Id), $($_.D))" }) -join "`n")
$pesoExpected = (@($pesoPairs | ForEach-Object { Format-PesoLine $_.Id $_.D $canonical[$_.Id] }) -join "`n")

$validatorDriver = $initDriver
$validatorExpected = @()
foreach ($x in @(-1, 0, 24, 25)) {
    $validatorDriver += "`nse (emb_id_valido($x)) { escreva(""VALIDO=1\n"") } senao { escreva(""VALIDO=0\n"") }"
    $validatorExpected += $(if ($x -ge 0 -and $x -le 24) { "VALIDO=1" } else { "VALIDO=0" })
}
foreach ($x in @(-1, 0, 3, 4)) {
    $validatorDriver += "`nse (emb_dim_valida($x)) { escreva(""VALIDO=1\n"") } senao { escreva(""VALIDO=0\n"") }"
    $validatorExpected += $(if ($x -ge 0 -and $x -le 3) { "VALIDO=1" } else { "VALIDO=0" })
}
$validatorExpected = $validatorExpected -join "`n"

$layoutDriver = $initDriver + "`nlogico layout_ok = verdadeiro"
foreach ($id in @(0, 9, 17, 24)) {
    foreach ($d in 0..3) {
        $index = $id * 4 + $d
        $layoutDriver += "`nlayout_ok = layout_ok e (w[$index] == emb_obter(w, $id, $d))"
    }
}
$layoutDriver += "`nse (layout_ok) { escreva(""LAYOUT=OK\n"") } senao { escreva(""LAYOUT=FAIL\n"") }"

$mutationState = @{}
foreach ($id in 0..24) {
    $values = @($canonical[$id])
    $mutationState[$id] = $values
}
$mutationState[5][2] = 0.5
$mutationState[5][3] = 1.7
$mutationExpected = (@(5, 6 | ForEach-Object { Format-VectorLine $_ $mutationState[$_] }) -join "`n")

$updateDriver = @'
real w[100]
inicializar_embeddings(w)
emb_definir(w, 5, 2, 0.5)
emb_definir(w, 5, 3, 1.7)
emb_imprimir_vetor(w, 5)
emb_imprimir_vetor(w, 6)
'@

$reinitDriver = @'
real w[100]
inicializar_embeddings(w)
emb_definir(w, 5, 2, 1.7)
inicializar_embeddings(w)
emb_imprimir_vetor(w, 5)
'@

$cases = @(
    @{
        Name     = "emb_info"
        Driver   = $initDriver + "`nemb_imprimir_info()"
        Expected = "INFO=25 4 100"
    }
    @{
        Name     = "emb_unk"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, 0)"
        Expected = Format-VectorLine 0 $canonical[0]
    }
    @{
        Name     = "emb_id_1"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, 1)"
        Expected = Format-VectorLine 1 $canonical[1]
    }
    @{
        Name     = "emb_id_24"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, 24)"
        Expected = Format-VectorLine 24 $canonical[24]
    }
    @{
        Name     = "emb_amostra_vetores"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, 4)`nemb_imprimir_vetor(w, 9)`nemb_imprimir_vetor(w, 17)"
        Expected = (@(4, 9, 17 | ForEach-Object { Format-VectorLine $_ $canonical[$_] }) -join "`n")
    }
    @{
        Name     = "emb_peso"
        Driver   = $pesoDriver
        Expected = $pesoExpected
    }
    @{
        Name     = "emb_validadores"
        Driver   = $validatorDriver
        Expected = $validatorExpected
    }
    @{
        Name     = "emb_layout"
        Driver   = $layoutDriver
        Expected = "LAYOUT=OK"
    }
    @{
        Name     = "emb_id_invalido_neg"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, -1)"
        Expected = "ERRO=ID_INVALIDO"
    }
    @{
        Name     = "emb_id_invalido_25"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, 25)"
        Expected = "ERRO=ID_INVALIDO"
    }
    @{
        Name     = "emb_dim_invalida_neg"
        Driver   = $initDriver + "`nemb_imprimir_peso(w, 0, -1)"
        Expected = "ERRO=DIMENSAO_INVALIDA"
    }
    @{
        Name     = "emb_dim_invalida_4"
        Driver   = $initDriver + "`nemb_imprimir_peso(w, 0, 4)"
        Expected = "ERRO=DIMENSAO_INVALIDA"
    }
    @{
        Name     = "emb_ambos_invalidos"
        Driver   = $initDriver + "`nemb_imprimir_peso(w, -1, 4)"
        Expected = "ERRO=ID_INVALIDO"
    }
    @{
        Name     = "emb_apos_erro"
        Driver   = $initDriver + "`nemb_imprimir_vetor(w, 25)`nemb_imprimir_vetor(w, 0)"
        Expected = "ERRO=ID_INVALIDO`n" + (Format-VectorLine 0 $canonical[0])
    }
    @{
        Name     = "emb_atualizacao"
        Driver   = $updateDriver
        Expected = $mutationExpected
    }
    @{
        Name     = "emb_reinicializacao"
        Driver   = $reinitDriver
        Expected = Format-VectorLine 5 $canonical[5]
    }
    @{
        Name     = "emb_resumo"
        Driver   = $initDriver + "`nemb_resumo(w)"
        Expected = $summaryExpected
    }
    @{
        Name     = "emb_determinismo_a"
        Driver   = $determinismDriver
        Expected = $determinismExpected
    }
    @{
        Name     = "emb_determinismo_b"
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

# AC18: fonte ASCII puro (0x20-0x7E, TAB, CR, LF). Sem BOM.
Assert-Utf8NoBom $sourceFull
$sourceBytes = [IO.File]::ReadAllBytes($sourceFull)
foreach ($b in $sourceBytes) {
    if ($b -eq 0x09 -or $b -eq 0x0A -or $b -eq 0x0D) { continue }
    if ($b -lt 0x20 -or $b -gt 0x7E) {
        throw ("Byte nao ASCII 0x{0:X2} no fragmento" -f $b)
    }
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
}

Write-Host "Generated $($cases.Count) cases in $OutputRoot"
