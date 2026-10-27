<#
.SYNOPSIS
    Gera os 16 casos .por e .expected do contexto de multiplos tokens (M7)
    em temp/context-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/contexto.por (e, em ctx_composicao, tambem os fragmentos M1/M3/M4/M5/M6)
    a um driver. Os valores esperados sao recalculados aqui por um oraculo
    inteiro independente (W16[300], b16, c16, Z256, delta256, r, treino, perda,
    geracao), sem [double] e sem ler a saida do .por. As tabelas canonicas de
    inicializacao e final, a trajetoria, as margens, as ablacoes e os blocos de
    geracao sao conferidos como literais contra a spec. Tudo e gravado em UTF-8
    sem BOM, LF; .expected sem LF final.
#>

param(
    [string]$SourcePath = "src/contexto.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$NetworkSourcePath = "src/rede.por",
    [string]$TrainingSourcePath = "src/treino.por",
    [string]$GenerationSourcePath = "src/gerador.por",
    [string]$OutputRoot = "temp/context-tests"
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

# --- Oraculo inteiro independente (contexto M7) ----------------------------

function Get-CtxInitW {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($k = 0; $k -lt 3; $k++) {
            for ($d = 0; $d -lt 4; $d++) {
                if ($k -lt 2) {
                    $row[$k * 4 + $d] = 0
                } else {
                    $row[$k * 4 + $d] = (($y * 7 + $d * 5) % 25) - 12
                }
            }
        }
        $w[$y] = $row
    }
    return $w
}

function Get-CtxB16 {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-CtxW {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 12
        for ($p = 0; $p -lt 12; $p++) { $row[$p] = $W[$y][$p] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-CtxB {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-CtxEmb16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

# c16 a partir de uma sequencia de 1..64 tokens (janela dos 3 ultimos, PAD zero).
function Get-CtxC16 {
    param([int[]]$Seq)
    $c = New-Object 'int[]' 12
    for ($k = 0; $k -lt 3; $k++) {
        $pos = $Seq.Count - 3 + $k
        if ($pos -ge 0) {
            for ($d = 0; $d -lt 4; $d++) {
                $c[$k * 4 + $d] = Get-CtxEmb16 $Seq[$pos] $d
            }
        }
    }
    return $c
}

function Get-CtxC16FromExample {
    param([int[]]$Entradas, [int]$N)
    return Get-CtxC16 ([int[]]@($Entradas[$N * 3], $Entradas[$N * 3 + 1], $Entradas[$N * 3 + 2]))
}

function Get-CtxZ256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y)
    [long]$soma = 0
    for ($p = 0; $p -lt 12; $p++) {
        $soma += [long]$W[$Y][$p] * [long]$C[$p]
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-CtxDelta256 {
    param([hashtable]$W, [hashtable]$B, [int[]]$C, [int]$Y, [int]$Alvo)
    [long]$z = Get-CtxZ256 $W $B $C $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-CtxArgmax {
    param([hashtable]$W, [hashtable]$B, [int[]]$C)
    $melhor = 0
    [long]$melhorValor = Get-CtxZ256 $W $B $C 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-CtxZ256 $W $B $C $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-CtxLoss {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-CtxDelta256 $W $B $c $y $Alvos[$i]
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-CtxRoundHalfAway {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

function Invoke-CtxTraining {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-CtxLoss $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            [int[]]$c = Get-CtxC16FromExample $Entradas $i
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-CtxDelta256 $W $B $c $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($p = 0; $p -lt 12; $p++) {
                    [long]$novo = Get-CtxRoundHalfAway (
                        2048 * [long]$W[$y][$p] - $delta[$y] * [long]$c[$p]) 2048
                    $W[$y][$p] = $novo
                    if ([Math]::Abs($novo) -gt 16) {
                        return [pscustomobject]@{ Code = 5; History = $history }
                    }
                }
                [long]$novoB = Get-CtxRoundHalfAway (128 * [long]$B[$y] - $delta[$y]) 128
                $B[$y] = $novoB
                if ([Math]::Abs($novoB) -gt 16) {
                    return [pscustomobject]@{ Code = 5; History = $history }
                }
            }
        }
        $history[$ep] = Get-CtxLoss $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history }
}

function Get-CtxGeneration {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $total = $Prefixo.Count
    for ($i = 0; $i -lt $total; $i++) { $saida[$i] = $Prefixo[$i] }
    if ($saida[$total - 1] -eq 24) {
        return [pscustomobject]@{ Saida = $saida; Total = $total }
    }
    while ($total -lt $Maximo) {
        [int[]]$seq = @($saida[0..($total - 1)])
        [int[]]$c = Get-CtxC16 $seq
        $proximo = Get-CtxArgmax $W $B $c
        $saida[$total] = $proximo
        $total++
        if ($proximo -eq 24) { break }
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
}

function Get-CtxPalavra {
    param([int]$Id)
    $palavras = @(
        "UNK", "programa", "funcao", "inicio", "inteiro", "real", "logico",
        "cadeia", "vazio", "se", "senao", "enquanto", "faca", "para", "ate",
        "passo", "retorne", "escreva", "leia", "e", "ou", "nao", "verdadeiro",
        "falso", "pare"
    )
    return $palavras[$Id]
}

function Get-CtxContextLine {
    param([int[]]$Seq)
    [int[]]$c = Get-CtxC16 $Seq
    return "CTX16=$($Seq.Count) " + ($c -join " ")
}

function Get-CtxParam16Line {
    param([hashtable]$W, [hashtable]$B, [int]$Y)
    return "PARAM16=$Y " + ($W[$Y] -join " ") + " " + $B[$Y]
}

function Get-CtxGeracaoLines {
    param([hashtable]$W, [hashtable]$B, [int[]]$Prefixo, [int]$Maximo)
    $g = Get-CtxGeneration $W $B $Prefixo $Maximo
    $ids = @($g.Saida[0..($g.Total - 1)])
    $parada = if ($ids[$ids.Count - 1] -eq 24) { "PARE" } else { "MAXIMO" }
    $texto = (@($ids | ForEach-Object { Get-CtxPalavra $_ }) -join " ")
    $lines = @()
    $lines += "GERADO=" + ($ids -join " ")
    $lines += "N=$($g.Total)"
    $lines += "PASSOS=$($g.Total - $Prefixo.Count)"
    $lines += "PARADA=$parada"
    $lines += "TEXTO=$texto"
    return $lines
}

function Get-CtxMargins {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $out = @()
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        [long]$zAlvo = Get-CtxZ256 $W $B $c $Alvos[$i]
        [long]$segundo = -1000000
        for ($y = 0; $y -lt 25; $y++) {
            if ($y -ne $Alvos[$i]) {
                [long]$z = Get-CtxZ256 $W $B $c $y
                if ($z -gt $segundo) { $segundo = $z }
            }
        }
        $out += ($zAlvo - $segundo)
    }
    return $out
}

function Get-CtxAblation {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N, [string]$Modo)
    $x = Copy-CtxW $W
    for ($y = 0; $y -lt 25; $y++) {
        for ($p = 0; $p -lt 12; $p++) {
            if ($Modo -eq "ultimo" -and $p -lt 8) { $x[$y][$p] = 0 }
            if ($Modo -eq "antigos" -and $p -ge 8) { $x[$y][$p] = 0 }
        }
    }
    $acertos = 0
    for ($i = 0; $i -lt $N; $i++) {
        [int[]]$c = Get-CtxC16FromExample $Entradas $i
        if ((Get-CtxArgmax $x $B $c) -eq $Alvos[$i]) { $acertos++ }
    }
    return [pscustomobject]@{ Acertos = $acertos; S = (Get-CtxLoss $x $B $Entradas $Alvos $N) }
}

function Get-CtxMaxUltimo {
    param([int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($t = 0; $t -lt 25; $t++) {
        $melhor = 0
        for ($i = 0; $i -lt $N; $i++) {
            if ($Entradas[$i * 3 + 2] -eq $t) {
                $cont = 0
                for ($j = 0; $j -lt $N; $j++) {
                    if ($Entradas[$j * 3 + 2] -eq $t -and $Alvos[$j] -eq $Alvos[$i]) { $cont++ }
                }
                if ($cont -gt $melhor) { $melhor = $cont }
            }
        }
        $total += $melhor
    }
    return $total
}

function Get-CtxBagKey {
    param([int[]]$Entradas, [int]$I)
    $a = $Entradas[$I * 3]
    $b = $Entradas[$I * 3 + 1]
    $c = $Entradas[$I * 3 + 2]
    if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
    if ($b -gt $c) { $t = $b; $b = $c; $c = $t }
    if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
    return $a * 625 + $b * 25 + $c
}

function Get-CtxMaxBag {
    param([int[]]$Entradas, [int[]]$Alvos, [int]$N)
    $total = 0
    for ($i = 0; $i -lt $N; $i++) {
        $primeiro = $true
        for ($j = 0; $j -lt $i; $j++) {
            if ((Get-CtxBagKey $Entradas $j) -eq (Get-CtxBagKey $Entradas $i)) { $primeiro = $false }
        }
        if ($primeiro) {
            $melhor = 0
            for ($j = 0; $j -lt $N; $j++) {
                if ((Get-CtxBagKey $Entradas $j) -eq (Get-CtxBagKey $Entradas $i)) {
                    $cont = 0
                    for ($k = 0; $k -lt $N; $k++) {
                        if ((Get-CtxBagKey $Entradas $k) -eq (Get-CtxBagKey $Entradas $i) -and
                            $Alvos[$k] -eq $Alvos[$j]) { $cont++ }
                    }
                    if ($cont -gt $melhor) { $melhor = $cont }
                }
            }
            $total += $melhor
        }
    }
    return $total
}

# --- Fontes ----------------------------------------------------------------

$repoRoot = (Get-Location).Path
$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
$tokenizerFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TokenizerSourcePath))
$embeddingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $EmbeddingSourcePath))
$networkFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $NetworkSourcePath))
$trainingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TrainingSourcePath))
$generationFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $GenerationSourcePath))
foreach ($path in @($sourceFull, $tokenizerFull, $embeddingFull, $networkFull, $trainingFull, $generationFull)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Fragmento nao encontrado: $path" }
    Assert-Utf8NoBom $path
    Assert-AsciiLf $path
}

$ctxText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sourceFull))
$ctxCode = (($ctxText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
$ctxCode = [regex]::Replace($ctxCode, '"[^"]*"', '""')
foreach ($forbidden in @(
    "programa", "inicio", "inclua", "Matematica", "aleatorio", "tempo",
    "leia", "softmax", "exp(", "temperatura", "top_", "real"
)) {
    if ($ctxCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "src/contexto.por contem identificador proibido: $forbidden"
    }
}
foreach ($required in @(
    "CTX_K = 3", "CTX_TAM_VOCAB = 25", "CTX_DIM = 4", "CTX_ENTRADAS = 12",
    "CTX_TOTAL_W = 300", "CTX_TOTAL_B = 25", "CTX_PARAMS = 325",
    "CTX_MAX_EXEMPLOS = 6", "CTX_MAX_EPOCAS = 32", "CTX_GRADE = 16",
    "CTX_ESCALA_PERDA = 131072", "CTX_LIMITE = 16", "CTX_TAXA_NUM = 1",
    "CTX_TAXA_DEN = 8", "CTX_DIV_W = 2048", "CTX_DIV_B = 128",
    "CTX_EPOCAS = 7", "CTX_TOKENS_MAX = 64",
    "funcao logico ctx_id_valido", "funcao logico ctx_n_valido",
    "funcao logico ctx_epocas_validas", "funcao logico ctx_maximo_valido",
    "funcao logico ctx_prefixo_valido", "funcao logico ctx_params_validos",
    "funcao inteiro ctx_validar", "funcao inteiro ctx_validar_geracao",
    "funcao inteiro ctx_e16", "funcao ctx_montar_contexto",
    "funcao ctx_contexto_de_exemplo", "funcao inteiro ctx_z256",
    "funcao inteiro ctx_argmax", "funcao inteiro ctx_perda_escalada",
    "funcao inteiro ctx_acertos", "funcao inteiro ctx_div_arredondada",
    "funcao ctx_inicializar", "funcao inteiro ctx_executar",
    "funcao inteiro ctx_gerar", "funcao ctx_imprimir_config",
    "funcao ctx_imprimir_validacao", "funcao ctx_imprimir_avaliacao",
    "funcao ctx_imprimir_historico", "funcao ctx_imprimir_param16",
    "funcao ctx_imprimir_estado", "funcao ctx_imprimir_alterados",
    "funcao ctx_imprimir_contexto", "funcao ctx_imprimir_geracao"
)) {
    if ($ctxText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "src/contexto.por nao contem: $required"
    }
}
foreach ($dep in @("treino_", "gerador_", "emb_", "rede_", "tokenizar")) {
    if ($ctxCode.IndexOf($dep, [StringComparison]::Ordinal) -ge 0) {
        throw "src/contexto.por depende de simbolo externo: $dep"
    }
}

$ctxFragment = $ctxText.TrimEnd("`r", "`n")
$tokenizerFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($tokenizerFull)).TrimEnd("`r", "`n")
$embeddingFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($embeddingFull)).TrimEnd("`r", "`n")
$networkFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($networkFull)).TrimEnd("`r", "`n")
$trainingFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($trainingFull)).TrimEnd("`r", "`n")
$generationFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($generationFull)).TrimEnd("`r", "`n")

# --- Estado canonico e treinado --------------------------------------------

$ENT = [int[]]@(9, 12, 13, 12, 13, 14, 12, 9, 13, 9, 13, 12, 13, 12, 9, 14, 12, 13)
$ALV = [int[]]@(14, 24, 10, 24, 11, 9)

$initW = Get-CtxInitW
$initB = Get-CtxB16
$finalW = Copy-CtxW $initW
$finalB = Copy-CtxB $initB
$train7 = Invoke-CtxTraining $finalW $finalB $ENT $ALV 6 7
if ($train7.Code -ne 0) { throw "Oraculo de treino retornou codigo $($train7.Code)" }
$traj7 = $train7.History

$frozenInit = @(
    "0 0 0 0 0 0 0 0 0 -12 -7 -2 3 -4",
    "1 0 0 0 0 0 0 0 0 -5 0 5 10 3",
    "2 0 0 0 0 0 0 0 0 2 7 12 -8 1",
    "3 0 0 0 0 0 0 0 0 9 -11 -6 -1 -1",
    "4 0 0 0 0 0 0 0 0 -9 -4 1 6 -3",
    "5 0 0 0 0 0 0 0 0 -2 3 8 -12 4",
    "6 0 0 0 0 0 0 0 0 5 10 -10 -5 2",
    "7 0 0 0 0 0 0 0 0 12 -8 -3 2 0",
    "8 0 0 0 0 0 0 0 0 -6 -1 4 9 -2",
    "9 0 0 0 0 0 0 0 0 1 6 11 -9 -4",
    "10 0 0 0 0 0 0 0 0 8 -12 -7 -2 3",
    "11 0 0 0 0 0 0 0 0 -10 -5 0 5 1",
    "12 0 0 0 0 0 0 0 0 -3 2 7 12 -1",
    "13 0 0 0 0 0 0 0 0 4 9 -11 -6 -3",
    "14 0 0 0 0 0 0 0 0 11 -9 -4 1 4",
    "15 0 0 0 0 0 0 0 0 -7 -2 3 8 2",
    "16 0 0 0 0 0 0 0 0 0 5 10 -10 0",
    "17 0 0 0 0 0 0 0 0 7 12 -8 -3 -2",
    "18 0 0 0 0 0 0 0 0 -11 -6 -1 4 -4",
    "19 0 0 0 0 0 0 0 0 -4 1 6 11 3",
    "20 0 0 0 0 0 0 0 0 3 8 -12 -7 1",
    "21 0 0 0 0 0 0 0 0 10 -10 -5 0 -1",
    "22 0 0 0 0 0 0 0 0 -8 -3 2 7 -3",
    "23 0 0 0 0 0 0 0 0 -1 4 9 -11 4",
    "24 0 0 0 0 0 0 0 0 6 11 -9 -4 2"
)
for ($y = 0; $y -lt 25; $y++) {
    $row = "$y " + ($initW[$y] -join " ") + " " + $initB[$y]
    if ($row -cne $frozenInit[$y]) {
        throw "Tabela inicial divergente em y=$y. Oraculo: [$row]; spec: [$($frozenInit[$y])]"
    }
}

$frozenFinal = @(
    "0 2 -2 -2 0 2 -3 0 1 -6 -1 -3 -1 -2",
    "1 0 1 0 1 0 -2 2 3 -3 2 1 5 5",
    "2 0 2 2 0 0 2 1 0 0 3 10 -9 2",
    "3 -2 -4 2 1 0 0 -2 -2 7 -8 -4 0 -2",
    "4 1 -1 -1 0 3 -2 2 2 -5 1 -4 3 -1",
    "5 -1 1 1 -1 0 -1 0 0 -2 2 9 -11 2",
    "6 -1 3 -2 -2 -3 2 -2 -3 1 4 -3 1 -2",
    "7 0 -5 2 2 -1 1 -1 -2 8 -5 -2 2 -1",
    "8 1 0 0 1 2 -1 1 2 -3 1 -1 5 1",
    "9 -7 2 0 1 1 5 0 1 2 4 9 -9 2",
    "10 -1 -3 2 1 0 -4 -2 -3 7 -5 -4 -1 1",
    "11 2 4 -3 -3 3 -4 4 1 -3 -4 -3 3 3",
    "12 1 2 2 1 1 0 2 3 -2 2 1 6 2",
    "13 0 1 0 -3 -2 4 -3 -2 1 4 -5 0 -5",
    "14 6 -7 3 2 -4 1 4 -1 2 -1 -4 0 -2",
    "15 1 1 1 0 0 -2 2 1 -4 0 -1 5 3",
    "16 1 2 -1 0 0 1 0 1 0 2 11 -10 0",
    "17 -1 3 -1 -1 -1 4 -1 -3 2 4 -3 2 -5",
    "18 2 0 -2 -1 2 -4 1 1 -5 -1 -5 2 0",
    "19 0 3 1 0 -1 -2 2 3 -2 1 2 7 5",
    "20 -1 1 -3 -2 -1 2 -2 -4 1 3 -5 0 -4",
    "21 -2 -5 2 3 -1 1 -3 -2 7 -6 -3 0 -2",
    "22 1 0 0 0 2 -2 1 2 -5 1 -2 3 0",
    "23 0 2 0 -1 -1 0 0 0 -1 2 10 -10 3",
    "24 0 3 -2 -1 -1 8 -4 -5 0 2 -4 4 0"
)
for ($y = 0; $y -lt 25; $y++) {
    $row = "$y " + ($finalW[$y] -join " ") + " " + $finalB[$y]
    if ($row -cne $frozenFinal[$y]) {
        throw "Tabela final divergente em y=$y. Oraculo: [$row]; spec: [$($frozenFinal[$y])]"
    }
}

$frozenTraj = @(6728768, 465936, 282923, 216490, 193677, 183943, 167288, 153027)
for ($e = 0; $e -le 7; $e++) {
    if ($traj7[$e] -ne $frozenTraj[$e]) {
        throw "Trajetoria divergente em S$e`: $($traj7[$e]) vs $($frozenTraj[$e])"
    }
}

$finalPred = @()
$finalAcc = 0
for ($i = 0; $i -lt 6; $i++) {
    [int[]]$c = Get-CtxC16FromExample $ENT $i
    $p = Get-CtxArgmax $finalW $finalB $c
    $finalPred += $p
    if ($p -eq $ALV[$i]) { $finalAcc++ }
}
if (($finalPred -join " ") -cne "14 24 10 24 11 9") {
    throw "PRED final divergente: $($finalPred -join ' ')"
}
if ($finalAcc -ne 6) { throw "Acertos finais: $finalAcc; esperado 6" }

$initPred = @()
$initAcc = 0
for ($i = 0; $i -lt 6; $i++) {
    [int[]]$c = Get-CtxC16FromExample $ENT $i
    $p = Get-CtxArgmax $initW $initB $c
    $initPred += $p
    if ($p -eq $ALV[$i]) { $initAcc++ }
}
if (($initPred -join " ") -cne "6 11 6 19 10 6") {
    throw "PRED inicial divergente: $($initPred -join ' ')"
}

$margins = Get-CtxMargins $finalW $finalB $ENT $ALV 6
if (($margins -join " ") -cne "142 151 156 174 201 167") {
    throw "Margens divergentes: $($margins -join ' ')"
}

$ablFull = Get-CtxAblation $finalW $finalB $ENT $ALV 6 "full"
$ablUltimo = Get-CtxAblation $finalW $finalB $ENT $ALV 6 "ultimo"
$ablAntigos = Get-CtxAblation $finalW $finalB $ENT $ALV 6 "antigos"
$ultimoMax = Get-CtxMaxUltimo $ENT $ALV 6
$bagMax = Get-CtxMaxBag $ENT $ALV 6
if ($ablFull.Acertos -ne 6 -or $ablFull.S -ne 153027) { throw "Ablacao full divergente" }
if ($ablUltimo.Acertos -ne 1 -or $ablUltimo.S -ne 916888) { throw "Ablacao ultimo divergente" }
if ($ablAntigos.Acertos -ne 6 -or $ablAntigos.S -ne 717503) { throw "Ablacao antigos divergente" }
if ($ultimoMax -ne 4) { throw "Limite ultimo token: $ultimoMax; esperado 4" }
if ($bagMax -ne 2) { throw "Limite invariante a ordem: $bagMax; esperado 2" }

# Oitava epoca: ponto fixo.
$probeW = Copy-CtxW $finalW
$probeB = Copy-CtxB $finalB
$train8 = Invoke-CtxTraining $probeW $probeB $ENT $ALV 6 1
if ($train8.Code -ne 0) { throw "Oraculo da oitava epoca retornou codigo $($train8.Code)" }
$s8 = $train8.History[1]
$mudouW = 0
$mudouB = 0
for ($y = 0; $y -lt 25; $y++) {
    for ($p = 0; $p -lt 12; $p++) {
        if ($probeW[$y][$p] -ne $finalW[$y][$p]) { $mudouW++ }
    }
    if ($probeB[$y] -ne $finalB[$y]) { $mudouB++ }
}
if ($s8 -ne 153027 -or $mudouW -ne 0 -or $mudouB -ne 0) {
    throw "Ponto fixo divergente: S8=$s8 MUDOU_W=$mudouW MUDOU_B=$mudouB"
}

# --- Blocos canonicos de geracao -------------------------------------------

$genCadeia = Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 64
$frozenCadeia = @(
    "GERADO=9 12 13 14 24", "N=5", "PASSOS=2", "PARADA=PARE",
    "TEXTO=se faca para ate pare"
)
if (($genCadeia -join "`n") -cne ($frozenCadeia -join "`n")) {
    throw "Oraculo divergiu de ctx_geracao_cadeia"
}

$genLimites = @()
$genLimites += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 4
$genLimites += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 3
$genLimites += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(24)) 64
$genLimites += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(12, 24)) 64
$frozenLimites = @(
    "GERADO=9 12 13 14", "N=4", "PASSOS=1", "PARADA=MAXIMO", "TEXTO=se faca para ate",
    "GERADO=9 12 13", "N=3", "PASSOS=0", "PARADA=MAXIMO", "TEXTO=se faca para",
    "GERADO=24", "N=1", "PASSOS=0", "PARADA=PARE", "TEXTO=pare",
    "GERADO=12 24", "N=2", "PASSOS=0", "PARADA=PARE", "TEXTO=faca pare"
)
if (($genLimites -join "`n") -cne ($frozenLimites -join "`n")) {
    throw "Oraculo divergiu de ctx_geracao_limites"
}

$genSemente = @()
$genSemente += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9)) 10
$genSemente += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(12)) 10
$frozenSemente = @(
    "GERADO=9 10 11 14 11 19 11 19 11 19", "N=10", "PASSOS=9", "PARADA=MAXIMO",
    "TEXTO=se senao enquanto ate enquanto e enquanto e enquanto e",
    "GERADO=12 19 11 19 11 19 11 19 11 19", "N=10", "PASSOS=9", "PARADA=MAXIMO",
    "TEXTO=faca e enquanto e enquanto e enquanto e enquanto e"
)
if (($genSemente -join "`n") -cne ($frozenSemente -join "`n")) {
    throw "Oraculo divergiu de ctx_geracao_semente"
}

$gen64 = Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9)) 64
$frozen64Prefix = "GERADO=9 10 11 14"
for ($i = 0; $i -lt 30; $i++) { $frozen64Prefix += " 11 19" }
if ((@($gen64[0] -split " ")).Count -ne 64) { throw "Bloco de 64 tokens com contagem errada" }
if ($gen64[0] -cne $frozen64Prefix) { throw "Bloco de 64 tokens divergente: [$($gen64[0])]" }
if ($gen64[1] -cne "N=64" -or $gen64[2] -cne "PASSOS=63" -or $gen64[3] -cne "PARADA=MAXIMO") {
    throw "Cauda do bloco de 64 tokens divergente"
}

# Trinta e duas epocas: o oraculo tambem confere o caso de limite.
$limW = Copy-CtxW $initW
$limB = Copy-CtxB $initB
$train32 = Invoke-CtxTraining $limW $limB $ENT $ALV 6 32
if ($train32.Code -ne 0) { throw "Oraculo de 32 epocas retornou codigo $($train32.Code)" }
if ($train32.History.Count -ne 33) { throw "Historico de 32 epocas com $($train32.History.Count) valores" }
$limAcc = 0
for ($i = 0; $i -lt 6; $i++) {
    [int[]]$c = Get-CtxC16FromExample $ENT $i
    if ((Get-CtxArgmax $limW $limB $c) -eq $ALV[$i]) { $limAcc++ }
}
if ($limAcc -ne 6) { throw "Acertos apos 32 epocas: $limAcc" }
$genLim64 = Get-CtxGeracaoLines $limW $limB ([int[]]@(9)) 64
if ($genLim64[1] -cne "N=64" -or $genLim64[2] -cne "PASSOS=63") {
    throw "Geracao de 64 tokens apos 32 epocas divergente"
}

# --- Helpers em Portugol (escopo global do driver) -------------------------

$ctxHelpers = @'
    funcao ct_load_exemplos(inteiro entradas[], inteiro alvos[])
    {
        entradas[0] = 9
        entradas[1] = 12
        entradas[2] = 13
        entradas[3] = 12
        entradas[4] = 13
        entradas[5] = 14
        entradas[6] = 12
        entradas[7] = 9
        entradas[8] = 13
        entradas[9] = 9
        entradas[10] = 13
        entradas[11] = 12
        entradas[12] = 13
        entradas[13] = 12
        entradas[14] = 9
        entradas[15] = 14
        entradas[16] = 12
        entradas[17] = 13
        alvos[0] = 14
        alvos[1] = 24
        alvos[2] = 10
        alvos[3] = 24
        alvos[4] = 11
        alvos[5] = 9
    }

    funcao logico ct_iguais(inteiro a[], inteiro b[], inteiro n)
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

    funcao ct_erro_treino(inteiro codigo)
    {
        se (codigo == 1)
        {
            escreva("ERRO=EXEMPLOS_INVALIDOS\n")
        }
        senao se (codigo == 2)
        {
            escreva("ERRO=EPOCAS_INVALIDAS\n")
        }
        senao se (codigo == 3)
        {
            escreva("ERRO=ID_INVALIDO\n")
        }
        senao se (codigo == 4)
        {
            escreva("ERRO=PARAMETROS_INVALIDOS\n")
        }
        senao se (codigo == 5)
        {
            escreva("ERRO=ESTOURO_NUMERICO\n")
        }
    }

    funcao ct_erro_geracao(inteiro codigo)
    {
        se (codigo == 1)
        {
            escreva("ERRO=PREFIXO_INVALIDO\n")
        }
        senao se (codigo == 2)
        {
            escreva("ERRO=MAXIMO_INVALIDO\n")
        }
        senao se (codigo == 3)
        {
            escreva("ERRO=PARAMETROS_INVALIDOS\n")
        }
    }

    funcao ct_exec_invalido(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[],
                            inteiro n, inteiro epocas)
    {
        inteiro sw[300]
        inteiro sb[25]
        inteiro i = 0
        enquanto (i < 300)
        {
            sw[i] = w16[i]
            i = i + 1
        }
        i = 0
        enquanto (i < 25)
        {
            sb[i] = b16[i]
            i = i + 1
        }
        inteiro historico[33]
        inteiro codigo = ctx_executar(w16, b16, entradas, alvos, n, epocas, historico)
        ct_erro_treino(codigo)
        se (ct_iguais(w16, sw, 300) e ct_iguais(b16, sb, 25))
        {
            escreva("INTACTO=OK\n")
        }
        senao
        {
            escreva("INTACTO=FALHA\n")
        }
    }

    funcao ct_ger_invalido(inteiro w16[], inteiro b16[], inteiro prefixo[],
                           inteiro n_prefixo, inteiro maximo)
    {
        inteiro saida[64]
        inteiro i = 0
        enquanto (i < 64)
        {
            saida[i] = 99
            i = i + 1
        }
        inteiro codigo = 0 - ctx_gerar(w16, b16, prefixo, n_prefixo, maximo, saida)
        ct_erro_geracao(codigo)
        logico intacta = verdadeiro
        i = 0
        enquanto (i < 64)
        {
            se (saida[i] != 99)
            {
                intacta = falso
            }
            i = i + 1
        }
        se (intacta)
        {
            escreva("SAIDA_INTACTA=OK\n")
        }
        senao
        {
            escreva("SAIDA_INTACTA=FALHA\n")
        }
    }

    funcao inteiro ct_margem(inteiro w16[], inteiro b16[], inteiro entradas[],
                             inteiro alvos[], inteiro n)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, n, c16)
        inteiro z_alvo = ctx_z256(w16, b16, c16, alvos[n])
        inteiro segundo = 0 - 1000000
        inteiro y = 0
        enquanto (y < 25)
        {
            se (y != alvos[n])
            {
                inteiro z = ctx_z256(w16, b16, c16, y)
                se (z > segundo)
                {
                    segundo = z
                }
            }
            y = y + 1
        }
        retorne z_alvo - segundo
    }

    funcao inteiro ct_chave(inteiro entradas[], inteiro i)
    {
        inteiro a = entradas[i * 3]
        inteiro b = entradas[i * 3 + 1]
        inteiro c = entradas[i * 3 + 2]
        inteiro aux = 0
        se (a > b)
        {
            aux = a
            a = b
            b = aux
        }
        se (b > c)
        {
            aux = b
            b = c
            c = aux
        }
        se (a > b)
        {
            aux = a
            a = b
            b = aux
        }
        retorne a * 625 + b * 25 + c
    }

    funcao inteiro ct_max_ultimo(inteiro entradas[], inteiro alvos[], inteiro n)
    {
        inteiro total = 0
        inteiro t = 0
        enquanto (t < 25)
        {
            inteiro melhor = 0
            inteiro i = 0
            enquanto (i < n)
            {
                se (entradas[i * 3 + 2] == t)
                {
                    inteiro cont = 0
                    inteiro j = 0
                    enquanto (j < n)
                    {
                        se (entradas[j * 3 + 2] == t e alvos[j] == alvos[i])
                        {
                            cont = cont + 1
                        }
                        j = j + 1
                    }
                    se (cont > melhor)
                    {
                        melhor = cont
                    }
                }
                i = i + 1
            }
            total = total + melhor
            t = t + 1
        }
        retorne total
    }

    funcao inteiro ct_max_bag(inteiro entradas[], inteiro alvos[], inteiro n)
    {
        inteiro total = 0
        inteiro i = 0
        enquanto (i < n)
        {
            logico primeiro = verdadeiro
            inteiro j = 0
            enquanto (j < i)
            {
                se (ct_chave(entradas, j) == ct_chave(entradas, i))
                {
                    primeiro = falso
                }
                j = j + 1
            }
            se (primeiro)
            {
                inteiro melhor = 0
                j = 0
                enquanto (j < n)
                {
                    se (ct_chave(entradas, j) == ct_chave(entradas, i))
                    {
                        inteiro cont = 0
                        inteiro k = 0
                        enquanto (k < n)
                        {
                            se (ct_chave(entradas, k) == ct_chave(entradas, i) e alvos[k] == alvos[j])
                            {
                                cont = cont + 1
                            }
                            k = k + 1
                        }
                        se (cont > melhor)
                        {
                            melhor = cont
                        }
                    }
                    j = j + 1
                }
                total = total + melhor
            }
            i = i + 1
        }
        retorne total
    }
'@

# --- Setup dos drivers -----------------------------------------------------

$setupInit = @'
inteiro w16[300]
inteiro b16[25]
inteiro entradas[18]
inteiro alvos[6]
ct_load_exemplos(entradas, alvos)
ctx_inicializar(w16, b16)
'@

$setupTrained = @'
inteiro w16[300]
inteiro b16[25]
inteiro entradas[18]
inteiro alvos[6]
ct_load_exemplos(entradas, alvos)
ctx_inicializar(w16, b16)
inteiro historico[33]
inteiro codigo = ctx_executar(w16, b16, entradas, alvos, 6, 7, historico)
'@

# --- Drivers ---------------------------------------------------------------

$driverInit = @'
ctx_imprimir_config()
inteiro w16[300]
inteiro b16[25]
inteiro entradas[18]
inteiro alvos[6]
ct_load_exemplos(entradas, alvos)
ctx_inicializar(w16, b16)
ctx_imprimir_estado(w16, b16)
ctx_imprimir_avaliacao(w16, b16, entradas, alvos, 6)
'@

$driverContextoK = @'
inteiro h[64]
h[0] = 13
ctx_imprimir_contexto(h, 1)
h[0] = 9
h[1] = 13
ctx_imprimir_contexto(h, 2)
h[0] = 9
h[1] = 12
h[2] = 13
ctx_imprimir_contexto(h, 3)
h[0] = 12
h[1] = 9
h[2] = 12
h[3] = 13
ctx_imprimir_contexto(h, 4)
h[0] = 1
h[1] = 2
h[2] = 3
h[3] = 4
h[4] = 5
ctx_imprimir_contexto(h, 5)

logico pad_ok = verdadeiro
inteiro c16[12]
inteiro t = 0
enquanto (t < 25)
{
    h[0] = t
    ctx_montar_contexto(h, 1, c16)
    inteiro zeros = 0
    inteiro nao_zero = 0
    inteiro p = 0
    enquanto (p < 12)
    {
        se (p < 8)
        {
            se (c16[p] == 0)
            {
                zeros = zeros + 1
            }
        }
        senao
        {
            se (c16[p] != 0)
            {
                nao_zero = nao_zero + 1
            }
        }
        p = p + 1
    }
    se (zeros != 8 ou nao_zero == 0)
    {
        pad_ok = falso
    }
    t = t + 1
}
se (pad_ok)
{
    escreva("PAD_DISTINTO=OK\n")
}
senao
{
    escreva("PAD_DISTINTO=FALHA\n")
}
'@

$driverContextoOrdem = @'
inteiro h[64]
inteiro c16[12]
inteiro vetores[48]
inteiro perm[12]
perm[0] = 9
perm[1] = 12
perm[2] = 13
perm[3] = 12
perm[4] = 9
perm[5] = 13
perm[6] = 9
perm[7] = 13
perm[8] = 12
perm[9] = 13
perm[10] = 12
perm[11] = 9

inteiro b = 0
enquanto (b < 4)
{
    h[0] = perm[b * 3]
    h[1] = perm[b * 3 + 1]
    h[2] = perm[b * 3 + 2]
    ctx_montar_contexto(h, 3, c16)
    ctx_imprimir_contexto(h, 3)
    inteiro p = 0
    enquanto (p < 12)
    {
        vetores[b * 12 + p] = c16[p]
        p = p + 1
    }
    b = b + 1
}

inteiro distintos = 0
b = 0
enquanto (b < 4)
{
    logico novo = verdadeiro
    inteiro a = 0
    enquanto (a < b)
    {
        logico igual = verdadeiro
        inteiro p = 0
        enquanto (p < 12)
        {
            se (vetores[a * 12 + p] != vetores[b * 12 + p])
            {
                igual = falso
            }
            p = p + 1
        }
        se (igual)
        {
            novo = falso
        }
        a = a + 1
    }
    se (novo)
    {
        distintos = distintos + 1
    }
    b = b + 1
}
escreva("ORDEM_DISTINTOS=", distintos, "\n")

inteiro w16[300]
inteiro b16[25]
inteiro entradas[18]
inteiro alvos[6]
ct_load_exemplos(entradas, alvos)
ctx_inicializar(w16, b16)
inteiro historico[33]
ctx_executar(w16, b16, entradas, alvos, 6, 7, historico)

escreva("MESMO_ULTIMO=")
inteiro idx[3]
idx[0] = 0
idx[1] = 2
idx[2] = 5
inteiro i = 0
enquanto (i < 3)
{
    se (i > 0)
    {
        escreva(" ")
    }
    ctx_contexto_de_exemplo(entradas, idx[i], c16)
    escreva(ctx_argmax(w16, b16, c16))
    i = i + 1
}
escreva("\n")
'@

$driverTreino = $setupTrained + @'

ctx_imprimir_estado(w16, b16)
ctx_imprimir_historico(historico, 7)
ctx_imprimir_avaliacao(w16, b16, entradas, alvos, 6)
ctx_imprimir_alterados(w16, b16)
escreva("MARGENS=")
inteiro i = 0
enquanto (i < 6)
{
    se (i > 0)
    {
        escreva(" ")
    }
    escreva(ct_margem(w16, b16, entradas, alvos, i))
    i = i + 1
}
escreva("\n")
'@

$driverPontoFixo = $setupTrained + @'

inteiro sw[300]
inteiro sb[25]
inteiro i = 0
enquanto (i < 300)
{
    sw[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    sb[i] = b16[i]
    i = i + 1
}

escreva("S7=", ctx_perda_escalada(w16, b16, entradas, alvos, 6), "\n")
ctx_executar(w16, b16, entradas, alvos, 6, 1, historico)
escreva("S8=", ctx_perda_escalada(w16, b16, entradas, alvos, 6), "\n")

inteiro mudou_w = 0
inteiro mudou_b = 0
i = 0
enquanto (i < 300)
{
    se (w16[i] != sw[i])
    {
        mudou_w = mudou_w + 1
    }
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    se (b16[i] != sb[i])
    {
        mudou_b = mudou_b + 1
    }
    i = i + 1
}
escreva("MUDOU_W=", mudou_w, "\n")
escreva("MUDOU_B=", mudou_b, "\n")
'@

$driverAblacao = $setupTrained + @'

escreva("ABL_FULL=", ctx_acertos(w16, b16, entradas, alvos, 6), "\n")
escreva("ABL_FULL_S=", ctx_perda_escalada(w16, b16, entradas, alvos, 6), "\n")

inteiro wa[300]
inteiro i = 0
enquanto (i < 300)
{
    wa[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 300)
{
    se (i % 12 < 8)
    {
        wa[i] = 0
    }
    i = i + 1
}
escreva("ABL_ULTIMO=", ctx_acertos(wa, b16, entradas, alvos, 6), "\n")
escreva("ABL_ULTIMO_S=", ctx_perda_escalada(wa, b16, entradas, alvos, 6), "\n")

i = 0
enquanto (i < 300)
{
    wa[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 300)
{
    se (i % 12 >= 8)
    {
        wa[i] = 0
    }
    i = i + 1
}
escreva("ABL_ANTIGOS=", ctx_acertos(wa, b16, entradas, alvos, 6), "\n")
escreva("ABL_ANTIGOS_S=", ctx_perda_escalada(wa, b16, entradas, alvos, 6), "\n")
escreva("ABL_ULTIMO_MAX=", ct_max_ultimo(entradas, alvos, 6), "\n")
escreva("ABL_BAG_MAX=", ct_max_bag(entradas, alvos, 6), "\n")
'@

$driverGeracaoCadeia = $setupTrained + @'

inteiro prefixo[3]
prefixo[0] = 9
prefixo[1] = 12
prefixo[2] = 13
inteiro saida[64]
inteiro n = ctx_gerar(w16, b16, prefixo, 3, 64, saida)
inteiro parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 3, parada)
'@

$driverGeracaoLimites = $setupTrained + @'

inteiro prefixo[3]
inteiro saida[64]
inteiro n = 0
inteiro parada = 0

prefixo[0] = 9
prefixo[1] = 12
prefixo[2] = 13
n = ctx_gerar(w16, b16, prefixo, 3, 4, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 3, parada)

n = ctx_gerar(w16, b16, prefixo, 3, 3, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 3, parada)

prefixo[0] = 24
n = ctx_gerar(w16, b16, prefixo, 1, 64, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 1, parada)

prefixo[0] = 12
prefixo[1] = 24
n = ctx_gerar(w16, b16, prefixo, 2, 64, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 2, parada)
'@

$driverGeracaoSemente = $setupTrained + @'

inteiro prefixo[3]
inteiro saida[64]
inteiro n = 0
inteiro parada = 0

prefixo[0] = 9
n = ctx_gerar(w16, b16, prefixo, 1, 10, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 1, parada)

prefixo[0] = 12
n = ctx_gerar(w16, b16, prefixo, 1, 10, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 1, parada)
'@

$driverErrosTreino = $setupInit + @'

ct_exec_invalido(w16, b16, entradas, alvos, 0, 7)
ct_exec_invalido(w16, b16, entradas, alvos, 7, 7)
ct_exec_invalido(w16, b16, entradas, alvos, 6, 0)
ct_exec_invalido(w16, b16, entradas, alvos, 6, 33)

entradas[0] = 25
ct_exec_invalido(w16, b16, entradas, alvos, 6, 7)
entradas[0] = 9
alvos[0] = 0 - 1
ct_exec_invalido(w16, b16, entradas, alvos, 6, 7)
alvos[0] = 14

w16[0] = 17
ct_exec_invalido(w16, b16, entradas, alvos, 6, 7)
w16[0] = 2
b16[0] = 0 - 17
ct_exec_invalido(w16, b16, entradas, alvos, 6, 7)
b16[0] = 0 - 4

ct_exec_invalido(w16, b16, entradas, alvos, 0, 0)
entradas[0] = 25
ct_exec_invalido(w16, b16, entradas, alvos, 6, 0)
w16[0] = 17
ct_exec_invalido(w16, b16, entradas, alvos, 6, 7)
entradas[0] = 9
w16[0] = 2

ctx_imprimir_validacao(entradas, alvos, 6, 7, w16, b16)

ctx_inicializar(w16, b16)
inteiro i = 0
enquanto (i < 300)
{
    w16[i] = 0 - 16
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    b16[i] = 0
    i = i + 1
}
entradas[0] = 9
entradas[1] = 9
entradas[2] = 9
alvos[0] = 0
inteiro historico[33]
inteiro codigo = ctx_executar(w16, b16, entradas, alvos, 1, 1, historico)
ct_erro_treino(codigo)
escreva("PARCIAL_W0=", w16[0], "\n")
escreva("PARCIAL_W1=", w16[1], "\n")
escreva("PARCIAL_W299=", w16[299], "\n")
escreva("PARCIAL_B0=", b16[0], "\n")
escreva("PARCIAL_B24=", b16[24], "\n")
'@

$driverErrosGeracao = $setupInit + @'

inteiro saida[64]
inteiro prefixo[3]
prefixo[0] = 9
prefixo[1] = 12
prefixo[2] = 13

ct_ger_invalido(w16, b16, prefixo, 0, 64)
ct_ger_invalido(w16, b16, prefixo, 4, 64)
prefixo[0] = 25
ct_ger_invalido(w16, b16, prefixo, 1, 64)
prefixo[0] = 24
prefixo[1] = 9
ct_ger_invalido(w16, b16, prefixo, 2, 64)
prefixo[0] = 9
ct_ger_invalido(w16, b16, prefixo, 1, 0)
ct_ger_invalido(w16, b16, prefixo, 1, 65)
prefixo[0] = 9
prefixo[1] = 12
prefixo[2] = 13
ct_ger_invalido(w16, b16, prefixo, 3, 2)
prefixo[0] = 9
w16[0] = 17
ct_ger_invalido(w16, b16, prefixo, 1, 64)
w16[0] = 0
ct_ger_invalido(w16, b16, prefixo, 0, 0)
ct_ger_invalido(w16, b16, prefixo, 1, 0)

inteiro sw[300]
inteiro sb[25]
inteiro i = 0
enquanto (i < 300)
{
    sw[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    sb[i] = b16[i]
    i = i + 1
}
ctx_inicializar(w16, b16)
se (ct_iguais(w16, sw, 300) e ct_iguais(b16, sb, 25))
{
    escreva("PARAMS_INTACTOS=OK\n")
}
senao
{
    escreva("PARAMS_INTACTOS=FALHA\n")
}

i = 0
enquanto (i < 64)
{
    saida[i] = 99
    i = i + 1
}
prefixo[0] = 9
inteiro codigo = ctx_gerar(w16, b16, prefixo, 0, 64, saida)
logico saida_intacta = verdadeiro
i = 0
enquanto (i < 64)
{
    se (saida[i] != 99)
    {
        saida_intacta = falso
    }
    i = i + 1
}
se (saida_intacta)
{
    escreva("SAIDA_INTACTA=OK\n")
}
senao
{
    escreva("SAIDA_INTACTA=FALHA\n")
}
'@

$driverDeterminismo = $setupTrained + @'

ctx_imprimir_estado(w16, b16)
ctx_imprimir_historico(historico, 7)
inteiro prefixo[3]
prefixo[0] = 9
prefixo[1] = 12
prefixo[2] = 13
inteiro saida[64]
inteiro n = ctx_gerar(w16, b16, prefixo, 3, 64, saida)
inteiro parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 3, parada)
prefixo[0] = 9
n = ctx_gerar(w16, b16, prefixo, 1, 10, saida)
parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 1, parada)
'@

$driverComposicao = @'
tokenizar("se faca para ate pare")
real emb[100]
real pesos[100]
real vieses[25]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)

inteiro w16[300]
inteiro b16[25]
ctx_inicializar(w16, b16)
inteiro c16[12]
inteiro h[64]

inteiro e16_ok = 0
inteiro id = 0
enquanto (id < 25)
{
    inteiro d = 0
    enquanto (d < 4)
    {
        se (ctx_e16(id, d) == treino_emb16(id, d) e ctx_e16(id, d) / 16.0 == emb_obter(emb, id, d))
        {
            e16_ok = e16_ok + 1
        }
        d = d + 1
    }
    id = id + 1
}
escreva("E16_OK=", e16_ok, "\n")

inteiro w16m5[100]
inteiro b16m5[25]
treino_inicializar(w16m5, b16m5)

inteiro ent_m5[16]
inteiro alv_m5[16]
ent_m5[0] = 9
ent_m5[1] = 12
ent_m5[2] = 13
ent_m5[3] = 14
alv_m5[0] = 12
alv_m5[1] = 13
alv_m5[2] = 14
alv_m5[3] = 24
inteiro w16t[100]
inteiro b16t[25]
treino_inicializar(w16t, b16t)
inteiro hist_m5[6]
treino_executar(w16t, b16t, ent_m5, alv_m5, 4, 5, hist_m5)

inteiro m4_ok = 0
inteiro m5_ok = 0
inteiro m6_ok = 0
inteiro t = 0
enquanto (t < 25)
{
    h[0] = t
    ctx_montar_contexto(h, 1, c16)
    inteiro previsto = ctx_argmax(w16, b16, c16)
    se (previsto == rede_argmax(pesos, vieses, emb, t))
    {
        m4_ok = m4_ok + 1
    }
    se (previsto == treino_argmax(w16m5, b16m5, t))
    {
        m5_ok = m5_ok + 1
    }
    inteiro saida6[64]
    inteiro saida7[64]
    inteiro n6 = gerador_gerar(w16m5, b16m5, t, 16, saida6)
    inteiro n7 = ctx_gerar(w16, b16, h, 1, 16, saida7)
    logico igual = verdadeiro
    se (n6 != n7)
    {
        igual = falso
    }
    senao
    {
        inteiro i = 0
        enquanto (i < n6)
        {
            se (saida6[i] != saida7[i])
            {
                igual = falso
            }
            i = i + 1
        }
    }
    se (igual)
    {
        m6_ok = m6_ok + 1
    }
    t = t + 1
}
escreva("M4_OK=", m4_ok, "\n")
escreva("M5_OK=", m5_ok, "\n")
escreva("M6_OK=", m6_ok, "\n")

inteiro saida[64]
h[0] = 9
inteiro n = gerador_gerar(w16t, b16t, 9, 16, saida)
escreva("M6_CADEIA=")
inteiro i = 0
enquanto (i < n)
{
    se (i > 0)
    {
        escreva(" ")
    }
    escreva(saida[i])
    i = i + 1
}
escreva("\n")
escreva("COMPOE=OK\n")
'@

$driverLimites = @'
inteiro w16[300]
inteiro b16[25]
inteiro entradas[18]
inteiro alvos[6]
ct_load_exemplos(entradas, alvos)
ctx_inicializar(w16, b16)
inteiro historico[33]
ctx_executar(w16, b16, entradas, alvos, 6, 32, historico)
ctx_imprimir_historico(historico, 32)
escreva("ACERTOS=", ctx_acertos(w16, b16, entradas, alvos, 6), "\n")
inteiro prefixo[3]
prefixo[0] = 9
inteiro saida[64]
inteiro n = ctx_gerar(w16, b16, prefixo, 1, 64, saida)
inteiro parada = 0
se (saida[n - 1] == 24)
{
    parada = 1
}
ctx_imprimir_geracao(saida, n, 1, parada)
'@

$driverParamsIntactos = $setupTrained + @'

inteiro sw[300]
inteiro sb[25]
inteiro i = 0
enquanto (i < 300)
{
    sw[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    sb[i] = b16[i]
    i = i + 1
}

ctx_perda_escalada(w16, b16, entradas, alvos, 6)
ctx_acertos(w16, b16, entradas, alvos, 6)
inteiro h[64]
h[0] = 9
h[1] = 12
h[2] = 13
inteiro c16[12]
ctx_montar_contexto(h, 3, c16)
ctx_argmax(w16, b16, c16)

inteiro prefixo[3]
prefixo[0] = 9
prefixo[1] = 12
prefixo[2] = 13
inteiro saida[64]
ctx_gerar(w16, b16, prefixo, 3, 64, saida)
codigo = ctx_gerar(w16, b16, prefixo, 0, 64, saida)

logico params_ok = ct_iguais(w16, sw, 300) e ct_iguais(b16, sb, 25)
se (params_ok)
{
    escreva("PARAMS_INTACTOS=OK\n")
}
senao
{
    escreva("PARAMS_INTACTOS=FALHA\n")
}

i = 0
enquanto (i < 64)
{
    saida[i] = 99
    i = i + 1
}
codigo = ctx_gerar(w16, b16, prefixo, 0, 64, saida)
logico intacta = verdadeiro
i = 0
enquanto (i < 64)
{
    se (saida[i] != 99)
    {
        intacta = falso
    }
    i = i + 1
}
se (intacta)
{
    escreva("SAIDA_INTACTA=OK\n")
}
senao
{
    escreva("SAIDA_INTACTA=FALHA\n")
}
'@

# --- Saidas esperadas ------------------------------------------------------

$configLines = @(
    "INFO=CTX 3 12 325 300",
    "TAXA=1/8",
    "GRADE=1/16",
    "EPOCAS=7",
    "ESCALA_PERDA=131072",
    "LIMITE_PARAM=16",
    "ORDEM=EXEMPLO"
)

function Get-ParamLines {
    param([hashtable]$W, [hashtable]$B)
    $lines = @()
    for ($y = 0; $y -lt 25; $y++) { $lines += Get-CtxParam16Line $W $B $y }
    return $lines
}

$initLoss = Get-CtxLoss $initW $initB $ENT $ALV 6
if ($initLoss -ne 6728768) { throw "S0 divergente: $initLoss" }

$expectedInit = @()
$expectedInit += $configLines
$expectedInit += Get-ParamLines $initW $initB
$expectedInit += "MAXIMO16=12 4"
$expectedInit += "PERDA=6728768"
$expectedInit += "ACERTOS=0"
$expectedInit += "PRED=" + ($initPred -join " ")

$expectedContextoK = @()
$expectedContextoK += Get-CtxContextLine ([int[]]@(13))
$expectedContextoK += Get-CtxContextLine ([int[]]@(9, 13))
$expectedContextoK += Get-CtxContextLine ([int[]]@(9, 12, 13))
$expectedContextoK += Get-CtxContextLine ([int[]]@(12, 9, 12, 13))
$expectedContextoK += Get-CtxContextLine ([int[]]@(1, 2, 3, 4, 5))
$expectedContextoK += "PAD_DISTINTO=OK"
$frozenContextoK = @(
    "CTX16=1 0 0 0 0 0 0 0 0 11 14 -15 -12",
    "CTX16=2 0 0 0 0 15 -14 -11 -8 11 14 -15 -12",
    "CTX16=3 15 -14 -11 -8 4 7 10 13 11 14 -15 -12",
    "CTX16=4 15 -14 -11 -8 4 7 10 13 11 14 -15 -12",
    "CTX16=5 5 8 11 14 12 15 -14 -11 -13 -10 -7 -4",
    "PAD_DISTINTO=OK"
)
if (($expectedContextoK -join "`n") -cne ($frozenContextoK -join "`n")) {
    throw "Oraculo divergiu de ctx_contexto_k"
}

$expectedContextoOrdem = @()
$expectedContextoOrdem += Get-CtxContextLine ([int[]]@(9, 12, 13))
$expectedContextoOrdem += Get-CtxContextLine ([int[]]@(12, 9, 13))
$expectedContextoOrdem += Get-CtxContextLine ([int[]]@(9, 13, 12))
$expectedContextoOrdem += Get-CtxContextLine ([int[]]@(13, 12, 9))
$expectedContextoOrdem += "ORDEM_DISTINTOS=4"
$expectedContextoOrdem += "MESMO_ULTIMO=14 10 9"
$frozenOrdem = @(
    "CTX16=3 15 -14 -11 -8 4 7 10 13 11 14 -15 -12",
    "CTX16=3 4 7 10 13 15 -14 -11 -8 11 14 -15 -12",
    "CTX16=3 15 -14 -11 -8 11 14 -15 -12 4 7 10 13",
    "CTX16=3 11 14 -15 -12 4 7 10 13 15 -14 -11 -8",
    "ORDEM_DISTINTOS=4",
    "MESMO_ULTIMO=14 10 9"
)
if (($expectedContextoOrdem -join "`n") -cne ($frozenOrdem -join "`n")) {
    throw "Oraculo divergiu de ctx_contexto_ordem"
}

$expectedTreino = @()
$expectedTreino += Get-ParamLines $finalW $finalB
$expectedTreino += "MAXIMO16=11 5"
$expectedTreino += "HISTORICO=" + ($traj7 -join " ")
$expectedTreino += "PERDA=153027"
$expectedTreino += "ACERTOS=6"
$expectedTreino += "PRED=" + ($finalPred -join " ")
$expectedTreino += "ALTERADOS_W=249"
$expectedTreino += "ALTERADOS_B=24"
$expectedTreino += "MARGENS=" + ($margins -join " ")

$expectedPontoFixo = @("S7=153027", "S8=153027", "MUDOU_W=0", "MUDOU_B=0")

$expectedAblacao = @(
    "ABL_FULL=6",
    "ABL_FULL_S=153027",
    "ABL_ULTIMO=1",
    "ABL_ULTIMO_S=916888",
    "ABL_ANTIGOS=6",
    "ABL_ANTIGOS_S=717503",
    "ABL_ULTIMO_MAX=4",
    "ABL_BAG_MAX=2"
)

$expectedErrosTreino = @(
    "ERRO=EXEMPLOS_INVALIDOS", "INTACTO=OK",
    "ERRO=EXEMPLOS_INVALIDOS", "INTACTO=OK",
    "ERRO=EPOCAS_INVALIDAS", "INTACTO=OK",
    "ERRO=EPOCAS_INVALIDAS", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "ERRO=PARAMETROS_INVALIDOS", "INTACTO=OK",
    "ERRO=PARAMETROS_INVALIDOS", "INTACTO=OK",
    "ERRO=EXEMPLOS_INVALIDOS", "INTACTO=OK",
    "ERRO=EPOCAS_INVALIDAS", "INTACTO=OK",
    "ERRO=ID_INVALIDO", "INTACTO=OK",
    "VALIDO=OK",
    "ERRO=ESTOURO_NUMERICO",
    "PARCIAL_W0=-20",
    "PARCIAL_W1=-16",
    "PARCIAL_W299=-16",
    "PARCIAL_B0=0",
    "PARCIAL_B24=0"
)

$expectedErrosGeracao = @(
    "ERRO=PREFIXO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=PREFIXO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=PREFIXO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=PREFIXO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=MAXIMO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=MAXIMO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=MAXIMO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=PARAMETROS_INVALIDOS", "SAIDA_INTACTA=OK",
    "ERRO=PREFIXO_INVALIDO", "SAIDA_INTACTA=OK",
    "ERRO=MAXIMO_INVALIDO", "SAIDA_INTACTA=OK",
    "PARAMS_INTACTOS=OK",
    "SAIDA_INTACTA=OK"
)

$expectedDeterminismo = @()
$expectedDeterminismo += Get-ParamLines $finalW $finalB
$expectedDeterminismo += "MAXIMO16=11 5"
$expectedDeterminismo += "HISTORICO=" + ($traj7 -join " ")
$expectedDeterminismo += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9, 12, 13)) 64
$expectedDeterminismo += Get-CtxGeracaoLines $finalW $finalB ([int[]]@(9)) 10

$expectedComposicao = @(
    "IDS=9 12 13 14 24",
    "E16_OK=100",
    "M4_OK=25",
    "M5_OK=25",
    "M6_OK=25",
    "M6_CADEIA=9 12 13 14 24",
    "COMPOE=OK"
)

$expectedLimites = @()
$expectedLimites += "HISTORICO=" + ($train32.History -join " ")
$expectedLimites += "ACERTOS=6"
$expectedLimites += $genLim64

$expectedParamsIntactos = @("PARAMS_INTACTOS=OK", "SAIDA_INTACTA=OK")

# --- Casos -----------------------------------------------------------------

$cases = @(
    @{ Name = "ctx_init"; Driver = $driverInit; Expected = $expectedInit; Compose = "contexto" },
    @{ Name = "ctx_contexto_k"; Driver = $driverContextoK; Expected = $expectedContextoK; Compose = "contexto" },
    @{ Name = "ctx_contexto_ordem"; Driver = $driverContextoOrdem; Expected = $expectedContextoOrdem; Compose = "contexto" },
    @{ Name = "ctx_treino"; Driver = $driverTreino; Expected = $expectedTreino; Compose = "contexto" },
    @{ Name = "ctx_ponto_fixo"; Driver = $driverPontoFixo; Expected = $expectedPontoFixo; Compose = "contexto" },
    @{ Name = "ctx_ablation"; Driver = $driverAblacao; Expected = $expectedAblacao; Compose = "contexto" },
    @{ Name = "ctx_geracao_cadeia"; Driver = $driverGeracaoCadeia; Expected = $genCadeia; Compose = "contexto" },
    @{ Name = "ctx_geracao_limites"; Driver = $driverGeracaoLimites; Expected = $genLimites; Compose = "contexto" },
    @{ Name = "ctx_geracao_semente"; Driver = $driverGeracaoSemente; Expected = $genSemente; Compose = "contexto" },
    @{ Name = "ctx_erros_treino"; Driver = $driverErrosTreino; Expected = $expectedErrosTreino; Compose = "contexto" },
    @{ Name = "ctx_erros_geracao"; Driver = $driverErrosGeracao; Expected = $expectedErrosGeracao; Compose = "contexto" },
    @{ Name = "ctx_determinismo_a"; Driver = $driverDeterminismo; Expected = $expectedDeterminismo; Compose = "contexto" },
    @{ Name = "ctx_determinismo_b"; Driver = $driverDeterminismo; Expected = $expectedDeterminismo; Compose = "contexto" },
    @{ Name = "ctx_composicao"; Driver = $driverComposicao; Expected = $expectedComposicao; Compose = "full" },
    @{ Name = "ctx_limites"; Driver = $driverLimites; Expected = $expectedLimites; Compose = "contexto" },
    @{ Name = "ctx_params_intactos"; Driver = $driverParamsIntactos; Expected = $expectedParamsIntactos; Compose = "contexto" }
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

foreach ($case in $cases) {
    $fragments = switch ($case.Compose) {
        "contexto" { $ctxFragment }
        "full" {
            $tokenizerFragment + "`n`n" + $embeddingFragment + "`n`n" +
            $networkFragment + "`n`n" + $trainingFragment + "`n`n" +
            $generationFragment + "`n`n" + $ctxFragment
        }
        default { throw "Compose desconhecido: $($case.Compose)" }
    }

    $content = "programa`n{`n" +
        $fragments + "`n`n" +
        $ctxHelpers + "`n`n" +
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

Write-Host "Generated $($cases.Count) context cases in $OutputRoot"
