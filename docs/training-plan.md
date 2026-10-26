# Plano de execução — Primeiro treinamento supervisionado (M5)

- **Status:** executado e verificado em 26/10/2026. E0–E7 concluídas; nenhum gate
  G1–G9 disparado; AC1–AC22 verificados. Evidências na §13 e na
  `docs/training-spec.md` §18.
- **Especificação:** `docs/training-spec.md` v1.0.0 (congelada em E0; valores
  canônicos inalterados).
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0).
- **Fora de escopo:** Transformer, atenção, contexto, geração, softmax,
  embeddings treináveis, commit e push.

## 1. Estado de partida

Verificado nesta missão, antes de escrever este plano:

| Item | Estado |
| --- | --- |
| `HEAD` | `d7175dd6c7ccdbac5b3f669038f94ca29140f519` |
| Branch | `main`, 0 ahead / 0 behind de `origin/main` |
| Árvore de trabalho | limpa; apenas `docs/training-spec.md` e `docs/training-plan.md` não rastreados |
| Suíte | `scripts/test.ps1` = **58 PASS / 0 FAIL**, exit `0` (executado agora) |
| M1 bytes | `scripts/verify-bytes.ps1` = **21/21**, exit `0` (executado agora) |
| M3 bytes | `scripts/verify-embedding-bytes.ps1` = **19/19**, exit `0` (executado agora) |
| M4 bytes | `scripts/verify-network-bytes.ps1` = **22/22**, exit `0` (executado agora) |
| Autoteste | `scripts/test.ps1 -SelfTest` = **0 PASS / 1 FAIL intencional**, exit `1` (executado agora) |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |
| Custo por caso | ~1,3 s; suíte de 70 casos ≈ 90 s |

Hashes de `HEAD` dos arquivos que **não podem** mudar (baseline de AC19):

```
src/tokenizador.por                    6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f
src/embeddings.por                     6f06aa820d163d3c1636383803b86105bf54cd85
src/rede.por                           fa9367a79bd2aefc373d30a94cfca2b7c86d9958
scripts/build-tests.ps1                1cfb01202586a83c4d7ec08ff738a8e90fb19044
scripts/verify-bytes.ps1               851afbbad494778f019bf2ce70e82b0b575ab443
scripts/build-embedding-tests.ps1      94d1a3819b76b4d614f4422bf00b0cd2c008daaf
scripts/verify-embedding-bytes.ps1     4f3aa68e499a9dc3289d22ebae5b8d1c18086651
scripts/build-network-tests.ps1        998e91b2896e9ec40bc1814990a0a53ae740fb3e
scripts/verify-network-bytes.ps1       1f46800852fed34d840206ca97bc84badd109b31
```

`scripts/test.ps1` em `HEAD` tem hash `a688b6dab60e485952a8e9d4e4158898e4ababbe`.
Ele muda por desenho (bloco aditivo), mas o restante do arquivo deve permanecer
idêntico. O hash é capturado em E0 e reconferido em E7 por `git diff`.

Comandos de referência:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-embedding-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-network-bytes.ps1
```

## 2. Restrições do runner

Comprovadas por leitura de `scripts/test.ps1` e pelas missões anteriores:

1. **Exit code do interpretador é sempre 0.** Falhas de execução precisam ser
   detectadas por texto; por isso todos os casos de treino usam saídas normais.
2. **stdout começa com form feed (`0x0C`).** `Normalize-Output` remove um `\f` inicial.
3. **Epílogo de sucesso:** `"\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n"`.
   O corpo usa LF; o epílogo usa CRLF.
4. **`Normalize-Output` remove o epílogo, um `\n` final e aplica `.Trim()`.** A
   comparação é `-ceq` (case-sensitive). `.expected` não pode ter `\n` final nem
   espaços nas pontas.
5. **Entrada padrão:** o runner envia `" "` e fecha; nenhum teste pode ler teclado.
6. **Casos gerados** são descobertos por `Get-ChildItem -Filter *.expected` em um
   diretório próprio, ordenados por nome, e anexados a `$testCases`.
7. **Autoteste** substitui `$testCases` por um único caso que deve falhar; os blocos
   de geração ficam dentro de `if (-not $SelfTest)`.
8. **`scripts/test.ps1` tem BOM UTF-8 e não termina em LF** (último byte `0x7D`). A
   edição aditiva precisa preservar ambos.
9. **Nomes de caso** não podem colidir entre M0, M1, M3, M4 e M5; o prefixo `trn_`
   garante isso.
10. **Diretórios de teste independentes** (`temp/tests`, `temp/embedding-tests`,
    `temp/network-tests`, `temp/training-tests`) para que `verify-bytes.ps1` continue
    varrendo apenas `temp/tests`.

## 3. Decisões de execução

Herdadas da spec (§17) e fixadas para a implementação:

| ID | Decisão |
| --- | --- |
| D1 | camada afim 4→25; sem ativação, sem softmax |
| D2 | MSE sobre logits; sem `exp`, sem `log`, sem `Matematica` |
| D3 | estado `inteiro w16[100]` + `inteiro b16[25]`, unidades de 1/16 |
| D4 | embeddings congelados; `treino_emb16` recalcula a fórmula da M3 |
| D5 | SGD por exemplo, ordem `0..n−1`, `η = 1/4` |
| D6 | quantização no novo valor, meio para longe de zero, após cada parâmetro |
| D7 | `E = 5`; `epocas` parametrizável em `1..256` |
| D8 | conjunto `9→12, 12→13, 13→14, 14→24` |
| D9 | saída sempre inteira; `L = S/524288` não é impresso |
| D10 | erros `1..5`; precedência `n → épocas → ids → parâmetros` |
| D11 | sem rollback em `ESTOURO_NUMERICO` |
| D12 | oráculo inteiro independente + conferência racional exata |
| D13 | prefixos `treino_`/`TREINO_`; módulo sem dependência de M1/M3/M4 |
| D14 | nenhum commit/push/tag/remote |

## 4. Arquivos

### 4.1 Autorizados

| Arquivo | Ação | Conteúdo |
| --- | --- | --- |
| `src/treino.por` | criar | fragmento ASCII: constantes, validadores, forward inteiro, `executar`, impressoras |
| `scripts/build-training-tests.ps1` | criar | gera 12 `.por` + 12 `.expected` em `temp/training-tests/` |
| `scripts/verify-training-bytes.ps1` | criar | verificação de bytes + oráculo independente (V1–V12) |
| `scripts/test.ps1` | alterar (aditivo) | quarto bloco de geração/anexo dentro de `if (-not $SelfTest)` |
| `docs/training-spec.md` | criar agora; atualizar evidências em E7 | especificação e resultados observados |
| `docs/training-plan.md` | criar agora; atualizar evidências em E7 | este plano e log de execução |

### 4.2 Proibidos

`src/tokenizador.por`, `src/embeddings.por`, `src/rede.por`, `tests/*`,
`scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`,
`scripts/build-embedding-tests.ps1`, `scripts/verify-embedding-bytes.ps1`,
`scripts/build-network-tests.ps1`, `scripts/verify-network-bytes.ps1`, `README.md`,
`AGENTS.md`, `.gitignore`, qualquer arquivo em `.git/`.

### 4.3 Artefatos descartáveis (ignorados)

`temp/e0-trn/` (sondas), `temp/training-tests/` (casos gerados) e
`temp/e0-trn/manual/` (drivers de scratch). Nada é rastreado; `git status --short`
deve continuar mostrando apenas os arquivos autorizados.

## 5. E0 — Sondas e congelamento

**Objetivo:** provar ou refutar as suposições da spec §3, §6 e §9 antes de escrever
o módulo.

**Arquivos permitidos:** apenas `temp/e0-trn/*.por` e `temp/e0-trn/*.ps1`.

**Procedimento:** um driver por sonda, executado com o mesmo runner
(`portugol-console.bat`, stdin `" "`). Cada saída é capturada em texto bruto e
anotada no log (§13).

### 5.1 Sondas

| ID | Programa mínimo | Observação esperada | Se falhar |
| --- | --- | --- | --- |
| P1 | `escreva(100*4096*4096)` e a soma de 100 quadrados de 4096 | `1677721600`, sem estouro | G2 |
| P2 | `7/2`, `-7/2`, `(-7)%3`, `7%(-3)`, `0/2` | divisão truncando para zero; `%` com sinal do dividendo | G1 |
| P3 | `r(512,1024)`, `r(-512,1024)`, `r(511,1024)`, `r(-511,1024)`, `r(32,64)`, `r(-32,64)` | `1, -1, 0, 0, 1, -1` | G9 |
| P4 | `inteiro w[100]`, `inteiro b[25]`; função que muta e chamador que lê | mutação visível | G3 |
| P5 | função com 7 parâmetros (2 arrays + 4 inteiros + 1 array) | compila e executa | G3 |
| P6 | função `inteiro` com `retorne` dentro de `se` | retorno correto | BLOQUEAR |
| P7 | `const inteiro A = 16` e `const inteiro B = 1024` | aceitos; expressão em `const` rejeitada | G7 |
| P8 | 25 linhas `PARAM16=y a b c d e` (~40 caracteres) | sem truncamento | G4 |
| P9 | `escreva(-3696)`, `escreva(1677721600)` | sem separador de milhar e sem expoente | G4 |
| P10 | laço 16×256×25×4 com multiplicações inteiras | termina em < 10 s | G5 |
| P11 | concatenar tokenizador + embeddings + rede + treino + driver | compila; `id_do_campo` visível | G6 |
| P12 | `real w = 1 / 16.0`, `real v = -36 / 16.0`; imprimir | `0.0625`, `-2.25` | G8 |
| P13 | copiar `w16` para `copia[100]` com laço e comparar | `IGUAL=1` | BLOQUEAR |
| P14 | medir BOM/CRLF/EOF e ASCII dos fragmentos | ASCII puro, sem BOM, LF | corrigir no builder |

### 5.2 Critérios de conclusão de E0

- Todas as 14 sondas executadas e registradas.
- Formato A (linhas inteiras) confirmado; nenhuma mudança de layout.
- Se qualquer valor canônico mudar, a spec sobe para `v1.1.0` **antes** de E1.
- Tabela de gates preenchida com o resultado real.

### 5.3 Gates

| Gate | Gatilho | Ação pré-aprovada |
| --- | --- | --- |
| G1 | P2: divisão/`%` negativos diferentes | já evitado: `r` usa `\|num\|` e sinal explícito; registrar |
| G2 | P1 estoura 32 bits | baixar `TREINO_LIMITE` para 24 (limite de S = 473.497.600; canônico máx. 11), atualizar spec e testes |
| G3 | P4/P5 falham | estado único `inteiro estado[125]` (W `0..99`, b `100..124`) e API de um array; spec `v1.1.0` |
| G4 | P8/P9 truncam | quebrar `PARAM16` em duas linhas (`PARAM16W`/`PARAM16B`); regenerar tudo |
| G5 | P10 > 10 s | baixar `TREINO_MAX_EPOCAS` para 64; atualizar §12 e `trn_limites` |
| G6 | P11 colide | renomear com `treino_`/`TREINO_` |
| G7 | P7: `const` com expressão | manter literais (já previsto) |
| G8 | P12 formata diferente | não imprimir `real` no treino; composição compara inteiros |
| G9 | P3 diverge | corrigir `r`; se impossível, **BLOQUEAR** |
| G10 | P14 com BOM/CRLF | corrigir o builder; não aceitar `.por` com CR |

## 6. Etapas E1–E7

Cada etapa termina com um driver de scratch em `temp/e0-trn/manual/` (não rastreado)
e só avança quando a saída bate com o oráculo. Nenhum teste do repositório é
alterado antes de E6.

### E1 — Esqueleto, constantes, validadores e estado

- **Arquivos:** `src/treino.por` (novo).
- **Conteúdo:** cabeçalho comentado, 16 constantes literais, `treino_id_valido`,
  `treino_n_valido`, `treino_epocas_validas`, `treino_params_validos`,
  `treino_validar`, `treino_inicializar`, `treino_imprimir_config`,
  `treino_imprimir_param16`, `treino_imprimir_estado`, `treino_imprimir_alterados`,
  `treino_imprimir_validacao`.
- **Teste local:** driver que inicializa e imprime `INFO`, as 25 linhas
  `PARAM16`, `MAXIMO16=12 4`, `ALTERADOS_W=0`, `ALTERADOS_B=0` e as fronteiras
  de validação.
- **Saída de controle:** `S0` ainda não é calculado; a tabela inicial deve ser
  idêntica à spec §4.2.

### E2 — Forward, perda e acurácia

- **Conteúdo:** `treino_emb16`, `treino_z256`, `treino_delta256`, `treino_argmax`,
  `treino_perda_escalada`, `treino_acertos`, `treino_imprimir_avaliacao`.
- **Teste local:** `PERDA=3674036`, `ACERTOS=0`, `PRED=10 19 6 11`;
  `n=1` → `1298270`; `n=16` → `14696144`.
- **Gate G2** já resolvido em E0.

### E3 — Quantização e primeira época

- **Conteúdo:** `treino_div_arredondada`, `treino_executar` (uma época),
  `treino_imprimir_historico`.
- **Teste local:** `HISTORICO=3674036 428488`, `PERDA=428488`, `ACERTOS=2`,
  `PRED=14 1 14 24`, linhas 9/12/13/14 da época 1.
- **Ponto crítico:** o `δ256` é congelado por exemplo antes das 5 atualizações da linha.

### E4 — Cinco épocas, estado final e alterações

- **Conteúdo:** laço de épocas completo, `historico`, `MAXIMO16`, `ALTERADOS_*`.
- **Teste local:** `HISTORICO` de 6 valores; tabela final da spec §8.3;
  `ALTERADOS_W=91`, `ALTERADOS_B=23`; época 6 sem mudanças.
- **Verificação de ponto fixo:** rodar 6 épocas e comparar as duas últimas tabelas.

### E5 — Gradiente e restauração

- **Conteúdo:** `treino_calcular_gradiente`,
  `treino_imprimir_gradiente`.
- **Teste local:** `GRAD_EXATOS=125`, `GRAD_TOTAL=125`, `GRAD_SOMA=-8960`;
  `MAXIMO16=12 4` depois do teste (estado restaurado).
- **Ponto crítico:** avaliar apenas a linha afetada; `h = 1`; comparar com `4G`.
- **Guarda:** `treino_imprimir_gradiente` valida `n → ids → limite 47` e emite
  `ERRO=PARAMETROS_INVALIDOS` (uma linha, sem saída parcial) se `|W16| > 47` ou
  `|b16| > 47`. O driver cobre a rejeição com um estado em 48; o estado canônico
  cobre a aceitação.

### E6 — Erros, limites, determinismo, composição e reset

- **Conteúdo:** `treino_materializar`, guarda de `y` em
  `treino_imprimir_param16`, os 6 cenários de `trn_erros`, `trn_limites`,
  `trn_determinismo_a/b`, `trn_composicao`, `trn_reinicializacao`.
- **Arquivos:** `scripts/build-training-tests.ps1` e o bloco aditivo em
  `scripts/test.ps1`.
- **Teste local:** 12/12 casos; suíte **70 PASS / 0 FAIL**.

### E7 — Verificador e regressão final

- **Arquivos:** `scripts/verify-training-bytes.ps1`.
- **Conteúdo:** V1–V12 da spec §13; re-derivação de `S` a partir das tabelas
  impressas; comparação A/B.
- **Teste local:** `verify-training-bytes` ≥ 12/12; M1 21/21, M3 19/19, M4 22/22;
  autoteste 0 PASS / 1 FAIL exit 1.
- **Fechamento:** hashes de `HEAD` conferidos, `git diff --stat` restrito aos
  arquivos autorizados, evidências registradas.

## 7. Matriz de testes

### 7.1 Casos e saídas esperadas

Todos os drivers começam com estado canônico (`treino_inicializar`) e usam o
conjunto `entradas = {9,12,13,14}`, `alvos = {12,13,14,24}`, salvo indicação.

| # | Caso | Setup | Saída esperada (resumo) |
| ---: | --- | --- | --- |
| 1 | `trn_info` | validadores de fronteira; `r` | `INFO=TREINO 16 256 125 100` + 6 linhas de config (`TAXA` a `ORDEM`); `N0/N17 → EXEMPLOS_INVALIDOS`; `E0/E257 → EPOCAS_INVALIDAS`; `ID-1/ID25 → ID_INVALIDO`; `Y-1/Y25 → SAIDA_INVALIDA`; tabela `r` |
| 2 | `trn_perda_inicial` | init | `PERDA=3674036`, `ACERTOS=0`, `PRED=10 19 6 11`; 25 `PARAM16`; `MAXIMO16=12 4`; `ALTERADOS_W=0`, `ALTERADOS_B=0` |
| 3 | `trn_gradiente` | init; mutar cópia para 48 | `GRAD_EXATOS=125`, `GRAD_TOTAL=125`, `GRAD_SOMA=-8960`; `MAXIMO16=12 4`; `PARAM16=12 -3 2 7 12 -1`; `ERRO=PARAMETROS_INVALIDOS` na guarda 48 |
| 4 | `trn_epoca_1` | 1 época | `HISTORICO=3674036 428488`; `PERDA=428488`; `ACERTOS=2`; `PRED=14 1 14 24`; quatro linhas de interesse `PARAM16=9 1 1 9 -10 0`, `12 5 -5 -1 5 3`, `13 -1 6 -1 3 0`, `14 8 0 -5 0 4`; 113 parâmetros mudaram nesta época |
| 5 | `trn_cinco_epocas` | 5 épocas | `HISTORICO=3674036 428488 107796 41544 30998 27804`; `PERDA=27804`; `ACERTOS=4`; `PRED=12 13 14 24` |
| 6 | `trn_estado_final` | 5 épocas | 25 `PARAM16` da spec §8.3; `MAXIMO16=11 6`; `ALTERADOS_W=91`; `ALTERADOS_B=23` |
| 7 | `trn_erros` | 6 cenários; estouro com o estado da spec §11.4 | `EXEMPLOS_INVALIDOS`, `EPOCAS_INVALIDAS`, `ID_INVALIDO` (2×), `PARAMETROS_INVALIDOS`, `ESTOURO_NUMERICO`; `INTACTO=OK` nos 5 primeiros; estouro resulta em `b16[5]=62` |
| 8 | `trn_limites` | `n=1` e `n=16`, 1 época | `n=1`: `HISTORICO=1298270 31576`, `ACERTOS=1`, `PRED=12`; `n=16`: `HISTORICO=14696144 123992`, `ACERTOS=16`, `PRED` com 16 IDs |
| 9 | `trn_determinismo_a` | 5 épocas | `HISTORICO` + `PERDA` + `ACERTOS` + `PRED` + 25 `PARAM16` + `MAXIMO16` |
| 10 | `trn_determinismo_b` | idêntico ao A | bytes idênticos ao A |
| 11 | `trn_composicao` | tokenizador + embeddings + rede; treina 5 épocas e materializa | `IDS=9 12 13 14 24` (de `tokenizar`); `ALVOS=12 13 14 24`; `EMB16=OK`; `ACERTOS=4`; `ARGMAX_REDE=12 13 14 24`; `ARGMAX_TREINO=12 13 14 24`; `COMPOE=OK` |
| 12 | `trn_reinicializacao` | mutar `w16[9][2]=40`; init de novo | `PARAM16=9 1 6 40 -9 -4`; depois `PARAM16=9 1 6 11 -9 -4`; `PERDA=3674036`; `ACERTOS=0`; `PRED=10 19 6 11` |

### 7.2 Contagem

| Suíte | Origem dos `.expected` | Antes | Depois |
| --- | --- | ---: | ---: |
| Base do runner | 5 casos literais de `test.ps1` (`smoke`, `division-by-zero`, `syntax-error`, `nonexistent-file`, `unavailable-interpreter`) | 5 | 5 |
| M1 tokenizador | `temp/tests` | 20 | 20 |
| M3 embeddings | `temp/embedding-tests` | 19 | 19 |
| M4 rede | `temp/network-tests` | 14 | 14 |
| **M5 treino** | `temp/training-tests` | 0 | **12** |
| **Total** | | **58** | **70** |

Contagem medida nesta missão: `20 + 19 + 14 = 53` arquivos `.expected` gerados,
mais os 5 casos literais do runner. O `unexpected-output` é o único caso do
autoteste e substitui `$testCases`; não entra na conta. O total 70 é o que
importa para AC2.

### 7.3 Regras dos arquivos esperados

- `.expected` sem `\n` final, sem espaços nas pontas, ASCII puro.
- `.por` ASCII puro, UTF-8 sem BOM, LF.
- Nenhum driver lê teclado, usa `aleatorio`, `tempo` ou biblioteca.
- Nenhum driver imprime `real` no caminho de treino.
- `trn_determinismo_a.expected` e `trn_determinismo_b.expected` são idênticos.

## 8. Integração em `scripts/test.ps1`

Inserir um quarto bloco **dentro** de `if (-not $SelfTest)`, imediatamente após o
`foreach` do bloco da rede (que termina na linha 265 em `HEAD`) e antes do `}` que
fecha o `if` (linha 266). O laço de execução começa depois, na linha 280, e não
deve ser tocado:

```powershell
# Gerar e anexar os casos de treinamento (M5). Diretorio proprio para nao
# interferir nas verificacoes de bytes das missoes anteriores.
$trainingBuilder = Join-Path $PSScriptRoot "build-training-tests.ps1"
try {
    & $trainingBuilder
} catch {
    Write-Host "ERROR: training test builder failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$trainingRoot = "temp/training-tests"
$trainingGenerated = @(Get-ChildItem -Path $trainingRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($trainingGenerated.Count -eq 0) {
    Write-Host "ERROR: no training test cases found in $trainingRoot" -ForegroundColor Red
    exit 1
}

foreach ($expectedFile in $trainingGenerated) {
    $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
    $testCases += @{
        Name = $caseName
        File = "$trainingRoot/$caseName.por"
        ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
    }
}
```

Regras:

- Não alterar nenhuma linha existente; apenas inserir o bloco.
- Preservar BOM UTF-8 e o último byte `0x7D` (sem `\n` final).
- Conferir com `git diff -- scripts/test.ps1` que só há linhas adicionadas.
- O autoteste não executa o bloco (já está dentro de `if (-not $SelfTest)`).

## 9. Builder e verificador

### 9.1 `scripts/build-training-tests.ps1`

Responsabilidades:

1. Gerar os 12 `.por` em `temp/training-tests/` por concatenação ASCII+LF de
   `src/tokenizador.por` (só no caso de composição), `src/embeddings.por` (só na
   composição), `src/rede.por` (só na composição) e `src/treino.por`, mais o driver.
2. Gerar os 12 `.expected` a partir do **oráculo inteiro** (não da execução do
   `.por`); linhas não numéricas (config, erros, composição) são literais
   transcritos da spec.
3. Embutir as tabelas canônicas (inicial, final, histórico, gradiente) como
   literais conferidos com a spec §8.
4. Recusar-se a gerar se um `.expected` tiver `\n` final, CR, BOM ou byte > 0x7E.
5. Não tocar em `temp/tests`, `temp/embedding-tests` ou `temp/network-tests`.

O oráculo do builder segue exatamente as fórmulas da spec §5 e §6, mas é escrito
independentemente do `.por` (sem reutilizar funções Portugol).

### 9.2 `scripts/verify-training-bytes.ps1`

Verificações V1–V12 (spec §13):

| ID | Verificação |
| --- | --- |
| V1 | `src/treino.por` ASCII, sem BOM, LF, sem `programa`/`inicio`, sem `Matematica`/`aleatorio`/`tempo`/`leia` |
| V2 | conjunto de casos exatamente os 12 esperados |
| V3 | bytes crus: `\f` inicial, carga ASCII com LF, epílogo exato |
| V4 | constantes de `INFO`/config |
| V5 | nos casos com tabela completa de 25 `PARAM16` (`trn_perda_inicial`, `trn_estado_final`, `trn_determinismo_a`, `trn_determinismo_b`), re-derivar `S` da tabela e comparar com `PERDA`; nos demais, conferir os literais congelados |
| V6 | `HISTORICO` estritamente decrescente em 0..5; `S5 = 27804` |
| V7 | `ACERTOS`/`PRED` coerentes com a tabela final |
| V8 | `ALTERADOS_*`, `MAXIMO16` coerentes |
| V9 | `GRAD_EXATOS = GRAD_TOTAL = 125`, `GRAD_SOMA = -8960` |
| V10 | `trn_determinismo_a.expected` ≡ `trn_determinismo_b.expected` |
| V11 | `trn_composicao` com IDs da M1 e 100 células da M3 |
| V12 | nenhum `.expected` com `\n` final, CR, BOM ou espaço nas pontas |

O verificador **não lê `.expected` para decidir valores**; usa os literais e a
re-derivação forward-only. `.expected` é lido apenas para conferências de bytes e
de igualdade (V3, V10, V12); nunca para determinar um valor numérico esperado.

### 9.3 Independência

- O builder calcula o esperado com um oráculo inteiro independente (terceira
  implementação, sem reutilizar o `.por`).
- O verificador recalcula `S` a partir das tabelas impressas completas
  (`trn_perda_inicial`, `trn_estado_final`, `trn_determinismo_a/b`), sem simular
  o treinamento; nos demais casos compara com os literais congelados.
- A derivação racional exata (Python) e o oráculo inteiro (PowerShell) desta
  missão são as duas primeiras implementações e estão registrados como evidência.
- Nenhum deles lê a saída do `.por` para produzir o valor esperado.

## 10. Matriz de aceitação

| AC | Comando | Resultado exigido |
| ---: | --- | --- |
| AC1 | `git status --short` | somente `docs/training-*.md`, `src/treino.por`, `scripts/build-training-tests.ps1`, `scripts/verify-training-bytes.ps1`, `scripts/test.ps1` |
| AC2 | `.\scripts\test.ps1` | `Passed: 70`, `Failed: 0`, exit `0` |
| AC3 | 3 verificadores | 21/21, 19/19, 22/22, exit `0` |
| AC4 | `.\scripts\test.ps1 -SelfTest` | `Passed: 0`, `Failed: 1`, exit `1` |
| AC5 | `.\scripts\verify-training-bytes.ps1` | ≥ 12/12, exit `0` |
| AC6 | inspeção do verificador | nenhum valor esperado derivado do `.por` |
| AC7 | `trn_cinco_epocas` | `HISTORICO=3674036 428488 107796 41544 30998 27804` |
| AC8 | cálculo | `27804/3674036 = 0,007568` |
| AC9 | `trn_epoca_1`/`trn_cinco_epocas` | `2/4` e `4/4` |
| AC10 | `trn_estado_final` | `ALTERADOS_W=91`, `ALTERADOS_B=23`, `MAXIMO16=11 6` |
| AC11 | re-derivação a partir de `trn_estado_final` | logits do alvo `-262→259`, `-157→222`, `107→239`, `-81→244` (spec §8.4) |
| AC12 | `trn_gradiente` | `125/125`, `GRAD_SOMA=-8960` |
| AC13 | `trn_info` | tabela `r` |
| AC14 | V10 | arquivos A/B idênticos |
| AC15 | `trn_composicao` | `EMB16=OK`, `ARGMAX_REDE` = `ARGMAX_TREINO` |
| AC16 | `trn_erros` | 6 códigos |
| AC17 | `trn_erros` | `INTACTO=OK` em 5 cenários |
| AC18 | `git hash-object src/embeddings.por` | `6f06aa82...` |
| AC19 | `git hash-object` dos 9 arquivos | hashes da §1 |
| AC20 | `git log -1`, `git status` | `HEAD` e branch inalterados |
| AC21 | leitura da spec/plano | evidências reais, sem placeholders |
| AC22 | V1 | sem `inclua`/`Matematica`/`aleatorio` |

### 10.1 Resultado medido

Todos os 22 critérios foram verificados na execução de 26/10/2026:

| AC | Obtido |
| ---: | --- |
| AC1 | `git status --short` restrito a `M scripts/test.ps1` e 5 arquivos novos autorizados |
| AC2 | 70 PASS / 0 FAIL, exit `0` (duas execuções consecutivas) |
| AC3 | 21/21, 19/19, 22/22, exit `0` |
| AC4 | 0 PASS / 1 FAIL, exit `1` |
| AC5 | 12/12 casos; verificador 23/23, exit `0` |
| AC6 | V5 re-deriva `S` das 25 linhas `PARAM16`; V12 só compara bytes |
| AC7 | `3674036 428488 107796 41544 30998 27804` |
| AC8 | `0,007567699391078367`; queda de `3.646.232` (`99,24323006089216%`) |
| AC9 | `0/4 → 2/4 → 4/4` |
| AC10 | `91 W + 23 b = 114/125`; `MAXIMO16=11 6` |
| AC11 | `-262→259`, `-157→222`, `107→239`, `-81→244`; margens `231/194/207/212` |
| AC12 | `125/125`, `GRAD_SOMA=-8960`, estado restaurado |
| AC13 | tabela `r` de `trn_info` com 15 linhas exatas |
| AC14 | A ≡ B nos `.expected` e nos bytes das duas execuções |
| AC15 | `IDS=9 12 13 14 24`, `EMB16=OK`, `ARGMAX_REDE` = `ARGMAX_TREINO` = `12 13 14 24`, `COMPOE=OK` |
| AC16 | 5 códigos de erro mais `SAIDA_INVALIDA`, com precedência correta |
| AC17 | 5 × `INTACTO=OK`; estouro preserva mutação parcial (`CODIGO=5`) |
| AC18 | `src/embeddings.por` = `6f06aa82...` (hash de `HEAD`) |
| AC19 | 9 hashes protegidos iguais a `HEAD`; `test.ps1` com 26 inserções e 0 remoções |
| AC20 | `main`, `HEAD d7175dd`, sem commit/push/tag |
| AC21 | este documento e a spec com valores medidos, sem placeholders |
| AC22 | V1 do verificador: sem `inclua`, `Matematica`, `aleatorio`, `tempo` ou `leia` |

## 11. Riscos e mitigações

| ID | Risco | Mitigação |
| --- | --- | --- |
| R1 | `S` pode estourar 32 bits se `TREINO_LIMITE` subir muito | prova em §3.3 mostra folga com 48; G2 reduz para 24 se a sonda P1 falhar |
| R2 | divisão/`%` negativos diferem | `r` usa `\|num\|` e sinal explícito; P2 documenta |
| R3 | limite de parâmetros do runtime | G3: estado único `estado[125]` |
| R4 | 256 épocas × 16 exemplos lentas | G5: reduzir máximo para 64 |
| R5 | corromper BOM/EOF de `test.ps1` | inserção aditiva + `git diff` + checagem de bytes |
| R6 | `.expected` com `\n` final | builder escreve sem `\n`; V12 |
| R7 | oráculo divergir do `.por` | V5 re-deriva `S` da tabela impressa nos casos com tabela completa |
| R8 | "ajustar" valores para passar | valores congelados na spec; mudança exige `v1.1.0` + regeneração + aprovação |
| R9 | confundir "executa" com "aprendeu" | AC7–AC12 exigem perda, acurácia, parâmetros e gradiente |
| R10 | generalizar o resultado para "LLM" | o relatório declara memorização de 4 pares |

## 12. Execução autônoma

A execução descrita nesta seção só começa **após aprovação explícita** deste plano.
Uma vez aprovada, as etapas E0–E7 correm sem aprovação intermediária, respeitando os
gates pré-aprovados.

Aprovação registrada em 26/10/2026; execução concluída conforme a §13.

### 12.1 Laço

1. Executar E0 e preencher os gates.
2. Implementar E1–E7 em ordem, com driver de scratch antes de cada caso oficial.
3. Rodar a suíte completa e os quatro verificadores ao fim de E6 e E7.
4. Registrar comando, saída e exit code no log (§13).
5. Só declarar **PRONTO** com AC1–AC22 verificados.

### 12.2 Regras

- **Sem aprovação intermediária:** G1–G10 são pré-aprovados; ao disparar um gate,
  aplicar a alternativa, registrar e continuar.
- **Orçamento por falha:** até 3 tentativas de correção; depois, se não houver
  fallback, parar como PARCIAL.
- **Escalonamento:** no máximo 2 gates de formato/layout na mesma execução; um
  terceiro exige parar e reportar.
- **Nunca** alterar valores canônicos, o oráculo ou os critérios para "fazer passar".
- **Nunca** tocar nos arquivos proibidos (§4.2).
- **Nunca** executar `git add`, `git commit`, `git push`, `git tag` ou `git remote`.
- **Sempre** registrar o comando e a saída bruta relevante antes de concluir.

### 12.3 Condições de parada imediata

1. `HEAD` diferente de `d7175dd`, branch diferente de `main` ou alteração fora
   dos arquivos autorizados (§4.1).
2. Gate G9 (divergência de arredondamento) disparado.
3. Necessidade de alterar arquivo proibido.
4. Falha de AC sem fallback após 3 tentativas.
5. Interpretador ausente ou instável.
6. Qualquer efeito colateral em `src/tokenizador.por`, `src/embeddings.por` ou
   `src/rede.por`.

### 12.4 Definição de pronto

**PRONTO** exige, simultaneamente:

- suíte 70/70, exit `0`;
- M1 21/21, M3 19/19, M4 22/22, exit `0`;
- autoteste 0 PASS / 1 FAIL, exit `1`;
- `verify-training-bytes` ≥ 12/12, exit `0`;
- 12 `.por` e 12 `.expected` presentes, A ≡ B;
- hashes de `HEAD` dos 9 arquivos protegidos inalterados;
- `git diff` restrito aos arquivos autorizados;
- nenhum commit/push;
- log de evidências preenchido.

Caso contrário: **PARCIAL** (com o que falta) ou **BLOQUEADO** (com o gate).

## 13. Registro de evidências

Preenchido na execução de 26/10/2026:

| Etapa | Comando | Exit | Resultado | Data |
| --- | --- | ---: | --- | --- |
| E0 | sondas P1–P14 em `temp/e0-trn/` | 0 | 14/14 PASS; nenhum gate disparado | 26/10/2026 |
| E1 | tabela inicial | 0 | 25 linhas canônicas, `MAXIMO16=12 4` | 26/10/2026 |
| E2 | `trn_perda_inicial` | 0 | `PERDA=3674036`, `ACERTOS=0`, `PRED=10 19 6 11` | 26/10/2026 |
| E3 | `trn_epoca_1` | 0 | `S1=428488`, `ACERTOS=2`, `PRED=14 1 14 24`, `93 W + 20 b` | 26/10/2026 |
| E4 | `trn_estado_final` / `trn_cinco_epocas` | 0 | `S5=27804`, `ACERTOS=4`, `91 W + 23 b`, `PONTO_FIXO=OK` | 26/10/2026 |
| E5 | `trn_gradiente` | 0 | `125/125`, `GRAD_SOMA=-8960`, estado restaurado | 26/10/2026 |
| E6 | `scripts/test.ps1` (×2) | 0 | 70 PASS / 0 FAIL nas duas execuções | 26/10/2026 |
| E7 | `verify-training-bytes` + regressão | 0 | 23/23; M1 21/21, M3 19/19, M4 22/22; autoteste exit `1` | 26/10/2026 |

Saídas brutas relevantes:

```
scripts/test.ps1                      Passed: 70  Failed: 0  exit 0
scripts/test.ps1 -SelfTest            Passed: 0   Failed: 1  exit 1
scripts/verify-bytes.ps1              Total: 21  falha(s): 0  exit 0
scripts/verify-embedding-bytes.ps1    Total: 19  falha(s): 0  exit 0
scripts/verify-network-bytes.ps1      Total: 22  falha(s): 0  exit 0
scripts/verify-training-bytes.ps1     Total: 23  falha(s): 0  exit 0
```

Detalhes adicionais:

- `temp/training-tests`: 12 `.por`, 12 `.expected`, todos ASCII sem BOM.
- `.expected` sem LF final, sem CR e sem espaços nas pontas (V12).
- `trn_determinismo_a` e `trn_determinismo_b`: bytes idênticos nos arquivos e nas
  saídas dos dois processos (V10).
- `scripts/test.ps1`: 26 inserções, 0 remoções; BOM UTF-8 e último byte `0x7D`
  preservados.
- Nenhum arquivo proibido alterado: hashes de `HEAD` conferem nos 9 arquivos
  protegidos.

## 14. Relatório final

```
VEREDITO: PRONTO

Suítes
  test.ps1 .................. 70/70 (exit 0, duas execuções)
  test.ps1 -SelfTest ........ 0/1 (exit 1)
  verify-bytes .............. 21/21 (exit 0)
  verify-embedding-bytes .... 19/19 (exit 0)
  verify-network-bytes ...... 22/22 (exit 0)
  verify-training-bytes ..... 23/23 (exit 0)

Aprendizado (conjunto fixo de 4 pares)
  S0 ........................ 3674036
  S5 ........................ 27804
  queda ..................... 99,24323006089216% (3.646.232)
  acurácia .................. 0/4 -> 2/4 -> 4/4
  parâmetros alterados ...... 114/125 (91 W + 23 b)
  gradiente ................. 125/125, soma -8960
  determinismo .............. A == B
  ponto fixo ................ época 6 sem mudanças (PONTO_FIXO=OK)

Arquivos
  criados ................... src/treino.por, scripts/build-training-tests.ps1,
                              scripts/verify-training-bytes.ps1
  docs ...................... docs/training-spec.md, docs/training-plan.md
  alterados ................. scripts/test.ps1 (26 linhas aditivas)
  protegidos ................ 9 hashes de HEAD inalterados

Desvios e gates
  Nenhum gate G1-G9 disparado. As únicas correções foram de implementação do
  próprio builder/verificador (arredondamento de PowerShell, precedência de
  concatenação em array e interpolação `$y:`), sempre com valores canônicos
  intactos.

Pendências
  Nenhuma pendência de escopo. Fora de escopo por contrato: commit, push,
  Transformer, atenção, geração, softmax e MISSION 006.

Limite declarado
  Memorização de 4 pares. Não é um modelo de linguagem treinado.
```

## Apêndice A — Ordem de implementação recomendada

```
E1  constantes + validadores + init + impressoras de estado
E2  emb16 + z256 + delta256 + argmax + perda + acertos
E3  r + executar(1 época) + historico
E4  executar(E) + estado final + alterados
E5  gradiente + restauração
E6  erros + limites + determinismo + composição + reset + builder + runner
E7  verificador + regressão + evidências
```

## Apêndice B — Checklist de revisão antes de E6

- [x] `treino.por` é ASCII puro, sem BOM, LF, sem `programa`/`inicio`.
- [x] Nenhuma função chama M1/M3/M4.
- [x] `TREINO_*` são literais inteiros.
- [x] `r` trata `±den/2` como meio para longe de zero.
- [x] `δ256` é congelado por exemplo antes das 5 atualizações da linha.
- [x] A guarda I2 é checada após cada escrita.
- [x] `treino_imprimir_gradiente` usa limite 47 e emite `ERRO=PARAMETROS_INVALIDOS` sem saída parcial.
- [x] `treino_executar` valida antes de mutar.
- [x] `treino_materializar` usa `/ 16.0`, nunca `/ 16`.
- [x] Nenhuma impressão de `real` no caminho de treino.
- [x] `trn_determinismo_a/b` usam o mesmo driver, em processos separados.
- [x] `test.ps1` preserva BOM e último byte `0x7D`.
