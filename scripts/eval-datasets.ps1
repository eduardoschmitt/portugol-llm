<#
.SYNOPSIS
    Datasets canonicos da avaliacao de generalizacao (M9).

.DESCRIPTION
    Fonte unica de verdade dos literais de A/B/C/D e da serializacao do
    holdout EVAL-V1. O script nao executa o modelo: apenas monta, serializa e
    audita os dados contra o hash pre-registrado.

    Uso direto:
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/eval-datasets.ps1 -Check

    Uso como biblioteca:
        . ./scripts/eval-datasets.ps1 -Quiet

    Saida: linhas ASCII, LF, deterministas.
#>

param(
    [switch]$Check,
    [switch]$Quiet,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$script:EvalHoldoutBytes = 724
$script:EvalHoldoutLines = 50
$script:EvalHoldoutSha256 = "e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10"

function Get-EvalDataset {
    $trainEnt = [int[]]@(
        1, 3, 17, 3, 17, 22, 2, 3, 17, 3, 17, 23, 9, 22, 12,
        22, 12, 17, 9, 23, 10, 23, 10, 18, 11, 22, 12, 22, 12, 18
    )
    $trainAlv = [int[]]@(22, 24, 23, 24, 17, 24, 18, 24, 18, 24)

    $aEnt = [int[]]@(
        1, 3, 17, 3, 17, 22, 2, 3, 17, 3, 17, 23, 9, 22, 12,
        22, 12, 17, 9, 23, 10, 23, 10, 18, 11, 22, 12, 22, 12, 18
    )
    $aAlv = [int[]]@(22, 24, 23, 24, 17, 24, 18, 24, 18, 24)

    $bSeq = [int[]]@(
        4, 7, 9, 22, 12, 17, 24,
        5, 13, 11, 22, 12, 18, 24,
        6, 14, 9, 23, 10, 18, 24,
        8, 15, 1, 3, 17, 22, 24,
        7, 16, 2, 3, 17, 23, 24
    )

    $cSeq = [int[]]@(
        4, 7, 5, 13, 6, 18, 24,
        8, 19, 14, 21, 15, 5, 24,
        6, 16, 1, 20, 2, 13, 24,
        7, 11, 4, 19, 5, 20, 24,
        13, 8, 21, 16, 14, 2, 24,
        15, 9, 20, 3, 10, 6, 24,
        5, 14, 2, 8, 19, 11, 24,
        20, 6, 15, 7, 21, 4, 24
    )

    $dEnt = [int[]]@(
        1, 3, 17, 3, 17, 22, 2, 3, 17, 3, 17, 23, 9, 22, 12,
        22, 12, 17, 9, 23, 10, 23, 10, 18, 11, 22, 12, 22, 12, 18
    )
    $dOrig = [int[]]@(22, 24, 23, 24, 17, 24, 18, 24, 18, 24)
    $dAlv = [int[]]@(23, 1, 24, 1, 18, 1, 19, 1, 19, 1)

    return [pscustomobject]@{
        TrainEnt = $trainEnt
        TrainAlv = $trainAlv
        AEnt = $aEnt
        AAlv = $aAlv
        BSeq = $bSeq
        BCount = 5
        CSeq = $cSeq
        CCount = 8
        DEnt = $dEnt
        DOrig = $dOrig
        DAlv = $dAlv
    }
}

function Expand-EvalSequence {
    param(
        [int[]]$Seq,
        [int]$Count,
        [int]$Modo
    )
    # Modo 0: todos INEDITO. Modo 1: B (j<2 INEDITO, j>=2 VISTO).
    $n = $Count * 4
    $ent = New-Object 'int[]' ($n * 3)
    $alv = New-Object 'int[]' $n
    $tipo = New-Object 'int[]' $n
    for ($s = 0; $s -lt $Count; $s++) {
        for ($j = 0; $j -lt 4; $j++) {
            $idx = $s * 4 + $j
            $ent[$idx * 3] = $Seq[$s * 7 + $j]
            $ent[$idx * 3 + 1] = $Seq[$s * 7 + $j + 1]
            $ent[$idx * 3 + 2] = $Seq[$s * 7 + $j + 2]
            $alv[$idx] = $Seq[$s * 7 + $j + 3]
            if ($Modo -eq 1 -and $j -ge 2) { $tipo[$idx] = 1 } else { $tipo[$idx] = 0 }
        }
    }
    return [pscustomobject]@{ Ent = $ent; Alv = $alv; Tipo = $tipo; N = $n }
}

function Get-EvalSequenceSet {
    param([int[]]$Seq, [int]$Count, [int]$Modo)
    return Expand-EvalSequence -Seq $Seq -Count $Count -Modo $Modo
}

function Get-EvalHoldoutText {
    $d = Get-EvalDataset
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("EVAL-V1")
    $lines.Add("TRAIN 10")
    for ($i = 0; $i -lt 10; $i++) {
        $lines.Add("T " + $d.TrainEnt[$i * 3] + " " + $d.TrainEnt[$i * 3 + 1] + " " +
                   $d.TrainEnt[$i * 3 + 2] + " " + $d.TrainAlv[$i])
    }
    $lines.Add("A 10")
    for ($i = 0; $i -lt 10; $i++) {
        $lines.Add("A " + $d.AEnt[$i * 3] + " " + $d.AEnt[$i * 3 + 1] + " " +
                   $d.AEnt[$i * 3 + 2] + " " + $d.AAlv[$i])
    }
    $lines.Add("B 5")
    for ($s = 0; $s -lt 5; $s++) {
        $parts = @()
        for ($k = 0; $k -lt 7; $k++) { $parts += [string]$d.BSeq[$s * 7 + $k] }
        $lines.Add("B " + ($parts -join " "))
    }
    $lines.Add("C 8")
    for ($s = 0; $s -lt 8; $s++) {
        $parts = @()
        for ($k = 0; $k -lt 7; $k++) { $parts += [string]$d.CSeq[$s * 7 + $k] }
        $lines.Add("C " + ($parts -join " "))
    }
    $lines.Add("D 10")
    for ($i = 0; $i -lt 10; $i++) {
        $lines.Add("D " + $d.DEnt[$i * 3] + " " + $d.DEnt[$i * 3 + 1] + " " +
                   $d.DEnt[$i * 3 + 2] + " " + $d.DOrig[$i] + " " + $d.DAlv[$i])
    }
    $lines.Add("END")
    return (($lines -join "`n") + "`n")
}

function Get-EvalHoldoutBytes {
    return [Text.Encoding]::ASCII.GetBytes((Get-EvalHoldoutText))
}

function Get-EvalHoldoutSha256 {
    $bytes = Get-EvalHoldoutBytes
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Get-EvalContextKey {
    param([int[]]$Ent, [int]$Index)
    return "$($Ent[$Index * 3]),$($Ent[$Index * 3 + 1]),$($Ent[$Index * 3 + 2])"
}

function Get-EvalTrainContextSet {
    param([int[]]$Ent)
    $set = @{}
    for ($i = 0; $i -lt 10; $i++) { $set[(Get-EvalContextKey $Ent $i)] = $true }
    return $set
}

function Get-EvalPairKey {
    param([int[]]$Ent, [int[]]$Alv, [int]$Index)
    return "$($Ent[$Index * 3]),$($Ent[$Index * 3 + 1]),$($Ent[$Index * 3 + 2]),$($Alv[$Index])"
}

function Test-EvalSameIntArray {
    param([int[]]$A, [int[]]$B, [int]$N)
    if ($A.Length -lt $N -or $B.Length -lt $N) { return $false }
    for ($i = 0; $i -lt $N; $i++) {
        if ($A[$i] -ne $B[$i]) { return $false }
    }
    return $true
}

function Assert-EvalDataset {
    $d = Get-EvalDataset
    $errors = New-Object System.Collections.Generic.List[string]

    $text = Get-EvalHoldoutText
    $bytes = [Text.Encoding]::ASCII.GetBytes($text)
    $lines = @($text.TrimEnd("`n").Split("`n"))
    $sha = Get-EvalHoldoutSha256

    if ($bytes.Length -ne $script:EvalHoldoutBytes) {
        $errors.Add("holdout com $($bytes.Length) bytes; esperado $($script:EvalHoldoutBytes)")
    }
    if ($lines.Count -ne $script:EvalHoldoutLines) {
        $errors.Add("holdout com $($lines.Count) linhas; esperado $($script:EvalHoldoutLines)")
    }
    if ($sha -cne $script:EvalHoldoutSha256) {
        $errors.Add("SHA-256 do holdout: $sha; esperado $($script:EvalHoldoutSha256)")
    }
    if (-not $text.EndsWith("`n")) { $errors.Add("holdout sem LF final") }
    if ($text.Contains("`r")) { $errors.Add("holdout com CR") }
    foreach ($b in $bytes) {
        if ($b -eq 0x0D) { $errors.Add("holdout com CR"); break }
        if ($b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) { $errors.Add(("holdout com byte nao ASCII 0x{0:X2}" -f $b)); break }
    }
    if ($lines.Count -gt 0 -and $lines[0] -cne "EVAL-V1") { $errors.Add("cabecalho do holdout invalido") }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -cne "END") { $errors.Add("rodape do holdout invalido") }

    # Estrutura e contagens.
    if ($d.TrainEnt.Length -ne 30 -or $d.TrainAlv.Length -ne 10) { $errors.Add("TRAIN com dimensoes invalidas") }
    if ($d.AEnt.Length -ne 30 -or $d.AAlv.Length -ne 10) { $errors.Add("A com dimensoes invalidas") }
    if ($d.BSeq.Length -ne 35) { $errors.Add("B com dimensoes invalidas") }
    if ($d.CSeq.Length -ne 56) { $errors.Add("C com dimensoes invalidas") }
    if ($d.DEnt.Length -ne 30 -or $d.DAlv.Length -ne 10 -or $d.DOrig.Length -ne 10) {
        $errors.Add("D com dimensoes invalidas")
    }

    $b = Get-EvalSequenceSet -Seq $d.BSeq -Count 5 -Modo 1
    $c = Get-EvalSequenceSet -Seq $d.CSeq -Count 8 -Modo 0
    if ($b.N -ne 20) { $errors.Add("B com $($b.N) predicoes; esperado 20") }
    if ($c.N -ne 32) { $errors.Add("C com $($c.N) predicoes; esperado 32") }

    # A e B_VISTO sao o mesmo conjunto de pares.
    $aPairs = @{}
    for ($i = 0; $i -lt 10; $i++) { $aPairs[(Get-EvalPairKey $d.AEnt $d.AAlv $i)] = $true }
    $bSeenPairs = @{}
    $bSeen = 0
    $bUnseen = 0
    for ($i = 0; $i -lt $b.N; $i++) {
        if ($b.Tipo[$i] -eq 1) {
            $bSeenPairs[(Get-EvalPairKey $b.Ent $b.Alv $i)] = $true
            $bSeen++
        } else {
            $bUnseen++
        }
    }
    if ($bSeen -ne 10) { $errors.Add("B_VISTO com $bSeen predicoes; esperado 10") }
    if ($bUnseen -ne 10) { $errors.Add("B_INEDITO com $bUnseen predicoes; esperado 10") }
    if ($aPairs.Count -ne 10 -or $bSeenPairs.Count -ne 10) {
        $errors.Add("A/B_VISTO com cardinalidade invalida")
    } else {
        foreach ($k in $aPairs.Keys) {
            if (-not $bSeenPairs.ContainsKey($k)) { $errors.Add("A e B_VISTO divergem em $k") }
        }
        foreach ($k in $bSeenPairs.Keys) {
            if (-not $aPairs.ContainsKey($k)) { $errors.Add("B_VISTO e A divergem em $k") }
        }
    }

    # Vazamento por contexto e por par.
    $trainCtx = Get-EvalTrainContextSet $d.TrainEnt
    $trainPairs = @{}
    for ($i = 0; $i -lt 10; $i++) { $trainPairs[(Get-EvalPairKey $d.TrainEnt $d.TrainAlv $i)] = $true }

    $cCtx = @{}
    $cLeaks = 0
    $cPairLeaks = 0
    for ($i = 0; $i -lt $c.N; $i++) {
        $k = Get-EvalContextKey $c.Ent $i
        if ($trainCtx.ContainsKey($k)) { $cLeaks++ }
        if ($cCtx.ContainsKey($k)) { $errors.Add("contexto de C duplicado: $k") }
        $cCtx[$k] = $true
        if ($trainPairs.ContainsKey((Get-EvalPairKey $c.Ent $c.Alv $i))) { $cPairLeaks++ }
    }
    if ($cCtx.Count -ne 32) { $errors.Add("C com $($cCtx.Count) contextos distintos; esperado 32") }
    if ($cLeaks -ne 0) { $errors.Add("C com $cLeaks contextos vistos") }
    if ($cPairLeaks -ne 0) { $errors.Add("C com $cPairLeaks pares vistos") }

    $bCtxLeaks = 0
    $bPairLeaks = 0
    for ($i = 0; $i -lt $b.N; $i++) {
        if ($b.Tipo[$i] -eq 0) {
            if ($trainCtx.ContainsKey((Get-EvalContextKey $b.Ent $i))) { $bCtxLeaks++ }
        } else {
            if (-not $trainPairs.ContainsKey((Get-EvalPairKey $b.Ent $b.Alv $i))) {
                $errors.Add("par de B_VISTO ausente do treino: $(Get-EvalPairKey $b.Ent $b.Alv $i)")
            }
        }
    }
    if ($bCtxLeaks -ne 0) { $errors.Add("B_INEDITO com $bCtxLeaks contextos vistos") }
    if ($bPairLeaks -ne 0) { $errors.Add("B com $bPairLeaks pares vistos inesperados") }

    # Sufixos de 2 tokens: C nao pode compartilhar com o treino.
    $trainSuffix = @{}
    for ($i = 0; $i -lt 10; $i++) {
        $trainSuffix["$($d.TrainEnt[$i * 3 + 1]),$($d.TrainEnt[$i * 3 + 2])"] = $true
    }
    $suffixLeaks = 0
    for ($i = 0; $i -lt $c.N; $i++) {
        $key = "$($c.Ent[$i * 3 + 1]),$($c.Ent[$i * 3 + 2])"
        if ($trainSuffix.ContainsKey($key)) { $suffixLeaks++ }
    }
    if ($suffixLeaks -ne 0) { $errors.Add("C com $suffixLeaks sufixos de 2 tokens vistos") }

    # D: contextos vistos, pares ausentes, alvo transformado.
    $dCtxSeen = 0
    $dPairAbsent = 0
    $dTargetOk = 0
    for ($i = 0; $i -lt 10; $i++) {
        $ctx = Get-EvalContextKey $d.DEnt $i
        if ($trainCtx.ContainsKey($ctx)) { $dCtxSeen++ }
        if (-not $trainPairs.ContainsKey((Get-EvalPairKey $d.DEnt $d.DAlv $i))) { $dPairAbsent++ }
        $esperado = ($d.DOrig[$i] % 24) + 1
        if ($d.DAlv[$i] -eq $esperado -and $d.DAlv[$i] -ne $d.DOrig[$i] -and
            $d.DAlv[$i] -ge 1 -and $d.DAlv[$i] -le 24) { $dTargetOk++ }
    }
    if ($dCtxSeen -ne 10) { $errors.Add("D com $dCtxSeen contextos vistos; esperado 10") }
    if ($dPairAbsent -ne 10) { $errors.Add("D com $dPairAbsent pares ausentes; esperado 10") }
    if ($dTargetOk -ne 10) { $errors.Add("D com $dTargetOk alvos transformados validos; esperado 10") }

    # IDs: 1..24, nenhum 0.
    $allEnt = @($d.TrainEnt) + @($d.AEnt) + @($b.Ent) + @($c.Ent) + @($d.DEnt)
    $allAlv = @($d.TrainAlv) + @($d.AAlv) + @($b.Alv) + @($c.Alv) + @($d.DAlv)
    foreach ($id in $allEnt) {
        if ($id -lt 1 -or $id -gt 24) { $errors.Add("ID fora de 1..24 nas entradas: $id"); break }
    }
    foreach ($id in $allAlv) {
        if ($id -lt 1 -or $id -gt 24) { $errors.Add("ID fora de 1..24 nos alvos: $id"); break }
    }

    # L7: nenhuma sequencia completa de B/C e uma linha do corpus e nenhuma
    # janela de 5 tokens de C coincide com uma linha do corpus. B contem
    # janelas vistas por desenho (as duas ultimas predicoes de cada sequencia).
    $corpusIds = @(
        @(1, 3, 17, 22, 24), @(2, 3, 17, 23, 24), @(9, 22, 12, 17, 24),
        @(9, 23, 10, 18, 24), @(11, 22, 12, 18, 24)
    )
    foreach ($seq in @($d.BSeq, $d.CSeq)) {
        for ($s = 0; $s -lt ($seq.Length / 7); $s++) {
            $full = @()
            for ($k = 0; $k -lt 7; $k++) { $full += $seq[$s * 7 + $k] }
            foreach ($row in $corpusIds) {
                if (($full -join ",") -ceq ($row -join ",")) {
                    $errors.Add("sequencia completa de B/C e linha do corpus: $($full -join ' ')")
                }
            }
        }
    }
    for ($s = 0; $s -lt 8; $s++) {
        for ($j = 0; $j -le 2; $j++) {
            $window = @($d.CSeq[$s * 7 + $j], $d.CSeq[$s * 7 + $j + 1], $d.CSeq[$s * 7 + $j + 2],
                        $d.CSeq[$s * 7 + $j + 3], $d.CSeq[$s * 7 + $j + 4])
            foreach ($row in $corpusIds) {
                if (($window -join ",") -ceq ($row -join ",")) {
                    $errors.Add("C contem janela de linha do corpus: $($window -join ' ')")
                }
            }
        }
    }

    # Alvos 24 e baselines discretos.
    $a24 = 0; for ($i = 0; $i -lt 10; $i++) { if ($d.AAlv[$i] -eq 24) { $a24++ } }
    $b24 = 0; for ($i = 0; $i -lt $b.N; $i++) { if ($b.Alv[$i] -eq 24) { $b24++ } }
    $c24 = 0; for ($i = 0; $i -lt $c.N; $i++) { if ($c.Alv[$i] -eq 24) { $c24++ } }
    $d24 = 0; for ($i = 0; $i -lt 10; $i++) { if ($d.DAlv[$i] -eq 24) { $d24++ } }
    if ($a24 -ne 5) { $errors.Add("A com $a24 alvos 24; esperado 5") }
    if ($b24 -ne 5) { $errors.Add("B com $b24 alvos 24; esperado 5") }
    if ($c24 -ne 8) { $errors.Add("C com $c24 alvos 24; esperado 8") }
    if ($d24 -ne 1) { $errors.Add("D com $d24 alvos 24; esperado 1") }

    $memA = 0; for ($i = 0; $i -lt 10; $i++) { if ($d.AAlv[$i] -eq $d.TrainAlv[$i]) { $memA++ } }
    $memBSeen = 0
    $memBUnseen = 0
    for ($i = 0; $i -lt $b.N; $i++) {
        if ($b.Tipo[$i] -eq 1) {
            if ($trainPairs.ContainsKey((Get-EvalPairKey $b.Ent $b.Alv $i))) { $memBSeen++ }
        } else {
            if ($b.Alv[$i] -eq 24) { $memBUnseen++ }
        }
    }
    # Memorizacao em B: 10 pares vistos + 0 ineditos (nenhum alvo inedito e 24).
    $memB = $memBSeen + $memBUnseen
    # Memorizacao em C: todo contexto e inedito -> prediz 24.
    $memC = $c24
    $memD = 0
    for ($i = 0; $i -lt 10; $i++) { if ($d.DAlv[$i] -eq $d.DOrig[$i]) { $memD++ } }
    if ($memA -ne 10) { $errors.Add("memorizacao em A: $memA; esperado 10") }
    if ($memBUnseen -ne 0) { $errors.Add("memorizacao em B_INEDITO: $memBUnseen; esperado 0") }
    if ($memB -ne 10) { $errors.Add("memorizacao em B: $memB; esperado 10") }
    if ($memC -ne 8) { $errors.Add("memorizacao em C: $memC; esperado 8") }
    if ($memD -ne 0) { $errors.Add("memorizacao em D: $memD; esperado 0") }

    return [pscustomobject]@{
        Errors = $errors
        Text = $text
        Bytes = $bytes.Length
        Lines = $lines.Count
        Sha256 = $sha
        A = 10
        BSeen = $bSeen
        BUnseen = $bUnseen
        C = $c.N
        CSemPare = $c.N - $c24
        D = 10
        CLeaks = $cLeaks
        SuffixLeaks = $suffixLeaks
        A24 = $a24
        B24 = $b24
        C24 = $c24
        D24 = $d24
        MemA = $memA
        MemB = $memB
        MemC = $memC
        MemD = $memD
    }
}

function Invoke-EvalDatasetCheck {
    param([string]$Path = "")
    $r = Assert-EvalDataset
    $lines = New-Object System.Collections.Generic.List[string]
    if ($r.Errors.Count -eq 0) {
        $lines.Add("SEPARACAO=OK")
    } else {
        $lines.Add("SEPARACAO=FALHA")
        foreach ($e in $r.Errors) { $lines.Add("ERRO=$e") }
    }
    $lines.Add("HOLDOUT_BYTES=$($r.Bytes)")
    $lines.Add("HOLDOUT_LINHAS=$($r.Lines)")
    $lines.Add("HOLDOUT_SHA256=$($r.Sha256)")
    $lines.Add("A=$($r.A) B_VISTO=$($r.BSeen) B_INEDITO=$($r.BUnseen) C=$($r.C) C_SEM_PARE=$($r.CSemPare) D=$($r.D)")
    $lines.Add("VAZAMENTOS_CONTEXTO=$($r.CLeaks)")
    $lines.Add("VAZAMENTOS_SUFIXO2=$($r.SuffixLeaks)")
    $lines.Add("ALVOS24 A=$($r.A24) B=$($r.B24) C=$($r.C24) D=$($r.D24)")
    $lines.Add("MEMORIZACAO A=$($r.MemA) B=$($r.MemB) C=$($r.MemC) D=$($r.MemD)")
    $text = ($lines -join "`n") + "`n"

    if ($Path -ne "") {
        [IO.File]::WriteAllText($Path, $text, (New-Object System.Text.ASCIIEncoding))
    } else {
        [Console]::Out.Write($text)
    }
    if ($r.Errors.Count -ne 0) { exit 1 }
}

if ($Check -or (-not $Quiet)) {
    Invoke-EvalDatasetCheck -Path $OutputPath
}
