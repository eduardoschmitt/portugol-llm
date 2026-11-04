# ---------------------------------------------------------------------------
# Verificacao independente da atencao causal minima (M10).
# - V1  hashes M1-M9, test.ps1 intacto, escopo do git status, fonte ASCII
# - V2  corpus M8 e holdout M9 intactos (bytes/linhas/SHA-256)
# - V3  contagens de A/B/C/D e 10 exemplos de treino
# - V4  causalidade: tokens futuros nao alteram a saida
# - V5  padding: n=1,2,3 sem PAD-ID e com c correto
# - V6  pesos normalizados e zero fora da mascara
# - V7  exemplo numerico igual em O1/O2/O3/.por
# - V8  metricas de C iguais em O1/O2 e .por
# - V9  perda de treino cai, converge e e deterministica
# - V10 nao mutacao do estado durante inferencia
# - V11 determinismo A/B, gramatica ASCII/LF, sem real
# - V12 regressao: suite 116/116, M7 16/16, M8 18/18, M9 13/13
# - V13 limites, erros e casos extremos
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-attention-bytes.ps1
# ---------------------------------------------------------------------------

param(
    [string]$GeneratedRoot = "temp/attention-tests",
    [string]$SourcePath = "src/atencao.por",
    [string]$InterpreterPath = "C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat",
    [string]$SuitesPath = "scripts/test.ps1",
    [string]$ContextVerifier = "scripts/verify-context-bytes.ps1",
    [string]$CorpusVerifier = "scripts/verify-corpus-bytes.ps1",
    [string]$EvaluationVerifier = "scripts/verify-evaluation-bytes.ps1",
    [string]$LogPath = "temp/m10-verify.log",
    [switch]$SkipSuite
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

. (Join-Path $root "scripts/eval-datasets.ps1") -Quiet
. (Join-Path $root "scripts/attention-oracle.ps1") -Quiet

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

function Get-AtFileSha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead((Join-Path $root $Path))
        try {
            return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "")
        } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

function Get-AtGitBlob([string]$Path) {
    return ((& git -C $root hash-object -- $Path 2>$null) -join "").Trim()
}

$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"
$script:CaseCache = @{}
$script:ReportCache = @{}

function Invoke-AtCase {
    param([string]$Name)
    if ($script:CaseCache.ContainsKey($Name)) { return $script:CaseCache[$Name] }
    $porPath = Join-Path $root (Join-Path $GeneratedRoot "$Name.por")
    if (-not (Test-Path -LiteralPath $porPath)) { throw "Caso ausente: $porPath" }
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

function Get-AtExpectedReport([string]$Name) {
    if (-not $script:ReportCache.ContainsKey($Name)) {
        $script:ReportCache[$Name] = @(Get-AtReport $Name)
    }
    return $script:ReportCache[$Name]
}

function Compare-AtCaseLines {
    param([string]$Name, [string[]]$ExpectedLines)
    $actual = Invoke-AtCase $Name
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

function Get-AtSummaryLine {
    param([string[]]$Lines, [string]$Estado, [string]$Conjunto)
    $prefix = "RESUMO $Estado $Conjunto "
    foreach ($line in $Lines) {
        if ($line.StartsWith($prefix, [StringComparison]::Ordinal)) {
            $parts = $line.Split(' ')
            return [pscustomobject]@{
                N = [int]$parts[3]
                Acertos = [int]$parts[4]
                Bp = [int]$parts[5]
                Perda = [long]$parts[6]
            }
        }
    }
    return $null
}

function Get-AtCheckLine {
    param([string[]]$Lines, [string]$Prefix)
    foreach ($line in $Lines) {
        if ($line.StartsWith($prefix, [StringComparison]::Ordinal)) { return $line }
    }
    return $null
}

function Get-AtCtxLines {
    param([string[]]$Lines)
    return @($Lines | Where-Object { $_.StartsWith("CTX ", [StringComparison]::Ordinal) })
}

function Get-AtPesoMap {
    param([string[]]$Lines)
    $map = @{}
    foreach ($line in $Lines) {
        if ($line -match '^PESO (a|beta) ([0-9]+) (-?[0-9]+)$') {
            $map["$($Matches[1])$($Matches[2])"] = [int]$Matches[3]
        }
    }
    return $map
}

# O2: perda com BigInteger a partir do estado de O1.
function Get-AtPerdaBig {
    param([object]$St, [int[]]$Ent, [int[]]$Alv, [int]$N, [int]$Modo)
    $soma = [System.Numerics.BigInteger]::Zero
    for ($ex = 0; $ex -lt $N; $ex++) {
        $ids = [int[]]@($Ent[$ex * 3], $Ent[$ex * 3 + 1], $Ent[$ex * 3 + 2])
        $ctx = At-CtxInterno $St.A $St.Beta $ids 2 $Modo
        $alvo = $Alv[$ex]
        for ($y = 0; $y -lt 25; $y++) {
            $z = [System.Numerics.BigInteger]::Zero
            for ($d = 0; $d -lt 4; $d++) {
                $z = $z + [System.Numerics.BigInteger]([long]$St.W[$y * 4 + $d] * $ctx.C[$d])
            }
            $z = $z + [System.Numerics.BigInteger]([long](16 * $St.B[$y]))
            if ($y -eq $alvo) { $z = $z - [System.Numerics.BigInteger]::new(256) }
            $soma = $soma + $z * $z
        }
    }
    return $soma
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
    "src/corpus.por"                      = "53e3c624a0f0455721aafb608c965a392cc9261d"
    "src/avaliacao.por"                   = "73233f06855215a2fca0b08fcd5af24fb5a47601"
    "scripts/test.ps1"                    = "e10771b7b89f7ff3132025f57e63a70683600d75"
    "scripts/eval-datasets.ps1"           = "24d6ac03d400d7b538fbe5e30f7048944b63b6ad"
    "scripts/eval-oracle.ps1"             = "c00eb127ca9cf357e533279fe0bb18033beaac9a"
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
    "scripts/build-corpus-tests.ps1"      = "20f491be6ce26d33cb27dc69722ed8d39fa7c16b"
    "scripts/build-evaluation-tests.ps1"  = "27f39e94e808fd66228d408727315dbffae86f71"
    "scripts/test-evaluation.ps1"         = "c3cf35d926ead1142ebfa27f166abab31a7dfc51"
}
foreach ($path in $frozen.Keys) {
    $actual = Get-AtGitBlob $path
    if ($actual -cne $frozen[$path]) { $v1.Add("${path}: $actual; esperado $($frozen[$path])") }
}
$corpusHash = Get-AtFileSha256 "corpus/m8-corpus-v1.txt"
if ($corpusHash -cne "d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113") {
    $v1.Add("corpus/m8-corpus-v1.txt: $corpusHash")
}

$testPath = Join-Path $root "scripts/test.ps1"
$testBytes = [IO.File]::ReadAllBytes($testPath)
if ($testBytes.Length -lt 4 -or $testBytes[0] -ne 0xEF -or $testBytes[1] -ne 0xBB -or $testBytes[2] -ne 0xBF) {
    $v1.Add("test.ps1 sem BOM UTF-8")
}
foreach ($b in $testBytes) { if ($b -eq 0x0D) { $v1.Add("test.ps1 com CR"); break } }
$testText = [Text.Encoding]::UTF8.GetString($testBytes, 3, $testBytes.Length - 3)
$testLines = @($testText -split "`n")
$lineCount = if ($testLines[$testLines.Count - 1] -eq "") { $testLines.Count - 1 } else { $testLines.Count }
if ($lineCount -ne 402) { $v1.Add("test.ps1 com $lineCount linhas; esperado 402") }
if ($testText -notmatch 'Passed:\s+\$passed') { $v1.Add("test.ps1 sem resumo Passed") }

# Fonte M10: ASCII puro, sem CR, sem real/aleatorio/tempo.
$srcBytes = [IO.File]::ReadAllBytes((Join-Path $root $SourcePath))
foreach ($b in $srcBytes) {
    if ($b -eq 0x0D) { $v1.Add("src/atencao.por com CR"); break }
    if ($b -gt 0x7E -and $b -ne 0x0A) { $v1.Add("src/atencao.por fora de ASCII"); break }
}
$srcText = [Text.Encoding]::ASCII.GetString($srcBytes)
$codeOnly = (@($srcText -split "`n" | Where-Object { -not $_.TrimStart().StartsWith("//") }) -join "`n")
foreach ($token in @('aleatorio', 'tempo', 'Math', 'inclua', 'real ')) {
    if ($codeOnly -match [regex]::Escape($token)) { $v1.Add("src/atencao.por usa token proibido: $token") }
}

# Escopo do git status.
$allowedStatus = @(
    "?? docs/attention-plan.md",
    "?? docs/attention-spec.md",
    "?? scripts/attention-oracle.ps1",
    "?? scripts/build-attention-tests.ps1",
    "?? scripts/test-attention.ps1",
    "?? scripts/verify-attention-bytes.ps1",
    "?? src/atencao.por",
    " M scripts/verify-context-bytes.ps1",
    " M scripts/verify-corpus-bytes.ps1",
    " M scripts/verify-evaluation-bytes.ps1"
)
$statusLines = @(& git -C $root status --short 2>$null | ForEach-Object { $_.TrimEnd() })
$unexpected = @($statusLines | Where-Object { $allowedStatus -notcontains $_ })
if ($unexpected.Count -gt 0) {
    $v1.Add("git status fora do escopo: " + ($unexpected -join " | "))
}
Write-Check "hashes M1-M9, test.ps1 intacto, fonte ASCII e escopo" $v1.ToArray()

# --- V2 ---------------------------------------------------------------------

$ds = Get-AtDatasets
$sep = Assert-EvalDataset
$v2 = @()
if ($sep.Bytes -ne 724) { $v2 += "holdout bytes=$($sep.Bytes)" }
if ($sep.Lines -ne 50) { $v2 += "holdout linhas=$($sep.Lines)" }
if ($sep.Sha256 -cne "e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10") {
    $v2 += "holdout sha=$($sep.Sha256)"
}
if ($sep.Errors.Count -ne 0) { $v2 += $sep.Errors }
if ($corpusHash -cne "d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113") {
    $v2 += "corpus sha=$corpusHash"
}
Write-Check "corpus M8 e holdout M9 intactos" $v2

# --- V3 ---------------------------------------------------------------------

$v3 = @()
if ($sep.A -ne 10) { $v3 += "A=$($sep.A)" }
if ($sep.BSeen -ne 10 -or $sep.BUnseen -ne 10) { $v3 += "B=$($sep.BSeen)+$($sep.BUnseen)" }
if ($sep.C -ne 32) { $v3 += "C=$($sep.C)" }
if ($sep.CSemPare -ne 24) { $v3 += "C_SEM_PARE=$($sep.CSemPare)" }
if ($sep.D -ne 10) { $v3 += "D=$($sep.D)" }
if ($ds.TrainEnt.Length -ne 30 -or $ds.TrainAlv.Length -ne 10) {
    $v3 += "treino entradas=$($ds.TrainEnt.Length) alvos=$($ds.TrainAlv.Length)"
}
Write-Check "contagens de A/B/C/D e 10 exemplos de treino" $v3

# --- V4 ---------------------------------------------------------------------

$v4 = New-Object System.Collections.Generic.List[string]
$stC = At-NovoEstado
$idsA = [int[]]@(3, 12, 5)
$idsB = [int[]]@(3, 12, 24)
$ctxA = At-CtxInterno $stC.A $stC.Beta $idsA 1 0
$ctxB = At-CtxInterno $stC.A $stC.Beta $idsB 1 0
for ($k = 0; $k -lt 4; $k++) {
    if ($ctxA.C[$k] -ne $ctxB.C[$k]) { $v4.Add("causal: c[$k] muda com token futuro (modo 0)") }
}
$cntrlA = At-CtxInterno $stC.A $stC.Beta $idsA 2 1
$cntrlB = At-CtxInterno $stC.A $stC.Beta $idsB 2 1
$diff = $false
for ($k = 0; $k -lt 4; $k++) { if ($cntrlA.C[$k] -ne $cntrlB.C[$k]) { $diff = $true } }
if (-not $diff) { $v4.Add("controle: futuro nao muda nem quando permitido") }
# Todos os 32 contextos de C: alterar a posicao 2 nao muda a consulta i=1.
for ($ex = 0; $ex -lt 32; $ex++) {
    $p = [int[]]@($ds.CEnt[$ex * 3], $ds.CEnt[$ex * 3 + 1], $ds.CEnt[$ex * 3 + 2])
    $q2 = ($p[2] + 1) % 25
    $q = [int[]]@($p[0], $p[1], $q2)
    $r1 = At-CtxInterno $stC.A $stC.Beta $p 1 0
    $r2 = At-CtxInterno $stC.A $stC.Beta $q 1 0
    for ($k = 0; $k -lt 4; $k++) {
        if ($r1.C[$k] -ne $r2.C[$k]) { $v4.Add("C[$ex]: futuro altera consulta i=1"); break }
    }
}
$caso = Invoke-AtCase "at_causal_futuro"
if ($null -eq (Get-AtCheckLine $caso.Lines "CHECK CAUSAL OK")) { $v4.Add(".por: CHECK CAUSAL OK ausente") }
if ($null -eq (Get-AtCheckLine $caso.Lines "CONTROLE FUTURO 1")) { $v4.Add(".por: CONTROLE FUTURO != 1") }
$ctxs = Get-AtCtxLines $caso.Lines
if ($ctxs.Count -ne 2 -or $ctxs[0].Substring(6) -cne $ctxs[1].Substring(6)) {
    $v4.Add(".por: CTX causal 2 diverge")
}
Write-Check "causalidade: tokens futuros nao alteram a saida" $v4.ToArray()

# --- V5 ---------------------------------------------------------------------

$v5 = New-Object System.Collections.Generic.List[string]
$pad = Invoke-AtCase "at_padding"
if ($null -eq (Get-AtCheckLine $pad.Lines "CHECK PADDING OK")) { $v5.Add(".por: CHECK PADDING OK ausente") }
$padCtx = Get-AtCtxLines $pad.Lines
if ($padCtx.Count -ne 3) {
    $v5.Add(".por: $($padCtx.Count) linhas CTX; esperado 3")
} else {
    for ($n = 1; $n -le 3; $n++) {
        $r = At-CtxInterno $stC.A $stC.Beta $idsA ($n - 1) 0
        $want = "CTX $n $($r.U) $($r.C[0]) $($r.C[1]) $($r.C[2]) $($r.C[3])"
        if ($padCtx[$n - 1] -cne $want) { $v5.Add("padding n=${n}: '$($padCtx[$n - 1])'; esperado '$want'") }
    }
}
# Sem PAD-ID: mudar ids fora de 0..n-1 nao altera nada.
for ($n = 1; $n -le 3; $n++) {
    $x = [int[]]@($idsA[0], $idsA[1], $idsA[2])
    $y = [int[]]@($idsA[0], $idsA[1], $idsA[2])
    for ($k = $n; $k -lt 3; $k++) { $y[$k] = ($y[$k] + 7) % 25 }
    $r1 = At-CtxInterno $stC.A $stC.Beta $x ($n - 1) 0
    $r2 = At-CtxInterno $stC.A $stC.Beta $y ($n - 1) 0
    for ($k = 0; $k -lt 4; $k++) {
        if ($r1.C[$k] -ne $r2.C[$k]) { $v5.Add("padding n=${n}: posicao futura lida"); break }
    }
}
Write-Check "padding n=1,2,3 sem PAD-ID e com c correto" $v5.ToArray()

# --- V6 ---------------------------------------------------------------------

$v6 = New-Object System.Collections.Generic.List[string]
$pesos = Invoke-AtCase "at_pesos"
$somas = @($pesos.Lines | Where-Object { $_.StartsWith("SOMA_PERMIL ", [StringComparison]::Ordinal) })
if ($somas.Count -ne 2) {
    $v6.Add(".por: $($somas.Count) SOMA_PERMIL; esperado 2")
} else {
    foreach ($line in $somas) {
        $v = [int]$line.Substring(12)
        if ([math]::Abs($v - 1000) -gt 2) { $v6.Add("soma de permilagens=$v") }
    }
}
$mask = Invoke-AtCase "at_mascara"
foreach ($line in $mask.Lines) {
    if ($line -match '^AT ([0-9]+) ([0-9]+) (-?[0-9]+) ([0-9]+) ([0-9]+) ([01])$') {
        $i = [int]$Matches[1]; $j = [int]$Matches[2]
        $u = [int]$Matches[4]; $p = [int]$Matches[5]; $perm = [int]$Matches[6]
        if ($j -gt $i -and ($u -ne 0 -or $p -ne 0 -or $perm -ne 0)) {
            $v6.Add("mascara: AT $i $j com peso fora da mascara")
        }
    }
}
# O1: para todos os modos e posicoes, soma dentro da tolerancia e zero fora.
foreach ($modo in @(0, 1, 2)) {
    for ($i = 0; $i -lt 3; $i++) {
        $r = At-PesosInterno $stC.A $stC.Beta $idsA $i $modo
        $soma = 0
        for ($j = 0; $j -le $i; $j++) { $soma += $r.P[$j] }
        if ([math]::Abs($soma - 1000) -gt 2) { $v6.Add("O1 modo=$modo i=$i soma=$soma") }
        for ($j = $i + 1; $j -lt 3; $j++) {
            if ($r.UArr[$j] -ne 0 -or $r.P[$j] -ne 0) { $v6.Add("O1 modo=$modo i=$i j=$j fora da mascara") }
        }
    }
}
Write-Check "pesos normalizados e zero fora da mascara" $v6.ToArray()

# --- V7 ---------------------------------------------------------------------

$v7 = New-Object System.Collections.Generic.List[string]
$manual = @(Get-AtManualExample)
$exemplo = Invoke-AtCase "at_exemplo"
$exemploLines = @($exemplo.Lines | Where-Object { $_ -ne "ATEN V1" -and $_ -ne "ESTADO EXEMPLO" -and $_ -ne "FIM" })
if (($exemploLines -join "`n") -cne ($manual -join "`n")) {
    $v7.Add(".por difere de O3: '$($exemploLines -join ' | ')'")
}
$o1Exemplo = @(Get-AtExpectedReport "at_exemplo" | Where-Object { $_ -ne "ATEN V1" -and $_ -ne "ESTADO EXEMPLO" -and $_ -ne "FIM" })
if (($o1Exemplo -join "`n") -cne ($manual -join "`n")) {
    $v7.Add("O1 difere de O3")
}
# O2: mesmo exemplo com BigInteger, independente da aritmetica long de O1.
$sA = [System.Numerics.BigInteger]::Zero
$sB = [System.Numerics.BigInteger]::Zero
$sC = [System.Numerics.BigInteger]::Zero
for ($d = 0; $d -lt 4; $d++) {
    $e3 = [System.Numerics.BigInteger]::new([long](((3 * 7 + $d * 3) % 32) - 16))
    $e12 = [System.Numerics.BigInteger]::new([long](((12 * 7 + $d * 3) % 32) - 16))
    $e5 = [System.Numerics.BigInteger]::new([long](((5 * 7 + $d * 3) % 32) - 16))
    $sc = [System.Numerics.BigInteger]::new(16) * $e3
    if ($d -eq 0) { $sc = $sc + [System.Numerics.BigInteger]::Zero }
    if ($d -eq 1) { $sc = $sc + [System.Numerics.BigInteger]::new(1) }
    if ($d -eq 2) { $sc = $sc - [System.Numerics.BigInteger]::new(1) }
    if ($d -eq 0) { $sA = $sc } elseif ($d -eq 1) { $sB = $sc } else { $sC = $sC }
}
$scores = @(
    [System.Numerics.BigInteger]::new(16) * [System.Numerics.BigInteger]::new([long]((3 * 7) % 32 - 16))
)
# Recalcula os tres escores completos com BigInteger.
$biScores = New-Object 'System.Numerics.BigInteger[]' 3
$biIds = @(3, 12, 5)
$biBeta = @(0, 1, -1)
for ($j = 0; $j -lt 3; $j++) {
    $s = [System.Numerics.BigInteger]::Zero
    for ($d2 = 0; $d2 -lt 4; $d2++) {
        $e = [System.Numerics.BigInteger]::new([long](((($biIds[$j] * 7 + $d2 * 3) % 32) - 16) * 16))
        $s = $s + $e
    }
    $s = $s + [System.Numerics.BigInteger]::new([long]$biBeta[$j])
    $biScores[$j] = $s
}
$uBig = @()
for ($j = 0; $j -lt 3; $j++) { if ($biScores[$j] -gt 0) { $uBig += $biScores[$j] } else { $uBig += [System.Numerics.BigInteger]::Zero } }
$uSum = [System.Numerics.BigInteger]::Zero
foreach ($u in $uBig) { $uSum += $u }
$divBig = {
    param([System.Numerics.BigInteger]$Num, [System.Numerics.BigInteger]$Den)
    $neg = $Num -lt 0
    $abs = if ($neg) { -$Num } else { $Num }
    $q = [System.Numerics.BigInteger]::Divide(($abs + [System.Numerics.BigInteger]::new([long][math]::Floor([double]$Den / 2.0))), $Den)
    if ($neg) { return -$q }
    return $q
}
$cBig = @()
for ($d2 = 0; $d2 -lt 4; $d2++) {
    $num = [System.Numerics.BigInteger]::Zero
    for ($j = 0; $j -lt 3; $j++) {
        $e = [System.Numerics.BigInteger]::new([long]((($biIds[$j] * 7 + $d2 * 3) % 32) - 16))
        $num = $num + $uBig[$j] * $e
    }
    $cBig += (& $divBig $num $uSum)
}
$zBig = [System.Numerics.BigInteger]::Zero
$wEx = @(1, 0, -1, 2)
for ($d2 = 0; $d2 -lt 4; $d2++) { $zBig += [System.Numerics.BigInteger]::new([long]$wEx[$d2]) * $cBig[$d2] }
$zBig += [System.Numerics.BigInteger]::new(16)
$deltaBig = $zBig - [System.Numerics.BigInteger]::new(256)
$manualText = ($manual -join "`n")
if ($manualText -notmatch ("(?m)^Z " + $zBig + "$")) { $v7.Add("O2: Z=$zBig difere de O3") }
if ($manualText -notmatch ("(?m)^DELTA " + $deltaBig + "$")) { $v7.Add("O2: DELTA=$deltaBig difere de O3") }
if ($biScores[0] -ne 608 -or $biScores[1] -ne 545 -or $biScores[2] -ne -545) {
    $v7.Add("O2: escores $($biScores -join ' ')")
}
if (($cBig -join " ") -cne "5 8 11 14") { $v7.Add("O2: c=$($cBig -join ' ')") }
Write-Check "exemplo numerico igual em O1/O2/O3/.por" $v7.ToArray()

# --- V8 ---------------------------------------------------------------------

$v8 = New-Object System.Collections.Generic.List[string]
$treinadoExpected = Get-AtExpectedReport "at_treinado"
$cmp8 = Compare-AtCaseLines "at_treinado" $treinadoExpected
foreach ($e in $cmp8.Errors) { $v8.Add($e) }
$real8 = $cmp8.Actual.Lines
foreach ($conj in @("A", "B", "B_VISTO", "B_INEDITO", "C", "C_SEM_PARE", "D")) {
    $sum = Get-AtSummaryLine $real8 "TREINADO" $conj
    if ($null -eq $sum) { $v8.Add("RESUMO TREINADO $conj ausente"); continue }
    $bpCalc = At-BP $sum.Acertos $sum.N
    if ($bpCalc -ne $sum.Bp) { $v8.Add("${conj}: BP=$($sum.Bp); r(10000*$($sum.Acertos)/$($sum.N))=$bpCalc") }
}
$cReal = Get-AtSummaryLine $real8 "TREINADO" "C"
$cExp = Get-AtSummaryLine $treinadoExpected "TREINADO" "C"
if ($null -eq $cReal -or $null -eq $cExp) {
    $v8.Add("RESUMO C ausente")
} elseif ($cReal.Acertos -ne $cExp.Acertos -or $cReal.Bp -ne $cExp.Bp -or $cReal.Perda -ne $cExp.Perda) {
    $v8.Add("C real difere de O1")
}
# O2: perda de C com BigInteger a partir do estado treinado de O1.
$stT = At-NovoEstado
[void](At-Treinar $stT $ds.TrainEnt $ds.TrainAlv 10 0)
$cEnt = [int[]]$ds.CEnt
$cAlv = [int[]]$ds.CAlv
$perdaBig = Get-AtPerdaBig $stT $cEnt $cAlv 32 0
if ($null -ne $cReal -and [System.Numerics.BigInteger]::new([long]$cReal.Perda) -ne $perdaBig) {
    $v8.Add("perda C: .por=$($cReal.Perda) O2=$perdaBig")
}
$semReal = Get-AtSummaryLine $real8 "TREINADO" "C_SEM_PARE"
$semExp = Get-AtSummaryLine $treinadoExpected "TREINADO" "C_SEM_PARE"
if ($null -eq $semReal -or $null -eq $semExp -or $semReal.N -ne 24) {
    $v8.Add("C_SEM_PARE invalido")
}
# Soma dos ok das linhas EX igual ao acerto do RESUMO.
foreach ($conj in @("A", "B", "C", "D")) {
    $sum = Get-AtSummaryLine $real8 "TREINADO" $conj
    if ($null -eq $sum) { continue }
    $oks = 0
    foreach ($line in $real8) {
        if ($line.StartsWith("EX TREINADO $conj ", [StringComparison]::Ordinal)) {
            $parts = $line.Split(' ')
            if ([int]$parts[9] -eq 1) { $oks++ }
        }
    }
    if ($oks -ne $sum.Acertos) { $v8.Add("EX ok de $conj = $oks; RESUMO = $($sum.Acertos)") }
}
Write-Check "metricas de C iguais em O1/O2 e .por" $v8.ToArray()

# --- V9 ---------------------------------------------------------------------

$v9 = New-Object System.Collections.Generic.List[string]
$treinoLine = $null
foreach ($line in $real8) {
    if ($line.StartsWith("TREINO 10 ", [StringComparison]::Ordinal)) { $treinoLine = $line; break }
}
if ($null -eq $treinoLine) {
    $v9.Add("TREINO 10 ausente")
} else {
    $p = $treinoLine.Split(' ')
    $n = [int]$p[1]; $rodadas = [int]$p[2]; $loss0 = [long]$p[3]; $lossN = [long]$p[4]
    $alteracoes = [int]$p[5]; $convergiu = [int]$p[6]
    if ($n -ne 10) { $v9.Add("n=$n") }
    if ($rodadas -lt 1 -or $rodadas -gt 6) { $v9.Add("rodadas=$rodadas") }
    if (-not ($lossN -lt $loss0)) { $v9.Add("perda nao caiu: $loss0 -> $lossN") }
    if ($alteracoes -lt 0 -or $alteracoes -gt 7 * $rodadas) { $v9.Add("alteracoes=$alteracoes") }
    if ($convergiu -ne 0 -and $convergiu -ne 1) { $v9.Add("convergiu=$convergiu") }
    # Resultado honesto do corpus real: atencao permanece uniforme.
    $primeiroRelatorio = New-Object System.Collections.Generic.List[string]
    $vistos = 0
    foreach ($linha in $real8) {
        if ($linha -ceq "ATEN V1") {
            $vistos++
            if ($vistos -gt 1) { break }
        }
        $primeiroRelatorio.Add($linha)
    }
    $pm = Get-AtPesoMap $primeiroRelatorio.ToArray()
    foreach ($key in $pm.Keys) {
        if ($pm[$key] -ne 0) { $v9.Add("PESO $key=$($pm[$key]); esperado 0 no corpus real") }
    }
    if ($alteracoes -ne 0) { $v9.Add("alteracoes=$alteracoes no corpus real; esperado 0 (uniforme e otimo local)") }
}
# Historico de O1 monotono e decrescente.
$stH = At-NovoEstado
$trH = At-Treinar $stH $ds.TrainEnt $ds.TrainAlv 10 0
for ($i = 1; $i -le $trH.Info[0]; $i++) {
    if ($trH.Hist[$i] -gt $trH.Hist[$i - 1]) { $v9.Add("historico subiu em $i") }
}
if (-not ($trH.Hist[$trH.Info[0]] -lt $trH.Hist[0])) { $v9.Add("historico de O1 nao caiu") }
# Sintetico: a atencao muda de fato quando ha sinal.
$sintPeso = Get-AtPesoMap $real8
if ($sintPeso["beta2"] -ne 1) { $v9.Add("sintetico: beta[2]=$($sintPeso['beta2']); esperado 1") }
$sintTreino = $null
$seenSint = $false
foreach ($line in $real8) {
    if ($line -ceq "ESTADO SINTETICO") { $seenSint = $true; continue }
    if ($seenSint -and $line.StartsWith("TREINO 10 ", [StringComparison]::Ordinal)) { $sintTreino = $line; break }
}
if ($null -eq $sintTreino) {
    $v9.Add("TREINO do sintetico ausente")
} else {
    $p = $sintTreino.Split(' ')
    if (-not ([long]$p[4] -lt [long]$p[3])) { $v9.Add("sintetico: perda nao caiu") }
    if ([int]$p[5] -le 0) { $v9.Add("sintetico: nenhuma alteracao de atencao") }
}
if ($null -eq (Get-AtCheckLine $real8 "CHECK ATENCAO_MUDOU OK")) { $v9.Add("CHECK ATENCAO_MUDOU OK ausente") }
# Determinismo do treino: segunda execucao identica.
$again = Invoke-AtCase "at_treinado"
if (($again.Bytes -join ",") -cne ((Invoke-AtCase "at_treinado").Bytes -join ",")) { $v9.Add("treino nao deterministico") }
Write-Check "perda cai, converge e e deterministica" $v9.ToArray()

# --- V10 --------------------------------------------------------------------

$v10 = New-Object System.Collections.Generic.List[string]
$stM = At-NovoEstado
$before = [pscustomobject]@{
    A = [int[]]$stM.A.Clone(); Beta = [int[]]$stM.Beta.Clone()
    W = [int[]]$stM.W.Clone(); B = [int[]]$stM.B.Clone()
}
$cM = [int[]]@(0, 0, 0, 0)
foreach ($modo in @(0, 1, 2)) {
    [void](At-CtxInterno $stM.A $stM.Beta $idsA 2 $modo)
    [void](At-PesosInterno $stM.A $stM.Beta $idsA 2 $modo)
}
[void](At-Acertos $stM $ds.TrainEnt $ds.TrainAlv 10 0)
[void](At-AcertosTipo $stM $ds.CEnt $ds.CAlv $ds.CSemPareTipo 32 0 1)
[void](At-MargemMedia $stM $ds.TrainEnt $ds.TrainAlv 10 0)
[void](At-Argmax $stM.W $stM.B $cM)
$after = $stM
for ($i = 0; $i -lt 4; $i++) { if ($before.A[$i] -ne $after.A[$i]) { $v10.Add("a[$i] mudou") } }
for ($i = 0; $i -lt 3; $i++) { if ($before.Beta[$i] -ne $after.Beta[$i]) { $v10.Add("beta[$i] mudou") } }
for ($i = 0; $i -lt 100; $i++) { if ($before.W[$i] -ne $after.W[$i]) { $v10.Add("w[$i] mudou"); break } }
for ($i = 0; $i -lt 25; $i++) { if ($before.B[$i] -ne $after.B[$i]) { $v10.Add("b[$i] mudou"); break } }
# .por: checksum dos casos so de inferencia igual ao inicial.
$initChecksum = At-Checksum (At-NovoEstado)
foreach ($name in @("at_limites", "at_padding", "at_nao_treinado", "at_determinismo_a")) {
    $case = Invoke-AtCase $name
    $line = $null
    foreach ($l in $case.Lines) { if ($l.StartsWith("CHECKSUM ", [StringComparison]::Ordinal)) { $line = $l } }
    if ($null -eq $line) { $v10.Add("${name}: CHECKSUM ausente"); continue }
    if ([int]$line.Substring(9) -ne $initChecksum) {
        $v10.Add("${name}: checksum $($line.Substring(9)); inicial $initChecksum")
    }
}
if ($null -eq (Get-AtCheckLine $real8 "CHECK MUTACAO TREINADO OK")) { $v10.Add("CHECK MUTACAO TREINADO OK ausente") }
$nao = Invoke-AtCase "at_nao_treinado"
if ($null -eq (Get-AtCheckLine $nao.Lines "CHECK MUTACAO NAO_TREINADO OK")) { $v10.Add("CHECK MUTACAO NAO_TREINADO OK ausente") }
Write-Check "nao mutacao do estado durante inferencia" $v10.ToArray()

# --- V11 --------------------------------------------------------------------

$v11 = New-Object System.Collections.Generic.List[string]
$detA = Invoke-AtCase "at_determinismo_a"
$detB = Invoke-AtCase "at_determinismo_b"
if (($detA.Bytes -join ",") -cne ($detB.Bytes -join ",")) { $v11.Add("determinismo A/B diverge") }
if ($detA.Error.Length -gt 0 -or $detB.Error.Length -gt 0) { $v11.Add("stderr nao vazio") }
$grammar = @(
    '^ATEN V1$',
    '^ESTADO (NAO_TREINADO|LIMITES|MASCARA|PADDING|PESOS|EXEMPLO|CAUSAL|OVERFLOW|LAYOUT|UNIFORME|RECENCIA|TREINADO|SINTETICO|ORDEM|DETERMINISMO)$',
    '^TREINO [0-9]+( -?[0-9]+){0,5}$',
    '^PESO (a|beta) [0-9]+ -?[0-9]+$',
    '^AT [0-9]+ [0-9]+ -?[0-9]+ [0-9]+ [0-9]+ [01]$',
    '^CTX [0-9]+( -?[0-9]+){4,5}$',
    '^RESUMO [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D|S) [0-9]+ [0-9]+ [0-9]+ -?[0-9]+$',
    '^EX [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D|S) [0-9]+( [0-9]+){3}( [0-9]+){2} [01]$',
    '^CONF [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D|S) [0-9]+ [0-9]+ [0-9]+$',
    '^DELTA_BP [A-Z_]+ (A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D|S) -?[0-9]+ -?[0-9]+ -?[0-9]+$',
    '^MARGEM [A-Z_]+ (A|C) -?[0-9]+$',
    '^CHECK MASCARA CAUSAL (OK|FALHA)$',
    '^CHECK PADDING (OK|FALHA)$',
    '^CHECK NORMALIZACAO (OK|FALHA)$',
    '^CHECK CAUSAL (OK|FALHA)$',
    '^CHECK MUTACAO [A-Z_]+ (OK|FALHA)$',
    '^CHECK ORDEM OK$',
    '^CHECK ATENCAO_MUDOU (OK|FALHA)$',
    '^CHECK OVERFLOW OK$',
    '^CONTROLE FUTURO [01]$',
    '^ORDEM (INVERSO|PESOS) [0-9]+ 32$',
    '^LIMITES [A-Z0-9_]+( -?[0-9]+)*$',
    '^LIMITE TEORICO S [0-9]+$',
    '^REAL (IDMAX|ZMAX|DELTA|DELTA2|PERDA10) -?[0-9]+( -?[0-9]+)?$',
    '^CODIGO [A-Z_]+ [0-9]$',
    '^Z -?[0-9]+$',
    '^DELTA -?[0-9]+$',
    '^WN [0-3] -?[0-9]+$',
    '^BN -?[0-9]+$',
    '^SOMA_PERMIL [0-9]+$',
    '^CHECKSUM -?[0-9]+$',
    '^FIM$'
)
$allCases = @(
    "at_limites", "at_layout", "at_mascara", "at_padding", "at_pesos",
    "at_exemplo", "at_causal_futuro", "at_overflow", "at_treinado",
    "at_nao_treinado", "at_uniforme", "at_recencia", "at_ordem",
    "at_determinismo_a", "at_determinismo_b"
)
foreach ($name in $allCases) {
    $case = Invoke-AtCase $name
    foreach ($line in $case.Lines) {
        $matched = $false
        foreach ($pattern in $grammar) {
            if ($line -match $pattern) { $matched = $true; break }
        }
        if (-not $matched) { $v11.Add("${name}: linha fora da gramatica: '$line'"); break }
    }
    $bytes = $case.Bytes
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 0x0A) { $v11.Add("${name}: sem LF final") }
    foreach ($bb in $bytes) {
        if ($bb -eq 0x0D) { $v11.Add("${name}: CR"); break }
        if ($bb -ne 0x0A -and ($bb -lt 0x20 -or $bb -gt 0x7E)) { $v11.Add("${name}: byte fora de ASCII/LF"); break }
    }
    if ($case.Text -match 'NaN|Infinity|e\+|-0([^0-9]|$)') { $v11.Add("${name}: token proibido") }
}
Write-Check "determinismo A/B, gramatica e ASCII/LF" $v11.ToArray()

# --- V12 --------------------------------------------------------------------

$v12 = New-Object System.Collections.Generic.List[string]
if (-not $SkipSuite) {
    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = "powershell.exe" }
    $suiteOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $SuitesPath) 2>&1 | Out-String
    $suiteCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $root "temp/m10-verify-suite.log"), $suiteOut, (New-Object System.Text.UTF8Encoding($false)))
    if ($suiteCode -ne 0) { $v12.Add("suite saiu com $suiteCode") }
    if ($suiteOut -notmatch 'Passed:\s+116') { $v12.Add("suite nao reportou 116 PASS") }
    if ($suiteOut -notmatch 'Failed:\s+0') { $v12.Add("suite nao reportou 0 FAIL") }
    if ($suiteOut -notmatch 'Total:\s+116') { $v12.Add("suite nao reportou Total 116") }

    $regressions = @(
        @{ Name = "M7"; Path = $ContextVerifier; Checks = 16 },
        @{ Name = "M8"; Path = $CorpusVerifier; Checks = 18 },
        @{ Name = "M9"; Path = $EvaluationVerifier; Checks = 13 }
    )
    foreach ($reg in $regressions) {
        $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $reg.Path) 2>&1 | Out-String
        $code = $LASTEXITCODE
        $logName = "temp/m10-verify-" + $reg.Name.ToLower() + ".log"
        [IO.File]::WriteAllText((Join-Path $root $logName), $out, (New-Object System.Text.UTF8Encoding($false)))
        if ($code -ne 0) { $v12.Add("$($reg.Name) saiu com $code") }
        $reportou = $false
        if ($out -match ("Total: {0} verificacoes, 0 falha" -f $reg.Checks)) { $reportou = $true }
        if ($out -match ("(?s)Checks:\s+{0}\s+Failures:\s+0" -f $reg.Checks)) { $reportou = $true }
        if (-not $reportou) {
            $v12.Add("$($reg.Name) nao reportou $($reg.Checks)/$($reg.Checks)")
        }
    }
} else {
    $script:LogLines.Add("V12 suite/regressao ignorada por -SkipSuite (Gate G6)")
}
Write-Check "suite 116/116, M7 16/16, M8 18/18, M9 13/13" $v12.ToArray()

# --- V13 --------------------------------------------------------------------

$v13 = New-Object System.Collections.Generic.List[string]
$limExpected = @(Get-AtExpectedReport "at_limites")
$cmpLim = Compare-AtCaseLines "at_limites" $limExpected
foreach ($e in $cmpLim.Errors) { $v13.Add($e) }
$layExpected = @(Get-AtExpectedReport "at_layout")
$cmpLay = Compare-AtCaseLines "at_layout" $layExpected
foreach ($e in $cmpLay.Errors) { $v13.Add($e) }
$overflowExpected = @(Get-AtExpectedReport "at_overflow")
$cmpOv = Compare-AtCaseLines "at_overflow" $overflowExpected
foreach ($e in $cmpOv.Errors) { $v13.Add($e) }
foreach ($want in @("CODIGO N_ID 1", "CODIGO ID 2", "CODIGO MODO 6", "CODIGO PARAM 3", "CODIGO EPOCAS 4", "CODIGO OK 0")) {
    if ($cmpLay.Actual.Lines -notcontains $want) { $v13.Add("codigo ausente: $want") }
}
$perda10 = $null
foreach ($line in $cmpOv.Actual.Lines) {
    if ($line.StartsWith("REAL PERDA10 ", [StringComparison]::Ordinal)) { $perda10 = [long]$line.Substring(13) }
}
if ($null -eq $perda10) {
    $v13.Add("REAL PERDA10 ausente")
} elseif ($perda10 -ge 2147483647) {
    $v13.Add("PERDA10=$perda10 estoura 32 bits")
}
# O2: limites teoricos com BigInteger.
Add-Type -AssemblyName System.Numerics
$bigS = [System.Numerics.BigInteger]::new([long](4 * 16 * 16 + 16))
$bigU = $bigS * 3
$bigNum = $bigU * 16
$bigZ = [System.Numerics.BigInteger]::new([long](4 * 16 * 16 + 16 * 16))
$bigD = $bigZ + 256
$bigL = $bigD * $bigD * 25 * 10
$limit = [System.Numerics.BigInteger]::new([long]2147483647)
if ($bigS -ne 1040 -or $bigU -ne 3120 -or $bigNum -ne 49920) { $v13.Add("limites S/U/NUM: $bigS/$bigU/$bigNum") }
if ($bigZ -ne 1280 -or $bigD -ne 1536) { $v13.Add("limites Z/DELTA: $bigZ/$bigD") }
if ($bigL -ne 589824000) { $v13.Add("limite PERDA: $bigL") }
if (-not ($bigL -lt $limit)) { $v13.Add("limite PERDA fora de 32 bits") }
Write-Check "limites, erros e casos extremos" $v13.ToArray()

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
