<#
.SYNOPSIS
    Demonstracao minima e reproduzivel do pipeline M1 -> M8.

.DESCRIPTION
    Le o corpus versionado corpus/m8-corpus-v1.txt, tokeniza uma linha,
    extrai as janelas K=3, treina a camada linear com a regra delta e gera
    uma continuacao autoregressiva a partir de "se verdadeiro faca".

    O arquivo .por e montado em temp/demo/ a partir dos fragmentos
    versionados em src/. Nada em temp/ e necessario para executar a demo:
    o script recria tudo a cada execucao.

    Requisitos: Windows, PowerShell 5.1+ e Portugol Studio instalado
    (portugol-console.bat). O caminho do interpretador pode ser informado
    com -InterpreterPath ou pela variavel de ambiente PORTUGOL_CONSOLE.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo.ps1 `
        -InterpreterPath "C:\Program Files\Portugol Studio\portugol-console.bat"
#>

param(
    [string]$InterpreterPath = "",
    [string]$CorpusPath = "corpus/m8-corpus-v1.txt",
    [string]$OutputRoot = "temp/demo"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

function Resolve-DemoInterpreter {
    param([string]$Explicit)

    if ($Explicit) {
        if (Test-Path -LiteralPath $Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
        throw "Interpretador nao encontrado em: $Explicit"
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:PORTUGOL_CONSOLE) { $candidates.Add($env:PORTUGOL_CONSOLE) }
    if ($env:ProgramData) {
        $candidates.Add((Join-Path $env:ProgramData "UNIVALI\Portugol Studio\portugol-console.bat"))
    }
    $candidates.Add("C:\Program Files\Portugol Studio\portugol-console.bat")
    $candidates.Add("C:\Program Files (x86)\Portugol Studio\portugol-console.bat")

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @"
Interpretador do Portugol Studio nao encontrado.

Instale o Portugol Studio e informe o caminho do portugol-console.bat:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo.ps1 ``
      -InterpreterPath "C:\Program Files\Portugol Studio\portugol-console.bat"

Ou defina a variavel de ambiente PORTUGOL_CONSOLE.
"@
}

function Read-DemoFragment {
    param([string]$Path)
    return (([IO.File]::ReadAllText((Join-Path $root $Path))) -replace "`r`n", "`n").TrimEnd("`n")
}

function ConvertTo-DemoLiteral {
    param([string]$Text)
    if ($Text -match '[\\"]') { throw "Caractere nao suportado no literal do corpus: $Text" }
    return '"' + $Text + '"'
}

$interpreter = Resolve-DemoInterpreter $InterpreterPath

$corpusFull = Join-Path $root $CorpusPath
if (-not (Test-Path -LiteralPath $corpusFull)) { throw "Corpus ausente: $CorpusPath" }
$lines = @([IO.File]::ReadAllLines($corpusFull))
if ($lines.Count -ne 5) { throw "Corpus deve ter 5 linhas; encontrado $($lines.Count)" }
foreach ($line in $lines) {
    if ($line -notmatch '^[a-z ]+$') { throw "Linha do corpus fora do formato esperado: $line" }
}

$declarations = New-Object System.Collections.Generic.List[string]
$declarations.Add("        cadeia linhas[5]")
for ($i = 0; $i -lt 5; $i++) {
    $declarations.Add(("        linhas[{0}] = {1}" -f $i, (ConvertTo-DemoLiteral $lines[$i])))
}

$driver = @'
        escreva("=== 1. TOKENIZACAO ===\n")
        inteiro ids[8]
        inteiro diag[2]
        inteiro n = corp_tokenizar(linhas[0], ids, diag)
        se (n < 1)
        {
            escreva("ERRO_TOKENIZAR=", 0 - n, "\n")
        }
        senao
        {
            escreva("LINHA: ", linhas[0], "\n")
            escreva("IDS:")
            inteiro k = 0
            enquanto (k < n)
            {
                escreva(" ", ids[k])
                k = k + 1
            }
            escreva("\nPALAVRAS:")
            k = 0
            enquanto (k < n)
            {
                escreva(" ")
                ctx_escrever_palavra(ids[k])
                k = k + 1
            }
            escreva("\n")
        }

        escreva("\n=== 2. JANELAS K=3 ===\n")
        inteiro entradas[30]
        inteiro alvos[10]
        inteiro n_ex[2]
        inteiro dg[2]
        inteiro codigo = corp_extrair(linhas, 5, entradas, alvos, n_ex, dg)
        escreva("EXEMPLOS=", n_ex[0], " CODIGO=", codigo, "\n")

        escreva("\n=== 3. TREINO ===\n")
        inteiro w16[300]
        inteiro b16[25]
        ctx_inicializar(w16, b16)
        inteiro hist[9]
        inteiro epocas = 8
        inteiro r = corp_treinar(w16, b16, entradas, alvos, n_ex[0], epocas, hist)
        escreva("TREINO_CODIGO=", r, "\n")
        ctx_imprimir_historico(hist, epocas)
        inteiro acertos = ctx_acertos(w16, b16, entradas, alvos, n_ex[0])
        escreva("ACERTOS_NO_TREINO=", acertos, "/", n_ex[0], "\n")

        escreva("\n=== 4. PREDICAO DE UM CONTEXTO ===\n")
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, 6, c16)
        inteiro pred = ctx_argmax(w16, b16, c16)
        escreva("CONTEXTO: ")
        ctx_escrever_palavra(entradas[18])
        escreva(" ")
        ctx_escrever_palavra(entradas[19])
        escreva(" ")
        ctx_escrever_palavra(entradas[20])
        escreva(" -> ")
        ctx_escrever_palavra(pred)
        escreva("\nALVO: ")
        ctx_escrever_palavra(alvos[6])
        escreva("\n")

        escreva("\n=== 5. GERACAO AUTORREGRESSIVA ===\n")
        inteiro prefixo[3]
        prefixo[0] = 9
        prefixo[1] = 22
        prefixo[2] = 12
        inteiro saida[16]
        inteiro g = ctx_gerar(w16, b16, prefixo, 3, 10, saida)
        se (g > 0)
        {
            inteiro parada = 0
            se (saida[g - 1] == 24)
            {
                parada = 1
            }
            ctx_imprimir_geracao(saida, g, 3, parada)
        }
        senao
        {
            escreva("ERRO_GERACAO=", 0 - g, "\n")
        }
'@

$source = (Read-DemoFragment "src/tokenizador.por") + "`n`n" +
    (Read-DemoFragment "src/corpus.por") + "`n`n" +
    (Read-DemoFragment "src/contexto.por")

$program = "programa`n{`n" + $source + "`n`n" +
    "    funcao inicio()`n    {`n" +
    ($declarations -join "`n") + "`n`n" +
    $driver + "`n    }`n}`n"

$outDir = Join-Path $root $OutputRoot
if (-not (Test-Path -LiteralPath $outDir)) {
    [void](New-Item -ItemType Directory -Path $outDir)
}
$porPath = Join-Path $outDir "demo.por"
[IO.File]::WriteAllText($porPath, $program, (New-Object System.Text.ASCIIEncoding))

Write-Host "=== Demonstracao: texto -> tokenizacao -> treino -> geracao ==="
Write-Host ("Interpretador: {0}" -f $interpreter)
Write-Host ("Corpus:        {0}" -f $CorpusPath)
Write-Host ""

$epilogue = "`nPrograma finalizado`r`n`r`nPressione ENTER para continuar`r`n"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $interpreter
$psi.Arguments = '"' + $porPath + '"'
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.StandardInput.WriteLine(' ')
$proc.StandardInput.Close()
$output = $proc.StandardOutput.ReadToEnd()
$errorOutput = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if ($output.Length -gt 0 -and [int][char]$output[0] -eq 0x0C) {
    $output = $output.Substring(1)
}
if ($output.EndsWith($epilogue)) {
    $output = $output.Substring(0, $output.Length - $epilogue.Length)
}

if ($errorOutput.Length -gt 0) {
    Write-Host "--- stderr ---"
    Write-Host $errorOutput
}
Write-Host $output

if ($errorOutput.Length -gt 0 -or $output -notmatch 'ACERTOS_NO_TREINO=') {
    Write-Host "DEMO_STATUS=FALHA"
    exit 1
}

Write-Host ""
Write-Host "DEMO_STATUS=OK"
Write-Host "Observacao: os acertos acima sao no proprio conjunto de treino (memorizacao)."
exit 0
