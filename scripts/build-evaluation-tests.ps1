<#
.SYNOPSIS
    Gera os 9 casos .por e .expected da avaliacao M9 em temp/evaluation-tests/.
.DESCRIPTION
    Fonte unica de verdade de (driver + saida esperada). Cada caso concatena
    src/tokenizador.por (M1), src/corpus.por (M8), src/contexto.por (M7) e
    src/avaliacao.por (M9) a um driver com os literais de A/B/C/D.

    O .expected vem exclusivamente do oraculo O1 (scripts/eval-oracle.ps1),
    nunca da saida real do interpretador. Grava ASCII sem BOM, LF, com um LF
    final. Tambem grava eval_separacao.txt a partir de eval-datasets.ps1.

    Uso:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-evaluation-tests.ps1
#>

param(
    [string]$SourcePath = "src/avaliacao.por",
    [string]$TokenizerSourcePath = "src/tokenizador.por",
    [string]$CorpusSourcePath = "src/corpus.por",
    [string]$ContextSourcePath = "src/contexto.por",
    [string]$OutputRoot = "temp/evaluation-tests"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

. (Join-Path $root "scripts/eval-datasets.ps1") -Quiet
. (Join-Path $root "scripts/eval-oracle.ps1") -Quiet

function Read-EvalFragment([string]$Path) {
    $text = [IO.File]::ReadAllText((Join-Path $root $Path))
    return (($text -replace "`r`n", "`n").TrimEnd("`n"))
}

function Emit-EvalArray([string]$Name, [int[]]$Values) {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("inteiro $Name[$($Values.Count)]")
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $out.Add("$Name[$i] = $($Values[$i])")
    }
    return ($out -join "`n")
}

function New-EvalArrays {
    $d = Get-EvalDataset
    $b = Get-EvalSequenceSet -Seq $d.BSeq -Count 5 -Modo 1
    $c = Get-EvalSequenceSet -Seq $d.CSeq -Count 8 -Modo 0
    $parts = @()
    $parts += Emit-EvalArray "train_e" $d.TrainEnt
    $parts += Emit-EvalArray "train_t" $d.TrainAlv
    $parts += Emit-EvalArray "a_e" $d.AEnt
    $parts += Emit-EvalArray "a_t" $d.AAlv
    $parts += Emit-EvalArray "b_e" $b.Ent
    $parts += Emit-EvalArray "b_t" $b.Alv
    $parts += Emit-EvalArray "b_tipo" $b.Tipo
    $parts += Emit-EvalArray "c_e" $c.Ent
    $parts += Emit-EvalArray "c_t" $c.Alv
    $parts += Emit-EvalArray "d_e" $d.DEnt
    $parts += Emit-EvalArray "d_t" $d.DAlv
    $parts += Emit-EvalArray "d_orig" $d.DOrig
    return ($parts -join "`n")
}

$script:EvalCommon = @'
        inteiro sem_tipo[32]
        inteiro sem_extra[32]
        inteiro i = 0
        enquanto (i < 32)
        {
            sem_tipo[i] = -1
            sem_extra[i] = -1
            i = i + 1
        }
'@

$script:EvalTrain = @'
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro h[5]
        inteiro r = corp_treinar(w16, b16, train_e, train_t, 10, 4, h)
'@

function Get-EvalDriver([string]$Name) {
    switch ($Name) {
        "eval_nao_treinado" {
            return @'
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro sem_tipo[32]
        inteiro sem_extra[32]
        inteiro i = 0
        enquanto (i < 32)
        {
            sem_tipo[i] = -1
            sem_extra[i] = -1
            i = i + 1
        }
        escreva("AVAL V1\n")
        escreva("ESTADO NAO_TREINADO\n")
        escreva("TREINO 0\n")
        aval_imprimir_estado(w16, b16, 0)
        aval_relatorio("NAO_TREINADO", "A", w16, b16, a_e, a_t, 10,
                       sem_tipo, sem_extra, 0, 1, 0)
        aval_relatorio_b("NAO_TREINADO", w16, b16, b_e, b_t, b_tipo, 1)
        aval_relatorio("NAO_TREINADO", "C", w16, b16, c_e, c_t, 32,
                       sem_tipo, sem_extra, 1, 1, 1)
        aval_relatorio("NAO_TREINADO", "D", w16, b16, d_e, d_t, 10,
                       sem_tipo, d_orig, 0, 1, 0)
        aval_imprimir_estado(w16, b16, 1)
        escreva("FIM\n")
'@
        }
        "eval_treinado" {
            return @'
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro h[5]
        inteiro r = corp_treinar(w16, b16, train_e, train_t, 10, 4, h)
        inteiro w0[300]
        inteiro b0[25]
        ctx_inicializar(w0, b0)
        inteiro sem_tipo[32]
        inteiro sem_extra[32]
        inteiro i = 0
        enquanto (i < 32)
        {
            sem_tipo[i] = -1
            sem_extra[i] = -1
            i = i + 1
        }
        escreva("AVAL V1\n")
        escreva("ESTADO CANONICO\n")
        escreva("TREINO 10\n")
        aval_imprimir_estado(w16, b16, 0)
        aval_relatorio("CANONICO", "A", w16, b16, a_e, a_t, 10,
                       sem_tipo, sem_extra, 0, 1, 0)
        aval_relatorio_b("CANONICO", w16, b16, b_e, b_t, b_tipo, 1)
        aval_relatorio("CANONICO", "C", w16, b16, c_e, c_t, 32,
                       sem_tipo, sem_extra, 1, 1, 1)
        aval_relatorio("CANONICO", "D", w16, b16, d_e, d_t, 10,
                       sem_tipo, d_orig, 0, 1, 0)

        inteiro memo[32]
        inteiro preds[32]
        aval_baseline_lookup(train_e, train_t, 10, a_e, a_t, 10, memo)
        inteiro bp_mem_a = aval_bp(aval_contar_acertos(memo, a_t, 10), 10)
        inteiro bp_can_a = aval_bp(aval_acertos_lotes(w16, b16, a_e, a_t, 10), 10)
        aval_imprimir_delta("A", bp_can_a, bp_mem_a)

        aval_baseline_lookup(train_e, train_t, 10, b_e, b_t, 20, memo)
        inteiro mem_b = aval_contar_acertos(memo, b_t, 20)
        inteiro mem_bv = aval_contar_acertos_tipo(memo, b_t, b_tipo, 20, 1)
        inteiro mem_bi = aval_contar_acertos_tipo(memo, b_t, b_tipo, 20, 0)
        aval_predizer(w16, b16, b_e, 20, preds)
        inteiro can_b = aval_contar_acertos(preds, b_t, 20)
        inteiro can_bv = aval_contar_acertos_tipo(preds, b_t, b_tipo, 20, 1)
        inteiro can_bi = aval_contar_acertos_tipo(preds, b_t, b_tipo, 20, 0)
        aval_imprimir_delta("B", aval_bp(can_b, 20), aval_bp(mem_b, 20))
        aval_imprimir_delta("B_VISTO", aval_bp(can_bv, 10), aval_bp(mem_bv, 10))
        aval_imprimir_delta("B_INEDITO", aval_bp(can_bi, 10), aval_bp(mem_bi, 10))

        aval_baseline_lookup(train_e, train_t, 10, c_e, c_t, 32, memo)
        inteiro bp_mem_c = aval_bp(aval_contar_acertos(memo, c_t, 32), 32)
        inteiro bp_can_c = aval_bp(aval_acertos_lotes(w16, b16, c_e, c_t, 32), 32)
        inteiro bp_unt_c = aval_bp(aval_acertos_lotes(w0, b0, c_e, c_t, 32), 32)
        aval_imprimir_delta("C", bp_can_c, bp_mem_c)
        aval_imprimir_delta("C", bp_can_c, bp_unt_c)

        aval_baseline_lookup(train_e, train_t, 10, d_e, d_t, 10, memo)
        inteiro bp_mem_d = aval_bp(aval_contar_acertos(memo, d_t, 10), 10)
        inteiro bp_can_d = aval_bp(aval_acertos_lotes(w16, b16, d_e, d_t, 10), 10)
        aval_imprimir_delta("D", bp_can_d, bp_mem_d)

        aval_imprimir_estado(w16, b16, 1)
        escreva("FIM\n")
'@
        }
        "eval_baselines" {
            return @'
        inteiro pred_a[32]
        inteiro pred_b[32]
        inteiro pred_c[32]
        inteiro pred_d[32]
        inteiro sem_tipo[32]
        inteiro sem_extra[32]
        inteiro i = 0
        enquanto (i < 32)
        {
            sem_tipo[i] = -1
            sem_extra[i] = -1
            i = i + 1
        }

        escreva("AVAL V1\n")
        escreva("ESTADO MEMORIZACAO\n")
        escreva("TREINO 10\n")
        aval_baseline_lookup(train_e, train_t, 10, a_e, a_t, 10, pred_a)
        aval_baseline_lookup(train_e, train_t, 10, b_e, b_t, 20, pred_b)
        aval_baseline_lookup(train_e, train_t, 10, c_e, c_t, 32, pred_c)
        aval_baseline_lookup(train_e, train_t, 10, d_e, d_t, 10, pred_d)
        aval_relatorio_baseline("MEMORIZACAO", "A", a_e, pred_a, a_t, 10,
                                sem_tipo, sem_extra, 0, 0, 0)
        aval_relatorio_baseline_b("MEMORIZACAO", b_e, pred_b, b_t, b_tipo, 0)
        aval_relatorio_baseline("MEMORIZACAO", "C", c_e, pred_c, c_t, 32,
                                sem_tipo, sem_extra, 1, 0, 1)
        aval_relatorio_baseline("MEMORIZACAO", "D", d_e, pred_d, d_t, 10,
                                sem_tipo, d_orig, 0, 0, 0)
        escreva("FIM\n")

        escreva("AVAL V1\n")
        escreva("ESTADO MAJORITARIO\n")
        escreva("TREINO 10\n")
        aval_preencher_constante(pred_a, 10, 24)
        aval_preencher_constante(pred_b, 20, 24)
        aval_preencher_constante(pred_c, 32, 24)
        aval_preencher_constante(pred_d, 10, 24)
        aval_relatorio_baseline("MAJORITARIO", "A", a_e, pred_a, a_t, 10,
                                sem_tipo, sem_extra, 0, 0, 0)
        aval_relatorio_baseline_b("MAJORITARIO", b_e, pred_b, b_t, b_tipo, 0)
        aval_relatorio_baseline("MAJORITARIO", "C", c_e, pred_c, c_t, 32,
                                sem_tipo, sem_extra, 1, 0, 1)
        aval_relatorio_baseline("MAJORITARIO", "D", d_e, pred_d, d_t, 10,
                                sem_tipo, d_orig, 0, 0, 0)
        escreva("FIM\n")
'@
        }
        "eval_controle_rotulo" {
            return @'
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro pt[10]
        inteiro i = 0
        enquanto (i < 10)
        {
            pt[i] = (train_t[i] % 24) + 1
            i = i + 1
        }
        inteiro h[5]
        inteiro r = corp_treinar(w16, b16, train_e, pt, 10, 4, h)
        inteiro sem_tipo[32]
        inteiro sem_extra[32]
        i = 0
        enquanto (i < 32)
        {
            sem_tipo[i] = -1
            sem_extra[i] = -1
            i = i + 1
        }
        escreva("AVAL V1\n")
        escreva("ESTADO ROTULO_PERMUTADO\n")
        escreva("TREINO 10\n")
        aval_imprimir_estado(w16, b16, 0)
        aval_relatorio("ROTULO_PERMUTADO", "A", w16, b16, a_e, pt, 10,
                       sem_tipo, sem_extra, 0, 0, 0)
        aval_relatorio("ROTULO_PERMUTADO", "C", w16, b16, c_e, c_t, 32,
                       sem_tipo, sem_extra, 1, 0, 1)
        aval_imprimir_estado(w16, b16, 1)
        escreva("FIM\n")
'@
        }
        "eval_controle_ordem" {
            return @'
        inteiro rev_e[30]
        inteiro rev_t[10]
        inteiro i = 0
        enquanto (i < 10)
        {
            inteiro src = 9 - i
            rev_e[i * 3] = train_e[src * 3]
            rev_e[i * 3 + 1] = train_e[src * 3 + 1]
            rev_e[i * 3 + 2] = train_e[src * 3 + 2]
            rev_t[i] = train_t[src]
            i = i + 1
        }
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro h[5]
        inteiro r = corp_treinar(w16, b16, rev_e, rev_t, 10, 4, h)
        inteiro sem_tipo[32]
        inteiro sem_extra[32]
        i = 0
        enquanto (i < 32)
        {
            sem_tipo[i] = -1
            sem_extra[i] = -1
            i = i + 1
        }
        escreva("AVAL V1\n")
        escreva("ESTADO ORDEM_INVERSA\n")
        escreva("TREINO 10\n")
        aval_imprimir_estado(w16, b16, 0)
        aval_relatorio("ORDEM_INVERSA", "A", w16, b16, a_e, a_t, 10,
                       sem_tipo, sem_extra, 0, 0, 0)
        aval_relatorio("ORDEM_INVERSA", "C", w16, b16, c_e, c_t, 32,
                       sem_tipo, sem_extra, 1, 0, 1)
        aval_imprimir_estado(w16, b16, 1)
        escreva("FIM\n")
'@
        }
        "eval_ordem_permutacoes" {
            return @'
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro h[5]
        inteiro r = corp_treinar(w16, b16, train_e, train_t, 10, 4, h)
        escreva("AVAL V1\n")
        escreva("ESTADO CANONICO\n")
        escreva("TREINO 10\n")
        aval_imprimir_estado(w16, b16, 0)
        aval_permutacoes("CANONICO", w16, b16, c_e, c_t, 32)
        aval_imprimir_estado(w16, b16, 1)
        escreva("FIM\n")
'@
        }
        "eval_limites" {
            return @'
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        aval_limites(w16, b16, train_e, train_t)
'@
        }
        default { throw "Caso sem driver: $Name" }
    }
}

$script:EvalCases = @(
    "eval_nao_treinado",
    "eval_treinado",
    "eval_baselines",
    "eval_controle_rotulo",
    "eval_controle_ordem",
    "eval_ordem_permutacoes",
    "eval_limites",
    "eval_determinismo_a",
    "eval_determinismo_b"
)

$tokenizer = Read-EvalFragment $TokenizerSourcePath
$corpus = Read-EvalFragment $CorpusSourcePath
$context = Read-EvalFragment $ContextSourcePath
$source = Read-EvalFragment $SourcePath
$arrays = New-EvalArrays

$outDir = Join-Path $root $OutputRoot
if (-not (Test-Path -LiteralPath $outDir)) {
    [void](New-Item -ItemType Directory -Path $outDir)
}

foreach ($name in $script:EvalCases) {
    $driverName = $name
    if ($name -ceq "eval_determinismo_a" -or $name -ceq "eval_determinismo_b") {
        $driverName = "eval_treinado"
    }
    $driver = Get-EvalDriver $driverName
    $program = "programa`n{`n" + $tokenizer + "`n`n" + $corpus + "`n`n" +
        $context + "`n`n" + $source + "`n`n" +
        "    funcao inicio()`n    {`n" + $arrays + "`n`n" + $driver + "`n    }`n}`n"
    $porPath = Join-Path $outDir "$name.por"
    [IO.File]::WriteAllText($porPath, $program, (New-Object System.Text.ASCIIEncoding))

    $expected = Get-EvalExpected $name
    $expectedText = (($expected -join "`n") + "`n")
    $expectedPath = Join-Path $outDir "$name.expected"
    [IO.File]::WriteAllText($expectedPath, $expectedText, (New-Object System.Text.ASCIIEncoding))
}

$sep = Assert-EvalDataset
$sepLines = New-Object System.Collections.Generic.List[string]
if ($sep.Errors.Count -eq 0) {
    $sepLines.Add("SEPARACAO=OK")
} else {
    $sepLines.Add("SEPARACAO=FALHA")
    foreach ($e in $sep.Errors) { $sepLines.Add("ERRO=$e") }
}
$sepLines.Add("HOLDOUT_BYTES=$($sep.Bytes)")
$sepLines.Add("HOLDOUT_LINHAS=$($sep.Lines)")
$sepLines.Add("HOLDOUT_SHA256=$($sep.Sha256)")
$sepLines.Add("A=$($sep.A) B_VISTO=$($sep.BSeen) B_INEDITO=$($sep.BUnseen) C=$($sep.C) C_SEM_PARE=$($sep.CSemPare) D=$($sep.D)")
$sepLines.Add("VAZAMENTOS_CONTEXTO=$($sep.CLeaks)")
$sepLines.Add("VAZAMENTOS_SUFIXO2=$($sep.SuffixLeaks)")
$sepLines.Add("ALVOS24 A=$($sep.A24) B=$($sep.B24) C=$($sep.C24) D=$($sep.D24)")
$sepLines.Add("MEMORIZACAO A=$($sep.MemA) B=$($sep.MemB) C=$($sep.MemC) D=$($sep.MemD)")
[IO.File]::WriteAllText((Join-Path $outDir "eval_separacao.expected"),
    ((($sepLines -join "`n") + "`n")), (New-Object System.Text.ASCIIEncoding))

if ($sep.Errors.Count -ne 0) {
    throw "Separacao invalida: $($sep.Errors -join '; ')"
}

Write-Host "BUILD_EVALUATION=OK casos=$($script:EvalCases.Count) separacao=OK"
