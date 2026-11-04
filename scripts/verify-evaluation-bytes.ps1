# ---------------------------------------------------------------------------
# Verificacao independente da avaliacao de generalizacao (M9).
# - V1  hashes M1-M8, test.ps1 intacto, escopo do git status, modulo somente leitura
# - V2  serializacao do holdout (724 bytes, 50 linhas, SHA-256)
# - V3  contagens e composicao de A/B/C/D
# - V4  vazamentos, B 10+10, C 32/32, D 10/10
# - V5  IDs 1..24, nenhum 0, nenhuma sequencia do corpus
# - V6  estado canonico reproduzido por O1 e hash congelado
# - V7  metricas do nao treinado iguais a O1/O2
# - V8  metricas do canonico iguais a O1/O2, margens e confusao, O3
# - V9  baselines exatos
# - V10 nao mutacao (estado completo antes/depois)
# - V11 determinismo A/B, gramatica, ASCII/LF
# - V12 suite 116/116 e autoteste 0/1
# - V13 casos extremos e codigos de erro
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-evaluation-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/evaluation-tests",
    [string]$SourcePath = "src/avaliacao.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat",
    [string]$RunnerPath = "scripts/test-evaluation.ps1",
    [string]$SuitesPath = "scripts/test.ps1",
    [string]$LogPath = "temp/eval-verify.log",
    [switch]$SkipSuite
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

. (Join-Path $root "scripts/eval-datasets.ps1") -Quiet
. (Join-Path $root "scripts/eval-oracle.ps1") -Quiet

$script:CheckErrors = New-Object System.Collections.Generic.List[string]
$script:CheckCount = 0
$script:FailedChecks = 0
$script:LogLines = New-Object System.Collections.Generic.List[string]

function Write-Check {
    param([string]$Name, [string[]]$Errors)
    $script:CheckCount++
    $list = @($Errors)
    if ($list.Count -eq 0) {
        Write-Host ("V{0} {1} OK" -f $script:CheckCount, $Name)
        $script:LogLines.Add(("V{0} {1} OK" -f $script:CheckCount, $Name))
    } else {
        $script:FailedChecks++
        Write-Host ("V{0} {1} FALHA ({2})" -f $script:CheckCount, $Name, $list.Count)
        $script:LogLines.Add(("V{0} {1} FALHA ({2})" -f $script:CheckCount, $Name, $list.Count))
        foreach ($e in $list) {
            Write-Host ("  - {0}" -f $e)
            $script:LogLines.Add(("  - {0}" -f $e))
        }
    }
}

function Get-EvalSha256Text([string]$Text) {
    $bytes = [Text.Encoding]::ASCII.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally { $sha.Dispose() }
}

function Get-EvalFileSha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead((Join-Path $root $Path))
        try {
            return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "")
        } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

function Get-EvalGitBlob([string]$Path) {
    return ((& git -C $root hash-object -- $Path 2>$null) -join "").Trim()
}

$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"
$script:CaseCache = @{}

function Invoke-EvalCase {
    param([string]$Name)
    if ($script:CaseCache.ContainsKey($Name)) { return $script:CaseCache[$Name] }
    $porPath = Join-Path $root (Join-Path $GeneratedRoot "$Name.por")
    if (-not (Test-Path -LiteralPath $porPath)) {
        throw "Caso ausente: $porPath"
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $InterpreterPath
    $psi.Arguments = '"' + $porPath + '"'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.WriteLine(' ')
    $proc.StandardInput.Close()
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $text = $out
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0x0C) { $text = $text.Substring(1) }
    if ($text.EndsWith($epilogue)) { $text = $text.Substring(0, $text.Length - $epilogue.Length) }
    $result = [pscustomobject]@{
        Name = $Name
        Text = $text
        Lines = @($text.TrimEnd("`n").Split("`n"))
        Error = $err
        Bytes = [Text.Encoding]::ASCII.GetBytes($text)
    }
    $script:CaseCache[$Name] = $result
    return $result
}

function Get-EvalExpectedText([string]$Name) {
    $expected = Get-EvalExpected $Name
    return (($expected -join "`n") + "`n")
}

function Compare-EvalCaseLines {
    param([string]$Name, [string[]]$ExpectedLines)
    $actual = Invoke-EvalCase $Name
    $errors = New-Object System.Collections.Generic.List[string]
    if ($actual.Error.Length -gt 0) { $errors.Add("stderr: $($actual.Error.Trim())") }
    if ($actual.Lines.Count -ne $ExpectedLines.Count) {
        $errors.Add("linhas: $($actual.Lines.Count); esperado $($ExpectedLines.Count)")
    }
    $n = [Math]::Min($actual.Lines.Count, $ExpectedLines.Count)
    for ($i = 0; $i -lt $n; $i++) {
        if ($actual.Lines[$i] -cne $ExpectedLines[$i]) {
            $errors.Add("linha $($i + 1): '$($actual.Lines[$i])'; esperado '$($ExpectedLines[$i])'")
            if ($errors.Count -ge 12) { break }
        }
    }
    return [pscustomobject]@{ Errors = $errors; Actual = $actual }
}

function Get-EvalSummaryLine {
    param([string[]]$Lines, [string]$Estado, [string]$Conjunto)
    $prefix = "RESUMO $Estado $Conjunto "
    foreach ($line in $Lines) {
        if ($line.StartsWith($prefix, [StringComparison]::Ordinal)) {
            $parts = $line.Split(' ')
            return [pscustomobject]@{
                N = [int]$parts[3]
                Acertos = [int]$parts[4]
                Bp = [int]$parts[5]
                Milesimos = [int]$parts[6]
            }
        }
    }
    return $null
}

function Get-EvalBatchList {
    param([string[]]$Lines, [string]$Estado, [string]$Conjunto)
    $prefix = "PERDA $Estado $Conjunto "
    $batches = @()
    foreach ($line in $Lines) {
        if ($line.StartsWith($prefix, [StringComparison]::Ordinal)) {
            $parts = $line.Split(' ')
            $batches += [pscustomobject]@{ N = [int]$parts[4]; S = [long]$parts[5] }
        }
    }
    return $batches
}

function Get-EvalStateBlock {
    param([string[]]$Lines, [string]$PrefixW, [string]$PrefixB)
    $block = New-Object System.Collections.Generic.List[string]
    for ($y = 0; $y -lt 25; $y++) {
        $p = "$PrefixW $y "
        $found = $false
        foreach ($line in $Lines) {
            if ($line.StartsWith($p, [StringComparison]::Ordinal)) { $block.Add($line); $found = $true; break }
        }
        if (-not $found) { return $null }
    }
    foreach ($line in $Lines) {
        if ($line.StartsWith("$PrefixB ", [StringComparison]::Ordinal)) { $block.Add($line); return $block }
    }
    return $null
}

# --- V1 ---------------------------------------------------------------------

$v1 = New-Object System.Collections.Generic.List[string]
$frozen = [ordered]@{
    "src/tokenizador.por"                 = "6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f"
    "src/embeddings.por"                  = "6f06aa820d163d3c1636383803b86105bf54cd85"
    "src/rede.por"                        = "fa9367a79bd2aefc373d30a94cfca2b7c86d9958"
    "src/treino.por"                      = "f5121423dd0aac6469b59b24b13d8a85b2c0d64d"
    "src/gerador.por"                     = "532e60cc52cef03fbd60c2a9d2b530472c73ded1"
    "src/contexto.por"                    = "9da552861c58d145a1d1c52442e0c27a4c42ce2e"
    "scripts/build-tests.ps1"             = "1cfb01202586a83c4d7ec08ff738a8e90fb19044"
    "scripts/verify-bytes.ps1"            = "851afbbad494778f019bf2ce70e82b0b575ab443"
    "scripts/build-embedding-tests.ps1"   = "94d1a3819b76b4d614f4422bf00b0cd2c008daaf"
    "scripts/verify-embedding-bytes.ps1"  = "4f3aa68e499a9dc3289d22ebae5b8d1c18086651"
    "scripts/build-network-tests.ps1"     = "998e91b2896e9ec40bc1814990a0a53ae740fb3e"
    "scripts/verify-network-bytes.ps1"    = "1f46800852fed34d840206ca97bc84badd109b31"
    "scripts/build-training-tests.ps1"    = "c587e161e19d353af23f0cb9d055119b288c2675"
    "scripts/verify-training-bytes.ps1"   = "f59fee82d337e13f619360e63d6e928aef8e0f6b"
    "scripts/build-generation-tests.ps1"  = "e712064d631e6fbf2711943ec65da6812223427f"
    "scripts/verify-generation-bytes.ps1" = "e1807a8d6469ecaba0d2ad724c9e58b6a2689b3a"
    "scripts/build-context-tests.ps1"     = "e9dd6d1ba2b54eb4caade4391a3da12cb555f29d"
    "scripts/verify-context-bytes.ps1"    = "e6d902c7ec374a97e87844df933ba728ae220216"
}
foreach ($path in $frozen.Keys) {
    $actual = Get-EvalGitBlob $path
    if ($actual -cne $frozen[$path]) { $v1.Add("${path}: $actual; esperado $($frozen[$path])") }
}
$m8SpecHash = Get-EvalFileSha256 "corpus/m8-corpus-v1.txt"
if ($m8SpecHash -cne "d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113") {
    $v1.Add("corpus/m8-corpus-v1.txt: $m8SpecHash")
}

$testPath = Join-Path $root "scripts/test.ps1"
$testBytes = [IO.File]::ReadAllBytes($testPath)
if ($testBytes.Length -lt 4 -or $testBytes[0] -ne 0xEF -or $testBytes[1] -ne 0xBB -or $testBytes[2] -ne 0xBF) {
    $v1.Add("test.ps1 sem BOM UTF-8")
}
foreach ($b in $testBytes) { if ($b -eq 0x0D) { $v1.Add("test.ps1 com CR"); break } }
if ($testBytes[$testBytes.Length - 1] -ne 0x7D) { $v1.Add("test.ps1 nao termina em }") }
$testText = [Text.Encoding]::UTF8.GetString($testBytes, 3, $testBytes.Length - 3)
$testLines = @($testText -split "`n")
$lineCount = if ($testLines[$testLines.Count - 1] -eq "") { $testLines.Count - 1 } else { $testLines.Count }
if ($lineCount -ne 402) { $v1.Add("test.ps1 com $lineCount linhas; esperado 402") }
if ($testText -notmatch 'Passed:\s+\$passed') { $v1.Add("test.ps1 sem resumo Passed") }

# Escopo do git status.
$allowed = @(
    "src/avaliacao.por",
    "scripts/eval-datasets.ps1",
    "scripts/eval-oracle.ps1",
    "scripts/build-evaluation-tests.ps1",
    "scripts/test-evaluation.ps1",
    "scripts/verify-evaluation-bytes.ps1",
    "docs/evaluation-spec.md",
    "docs/evaluation-plan.md",
    "scripts/verify-context-bytes.ps1",
    "scripts/verify-corpus-bytes.ps1",
    "src/atencao.por",
    "scripts/attention-oracle.ps1",
    "scripts/build-attention-tests.ps1",
    "scripts/test-attention.ps1",
    "scripts/verify-attention-bytes.ps1",
    "docs/attention-spec.md",
    "docs/attention-plan.md"
)
$statusLines = @(& git -C $root status --porcelain 2>$null)
foreach ($line in $statusLines) {
    if ($line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -like "* -> *") { $path = $path.Split(" -> ")[1] }
    if ($allowed -notcontains $path) { $v1.Add("git status fora do escopo: $line") }
}
Write-Check "hashes M1-M8, test.ps1 intacto e escopo" $v1.ToArray()

# --- V2-V5 ------------------------------------------------------------------

$sep = Assert-EvalDataset
$v2 = @()
if ($sep.Bytes -ne 724) { $v2 += "bytes=$($sep.Bytes)" }
if ($sep.Lines -ne 50) { $v2 += "linhas=$($sep.Lines)" }
if ($sep.Sha256 -cne "e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10") {
    $v2 += "sha=$($sep.Sha256)"
}
if ($sep.Errors.Count -ne 0) { $v2 += $sep.Errors }
Write-Check "holdout 724 bytes / 50 linhas / SHA-256" $v2

$v3 = @()
if ($sep.A -ne 10) { $v3 += "A=$($sep.A)" }
if ($sep.BSeen -ne 10 -or $sep.BUnseen -ne 10) { $v3 += "B=$($sep.BSeen)+$($sep.BUnseen)" }
if ($sep.C -ne 32) { $v3 += "C=$($sep.C)" }
if ($sep.CSemPare -ne 24) { $v3 += "C_SEM_PARE=$($sep.CSemPare)" }
if ($sep.D -ne 10) { $v3 += "D=$($sep.D)" }
if ($sep.A24 -ne 5 -or $sep.B24 -ne 5 -or $sep.C24 -ne 8 -or $sep.D24 -ne 1) {
    $v3 += "alvos24 A=$($sep.A24) B=$($sep.B24) C=$($sep.C24) D=$($sep.D24)"
}
Write-Check "contagens e composicao de A/B/C/D" $v3

$v4 = @()
if ($sep.CLeaks -ne 0) { $v4 += "vazamentos_contexto=$($sep.CLeaks)" }
if ($sep.SuffixLeaks -ne 0) { $v4 += "vazamentos_sufixo2=$($sep.SuffixLeaks)" }
if ($sep.MemA -ne 10 -or $sep.MemC -ne 8 -or $sep.MemD -ne 0) {
    $v4 += "memorizacao A=$($sep.MemA) C=$($sep.MemC) D=$($sep.MemD)"
}
Write-Check "0 vazamentos, B 10+10, C 32/32, D 10/10" $v4

$v5 = @()
$d = Get-EvalDataset
$bSet = Get-EvalSequenceSet -Seq $d.BSeq -Count 5 -Modo 1
$cSet = Get-EvalSequenceSet -Seq $d.CSeq -Count 8 -Modo 0
foreach ($id in (@($d.TrainEnt) + @($d.AEnt) + @($bSet.Ent) + @($cSet.Ent) + @($d.DEnt))) {
    if ($id -lt 1 -or $id -gt 24) { $v5 += "entrada fora de 1..24: $id"; break }
}
foreach ($id in (@($d.TrainAlv) + @($d.AAlv) + @($bSet.Alv) + @($cSet.Alv) + @($d.DAlv))) {
    if ($id -lt 1 -or $id -gt 24) { $v5 += "alvo fora de 1..24: $id"; break }
}
$corpusRows = @(
    @(1, 3, 17, 22, 24), @(2, 3, 17, 23, 24), @(9, 22, 12, 17, 24),
    @(9, 23, 10, 18, 24), @(11, 22, 12, 18, 24)
)
foreach ($seq in @($d.BSeq, $d.CSeq)) {
    for ($s = 0; $s -lt ($seq.Length / 7); $s++) {
        $full = @()
        for ($j = 0; $j -lt 7; $j++) { $full += $seq[$s * 7 + $j] }
        foreach ($row in $corpusRows) {
            if (($full -join ",") -ceq ($row -join ",")) {
                $v5 += "sequencia de corpus em B/C: $($full -join ' ')"
            }
        }
    }
}
Write-Check "IDs 1..24, sem 0 e sem sequencia do corpus" $v5

# --- V6 ---------------------------------------------------------------------

$v6 = @()
$canonicalExpected = Get-EvalExpected "eval_treinado"
$canonicalText = (($canonicalExpected -join "`n") + "`n")
$canonicalReal = Invoke-EvalCase "eval_treinado"
$stateBlock = Get-EvalStateBlock $canonicalExpected "W16" "B16"
if ($null -eq $stateBlock) {
    $v6 += "bloco W16/B16 ausente no O1"
} else {
    $stateText = (($stateBlock -join "`n") + "`n")
    $stateHash = Get-EvalSha256Text $stateText
    if ($stateHash -cne "efa3f1d397a7fa37aaa83fb1c664fc054f1844309a5a7220f4ef7c3de630bb6d") {
        $v6 += "hash do estado: $stateHash"
    }
    $realBlock = Get-EvalStateBlock $canonicalReal.Lines "W16" "B16"
    if ($null -eq $realBlock) {
        $v6 += "bloco W16/B16 ausente na saida real"
    } elseif (($realBlock -join "`n") -cne ($stateBlock -join "`n")) {
        $v6 += "estado real difere do O1"
    }
}
if ($canonicalText -notmatch 'RESUMO CANONICO A 10 10 10000 332') {
    $v6 += "A canonico nao e 10/10"
}
Write-Check "estado canonico reproduzido por O1 e hash congelado" $v6

# --- V7 ---------------------------------------------------------------------

$nonTrainedExpected = Get-EvalExpected "eval_nao_treinado"
$v7 = New-Object System.Collections.Generic.List[string]
$cmp7 = Compare-EvalCaseLines "eval_nao_treinado" $nonTrainedExpected
foreach ($e in $cmp7.Errors) { $v7.Add($e) }
$real7 = $cmp7.Actual.Lines
foreach ($conj in @("A", "B", "C", "D")) {
    $sum = Get-EvalSummaryLine $real7 "NAO_TREINADO" $conj
    if ($null -eq $sum) { $v7.Add("RESUMO NAO_TREINADO $conj ausente"); continue }
    $batches = Get-EvalBatchList $real7 "NAO_TREINADO" $conj
    if ($batches.Count -eq 0) { $v7.Add("PERDA NAO_TREINADO $conj ausente"); continue }
    $o2 = Assert-EvalO2 $batches $sum.N $sum.Milesimos
    foreach ($e in $o2.Errors) { $v7.Add("$conj $e") }
}
Write-Check "metricas do nao treinado iguais a O1/O2" $v7.ToArray()

# --- V8 ---------------------------------------------------------------------

$v8 = New-Object System.Collections.Generic.List[string]
$cmp8 = Compare-EvalCaseLines "eval_treinado" $canonicalExpected
foreach ($e in $cmp8.Errors) { $v8.Add($e) }
$real8 = $cmp8.Actual.Lines
foreach ($conj in @("A", "B", "C", "D")) {
    $sum = Get-EvalSummaryLine $real8 "CANONICO" $conj
    if ($null -eq $sum) { $v8.Add("RESUMO CANONICO $conj ausente"); continue }
    $batches = Get-EvalBatchList $real8 "CANONICO" $conj
    if ($batches.Count -eq 0) { $v8.Add("PERDA CANONICO $conj ausente"); continue }
    $o2 = Assert-EvalO2 $batches $sum.N $sum.Milesimos
    foreach ($e in $o2.Errors) { $v8.Add("$conj $e") }
}
$cSum = Get-EvalSummaryLine $real8 "CANONICO" "C"
if ($null -eq $cSum) {
    $v8.Add("RESUMO CANONICO C ausente")
} else {
    if ($cSum.N -ne 32 -or $cSum.Acertos -ne 4 -or $cSum.Bp -ne 1250) {
        $v8.Add("C: N=$($cSum.N) acertos=$($cSum.Acertos) BP=$($cSum.Bp); esperado 32/4/1250")
    }
}
$cSem = Get-EvalSummaryLine $real8 "CANONICO" "C_SEM_PARE"
if ($null -eq $cSem -or $cSem.N -ne 24) { $v8.Add("C_SEM_PARE invalido") }
# O3: literais congelados (transcritos da execucao real e conferidos contra O1/O2).
$o3 = @(
    @{ Conj = "A"; Index = 1; Pos = 0; A = 1; B = 3; C = 17; T = 22; P = 22; Ok = 1; ZP = 114; ZT = 114; MZ = 0 },
    @{ Conj = "A"; Index = 2; Pos = 0; A = 3; B = 17; C = 22; T = 24; P = 24; Ok = 1; ZP = 401; ZT = 401; MZ = 0 },
    @{ Conj = "C"; Index = 1; Pos = 0; A = 4; B = 7; C = 5; T = 13; P = 24; Ok = 0; ZP = 157; ZT = 76; MZ = 81 },
    @{ Conj = "C"; Index = 1; Pos = 1; A = 7; B = 5; C = 13; T = 6; P = 24; Ok = 0; ZP = 263; ZT = 77; MZ = 186 }
)
foreach ($lit in $o3) {
    $prefix = "EX CANONICO $($lit.Conj) $($lit.Index) $($lit.Pos) "
    $found = $null
    foreach ($line in $real8) {
        if ($line.StartsWith($prefix, [StringComparison]::Ordinal)) { $found = $line; break }
    }
    if ($null -eq $found) {
        $v8.Add("O3: EX ausente $($lit.Conj) $($lit.Index) $($lit.Pos)")
        continue
    }
    $parts = $found.Split(' ')
    # EX estado conjunto indice pos a b c alvo pred ok ZP ZT MZ alvo_treino tipo palavra_alvo palavra_pred
    if ([int]$parts[5] -ne $lit.A -or [int]$parts[6] -ne $lit.B -or [int]$parts[7] -ne $lit.C -or
        [int]$parts[8] -ne $lit.T -or [int]$parts[9] -ne $lit.P -or [int]$parts[10] -ne $lit.Ok -or
        [int]$parts[11] -ne $lit.ZP -or [int]$parts[12] -ne $lit.ZT -or [int]$parts[13] -ne $lit.MZ) {
        $v8.Add("O3: $($lit.Conj)#$($lit.Index)/$($lit.Pos) difere: $found")
    }
}
# Soma dos ok das linhas EX igual ao acerto reportado (A, B, C, D).
foreach ($conj in @("A", "B", "C", "D")) {
    $sum = Get-EvalSummaryLine $real8 "CANONICO" $conj
    if ($null -eq $sum) { continue }
    $oks = 0
    foreach ($line in $real8) {
        if ($line.StartsWith("EX CANONICO $conj ", [StringComparison]::Ordinal)) {
            $parts = $line.Split(' ')
            if ([int]$parts[10] -eq 1) { $oks++ }
        }
    }
    if ($oks -ne $sum.Acertos) { $v8.Add("EX ok de $conj = $oks; RESUMO = $($sum.Acertos)") }
}
# L8: A e B_VISTO com predicoes identicas por par.
$mapA = @{}
foreach ($line in $real8) {
    if ($line.StartsWith("EX CANONICO A ", [StringComparison]::Ordinal)) {
        $parts = $line.Split(' ')
        $mapA["$($parts[5]),$($parts[6]),$($parts[7])"] = [int]$parts[9]
    }
}
$mapBSeen = @{}
$bSeenCount = 0
foreach ($line in $real8) {
    if ($line.StartsWith("EX CANONICO B ", [StringComparison]::Ordinal)) {
        $parts = $line.Split(' ')
        if ($parts[15] -ceq "VISTO") {
            $mapBSeen["$($parts[5]),$($parts[6]),$($parts[7])"] = [int]$parts[9]
            $bSeenCount++
        }
    }
}
if ($mapA.Count -ne 10) { $v8.Add("A com $($mapA.Count) pares; esperado 10") }
if ($bSeenCount -ne 10) { $v8.Add("B_VISTO com $bSeenCount linhas; esperado 10") }
foreach ($key in $mapA.Keys) {
    if (-not $mapBSeen.ContainsKey($key)) {
        $v8.Add("B_VISTO nao contem o par de A: $key")
    } elseif ($mapBSeen[$key] -ne $mapA[$key]) {
        $v8.Add("L8: par $key A=$($mapA[$key]) B=$($mapBSeen[$key])")
    }
}
Write-Check "metricas do canonico iguais a O1/O2, margens e O3" $v8.ToArray()

# --- V9 ---------------------------------------------------------------------

$baselineExpected = Get-EvalExpected "eval_baselines"
$v9 = New-Object System.Collections.Generic.List[string]
$cmp9 = Compare-EvalCaseLines "eval_baselines" $baselineExpected
foreach ($e in $cmp9.Errors) { $v9.Add($e) }
$real9 = $cmp9.Actual.Lines
$want = @{
    "MEMORIZACAO|A" = 10; "MEMORIZACAO|B" = 10; "MEMORIZACAO|C" = 8; "MEMORIZACAO|D" = 0;
    "MAJORITARIO|A" = 5; "MAJORITARIO|B" = 5; "MAJORITARIO|C" = 8; "MAJORITARIO|D" = 1
}
foreach ($key in $want.Keys) {
    $parts = $key.Split('|')
    $sum = Get-EvalSummaryLine $real9 $parts[0] $parts[1]
    if ($null -eq $sum) { $v9.Add("RESUMO $key ausente"); continue }
    if ($sum.Acertos -ne $want[$key]) {
        $v9.Add("$key acertos=$($sum.Acertos); esperado $($want[$key])")
    }
    if ($sum.Milesimos -ne -1) { $v9.Add("$key milesimos=$($sum.Milesimos); esperado -1") }
}
$bv = Get-EvalSummaryLine $real9 "MEMORIZACAO" "B_VISTO"
$bi = Get-EvalSummaryLine $real9 "MEMORIZACAO" "B_INEDITO"
if ($null -eq $bv -or $bv.Acertos -ne 10) { $v9.Add("MEMORIZACAO B_VISTO invalido") }
if ($null -eq $bi -or $bi.Acertos -ne 0) { $v9.Add("MEMORIZACAO B_INEDITO invalido") }
Write-Check "baselines exatos" $v9.ToArray()

# --- V10 --------------------------------------------------------------------

$v10 = New-Object System.Collections.Generic.List[string]
$parameterized = @(
    "eval_nao_treinado", "eval_treinado", "eval_controle_rotulo",
    "eval_controle_ordem", "eval_ordem_permutacoes"
)
foreach ($name in $parameterized) {
    $evalCase = Invoke-EvalCase $name
    $before = Get-EvalStateBlock $evalCase.Lines "W16" "B16"
    $after = Get-EvalStateBlock $evalCase.Lines "W16_FIM" "B16_FIM"
    if ($null -eq $before) { $v10.Add("${name}: bloco inicial ausente"); continue }
    if ($null -eq $after) { $v10.Add("${name}: bloco final ausente"); continue }
    $afterNorm = @($after | ForEach-Object {
        if ($_.StartsWith("W16_FIM ", [StringComparison]::Ordinal)) { "W16 " + $_.Substring(8) }
        elseif ($_.StartsWith("B16_FIM ", [StringComparison]::Ordinal)) { "B16 " + $_.Substring(8) }
        else { $_ }
    })
    if (($before -join "`n") -cne ($afterNorm -join "`n")) { $v10.Add("${name}: estado mudou") }
    if ($evalCase.Lines -notcontains "CHECK CANONICO MUTACAO OK" -and
        $evalCase.Lines -notcontains "CHECK NAO_TREINADO MUTACAO OK" -and
        $evalCase.Lines -notcontains "CHECK ROTULO_PERMUTADO MUTACAO OK" -and
        $evalCase.Lines -notcontains "CHECK ORDEM_INVERSA MUTACAO OK") {
        if ($name -ne "eval_ordem_permutacoes") { $v10.Add("${name}: CHECK MUTACAO OK ausente") }
    }
}
Write-Check "nao mutacao (estado completo antes/depois)" $v10.ToArray()

# --- V11 --------------------------------------------------------------------

$v11 = New-Object System.Collections.Generic.List[string]
$detA = Invoke-EvalCase "eval_determinismo_a"
$detB = Invoke-EvalCase "eval_determinismo_b"
if (($detA.Lines -join "`n") -cne ($detB.Lines -join "`n")) { $v11.Add("determinismo A/B diverge") }
if ($detA.Error.Length -gt 0 -or $detB.Error.Length -gt 0) { $v11.Add("stderr nao vazio") }
$grammar = @(
    '^AVAL V1$',
    '^ESTADO (NAO_TREINADO|CANONICO|ROTULO_PERMUTADO|ORDEM_INVERSA|MEMORIZACAO|MAJORITARIO)$',
    '^TREINO [0-9]+$',
    '^W16(_FIM)? [0-9]+( -?[0-9]+){12}$',
    '^B16(_FIM)?( -?[0-9]+){25}$',
    '^CHECK [A-Z_]+ MUTACAO (OK|FALHA|NA)$',
    '^CHECK [A-Z_]+ ACERTOS (OK|FALHA)$',
    '^RESUMO [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D) [0-9]+ [0-9]+ [0-9]+ -?[0-9]+$',
    '^PERDA [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D) [0-9]+ [0-9]+ [0-9]+$',
    '^EX [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D) [0-9]+ [0-9]+( -?[0-9]+){3}( -?[0-9]+){7} (VISTO|INEDITO|-)( [a-z]+){2}$',
    '^CONF [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D) [0-9]+ [0-9]+ [0-9]+$',
    '^DELTA_BP (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D) -?[0-9]+ -?[0-9]+ -?[0-9]+$',
    '^PERM( -?[0-9]+){12}$',
    '^PERM_RESUMO [0-9]+ [0-9]+ [0-9]+$',
    '^IDS [a-z=-]+[0-9]* [0-9]+$',
    '^DIV -?[0-9]+ -?[0-9]+ -?[0-9]+$',
    '^MILES [0-9]+ [0-9]+ -?[0-9]+$',
    '^CHECKSUM -?[0-9]+$',
    '^AVALIAR [a-z=0-9 -]+[0-9]+$',
    '^RELATORIO modo [0-9]+ -?[0-9]+$',
    '^COPIAR tam=[0-9]+ -?[0-9]+$',
    '^LIMITES$',
    '^FIM$'
)
$allCases = @(
    "eval_nao_treinado", "eval_treinado", "eval_baselines",
    "eval_controle_rotulo", "eval_controle_ordem", "eval_ordem_permutacoes",
    "eval_limites", "eval_determinismo_a", "eval_determinismo_b"
)
foreach ($name in $allCases) {
    $evalCase = Invoke-EvalCase $name
    foreach ($line in $evalCase.Lines) {
        $matched = $false
        foreach ($pattern in $grammar) {
            if ($line -match $pattern) { $matched = $true; break }
        }
        if (-not $matched) {
            $v11.Add("${name}: linha fora da gramatica: '$line'")
            break
        }
    }
    $bytes = $evalCase.Bytes
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 0x0A) { $v11.Add("${name}: sem LF final") }
    foreach ($bb in $bytes) {
        if ($bb -eq 0x0D) { $v11.Add("${name}: CR"); break }
        if ($bb -ne 0x0A -and ($bb -lt 0x20 -or $bb -gt 0x7E)) { $v11.Add("${name}: byte fora de ASCII/LF"); break }
    }
    if ($evalCase.Text -match 'NaN|Infinity|-0([^0-9]|$)|e\+') { $v11.Add("${name}: token proibido") }
}
Write-Check "determinismo A/B, gramatica e ASCII/LF" $v11.ToArray()

# --- V12 --------------------------------------------------------------------

$v12 = New-Object System.Collections.Generic.List[string]
if (-not $SkipSuite) {
    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = "powershell.exe" }
    $suiteOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $SuitesPath) 2>&1 | Out-String
    $suiteCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $root "temp/eval-verify-suite.log"), $suiteOut, (New-Object System.Text.UTF8Encoding($false)))
    if ($suiteCode -ne 0) { $v12.Add("suite saiu com $suiteCode") }
    if ($suiteOut -notmatch 'Passed:\s+116') { $v12.Add("suite nao reportou 116 PASS") }
    if ($suiteOut -notmatch 'Failed:\s+0') { $v12.Add("suite nao reportou 0 FAIL") }
    if ($suiteOut -notmatch 'Total:\s+116') { $v12.Add("suite nao reportou Total 116") }
    $selfOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $SuitesPath) -SelfTest 2>&1 | Out-String
    $selfCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $root "temp/eval-verify-selftest.log"), $selfOut, (New-Object System.Text.UTF8Encoding($false)))
    if ($selfCode -ne 1) { $v12.Add("autoteste saiu com $selfCode; esperado 1") }
    if ($selfOut -notmatch 'Passed:\s+0') { $v12.Add("autoteste nao reportou 0 PASS") }
    if ($selfOut -notmatch 'Failed:\s+1') { $v12.Add("autoteste nao reportou 1 FAIL") }
} else {
    $v12.Add("suite ignorada por -SkipSuite")
}
Write-Check "suite 116/116 e autoteste 0/1" $v12.ToArray()

# --- V13 --------------------------------------------------------------------

$limitsExpected = Get-EvalExpected "eval_limites"
$v13 = New-Object System.Collections.Generic.List[string]
$cmp13 = Compare-EvalCaseLines "eval_limites" $limitsExpected
foreach ($e in $cmp13.Errors) { $v13.Add($e) }
$limitsText = ($cmp13.Actual.Lines -join "`n")
foreach ($code in @(
    "IDS n=0 0", "IDS n=65 0", "IDS id=25 0", "IDS id=-1 0", "IDS validos 1",
    "DIV 5 0 -1", "DIV -1 3 -1",
    "MILES 321126400 1 2450", "MILES 1926758400 6 2450", "MILES 1 0 -1",
    "AVALIAR n=0 21", "AVALIAR n=65 21", "AVALIAR id=25 22",
    "AVALIAR id=-1 22", "AVALIAR params 23", "RELATORIO modo 3 24",
    "COPIAR tam=7 26", "COPIAR tam=6 0")) {
    if ($limitsText -notmatch [regex]::Escape($code)) { $v13.Add("limite ausente: $code") }
}
Write-Check "casos extremos e codigos de erro" $v13.ToArray()

# --- Resumo -----------------------------------------------------------------

$logPathFull = Join-Path $root $LogPath
$logDir = Split-Path -Parent $logPathFull
if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    [void](New-Item -ItemType Directory -Path $logDir)
}
$summary = "Total: $($script:CheckCount) verificacoes, $($script:FailedChecks) falha(s)"
$script:LogLines.Add($summary)
[IO.File]::WriteAllText($logPathFull, (($script:LogLines -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))
Write-Host $summary
if ($script:FailedChecks -ne 0) { exit 1 }
exit 0
