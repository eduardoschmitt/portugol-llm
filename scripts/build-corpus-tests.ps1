<#
.SYNOPSIS
    Gera os 16 casos .por e .expected do treinamento com corpus textual (M8)
    em temp/corpus-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/tokenizador.por (M1), src/corpus.por (M8) e src/contexto.por (M7) a um
    driver. Em corp_composicao tambem concatena src/embeddings.por (M3).

    Os valores esperados sao recalculados por um oraculo inteiro independente
    (W16[300], b16[25], c16, Z256, delta256, r, treino, perda, margens,
    geracao), sem [double] e sem ler a saida do .por. As tabelas canonicas de
    inicializacao/final, a trajetoria, as margens, a ordem inversa, a geracao,
    a capacidade e E=32 sao conferidos como literais contra a spec.

    Tudo e gravado em UTF-8 sem BOM, LF; .expected sem LF final.
#>

param(
    [string]$SourcePath = "src/corpus.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$ContextSourcePath = "src/contexto.por",
    [string]$CorpusPath = "corpus/m8-corpus-v1.txt",
    [string]$OutputRoot = "temp/corpus-tests"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-Utf8NoBom {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "Arquivo com BOM: $Path"
    }
}

function Assert-AsciiLf {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { throw "CR encontrado: $Path" }
        if ($b -gt 0x7E) { throw "Byte nao ASCII: $Path" }
    }
}

function Add-PortugolIndent {
    param([string]$Text)
    $lines = $Text -split "`n"
    $out = foreach ($line in $lines) {
        if ($line -eq "") { "" } else { "        " + $line }
    }
    return ($out -join "`n")
}

# --- Oraculo inteiro independente -----------------------------------------

$script:CorpWords = @(
    "UNK", "programa", "funcao", "inicio", "inteiro", "real", "logico",
    "cadeia", "vazio", "se", "senao", "enquanto", "faca", "para", "ate",
    "passo", "retorne", "escreva", "leia", "e", "ou", "nao", "verdadeiro",
    "falso", "pare"
)

function Get-CorpWordId {
    param([string]$Word)
    for ($i = 0; $i -lt $script:CorpWords.Count; $i++) {
        if ($script:CorpWords[$i] -ceq $Word) { return $i }
    }
    return -1
}

function Get-CorpWord {
    param([int]$Id)
    return $script:CorpWords[$Id]
}

# Tokeniza uma linha com a mesma precedencia de corp_tokenizar.
function Get-CorpTokenize {
    param([string]$Line)
    if ($Line.Length -eq 0) {
        return [pscustomobject]@{ Code = 2; Ids = @(); Token = 0 }
    }
    if ($Line.IndexOf("`t") -ge 0 -or $Line.IndexOf("`r") -ge 0 -or $Line.IndexOf("`n") -ge 0) {
        return [pscustomobject]@{ Code = 2; Ids = @(); Token = 0 }
    }
    if ($Line[0] -eq ' ' -or $Line[$Line.Length - 1] -eq ' ' -or $Line.Contains("  ")) {
        return [pscustomobject]@{ Code = 2; Ids = @(); Token = 0 }
    }
    $parts = @($Line.Split(' '))
    $ids = @()
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $id = Get-CorpWordId $parts[$i]
        if ($id -lt 0) {
            return [pscustomobject]@{ Code = 3; Ids = @(); Token = $i + 1 }
        }
        $ids += $id
    }
    if ($parts.Count -lt 4) {
        return [pscustomobject]@{ Code = 6; Ids = @(); Token = $parts.Count }
    }
    if ($parts.Count -gt 8) {
        return [pscustomobject]@{ Code = 7; Ids = @(); Token = $parts.Count }
    }
    if ($ids[$ids.Count - 1] -ne 24) {
        return [pscustomobject]@{ Code = 4; Ids = @(); Token = 0 }
    }
    for ($i = 0; $i -lt $ids.Count - 1; $i++) {
        if ($ids[$i] -eq 24) {
            return [pscustomobject]@{ Code = 5; Ids = @(); Token = $i + 1 }
        }
    }
    return [pscustomobject]@{ Code = 0; Ids = [int[]]$ids; Token = 0 }
}

function Get-CorpExtract {
    param([string[]]$Lines)
    if ($Lines.Count -eq 0) {
        return [pscustomobject]@{ Code = 1; Entradas = @(); Alvos = @(); N = 0; Line = 0; Token = 0 }
    }
    if ($Lines.Count -gt 6) {
        return [pscustomobject]@{ Code = 8; Entradas = @(); Alvos = @(); N = 0; Line = 0; Token = 0 }
    }
    $ent = @()
    $alv = @()
    for ($li = 0; $li -lt $Lines.Count; $li++) {
        $tk = Get-CorpTokenize $Lines[$li]
        if ($tk.Code -ne 0) {
            return [pscustomobject]@{ Code = $tk.Code; Entradas = @(); Alvos = @(); N = 0; Line = $li + 1; Token = $tk.Token }
        }
        $ids = $tk.Ids
        for ($i = 3; $i -lt $ids.Count; $i++) {
            $a = $ids[$i - 3]; $b = $ids[$i - 2]; $c = $ids[$i - 1]; $t = $ids[$i]
            for ($j = 0; $j -lt $alv.Count; $j++) {
                if ($ent[$j * 3] -eq $a -and $ent[$j * 3 + 1] -eq $b -and $ent[$j * 3 + 2] -eq $c) {
                    $code = if ($alv[$j] -eq $t) { 9 } else { 10 }
                    return [pscustomobject]@{ Code = $code; Entradas = @(); Alvos = @(); N = 0; Line = $li + 1; Token = $i + 1 }
                }
            }
            $ent += $a; $ent += $b; $ent += $c
            $alv += $t
        }
    }
    return [pscustomobject]@{ Code = 0; Entradas = [int[]]$ent; Alvos = [int[]]$alv; N = $alv.Count; Line = 0; Token = 0 }
}

function New-CorpW {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($k = 0; $k -lt 3; $k++) {
            for ($d = 0; $d -lt 4; $d++) {
                if ($k -lt 2) { $row[$k * 4 + $d] = 0 }
                else { $row[$k * 4 + $d] = (($y * 7 + $d * 5) % 25) - 12 }
            }
        }
        $w[$y] = $row
    }
    return $w
}

function New-CorpB {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-CorpW {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($p = 0; $p -lt 12; $p++) { $row[$p] = $W[$y][$p] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-CorpB {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-CorpE16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

function Get-CorpC16 {
    param([int[]]$Seq)
    $c = New-Object 'int[]' 12
    for ($k = 0; $k -lt 3; $k++) {
        $pos = $Seq.Count - 3 + $k
        if ($pos -ge 0) {
            for ($d = 0; $d -lt 4; $d++) {
                $c[$k * 4 + $d] = Get-CorpE16 $Seq[$pos] $d
            }
        }
    }
    return $c
}

function Get-CorpC16FromExample {
    param([int[]]$Entradas, [int]$N)
    return Get-CorpC16 ([int[]]@($Entradas[$N * 3], $Entradas[$N * 3 + 1], $Entradas[$N * 3 + 2]))
}

function Get-CorpZ256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y)
    [long]$soma = 0
    for ($p = 0; $p -lt 12; $p++) {
        $soma += [long]$W[$Y][$p] * [long]$C[$p]
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-CorpDelta256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y, [int]$Alvo)
    [long]$z = Get-CorpZ256 $W $B $C $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-CorpArgmax {
    param([hashtable]$W, [hashtable]$B, [int[]]$C)
    $melhor = 0
    [long]$melhorValor = Get-CorpZ256 $W $B $C 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-CorpZ256 $W $B $C $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-CorpLoss {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-CorpDelta256 $W $B $c $y $Alvos[$i]
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-CorpRound {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

function Invoke-CorpTrain {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-CorpLoss $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            [int[]]$c = Get-CorpC16FromExample $Entradas $i
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-CorpDelta256 $W $B $c $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($p = 0; $p -lt 12; $p++) {
                    [long]$novo = Get-CorpRound (2048 * [long]$W[$y][$p] - $delta[$y] * [long]$c[$p]) 2048
                    $W[$y][$p] = $novo
                    if ([Math]::Abs($novo) -gt 16) {
                        return [pscustomobject]@{ Code = 5; History = $history }
                    }
                }
                [long]$novoB = Get-CorpRound (128 * [long]$B[$y] - $delta[$y]) 128
                $B[$y] = $novoB
                if ([Math]::Abs($novoB) -gt 16) {
                    return [pscustomobject]@{ Code = 5; History = $history }
                }
            }
        }
        $history[$ep] = Get-CorpLoss $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history }
}

function Get-CorpAccuracy {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        if ((Get-CorpArgmax $W $B $c) -eq $Alvos[$i]) { $total++ }
    }
    return $total
}

function Get-CorpPred {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int]$N)
    $out = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        $out += (Get-CorpArgmax $W $B $c)
    }
    return $out
}

function Get-CorpGeneration {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $total = $Prefixo.Count
    for ($i = 0; $i -lt $total; $i++) { $saida[$i] = $Prefixo[$i] }
    if ($saida[$total - 1] -eq 24) {
        return [pscustomobject]@{ Saida = $saida; Total = $total }
    }
    while ($total -lt $Maximo) {
        [int[]]$seq = @($saida[0..($total - 1)])
        [int[]]$c = Get-CorpC16 $seq
        $proximo = Get-CorpArgmax $W $B $c
        $saida[$total] = $proximo
        $total++
        if ($proximo -eq 24) { break }
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
}

function Get-CorpGenLines {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $g = Get-CorpGeneration $W $B $Prefixo $Maximo
    $ids = @($g.Saida[0..($g.Total - 1)])
    $parada = if ($ids[$ids.Count - 1] -eq 24) { "PARE" } else { "MAXIMO" }
    $texto = (@($ids | ForEach-Object { Get-CorpWord $_ }) -join " ")
    return @(
        ("GERADO=" + ($ids -join " ")),
        "N=$($g.Total)",
        "PASSOS=$($g.Total - $Prefixo.Count)",
        "PARADA=$parada",
        "TEXTO=$texto"
    )
}

function Get-CorpMargins {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $out = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CorpC16FromExample $Entradas $i
        [long]$zAlvo = Get-CorpZ256 $W $B $c $Alvos[$i]
        [long]$segundo = -1000000
        for ($y = 0; $y -lt 25; $y++) {
            if ($y -ne $Alvos[$i]) {
                [long]$z = Get-CorpZ256 $W $B $c $y
                if ($z -gt $segundo) { $segundo = $z }
            }
        }
        $out += ($zAlvo - $segundo)
    }
    return $out
}

function Get-CorpParamLine {
    param([hashtable]$W, [hashtable]$B, [int]$Y)
    return "PARAM16=$Y " + ($W[$Y] -join " ") + " " + $B[$Y]
}

function Get-CorpParamLines {
    param([hashtable]$W, [hashtable]$B)
    $lines = @()
    for ($y = 0; $y -lt 25; $y++) { $lines += Get-CorpParamLine $W $B $y }
    return $lines
}

function Get-CorpMaxima {
    param([hashtable]$W, [hashtable]$B)
    $mw = 0; $mb = 0
    for ($y = 0; $y -lt 25; $y++) {
        for ($p = 0; $p -lt 12; $p++) {
            if ([Math]::Abs($W[$y][$p]) -gt $mw) { $mw = [Math]::Abs($W[$y][$p]) }
        }
        if ([Math]::Abs($B[$y]) -gt $mb) { $mb = [Math]::Abs($B[$y]) }
    }
    return "MAXIMO16=$mw $mb"
}

# --- Fontes e corpus -------------------------------------------------------

$repoRoot = (Get-Location).Path
$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
$tokenizerFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TokenizerSourcePath))
$embeddingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $EmbeddingSourcePath))
$contextFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $ContextSourcePath))
$corpusFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $CorpusPath))
foreach ($path in @($sourceFull, $tokenizerFull, $embeddingFull, $contextFull, $corpusFull)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo nao encontrado: $path" }
    Assert-Utf8NoBom $path
}

$corpusBytes = [IO.File]::ReadAllBytes($corpusFull)
foreach ($b in $corpusBytes) {
    if ($b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) {
        throw "Byte invalido no corpus: 0x$('{0:X2}' -f $b)"
    }
}
if ($corpusBytes.Length -ne 165) { throw "Corpus com $($corpusBytes.Length) bytes; esperado 165" }
$sha = (Get-FileHash -LiteralPath $corpusFull -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -cne "d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113") {
    throw "SHA-256 do corpus divergente: $sha"
}
if ($corpusBytes[$corpusBytes.Length - 1] -ne 0x0A) { throw "Corpus sem LF final" }
if (@($corpusBytes | Where-Object { $_ -eq 0x0A }).Count -ne 5) { throw "Corpus nao tem 5 LF" }
$corpusText = [Text.Encoding]::ASCII.GetString($corpusBytes)
$corpusLines = @($corpusText.TrimEnd("`n").Split("`n"))
$frozenCorpus = @(
    "programa inicio escreva verdadeiro pare",
    "funcao inicio escreva falso pare",
    "se verdadeiro faca escreva pare",
    "se falso senao leia pare",
    "enquanto verdadeiro faca leia pare"
)
if (($corpusLines -join "`n") -cne ($frozenCorpus -join "`n")) {
    throw "Conteudo do corpus divergente da spec"
}
foreach ($line in $corpusLines) {
    $tk = Get-CorpTokenize $line
    if ($tk.Code -ne 0 -or $tk.Ids.Count -ne 5) { throw "Linha canonica invalida: $line" }
}

$sourceText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sourceFull))
foreach ($required in @(
    "CORP_MAX_LINHAS = 6", "CORP_MIN_TOKENS = 4", "CORP_MAX_TOKENS = 8",
    "CORP_MAX_EXEMPLOS = 30", "CORP_K = 3", "CORP_LOTE = 6",
    "CORP_MAX_EPOCAS = 32", "CORP_LIMITE_PERDA = 2000000000",
    "funcao inteiro corp_tokenizar", "funcao inteiro corp_extrair",
    "funcao inteiro corp_perda_total", "funcao inteiro corp_treinar",
    "ctx_perda_escalada", "ctx_executar", "id_do_campo"
)) {
    if ($sourceText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "src/corpus.por nao contem: $required"
    }
}
$sourceCode = (($sourceText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
foreach ($forbidden in @("aleatorio", "tempo", "inclua", "arquivo", "leia(")) {
    if ($sourceCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "src/corpus.por contem termo proibido: $forbidden"
    }
}
Assert-AsciiLf $sourceFull
Assert-AsciiLf $tokenizerFull
Assert-AsciiLf $embeddingFull
Assert-AsciiLf $contextFull

$sourceFragment = $sourceText.TrimEnd("`r", "`n")
$tokenizerFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($tokenizerFull)).TrimEnd("`r", "`n")
$embeddingFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($embeddingFull)).TrimEnd("`r", "`n")
$contextFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($contextFull)).TrimEnd("`r", "`n")

# --- Valores canonicos -----------------------------------------------------

$ext = Get-CorpExtract $corpusLines
if ($ext.Code -ne 0 -or $ext.N -ne 10) { throw "Extracao canonica: Code=$($ext.Code) N=$($ext.N)" }
$ENT = [int[]]$ext.Entradas
$ALV = [int[]]$ext.Alvos

$frozenIds = @(
    @(1, 3, 17, 22, 24),
    @(2, 3, 17, 23, 24),
    @(9, 22, 12, 17, 24),
    @(9, 23, 10, 18, 24),
    @(11, 22, 12, 18, 24)
)
for ($i = 0; $i -lt 5; $i++) {
    $tk = Get-CorpTokenize $corpusLines[$i]
    if (($tk.Ids -join " ") -cne ($frozenIds[$i] -join " ")) {
        throw "IDs canonicos divergentes na linha $($i + 1)"
    }
}
$frozenExamples = @(
    @(0, 1, 3, 17, 22), @(1, 3, 17, 22, 24), @(2, 2, 3, 17, 23),
    @(3, 3, 17, 23, 24), @(4, 9, 22, 12, 17), @(5, 22, 12, 17, 24),
    @(6, 9, 23, 10, 18), @(7, 23, 10, 18, 24), @(8, 11, 22, 12, 18),
    @(9, 22, 12, 18, 24)
)
for ($i = 0; $i -lt 10; $i++) {
    $got = @($ENT[$i * 3], $ENT[$i * 3 + 1], $ENT[$i * 3 + 2], $ALV[$i])
    $want = @($frozenExamples[$i][1], $frozenExamples[$i][2], $frozenExamples[$i][3], $frozenExamples[$i][4])
    if (($got -join " ") -cne ($want -join " ")) {
        throw "Exemplo $i divergente: $($got -join ' ')"
    }
}

$initW = New-CorpW
$initB = New-CorpB
$s0 = Get-CorpLoss $initW $initB $ENT $ALV 10
if ($s0 -ne 8404936) { throw "S0 divergente: $s0" }

$finalW = Copy-CorpW $initW
$finalB = Copy-CorpB $initB
$train = Invoke-CorpTrain $finalW $finalB $ENT $ALV 10 4
if ($train.Code -ne 0) { throw "Treino canonico retornou $($train.Code)" }
$traj = $train.History
if (($traj -join " ") -cne "8404936 1341188 651091 509249 436118") {
    throw "Historico divergente: $($traj -join ' ')"
}
$acc = Get-CorpAccuracy $finalW $finalB $ENT $ALV 10
if ($acc -ne 10) { throw "Acuracia final divergente: $acc" }
$pred = Get-CorpPred $finalW $finalB $ENT 10
if (($pred -join " ") -cne "22 24 23 24 17 24 18 24 18 24") {
    throw "PRED divergente: $($pred -join ' ')"
}
$margins = Get-CorpMargins $finalW $finalB $ENT $ALV 10
if (($margins -join " ") -cne "11 350 17 119 4 102 161 115 125 224") {
    throw "Margens divergentes: $($margins -join ' ')"
}

$frozenParams = @(
    "PARAM16=0 -2 -2 -4 0 3 1 0 1 -3 0 -1 -1 0",
    "PARAM16=1 -2 1 0 1 -1 -1 3 1 -1 2 1 5 2",
    "PARAM16=2 1 1 1 -1 -1 -2 -1 -5 2 -2 3 -4 -2",
    "PARAM16=3 1 -1 1 0 2 1 -1 0 3 -3 2 -1 -1",
    "PARAM16=4 -1 -1 0 0 1 2 2 2 -2 1 -1 3 1",
    "PARAM16=5 1 1 2 -2 0 0 -4 -3 -1 -3 2 -7 -2",
    "PARAM16=6 0 0 -1 -2 1 0 -3 3 -3 3 -5 -2 0",
    "PARAM16=7 3 0 1 2 1 -1 1 0 4 -4 4 0 -1",
    "PARAM16=8 0 0 -1 0 -1 -2 4 1 -2 2 0 3 3",
    "PARAM16=9 1 2 0 -1 -1 0 -4 -5 2 -2 2 -6 -3",
    "PARAM16=10 2 -1 3 1 1 0 -1 2 3 -3 2 -1 0",
    "PARAM16=11 -2 -1 -1 0 1 1 2 1 -3 1 0 3 1",
    "PARAM16=12 -2 1 -1 1 -3 -3 4 1 0 1 1 6 5",
    "PARAM16=13 1 0 -1 -2 2 1 -4 1 -3 3 -5 -3 -1",
    "PARAM16=14 2 0 2 1 1 -1 0 0 3 -3 3 2 0",
    "PARAM16=15 -3 0 -1 0 -2 0 2 1 -2 2 0 5 3",
    "PARAM16=16 1 1 -1 0 -2 0 -1 -4 1 -2 2 -6 -2",
    "PARAM16=17 2 -5 -3 -2 4 3 1 0 0 2 -3 1 -1",
    "PARAM16=18 1 0 -2 3 -3 0 -4 0 -4 0 1 4 6",
    "PARAM16=19 -1 0 1 2 -3 -1 3 2 0 1 1 6 3",
    "PARAM16=20 0 -1 -1 -3 2 1 -2 1 -3 4 -5 -3 -1",
    "PARAM16=21 4 -3 2 3 0 0 1 0 6 -3 3 1 -2",
    "PARAM16=22 -5 -1 -1 -2 0 1 3 1 -3 0 2 2 2",
    "PARAM16=23 -1 0 -1 4 3 -2 -4 -2 0 -3 3 -9 0",
    "PARAM16=24 -1 2 -2 -1 -1 3 3 -3 2 2 -8 -6 4"
)
$paramLines = Get-CorpParamLines $finalW $finalB
if (($paramLines -join "`n") -cne ($frozenParams -join "`n")) {
    throw "Tabela PARAM16 divergente da spec"
}
$maxLine = Get-CorpMaxima $finalW $finalB
if ($maxLine -cne "MAXIMO16=9 6") { throw "Maximos finais divergentes: $maxLine" }

$changedW = 0; $changedB = 0
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 12; $p++) {
        if ($finalW[$y][$p] -ne $initW[$y][$p]) { $changedW++ }
    }
    if ($finalB[$y] -ne $initB[$y]) { $changedB++ }
}
if ($changedW -ne 253 -or $changedB -ne 22) {
    throw "Parametros alterados divergentes: W=$changedW B=$changedB"
}

# --- Ordem inversa ---------------------------------------------------------

$revEnt = New-Object 'int[]' 30
$revAlv = New-Object 'int[]' 10
for ($i = 0; $i -lt 10; $i++) {
    $src = 9 - $i
    for ($k = 0; $k -lt 3; $k++) { $revEnt[$i * 3 + $k] = $ENT[$src * 3 + $k] }
    $revAlv[$i] = $ALV[$src]
}
$revW = Copy-CorpW $initW
$revB = Copy-CorpB $initB
$revTrain = Invoke-CorpTrain $revW $revB $revEnt $revAlv 10 4
if ($revTrain.Code -ne 0) { throw "Treino inverso retornou $($revTrain.Code)" }
$revTraj = $revTrain.History
if (($revTraj -join " ") -cne "8404936 1941318 727037 491309 377464") {
    throw "Historico inverso divergente: $($revTraj -join ' ')"
}
$revAcc = Get-CorpAccuracy $revW $revB $revEnt $revAlv 10
if ($revAcc -ne 8) { throw "Acuracia inversa divergente: $revAcc" }
$revPred = Get-CorpPred $revW $revB $revEnt 10
if (($revPred -join " ") -cne "24 17 24 18 24 17 24 22 24 22") {
    throw "PRED inverso divergente: $($revPred -join ' ')"
}
$revMax = Get-CorpMaxima $revW $revB
if ($revMax -cne "MAXIMO16=7 4") { throw "Maximos inversos divergentes: $revMax" }
$diffParams = 0
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 12; $p++) {
        if ($finalW[$y][$p] -ne $revW[$y][$p]) { $diffParams++ }
    }
    if ($finalB[$y] -ne $revB[$y]) { $diffParams++ }
}
if ($diffParams -ne 213) { throw "Diferencas de parametros: $diffParams" }

# --- Capacidade, E=32, ablacoes e sonda ------------------------------------

$capLines = @(
    "programa inicio inteiro real logico cadeia vazio pare",
    "funcao inicio logico real cadeia vazio inteiro pare",
    "se verdadeiro faca leia escreva retorne passo pare",
    "enquanto falso faca escreva leia retorne passo pare",
    "para real ate passo leia faca escreva pare",
    "se falso senao leia retorne escreva passo pare"
)
$capExt = Get-CorpExtract $capLines
if ($capExt.Code -ne 0 -or $capExt.N -ne 30) { throw "Capacidade: Code=$($capExt.Code) N=$($capExt.N)" }
$capEnt = [int[]]$capExt.Entradas
$capAlv = [int[]]$capExt.Alvos
$capS0 = Get-CorpLoss $initW $initB $capEnt $capAlv 30
if ($capS0 -ne 19563100) { throw "S0 da capacidade divergente: $capS0" }
$capW = Copy-CorpW $initW
$capB = Copy-CorpB $initB
$capTrain = Invoke-CorpTrain $capW $capB $capEnt $capAlv 30 1
if ($capTrain.Code -ne 0) { throw "Treino da capacidade retornou $($capTrain.Code)" }
if ($capTrain.History[1] -ne 3361748) { throw "S1 da capacidade divergente: $($capTrain.History[1])" }
$capMax = Get-CorpMaxima $capW $capB
if ($capMax -cne "MAXIMO16=7 5") { throw "Maximos da capacidade divergentes: $capMax" }
if (([int][Math]::Ceiling(30 / 6)) -ne 5) { throw "Contagem de lotes divergente" }

$stressW = Copy-CorpW $initW
$stressB = Copy-CorpB $initB
$stress = Invoke-CorpTrain $stressW $stressB $ENT $ALV 10 32
if ($stress.Code -ne 0) { throw "Treino E=32 retornou $($stress.Code)" }
if ($stress.History[32] -ne 310777) { throw "S32 divergente: $($stress.History[32])" }
if ((Get-CorpAccuracy $stressW $stressB $ENT $ALV 10) -ne 10) { throw "Acuracia E=32 divergente" }
if ((Get-CorpMaxima $stressW $stressB) -cne "MAXIMO16=12 10") { throw "Maximos E=32 divergentes" }

$ablW = Copy-CorpW $finalW
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 8; $p++) { $ablW[$y][$p] = 0 }
}
$ablLastAcc = Get-CorpAccuracy $ablW $finalB $ENT $ALV 10
$ablLastS = Get-CorpLoss $ablW $finalB $ENT $ALV 10
if ($ablLastAcc -ne 5 -or $ablLastS -ne 1058696) {
    throw "Ablacao ultimo divergente: $ablLastAcc/$ablLastS"
}
$ablOldW = Copy-CorpW $finalW
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 8; $p -lt 12; $p++) { $ablOldW[$y][$p] = 0 }
}
$ablOldAcc = Get-CorpAccuracy $ablOldW $finalB $ENT $ALV 10
$ablOldS = Get-CorpLoss $ablOldW $finalB $ENT $ALV 10
if ($ablOldAcc -ne 8 -or $ablOldS -ne 1180874) {
    throw "Ablacao antigos divergente: $ablOldAcc/$ablOldS"
}

$heldLines = @(
    "para inteiro ate passo pare",
    "programa inicio leia falso pare",
    "se falso faca escreva pare",
    "funcao inicio retorne verdadeiro pare",
    "enquanto falso faca escreva pare"
)
$heldAcc = 0
$heldTotal = 0
foreach ($line in $heldLines) {
    $tk = Get-CorpTokenize $line
    if ($tk.Code -ne 0) { throw "Linha da sonda invalida: $line" }
    for ($i = 3; $i -lt $tk.Ids.Count; $i++) {
        [int[]]$hseq = @($tk.Ids[$i - 3], $tk.Ids[$i - 2], $tk.Ids[$i - 1])
        [int[]]$hc = Get-CorpC16 $hseq
        if ((Get-CorpArgmax $finalW $finalB $hc) -eq $tk.Ids[$i]) { $heldAcc++ }
        $heldTotal++
    }
}
if ($heldTotal -ne 10 -or $heldAcc -ne 1) {
    throw "Sonda fora do corpus divergente: $heldAcc/$heldTotal"
}

# --- Helpers comuns dos drivers --------------------------------------------

$corpHelpers = @'
funcao logico corp_drv_iguais(inteiro a[], inteiro b[], inteiro n)
{
    inteiro i = 0
    enquanto (i < n)
    {
        se (a[i] != b[i])
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

funcao logico corp_drv_tudo(inteiro a[], inteiro n, inteiro valor)
{
    inteiro i = 0
    enquanto (i < n)
    {
        se (a[i] != valor)
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

funcao corp_drv_ids(inteiro ids[], inteiro n)
{
    escreva("IDS=")
    inteiro i = 0
    enquanto (i < n)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        escreva(ids[i])
        i = i + 1
    }
    escreva("\n")
}

funcao corp_drv_maximos(inteiro w16[], inteiro b16[])
{
    inteiro mw = 0
    inteiro mb = 0
    inteiro i = 0
    enquanto (i < 300)
    {
        se (ctx_abs(w16[i]) > mw)
        {
            mw = ctx_abs(w16[i])
        }
        i = i + 1
    }
    i = 0
    enquanto (i < 25)
    {
        se (ctx_abs(b16[i]) > mb)
        {
            mb = ctx_abs(b16[i])
        }
        i = i + 1
    }
    escreva("MAXIMO16=", mw, " ", mb, "\n")
}

funcao corp_drv_avaliacao(inteiro w16[], inteiro b16[],
                          inteiro entradas[], inteiro alvos[], inteiro n)
{
    escreva("PERDA=", ctx_perda_escalada(w16, b16, entradas, alvos, n), "\n")
    escreva("ACERTOS=", ctx_acertos(w16, b16, entradas, alvos, n), "\n")
    escreva("PRED=")
    inteiro i = 0
    enquanto (i < n)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        escreva(ctx_argmax(w16, b16, c16))
        i = i + 1
    }
    escreva("\n")
}

funcao corp_drv_margens(inteiro w16[], inteiro b16[],
                        inteiro entradas[], inteiro alvos[], inteiro n)
{
    escreva("MARGENS=")
    inteiro i = 0
    enquanto (i < n)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        inteiro alvo = alvos[i]
        inteiro z_alvo = ctx_z256(w16, b16, c16, alvo)
        inteiro segundo = 0 - 1000000
        inteiro y = 0
        enquanto (y < 25)
        {
            se (y != alvo)
            {
                inteiro z = ctx_z256(w16, b16, c16, y)
                se (z > segundo)
                {
                    segundo = z
                }
            }
            y = y + 1
        }
        se (i > 0)
        {
            escreva(" ")
        }
        escreva(z_alvo - segundo)
        i = i + 1
    }
    escreva("\n")
}

funcao logico corp_drv_m1_linha(cadeia linha, inteiro ids[], inteiro n)
{
    inteiro tam = tx.numero_caracteres(linha)
    inteiro ini = 0
    inteiro total = 0
    inteiro i = 0
    logico ok = verdadeiro
    enquanto (i < tam)
    {
        se (tx.obter_caracter(linha, i) == ' ')
        {
            se (total >= n)
            {
                ok = falso
            }
            senao se (id_do_campo(linha, ini, i - 1) != ids[total])
            {
                ok = falso
            }
            total = total + 1
            ini = i + 1
        }
        i = i + 1
    }
    se (total >= n)
    {
        ok = falso
    }
    senao se (id_do_campo(linha, ini, tam - 1) != ids[total])
    {
        ok = falso
    }
    total = total + 1
    se (total != n)
    {
        ok = falso
    }
    retorne ok
}

funcao corp_drv_gerar(inteiro w16[], inteiro b16[], inteiro prefixo[],
                      inteiro n_prefixo, inteiro maximo)
{
    inteiro saida[64]
    inteiro n = ctx_gerar(w16, b16, prefixo, n_prefixo, maximo, saida)
    se (n < 1)
    {
        escreva("ERRO_GERACAO=", 0 - n, "\n")
        retorne
    }
    inteiro parada = 0
    se (saida[n - 1] == 24)
    {
        parada = 1
    }
    ctx_imprimir_geracao(saida, n, n_prefixo, parada)
}
'@

$linesDecl = "cadeia linhas[6]`n"
for ($i = 0; $i -lt 5; $i++) {
    $linesDecl += "linhas[$i] = `"$($corpusLines[$i])`"`n"
}

$extract5 = @'
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro rex = corp_extrair(linhas, 5, entradas, alvos, nxs, diag)
se (rex != 0)
{
    escreva("FALHA_EXTRACAO=", rex, "\n")
}
'@

# --- Drivers ---------------------------------------------------------------

$drvIntegridade = $linesDecl + @'
inteiro i = 0
inteiro total = 0
logico ok = verdadeiro
enquanto (i < 5)
{
    inteiro ids[8]
    inteiro d2[2]
    inteiro n = corp_tokenizar(linhas[i], ids, d2)
    corp_drv_ids(ids, n)
    se (n != 5)
    {
        ok = falso
    }
    total = total + n
    i = i + 1
}
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro rex = corp_extrair(linhas, 5, entradas, alvos, nxs, diag)
se (rex == 0 e nxs[0] == 10 e total == 25 e ok)
{
    escreva("CORPUS=OK LINHAS=5 TOKENS=25 EXEMPLOS=10\n")
}
senao
{
    escreva("CORPUS=FALHA\n")
}
'@

$drvTokenizacao = $linesDecl + @'
inteiro i = 0
logico todos = verdadeiro
enquanto (i < 5)
{
    tokenizar(linhas[i])
    inteiro ids[8]
    inteiro d2[2]
    inteiro n = corp_tokenizar(linhas[i], ids, d2)
    corp_drv_ids(ids, n)
    se (n != 5 ou nao corp_drv_m1_linha(linhas[i], ids, n))
    {
        todos = falso
    }
    i = i + 1
}
se (todos)
{
    escreva("M1_IDS=OK\n")
}
senao
{
    escreva("M1_IDS=FALHA\n")
}
'@

$drvJanelas = $linesDecl + "`n" + $extract5 + @'
inteiro i = 0
enquanto (i < nxs[0])
{
    escreva("EXEMPLO=", i, " CTX=", entradas[i * 3], " ",
            entradas[i * 3 + 1], " ", entradas[i * 3 + 2],
            " ALVO=", alvos[i], "\n")
    i = i + 1
}
escreva("N=", nxs[0], "\n")
'@

$drvFronteiras = @'
cadeia linhas[3]
linhas[0] = "programa inicio escreva pare"
linhas[1] = "se verdadeiro faca leia pare"
linhas[2] = "enquanto falso senao retorne passo pare"
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro rex = corp_extrair(linhas, 3, entradas, alvos, nxs, diag)
inteiro i = 0
enquanto (i < nxs[0])
{
    escreva("EXEMPLO=", i, " CTX=", entradas[i * 3], " ",
            entradas[i * 3 + 1], " ", entradas[i * 3 + 2],
            " ALVO=", alvos[i], "\n")
    i = i + 1
}
logico ok = verdadeiro
se (rex != 0 ou nxs[0] != 6)
{
    ok = falso
}
se (entradas[3] != 9 ou entradas[4] != 22 ou entradas[5] != 12 ou alvos[1] != 18)
{
    ok = falso
}
se (entradas[9] != 11 ou entradas[10] != 23 ou entradas[11] != 10 ou alvos[3] != 16)
{
    ok = falso
}
se (alvos[0] != 24 ou alvos[2] != 24 ou alvos[5] != 24)
{
    ok = falso
}
i = 0
enquanto (i < nxs[0])
{
    se (alvos[i] == 1 ou alvos[i] == 9 ou alvos[i] == 11)
    {
        ok = falso
    }
    i = i + 1
}
escreva("N=", nxs[0], "\n")
escreva("SOMA=6\n")
se (ok)
{
    escreva("FRONTEIRAS=OK\n")
}
senao
{
    escreva("FRONTEIRAS=FALHA\n")
}
'@

$drvUnk = @'
cadeia uma[2]
uma[0] = "programa inicio escreva Programa pare"
inteiro ids[8]
inteiro i = 0
enquanto (i < 8)
{
    ids[i] = 77
    i = i + 1
}
inteiro d2[2]
d2[0] = 0
d2[1] = 0
inteiro r = corp_tokenizar(uma[0], ids, d2)
escreva("ERRO=", 0 - r, " LINHA=0 TOKEN=", d2[0], "\n")
logico ok = (r == -3 e d2[0] == 4 e d2[1] == 0 e corp_drv_tudo(ids, 8, 77))
se (ok)
{
    escreva("IDS_INTACTOS=OK\n")
}
senao
{
    escreva("IDS_INTACTOS=FALHA\n")
}
cadeia tres[3]
tres[0] = "programa inicio escreva verdadeiro pare"
tres[1] = "funcao inicio escreva falso pare"
tres[2] = "programa inicio escreva Programa pare"
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
i = 0
enquanto (i < 90)
{
    entradas[i] = 88
    i = i + 1
}
i = 0
enquanto (i < 30)
{
    alvos[i] = 88
    i = i + 1
}
nxs[0] = 88
r = corp_extrair(tres, 3, entradas, alvos, nxs, diag)
escreva("ERRO=", r, " LINHA=", diag[0], " TOKEN=", diag[1], "\n")
ok = (r == 3 e diag[0] == 3 e diag[1] == 4 e
      corp_drv_tudo(entradas, 90, 88) e corp_drv_tudo(alvos, 30, 88) e nxs[0] == 88)
se (ok)
{
    escreva("BUFFERS_INTACTOS=OK\n")
}
senao
{
    escreva("BUFFERS_INTACTOS=FALHA\n")
}
'@

$drvInvalido = @'
cadeia vazias[2]
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro r = corp_extrair(vazias, 0, entradas, alvos, nxs, diag)
escreva("ERRO=", r, " LINHA=", diag[0], " TOKEN=", diag[1], "\n")
cadeia casos[10]
casos[0] = " programa inicio escreva pare"
casos[1] = "Programa inicio"
casos[2] = "programa inicio escreva"
casos[3] = "programa inicio escreva verdadeiro falso leia retorne passo pare"
casos[4] = "programa inicio escreva verdadeiro"
casos[5] = "programa pare escreva pare"
casos[6] = "programa\tinicio escreva pare"
cadeia uma[2]
inteiro i = 0
enquanto (i < 7)
{
    uma[0] = casos[i]
    r = corp_extrair(uma, 1, entradas, alvos, nxs, diag)
    escreva("ERRO=", r, " LINHA=", diag[0], " TOKEN=", diag[1], "\n")
    i = i + 1
}
cadeia oito[8]
oito[0] = "programa inicio escreva pare"
oito[1] = "funcao inicio escreva pare"
oito[2] = "se verdadeiro faca pare"
oito[3] = "se falso senao pare"
oito[4] = "enquanto verdadeiro faca pare"
oito[5] = "programa inicio leia pare"
oito[6] = "funcao inicio leia pare"
oito[7] = "se verdadeiro leia pare"
r = corp_extrair(oito, 8, entradas, alvos, nxs, diag)
escreva("ERRO=", r, " LINHA=", diag[0], " TOKEN=", diag[1], "\n")
cadeia oito_tokens[2]
oito_tokens[0] = "programa inicio inteiro real logico cadeia vazio pare"
r = corp_extrair(oito_tokens, 1, entradas, alvos, nxs, diag)
escreva("LIMITE=", r, " N=", nxs[0], "\n")
'@

$drvDuplicados = @'
cadeia duas[2]
duas[0] = "programa inicio escreva verdadeiro pare"
duas[1] = "programa inicio escreva verdadeiro pare"
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro i = 0
enquanto (i < 90)
{
    entradas[i] = 99
    i = i + 1
}
i = 0
enquanto (i < 30)
{
    alvos[i] = 99
    i = i + 1
}
nxs[0] = 99
inteiro r = corp_extrair(duas, 2, entradas, alvos, nxs, diag)
escreva("ERRO=", r, " LINHA=", diag[0], " TOKEN=", diag[1], "\n")
logico ok = (r == 9 e diag[0] == 2 e diag[1] == 4 e
             corp_drv_tudo(entradas, 90, 99) e corp_drv_tudo(alvos, 30, 99) e nxs[0] == 99)
se (ok)
{
    escreva("BUFFERS_INTACTOS=OK\n")
}
senao
{
    escreva("BUFFERS_INTACTOS=FALHA\n")
}
duas[1] = "programa inicio escreva falso pare"
i = 0
enquanto (i < 90)
{
    entradas[i] = 99
    i = i + 1
}
i = 0
enquanto (i < 30)
{
    alvos[i] = 99
    i = i + 1
}
nxs[0] = 99
r = corp_extrair(duas, 2, entradas, alvos, nxs, diag)
escreva("ERRO=", r, " LINHA=", diag[0], " TOKEN=", diag[1], "\n")
ok = (r == 10 e diag[0] == 2 e diag[1] == 4 e
      corp_drv_tudo(entradas, 90, 99) e corp_drv_tudo(alvos, 30, 99) e nxs[0] == 99)
se (ok)
{
    escreva("BUFFERS_INTACTOS=OK\n")
}
senao
{
    escreva("BUFFERS_INTACTOS=FALHA\n")
}
'@

$drvCapacidade = @'
cadeia linhas[6]
linhas[0] = "programa inicio inteiro real logico cadeia vazio pare"
linhas[1] = "funcao inicio logico real cadeia vazio inteiro pare"
linhas[2] = "se verdadeiro faca leia escreva retorne passo pare"
linhas[3] = "enquanto falso faca escreva leia retorne passo pare"
linhas[4] = "para real ate passo leia faca escreva pare"
linhas[5] = "se falso senao leia retorne escreva passo pare"
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro rex = corp_extrair(linhas, 6, entradas, alvos, nxs, diag)
escreva("N=", nxs[0], "\n")
logico unicos = verdadeiro
inteiro i = 0
enquanto (i < nxs[0])
{
    inteiro j = 0
    enquanto (j < i)
    {
        se (entradas[i * 3] == entradas[j * 3] e
            entradas[i * 3 + 1] == entradas[j * 3 + 1] e
            entradas[i * 3 + 2] == entradas[j * 3 + 2])
        {
            unicos = falso
        }
        j = j + 1
    }
    i = i + 1
}
se (unicos)
{
    escreva("UNICOS=OK\n")
}
senao
{
    escreva("UNICOS=FALHA\n")
}
inteiro w16[300]
inteiro b16[25]
ctx_inicializar(w16, b16)
inteiro s[2]
inteiro r = corp_perda_total(w16, b16, entradas, alvos, nxs[0], s)
escreva("S0=", s[0], "\n")
inteiro hist[2]
r = corp_treinar(w16, b16, entradas, alvos, nxs[0], 1, hist)
escreva("HISTORICO=", hist[0], " ", hist[1], "\n")
escreva("LOTES=", (nxs[0] + 5) / 6, "\n")
corp_drv_maximos(w16, b16)
'@

$drvLotes = $linesDecl + "`n" + $extract5 + @'
inteiro wd[300]
inteiro bd[25]
ctx_inicializar(wd, bd)
inteiro hd[5]
inteiro cd = ctx_executar(wd, bd, entradas, alvos, 6, 4, hd)
escreva("H6_DIRETO=", hd[0], " ", hd[1], " ", hd[2], " ", hd[3], " ", hd[4], "\n")
inteiro wl[300]
inteiro bl[25]
ctx_inicializar(wl, bl)
inteiro hl[5]
inteiro cl = corp_treinar(wl, bl, entradas, alvos, 6, 4, hl)
escreva("H6_LOTES=", hl[0], " ", hl[1], " ", hl[2], " ", hl[3], " ", hl[4], "\n")
logico igual = corp_drv_iguais(wl, wd, 300) e corp_drv_iguais(bl, bd, 25)
se (igual)
{
    escreva("IGUAL6=OK\n")
}
senao
{
    escreva("IGUAL6=FALHA\n")
}
inteiro w10[300]
inteiro b10[25]
ctx_inicializar(w10, b10)
inteiro h10[5]
inteiro c10 = corp_treinar(w10, b10, entradas, alvos, 10, 4, h10)
escreva("H10_LOTES=", h10[0], " ", h10[1], " ", h10[2], " ", h10[3], " ", h10[4], "\n")
'@

$drvTreino = $linesDecl + "`n" + $extract5 + @'
inteiro w16[300]
inteiro b16[25]
ctx_inicializar(w16, b16)
inteiro hist[5]
inteiro r = corp_treinar(w16, b16, entradas, alvos, 10, 4, hist)
ctx_imprimir_historico(hist, 4)
corp_drv_avaliacao(w16, b16, entradas, alvos, 10)
corp_drv_margens(w16, b16, entradas, alvos, 10)
ctx_imprimir_alterados(w16, b16)
ctx_imprimir_estado(w16, b16)
'@

$drvOrdem = $linesDecl + "`n" + $extract5 + @'
inteiro wd[300]
inteiro bd[25]
ctx_inicializar(wd, bd)
inteiro hd[5]
inteiro cd = corp_treinar(wd, bd, entradas, alvos, 10, 4, hd)
escreva("ORDEM=DIRETA\n")
ctx_imprimir_historico(hd, 4)
corp_drv_avaliacao(wd, bd, entradas, alvos, 10)
corp_drv_maximos(wd, bd)
inteiro ei[90]
inteiro ai[30]
inteiro i = 0
enquanto (i < 10)
{
    ei[i * 3] = entradas[(9 - i) * 3]
    ei[i * 3 + 1] = entradas[(9 - i) * 3 + 1]
    ei[i * 3 + 2] = entradas[(9 - i) * 3 + 2]
    ai[i] = alvos[9 - i]
    i = i + 1
}
inteiro wi[300]
inteiro bi[25]
ctx_inicializar(wi, bi)
inteiro hi[5]
inteiro ci = corp_treinar(wi, bi, ei, ai, 10, 4, hi)
escreva("ORDEM=INVERSA\n")
ctx_imprimir_historico(hi, 4)
corp_drv_avaliacao(wi, bi, ei, ai, 10)
corp_drv_maximos(wi, bi)
inteiro dif = 0
i = 0
enquanto (i < 300)
{
    se (wd[i] != wi[i])
    {
        dif = dif + 1
    }
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    se (bd[i] != bi[i])
    {
        dif = dif + 1
    }
    i = i + 1
}
escreva("DIF_PARAMS=", dif, "\n")
'@

$drvGeracao = $linesDecl + "`n" + $extract5 + @'
inteiro w16[300]
inteiro b16[25]
ctx_inicializar(w16, b16)
inteiro hist[5]
inteiro r = corp_treinar(w16, b16, entradas, alvos, 10, 4, hist)
inteiro p1[3]
p1[0] = 1
p1[1] = 3
p1[2] = 17
corp_drv_gerar(w16, b16, p1, 3, 64)
inteiro p2[3]
p2[0] = 9
p2[1] = 22
p2[2] = 12
corp_drv_gerar(w16, b16, p2, 3, 64)
inteiro p3[3]
p3[0] = 11
p3[1] = 22
p3[2] = 12
corp_drv_gerar(w16, b16, p3, 3, 64)
inteiro p4[3]
p4[0] = 9
p4[1] = 23
p4[2] = 10
corp_drv_gerar(w16, b16, p4, 3, 64)
inteiro p5[3]
p5[0] = 2
p5[1] = 3
p5[2] = 17
corp_drv_gerar(w16, b16, p5, 3, 64)
inteiro p6[3]
p6[0] = 22
p6[1] = 12
p6[2] = 24
corp_drv_gerar(w16, b16, p6, 3, 64)
corp_drv_gerar(w16, b16, p1, 3, 4)
inteiro p7[3]
p7[0] = 1
p7[1] = 3
p7[2] = 0
corp_drv_gerar(w16, b16, p7, 2, 64)
'@

$drvDeterminismo = $linesDecl + "`n" + $extract5 + @'
inteiro w16[300]
inteiro b16[25]
ctx_inicializar(w16, b16)
inteiro hist[5]
inteiro r = corp_treinar(w16, b16, entradas, alvos, 10, 4, hist)
ctx_imprimir_estado(w16, b16)
ctx_imprimir_historico(hist, 4)
corp_drv_avaliacao(w16, b16, entradas, alvos, 10)
corp_drv_margens(w16, b16, entradas, alvos, 10)
inteiro p1[3]
p1[0] = 1
p1[1] = 3
p1[2] = 17
corp_drv_gerar(w16, b16, p1, 3, 64)
'@

$drvComposicao = $linesDecl + @'
inteiro i = 0
logico todos = verdadeiro
enquanto (i < 5)
{
    tokenizar(linhas[i])
    inteiro ids[8]
    inteiro d2[2]
    inteiro n = corp_tokenizar(linhas[i], ids, d2)
    corp_drv_ids(ids, n)
    se (n != 5 ou nao corp_drv_m1_linha(linhas[i], ids, n))
    {
        todos = falso
    }
    i = i + 1
}
se (todos)
{
    escreva("M1_IDS=OK\n")
}
senao
{
    escreva("M1_IDS=FALHA\n")
}
real emb[100]
inicializar_embeddings(emb)
inteiro ok3 = 0
i = 0
enquanto (i < 25)
{
    inteiro d = 0
    enquanto (d < 4)
    {
        inteiro q = ((i * 7 + d * 3) % 32) - 16
        se (emb_obter(emb, i, d) == q / 16.0)
        {
            ok3 = ok3 + 1
        }
        d = d + 1
    }
    i = i + 1
}
escreva("M3_OK=", ok3, "\n")
inteiro entradas[90]
inteiro alvos[30]
inteiro nxs[2]
inteiro diag[2]
inteiro rex = corp_extrair(linhas, 5, entradas, alvos, nxs, diag)
inteiro w7[300]
inteiro b7[25]
ctx_inicializar(w7, b7)
inteiro e4[12]
inteiro a4[4]
i = 0
enquanto (i < 4)
{
    e4[i * 3] = entradas[(6 + i) * 3]
    e4[i * 3 + 1] = entradas[(6 + i) * 3 + 1]
    e4[i * 3 + 2] = entradas[(6 + i) * 3 + 2]
    a4[i] = alvos[6 + i]
    i = i + 1
}
inteiro h1[2]
inteiro h2[2]
inteiro ep = 1
enquanto (ep <= 4)
{
    ctx_executar(w7, b7, entradas, alvos, 6, 1, h1)
    ctx_executar(w7, b7, e4, a4, 4, 1, h2)
    ep = ep + 1
}
escreva("M7_OK=", ctx_acertos(w7, b7, entradas, alvos, 10), "\n")
inteiro w8[300]
inteiro b8[25]
ctx_inicializar(w8, b8)
inteiro h8[5]
inteiro r8 = corp_treinar(w8, b8, entradas, alvos, 10, 4, h8)
escreva("M8_OK=", ctx_acertos(w8, b8, entradas, alvos, 10), "\n")
inteiro p1[3]
p1[0] = 1
p1[1] = 3
p1[2] = 17
corp_drv_gerar(w8, b8, p1, 3, 64)
'@

$drvPureza = $linesDecl + "`n" + $extract5 + @'
inteiro w16[300]
inteiro b16[25]
ctx_inicializar(w16, b16)
inteiro ws[300]
inteiro bs[25]
inteiro i = 0
enquanto (i < 300)
{
    ws[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    bs[i] = b16[i]
    i = i + 1
}
i = 0
enquanto (i < 5)
{
    inteiro ids[8]
    inteiro d2[2]
    corp_tokenizar(linhas[i], ids, d2)
    i = i + 1
}
inteiro e2[90]
inteiro a2[30]
inteiro n2[2]
inteiro dg[2]
corp_extrair(linhas, 5, e2, a2, n2, dg)
inteiro s[2]
corp_perda_total(w16, b16, entradas, alvos, 10, s)
inteiro hb[5]
inteiro c11 = corp_treinar(w16, b16, entradas, alvos, 10, 0, hb)
inteiro c12 = corp_treinar(w16, b16, entradas, alvos, 0, 4, hb)
inteiro e_bad[90]
i = 0
enquanto (i < 90)
{
    e_bad[i] = entradas[i]
    i = i + 1
}
e_bad[0] = 25
inteiro c13 = corp_treinar(w16, b16, e_bad, alvos, 10, 4, hb)
inteiro w_bad[300]
inteiro b_bad[25]
i = 0
enquanto (i < 300)
{
    w_bad[i] = ws[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    b_bad[i] = bs[i]
    i = i + 1
}
w_bad[0] = 17
inteiro c14 = corp_treinar(w_bad, b_bad, entradas, alvos, 10, 4, hb)
logico params_ok = corp_drv_iguais(w16, ws, 300) e corp_drv_iguais(b16, bs, 25)
params_ok = params_ok e (w_bad[0] == 17) e corp_drv_iguais(b_bad, bs, 25)
i = 1
enquanto (i < 300)
{
    se (w_bad[i] != ws[i])
    {
        params_ok = falso
    }
    i = i + 1
}
se (params_ok)
{
    escreva("PARAMS_INTACTOS=OK\n")
}
senao
{
    escreva("PARAMS_INTACTOS=FALHA\n")
}
inteiro idb[8]
i = 0
enquanto (i < 8)
{
    idb[i] = 55
    i = i + 1
}
cadeia ub[2]
ub[0] = "programa inicio Programa pare"
inteiro db[2]
inteiro rb = corp_tokenizar(ub[0], idb, db)
logico ids_ok = (rb == -3 e corp_drv_tudo(idb, 8, 55))
cadeia dup[2]
dup[0] = "programa inicio escreva verdadeiro pare"
dup[1] = "programa inicio escreva verdadeiro pare"
inteiro eb[90]
inteiro ab[30]
inteiro nb[2]
i = 0
enquanto (i < 90)
{
    eb[i] = 66
    i = i + 1
}
i = 0
enquanto (i < 30)
{
    ab[i] = 66
    i = i + 1
}
nb[0] = 66
inteiro re = corp_extrair(dup, 2, eb, ab, nb, db)
ids_ok = ids_ok e (re == 9) e corp_drv_tudo(eb, 90, 66) e corp_drv_tudo(ab, 30, 66) e (nb[0] == 66)
se (ids_ok)
{
    escreva("IDS_INTACTOS=OK\n")
}
senao
{
    escreva("IDS_INTACTOS=FALHA\n")
}
inteiro pref_bad[3]
pref_bad[0] = 24
pref_bad[1] = 1
pref_bad[2] = 1
inteiro saida[64]
i = 0
enquanto (i < 64)
{
    saida[i] = 99
    i = i + 1
}
inteiro ng = ctx_gerar(w16, b16, pref_bad, 3, 64, saida)
logico saida_ok = (ng == -1 e corp_drv_tudo(saida, 64, 99))
se (saida_ok)
{
    escreva("SAIDA_INTACTA=OK\n")
}
senao
{
    escreva("SAIDA_INTACTA=FALHA\n")
}
escreva("ERROS=", c11, " ", c12, " ", c13, " ", c14, "\n")
'@

# --- Saidas esperadas ------------------------------------------------------

$idsLines = @()
foreach ($row in $frozenIds) { $idsLines += "IDS=" + ($row -join " ") }

$expectedIntegridade = @()
$expectedIntegridade += $idsLines
$expectedIntegridade += "CORPUS=OK LINHAS=5 TOKENS=25 EXEMPLOS=10"

$expectedTokenizacao = @()
for ($i = 0; $i -lt 5; $i++) {
    $expectedTokenizacao += $idsLines[$i]
    $expectedTokenizacao += $idsLines[$i]
}
$expectedTokenizacao += "M1_IDS=OK"

$expectedJanelas = @()
for ($i = 0; $i -lt 10; $i++) {
    $expectedJanelas += "EXEMPLO=$i CTX=$($ENT[$i * 3]) $($ENT[$i * 3 + 1]) $($ENT[$i * 3 + 2]) ALVO=$($ALV[$i])"
}
$expectedJanelas += "N=10"

$expectedFronteiras = @(
    "EXEMPLO=0 CTX=1 3 17 ALVO=24",
    "EXEMPLO=1 CTX=9 22 12 ALVO=18",
    "EXEMPLO=2 CTX=22 12 18 ALVO=24",
    "EXEMPLO=3 CTX=11 23 10 ALVO=16",
    "EXEMPLO=4 CTX=23 10 16 ALVO=15",
    "EXEMPLO=5 CTX=10 16 15 ALVO=24",
    "N=6",
    "SOMA=6",
    "FRONTEIRAS=OK"
)

$expectedUnk = @(
    "ERRO=3 LINHA=0 TOKEN=4",
    "IDS_INTACTOS=OK",
    "ERRO=3 LINHA=3 TOKEN=4",
    "BUFFERS_INTACTOS=OK"
)

$expectedInvalido = @(
    "ERRO=1 LINHA=0 TOKEN=0",
    "ERRO=2 LINHA=1 TOKEN=0",
    "ERRO=3 LINHA=1 TOKEN=1",
    "ERRO=6 LINHA=1 TOKEN=3",
    "ERRO=7 LINHA=1 TOKEN=9",
    "ERRO=4 LINHA=1 TOKEN=0",
    "ERRO=5 LINHA=1 TOKEN=2",
    "ERRO=2 LINHA=1 TOKEN=0",
    "ERRO=8 LINHA=0 TOKEN=0",
    "LIMITE=0 N=5"
)

$expectedDuplicados = @(
    "ERRO=9 LINHA=2 TOKEN=4",
    "BUFFERS_INTACTOS=OK",
    "ERRO=10 LINHA=2 TOKEN=4",
    "BUFFERS_INTACTOS=OK"
)

$expectedCapacidade = @(
    "N=30",
    "UNICOS=OK",
    "S0=19563100",
    "HISTORICO=19563100 3361748",
    "LOTES=5",
    "MAXIMO16=7 5"
)

$expectedLotes = @(
    "H6_DIRETO=5512972 642866 330914 230044 208582",
    "H6_LOTES=5512972 642866 330914 230044 208582",
    "IGUAL6=OK",
    "H10_LOTES=8404936 1341188 651091 509249 436118"
)

$expectedTreino = @()
$expectedTreino += "HISTORICO=" + ($traj -join " ")
$expectedTreino += "PERDA=436118"
$expectedTreino += "ACERTOS=10"
$expectedTreino += "PRED=" + ($pred -join " ")
$expectedTreino += "MARGENS=" + ($margins -join " ")
$expectedTreino += "ALTERADOS_W=253"
$expectedTreino += "ALTERADOS_B=22"
$expectedTreino += $paramLines
$expectedTreino += "MAXIMO16=9 6"

$revLoss = Get-CorpLoss $revW $revB $revEnt $revAlv 10
if ($revLoss -ne 377464) { throw "Perda inversa divergente: $revLoss" }
$expectedOrdem = @()
$expectedOrdem += "ORDEM=DIRETA"
$expectedOrdem += "HISTORICO=" + ($traj -join " ")
$expectedOrdem += "PERDA=436118"
$expectedOrdem += "ACERTOS=10"
$expectedOrdem += "PRED=" + ($pred -join " ")
$expectedOrdem += "MAXIMO16=9 6"
$expectedOrdem += "ORDEM=INVERSA"
$expectedOrdem += "HISTORICO=" + ($revTraj -join " ")
$expectedOrdem += "PERDA=377464"
$expectedOrdem += "ACERTOS=8"
$expectedOrdem += "PRED=" + ($revPred -join " ")
$expectedOrdem += "MAXIMO16=7 4"
$expectedOrdem += "DIF_PARAMS=213"

$expectedGeracao = @()
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 64
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(9, 22, 12)) 64
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(11, 22, 12)) 64
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(9, 23, 10)) 64
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(2, 3, 17)) 64
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(22, 12, 24)) 64
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 4
$expectedGeracao += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3)) 64

$frozenGeracao = @(
    "GERADO=1 3 17 22 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=programa inicio escreva verdadeiro pare",
    "GERADO=9 22 12 17 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=se verdadeiro faca escreva pare",
    "GERADO=11 22 12 18 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=enquanto verdadeiro faca leia pare",
    "GERADO=9 23 10 18 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=se falso senao leia pare",
    "GERADO=2 3 17 23 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=funcao inicio escreva falso pare",
    "GERADO=22 12 24", "N=3", "PASSOS=0", "PARADA=PARE",
    "TEXTO=verdadeiro faca pare",
    "GERADO=1 3 17 22", "N=4", "PASSOS=1", "PARADA=MAXIMO",
    "TEXTO=programa inicio escreva verdadeiro",
    "GERADO=1 3 12 12 19 18 24", "N=7", "PASSOS=5", "PARADA=PARE",
    "TEXTO=programa inicio faca faca e leia pare"
)
if (($expectedGeracao -join "`n") -cne ($frozenGeracao -join "`n")) {
    throw "Geracao divergente da spec"
}

$expectedDeterminismo = @()
$expectedDeterminismo += $paramLines
$expectedDeterminismo += "MAXIMO16=9 6"
$expectedDeterminismo += "HISTORICO=" + ($traj -join " ")
$expectedDeterminismo += "PERDA=436118"
$expectedDeterminismo += "ACERTOS=10"
$expectedDeterminismo += "PRED=" + ($pred -join " ")
$expectedDeterminismo += "MARGENS=" + ($margins -join " ")
$expectedDeterminismo += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 64

$expectedComposicao = @()
for ($i = 0; $i -lt 5; $i++) {
    $expectedComposicao += $idsLines[$i]
    $expectedComposicao += $idsLines[$i]
}
$expectedComposicao += "M1_IDS=OK"
$expectedComposicao += "M3_OK=100"
$expectedComposicao += "M7_OK=10"
$expectedComposicao += "M8_OK=10"
$expectedComposicao += Get-CorpGenLines $finalW $finalB ([int[]]@(1, 3, 17)) 64

$expectedPureza = @(
    "PARAMS_INTACTOS=OK",
    "IDS_INTACTOS=OK",
    "SAIDA_INTACTA=OK",
    "ERROS=11 12 13 14"
)

# --- Casos -----------------------------------------------------------------

$cases = @(
    @{ Name = "corp_integridade"; Driver = $drvIntegridade; Expected = $expectedIntegridade; Compose = "corp" },
    @{ Name = "corp_tokenizacao"; Driver = $drvTokenizacao; Expected = $expectedTokenizacao; Compose = "corp" },
    @{ Name = "corp_janelas"; Driver = $drvJanelas; Expected = $expectedJanelas; Compose = "corp" },
    @{ Name = "corp_fronteiras"; Driver = $drvFronteiras; Expected = $expectedFronteiras; Compose = "corp" },
    @{ Name = "corp_unk"; Driver = $drvUnk; Expected = $expectedUnk; Compose = "corp" },
    @{ Name = "corp_invalido"; Driver = $drvInvalido; Expected = $expectedInvalido; Compose = "corp" },
    @{ Name = "corp_duplicados"; Driver = $drvDuplicados; Expected = $expectedDuplicados; Compose = "corp" },
    @{ Name = "corp_capacidade"; Driver = $drvCapacidade; Expected = $expectedCapacidade; Compose = "corp" },
    @{ Name = "corp_lotes"; Driver = $drvLotes; Expected = $expectedLotes; Compose = "corp" },
    @{ Name = "corp_treino"; Driver = $drvTreino; Expected = $expectedTreino; Compose = "corp" },
    @{ Name = "corp_ordem"; Driver = $drvOrdem; Expected = $expectedOrdem; Compose = "corp" },
    @{ Name = "corp_geracao"; Driver = $drvGeracao; Expected = $expectedGeracao; Compose = "corp" },
    @{ Name = "corp_determinismo_a"; Driver = $drvDeterminismo; Expected = $expectedDeterminismo; Compose = "corp" },
    @{ Name = "corp_determinismo_b"; Driver = $drvDeterminismo; Expected = $expectedDeterminismo; Compose = "corp" },
    @{ Name = "corp_composicao"; Driver = $drvComposicao; Expected = $expectedComposicao; Compose = "full" },
    @{ Name = "corp_pureza"; Driver = $drvPureza; Expected = $expectedPureza; Compose = "corp" }
)

if ($cases.Count -ne 16) { throw "Quantidade de casos: $($cases.Count); esperado 16" }
$names = @($cases | ForEach-Object { $_.Name })
if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
    throw "Nome de caso duplicado na tabela de casos"
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

$indentedHelpers = Add-PortugolIndent $corpHelpers

foreach ($case in $cases) {
    $fragments = switch ($case.Compose) {
        "corp" { $tokenizerFragment + "`n`n" + $sourceFragment + "`n`n" + $contextFragment }
        "full" {
            $tokenizerFragment + "`n`n" + $embeddingFragment + "`n`n" +
            $sourceFragment + "`n`n" + $contextFragment
        }
        default { throw "Compose desconhecido: $($case.Compose)" }
    }

    $content = "programa`n{`n" +
        $fragments + "`n`n" +
        $indentedHelpers + "`n`n" +
        "    funcao inicio()`n" +
        "    {`n" +
        (Add-PortugolIndent $case.Driver) + "`n" +
        "    }`n" +
        "}`n"

    $expectedText = @($case.Expected) -join "`n"

    $porPath = Join-Path $outFull ($case.Name + ".por")
    $expectedPath = Join-Path $outFull ($case.Name + ".expected")

    [IO.File]::WriteAllText($porPath, $content, $utf8NoBom)
    [IO.File]::WriteAllText($expectedPath, $expectedText, $utf8NoBom)

    Assert-AsciiLf $porPath
    Assert-Utf8NoBom $expectedPath
    $expectedBytes = [IO.File]::ReadAllBytes($expectedPath)
    if ($expectedBytes.Length -eq 0) { throw "Expected vazio: $expectedPath" }
    if ($expectedBytes[$expectedBytes.Length - 1] -eq 0x0A) {
        throw "Arquivo .expected termina em LF: $expectedPath"
    }
    if ($expectedText.IndexOf("`r") -ge 0) { throw "CR em .expected: $expectedPath" }
    foreach ($line in @($case.Expected)) {
        if ($line -ne $line.Trim()) { throw "Espaco nas pontas em .expected: $expectedPath" }
        foreach ($b in [Text.Encoding]::ASCII.GetBytes($line)) {
            if ($b -lt 0x20 -or $b -gt 0x7E) { throw "Byte nao ASCII em .expected: $expectedPath" }
        }
    }
}

$generatedExpected = @(Get-ChildItem -Path $outFull -Filter "*.expected" -File)
$generatedPor = @(Get-ChildItem -Path $outFull -Filter "*.por" -File)
if ($generatedExpected.Count -ne 16 -or $generatedPor.Count -ne 16) {
    throw "Arquivos gerados: $($generatedPor.Count) .por e $($generatedExpected.Count) .expected; esperado 16/16"
}

Write-Host "Generated $($cases.Count) corpus cases in $OutputRoot"
