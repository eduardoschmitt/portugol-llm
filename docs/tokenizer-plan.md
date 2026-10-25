# Plano de implementação — MISSION 002: Tokenizador mínimo (M1)

- **Status:** MISSION 002 concluída em 2026-10-25 — E1–E7 implementadas e validadas; suíte com 25 casos (5 M0 + 20 gerados), 25 PASS / 0 FAIL. As sondas E0 estão registradas em §5.0.
- **Fonte de verdade:** `docs/tokenizer-spec.md` v0.2.1 (correção factual em §4; regras normativas inalteradas). Este plano não altera a especificação.
- **Base de leitura:** `AGENTS.md`, `README.md`, `docs/tokenizer-spec.md`, estrutura do repositório, `scripts/test.ps1` e artefatos do Portugol Studio instalado.
- **Aprovação:** decisões P1–P7 aprovadas em 2026-10-25 (ver §13). Execução das sondas E0 registrada em §5.0.
- **Data:** 2026-10-25.

## 1. Estado de partida verificado

### 1.1 Repositório

- Último commit: `0058b54 feat: complete M0 Portugol test infrastructure`.
- Há alterações não commitadas **pré-existentes** (`AGENTS.md`, remoções em `.agents/skills/`, `docs/tokenizer-spec.md` não rastreado, `AGENTS.md.bak-*`). Este plano não toca nesses arquivos.
- `src/` e `scripts/` contêm apenas `.gitkeep` e `test.ps1`.
- `tests/` contém `smoke.por`, `falha.por`, `syntax_error.por`, `unexpected.por`.
- Suíte M0 registrada no README: **5 PASS / 0 FAIL / EXIT_CODE=0**; autoteste: **0 PASS / 1 FAIL intencional / EXIT_CODE=1**.

### 1.2 Comportamentos de `scripts/test.ps1` que o plano precisa respeitar

| Comportamento | Consequência para o M1 |
| --- | --- |
| Casos são declarados explicitamente em `$testCases`; `$TestsRoot` só é impresso | Não há descoberta automática; os casos do tokenizador precisam ser registrados no script |
| Saída = stdout + stderr, com remoção do form feed, do epílogo (`Programa finalizado`, `Pressione ENTER...`), do `\n` final e `.Trim()` | O `\n` final e um eventual espaço final **não** são verificáveis pelo runner atual; são verificados byte a byte por `scripts/verify-bytes.ps1` (P1, executado na E6) |
| Sucesso compara com `-eq` (case-insensitive no PowerShell) | `IDS=` vs `ids=` não seria detectado; ver decisão D10/P2 |
| Erro compara por **substring** (`-match`) | Um teste de erro por `ExpectedError` aceitaria saída extra; os casos de erro devem usar `ExpectedOutput` |
| Interpretador sempre retorna `EXIT_CODE=0` | Só o conteúdo da saída serve de evidência |
| `test.ps1` exige **UTF-8 BOM** e usa finais de linha **LF** | Qualquer edição precisa preservar o BOM (`EF BB BF`) e não introduzir CRLF |
| Caminhos dos casos são relativos | A suíte continua exigindo execução a partir da raiz do repositório |

### 1.3 Evidências do ambiente

Inspeção somente leitura dos artefatos instalados em `C:\ProgramData\UNIVALI\Portugol Studio`:

- `aplicacao/lib/portugol-core-2.7.5.jar` contém `br/univali/portugol/nucleo/bibliotecas/Texto.class`, cujo constant pool expõe: `numero_caracteres`, `obter_caracter`, `extrair_subtexto`, `caixa_alta`, `caixa_baixa`, `substituir`, `pesquisar`, `preencher_a_esquerda`.
- `exemplos/bibliotecas/texto/caracteres.por` usa índice **0-based** em `cadeia`: `para (inteiro indice = 0; indice <= tx.numero_caracteres(numero) - 1; indice++)` e `tx.obter_caracter(numero, indice)`.
- `exemplos/bibliotecas/graficos/qr_code.por` declara `funcao cadeia codificar_par_de_caracteres(caracter primeiro_caracter, caracter segundo_caracter)` — logo `caracter` é tipo válido de parâmetro e literais como `'0'`, `'?'` existem.
- `ajuda/topicos/linguagem_portugol/declaracoes/funcao.html`: omitir o tipo de retorno equivale a `vazio`; `retorne` sem valor é permitido nesse caso.
- `ajuda/topicos/linguagem_portugol/expressao/relacional.html`: o operador de igualdade é `==`; `!=` é diferença.
- `tests/smoke.por` usa `escreva` com múltiplos argumentos e `\n` explícito.

Essas inspeções foram confirmadas (ou substituídas) por medições reais na etapa E0; os resultados, comandos e bytes observados estão em §5.0.

## 2. Ambiguidades e contradições (identificadas antes das decisões)

| ID | Onde | Problema | Decisão proposta | Status |
| A1 | spec §1, §2, §8; "fora de escopo: leitura de arquivos, entrada interativa" | A spec define entrada como "um texto", mas proíbe toda forma de I/O e não diz como o texto chega ao tokenizador. Sem isso o contrato não é testável ponta a ponta. | A entrada do M1 é um **parâmetro `cadeia`** de uma função; programas de teste injetam literais. Nenhum I/O em `src/`. | Aprovado (P3) |
| A2 | spec §4 vs. §1.1/AC13 | A redação da v0.2.0 ("o limite de entrada já o limita a 15.361 caracteres no pior caso (16.384 − 1.023 separadores)") estava **errada**. 15.361 só vale quando existem exatamente 1.024 tokens. Uma entrada de 16.384 caracteres **sem separadores** é aceita por §1.1 e produz um único campo de 16.384 caracteres. O máximo real de um campo é 16.384. | Seguir o fluxo normativo §1.1 (limite de caracteres, depois limite de tokens). Não há efeito na saída observável (campo longo = `UNK`), apenas no dimensionamento interno. | Aprovado (P6) — spec corrigida em v0.2.1 |
| A3 | spec §4 ("16.384 caracteres") | "Caractere" não é definido. `numero_caracteres` é `String.length()` do Java, isto é, unidades de código UTF-16; pares substitutos contam 2. | Adotar a unidade do runtime. Testes do M1 usam apenas ASCII e Latin-1 (1 unidade por caractere). Unicode fora do BMP fica documentado como não coberto. | Aprovado (P4) |
| A4 | spec §5 vs. README §"limitações" | O interpretador prefixa form feed e acrescenta epílogo; portanto o stdout do processo nunca é só a linha do contrato. Além disso, o runner remove `\n` final e aplica `.Trim()`. | O contrato vale para a linha emitida **antes** do epílogo. `\n` exato, ausência de espaço final, ausência de CR na carga e epílogo são verificados por captura bruta (`scripts/verify-bytes.ps1`, executado na E6). | Aprovado (P1) |
| A5 | `scripts/test.ps1` linha 124 | Comparação `-eq` é case-insensitive; AC15/AC16 exigem maiúsculas. | Trocar apenas a comparação de sucesso para `-ceq`, sem tocar em normalização, casos existentes ou autoteste. | Aprovado (P2) |
| A6 | `scripts/test.ps1` linhas 131-139 | `ExpectedError` valida por substring, então `ERRO=TOKENS_DEMAIS lixo` passaria. AC16 exige formato exato. | Casos de erro usam `ExpectedOutput` (comparação exata após normalização), não `ExpectedError`. Isso não altera o runner. | Não |
| A7 | infraestrutura de testes | Não há mecanismo verificado para um programa `.por` reutilizar funções de outro arquivo; `inclua biblioteca` serve a bibliotecas instaladas, não a arquivos locais. | `src/tokenizador.por` é um **fragmento** só de funções; `scripts/build-tests.ps1` gera cada `.por` de teste concatenando fragmento + driver em `temp/tests/` (ignorado pelo Git). | Não |
| A8 | ambiente | Escapes em literais **de cadeia**: medido que `\t`, `\r`, `\"` funcionam; `\uXXXX` e `\015` **não existem** (erro de sintaxe). Em literais **de `caracter`**, `'\t'`, `'\r'` e `'\n'` produzem `\` (0x5C), sem erro. | Usar apenas `\n`, `\t`, `\r`, `\"`, `\\` em strings. Nunca usar escape em literal de `caracter`. Obter TAB/CR/LF via `tx.obter_caracter("\t", 0)` e equivalentes. | Resolvido (P7) |
| A9 | ambiente | Medido: `.por` em **UTF-8 sem BOM** é lido corretamente (`não` = 3 unidades, `função` = 6, `ã` sai como 0xE3). O mesmo arquivo em CP1252 é lido como U+FFFD e sai como `?` (0x3F), **sem erro**. | Todo `.por`, inclusive os gerados, é escrito em UTF-8 sem BOM. O builder valida os bytes `C3 A3` do literal acentuado. | Resolvido (P7) |
| A10 | spec §3.3 | O vocabulário é todo ASCII; qualquer acento no fonte do tokenizador seria acidental. | `src/tokenizador.por` deve permanecer ASCII puro (verificável por checagem de bytes). | Não |
| A11 | spec §4 ("não há limite próprio de comprimento por token") | Guardar campos exigiria buffer de até 16.384 caracteres; a spec não define esse buffer. | Não materializar campos: comparar por índices `[ini, fim]` direto no texto. Nenhum buffer de campo. | Não |
| A12 | AC19 ("25..63 não podem ser reutilizados") | Não é observável em runtime (nada é emitido nessa faixa). | Cobertura por AC7 (tabela completa em ordem) + revisão da tabela de 24 entradas. Sem teste estático frágil. | Não |
| A13 | ambiente | Medido: igualdade é `==`. Usar `=` dentro de expressão é **erro de sintaxe** ("A expressão não foi finalizada corretamente... Insira o caracter ')'"). | Toda comparação usa `==` / `!=`; `=` fica restrito a atribuição. | Resolvido (P7) |
| A14 | ambiente | Medido: índice igual ao tamanho do vetor (`ids[1024]`) gera erro de execução em stderr, `EXIT_CODE=0`, stdout só com form feed e epílogo, sem IDs parciais. | Verificar `total = 1024` **antes** de gravar; nunca indexar com `total`. Coberto por D14. | Resolvido (P7) |

Todas as pendências P1–P7 foram aprovadas em 2026-10-25; os itens A8, A9, A13 e A14 já estão fechados por medição na E0 (§5.0).

## 3. Decisões de projeto

- **D1 — Entrada por parâmetro.** `funcao tokenizar(cadeia texto)` (tipo de retorno omitido = `vazio`) emite a linha diretamente com `escreva`. Sem `leia`, sem arquivo, sem `stdin`.
- **D2 — Fragmento, não programa.** `src/tokenizador.por` contém `inclua biblioteca Texto --> tx` e apenas funções; não é executável sozinho. Isso é intencional e deve ser documentado no cabeçalho do arquivo para evitar falso diagnóstico.
- **D3 — Geração de testes.** `scripts/build-tests.ps1` é a única fonte de verdade de (construção da entrada + saída esperada) e gera `temp/tests/<nome>.por` e `temp/tests/<nome>.expected`. Artefatos são descartáveis; `temp/` já é ignorado pelo Git. Nada é duplicado no repositório.
- **D4 — Emissão direta.** Nada de retornar `cadeia` gigante nem vetor de `cadeia`. A saída é escrita com `escreva("IDS=")`, `escreva(" ", id)` entre tokens e `escreva("\n")` no fim. Isso evita construtos não verificados e mantém a linha única.
- **D5 — Buffer de IDs, uma passada.** `inteiro ids[1024]` local: os IDs são acumulados e só emitidos ao final. O 1.025º campo dispara `ERRO=TOKENS_DEMAIS` antes de qualquer escrita, garantindo "sem saída parcial" sem segunda varredura. É o desenho que a própria spec pressupõe (§8: "manter até 1.024 inteiros").
- **D6 — Biblioteca `Texto` (embutida no interpretador).** Uso restrito a `numero_caracteres` e `obter_caracter`, ambos medidos em E0. Não é dependência externa: acompanha o Portugol Studio instalado, sem download nem instalação. `caixa_alta`, `caixa_baixa`, `substituir`, `pesquisar` e `extrair_subtexto` ficam **proibidos** por poderem introduzir transformação ou semântica de fatiamento não necessária.
- **D7 — Comparação caractere a caractere.** `mesmo_conteudo` primeiro iguala comprimentos (`fim - ini + 1` vs. `numero_caracteres(palavra)`) e só então compara com `!=`, com saída antecipada na primeira diferença. A tabela é uma cadeia de 24 `se` na ordem da spec, cada um retornando o ID literal; fallback `retorne 0`. Comparações usam `==` / `!=` (A13).
- **D8 — Delimitadores explícitos.** TAB, CR e LF são obtidos uma vez por chamada com `tx.obter_caracter("\t", 0)`, `("\r", 0)` e `("\n", 0)` e passados a `eh_separador(caracter c, caracter tab, caracter cr, caracter lf)`; o espaço é comparado com o literal `' '`. Nenhum escape é usado em literal de `caracter` (A8). Nenhum outro caractere separa; nenhuma função de split é usada.
- **D9 — Ordem normativa.** Comprimento → campos → limite de tokens → mapeamento → serialização, exatamente como §1.1. Erros retornam antes de qualquer `IDS=`.
- **D10 — Testes como contrato observável.** Cada caso é um `.por` que chama `tokenizar` com uma entrada e imprime só a linha do contrato. A comparação é exata (`ExpectedOutput`) e passa a usar `-ceq` (P2 aprovado).
- **D11 — Vocabulário congelado.** 24 entradas, IDs `1..24`, sem renumeração. `0` só aparece como fallback `UNK`. `25..63` nunca são emitidos nesta versão.
- **D12 — Sem transformação textual.** Nenhuma conversão de caixa, remoção de acento, trim de pontuação, normalização Unicode ou truncamento, em nenhum ponto do fluxo (AC20).
- **D13 — Fonte em UTF-8 sem BOM.** Todos os `.por` (inclusive gerados) são escritos em UTF-8 sem BOM. O builder verifica os bytes do literal acentuado para impedir regressão silenciosa (A9).
- **D14 — Guarda de índice.** Antes de gravar qualquer ID, verificar se `total` já é 1024; nesse caso emitir `ERRO=TOKENS_DEMAIS` e encerrar. O índice 1024 nunca é usado (A14).

## 4. Arquivos criados ou modificados

| Arquivo | Ação | Etapa | Propósito |
| --- | --- | --- | --- |
| `docs/tokenizer-plan.md` | criar | entrega atual | Este plano, incluindo as evidências da E0 em §5.0 |
| `docs/tokenizer-spec.md` | modificar (feito) | preparação | Correção factual de §4 e versão v0.2.1; nenhuma regra normativa alterada |
| `src/tokenizador.por` | criar | E1–E4 | Fragmento com `eh_separador`, `mesmo_conteudo`, `id_do_campo` e `tokenizar` (E1–E3); E4 acrescenta o limite de tokens |
| `scripts/build-tests.ps1` | criar | E1 | Gera `temp/tests/*.por` (UTF-8 sem BOM) + `*.expected` a partir do fragmento |
| `scripts/test.ps1` | **modificar** | E1, E6 | Invocar o builder, anexar casos gerados, guarda de suíte vazia, `-ceq` (P2) |
| `scripts/verify-bytes.ps1` | criar (P1 aprovado) | E6 | Captura bruta: offset 0, ASCII, LF/CR, epílogo e tabela de 24 entradas; criado e executado na E6 |

Não serão criados `.por` permanentes em `tests/`. Os 4 arquivos existentes e os 5 casos atuais permanecem intactos. As sondas da E0 vivem em `temp/e0/` (ignorado pelo Git) e não fazem parte da entrega.

## 5. Etapas incrementais (Portugol Studio)

### E0 — Sondas executadas (CONCLUÍDA em 2026-10-25)

Comando do harness (executado a partir da raiz do repositório):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\temp\e0\run-probes.ps1
```

O harness replica o padrão do M0 (`ProcessStartInfo`, `UseShellExecute = false`, stdin com `" "` + quebra de linha), mas lê `StandardOutput.BaseStream`/`StandardError.BaseStream` para preservar os **bytes crus** e grava `<sonda>.out.bin`, `<sonda>.err.bin`, `.out.txt` e `.err.txt` em `temp/e0/`. Cada sonda é um `.por` independente, para que um erro de sintaxe não mascare as demais.

| Sonda | O que mede | Resultado observado | Veredito |
| --- | --- | --- | --- |
| S1 | `inclua biblioteca Texto --> tx` no runner de console; `numero_caracteres`; `obter_caracter` 0-based | `S1_LEN_ABC=3`, `S1_C0=a`, `S1_C2=c`, `S1_LEN_VAZIA=0` | **PASS** |
| S2a | `\t` e `\r` em literal de cadeia | `S2_TAB_LEN=1` com byte `09` entre `[T]`/`[/T]`; `S2_CR_LEN=1` com byte `0D` entre `[R]`/`[/R]` | **PASS** |
| S2b | `\"` em literal de cadeia | `S2_QUOTE_LEN=1`, byte `22` entre `[Q]`/`[/Q]` | **PASS** |
| S2c | `\u00E3` (escape Unicode) | Erro de sintaxe: `Variáveis do tipo cadeias e caracter com o símbolo '\' devem utiliza-lo como: '\\'` (linha 7); stdout 35 bytes, stderr 598 bytes | **FAIL** (escape inexistente) |
| S2d | `\015` (escape octal) | Mesmo erro da S2c (linha 7) | **FAIL** (escape inexistente) |
| S3 | Codificação do fonte e UTF-16 | UTF-8 sem BOM: `S3_LEN=3`, `S3_CH1` = byte `E3`, `S3_FUNCAO_LEN=6`. CP1252: `S3_LEN=3`, `S3_CH1` = byte `3F` (`?`), `S3_FUNCAO_LEN=6`, sem erro | **PASS** (UTF-8 correto; CP1252 corrompe em silêncio) |
| S4 | `inteiro ids[1024]` local, índices 0 e 1023 | `S4_0=7 S4_1023=24` | **PASS** |
| S4b | Índice igual ao tamanho (`ids[1024]`) | Erro de execução em stderr (`índice de vetor ou matriz inválido`), `EXIT_CODE=0`, stdout com 35 bytes (form feed + epílogo), nenhum ID parcial | **PASS** (comportamento de erro confirmado) |
| S5 | `cadeia` de 16.384 por duplicação; 16.385; 3.071 caracteres | `S5_LEN=16384`, `S5_PRIMEIRO=a`, `S5_ULTIMO=a` (índice 16.383), `S5_LEN_16385=16385`, `S5_TOKENS_LEN=3071`, `S5_TOKENS_ULTIMO=e` (índice 3.070) | **PASS** |
| S5b | Linha de saída com 1.024 IDs | `total_bytes=2109`, `first_byte=0x0C`, `first_LF_index=2052`, `first_CR_index=2073`, `payload_len=2051`, `payload_equals_expected=True` | **PASS** |
| S6 | Bytes crus da linha emitida | Ver bloco abaixo | **PASS** |
| S7 (1ª tentativa) | Forma completa com `=` em expressão | Erro de sintaxe: `A expressão não foi finalizada corretamente. Insira o caracter ')'` (linha 7, coluna 14) | **FAIL** (defeito da sonda) |
| S7b | Controle negativo de `=` | Mesmo erro, linha 5, coluna 14 | **FAIL** (confirma A13) |
| S7a | `==` em expressão | `S7A_SP=verdadeiro S7A_A=falso` | **PASS** |
| S7c | Escapes em literal de `caracter` | `[T]\[/T][R]\[/R][N]\[/N]`: `'\t'`, `'\r'` e `'\n'` produziram **`\` (0x5C)** | **FAIL** (armadilha silenciosa) |
| S7d | `eh_separador` com `'\t'` etc. | Retornou `verdadeiro` para os quatro — mas comparava `\` com `\` | **PASS aparente, inválido**: não mede TAB/CR/LF e não é usado como evidência |
| S7e | `caracter` via `tx.obter_caracter("\t", 0)` e equivalentes | Bytes `09`, `0D`, `0A` entre `[T]`, `[R]`, `[N]`; `S7E_SP/TAB/CR/LF=verdadeiro`, `S7E_A=falso` | **PASS** |
| S7f | Comparação de caracteres de strings distintas, `!=`, `e`, `ou`, retorno antecipado | `S7F_EQ=verdadeiro`, `S7F_NE=falso`, `S7F_AND=verdadeiro`, `S7F_OR=verdadeiro` | **PASS** |
| S7b_forward | Chamada de função definida depois | `S7B=8` | **PASS** |

Bytes crus da S6 (linha `IDS=9 12`):

```text
0C                                  form feed do CLS
49 44 53 3D 39 20 31 32            IDS=9 12
0A                                  LF único emitido pelo programa
0A 50 72 6F 67 72 61 6D 61 ...     epílogo do interpretador
```

O epílogo completo é `LF + "Programa finalizado" + CRLF + CRLF + "Pressione ENTER para continuar" + CRLF`. Não há `0D` antes do `0A` do contrato. Isso fecha P1: o verificador de bytes pode exigir form feed no offset 0, carga ASCII, exatamente um `0A` e nenhum `0D` dentro da carga.

Tempos observados (processo completo, incluindo JVM): 0,31 s a 0,98 s por sonda; a S5 ficou em 0,97 s contra 0,85 s de uma sonda trivial, diferença compatível com a construção e leitura de 16.384 caracteres. Com 20 casos, a ordem de grandeza da suíte é de ~20 s, sem incluir o build.

#### Premissas fechadas e ajustes obrigatórios

1. **`Texto` disponível e 0-based** (S1) — D6 confirmado.
2. **Somente `\n`, `\t`, `\r`, `\"`, `\\` em literais de cadeia** (S2a/S2b); `\uXXXX` e octal não existem (S2c/S2d).
3. **Escapes em literal de `caracter` são uma armadilha**: `'\t'` vale `\` (S7c). Delimitadores vêm de `tx.obter_caracter("...", 0)` e são passados como parâmetros (D8).
4. **Igualdade é `==`** (S7a/S7b); `=` em expressão é erro de sintaxe (D7).
5. **Fonte em UTF-8 sem BOM** (S3); CP1252 corrompe acentos sem erro (D13).
6. **Índice 1024 é erro de execução** (S4b), logo a guarda `total = 1024` antes de gravar é obrigatória (D14).
7. **16.384 caracteres e 1.024 IDs são viáveis** (S5/S5b), inclusive uma linha de 2.051 caracteres emitida sem quebra ou truncamento.
8. **Retorno antecipado, função sem tipo, `caracter` como parâmetro e chamada forward funcionam** (S7e/S7f/S7b_forward).

**Impedimentos:** nenhum bloqueante. As duas sondas FAIL (S2c/S2d) são recursos inexistentes, não requisitos da spec; as duas falhas de S7 foram defeitos das próprias sondas. Nenhuma premissa da spec depende de `\uXXXX`, de escape octal ou de escape em literal de `caracter`.

### E1 — Esqueleto e encanamento (CONCLUÍDA em 2026-10-25)

- `src/tokenizador.por` com o cabeçalho de fragmento e `tokenizar` implementando **apenas** o passo 1 (§1.1) e a emissão fixa `IDS=`.
- `scripts/build-tests.ps1` com a tabela de casos (nome, driver, saída esperada), limpeza controlada de `temp/tests/`, criação do diretório e escrita em **UTF-8 sem BOM**, com validação de round-trip UTF-8. A checagem específica dos bytes `C3 A3` do literal acentuado entra junto com o caso `acentos` (E3), único que contém acento.
- `scripts/test.ps1`: invocar o builder quando não for `-SelfTest`, anexar os casos descobertos, falhar se não houver caso gerado.

Casos ativos: `vazio`, `so_separadores`, `limite_chars_16385`.
Critério de saída: 5 casos antigos + 3 novos verdes; autoteste inalterado.

#### Evidência de execução da E1 (2026-10-25)

Comandos, a partir da raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

- Builder: `Generated 3 cases in temp/tests`, exit 0. `.por` gerados com 920/930/1.060 bytes e `.expected` com 4/4/18 bytes, todos sem BOM.
- Suíte normal: `Passed: 8`, `Failed: 0`, `Total: 8`, `EXIT_CODE=0` (5 casos M0 + 3 da E1, todos PASS). Executada duas vezes com totais idênticos; 5,68 s por execução.
- Autoteste: `Passed: 0`, `Failed: 1` intencional, `EXIT_CODE=1`; o builder não é invocado nesse modo.
- Bytes crus do stdout: `vazio` e `so_separadores` → `0C 49 44 53 3D 0A` (`IDS=\n`); `limite_chars_16385` → `ERRO=ENTRADA_LONGA\n` (`0C 45 52 52 4F … 0A`). `stderr` vazio e `exit=0` nos três.
- `src/tokenizador.por` é ASCII puro (0 bytes > 127); `scripts/test.ps1` mantém BOM `EF BB BF` e finais LF.
- O caso `limite_chars_16385` prova que 16.385 dispara o erro; a aceitação de exatamente 16.384 passou a ser coberta na E5 pelo caso `limite_chars_16384`.

### E2 — Separação e `UNK` (CONCLUÍDA em 2026-10-25)

- Implementar `eh_separador` e o laço de campos com `[ini, fim]`, armazenando `0` no buffer para cada campo (vocabulário ainda ausente) e emitindo a linha só ao final.
- Delimitadores obtidos com `tx.obter_caracter("\t", 0)`, `("\r", 0)` e `("\n", 0)` e passados por parâmetro (D8).
- Buffer `ids[1024]` já nesta etapa, para que E4 só acrescente a checagem de excesso.

Casos ativos: `fora_da_tabela`, `unk_isolado`.
Critério de saída: 5 + 5 verdes.

#### Evidência de execução da E2 (2026-10-25)

Comandos, a partir da raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

- Builder: `Generated 5 cases in temp/tests`, exit 0; todos os `.por`/`.expected` sem BOM.
- Suíte normal: `Passed: 10`, `Failed: 0`, `Total: 10`, `EXIT_CODE=0` (5 M0 + 3 E1 + 2 E2). Executada duas vezes com totais idênticos; 8,16 s na segunda.
- Autoteste: `Passed: 0`, `Failed: 1` intencional, `EXIT_CODE=1`.
- Bytes crus: `fora_da_tabela` → `0C 49 44 53 3D 30 20 30 20 30 20 30 0A` (`IDS=0 0 0 0\n`); `unk_isolado` → `IDS=0\n`. `stderr` vazio e `exit=0`.
- `eh_separador` recebe TAB/CR/LF por parâmetro; espaço é o literal `' '`. Nenhum escape em literal de `caracter` e nenhuma substring criada.
- `src/tokenizador.por` permanece ASCII puro (0 bytes > 127).

**Limitação registrada (não é E4):** entradas com mais de 1.024 campos não são tratadas nesta etapa. A guarda `total < 1024` impede acessar `ids[1024]`, mas uma entrada com 1.025 tokens hoje emite 1.024 IDs, sem erro — comportamento **não conforme** à spec até a E4 (resolvido na seção E4, abaixo). Sondas manuais descartáveis em `temp/e2/` (não são casos da suíte): `probe_1024` e `probe_1025` terminaram com `exit=0`, `stderr` vazio e `payload_len=2051`; ambas emitiram 1.024 IDs, confirmando o truncamento provisório. Nenhum caso ativo da E2 excede 1.024 campos.

### E3 — Vocabulário de 24 palavras e `UNK=0` (CONCLUÍDA em 2026-10-25)

- `mesmo_conteudo` e `id_do_campo` com as 24 entradas na ordem da spec; fallback `0`.
- Revisão explícita: nenhuma palavra com ID `0`; nenhum ID fora de `1..24`.

Casos ativos: `bordas_e_consecutivos`, `separador_estrito`, `caixa`, `acentos`, `vocabulario_completo`, `pontuacao`, `cardinalidade`, `exemplo_spec`.
Critério de saída: 5 + 13 verdes.

#### Evidência de execução da E3 (2026-10-25)

Comandos, a partir da raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

- Builder: `Generated 13 cases in temp/tests`, exit 0; 26 arquivos gerados, nenhum com BOM.
- Suíte normal: `Passed: 18`, `Failed: 0`, `Total: 18`, `EXIT_CODE=0` (5 M0 + 13 gerados). Executada duas vezes com totais idênticos; 17,85 s na segunda.
- Autoteste: `Passed: 0`, `Failed: 1` intencional, `EXIT_CODE=1`.
- Tabela verificada estaticamente contra a §3.3: 24 entradas em `id_do_campo`, palavras na ordem `programa..pare`, IDs `1..24`, 24 IDs únicos e nenhum fora de `1..24`.
- `src/tokenizador.por` permanece ASCII puro (0 bytes > 127).
- `acentos.por` gerado contém os bytes `C3 A3` (ã) e `C3 A7` (ç); o builder valida essas sequências além do round-trip UTF-8.
- `mesmo_conteudo` compara `fim - ini + 1` com `numero_caracteres(palavra)` e depois `tx.obter_caracter` por índice, sem substring e sem transformação.
- **Limitação de E2 inalterada nesta etapa:** entradas com mais de 1.024 campos ainda truncavam (sem `ERRO=TOKENS_DEMAIS`) até a E4; resolvido na E4 (seção abaixo). Nenhum caso ativo da E3 excedia 1.024 campos.

### E4 — Limite de tokens (CONCLUÍDA em 2026-10-25)

- No 1.025º campo: `ERRO=TOKENS_DEMAIS`, sem emitir nenhum ID. A guarda `total = 1024` vem antes de gravar (D14), porque `ids[1024]` é erro de execução (S4b).
- Confirmar que a checagem de caracteres continua sendo a primeira.

Casos ativos: `limite_tokens_1024`, `limite_tokens_1025`, `limite_ambos`.
Critério de saída: 5 + 16 verdes.

#### Evidência de execução da E4 (2026-10-25)

Comandos, a partir da raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

- Builder: `Generated 16 cases in temp/tests`, exit 0; 32 arquivos gerados, nenhum com BOM.
- Suíte normal: `Passed: 21`, `Failed: 0`, `Total: 21`, `EXIT_CODE=0` (5 M0 + 16 gerados). Executada duas vezes com totais idênticos; 25,56 s na segunda.
- Autoteste: `Passed: 0`, `Failed: 1` intencional, `EXIT_CODE=1`.
- `limite_tokens_1024`: payload de 2.051 bytes, 1.024 IDs, sem `ERRO=`.
- `limite_tokens_1025`: payload de 18 bytes, exatamente `ERRO=TOKENS_DEMAIS`, sem `IDS=` em nenhum ponto da saída.
- `limite_ambos`: payload de 18 bytes, `ERRO=ENTRADA_LONGA`, sem `IDS=`; a ordem normativa foi preservada.
- `stderr` vazio e `exit=0` nos três (o interpretador sempre retorna 0).
- Índices no código: declaração `inteiro ids[1024]`, gravação apenas em `ids[total]` e leitura em `ids[j]`; nenhuma expressão `ids[1024]`.
- `src/tokenizador.por` permanece ASCII puro (0 bytes > 127).

### E5 — Fronteiras restantes, determinismo e desempenho (CONCLUÍDA em 2026-10-25)

- Casos de fronteira de caracteres, separadores no limite e duas execuções independentes da mesma entrada.
- Medir tempo da suíte; a E0 já fixou a ordem de grandeza em 0,85–0,98 s por processo (JVM incluída) e 16.384 caracteres em 0,97 s.
- Medir o pior caminho de comparação: 1.024 tokens com comprimento igual ao de palavras candidatas, forçando a comparação caractere a caractere.

Casos ativos: `limite_chars_16384`, `longo_so_separadores`, `determinismo_a`, `determinismo_b`.
Critério de saída: 5 + 20 verdes e tempos registrados.

#### Evidência de execução da E5 (2026-10-25)

Comandos, a partir da raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

- Builder: `Generated 20 cases in temp/tests`, exit 0; 40 arquivos gerados, nenhum com BOM.
- Suíte normal, execução 1: `Passed: 25`, `Failed: 0`, `Total: 25`, `exit=0`, **25,78 s**.
- Suíte normal, execução 2: `Passed: 25`, `Failed: 0`, `Total: 25`, `exit=0`, **27,14 s**. Os cinco casos M0 continuam PASS.
- Autoteste: `Passed: 0`, `Failed: 1` intencional, `exit=1`. Nenhuma meta de tempo foi fixada; os valores acima são medições pontuais de uma máquina, não limites de aceitação.
- As duas execuções levam ~26–27 s porque cada caso sobe uma JVM (≈0,85–1,3 s por caso). O tempo cresce com o número de casos, não com o tamanho da entrada.

Fronteiras exatas, medidas executando cada `.por` isoladamente e lendo o payload cru:

| Caso | Entrada construída | Bytes de entrada | Payload observado | Tempo |
| --- | --- | ---: | --- | ---: |
| `limite_chars_16384` | 16.384 × `a` (14 duplicações de `"a"`) | 16.384 | `IDS=0` | 1.267 ms |
| `longo_so_separadores` | `" \t\r\n"` duplicado 12× | 16.384 | `IDS=` | 1.256 ms |

- `limite_chars_16384`: não há `ERRO=ENTRADA_LONGA`; o campo único de 16.384 caracteres vira um `UNK`, conforme §4 da spec.
- `longo_so_separadores`: o caso usa **exatamente 16.384 separadores**, o maior valor aceito. O payload é `IDS=` seguido de LF, sem IDs e sem espaços extras, ou seja, zero tokens vazios.
- A fronteira seguinte foi verificada em sonda manual descartável (`temp/e5/probe_sep_16385.por`, 16.385 separadores, ignora o Git): payload `ERRO=ENTRADA_LONGA`, `stderr` vazio, `exit=0`. A regra "somente separadores acima de 16.384 → `ERRO=ENTRADA_LONGA`" da spec §4 fica assim coberta, sem transformar o caso da suíte em erro — a missão da E5 exige `IDS=` para `longo_so_separadores`.

Determinismo (não apenas texto normalizado):

- `determinismo_a.por` e `determinismo_b.por` são gerados a partir do mesmo driver (`tokenizar("programa se x 42 se")`); SHA-256 dos dois arquivos: `07A97CF835F501D4F915306913C5B6328A14DC73B9E514D1298B34A4BBA91281` (idênticos).
- Execuções em processos separados: payloads `IDS=1 9 0 0 9`, `stdout` completo com SHA-256 **`34F6E1B6079E88FDD6ADF61254D3197741035CA6C1A61A1DB25D2C37D2BCCFB5`** nas duas; `stderr` vazio; 1.272 ms e 1.275 ms.
- A comparação foi feita sobre os bytes de `stdout` (incluindo form feed e epílogo), não sobre a saída aparada pelo runner.

Codificação e integridade:

- `src/tokenizador.por` permanece ASCII puro (0 bytes > 127).
- 40 arquivos `.por`/`.expected` gerados, 0 com BOM.
- Nenhuma saída esperada foi alterada para acomodar resultados; os valores vêm da spec/plano.

Limitações registradas nesta etapa:

- O interpretador sempre retorna `exit=0`; erros de contrato são detectados pelo payload, não pelo código de saída.
- Os tempos acima são de uma única máquina e não constituem critério de aceitação.
- A cobertura byte a byte formal do payload (form feed, LF único, ausência de CR) é a E6 (`scripts/verify-bytes.ps1`); aqui a conferência foi manual sobre o `stdout` cru.

### E6 — Formato observável e auditoria (CONCLUÍDA em 2026-10-25)

- Criar `scripts/verify-bytes.ps1` (P1 aprovado) usando o formato medido na E0: `0x0C` no offset 0, carga ASCII, exatamente um `0x0A` e nenhum `0x0D` dentro da carga, seguido do epílogo conhecido.
- Aplicar `-ceq` no runner (P2 aprovado).
- Auditar AC1–AC20 contra a tabela de casos; registrar explicitamente qualquer item parcial.
- Verificar que `src/tokenizador.por` é ASCII puro (`0..127`) e que a tabela tem exatamente 24 entradas.

Critério de saída: matriz de AC preenchida sem item "não verificado", exceto os aceitos por escrito.

#### Evidência de execução da E6 (2026-10-25)

Comandos, a partir da raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

`scripts/verify-bytes.ps1` foi criado nesta etapa. Ele executa cada `.por` gerado, lê o `stdout` como bytes crus (sem decodificação de página de código) e valida:

- `0x0C` no offset 0;
- carga entre o offset 1 e o primeiro `0x0A`, toda em ASCII imprimível (`0x20..0x7E`), sem `0x0D`;
- carga exatamente igual ao `.expected` correspondente, com comparação sensível a caixa (`-cne`);
- carga obedecendo ao contrato `IDS=`/`ERRO=`, sem espaço final;
- epílogo exato, sem bytes extras;
- `stderr` vazio;
- estaticamente, fonte ASCII puro e tabela de `id_do_campo` com 24 entradas, palavras na ordem da spec, IDs `1..24` únicos.

Formato cru confirmado (exemplo `vazio`, 62 bytes):

```
<0C>IDS=<LF><LF>Programa finalizado<CR><LF><CR><LF>Pressione ENTER para continuar<CR><LF>
```

O epílogo é contado a partir do LF que termina a carga: **57 bytes** (`LF`, `LF`, `Programa finalizado`, `CRLF`, `CRLF`, `Pressione ENTER para continuar`, `CRLF`).

- Primeira execução do verificador: 21 verificações, **20 falhas**, porque o próprio script esperava 56 bytes de epílogo (faltava um `LF`). Defeito do verificador, não do tokenizador: o payload e o contrato já casavam. Corrigido o literal e reexecutado.
- Segunda execução: `Total: 21 verificacoes, 0 falha(s)`, `Formato de bytes conforme.`, `verify_exit=0`, **38,79 s**.
- `-ceq` aplicado na comparação de sucesso do runner (`scripts/test.ps1`, linha 124); nenhuma outra mudança no runner. BOM e finais preservados: `EF BB BF`, 250 LF, 0 CR.
- Suíte normal, execução 1: `Passed: 25`, `Failed: 0`, `Total: 25`, `exit=0`, **36,94 s**.
- Suíte normal, execução 2: `Passed: 25`, `Failed: 0`, `Total: 25`, `exit=0`, **40,03 s**.
- Autoteste: `Passed: 0`, `Failed: 1` intencional, `exit=1`.
- Tempos maiores que os da E5 nesta máquina; registrados como medição, sem meta. Nenhum caso individual se aproximou de 60 s.
- Nenhuma saída esperada foi alterada; 40 arquivos gerados, 0 com BOM; `src/tokenizador.por` com 0 bytes > 127.
- Auditoria AC1–AC20: todos os critérios têm pelo menos um caso verde; AC15 passou a ter verificação byte a byte pelo script. A linha de AC16 na matriz foi corrigida: o caso 17 é sucesso (`IDS=`), não erro.

### E7 — Fechamento (CONCLUÍDA em 2026-10-25)

- Rodar a suíte completa duas vezes e o autoteste.
- `git status` conferido contra a tabela da seção 4.
- Acrescentar ao §5.0 deste plano as evidências de execução das etapas (comandos, saídas, tempos, contagem).
- Relatório final com PRONTO / PARCIAL / BLOQUEADO.

#### Evidência de execução da E7 (2026-10-25)

Sequência executada na ordem exigida, a partir da raiz do repositório:

| # | Comando | Saída resumida | Exit | Tempo |
| ---: | --- | --- | ---: | ---: |
| 1 | `build-tests.ps1` | `Generated 20 cases in temp/tests` | 0 | 0,63 s |
| 2 | `verify-bytes.ps1` | `Total: 21 verificacoes, 0 falha(s)` / `Formato de bytes conforme.` | 0 | 23,47 s |
| 3 | `test.ps1` | `Passed: 25`, `Failed: 0`, `Total: 25` | 0 | 27,93 s |
| 4 | `test.ps1` | `Passed: 25`, `Failed: 0`, `Total: 25` | 0 | 28,30 s |
| 5 | `test.ps1 -SelfTest` | `Passed: 0`, `Failed: 1` (intencional) | 1 | 1,21 s |

Comandos completos:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

Integridade do repositório:

- `git status --short`: alterações desta missão = `scripts/test.ps1` modificado (tracked) e não rastreados `src/tokenizador.por`, `scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`, `docs/tokenizer-plan.md`, `docs/tokenizer-spec.md`. Pré-existentes e intocadas: `AGENTS.md` modificado, seis remoções em `.agents/skills/` e `AGENTS.md.bak-1792847467`.
- `git diff --check`: exit 0; único aviso é o LF→CRLF que o Git aplicará a `scripts/test.ps1` (o arquivo permanece com BOM `EF BB BF`, 250 LF e 0 CR).
- `git diff --stat`: 8 arquivos rastreados, sendo 7 pré-existentes (`AGENTS.md`, 6 skills) e `scripts/test.ps1` (+28/−1, sendo +27 da E1 e a troca `-eq`→`-ceq` da E6).
- `README.md` e `tests/*.por` sem qualquer alteração.

Critérios finais:

| Critério | Evidência | Estado |
| --- | --- | --- |
| Builder gera 20 casos | `Generated 20 cases`, exit 0 | Atendido |
| Verificador de bytes | 21 verificações, 0 falhas, exit 0 | Atendido |
| Suíte normal duas vezes | 25 PASS / 0 FAIL / exit 0 nas duas | Atendido |
| Autoteste | 1 FAIL intencional, exit 1 | Atendido |
| Cinco testes M0 | 5 casos fixos + 20 gerados = 25; 0 falhas | Atendido |
| AC1–AC20 | matriz §9.1 com caso verde; AC15 verificado byte a byte | Atendido |
| Vocabulário | 24 entradas, IDs 1–24, fallback `UNK=0`, nenhum ID 25–63 | Atendido |
| Limite de caracteres | 16.384 aceito (`IDS=0`), 16.385 rejeitado | Atendido |
| Limite de tokens | 1.024 aceito, 1.025 → `ERRO=TOKENS_DEMAIS` | Atendido |
| Erros sem saída parcial | payloads de erro sem `IDS=` em nenhum ponto | Atendido |
| Fonte ASCII | 5.326 bytes, 0 acima de 0x7F | Atendido |
| `.por` gerados sem BOM | 20 `.por` + 20 `.expected`, 0 com BOM | Atendido |

Invariantes do código final conferidas: nenhum escape em literal de `caracter` (0 ocorrências de `'\t'`/`'\r'`/`'\n'`), TAB/CR/LF obtidos por `tx.obter_caracter("...", 0)`, guarda `total == 1024` nos dois caminhos de gravação e ID máximo 24.

**Estado final: PRONTO.** A MISSION 002 está concluída no escopo M1 (tokenizador mínimo como fragmento), com os 20 critérios de aceitação evidenciados.

Limitações remanescentes (não bloqueiam o escopo):

- O tokenizador é um fragmento para testes; não foi integrado a compilador, IDE ou pipeline de treino.
- O interpretador sempre retorna `exit=0`; a validação depende do payload.
- `verify-bytes.ps1` roda separadamente da suíte (mais 20 processos/JVM) e não faz parte de `test.ps1`.
- Tempos são medições desta máquina (23–28 s por execução completa), sem meta de desempenho.
- A cobertura de entradas restringe-se a ASCII/Latin-1, conforme decisão P4; não há testes com caracteres fora do BMP ou pares substitutos.


## 6. Estratégia do vocabulário fixo

Tabela transcrita da spec (§3.3), sem reordenação e sem alteração:

| ID | Palavra | ID | Palavra | ID | Palavra |
| ---: | --- | ---: | --- | ---: | --- |
| 1 | `programa` | 9 | `se` | 17 | `escreva` |
| 2 | `funcao` | 10 | `senao` | 18 | `leia` |
| 3 | `inicio` | 11 | `enquanto` | 19 | `e` |
| 4 | `inteiro` | 12 | `faca` | 20 | `ou` |
| 5 | `real` | 13 | `para` | 21 | `nao` |
| 6 | `logico` | 14 | `ate` | 22 | `verdadeiro` |
| 7 | `cadeia` | 15 | `passo` | 23 | `falso` |
| 8 | `vazio` | 16 | `retorne` | 24 | `pare` |

Regras de implementação:

1. Uma única função `id_do_campo` contém as 24 verificações; cada linha tem o literal da palavra e o literal do ID lado a lado, para revisão direta contra a tabela.
2. `UNK=0` é o valor inicial/fallback: se nenhuma verificação casar, retorna `0`. Nenhuma palavra mapeia para `0`.
3. Comparação exata: igualdade de comprimento + igualdade caractere a caractere. Nenhuma chamada a caixa, acento, trim ou normalização (AC20).
4. IDs são imutáveis; o código não contém nenhum ID em `25..63`.
5. Crescimento futuro só por acréscimo em `25..63`, com nova versão da spec — fora do M1.

## 7. Tratamento dos delimitadores

- Conjunto fechado: espaço (U+0020), TAB (U+0009), CR (U+000D), LF (U+000A).
- `eh_separador` é a única definição de separador e é usada no único laço de varredura.
- Máquina de estados por índice: `em_campo` falso ao iniciar; separador fora de campo é ignorado; separador dentro de campo fecha o campo; fim do texto fecha o campo aberto.
- Consequências diretas: separadores consecutivos, à esquerda e à direita não geram token; CRLF conta como dois separadores consecutivos e produz uma única fronteira; texto vazio ou só de separadores produz zero tokens.
- Nenhum outro caractere separa. Em particular `,` `;` `(` `)` `{` `}` `.` `=` e NBSP permanecem no campo e levam o campo a `UNK`.
- O form feed do interpretador não tem relação com a entrada; só aparece no stdout do processo e é tratado pelo runner.

## 8. Validação dos limites

| Passo | Regra | Implementação | Evidência |
| --- | --- | --- | --- |
| 1 | `numero_caracteres(texto) > 16384` → `ERRO=ENTRADA_LONGA` | Checagem única, antes de qualquer varredura ou escrita | `limite_chars_16384` (aceito), `limite_chars_16385` (rejeitado); sonda manual de 16.385 separadores |
| 2 | Contar apenas campos não vazios | Laço de separação | `so_separadores`, `vazio`, `longo_so_separadores` |
| 3 | 1.025º campo → `ERRO=TOKENS_DEMAIS` | Checar `total = 1024` **antes** de gravar (nunca indexar `1024` no vetor); buffer cheio dispara erro e nenhuma escrita ocorreu | `limite_tokens_1024`, `limite_tokens_1025` |
| 4 | Ambos excedidos | Ordem do passo 1 garante `ENTRADA_LONGA` | `limite_ambos` |
| 5 | Sem truncamento | Nenhum corte; campo de 16.384 caracteres é um único `UNK` | `limite_chars_16384` |

Construção das entradas de fronteira (sem literais gigantes e sem substring):

- **16.384 caracteres:** duplicação sucessiva de uma semente (`s = s + s`), 14 concatenações para 1 caractere, 13 para 2 caracteres. O(1) em número de concatenações, O(n) em memória.
- **1.024 tokens:** `s = s + " " + s` a partir de `"se"`, 10 duplicações → 1.024 tokens, 3.071 caracteres.
- **1.025 tokens:** a mesma string + `" se"` → 3.074 caracteres.
- **16.385 caracteres:** 16.384 + 1 caractere.
- **16.384 separadores:** `" \t\r\n"` duplicado 12× (4 × 2¹² = 16.384), sem campo não vazio.
- **Ambos excedidos:** `"x "` duplicado até 16.384 caracteres (8.192 tokens) + `"x"` → 16.385 caracteres e 8.193 tokens.

O valor esperado de cada caso funciona como asserção implícita do comprimento construído: se a construção errar o tamanho, a saída deixa de casar (por exemplo, `IDS=0` em vez de `ERRO=ENTRADA_LONGA`).

## 9. Casos de teste derivados dos critérios de aceitação

Todos usam comparação **exata** da linha. `␣`, `⇥` e reticências são apenas notação deste documento; no código os separadores são literais de cadeia com `\t`, `\r` e `\n` (medidos na E0).

| # | Nome | Entrada | Esperado | AC |
| ---: | --- | --- | --- | --- |
| 1 | `vazio` | `""` | `IDS=` | AC1, AC11 |
| 2 | `so_separadores` | espaço, TAB, CR, LF, TAB, espaço | `IDS=` | AC2 |
| 3 | `bordas_e_consecutivos` | `"␣␣se⇥⇥faca␣"` | `IDS=9 12` | AC3 |
| 4 | `separador_estrito` | `"se,faca␣se␣faca"` | `IDS=0 9 12` | AC4, AC9 |
| 5 | `caixa` | `"se␣Se␣SE"` | `IDS=9 0 0` | AC5 |
| 6 | `acentos` | `"nao␣não␣funcao␣função"` | `IDS=21 0 2 0` | AC6 |
| 7 | `vocabulario_completo` | as 24 palavras em ordem, um espaço entre elas | `IDS=1 2 3 … 24` (24 IDs) | AC7, AC19 |
| 8 | `fora_da_tabela` | `"x␣42␣@␣resultado"` | `IDS=0 0 0 0` | AC8 |
| 9 | `pontuacao` | `"se,␣(se)␣se,␣faca␣inicio()␣x=1"` | `IDS=0 0 0 12 0 0` | AC9 |
| 10 | `unk_isolado` | `"x"` | `IDS=0` | AC11 |
| 11 | `cardinalidade` | `"programa␣{␣se␣x␣}␣resultado"` | `IDS=1 0 9 0 0 0` | AC10 |
| 12 | `limite_tokens_1024` | 1.024 × `se` | `IDS=9 9 … 9` (1.024 IDs) | AC12 |
| 13 | `limite_tokens_1025` | 1.025 × `se` | `ERRO=TOKENS_DEMAIS` | AC12, AC16 |
| 14 | `limite_chars_16384` | 16.384 × `a` (campo único) | `IDS=0` | AC13, AC18 |
| 15 | `limite_chars_16385` | 16.385 × `a` | `ERRO=ENTRADA_LONGA` | AC13, AC16 |
| 16 | `limite_ambos` | 16.385 caracteres com 8.193 campos | `ERRO=ENTRADA_LONGA` | AC14, AC16 |
| 17 | `longo_so_separadores` | 16.384 separadores (`" \t\r\n"` repetido 12×) | `IDS=` | §4, AC2 |
| 18 | `exemplo_spec` | `programa { funcao inicio() { escreva("OI") } }` | `IDS=1 0 2 0 0 0 0 0` | AC10 |
| 19 | `determinismo_a` | `"programa␣se␣x␣42␣se"` | `IDS=1 9 0 0 9` | AC17 |
| 20 | `determinismo_b` | arquivo idêntico ao caso 19 (mesmo driver), processo separado | `IDS=1 9 0 0 9` | AC17 |

Observações:

- O caso 18 usa aspas escapadas dentro do literal (`\"`), confirmado na E0/S2b. Sem esse escape o caso seria removido e AC10 continuaria coberto pelo caso 11.
- O caso 6 usa **literal acentuado direto** em fonte UTF-8 sem BOM (medido na E0/S3). Não há `\u00E3` nem octal no dialeto (S2c/S2d). O builder valida os bytes `C3 A3` antes de rodar.
- Os casos 19 e 20 são gerados de um único driver e produzem arquivos byte a byte iguais; rodam em processos separados. A evidência de determinismo é o `stdout` completo com o mesmo SHA-256, sem introduzir saída fora do contrato.
- O caso 17 usa o maior valor aceito (16.384 caracteres), porque a missão exige `IDS=` para entrada composta só de separadores. A fronteira de rejeição (16.385 separadores → `ERRO=ENTRADA_LONGA`) foi verificada em sonda manual, registrada na evidência da E5.
- AC15 é coberto por todos os casos de sucesso; `\n` exato e ausência de espaço final são verificados por `scripts/verify-bytes.ps1` (executado na E6, 21 verificações, 0 falhas).

### 9.1 Matriz de cobertura dos critérios de aceitação

Auditoria da E6 (2026-10-25): todos os AC abaixo têm pelo menos um caso verde na suíte (25 PASS, 0 FAIL) ou verificação estática/byte a byte correspondente. Nenhum item ficou "não verificado".

| AC | Casos | Observação |
| --- | --- | --- |
| AC1 | 1 | |
| AC2 | 2 | `\r` e `\t` confirmados (E0/S2a) |
| AC3 | 3 | |
| AC4 | 4 | `,` não separa; espaço separa |
| AC5 | 5 | |
| AC6 | 6 | fonte UTF-8 sem BOM (E0/S3) |
| AC7 | 7 | 24 IDs em ordem |
| AC8 | 8 | |
| AC9 | 4, 9 | |
| AC10 | 11, 18 | contagem de IDs = campos não vazios |
| AC11 | 1, 10 | `IDS=` vs. `IDS=0` |
| AC12 | 12, 13 | |
| AC13 | 14, 15 | |
| AC14 | 16 | |
| AC15 | 1–12, 14, 18–20 | prefixo, separador simples e ausência de espaço interno; `\n` exato, ausência de espaço final e epílogo verificados byte a byte por `scripts/verify-bytes.ps1` |
| AC16 | 13, 15, 16 | comparação exata, sem `IDS=` |
| AC17 | 19, 20 | dois processos independentes + suíte executada duas vezes |
| AC18 | 14 | campo de 16.384 caracteres = 1 `UNK` |
| AC19 | 7 | mais revisão da tabela de 24 entradas |
| AC20 | 3, 4, 5, 6, 9 | nenhum caso exige transformação textual |

## 10. Integração com `scripts/test.ps1`

Alterações, todas aditivas:

1. Manter as funções existentes (`Write-Header`, `Write-Result`, `Normalize-Output`, `Run-PortugolTest`) e os 5 casos atuais sem alteração.
2. Antes de montar `$testCases`: se **não** for `-SelfTest`, executar `scripts/build-tests.ps1`; se o builder falhar, `exit 1` com mensagem clara, sem rodar casos.
3. Descobrir os casos gerados em `temp/tests/*.expected` (ordenação estável por nome), ler o esperado com `[IO.File]::ReadAllText` e anexar a `$testCases` com `ExpectedOutput`.
4. Guarda: zero casos gerados ⇒ erro e `exit 1` (evita suíte silenciosamente vazia).
5. `-SelfTest` continua substituindo `$testCases` por um único caso negativo e ignorando os gerados.
6. `-eq` → `-ceq` na comparação de `ExpectedOutput` (P2 aprovado), nada mais. O runner atual usa `-eq`, que é case-insensitive no PowerShell; a troca fecha a lacuna de caixa sem afetar os 5 casos existentes.
7. Preservar o BOM UTF-8 e os finais de linha **LF** de `test.ps1` (verificado: `EF BB BF` e 223 LF, zero CRLF); validar os 3 primeiros bytes após a edição.
8. Manter a execução a partir da raiz do repositório (premissa já existente).

Contagens esperadas: 5 casos M0 + 20 gerados = **25** no total.

Riscos de integração e mitigação:

- Regressão nos 5 casos: mitigada por não tocar em normalização, nos dados nem no autoteste; verificação explícita em cada etapa.
- Deriva entre entrada construída e saída esperada: ambas vivem na mesma tabela do builder.
- Artefato obsoleto em `temp/tests/`: o builder limpa apenas esse diretório, com guarda de caminho vazio.
- Tempo de execução: 20 invocações extras do interpretador; medir e registrar. Não há medição do M0 para comparar — não inventar limite.

## 11. Critérios objetivos de conclusão

Só será declarado **PRONTO** se todos forem verdadeiros e evidenciados:

1. E0 fechada, com as 7 sondas medidas e registradas em §5.0 (concluída em 2026-10-25, sem bloqueio).
2. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1` termina com `Failed: 0`, `Total: 25`, `EXIT_CODE=0`.
3. A suíte é executada duas vezes seguidas com os mesmos totais e sem falha (determinismo do conjunto).
4. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest` continua com `Passed: 0`, `Failed: 1` intencional, `EXIT_CODE=1`.
5. AC1–AC20 têm pelo menos um caso verde associado; as duas verificações conhecidas de AC15 (`\n` exato e ausência de espaço final) são executadas por `scripts/verify-bytes.ps1` (P1 aprovado).
6. A tabela de `id_do_campo` tem exatamente 24 entradas e o caso 7 emite `1..24` em ordem.
7. Nenhuma saída de erro contém `IDS=` e nenhuma saída de sucesso contém `ERRO=` (casos 13, 15, 16, 17 versus os demais).
8. `src/tokenizador.por` é ASCII puro (0..127); nenhum ID em `25..63`.
9. `git status` distingue o que esta missão criou do que já existia antes dela. Esperado como desta missão: `src/tokenizador.por` e `scripts/build-tests.ps1` (novos), `scripts/test.ps1` (modificado), `docs/tokenizer-plan.md` e `docs/tokenizer-spec.md` (não rastreados, criados na preparação) e `scripts/verify-bytes.ps1` (criado na E6). Alterações pré-existentes — `AGENTS.md` modificado, remoções em `.agents/skills/` e `AGENTS.md.bak-*` — não contam como desta missão e não podem ser tocadas. Nenhum `.por` novo em `tests/`.
10. Nenhuma dependência nova: nada baixado, nada instalado; apenas interpretador já instalado e Windows PowerShell.
11. Tempo real da suíte registrado; se algum caso individual ficar acima de 60 s, registrar como pendência de desempenho (sem alterar o contrato).
12. As quatro invariantes medidas na E0 estão presentes no código final: nenhum escape em literal de `caracter` (S7c), comparações com `==`/`!=` (S7a/S7b), `.por` em UTF-8 sem BOM com os bytes `C3 A3` validados (S3) e guarda `total = 1024` antes de gravar (S4b).

## 12. Riscos

Riscos remanescentes após a E0. Os riscos de `\r` ausente, de escape Unicode inexistente, de codificação ambígua e de `Texto` indisponível foram medidos e eliminados (ver §5.0).

| Risco | Probabilidade | Impacto | Mitigação |
| --- | --- | --- | --- |
| Usar escape em literal de `caracter` (`'\t'`) e obter `\` (0x5C) sem erro | Alta se copiado do hábito de outras linguagens | Alto — separadores errados, testes verdes pelo motivo errado | D8: TAB/CR/LF só via `tx.obter_caracter("...", 0)` e parâmetros; revisão explícita na E6 (fonte ASCII e separadores conferidos) |
| Fonte gravado em CP1252 e acento virar `?` (0x3F) silenciosamente | Média | Médio — AC6 passaria corrompido | D13: UTF-8 sem BOM + validação dos bytes `C3 A3` no builder |
| Usar `=` em expressão e receber erro de sintaxe obscuro | Média | Médio — retrabalho, sonda já falhou assim | D7: `==`/`!=` apenas; `=` só atribuição |
| Indexar `ids[1024]` e abortar a execução sem IDs parciais | Média | Alto — saída vazia mascarada como erro genérico | D14 implementado: `total == 1024` é checado **antes** de gravar; casos `limite_tokens_1024/1025/ambos` passam na E4 |
| String de 16.384 caracteres lenta | Baixa (medido: 0,97 s na E0; 1,27 s na E5) | Baixo | Medido na E5: `limite_chars_16384` em 1.267 ms |
| 1.024 IDs impressos um a um lentos | Baixa (linha de 2.051 caracteres medida) | Baixo | Medido na E4/E5: payload de 2.051 B; escrita em laço, um `escreva` por ID |
| Deriva entre builder e expectativas | Baixa | Médio | Fonte única no builder + totais fixos na suíte |
| Edição acidental do BOM de `test.ps1` | Média | Alto — suíte não roda | Checagem dos 3 primeiros bytes em E1 e E7 |
| Interpretação errada de A2 (campo de 16.384) | Baixa (spec v0.2.1 corrigida) | Médio | Caso 14 fixa a interpretação; §4 da spec é inequívoco |

## 13. Pendências aprovadas

Todas aprovadas em 2026-10-25; nenhuma pendência aberta antes da implementação.

| ID | Pendência | Decisão | Onde foi resolvida |
| --- | --- | --- | --- |
| P1 | Verificar `\n` exato, ausência de CR e de espaço final via captura bruta | **Aprovada** — criar `scripts/verify-bytes.ps1` | E6; formato já medido em S6 (form feed no offset 0, um único `0A`, nenhum `0D` na carga) |
| P2 | Trocar `-eq` por `-ceq` na comparação de sucesso | **Aprovada** | E6 (§10, item 6) |
| P3 | Entrada do M1 é parâmetro de função, sem I/O | **Confirmada** — contrato da spec §5 permanece | E1 |
| P4 | "Caractere" = unidade de código UTF-16 do runtime | **Confirmada** — testes restritos a ASCII/Latin-1 | E2/E5; S3 mediu `não` = 3 e `função` = 6 |
| P5 | Atualizar a seção "Estado" do `README.md` | **Cancelada** — `README.md` permanece fora do escopo da MISSION 002; não será alterado | — |
| P6 | Corrigir a frase "15.361 caracteres no pior caso" (§4 da spec) | **Concluída** — spec v0.2.1 | §4 da spec; ver §14 |
| P7 | Se S1/S2/S5 falhassem, aceitar pendências ou renegociar a spec | **Fechada** — nenhuma falha bloqueante; as duas FAIL (S2c/S2d) são recursos inexistentes e as duas de S7 foram defeitos das sondas | §5.0 |

## 14. Fora de escopo (não será feito neste plano)

- Lexer de Portugol, classes léxicas, parser, AST, avaliação.
- Treino, embeddings, redes neurais ou qualquer coisa além de produzir IDs.
- Normalização Unicode, de caixa ou de acentos.
- Leitura de arquivos, `stdin`, entrada interativa ou CLI.
- Ampliação do vocabulário, pontuação com ID, metadados de posição.
- Alterações em `tests/*.por` existentes ou nos 5 casos do M0.
- Atualização do `README.md` (P5 cancelada; permanece fora do escopo).
- Novas alterações em `docs/tokenizer-spec.md` além da correção factual de §4 já aplicada (v0.2.1, sem mudança normativa).
- Commits, pushes ou qualquer operação remota.
