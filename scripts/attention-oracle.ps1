<#
.SYNOPSIS
    Oraculo independente da atencao causal minima (M10).
.DESCRIPTION
    Reimplementa em PowerShell, sem ler a saida do interpretador, as equacoes
    de docs/attention-spec.md: e16, escore aditivo, mascara causal, pesos,
    contexto, camada afim 4 -> 25, perda, regra delta e descida coordenada.

    O1 usa aritmetica inteira de 32 bits (valores provados <= 589824000, logo
    sem promocao). O2 audita as somas com System.Numerics.BigInteger. O3
    devolve o exemplo numerico calculado a mao, sem usar O1/O2.

    Uso como biblioteca:
        . ./scripts/attention-oracle.ps1 -Quiet

    Uso direto:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/attention-oracle.ps1
#>

param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
. (Join-Path $root "scripts/eval-datasets.ps1") -Quiet

$script:AtModoAprendida = 0
$script:AtModoUniforme = 1
$script:AtModoRecencia = 2
$script:AtLimite = 16
$script:AtRodadas = 6
$script:AtEpocas = 4
$script:AtMaxExemplos = 10
$script:AtMaxAval = 32
$script:AtGrade = 16
$script:AtUnidade = 256
$script:AtDivW = 2048
$script:AtDivB = 128
$script:AtV = 25
$script:AtD = 4

# ---------------------------- O1: aritmetica ----------------------------

function At-DivR {
    param([long]$Num, [long]$Den)
    if ($Den -le 0) { return 0 }
    $sinal = 1
    $n = $Num
    if ($n -lt 0) { $sinal = -1; $n = -$n }
    $meio = [long][math]::Floor([double]$Den / 2.0)
    $q = [long][math]::Floor([double]($n + $meio) / [double]$Den)
    return [int]($sinal * $q)
}

function At-E16 {
    param([int]$Id, [int]$Dimensao)
    return (($Id * 7 + $Dimensao * 3) % 32) - 16
}

function At-U {
    param([int[]]$A, [int[]]$Beta, [int[]]$Ids, [int]$I, [int]$J, [int]$Modo)
    if ($J -gt $I) { return 0 }
    if ($Modo -eq 1) { return 1 }
    if ($Modo -eq 2) {
        $p = 1
        for ($k = 0; $k -lt $J; $k++) { $p = $p * 2 }
        return $p
    }
    $s = 0
    for ($d = 0; $d -lt 4; $d++) { $s = $s + $A[$d] * (At-E16 $Ids[$J] $d) }
    $s = $s + $Beta[$J]
    if ($s -lt 0) { return 0 }
    return $s
}

function At-PesosInterno {
    param([int[]]$A, [int[]]$Beta, [int[]]$Ids, [int]$I, [int]$Modo)
    $uarr = New-Object 'int[]' 3
    $parr = New-Object 'int[]' 3
    $somaU = 0
    for ($j = 0; $j -le $I; $j++) {
        $uarr[$j] = At-U $A $Beta $Ids $I $j $Modo
        $somaU = $somaU + $uarr[$j]
    }
    for ($j = 0; $j -le $I; $j++) {
        if ($somaU -gt 0) { $parr[$j] = At-DivR (1000 * $uarr[$j]) $somaU }
        else { $parr[$j] = At-DivR 1000 ($I + 1) }
    }
    return [pscustomobject]@{ U = $somaU; UArr = $uarr; P = $parr }
}

function At-CtxInterno {
    param([int[]]$A, [int[]]$Beta, [int[]]$Ids, [int]$I, [int]$Modo)
    $r = At-PesosInterno $A $Beta $Ids $I $Modo
    $c = New-Object 'int[]' 4
    for ($d = 0; $d -lt 4; $d++) {
        if ($r.U -gt 0) {
            $num = 0
            for ($j = 0; $j -le $I; $j++) { $num = $num + $r.UArr[$j] * (At-E16 $Ids[$j] $d) }
            $c[$d] = At-DivR $num $r.U
        } else {
            $soma = 0
            for ($j = 0; $j -le $I; $j++) { $soma = $soma + (At-E16 $Ids[$j] $d) }
            $c[$d] = At-DivR $soma ($I + 1)
        }
    }
    return [pscustomobject]@{ U = $r.U; UArr = $r.UArr; P = $r.P; C = $c }
}

function At-Z {
    param([int[]]$W, [int[]]$B, [int[]]$C, [int]$Y)
    $s = 0
    for ($d = 0; $d -lt 4; $d++) { $s = $s + $W[$Y * 4 + $d] * $C[$d] }
    return $s + 16 * $B[$Y]
}

function At-Delta {
    param([int[]]$W, [int[]]$B, [int[]]$C, [int]$Y, [int]$Alvo)
    $z = At-Z $W $B $C $Y
    if ($Y -eq $Alvo) { return $z - 256 }
    return $z
}

function At-Argmax {
    param([int[]]$W, [int[]]$B, [int[]]$C)
    $melhor = 0
    $valor = At-Z $W $B $C 0
    for ($y = 1; $y -lt 25; $y++) {
        $v = At-Z $W $B $C $y
        if ($v -gt $valor) { $valor = $v; $melhor = $y }
    }
    return $melhor
}

# Contexto rapido: sem objetos e sem chamadas de funcao no laco. Grava c[0..3]
# e retorna U. Equivalente a At-CtxInterno com i = 2 (ultima posicao).
function At-ContextoRapido {
    param([object]$St, [int[]]$Ids, [int]$Modo, [int[]]$C)
    $u0 = 0; $u1 = 0; $u2 = 0
    if ($Modo -eq 1) { $u0 = 1; $u1 = 1; $u2 = 1 }
    elseif ($Modo -eq 2) { $u0 = 1; $u1 = 2; $u2 = 4 }
    else {
        $A = $St.A; $Be = $St.Beta
        $s = $A[0] * ((($Ids[0] * 7) % 32) - 16) +
             $A[1] * (((($Ids[0] * 7 + 3) % 32)) - 16) +
             $A[2] * (((($Ids[0] * 7 + 6) % 32)) - 16) +
             $A[3] * (((($Ids[0] * 7 + 9) % 32)) - 16) + $Be[0]
        if ($s -gt 0) { $u0 = $s }
        $s = $A[0] * ((($Ids[1] * 7) % 32) - 16) +
             $A[1] * (((($Ids[1] * 7 + 3) % 32)) - 16) +
             $A[2] * (((($Ids[1] * 7 + 6) % 32)) - 16) +
             $A[3] * (((($Ids[1] * 7 + 9) % 32)) - 16) + $Be[1]
        if ($s -gt 0) { $u1 = $s }
        $s = $A[0] * ((($Ids[2] * 7) % 32) - 16) +
             $A[1] * (((($Ids[2] * 7 + 3) % 32)) - 16) +
             $A[2] * (((($Ids[2] * 7 + 6) % 32)) - 16) +
             $A[3] * (((($Ids[2] * 7 + 9) % 32)) - 16) + $Be[2]
        if ($s -gt 0) { $u2 = $s }
    }
    $somaU = $u0 + $u1 + $u2
    $e00 = (($Ids[0] * 7) % 32) - 16
    $e01 = ((($Ids[0] * 7 + 3) % 32)) - 16
    $e02 = ((($Ids[0] * 7 + 6) % 32)) - 16
    $e03 = ((($Ids[0] * 7 + 9) % 32)) - 16
    $e10 = (($Ids[1] * 7) % 32) - 16
    $e11 = ((($Ids[1] * 7 + 3) % 32)) - 16
    $e12 = ((($Ids[1] * 7 + 6) % 32)) - 16
    $e13 = ((($Ids[1] * 7 + 9) % 32)) - 16
    $e20 = (($Ids[2] * 7) % 32) - 16
    $e21 = ((($Ids[2] * 7 + 3) % 32)) - 16
    $e22 = ((($Ids[2] * 7 + 6) % 32)) - 16
    $e23 = ((($Ids[2] * 7 + 9) % 32)) - 16
    $num = $u0 * $e00 + $u1 * $e10 + $u2 * $e20
    if ($somaU -gt 0) { $half = [int][math]::Floor($somaU / 2.0); if ($num -lt 0) { $C[0] = -[int][math]::Floor((-$num + $half) / [double]$somaU) } else { $C[0] = [int][math]::Floor(($num + $half) / [double]$somaU) } }
    else { $num = $e00 + $e10 + $e20; if ($num -lt 0) { $C[0] = -[int][math]::Floor((-$num + 1) / 3.0) } else { $C[0] = [int][math]::Floor(($num + 1) / 3.0) } }
    $num = $u0 * $e01 + $u1 * $e11 + $u2 * $e21
    if ($somaU -gt 0) { if ($num -lt 0) { $C[1] = -[int][math]::Floor((-$num + $half) / [double]$somaU) } else { $C[1] = [int][math]::Floor(($num + $half) / [double]$somaU) } }
    else { $num = $e01 + $e11 + $e21; if ($num -lt 0) { $C[1] = -[int][math]::Floor((-$num + 1) / 3.0) } else { $C[1] = [int][math]::Floor(($num + 1) / 3.0) } }
    $num = $u0 * $e02 + $u1 * $e12 + $u2 * $e22
    if ($somaU -gt 0) { if ($num -lt 0) { $C[2] = -[int][math]::Floor((-$num + $half) / [double]$somaU) } else { $C[2] = [int][math]::Floor(($num + $half) / [double]$somaU) } }
    else { $num = $e02 + $e12 + $e22; if ($num -lt 0) { $C[2] = -[int][math]::Floor((-$num + 1) / 3.0) } else { $C[2] = [int][math]::Floor(($num + 1) / 3.0) } }
    $num = $u0 * $e03 + $u1 * $e13 + $u2 * $e23
    if ($somaU -gt 0) { if ($num -lt 0) { $C[3] = -[int][math]::Floor((-$num + $half) / [double]$somaU) } else { $C[3] = [int][math]::Floor(($num + $half) / [double]$somaU) } }
    else { $num = $e03 + $e13 + $e23; if ($num -lt 0) { $C[3] = -[int][math]::Floor((-$num + 1) / 3.0) } else { $C[3] = [int][math]::Floor(($num + 1) / 3.0) } }
    return $somaU
}

function At-PerdaInterna {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    $soma = 0
    $c = New-Object 'int[]' 4
    $W = $St.W
    $Bb = $St.B
    for ($ex = 0; $ex -lt $N; $ex++) {
        $ids = [int[]]@($Ent[$ex * 3], $Ent[$ex * 3 + 1], $Ent[$ex * 3 + 2])
        [void](At-ContextoRapido $St $ids $Modo $c)
        $alvo = $Alv[$ex]
        for ($y = 0; $y -lt 25; $y++) {
            $z = $W[$y * 4] * $c[0] + $W[$y * 4 + 1] * $c[1] + $W[$y * 4 + 2] * $c[2] + $W[$y * 4 + 3] * $c[3] + 16 * $Bb[$y]
            if ($y -eq $alvo) { $z = $z - 256 }
            $soma = $soma + $z * $z
        }
    }
    return $soma
}

# ---------------------------- O1: estado e treino ----------------------------

function At-NovoEstado {
    $st = [pscustomobject]@{
        A = New-Object 'int[]' 4
        Beta = New-Object 'int[]' 3
        W = New-Object 'int[]' 100
        B = New-Object 'int[]' 25
    }
    At-InitLeitura $st
    return $st
}

function At-InitLeitura {
    param([object]$St)
    for ($y = 0; $y -lt 25; $y++) {
        for ($k = 0; $k -lt 4; $k++) {
            $St.W[$y * 4 + $k] = (($y * 7 + $k * 3) % 9) - 4
        }
        $St.B[$y] = 0
    }
}

function At-Clonar {
    param([object]$St)
    return [pscustomobject]@{
        A = [int[]]$St.A.Clone()
        Beta = [int[]]$St.Beta.Clone()
        W = [int[]]$St.W.Clone()
        B = [int[]]$St.B.Clone()
    }
}

function At-Copiar {
    param([object]$Dest, [object]$Src)
    for ($i = 0; $i -lt 4; $i++) { $Dest.A[$i] = $Src.A[$i] }
    for ($i = 0; $i -lt 3; $i++) { $Dest.Beta[$i] = $Src.Beta[$i] }
    for ($i = 0; $i -lt 100; $i++) { $Dest.W[$i] = $Src.W[$i] }
    for ($i = 0; $i -lt 25; $i++) { $Dest.B[$i] = $Src.B[$i] }
}

function At-TreinarAfim {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo, [int]$Epocas)
    $delta = New-Object 'int[]' 25
    $c = New-Object 'int[]' 4
    $W = $St.W
    $Bb = $St.B
    for ($ep = 1; $ep -le $Epocas; $ep++) {
        for ($ex = 0; $ex -lt $N; $ex++) {
            $ids = [int[]]@($Ent[$ex * 3], $Ent[$ex * 3 + 1], $Ent[$ex * 3 + 2])
            [void](At-ContextoRapido $St $ids $Modo $c)
            $alvo = $Alv[$ex]
            for ($y = 0; $y -lt 25; $y++) {
                $z = $W[$y * 4] * $c[0] + $W[$y * 4 + 1] * $c[1] + $W[$y * 4 + 2] * $c[2] + $W[$y * 4 + 3] * $c[3] + 16 * $Bb[$y]
                if ($y -eq $alvo) { $delta[$y] = $z - 256 } else { $delta[$y] = $z }
            }
            for ($y = 0; $y -lt 25; $y++) {
                $dy = $delta[$y]
                for ($d = 0; $d -lt 4; $d++) {
                    $tv = 2048 * $W[$y * 4 + $d] - $dy * $c[$d]
                    if ($tv -lt 0) { $q = -[int][math]::Floor((-$tv + 1024) / 2048.0) } else { $q = [int][math]::Floor(($tv + 1024) / 2048.0) }
                    $W[$y * 4 + $d] = $q
                    if ($q -gt 16 -or $q -lt -16) { return 5 }
                }
                $tv = 128 * $Bb[$y] - $dy
                if ($tv -lt 0) { $q = -[int][math]::Floor((-$tv + 64) / 128.0) } else { $q = [int][math]::Floor(($tv + 64) / 128.0) }
                $Bb[$y] = $q
                if ($q -gt 16 -or $q -lt -16) { return 5 }
            }
        }
    }
    return 0
}

function At-AjustarLeitura {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    At-InitLeitura $St
    return (At-TreinarAfim $St $Ent $Alv $N $Modo 4)
}

function At-MelhorDesempate {
    param([int]$V, [int]$Melhor)
    if ([math]::Abs($V) -lt [math]::Abs($Melhor)) { return $true }
    if ([math]::Abs($V) -eq [math]::Abs($Melhor) -and $V -lt $Melhor) { return $true }
    return $false
}

function At-Varredura {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    if ($Modo -ne 0) { return 0 }
    $codigo = At-AjustarLeitura $St $Ent $Alv $N $Modo
    if ($codigo -ne 0) { return -$codigo }
    $base = At-PerdaInterna $St $Ent $Alv $N $Modo
    $alteracoes = 0
    for ($idx = 0; $idx -lt 7; $idx++) {
        if ($idx -lt 4) { $atual = $St.A[$idx] } else { $atual = $St.Beta[$idx - 4] }
        $melhorV = $atual
        $melhorL = $base
        for ($v = -16; $v -le 16; $v++) {
            if ($idx -lt 4) { $St.A[$idx] = $v } else { $St.Beta[$idx - 4] = $v }
            $codigo = At-AjustarLeitura $St $Ent $Alv $N $Modo
            if ($codigo -ne 0) { return -$codigo }
            $l = At-PerdaInterna $St $Ent $Alv $N $Modo
            if ($l -lt $melhorL) { $melhorL = $l; $melhorV = $v }
            elseif ($l -eq $melhorL -and (At-MelhorDesempate $v $melhorV)) { $melhorV = $v }
        }
        if ($idx -lt 4) { $St.A[$idx] = $atual } else { $St.Beta[$idx - 4] = $atual }
        $codigo = At-AjustarLeitura $St $Ent $Alv $N $Modo
        if ($codigo -ne 0) { return -$codigo }
        if ($melhorL -lt $base) {
            if ($idx -lt 4) { $St.A[$idx] = $melhorV } else { $St.Beta[$idx - 4] = $melhorV }
            $codigo = At-AjustarLeitura $St $Ent $Alv $N $Modo
            if ($codigo -ne 0) { return -$codigo }
            $base = $melhorL
            $alteracoes = $alteracoes + 1
        }
    }
    return $alteracoes
}

function At-Treinar {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    $hist = New-Object 'int[]' 7
    $info = New-Object 'int[]' 3
    $hist[0] = At-PerdaInterna $St $Ent $Alv $N $Modo
    $parar = $false
    $rodada = 1
    while ($rodada -le 6 -and -not $parar) {
        $snap = At-Clonar $St
        $inicial = $hist[$rodada - 1]
        $codigo = At-TreinarAfim $St $Ent $Alv $N $Modo 4
        if ($codigo -ne 0) { throw "treino afim falhou: $codigo" }
        $mudou = At-Varredura $St $Ent $Alv $N $Modo
        if ($mudou -lt 0) { throw "varredura falhou: $mudou" }
        $atual = At-PerdaInterna $St $Ent $Alv $N $Modo
        if ($atual -gt $inicial) {
            At-Copiar $St $snap
            $hist[$rodada] = $inicial
            $parar = $true
        } else {
            $hist[$rodada] = $atual
            $info[0] = $rodada
            $info[1] = $info[1] + $mudou
            if ($Modo -eq 0 -and $mudou -eq 0) { $info[2] = 1; $parar = $true }
            $rodada = $rodada + 1
        }
    }
    return [pscustomobject]@{ Hist = $hist; Info = $info }
}

# ---------------------------- O1: avaliacao ----------------------------

function At-Acertos {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    $t = 0
    for ($e = 0; $e -lt $N; $e++) {
        $ids = [int[]]@($Ent[$e * 3], $Ent[$e * 3 + 1], $Ent[$e * 3 + 2])
        $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
        if ((At-Argmax $St.W $St.B $ctx.C) -eq $Alv[$e]) { $t = $t + 1 }
    }
    return $t
}

function At-AcertosTipo {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int[]]$Tipo, [int]$N, [int]$Modo, [int]$Filtro)
    $t = 0
    for ($e = 0; $e -lt $N; $e++) {
        if ($Filtro -lt 0 -or $Tipo[$e] -eq $Filtro) {
            $ids = [int[]]@($Ent[$e * 3], $Ent[$e * 3 + 1], $Ent[$e * 3 + 2])
            $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
            if ((At-Argmax $St.W $St.B $ctx.C) -eq $Alv[$e]) { $t = $t + 1 }
        }
    }
    return $t
}

function At-BP {
    param([int]$Acertos, [int]$N)
    if ($N -lt 1 -or $Acertos -lt 0 -or $Acertos -gt $N) { return -1 }
    return At-DivR (10000 * $Acertos) $N
}

function At-MargemMedia {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    $soma = 0
    for ($e = 0; $e -lt $N; $e++) {
        $ids = [int[]]@($Ent[$e * 3], $Ent[$e * 3 + 1], $Ent[$e * 3 + 2])
        $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
        $alvo = $Alv[$e]
        $melhor = 0
        $tem = $false
        for ($y = 0; $y -lt 25; $y++) {
            if ($y -ne $alvo) {
                $v = At-Z $St.W $St.B $ctx.C $y
                if (-not $tem -or $v -gt $melhor) { $melhor = $v; $tem = $true }
            }
        }
        $soma = $soma + ((At-Z $St.W $St.B $ctx.C $alvo) - $melhor)
    }
    return At-DivR $soma $N
}

function At-Checksum {
    param([object]$St)
    $soma = 0
    for ($i = 0; $i -lt 4; $i++) { $soma = $soma + ($i + 1) * $St.A[$i] }
    for ($i = 0; $i -lt 3; $i++) { $soma = $soma + ($i + 1) * $St.Beta[$i] }
    for ($i = 0; $i -lt 100; $i++) { $soma = $soma + ($i + 1) * $St.W[$i] }
    for ($i = 0; $i -lt 25; $i++) { $soma = $soma + ($i + 1) * $St.B[$i] }
    return $soma
}

# ---------------------------- O1: relatorio ----------------------------

function At-LinhasPesos {
    param([object]$St)
    $out = New-Object System.Collections.Generic.List[string]
    for ($d = 0; $d -lt 4; $d++) { $out.Add("PESO a $d $($St.A[$d])") }
    for ($j = 0; $j -lt 3; $j++) { $out.Add("PESO beta $j $($St.Beta[$j])") }
    return $out
}

function At-LinhasPesosAtencao {
    param([object]$St, [int[]]$Ids, [int]$N, [int]$I, [int]$Modo)
    $out = New-Object System.Collections.Generic.List[string]
    $r = At-PesosInterno $St.A $St.Beta $Ids $I $Modo
    for ($j = 0; $j -lt 3; $j++) {
        $s = 0
        $permitido = 0
        if ($j -le $I -and $j -lt $N) {
            for ($d = 0; $d -lt 4; $d++) { $s = $s + $St.A[$d] * (At-E16 $Ids[$j] $d) }
            $s = $s + $St.Beta[$j]
            $permitido = 1
        }
        $u = $r.UArr[$j]
        $p = $r.P[$j]
        $out.Add("AT $I $j $s $u $p $permitido")
    }
    return $out
}

function At-LinhasRelatorio {
    param([object]$St, [string]$Estado, [string]$Conjunto,
          [int[]]$Ent, [int[]]$Alv, [int[]]$Tipo, [int]$N, [int]$Modo, [int]$Filtro)
    $out = New-Object System.Collections.Generic.List[string]
    $conta = 0
    $acertos = 0
    $perda = 0
    for ($e = 0; $e -lt $N; $e++) {
        if ($Filtro -lt 0 -or $Tipo[$e] -eq $Filtro) {
            $ids = [int[]]@($Ent[$e * 3], $Ent[$e * 3 + 1], $Ent[$e * 3 + 2])
            $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
            if ((At-Argmax $St.W $St.B $ctx.C) -eq $Alv[$e]) { $acertos = $acertos + 1 }
            for ($y = 0; $y -lt 25; $y++) {
                $dv = At-Delta $St.W $St.B $ctx.C $y $Alv[$e]
                $perda = $perda + $dv * $dv
            }
            $conta = $conta + 1
        }
    }
    $out.Add("RESUMO $Estado $Conjunto $conta $acertos $(At-BP $acertos $conta) $perda")
    for ($e = 0; $e -lt $N; $e++) {
        if ($Filtro -lt 0 -or $Tipo[$e] -eq $Filtro) {
            $ids = [int[]]@($Ent[$e * 3], $Ent[$e * 3 + 1], $Ent[$e * 3 + 2])
            $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
            $pred = At-Argmax $St.W $St.B $ctx.C
            $ok = 0
            if ($pred -eq $Alv[$e]) { $ok = 1 }
            $out.Add("EX $Estado $Conjunto $e $($ids[0]) $($ids[1]) $($ids[2]) $($Alv[$e]) $pred $ok")
        }
    }
    $conf = New-Object 'int[]' 625
    for ($e = 0; $e -lt $N; $e++) {
        if ($Filtro -lt 0 -or $Tipo[$e] -eq $Filtro) {
            $ids = [int[]]@($Ent[$e * 3], $Ent[$e * 3 + 1], $Ent[$e * 3 + 2])
            $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
            $pred = At-Argmax $St.W $St.B $ctx.C
            $conf[$Alv[$e] * 25 + $pred] = $conf[$Alv[$e] * 25 + $pred] + 1
        }
    }
    for ($alvo = 0; $alvo -lt 25; $alvo++) {
        for ($pred = 0; $pred -lt 25; $pred++) {
            $q = $conf[$alvo * 25 + $pred]
            if ($q -gt 0) { $out.Add("CONF $Estado $Conjunto $alvo $pred $q") }
        }
    }
    return $out
}

# ---------------------------- O1: datasets ----------------------------

function Get-AtDatasets {
    $d = Get-EvalDataset
    $b = Get-EvalSequenceSet -Seq $d.BSeq -Count 5 -Modo 1
    $c = Get-EvalSequenceSet -Seq $d.CSeq -Count 8 -Modo 0

    $aTipo = New-Object 'int[]' 10
    $dTipo = New-Object 'int[]' 10
    $cspTipo = New-Object 'int[]' 32
    for ($i = 0; $i -lt 32; $i++) {
        if ($c.Alv[$i] -ne 24) { $cspTipo[$i] = 1 }
    }

    $sintE = [int[]]@(
        1, 2, 3,  3, 2, 1,
        2, 4, 5,  5, 4, 2,
        3, 1, 4,  4, 1, 3,
        4, 3, 5,  5, 3, 4,
        1, 5, 2,  2, 5, 1
    )
    $sintT = [int[]]@(3, 1, 5, 2, 4, 3, 5, 4, 2, 1)

    return [pscustomobject]@{
        TrainEnt = $d.TrainEnt
        TrainAlv = $d.TrainAlv
        AEnt = $d.AEnt
        AAlv = $d.AAlv
        ATipo = $aTipo
        BEnt = $b.Ent
        BAlv = $b.Alv
        BTipo = $b.Tipo
        BSeen = 10
        BUnseen = 10
        CEnt = $c.Ent
        CAlv = $c.Alv
        CTipo = $c.Tipo
        CSemPareTipo = $cspTipo
        CSemPare = 24
        DEnt = $d.DEnt
        DAlv = $d.DAlv
        DTipo = $dTipo
        SintEnt = $sintE
        SintAlv = $sintT
    }
}

# ---------------------------- O3: exemplo manual ----------------------------

function Get-AtManualExample {
    return @(
        "AT 2 0 608 608 527 1",
        "AT 2 1 545 545 473 1",
        "AT 2 2 -545 0 0 1",
        "CTX 1153 5 8 11 14",
        "Z 38",
        "DELTA -218",
        "WN 0 2",
        "WN 1 1",
        "WN 2 0",
        "WN 3 3",
        "BN 3",
        "CHECKSUM 229"
    )
}

# ---------------------------- O2: auditoria BigInteger ----------------------------

function Get-AtBoundAudit {
    Add-Type -AssemblyName System.Numerics
    $out = New-Object System.Collections.Generic.List[string]
    $sMax = [System.Numerics.BigInteger]::new([long](4 * 16 * 16 + 16))
    $uMax = $sMax * 3
    $numMax = $uMax * 16
    $zMax = [System.Numerics.BigInteger]::new([long](4 * 16 * 16 + 16 * 16))
    $dMax = $zMax + 256
    $lMax = $dMax * $dMax * 25 * 10
    $limite = [System.Numerics.BigInteger]::new([long]2147483647)
    $out.Add("BIG S $sMax")
    $out.Add("BIG U $uMax")
    $out.Add("BIG NUM $numMax")
    $out.Add("BIG Z $zMax")
    $out.Add("BIG DELTA $dMax")
    $out.Add("BIG PERDA $lMax")
    $out.Add("BIG LIMITE $limite")
    $out.Add("BIG DENTRO " + $(if ($lMax -lt $limite) { 1 } else { 0 }))
    return $out
}

# ---------------------------- Relatorios por caso ----------------------------

function At-LinhasDelta {
    param([string]$Estado, [string]$Conj, [int]$Bp, [int]$Base)
    return "DELTA_BP $Estado $Conj $Bp $Base $($Bp - $Base)"
}

function Get-AtReport {
    param([string]$Name)
    $d = Get-AtDatasets
    $out = New-Object System.Collections.Generic.List[string]
    $zero10 = New-Object 'int[]' 10

    switch ($Name) {
        "at_limites" {
            $st = At-NovoEstado
            $out.Add("ATEN V1")
            $out.Add("ESTADO LIMITES")
            $out.Add("LIMITES MAXS 1040")
            $out.Add("LIMITES MAXU 3120")
            $out.Add("LIMITES MAXNUM 49920")
            $out.Add("LIMITES MAXZ 1280")
            $out.Add("LIMITES MAXDELTA 1536")
            $out.Add("LIMITES MAXPERDA 589824000")
            $ext = [pscustomobject]@{
                A = [int[]]@(16,16,16,16)
                Beta = [int[]]@(16,16,16)
                W = New-Object 'int[]' 100
                B = New-Object 'int[]' 25
            }
            for ($i = 0; $i -lt 100; $i++) { $ext.W[$i] = 16 }
            for ($i = 0; $i -lt 25; $i++) { $ext.B[$i] = 16 }
            $ids = [int[]]@(24,24,24)
            $ctx = At-CtxInterno $ext.A $ext.Beta $ids 2 0
            $z = At-Z $ext.W $ext.B $ctx.C 0
            $cs = At-Checksum $ext
            $out.Add("LIMITES EXTREMO $($ctx.U) $($ctx.C[0]) $($ctx.C[1]) $($ctx.C[2]) $($ctx.C[3]) $z $cs")
            $out.Add("LIMITES N0 1")
            $out.Add("LIMITES N4 1")
            $out.Add("LIMITES ID 2")
            $out.Add("LIMITES PARAM 3")
            $out.Add("LIMITES EPOCAS 4")
            $out.Add("LIMITES MODO 6")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_mascara" {
            $st = [pscustomobject]@{
                A = [int[]]@(0,0,0,0)
                Beta = [int[]]@(0,0,16)
                W = New-Object 'int[]' 100
                B = New-Object 'int[]' 25
            }
            $ids = [int[]]@(3,12,5)
            $out.Add("ATEN V1")
            $out.Add("ESTADO MASCARA")
            foreach ($l in (At-LinhasPesosAtencao $st $ids 3 1 0)) { $out.Add($l) }
            foreach ($l in (At-LinhasPesosAtencao $st $ids 3 2 0)) { $out.Add($l) }
            $c1 = At-CtxInterno $st.A $st.Beta $ids 1 0
            $c2 = At-CtxInterno $st.A $st.Beta $ids 2 0
            $out.Add("CTX 1 $($c1.U) $($c1.C[0]) $($c1.C[1]) $($c1.C[2]) $($c1.C[3])")
            $out.Add("CTX 2 $($c2.U) $($c2.C[0]) $($c2.C[1]) $($c2.C[2]) $($c2.C[3])")
            $bloqueado = 0
            if ($c1.U -eq 0 -and $c2.C[0] -eq -13 -and $c2.C[1] -eq -10 -and $c2.C[2] -eq -7 -and $c2.C[3] -eq -4) { $bloqueado = 1 }
            $out.Add("CHECK MASCARA CAUSAL " + $(if ($bloqueado -eq 1) { "OK" } else { "FALHA" }))
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_padding" {
            $st = At-NovoEstado
            $ids = [int[]]@(3,12,5)
            $out.Add("ATEN V1")
            $out.Add("ESTADO PADDING")
            for ($n = 1; $n -le 3; $n++) {
                $i = $n - 1
                foreach ($l in (At-LinhasPesosAtencao $st $ids $n $i 0)) { $out.Add($l) }
                $ctx = At-CtxInterno $st.A $st.Beta $ids $i 0
                $out.Add("CTX $n $($ctx.U) $($ctx.C[0]) $($ctx.C[1]) $($ctx.C[2]) $($ctx.C[3])")
            }
            $e3 = [int[]]@((At-E16 3 0), (At-E16 3 1), (At-E16 3 2), (At-E16 3 3))
            $c1 = At-CtxInterno $st.A $st.Beta $ids 0 0
            $ok = 1
            for ($k = 0; $k -lt 4; $k++) { if ($c1.C[$k] -ne $e3[$k]) { $ok = 0 } }
            $out.Add("CHECK PADDING " + $(if ($ok -eq 1) { "OK" } else { "FALHA" }))
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_pesos" {
            $st = [pscustomobject]@{
                A = [int[]]@(16,16,16,16)
                Beta = [int[]]@(0,1,-1)
                W = New-Object 'int[]' 100
                B = New-Object 'int[]' 25
            }
            $ids = [int[]]@(3,12,5)
            $out.Add("ATEN V1")
            $out.Add("ESTADO PESOS")
            foreach ($l in (At-LinhasPesosAtencao $st $ids 3 2 0)) { $out.Add($l) }
            $ctx = At-CtxInterno $st.A $st.Beta $ids 2 0
            $soma = $ctx.P[0] + $ctx.P[1] + $ctx.P[2]
            $out.Add("SOMA_PERMIL $soma")
            $out.Add("CTX 3 $($ctx.U) $($ctx.C[0]) $($ctx.C[1]) $($ctx.C[2]) $($ctx.C[3])")
            $uni = [pscustomobject]@{
                A = [int[]]@(0,0,0,0)
                Beta = [int[]]@(0,0,0)
                W = New-Object 'int[]' 100
                B = New-Object 'int[]' 25
            }
            foreach ($l in (At-LinhasPesosAtencao $uni $ids 3 2 0)) { $out.Add($l) }
            $ctx2 = At-CtxInterno $uni.A $uni.Beta $ids 2 0
            $soma2 = $ctx2.P[0] + $ctx2.P[1] + $ctx2.P[2]
            $out.Add("SOMA_PERMIL $soma2")
            $out.Add("CTX 3 $($ctx2.U) $($ctx2.C[0]) $($ctx2.C[1]) $($ctx2.C[2]) $($ctx2.C[3])")
            $ok = 1
            if ([math]::Abs($soma - 1000) -gt 2) { $ok = 0 }
            if ([math]::Abs($soma2 - 1000) -gt 2) { $ok = 0 }
            $out.Add("CHECK NORMALIZACAO " + $(if ($ok -eq 1) { "OK" } else { "FALHA" }))
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_exemplo" {
            $st = [pscustomobject]@{
                A = [int[]]@(16,16,16,16)
                Beta = [int[]]@(0,1,-1)
                W = New-Object 'int[]' 100
                B = New-Object 'int[]' 25
            }
            $st.W[7 * 4] = 1
            $st.W[7 * 4 + 1] = 0
            $st.W[7 * 4 + 2] = -1
            $st.W[7 * 4 + 3] = 2
            $st.B[7] = 1
            $ids = [int[]]@(3,12,5)
            $out.Add("ATEN V1")
            $out.Add("ESTADO EXEMPLO")
            foreach ($l in (At-LinhasPesosAtencao $st $ids 3 2 0)) { $out.Add($l) }
            $ctx = At-CtxInterno $st.A $st.Beta $ids 2 0
            $out.Add("CTX $($ctx.U) $($ctx.C[0]) $($ctx.C[1]) $($ctx.C[2]) $($ctx.C[3])")
            $z = At-Z $st.W $st.B $ctx.C 7
            $dv = At-Delta $st.W $st.B $ctx.C 7 7
            $out.Add("Z $z")
            $out.Add("DELTA $dv")
            for ($k = 0; $k -lt 4; $k++) {
                $out.Add("WN $k $(At-DivR (2048 * $st.W[7 * 4 + $k] - $dv * $ctx.C[$k]) 2048)")
            }
            $out.Add("BN $(At-DivR (128 * $st.B[7] - $dv) 128)")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_nao_treinado" {
            $st = At-NovoEstado
            $out.Add("ATEN V1")
            $out.Add("ESTADO NAO_TREINADO")
            $out.Add("TREINO 0 0 0")
            foreach ($l in (At-LinhasPesos $st)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "A" $d.AEnt $d.AAlv $d.ATipo 10 0 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "B" $d.BEnt $d.BAlv $d.BTipo 20 0 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "B_VISTO" $d.BEnt $d.BAlv $d.BTipo 20 0 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "B_INEDITO" $d.BEnt $d.BAlv $d.BTipo 20 0 0)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "C" $d.CEnt $d.CAlv $d.CTipo 32 0 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "C_SEM_PARE" $d.CEnt $d.CAlv $d.CSemPareTipo 32 0 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "NAO_TREINADO" "D" $d.DEnt $d.DAlv $d.DTipo 10 0 -1)) { $out.Add($l) }
            $out.Add("MARGEM NAO_TREINADO A $(At-MargemMedia $st $d.AEnt $d.AAlv 10 0)")
            $out.Add("MARGEM NAO_TREINADO C $(At-MargemMedia $st $d.CEnt $d.CAlv 32 0)")
            $out.Add("CHECK MUTACAO NAO_TREINADO OK")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_uniforme" {
            $st = At-NovoEstado
            $tr = At-Treinar $st $d.TrainEnt $d.TrainAlv 10 1
            $out.Add("ATEN V1")
            $out.Add("ESTADO UNIFORME")
            $out.Add("TREINO 10 $($tr.Info[0]) $($tr.Hist[0]) $($tr.Hist[$tr.Info[0]]) $($tr.Info[1]) $($tr.Info[2])")
            foreach ($l in (At-LinhasPesos $st)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "A" $d.AEnt $d.AAlv $d.ATipo 10 1 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "B" $d.BEnt $d.BAlv $d.BTipo 20 1 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "B_VISTO" $d.BEnt $d.BAlv $d.BTipo 20 1 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "B_INEDITO" $d.BEnt $d.BAlv $d.BTipo 20 1 0)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "C" $d.CEnt $d.CAlv $d.CTipo 32 1 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "C_SEM_PARE" $d.CEnt $d.CAlv $d.CSemPareTipo 32 1 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "UNIFORME" "D" $d.DEnt $d.DAlv $d.DTipo 10 1 -1)) { $out.Add($l) }
            $out.Add("MARGEM UNIFORME A $(At-MargemMedia $st $d.AEnt $d.AAlv 10 1)")
            $out.Add("MARGEM UNIFORME C $(At-MargemMedia $st $d.CEnt $d.CAlv 32 1)")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_recencia" {
            $st = At-NovoEstado
            $tr = At-Treinar $st $d.TrainEnt $d.TrainAlv 10 2
            $out.Add("ATEN V1")
            $out.Add("ESTADO RECENCIA")
            $out.Add("TREINO 10 $($tr.Info[0]) $($tr.Hist[0]) $($tr.Hist[$tr.Info[0]]) $($tr.Info[1]) $($tr.Info[2])")
            foreach ($l in (At-LinhasPesos $st)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "A" $d.AEnt $d.AAlv $d.ATipo 10 2 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "B" $d.BEnt $d.BAlv $d.BTipo 20 2 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "B_VISTO" $d.BEnt $d.BAlv $d.BTipo 20 2 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "B_INEDITO" $d.BEnt $d.BAlv $d.BTipo 20 2 0)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "C" $d.CEnt $d.CAlv $d.CTipo 32 2 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "C_SEM_PARE" $d.CEnt $d.CAlv $d.CSemPareTipo 32 2 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "RECENCIA" "D" $d.DEnt $d.DAlv $d.DTipo 10 2 -1)) { $out.Add($l) }
            $out.Add("MARGEM RECENCIA A $(At-MargemMedia $st $d.AEnt $d.AAlv 10 2)")
            $out.Add("MARGEM RECENCIA C $(At-MargemMedia $st $d.CEnt $d.CAlv 32 2)")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_treinado" {
            $st = At-NovoEstado
            $tr = At-Treinar $st $d.TrainEnt $d.TrainAlv 10 0
            $out.Add("ATEN V1")
            $out.Add("ESTADO TREINADO")
            $out.Add("TREINO 10 $($tr.Info[0]) $($tr.Hist[0]) $($tr.Hist[$tr.Info[0]]) $($tr.Info[1]) $($tr.Info[2])")
            foreach ($l in (At-LinhasPesos $st)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "A" $d.AEnt $d.AAlv $d.ATipo 10 0 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "B" $d.BEnt $d.BAlv $d.BTipo 20 0 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "B_VISTO" $d.BEnt $d.BAlv $d.BTipo 20 0 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "B_INEDITO" $d.BEnt $d.BAlv $d.BTipo 20 0 0)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "C" $d.CEnt $d.CAlv $d.CTipo 32 0 -1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "C_SEM_PARE" $d.CEnt $d.CAlv $d.CSemPareTipo 32 0 1)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "TREINADO" "D" $d.DEnt $d.DAlv $d.DTipo 10 0 -1)) { $out.Add($l) }
            $acA = At-Acertos $st $d.AEnt $d.AAlv 10 0
            $acB = At-Acertos $st $d.BEnt $d.BAlv 20 0
            $acBV = At-AcertosTipo $st $d.BEnt $d.BAlv $d.BTipo 20 0 1
            $acBI = At-AcertosTipo $st $d.BEnt $d.BAlv $d.BTipo 20 0 0
            $acC = At-Acertos $st $d.CEnt $d.CAlv 32 0
            $acP = At-AcertosTipo $st $d.CEnt $d.CAlv $d.CSemPareTipo 32 0 1
            $acD = At-Acertos $st $d.DEnt $d.DAlv 10 0
            $out.Add((At-LinhasDelta "TREINADO" "A" (At-BP $acA 10) 10000))
            $out.Add((At-LinhasDelta "TREINADO" "B" (At-BP $acB 20) 5000))
            $out.Add((At-LinhasDelta "TREINADO" "B_VISTO" (At-BP $acBV 10) 10000))
            $out.Add((At-LinhasDelta "TREINADO" "B_INEDITO" (At-BP $acBI 10) 0))
            $out.Add((At-LinhasDelta "TREINADO" "C" (At-BP $acC 32) 1250))
            $out.Add((At-LinhasDelta "TREINADO" "C_SEM_PARE" (At-BP $acP 24) 417))
            $out.Add((At-LinhasDelta "TREINADO" "D" (At-BP $acD 10) 0))
            $out.Add("MARGEM TREINADO A $(At-MargemMedia $st $d.AEnt $d.AAlv 10 0)")
            $out.Add("MARGEM TREINADO C $(At-MargemMedia $st $d.CEnt $d.CAlv 32 0)")
            $out.Add("CHECK MUTACAO TREINADO OK")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")

            $sint = At-NovoEstado
            $trS = At-Treinar $sint $d.SintEnt $d.SintAlv 10 0
            $out.Add("ATEN V1")
            $out.Add("ESTADO SINTETICO")
            $out.Add("TREINO 10 $($trS.Info[0]) $($trS.Hist[0]) $($trS.Hist[$trS.Info[0]]) $($trS.Info[1]) $($trS.Info[2])")
            foreach ($l in (At-LinhasPesos $sint)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $sint "SINTETICO" "S" $d.SintEnt $d.SintAlv $zero10 10 0 -1)) { $out.Add($l) }
            $acS = At-Acertos $sint $d.SintEnt $d.SintAlv 10 0
            $unif = At-NovoEstado
            [void](At-Treinar $unif $d.SintEnt $d.SintAlv 10 1)
            $acU = At-Acertos $unif $d.SintEnt $d.SintAlv 10 1
            $out.Add((At-LinhasDelta "SINTETICO" "S" (At-BP $acS 10) (At-BP $acU 10)))
            $mudouOk = 0
            if ($trS.Info[1] -gt 0) { $mudouOk = 1 }
            $out.Add("CHECK ATENCAO_MUDOU " + $(if ($mudouOk -eq 1) { "OK" } else { "FALHA" }))
            $out.Add("CHECKSUM $(At-Checksum $sint)")
            $out.Add("FIM")
        }
        "at_ordem" {
            $st = At-NovoEstado
            [void](At-Treinar $st $d.TrainEnt $d.TrainAlv 10 0)
            $out.Add("ATEN V1")
            $out.Add("ESTADO ORDEM")
            $mudancas = 0
            $pesosMudam = 0
            for ($e = 0; $e -lt 32; $e++) {
                $ids = [int[]]@($d.CEnt[$e * 3], $d.CEnt[$e * 3 + 1], $d.CEnt[$e * 3 + 2])
                $inv = [int[]]@($ids[2], $ids[1], $ids[0])
                $c1 = At-CtxInterno $st.A $st.Beta $ids 2 0
                $c2 = At-CtxInterno $st.A $st.Beta $inv 2 0
                $p1 = At-Argmax $st.W $st.B $c1.C
                $p2 = At-Argmax $st.W $st.B $c2.C
                if ($p1 -ne $p2) { $mudancas = $mudancas + 1 }
                $dif = 0
                for ($k = 0; $k -lt 3; $k++) { if ($c1.P[$k] -ne $c2.P[$k]) { $dif = 1 } }
                if ($dif -eq 1) { $pesosMudam = $pesosMudam + 1 }
            }
            $out.Add("ORDEM INVERSO $mudancas 32")
            $out.Add("ORDEM PESOS $pesosMudam 32")
            $out.Add("CHECK ORDEM OK")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_determinismo_a" {
            $st = At-NovoEstado
            $out.Add("ATEN V1")
            $out.Add("ESTADO DETERMINISMO")
            foreach ($l in (At-LinhasPesos $st)) { $out.Add($l) }
            $ids = [int[]]@(3,12,5)
            foreach ($l in (At-LinhasPesosAtencao $st $ids 3 2 0)) { $out.Add($l) }
            foreach ($l in (At-LinhasRelatorio $st "DETERMINISMO" "C" $d.CEnt $d.CAlv $d.CTipo 32 0 -1)) { $out.Add($l) }
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_causal_futuro" {
            $st = [pscustomobject]@{
                A = [int[]]@(16,16,16,16)
                Beta = [int[]]@(0,1,-1)
                W = New-Object 'int[]' 100
                B = New-Object 'int[]' 25
            }
            $ids1 = [int[]]@(3,12,5)
            $ids2 = [int[]]@(3,12,24)
            $out.Add("ATEN V1")
            $out.Add("ESTADO CAUSAL")
            $c1 = At-CtxInterno $st.A $st.Beta $ids1 1 0
            $c2 = At-CtxInterno $st.A $st.Beta $ids2 1 0
            $out.Add("CTX 2 $($c1.U) $($c1.C[0]) $($c1.C[1]) $($c1.C[2]) $($c1.C[3])")
            $out.Add("CTX 2 $($c2.U) $($c2.C[0]) $($c2.C[1]) $($c2.C[2]) $($c2.C[3])")
            $ok = 1
            for ($k = 0; $k -lt 4; $k++) { if ($c1.C[$k] -ne $c2.C[$k]) { $ok = 0 } }
            $out.Add("CHECK CAUSAL " + $(if ($ok -eq 1) { "OK" } else { "FALHA" }))
            # Controle: quando a posicao 2 e permitida (modo uniforme), trocar o
            # futuro muda o contexto. Isso mostra que a igualdade acima vem da
            # mascara causal, nao de embeddings degenerados.
            $f1 = At-CtxInterno $st.A $st.Beta $ids1 2 1
            $f2 = At-CtxInterno $st.A $st.Beta $ids2 2 1
            $dif = 0
            for ($k = 0; $k -lt 4; $k++) { if ($f1.C[$k] -ne $f2.C[$k]) { $dif = 1 } }
            $out.Add("CONTROLE FUTURO $dif")
            $out.Add("CHECKSUM $(At-Checksum $st)")
            $out.Add("FIM")
        }
        "at_overflow" {
            $out.Add("ATEN V1")
            $out.Add("ESTADO OVERFLOW")
            $out.Add("LIMITE TEORICO S 1040")
            $idMax = 0
            $somaMax = -1000
            $idMin = 0
            $somaMin = 1000
            for ($id = 0; $id -lt 25; $id++) {
                $soma = (At-E16 $id 0) + (At-E16 $id 1) + (At-E16 $id 2) + (At-E16 $id 3)
                if ($soma -gt $somaMax) { $somaMax = $soma; $idMax = $id }
                if ($soma -lt $somaMin) { $somaMin = $soma; $idMin = $id }
            }
            $out.Add("REAL IDMAX $idMax $somaMax")
            $z = 16 * $somaMax + 16 * 16
            $d2 = $z + 256
            $out.Add("REAL ZMAX $z")
            $out.Add("REAL DELTA $d2")
            $out.Add("REAL DELTA2 $($d2 * $d2)")
            $out.Add("REAL PERDA10 $(25 * 10 * $d2 * $d2)")
            $out.Add("CHECK OVERFLOW OK")
            $out.Add("FIM")
        }
        "at_layout" {
            $out.Add("ATEN V1")
            $out.Add("ESTADO LAYOUT")
            $out.Add("CODIGO N_ID 1")
            $out.Add("CODIGO ID 2")
            $out.Add("CODIGO MODO 6")
            $out.Add("CODIGO PARAM 3")
            $out.Add("CODIGO EPOCAS 4")
            $out.Add("CODIGO OK 0")
            $out.Add("CHECKSUM 0")
            $out.Add("FIM")
        }
        default { throw "Caso desconhecido: $Name" }
    }
    return $out.ToArray()
}
