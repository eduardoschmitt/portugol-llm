<#
.SYNOPSIS
    Gera os 14 casos .por e .expected da geracao autoregressiva em
    temp/generation-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/treino.por + src/gerador.por (e, em gen_composicao, tambem
    src/tokenizador.por, src/embeddings.por e src/rede.por) a um driver. Os
    valores esperados sao recalculados aqui por um oraculo inteiro independente
    (W16, b16, e16, Z256, argmax, geracao), sem [double] e sem ler a saida do
    .por. As tabelas canonicas e a tabela treinada da M5 sao conferidas como
    literais. Tudo e gravado em UTF-8 sem BOM, LF.
#>

param(
    [string]$SourcePath = "src/gerador.por",
    [string]$TrainingSourcePath = "src/treino.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$EmbeddingSourcePath = "src/embeddings.por",
    [string]$NetworkSourcePath = "src/rede.por",
    [string]$OutputRoot = "temp/generation-tests"
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

function Get-W16 {
    $w = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = (($y * 7 + $d * 5) % 25) - 12 }
        $w[$y] = $row
    }
    return $w
}

function Get-B16 {
    $b = @{}
    for ($y = 0; $y -lt 25; $y++) { $b[$y] = (($y * 7) % 9) - 4 }
    return $b
}

function Copy-W16 {
    param([hashtable]$W)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) {
        $row = New-Object 'int[]' 4
        for ($d = 0; $d -lt 4; $d++) { $row[$d] = $W[$y][$d] }
        $copy[$y] = $row
    }
    return $copy
}

function Copy-B16 {
    param([hashtable]$B)
    $copy = @{}
    for ($y = 0; $y -lt 25; $y++) { $copy[$y] = $B[$y] }
    return $copy
}

function Get-Emb16 {
    param([int]$Id, [int]$Dimensao)
    return ((($Id * 7) + ($Dimensao * 3)) % 32) - 16
}

function Get-Z256 {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada, [int]$Y)
    [long]$soma = 0
    for ($d = 0; $d -lt 4; $d++) {
        $soma += [long]$W[$Y][$d] * [long](Get-Emb16 $Entrada $d)
    }
    $soma += 16 * [long]$B[$Y]
    return $soma
}

function Get-Delta256 {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada, [int]$Y, [int]$Alvo)
    [long]$z = Get-Z256 $W $B $Entrada $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function Get-Argmax {
    param([hashtable]$W, [hashtable]$B, [int]$Entrada)
    $melhor = 0
    [long]$melhorValor = Get-Z256 $W $B $Entrada 0
    for ($y = 1; $y -lt 25; $y++) {
        [long]$valor = Get-Z256 $W $B $Entrada $y
        if ($valor -gt $melhorValor) {
            $melhorValor = $valor
            $melhor = $y
        }
    }
    return $melhor
}

function Get-LossS {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos, [int]$N)
    [long]$soma = 0
    for ($i = 0; $i -lt $N; $i++) {
        for ($y = 0; $y -lt 25; $y++) {
            [long]$delta = Get-Delta256 $W $B $Entradas[$i] $y $Alvos[$i]
            $soma += $delta * $delta
        }
    }
    return $soma
}

function Get-RoundHalfAway {
    param([long]$Numerador, [long]$Denominador)
    $sinal = if ($Numerador -lt 0) { -1 } else { 1 }
    [long]$absoluto = [Math]::Abs($Numerador)
    [long]$quociente = [long][Math]::Floor(($absoluto + [long]($Denominador / 2)) / $Denominador)
    return $sinal * $quociente
}

function Invoke-Training {
    param([hashtable]$W, [hashtable]$B, [int[]]$Entradas, [int[]]$Alvos,
          [int]$N, [int]$Epocas)
    $history = New-Object 'long[]' ($Epocas + 1)
    $history[0] = Get-LossS $W $B $Entradas $Alvos $N
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($i = 0; $i -lt $N; $i++) {
            $delta = New-Object 'long[]' 25
            for ($y = 0; $y -lt 25; $y++) {
                $delta[$y] = Get-Delta256 $W $B $Entradas[$i] $y $Alvos[$i]
            }
            for ($y = 0; $y -lt 25; $y++) {
                for ($d = 0; $d -lt 4; $d++) {
                    [long]$novo = Get-RoundHalfAway (
                        1024 * [long]$W[$y][$d] - $delta[$y] * [long](Get-Emb16 $Entradas[$i] $d)) 1024
                    $W[$y][$d] = $novo
                    if ([Math]::Abs($novo) -gt 48) {
                        return [pscustomobject]@{ Code = 5; History = $history }
                    }
                }
                [long]$novoB = Get-RoundHalfAway (64 * [long]$B[$y] - $delta[$y]) 64
                $B[$y] = $novoB
                if ([Math]::Abs($novoB) -gt 48) {
                    return [pscustomobject]@{ Code = 5; History = $history }
                }
            }
        }
        $history[$ep] = Get-LossS $W $B $Entradas $Alvos $N
    }
    return [pscustomobject]@{ Code = 0; History = $history }
}

# --- Oraculo da geracao ----------------------------------------------------

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

function Get-Geracao {
    param([hashtable]$W, [hashtable]$B, [int]$Semente, [int]$Maximo)
    $saida = New-Object 'int[]' 64
    $saida[0] = $Semente
    $total = 1
    while ($total -lt $Maximo) {
        if ($saida[$total - 1] -eq 24) { break }
        $saida[$total] = Get-Argmax $W $B $saida[$total - 1]
        $total++
    }
    return [pscustomobject]@{ Saida = $saida; Total = $total }
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

function Get-Param16Line {
    param([hashtable]$W, [hashtable]$B, [int]$Y)
    return "PARAM16=$Y $($W[$Y][0]) $($W[$Y][1]) $($W[$Y][2]) $($W[$Y][3]) $($B[$Y])"
}

# --- Fontes ----------------------------------------------------------------

$repoRoot = (Get-Location).Path
$sourceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
$trainingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TrainingSourcePath))
$tokenizerFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $TokenizerSourcePath))
$embeddingFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $EmbeddingSourcePath))
$networkFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $NetworkSourcePath))
foreach ($path in @($sourceFull, $trainingFull, $tokenizerFull, $embeddingFull, $networkFull)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Fragmento nao encontrado: $path" }
    Assert-Utf8NoBom $path
    Assert-AsciiLf $path
}

$geradorText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sourceFull))
$geradorCode = (($geradorText -split "`n") | ForEach-Object { ($_ -split "//", 2)[0] }) -join "`n"
$geradorCode = [regex]::Replace($geradorCode, '"[^"]*"', '""')
foreach ($forbidden in @(
    "programa", "inicio", "inclua", "Matematica", "aleatorio", "tempo",
    "leia", "softmax", "exp(", "temperatura", "top_", "real"
)) {
    if ($geradorCode.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "src/gerador.por contem identificador proibido: $forbidden"
    }
}
foreach ($required in @(
    "GERADOR_TAM_VOCAB = 25", "GERADOR_DIM = 4", "GERADOR_SAIDAS = 25",
    "GERADOR_PARAMS = 125", "GERADOR_MAX_TOKENS = 64", "GERADOR_TOKEN_UNK = 0",
    "GERADOR_TOKEN_PARADA = 24",
    "funcao logico gerador_token_valido", "funcao logico gerador_limite_valido",
    "funcao inteiro gerador_proximo", "funcao inteiro gerador_gerar",
    "funcao gerador_escrever_palavra", "funcao gerador_imprimir_texto",
    "funcao gerador_imprimir_palavra", "funcao gerador_imprimir_geracao",
    "funcao gerador_imprimir_config", "funcao gerador_imprimir_validadores"
)) {
    if ($geradorText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "src/gerador.por nao contem: $required"
    }
}
$deps = @([regex]::Matches($geradorCode, 'treino_[a-z0-9_]+') |
    ForEach-Object { $_.Value } | Sort-Object -Unique)
if (($deps -join "|") -cne "treino_argmax|treino_params_validos") {
    throw "Dependencias inesperadas da M5: $($deps -join ', ')"
}

$treinoText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($trainingFull))
$treinoFragment = $treinoText.TrimEnd("`r", "`n")
$geradorFragment = $geradorText.TrimEnd("`r", "`n")
$tokenizerFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($tokenizerFull)).TrimEnd("`r", "`n")
$embeddingFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($embeddingFull)).TrimEnd("`r", "`n")
$networkFragment = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($networkFull)).TrimEnd("`r", "`n")

# --- Tabelas canonicas e treinadas ----------------------------------------

$initW = Get-W16
$initB = Get-B16

$ENT = [int[]]@(9, 12, 13, 14)
$ALV = [int[]]@(12, 13, 14, 24)
$finalW = Copy-W16 $initW
$finalB = Copy-B16 $initB
$training = Invoke-Training $finalW $finalB $ENT $ALV 4 5
if ($training.Code -ne 0) { throw "Oraculo de treino retornou codigo $($training.Code)" }

$frozenFinal = @(
    "0 -1 0 -3 2 -1", "1 0 0 -2 3 0", "2 0 0 11 -10 2", "3 1 0 -3 2 -2",
    "4 0 0 -4 3 0", "5 -1 0 10 -11 2", "6 -1 0 -3 2 0", "7 1 0 -3 3 -1",
    "8 0 -1 -2 3 1", "9 0 0 9 -10 1", "10 1 0 -1 2 -1", "11 -1 0 -1 2 1",
    "12 8 -7 -3 3 2", "13 1 2 3 6 6", "14 1 8 -4 -2 2", "15 0 -1 -2 3 0",
    "16 0 1 10 -10 3", "17 0 0 -3 2 -1", "18 -1 -1 -3 4 0", "19 1 -1 -2 3 0",
    "20 -1 0 -4 3 0", "21 0 0 -3 3 -1", "22 0 0 -3 4 0", "23 -1 0 10 -10 3",
    "24 -9 -2 -4 0 4"
)
for ($y = 0; $y -lt 25; $y++) {
    $row = "$y $($finalW[$y][0]) $($finalW[$y][1]) $($finalW[$y][2]) $($finalW[$y][3]) $($finalB[$y])"
    if ($row -cne $frozenFinal[$y]) {
        throw "Tabela treinada divergente em y=$y. Oraculo: [$row]; spec: [$($frozenFinal[$y])]"
    }
}

$canonicalMap = @(0, 11, 19, 19, 24, 11, 1, 19, 2, 10, 11, 19, 19, 6, 11, 11, 19, 23, 10, 11, 19, 19, 6, 0, 11)
$trainedMap = @(24, 24, 13, 13, 14, 24, 24, 13, 16, 12, 24, 13, 13, 14, 24, 24, 13, 16, 12, 24, 13, 13, 14, 24, 24)
for ($t = 0; $t -lt 25; $t++) {
    $cm = Get-Argmax $initW $initB $t
    if ($cm -ne $canonicalMap[$t]) { throw "Mapa canonico divergente em $t`: $cm vs $($canonicalMap[$t])" }
    $tm = Get-Argmax $finalW $finalB $t
    if ($tm -ne $trainedMap[$t]) { throw "Mapa treinado divergente em $t`: $tm vs $($trainedMap[$t])" }
}

# --- Drivers ---------------------------------------------------------------

$setupCanonical = @'
inteiro w16[100]
inteiro b16[25]
treino_inicializar(w16, b16)
'@

$setupTrained = @'
inteiro w16[100]
inteiro b16[25]
treino_inicializar(w16, b16)
inteiro entradas[16]
inteiro alvos[16]
entradas[0] = 9
entradas[1] = 12
entradas[2] = 13
entradas[3] = 14
alvos[0] = 12
alvos[1] = 13
alvos[2] = 14
alvos[3] = 24
inteiro historico[6]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 5, historico)
'@

$infoDriver = @'
gerador_imprimir_config()
gerador_imprimir_validadores(0, 1)
gerador_imprimir_validadores(24, 64)
gerador_imprimir_validadores(-1, 0)
gerador_imprimir_validadores(25, 65)
'@

$canonicoDriver = $setupCanonical + @'

gerador_imprimir_geracao(w16, b16, 9, 8)
'@

$cicloDriver = $setupCanonical + @'

gerador_imprimir_geracao(w16, b16, 19, 8)
inteiro saida[64]
inteiro n = gerador_gerar(w16, b16, 19, 8, saida)
inteiro ciclo = n
inteiro p = 1
enquanto (p < n)
{
    logico ok = verdadeiro
    inteiro i = p
    enquanto (i < n)
    {
        se (saida[i] != saida[i - p])
        {
            ok = falso
        }
        i = i + 1
    }
    se (ok e ciclo == n)
    {
        ciclo = p
    }
    p = p + 1
}
escreva("CICLO=", ciclo, "\n")
gerador_imprimir_geracao(w16, b16, 0, 5)
n = gerador_gerar(w16, b16, 0, 5, saida)
ciclo = n
p = 1
enquanto (p < n)
{
    logico ok = verdadeiro
    inteiro i = p
    enquanto (i < n)
    {
        se (saida[i] != saida[i - p])
        {
            ok = falso
        }
        i = i + 1
    }
    se (ok e ciclo == n)
    {
        ciclo = p
    }
    p = p + 1
}
escreva("CICLO=", ciclo, "\n")
'@

$treinadoCadeiaDriver = $setupTrained + @'

gerador_imprimir_geracao(w16, b16, 9, 16)
'@

$treinadoParadaDriver = $setupTrained + @'

gerador_imprimir_geracao(w16, b16, 14, 16)
'@

$unkDriver = $setupTrained + @'

gerador_imprimir_geracao(w16, b16, 0, 16)
'@

$inicialPareDriver = $setupTrained + @'

gerador_imprimir_geracao(w16, b16, 24, 16)
'@

$limitesDriver = $setupTrained + @'

gerador_imprimir_geracao(w16, b16, 9, 1)
gerador_imprimir_geracao(w16, b16, 9, 4)
gerador_imprimir_geracao(w16, b16, 9, 5)
gerador_imprimir_geracao(w16, b16, 9, 64)
treino_inicializar(w16, b16)
gerador_imprimir_geracao(w16, b16, 9, 64)
'@

$errosDriver = $setupCanonical + @'

inteiro saida[64]
inteiro i = 0
enquanto (i < 64)
{
    saida[i] = 99
    i = i + 1
}
gerador_imprimir_geracao(w16, b16, -1, 8)
gerador_imprimir_geracao(w16, b16, 25, 8)
gerador_imprimir_geracao(w16, b16, 0, 0)
gerador_imprimir_geracao(w16, b16, 0, 65)
gerador_imprimir_geracao(w16, b16, -1, 0)
w16[0] = 49
gerador_imprimir_geracao(w16, b16, 0, 8)
w16[0] = -12
b16[0] = 49
gerador_imprimir_geracao(w16, b16, 0, 8)
b16[0] = -4
gerador_imprimir_geracao(w16, b16, 30, 70)
logico intacto = treino_igual_a_inicial(w16, b16)
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
se (intacto)
{
    escreva("INTACTO=OK\n")
}
senao
{
    escreva("INTACTO=FALHA\n")
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

$textoDriver = @'
inteiro saida[64]
inteiro i = 0
enquanto (i < 25)
{
    saida[i] = i
    i = i + 1
}
gerador_imprimir_texto(saida, 25)
gerador_imprimir_texto(saida, 0)
i = 0
enquanto (i < 6)
{
    saida[i] = 0
    i = i + 1
}
gerador_imprimir_texto(saida, 6)
gerador_imprimir_texto(saida, -1)
gerador_imprimir_texto(saida, 65)
saida[2] = 25
gerador_imprimir_texto(saida, 6)
saida[2] = 2
i = 0
enquanto (i < 25)
{
    gerador_imprimir_palavra(i)
    i = i + 1
}
gerador_imprimir_palavra(-1)
gerador_imprimir_palavra(25)
'@

$mapaDriver = $setupTrained + @'

inteiro s = 0
enquanto (s < 25)
{
    inteiro saida[64]
    inteiro n = gerador_gerar(w16, b16, s, 16, saida)
    escreva("MAPA=", s)
    inteiro i = 0
    enquanto (i < n)
    {
        escreva(" ", saida[i])
        i = i + 1
    }
    escreva("\n")
    s = s + 1
}
'@

$determinismoDriver = $setupTrained + @'

treino_imprimir_estado(w16, b16)
inteiro seeds[6]
seeds[0] = 0
seeds[1] = 4
seeds[2] = 9
seeds[3] = 14
seeds[4] = 19
seeds[5] = 24
inteiro k = 0
enquanto (k < 6)
{
    gerador_imprimir_geracao(w16, b16, seeds[k], 16)
    k = k + 1
}
'@

$composicaoDriver = @'
tokenizar("se faca para ate pare")
real emb[100]
real pesos[100]
real vieses[25]
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
inteiro w16[100]
inteiro b16[25]
treino_inicializar(w16, b16)
inteiro entradas[16]
inteiro alvos[16]
entradas[0] = 9
entradas[1] = 12
entradas[2] = 13
entradas[3] = 14
alvos[0] = 12
alvos[1] = 13
alvos[2] = 14
alvos[3] = 24
inteiro historico[6]
inteiro codigo = treino_executar(w16, b16, entradas, alvos, 4, 5, historico)
escreva("ALVOS=12 13 14 24\n")
treino_materializar(w16, b16, pesos, vieses)
logico emb16_ok = verdadeiro
inteiro id = 0
enquanto (id < 25)
{
    inteiro d = 0
    enquanto (d < 4)
    {
        se (treino_emb16(id, d) / 16.0 != emb_obter(emb, id, d))
        {
            emb16_ok = falso
        }
        d = d + 1
    }
    id = id + 1
}
se (emb16_ok)
{
    escreva("EMB16=OK\n")
}
senao
{
    escreva("EMB16=FALHA\n")
}
escreva("ARGMAX_REDE=")
inteiro i = 0
enquanto (i < 4)
{
    se (i > 0)
    {
        escreva(" ")
    }
    escreva(rede_argmax(pesos, vieses, emb, entradas[i]))
    i = i + 1
}
escreva("\n")
escreva("ARGMAX_TREINO=")
i = 0
enquanto (i < 4)
{
    se (i > 0)
    {
        escreva(" ")
    }
    escreva(treino_argmax(w16, b16, entradas[i]))
    i = i + 1
}
escreva("\n")
inteiro w16_ref[100]
inteiro b16_ref[25]
i = 0
enquanto (i < 100)
{
    w16_ref[i] = w16[i]
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    b16_ref[i] = b16[i]
    i = i + 1
}
gerador_imprimir_geracao(w16, b16, 9, 16)
logico params_ok = verdadeiro
i = 0
enquanto (i < 100)
{
    se (w16[i] != w16_ref[i])
    {
        params_ok = falso
    }
    i = i + 1
}
i = 0
enquanto (i < 25)
{
    se (b16[i] != b16_ref[i])
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
logico compoe = verdadeiro
i = 0
enquanto (i < 4)
{
    se (rede_argmax(pesos, vieses, emb, entradas[i]) != alvos[i])
    {
        compoe = falso
    }
    se (treino_argmax(w16, b16, entradas[i]) != alvos[i])
    {
        compoe = falso
    }
    se (rede_argmax(pesos, vieses, emb, entradas[i]) != treino_argmax(w16, b16, entradas[i]))
    {
        compoe = falso
    }
    i = i + 1
}
se (compoe)
{
    escreva("COMPOE=OK\n")
}
senao
{
    escreva("COMPOE=FALHA\n")
}
'@

# --- Saidas esperadas ------------------------------------------------------

$infoExpected = @(
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
    $infoExpected += "VALIDO=TOKEN $token $tokenOk"
    $infoExpected += "VALIDO=LIMITE $limite $limiteOk"
}

$canonicoExpected = Get-GeracaoLines $initW $initB 9 8

$cicloExpected = @()
$cicloExpected += Get-GeracaoLines $initW $initB 19 8
$g19 = Get-Geracao $initW $initB 19 8
$cicloExpected += "CICLO=$(Get-Ciclo $g19.Saida $g19.Total)"
$cicloExpected += Get-GeracaoLines $initW $initB 0 5
$g0 = Get-Geracao $initW $initB 0 5
$cicloExpected += "CICLO=$(Get-Ciclo $g0.Saida $g0.Total)"

$treinadoCadeiaExpected = Get-GeracaoLines $finalW $finalB 9 16
$treinadoParadaExpected = Get-GeracaoLines $finalW $finalB 14 16
$unkExpected = Get-GeracaoLines $finalW $finalB 0 16
$inicialPareExpected = Get-GeracaoLines $finalW $finalB 24 16

$limitesExpected = @()
$limitesExpected += Get-GeracaoLines $finalW $finalB 9 1
$limitesExpected += Get-GeracaoLines $finalW $finalB 9 4
$limitesExpected += Get-GeracaoLines $finalW $finalB 9 5
$limitesExpected += Get-GeracaoLines $finalW $finalB 9 64
$limitesExpected += Get-GeracaoLines $initW $initB 9 64

$errosExpected = @(
    "ERRO=TOKEN_INVALIDO", "ERRO=TOKEN_INVALIDO",
    "ERRO=LIMITE_INVALIDO", "ERRO=LIMITE_INVALIDO",
    "ERRO=TOKEN_INVALIDO",
    "ERRO=PARAMETROS_INVALIDOS", "ERRO=PARAMETROS_INVALIDOS",
    "ERRO=TOKEN_INVALIDO",
    "INTACTO=OK", "SAIDA_INTACTA=OK"
)

$allWords = @()
for ($t = 0; $t -lt 25; $t++) { $allWords += Get-Palavra $t }
$textoExpected = @("TEXTO=" + ($allWords -join " "))
$textoExpected += "TEXTO="
$textoExpected += "TEXTO=" + ((@(0, 0, 0, 0, 0, 0) | ForEach-Object { Get-Palavra $_ }) -join " ")
$textoExpected += "ERRO=SEQUENCIA_INVALIDA"
$textoExpected += "ERRO=SEQUENCIA_INVALIDA"
$textoExpected += "ERRO=SEQUENCIA_INVALIDA"
for ($t = 0; $t -lt 25; $t++) { $textoExpected += "PALAVRA=$t $(Get-Palavra $t)" }
$textoExpected += "ERRO=ID_INVALIDO"
$textoExpected += "ERRO=ID_INVALIDO"

$mapaExpected = Get-MapaLines $finalW $finalB 16

$determinismoExpected = @()
for ($y = 0; $y -lt 25; $y++) { $determinismoExpected += Get-Param16Line $finalW $finalB $y }
$determinismoExpected += "MAXIMO16=11 6"
foreach ($s in @(0, 4, 9, 14, 19, 24)) {
    $determinismoExpected += Get-GeracaoLines $finalW $finalB $s 16
}

$composicaoExpected = @(
    "IDS=9 12 13 14 24",
    "ALVOS=12 13 14 24",
    "EMB16=OK",
    "ARGMAX_REDE=12 13 14 24",
    "ARGMAX_TREINO=12 13 14 24"
) + (Get-GeracaoLines $finalW $finalB 9 16) + @(
    "PARAMS_INTACTOS=OK",
    "COMPOE=OK"
)

# --- Conferencias explicitas do oraculo ------------------------------------

$frozenCanonico = @(
    "GERADO=9 10 11 19 11 19 11 19",
    "N=8",
    "PASSOS=7",
    "PARADA=MAXIMO",
    "TEXTO=se senao enquanto e enquanto e enquanto e"
)
if (($canonicoExpected -join "`n") -cne ($frozenCanonico -join "`n")) {
    throw "Oraculo divergiu do bloco congelado de gen_canonico"
}
$frozenCadeia = @(
    "GERADO=9 12 13 14 24",
    "N=5",
    "PASSOS=4",
    "PARADA=PARE",
    "TEXTO=se faca para ate pare"
)
if (($treinadoCadeiaExpected -join "`n") -cne ($frozenCadeia -join "`n")) {
    throw "Oraculo divergiu do bloco congelado de gen_treinado_cadeia"
}
$frozenMapa = @(
    "MAPA=0 0 24", "MAPA=1 1 24", "MAPA=2 2 13 14 24", "MAPA=3 3 13 14 24",
    "MAPA=4 4 14 24", "MAPA=5 5 24", "MAPA=6 6 24", "MAPA=7 7 13 14 24",
    "MAPA=8 8 16 13 14 24", "MAPA=9 9 12 13 14 24", "MAPA=10 10 24",
    "MAPA=11 11 13 14 24", "MAPA=12 12 13 14 24", "MAPA=13 13 14 24",
    "MAPA=14 14 24", "MAPA=15 15 24", "MAPA=16 16 13 14 24",
    "MAPA=17 17 16 13 14 24", "MAPA=18 18 12 13 14 24", "MAPA=19 19 24",
    "MAPA=20 20 13 14 24", "MAPA=21 21 13 14 24", "MAPA=22 22 14 24",
    "MAPA=23 23 24", "MAPA=24 24"
)
if (($mapaExpected -join "`n") -cne ($frozenMapa -join "`n")) {
    throw "Oraculo divergiu do bloco congelado de gen_mapa_treinado"
}

# --- Casos -----------------------------------------------------------------

$cases = @(
    @{ Name = "gen_info"; Driver = $infoDriver; Expected = $infoExpected; Compose = "gerador" },
    @{ Name = "gen_canonico"; Driver = $canonicoDriver; Expected = $canonicoExpected; Compose = "gerador" },
    @{ Name = "gen_ciclo"; Driver = $cicloDriver; Expected = $cicloExpected; Compose = "gerador" },
    @{ Name = "gen_treinado_cadeia"; Driver = $treinadoCadeiaDriver; Expected = $treinadoCadeiaExpected; Compose = "gerador" },
    @{ Name = "gen_treinado_parada"; Driver = $treinadoParadaDriver; Expected = $treinadoParadaExpected; Compose = "gerador" },
    @{ Name = "gen_unk"; Driver = $unkDriver; Expected = $unkExpected; Compose = "gerador" },
    @{ Name = "gen_inicial_pare"; Driver = $inicialPareDriver; Expected = $inicialPareExpected; Compose = "gerador" },
    @{ Name = "gen_limites"; Driver = $limitesDriver; Expected = $limitesExpected; Compose = "gerador" },
    @{ Name = "gen_erros"; Driver = $errosDriver; Expected = $errosExpected; Compose = "gerador" },
    @{ Name = "gen_texto"; Driver = $textoDriver; Expected = $textoExpected; Compose = "gerador" },
    @{ Name = "gen_mapa_treinado"; Driver = $mapaDriver; Expected = $mapaExpected; Compose = "gerador" },
    @{ Name = "gen_determinismo_a"; Driver = $determinismoDriver; Expected = $determinismoExpected; Compose = "gerador" },
    @{ Name = "gen_determinismo_b"; Driver = $determinismoDriver; Expected = $determinismoExpected; Compose = "gerador" },
    @{ Name = "gen_composicao"; Driver = $composicaoDriver; Expected = $composicaoExpected; Compose = "full" }
)

if ($cases.Count -ne 14) { throw "Quantidade de casos: $($cases.Count); esperado 14" }
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
        "gerador" { $treinoFragment + "`n`n" + $geradorFragment }
        "full" {
            $tokenizerFragment + "`n`n" + $embeddingFragment + "`n`n" +
            $networkFragment + "`n`n" + $treinoFragment + "`n`n" + $geradorFragment
        }
        default { throw "Compose desconhecido: $($case.Compose)" }
    }

    $content = "programa`n{`n" +
        $fragments + "`n`n" +
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
if ($generatedExpected.Count -ne 14 -or $generatedPor.Count -ne 14) {
    throw "Arquivos gerados: $($generatedPor.Count) .por e $($generatedExpected.Count) .expected; esperado 14/14"
}

Write-Host "Generated $($cases.Count) generation cases in $OutputRoot"
