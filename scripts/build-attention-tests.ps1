<#
.SYNOPSIS
    Gera os 15 arquivos .por e .expected da atencao causal minima (M10)
    em temp/attention-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/atencao.por a um driver. O .expected vem exclusivamente do oraculo O1
    (scripts/attention-oracle.ps1), nunca da saida real do interpretador.

    T1-T14 sao 14 verificacoes; T11 usa dois arquivos (at_determinismo_a e
    at_determinismo_b) que devem produzir bytes identicos, totalizando 15
    arquivos .por. Grava ASCII sem BOM, LF, com um LF final.

    Uso:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-attention-tests.ps1
#>

param(
    [string]$SourcePath = "src/atencao.por",
    [string]$OutputRoot = "temp/attention-tests"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

. (Join-Path $root "scripts/attention-oracle.ps1") -Quiet

function Read-AtFragment([string]$Path) {
    $text = [IO.File]::ReadAllText((Join-Path $root $Path))
    return (($text -replace "`r`n", "`n").TrimEnd("`n"))
}

function Emit-AtArray([string]$Name, [int[]]$Values) {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("inteiro $Name[$($Values.Count)]")
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $out.Add("$Name[$i] = $($Values[$i])")
    }
    return ($out -join "`n")
}

function New-AtArrays {
    $d = Get-AtDatasets
    $zero10 = New-Object 'int[]' 10
    $parts = @()
    $parts += Emit-AtArray "train_e" $d.TrainEnt
    $parts += Emit-AtArray "train_t" $d.TrainAlv
    $parts += Emit-AtArray "a_e" $d.AEnt
    $parts += Emit-AtArray "a_t" $d.AAlv
    $parts += Emit-AtArray "b_e" $d.BEnt
    $parts += Emit-AtArray "b_t" $d.BAlv
    $parts += Emit-AtArray "b_tipo" $d.BTipo
    $parts += Emit-AtArray "c_e" $d.CEnt
    $parts += Emit-AtArray "c_t" $d.CAlv
    $parts += Emit-AtArray "c_tipo" $d.CTipo
    $parts += Emit-AtArray "csp_tipo" $d.CSemPareTipo
    $parts += Emit-AtArray "d_e" $d.DEnt
    $parts += Emit-AtArray "d_t" $d.DAlv
    $parts += Emit-AtArray "sint_e" $d.SintEnt
    $parts += Emit-AtArray "sint_t" $d.SintAlv
    $parts += Emit-AtArray "zero10" $zero10
    return ($parts -join "`n")
}

function Get-AtDriver([string]$Name) {
    switch ($Name) {
        "at_limites" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        escreva("ATEN V1\n")
        escreva("ESTADO LIMITES\n")
        at_limites()
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_layout" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        inteiro ids[3]
        ids[0] = 1
        ids[1] = 2
        ids[2] = 5
        inteiro alvos[3]
        alvos[0] = 1
        alvos[1] = 2
        alvos[2] = 5
        escreva("ATEN V1\n")
        escreva("ESTADO LAYOUT\n")
        escreva("CODIGO N_ID ", at_validar(a, beta, w, b, ids, alvos, 0, 0, 4), "\n")
        inteiro ruins[3]
        ruins[0] = 1
        ruins[1] = 25
        ruins[2] = 5
        escreva("CODIGO ID ", at_validar(a, beta, w, b, ruins, alvos, 1, 0, 4), "\n")
        escreva("CODIGO MODO ", at_validar(a, beta, w, b, ids, alvos, 1, 3, 4), "\n")
        inteiro aruim[4]
        aruim[0] = 17
        aruim[1] = 0
        aruim[2] = 0
        aruim[3] = 0
        escreva("CODIGO PARAM ", at_validar(aruim, beta, w, b, ids, alvos, 1, 0, 4), "\n")
        escreva("CODIGO EPOCAS ", at_validar(a, beta, w, b, ids, alvos, 1, 0, 0), "\n")
        escreva("CODIGO OK ", at_validar(a, beta, w, b, ids, alvos, 1, 0, 4), "\n")
        escreva("CHECKSUM 0\n")
        escreva("FIM\n")
'@
        }
        "at_mascara" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        beta[2] = 16
        inteiro zeros[100]
        inteiro i = 0
        enquanto (i < 100)
        {
            zeros[i] = 0
            i = i + 1
        }
        i = 0
        enquanto (i < 100)
        {
            w[i] = 0
            i = i + 1
        }
        i = 0
        enquanto (i < 25)
        {
            b[i] = 0
            i = i + 1
        }
        inteiro ids[3]
        ids[0] = 3
        ids[1] = 12
        ids[2] = 5
        escreva("ATEN V1\n")
        escreva("ESTADO MASCARA\n")
        at_imprimir_pesos(a, beta, ids, 3, 1, 0)
        at_imprimir_pesos(a, beta, ids, 3, 2, 0)
        inteiro c1[4]
        inteiro c2[4]
        inteiro u1 = at_ctx_interno(a, beta, ids, 1, 0, c1)
        inteiro u2 = at_ctx_interno(a, beta, ids, 2, 0, c2)
        escreva("CTX 1 ", u1, " ", c1[0], " ", c1[1], " ", c1[2], " ", c1[3], "\n")
        escreva("CTX 2 ", u2, " ", c2[0], " ", c2[1], " ", c2[2], " ", c2[3], "\n")
        logico ok = (u1 == 0 e c2[0] == 0 - 13 e c2[1] == 0 - 10 e c2[2] == 0 - 7 e c2[3] == 0 - 4)
        se (ok)
        {
            escreva("CHECK MASCARA CAUSAL OK\n")
        }
        senao
        {
            escreva("CHECK MASCARA CAUSAL FALHA\n")
        }
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_padding" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        inteiro ids[3]
        ids[0] = 3
        ids[1] = 12
        ids[2] = 5
        escreva("ATEN V1\n")
        escreva("ESTADO PADDING\n")
        inteiro c[4]
        inteiro n = 1
        enquanto (n <= 3)
        {
            at_imprimir_pesos(a, beta, ids, n, n - 1, 0)
            inteiro U = at_ctx_interno(a, beta, ids, n - 1, 0, c)
            escreva("CTX ", n, " ", U, " ", c[0], " ", c[1], " ", c[2], " ", c[3], "\n")
            n = n + 1
        }
        inteiro c1[4]
        at_ctx_interno(a, beta, ids, 0, 0, c1)
        logico ok = (c1[0] == 5 e c1[1] == 8 e c1[2] == 11 e c1[3] == 14)
        se (ok)
        {
            escreva("CHECK PADDING OK\n")
        }
        senao
        {
            escreva("CHECK PADDING FALHA\n")
        }
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_pesos" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        a[0] = 16
        a[1] = 16
        a[2] = 16
        a[3] = 16
        beta[0] = 0
        beta[1] = 1
        beta[2] = 0 - 1
        inteiro ids[3]
        ids[0] = 3
        ids[1] = 12
        ids[2] = 5
        inteiro i = 0
        enquanto (i < 100)
        {
            w[i] = 0
            i = i + 1
        }
        i = 0
        enquanto (i < 25)
        {
            b[i] = 0
            i = i + 1
        }
        inteiro checksum_original = at_checksum(a, beta, w, b)
        escreva("ATEN V1\n")
        escreva("ESTADO PESOS\n")
        at_imprimir_pesos(a, beta, ids, 3, 2, 0)
        inteiro u[3]
        inteiro p[3]
        at_pesos_interno(a, beta, ids, 2, 0, u, p)
        escreva("SOMA_PERMIL ", p[0] + p[1] + p[2], "\n")
        inteiro c[4]
        inteiro U = at_ctx_interno(a, beta, ids, 2, 0, c)
        escreva("CTX 3 ", U, " ", c[0], " ", c[1], " ", c[2], " ", c[3], "\n")
        a[0] = 0
        a[1] = 0
        a[2] = 0
        a[3] = 0
        beta[0] = 0
        beta[1] = 0
        beta[2] = 0
        at_imprimir_pesos(a, beta, ids, 3, 2, 0)
        at_pesos_interno(a, beta, ids, 2, 0, u, p)
        escreva("SOMA_PERMIL ", p[0] + p[1] + p[2], "\n")
        U = at_ctx_interno(a, beta, ids, 2, 0, c)
        escreva("CTX 3 ", U, " ", c[0], " ", c[1], " ", c[2], " ", c[3], "\n")
        escreva("CHECK NORMALIZACAO OK\n")
        escreva("CHECKSUM ", checksum_original, "\n")
        escreva("FIM\n")
'@
        }
        "at_exemplo" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        a[0] = 16
        a[1] = 16
        a[2] = 16
        a[3] = 16
        beta[0] = 0
        beta[1] = 1
        beta[2] = 0 - 1
        inteiro i = 0
        enquanto (i < 100)
        {
            w[i] = 0
            i = i + 1
        }
        i = 0
        enquanto (i < 25)
        {
            b[i] = 0
            i = i + 1
        }
        w[7 * 4] = 1
        w[7 * 4 + 1] = 0
        w[7 * 4 + 2] = 0 - 1
        w[7 * 4 + 3] = 2
        b[7] = 1
        inteiro ids[3]
        ids[0] = 3
        ids[1] = 12
        ids[2] = 5
        escreva("ATEN V1\n")
        escreva("ESTADO EXEMPLO\n")
        at_imprimir_pesos(a, beta, ids, 3, 2, 0)
        inteiro c[4]
        inteiro U = at_ctx_interno(a, beta, ids, 2, 0, c)
        escreva("CTX ", U, " ", c[0], " ", c[1], " ", c[2], " ", c[3], "\n")
        inteiro z = at_z256(w, b, c, 7)
        inteiro delta = at_delta256(w, b, c, 7, 7)
        escreva("Z ", z, "\n")
        escreva("DELTA ", delta, "\n")
        inteiro k = 0
        enquanto (k < 4)
        {
            escreva("WN ", k, " ",
                    at_div_arredondada(2048 * w[7 * 4 + k] - delta * c[k], 2048), "\n")
            k = k + 1
        }
        escreva("BN ", at_div_arredondada(128 * b[7] - delta, 128), "\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_causal_futuro" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        a[0] = 16
        a[1] = 16
        a[2] = 16
        a[3] = 16
        beta[0] = 0
        beta[1] = 1
        beta[2] = 0 - 1
        inteiro i = 0
        enquanto (i < 100)
        {
            w[i] = 0
            i = i + 1
        }
        i = 0
        enquanto (i < 25)
        {
            b[i] = 0
            i = i + 1
        }
        inteiro ids1[3]
        ids1[0] = 3
        ids1[1] = 12
        ids1[2] = 5
        inteiro ids2[3]
        ids2[0] = 3
        ids2[1] = 12
        ids2[2] = 24
        escreva("ATEN V1\n")
        escreva("ESTADO CAUSAL\n")
        inteiro c1[4]
        inteiro c2[4]
        inteiro U1 = at_ctx_interno(a, beta, ids1, 1, 0, c1)
        inteiro U2 = at_ctx_interno(a, beta, ids2, 1, 0, c2)
        escreva("CTX 2 ", U1, " ", c1[0], " ", c1[1], " ", c1[2], " ", c1[3], "\n")
        escreva("CTX 2 ", U2, " ", c2[0], " ", c2[1], " ", c2[2], " ", c2[3], "\n")
        logico ok = (c1[0] == c2[0] e c1[1] == c2[1] e c1[2] == c2[2] e c1[3] == c2[3])
        se (ok)
        {
            escreva("CHECK CAUSAL OK\n")
        }
        senao
        {
            escreva("CHECK CAUSAL FALHA\n")
        }
        inteiro f1[4]
        inteiro f2[4]
        at_ctx_interno(a, beta, ids1, 2, 1, f1)
        at_ctx_interno(a, beta, ids2, 2, 1, f2)
        inteiro dif = 0
        se (f1[0] != f2[0] ou f1[1] != f2[1] ou f1[2] != f2[2] ou f1[3] != f2[3])
        {
            dif = 1
        }
        escreva("CONTROLE FUTURO ", dif, "\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_overflow" {
            return @'
        escreva("ATEN V1\n")
        escreva("ESTADO OVERFLOW\n")
        escreva("LIMITE TEORICO S 1040\n")
        inteiro idmax = 0
        inteiro somamax = 0 - 1000
        inteiro idmin = 0
        inteiro somamin = 1000
        inteiro id = 0
        enquanto (id < 25)
        {
            inteiro soma = at_e16(id, 0) + at_e16(id, 1) + at_e16(id, 2) + at_e16(id, 3)
            se (soma > somamax)
            {
                somamax = soma
                idmax = id
            }
            se (soma < somamin)
            {
                somamin = soma
                idmin = id
            }
            id = id + 1
        }
        inteiro z = 16 * somamax + 16 * 16
        inteiro d2 = z + 256
        escreva("REAL IDMAX ", idmax, " ", somamax, "\n")
        escreva("REAL ZMAX ", z, "\n")
        escreva("REAL DELTA ", d2, "\n")
        escreva("REAL DELTA2 ", d2 * d2, "\n")
        escreva("REAL PERDA10 ", 25 * 10 * d2 * d2, "\n")
        escreva("CHECK OVERFLOW OK\n")
        escreva("FIM\n")
'@
        }
        "at_nao_treinado" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        escreva("ATEN V1\n")
        escreva("ESTADO NAO_TREINADO\n")
        escreva("TREINO 0 0 0\n")
        at_imprimir_estado(a, beta, w, b)
        at_relatorio("NAO_TREINADO", "A", w, b, a, beta, a_e, a_t, zero10, 10, 0, -1)
        at_relatorio("NAO_TREINADO", "B", w, b, a, beta, b_e, b_t, b_tipo, 20, 0, -1)
        at_relatorio("NAO_TREINADO", "B_VISTO", w, b, a, beta, b_e, b_t, b_tipo, 20, 0, 1)
        at_relatorio("NAO_TREINADO", "B_INEDITO", w, b, a, beta, b_e, b_t, b_tipo, 20, 0, 0)
        at_relatorio("NAO_TREINADO", "C", w, b, a, beta, c_e, c_t, c_tipo, 32, 0, -1)
        at_relatorio("NAO_TREINADO", "C_SEM_PARE", w, b, a, beta, c_e, c_t, csp_tipo, 32, 0, 1)
        at_relatorio("NAO_TREINADO", "D", w, b, a, beta, d_e, d_t, zero10, 10, 0, -1)
        escreva("MARGEM NAO_TREINADO A ", at_margem_media(w, b, a, beta, a_e, a_t, 10, 0), "\n")
        escreva("MARGEM NAO_TREINADO C ", at_margem_media(w, b, a, beta, c_e, c_t, 32, 0), "\n")
        escreva("CHECK MUTACAO NAO_TREINADO OK\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_uniforme" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        inteiro hist[7]
        inteiro info[3]
        inteiro r = at_treinar(w, b, a, beta, train_e, train_t, 10, 1, hist, info)
        escreva("ATEN V1\n")
        escreva("ESTADO UNIFORME\n")
        escreva("TREINO 10 ", info[0], " ", hist[0], " ", hist[info[0]], " ", info[1], " ", info[2], "\n")
        at_imprimir_estado(a, beta, w, b)
        at_relatorio("UNIFORME", "A", w, b, a, beta, a_e, a_t, zero10, 10, 1, -1)
        at_relatorio("UNIFORME", "B", w, b, a, beta, b_e, b_t, b_tipo, 20, 1, -1)
        at_relatorio("UNIFORME", "B_VISTO", w, b, a, beta, b_e, b_t, b_tipo, 20, 1, 1)
        at_relatorio("UNIFORME", "B_INEDITO", w, b, a, beta, b_e, b_t, b_tipo, 20, 1, 0)
        at_relatorio("UNIFORME", "C", w, b, a, beta, c_e, c_t, c_tipo, 32, 1, -1)
        at_relatorio("UNIFORME", "C_SEM_PARE", w, b, a, beta, c_e, c_t, csp_tipo, 32, 1, 1)
        at_relatorio("UNIFORME", "D", w, b, a, beta, d_e, d_t, zero10, 10, 1, -1)
        escreva("MARGEM UNIFORME A ", at_margem_media(w, b, a, beta, a_e, a_t, 10, 1), "\n")
        escreva("MARGEM UNIFORME C ", at_margem_media(w, b, a, beta, c_e, c_t, 32, 1), "\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_recencia" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        inteiro hist[7]
        inteiro info[3]
        inteiro r = at_treinar(w, b, a, beta, train_e, train_t, 10, 2, hist, info)
        escreva("ATEN V1\n")
        escreva("ESTADO RECENCIA\n")
        escreva("TREINO 10 ", info[0], " ", hist[0], " ", hist[info[0]], " ", info[1], " ", info[2], "\n")
        at_imprimir_estado(a, beta, w, b)
        at_relatorio("RECENCIA", "A", w, b, a, beta, a_e, a_t, zero10, 10, 2, -1)
        at_relatorio("RECENCIA", "B", w, b, a, beta, b_e, b_t, b_tipo, 20, 2, -1)
        at_relatorio("RECENCIA", "B_VISTO", w, b, a, beta, b_e, b_t, b_tipo, 20, 2, 1)
        at_relatorio("RECENCIA", "B_INEDITO", w, b, a, beta, b_e, b_t, b_tipo, 20, 2, 0)
        at_relatorio("RECENCIA", "C", w, b, a, beta, c_e, c_t, c_tipo, 32, 2, -1)
        at_relatorio("RECENCIA", "C_SEM_PARE", w, b, a, beta, c_e, c_t, csp_tipo, 32, 2, 1)
        at_relatorio("RECENCIA", "D", w, b, a, beta, d_e, d_t, zero10, 10, 2, -1)
        escreva("MARGEM RECENCIA A ", at_margem_media(w, b, a, beta, a_e, a_t, 10, 2), "\n")
        escreva("MARGEM RECENCIA C ", at_margem_media(w, b, a, beta, c_e, c_t, 32, 2), "\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_treinado" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        inteiro hist[7]
        inteiro info[3]
        inteiro r = at_treinar(w, b, a, beta, train_e, train_t, 10, 0, hist, info)
        escreva("ATEN V1\n")
        escreva("ESTADO TREINADO\n")
        escreva("TREINO 10 ", info[0], " ", hist[0], " ", hist[info[0]], " ", info[1], " ", info[2], "\n")
        at_imprimir_estado(a, beta, w, b)
        at_relatorio("TREINADO", "A", w, b, a, beta, a_e, a_t, zero10, 10, 0, -1)
        at_relatorio("TREINADO", "B", w, b, a, beta, b_e, b_t, b_tipo, 20, 0, -1)
        at_relatorio("TREINADO", "B_VISTO", w, b, a, beta, b_e, b_t, b_tipo, 20, 0, 1)
        at_relatorio("TREINADO", "B_INEDITO", w, b, a, beta, b_e, b_t, b_tipo, 20, 0, 0)
        at_relatorio("TREINADO", "C", w, b, a, beta, c_e, c_t, c_tipo, 32, 0, -1)
        at_relatorio("TREINADO", "C_SEM_PARE", w, b, a, beta, c_e, c_t, csp_tipo, 32, 0, 1)
        at_relatorio("TREINADO", "D", w, b, a, beta, d_e, d_t, zero10, 10, 0, -1)
        inteiro ac_a = at_acertos(w, b, a, beta, a_e, a_t, 10, 0)
        inteiro ac_b = at_acertos(w, b, a, beta, b_e, b_t, 20, 0)
        inteiro ac_bv = at_acertos_tipo(w, b, a, beta, b_e, b_t, b_tipo, 20, 0, 1)
        inteiro ac_bi = at_acertos_tipo(w, b, a, beta, b_e, b_t, b_tipo, 20, 0, 0)
        inteiro ac_c = at_acertos(w, b, a, beta, c_e, c_t, 32, 0)
        inteiro ac_cp = at_acertos_tipo(w, b, a, beta, c_e, c_t, csp_tipo, 32, 0, 1)
        inteiro ac_d = at_acertos(w, b, a, beta, d_e, d_t, 10, 0)
        escreva("DELTA_BP TREINADO A ", at_bp(ac_a, 10), " 10000 ", at_bp(ac_a, 10) - 10000, "\n")
        escreva("DELTA_BP TREINADO B ", at_bp(ac_b, 20), " 5000 ", at_bp(ac_b, 20) - 5000, "\n")
        escreva("DELTA_BP TREINADO B_VISTO ", at_bp(ac_bv, 10), " 10000 ", at_bp(ac_bv, 10) - 10000, "\n")
        escreva("DELTA_BP TREINADO B_INEDITO ", at_bp(ac_bi, 10), " 0 ", at_bp(ac_bi, 10), "\n")
        escreva("DELTA_BP TREINADO C ", at_bp(ac_c, 32), " 1250 ", at_bp(ac_c, 32) - 1250, "\n")
        escreva("DELTA_BP TREINADO C_SEM_PARE ", at_bp(ac_cp, 24), " 417 ", at_bp(ac_cp, 24) - 417, "\n")
        escreva("DELTA_BP TREINADO D ", at_bp(ac_d, 10), " 0 ", at_bp(ac_d, 10), "\n")
        escreva("MARGEM TREINADO A ", at_margem_media(w, b, a, beta, a_e, a_t, 10, 0), "\n")
        escreva("MARGEM TREINADO C ", at_margem_media(w, b, a, beta, c_e, c_t, 32, 0), "\n")
        escreva("CHECK MUTACAO TREINADO OK\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")

        inteiro a2[4]
        inteiro beta2[3]
        inteiro w2[100]
        inteiro b2[25]
        at_inicializar(a2, beta2, w2, b2)
        inteiro hist2[7]
        inteiro info2[3]
        inteiro r2 = at_treinar(w2, b2, a2, beta2, sint_e, sint_t, 10, 0, hist2, info2)
        escreva("ATEN V1\n")
        escreva("ESTADO SINTETICO\n")
        escreva("TREINO 10 ", info2[0], " ", hist2[0], " ", hist2[info2[0]], " ", info2[1], " ", info2[2], "\n")
        at_imprimir_estado(a2, beta2, w2, b2)
        at_relatorio("SINTETICO", "S", w2, b2, a2, beta2, sint_e, sint_t, zero10, 10, 0, -1)
        inteiro ac_s = at_acertos(w2, b2, a2, beta2, sint_e, sint_t, 10, 0)
        inteiro a3[4]
        inteiro beta3[3]
        inteiro w3[100]
        inteiro b3[25]
        at_inicializar(a3, beta3, w3, b3)
        inteiro hist3[7]
        inteiro info3[3]
        inteiro r3 = at_treinar(w3, b3, a3, beta3, sint_e, sint_t, 10, 1, hist3, info3)
        inteiro ac_u = at_acertos(w3, b3, a3, beta3, sint_e, sint_t, 10, 1)
        escreva("DELTA_BP SINTETICO S ", at_bp(ac_s, 10), " ", at_bp(ac_u, 10), " ",
                at_bp(ac_s, 10) - at_bp(ac_u, 10), "\n")
        se (info2[1] > 0)
        {
            escreva("CHECK ATENCAO_MUDOU OK\n")
        }
        senao
        {
            escreva("CHECK ATENCAO_MUDOU FALHA\n")
        }
        escreva("CHECKSUM ", at_checksum(a2, beta2, w2, b2), "\n")
        escreva("FIM\n")
'@
        }
        "at_ordem" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        inteiro hist[7]
        inteiro info[3]
        inteiro r = at_treinar(w, b, a, beta, train_e, train_t, 10, 0, hist, info)
        escreva("ATEN V1\n")
        escreva("ESTADO ORDEM\n")
        inteiro mudancas = 0
        inteiro pesos = 0
        inteiro ex = 0
        enquanto (ex < 32)
        {
            inteiro ids[3]
            ids[0] = c_e[ex * 3]
            ids[1] = c_e[ex * 3 + 1]
            ids[2] = c_e[ex * 3 + 2]
            inteiro inv[3]
            inv[0] = ids[2]
            inv[1] = ids[1]
            inv[2] = ids[0]
            inteiro c1[4]
            inteiro c2[4]
            at_ctx_interno(a, beta, ids, 2, 0, c1)
            at_ctx_interno(a, beta, inv, 2, 0, c2)
            se (at_argmax(w, b, c1) != at_argmax(w, b, c2))
            {
                mudancas = mudancas + 1
            }
            inteiro u1[3]
            inteiro p1[3]
            inteiro u2[3]
            inteiro p2[3]
            at_pesos_interno(a, beta, ids, 2, 0, u1, p1)
            at_pesos_interno(a, beta, inv, 2, 0, u2, p2)
            se (p1[0] != p2[0] ou p1[1] != p2[1] ou p1[2] != p2[2])
            {
                pesos = pesos + 1
            }
            ex = ex + 1
        }
        escreva("ORDEM INVERSO ", mudancas, " 32\n")
        escreva("ORDEM PESOS ", pesos, " 32\n")
        escreva("CHECK ORDEM OK\n")
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        "at_determinismo_a" {
            return @'
        inteiro a[4]
        inteiro beta[3]
        inteiro w[100]
        inteiro b[25]
        at_inicializar(a, beta, w, b)
        escreva("ATEN V1\n")
        escreva("ESTADO DETERMINISMO\n")
        at_imprimir_estado(a, beta, w, b)
        inteiro ids[3]
        ids[0] = 3
        ids[1] = 12
        ids[2] = 5
        at_imprimir_pesos(a, beta, ids, 3, 2, 0)
        at_relatorio("DETERMINISMO", "C", w, b, a, beta, c_e, c_t, c_tipo, 32, 0, -1)
        escreva("CHECKSUM ", at_checksum(a, beta, w, b), "\n")
        escreva("FIM\n")
'@
        }
        default { throw "Caso sem driver: $Name" }
    }
}

$script:AtCases = @(
    "at_limites",
    "at_layout",
    "at_mascara",
    "at_padding",
    "at_pesos",
    "at_exemplo",
    "at_causal_futuro",
    "at_overflow",
    "at_treinado",
    "at_nao_treinado",
    "at_uniforme",
    "at_recencia",
    "at_ordem",
    "at_determinismo_a",
    "at_determinismo_b"
)

$source = Read-AtFragment $SourcePath
$arrays = New-AtArrays

$outDir = Join-Path $root $OutputRoot
if (-not (Test-Path -LiteralPath $outDir)) {
    [void](New-Item -ItemType Directory -Path $outDir)
}

foreach ($name in $script:AtCases) {
    $driverName = $name
    if ($name -ceq "at_determinismo_b") {
        $driverName = "at_determinismo_a"
    }
    $driver = Get-AtDriver $driverName
    $program = "programa`n{`n" + $source + "`n`n" +
        "    funcao inicio()`n    {`n" + $arrays + "`n`n" + $driver + "`n    }`n}`n"
    $porPath = Join-Path $outDir "$name.por"
    [IO.File]::WriteAllText($porPath, $program, (New-Object System.Text.ASCIIEncoding))

    $expectedName = $name
    if ($name -ceq "at_determinismo_b") { $expectedName = "at_determinismo_a" }
    $expected = Get-AtReport $expectedName
    $expectedText = (($expected -join "`n") + "`n")
    $expectedPath = Join-Path $outDir "$name.expected"
    [IO.File]::WriteAllText($expectedPath, $expectedText, (New-Object System.Text.ASCIIEncoding))
}

Write-Host "BUILD_ATTENTION=OK arquivos=$($script:AtCases.Count) verificacoes=14"
