# Plano de execução — Contexto de múltiplos tokens (M7)

- **Status:** E0–E7 **executadas e verificadas** (2026-10-27). O contrato
  normativo de `docs/context-spec.md` permaneceu congelado em v1.0.0. Evidências
  medidas em §11.1.
- **Especificação:** `docs/context-spec.md` v1.0.0 (congelada em E0; nenhum gate
  disparou).
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0), M5
  (`docs/training-spec.md` v1.0.0), M6 (`docs/generation-spec.md` v1.0.0).
- **Fora de escopo:** Transformer, atenção, redes recorrentes, memória externa,
  softmax, amostragem, temperatura, top-k, top-p, beam search, dependências
  externas, aleatoriedade, embeddings treináveis, detokenização inversa, commit,
  push, tag e operação remota.
- **Entrega:** `docs/context-spec.md`, `docs/context-plan.md`, `src/contexto.por`,
  `scripts/build-context-tests.ps1`, `scripts/verify-context-bytes.ps1` e o bloco
  aditivo de `scripts/test.ps1`.

## 1. Estado de partida e pré-voo

Verificado por comando antes de escrever este plano:

| Item | Estado medido |
| --- | --- |
| Branch | `main` |
| `HEAD` | `38fc295be84c7f62ee14b337b76bffb433387938` |
| `origin/main` | mesmo commit; 0 ahead / 0 behind |
| Árvore de trabalho | limpa antes dos docs; depois, apenas `docs/context-spec.md` e `docs/context-plan.md` não rastreados |
| Suíte de partida | `scripts/test.ps1` = **84 PASS / 0 FAIL**, exit `0` (`temp/m7-baseline.log`) |
| Composição da suíte | 5 casos literais + 20 M1 + 19 M3 + 14 M4 + 12 M5 + 14 M6 = 84 |
| M1 bytes | 21/21 (baseline histórico) |
| M3 bytes | 19/19 (baseline histórico) |
| M4 bytes | 22/22 (baseline histórico) |
| M5 bytes | 23/23 (baseline histórico) |
| M6 bytes | 13/13 (baseline histórico) |
| Autoteste | `scripts/test.ps1 -SelfTest` = **0 PASS / 1 FAIL intencional**, exit `1` |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |
| Custo por caso | ~1,3–1,5 s; suíte de 84 casos ~215 s, incluindo builders |

O baseline de 84/84 foi medido nesta missão e está em `temp/m7-baseline.log`
(artefato descartável, ignorado pelo Git). Nenhum valor foi inferido de
memória.

### 1.1 Arquivos congelados

Hashes `git hash-object` em `HEAD`, que **não podem** mudar na implementação:

```
src/tokenizador.por                    6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f
src/embeddings.por                     6f06aa820d163d3c1636383803b86105bf54cd85
src/rede.por                           fa9367a79bd2aefc373d30a94cfca2b7c86d9958
src/treino.por                         f5121423dd0aac6469b59b24b13d8a85b2c0d64d
src/gerador.por                        532e60cc52cef03fbd60c2a9d2b530472c73ded1
scripts/build-tests.ps1                1cfb01202586a83c4d7ec08ff738a8e90fb19044
scripts/verify-bytes.ps1               851afbbad494778f019bf2ce70e82b0b575ab443
scripts/build-embedding-tests.ps1      94d1a3819b76b4d614f4422bf00b0cd2c008daaf
scripts/verify-embedding-bytes.ps1     4f3aa68e499a9dc3289d22ebae5b8d1c18086651
scripts/build-network-tests.ps1        998e91b2896e9ec40bc1814990a0a53ae740fb3e
scripts/verify-network-bytes.ps1       1f46800852fed34d840206ca97bc84badd109b31
scripts/build-training-tests.ps1       c587e161e19d353af23f0cb9d055119b288c2675
scripts/verify-training-bytes.ps1      f59fee82d337e13f619360e63d6e928aef8e0f6b
scripts/build-generation-tests.ps1     e712064d631e6fbf2711943ec65da6812223427f
scripts/verify-generation-bytes.ps1    e1807a8d6469ecaba0d2ad724c9e58b6a2689b3a
```

`scripts/test.ps1` em `HEAD` tem hash
`2a37138ae53c5454806f2e7db0ec1fd3e356edb5`, **BOM UTF-8**, **353 linhas** e
último byte `0x7D` (`}`). Ele muda por desenho: apenas um bloco aditivo de 16
casos, dentro de `if (-not $SelfTest)`. O restante do arquivo deve permanecer
idêntico; o diff é conferido em E6 e E7.

### 1.2 Comandos de referência

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-embedding-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-network-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-training-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-generation-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-context-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-context-bytes.ps1
```

## 2. Restrições do runner e do ambiente

Comprovadas por leitura de `scripts/test.ps1` e pelas missões anteriores:

1. **Exit code do interpretador é sempre `0`.** Falhas de execução precisam ser
   detectadas por texto. Todos os casos novos usam saídas normais.
2. **stdout começa com form feed (`0x0C`).** `Normalize-Output` remove um `\f`
   inicial.
3. **Epílogo de sucesso:**
   `"\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n"`. O corpo
   usa LF; o epílogo usa CRLF.
4. **`Normalize-Output` remove o epílogo, um `\n` final e aplica `.Trim()`.**
   Comparação `-ceq` (case-sensitive). `.expected` não pode ter `\n` final, CR,
   BOM ou espaços nas pontas.
5. **Entrada padrão:** o runner envia `" "` e fecha. Nenhum caso lê teclado.
6. **Casos gerados** são descobertos por `Get-ChildItem -Filter *.expected` em
   um diretório próprio, ordenados por nome, e anexados a `$testCases`.
7. **Autoteste** substitui `$testCases` por um único caso que deve falhar; todos
   os blocos de geração ficam dentro de `if (-not $SelfTest)`.
8. **`scripts/test.ps1` tem BOM UTF-8 e não termina em LF** (último byte
   `0x7D`). A inserção precisa preservar ambos.
9. **stdout e stderr são concatenados.** Qualquer `AVISO` (por exemplo, array
   declarado com tamanho 1) quebra o caso. Buffers novos: `w16[300]`,
   `b16[25]`, `c16[12]`, `entradas[18]`, `alvos[6]`, `historico[33]`,
   `saida[64]`.
10. **`.Trim()` é aplicado ao total.** Nenhum caso termina com uma linha cujo
    valor seja whitespace; `TEXTO=` vazio não é usado.
11. **Nomes de caso** não podem colidir com M0/M1/M3/M4/M5/M6; o prefixo `ctx_`
    garante isso.
12. **Diretórios independentes** (`temp/tests`, `temp/embedding-tests`,
    `temp/network-tests`, `temp/training-tests`, `temp/generation-tests`) para
    que os verificadores anteriores continuem varrendo apenas o próprio
    diretório. O novo diretório é `temp/context-tests`.
13. **Linhas longas.** A maior linha nova é `HISTORICO` com 33 inteiros
    (~330 caracteres) e `PARAM16` com 12 inteiros (~60). A M6 já comprovou 480
    caracteres sem truncamento; E0/P8 reconfirma com o formato novo.
14. **Inteiros.** O caminho quente usa apenas `inteiro`; nenhum `real`,
    `%` negativo ou divisão real. A prova de faixa da spec §3.3 limita
    `|Z256| ≤ 3.328`, `S ≤ 1.926.758.400` e intermediários de atualização a
    `90.112`, todos abaixo de 32 bits assinado.
15. **Codificação.** `.por`, `.expected` e scripts novos em ASCII/UTF-8 sem BOM,
    LF apenas, um LF final nos `.por`; `.expected` sem LF final. `test.ps1`
    permanece com BOM e último byte `0x7D`.

## 3. Decisões de execução

Herdadas da spec (§2, §5–§9) e fixadas para a implementação:

| ID | Decisão |
| --- | --- |
| D1 | Contexto = concatenação de `K = 3` embeddings; média e peso posicional rejeitados na spec §2.1 |
| D2 | Posições `k = 0,1,2` do mais antigo para o mais recente; o último token está sempre em `k=2` |
| D3 | Sequências curtas usam preenchimento à esquerda com vetor zero; `PAD` não é `UNK` (0) |
| D4 | Uma camada afim `12 → 25`; 300 pesos + 25 vieses = 325 parâmetros; sem camada oculta |
| D5 | Inicialização: fatias `k=0,1` zeradas; fatia `k=2` igual à tabela canônica da M5; `b16` igual à M5 |
| D6 | Caminho inteiro `Z256`; nenhum `real` em forward, perda, treino, geração ou impressão |
| D7 | SGD por exemplo, ordem fixa `n=0..5`, `η = 1/8`, 7 épocas canônicas |
| D8 | Atualização quantizada `r(2048·W − δ·c, 2048)` e `r(128·b − δ, 128)`, meio para longe de zero |
| D9 | `δ` é congelado por exemplo antes de qualquer escrita; `y` cresce, `p` cresce, `b` por último |
| D10 | Limite `|W16|,|b16| ≤ 16`; violação retorna código 5 com estado parcial possível |
| D11 | Conjunto canônico de 6 exemplos da spec §8.1, sem alteração após ver o resultado |
| D12 | Geração aceita prefixo de 1..3 tokens, `maximo` 1..64; `pare` (24) tem precedência sobre `MAXIMO` |
| D13 | Sem detecção de ciclo; repetições preservadas; `UNK` não é parada |
| D14 | `src/gerador.por` e a M6 **não** são alterados; compatibilidade é demonstrada por construção de estado |
| D15 | Erros de treino 1–4 e de geração 1–3 não mutam estado nem buffer; erro 5 pode deixar estado parcial |
| D16 | Funções puras (`ctx_z256`, `ctx_argmax`, `ctx_perda_escalada`, `ctx_acertos`, `ctx_montar_contexto`) não validam, não imprimem e não mutam |
| D17 | Diagnósticos derivados (`MARGENS`, `MUDOU_*`, `ABL_*`, `ORDEM_DISTINTOS`, `PAD_DISTINTO`, `E16_OK`, `M4_OK`, `M5_OK`, `M6_OK`) são calculados pelo **driver** e impressos por ele; não fazem parte das impressoras do módulo |
| D18 | O builder concatena fragmentos e driver em um `.por` autocontido; nenhum `inclua` entre fragmentos |
| D19 | Prefixos `ctx_`/`CTX_`; nenhum símbolo novo sem prefixo |
| D20 | Nenhum commit, push, tag, reset, clean ou operação remota nesta fase |

D5 é o que dá a regressão forte: no estado inicial, o M7 é **exatamente** a M5
para contextos de um token. D14 impede "consertar" a M6 para acomodar o M7.

## 4. Arquivos

### 4.1 Autorizados na implementação futura

| Arquivo | Ação | Conteúdo |
| --- | --- | --- |
| `src/contexto.por` | criar | fragmento ASCII: 18 constantes, validadores, `ctx_e16`, contexto, `Z256`, argmax, perda, acertos, `r`, init, execução, geração e 9 impressoras |
| `scripts/build-context-tests.ps1` | criar | gera 16 `.por` + 16 `.expected` em `temp/context-tests/` |
| `scripts/verify-context-bytes.ps1` | criar | V1–V16, oráculo independente, regressão embutida |
| `scripts/test.ps1` | alterar (aditivo) | sexto bloco de descoberta/anexo, 24 linhas, dentro de `if (-not $SelfTest)` |
| `docs/context-spec.md` | atualizar em E7 | status, registro de execução, nenhuma regra normativa alterada |
| `docs/context-plan.md` | atualizar em E7 | este plano e log de evidências |

### 4.2 Proibidos

`src/tokenizador.por`, `src/embeddings.por`, `src/rede.por`, `src/treino.por`,
`src/gerador.por`, `tests/*`, `scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`,
`scripts/build-embedding-tests.ps1`, `scripts/verify-embedding-bytes.ps1`,
`scripts/build-network-tests.ps1`, `scripts/verify-network-bytes.ps1`,
`scripts/build-training-tests.ps1`, `scripts/verify-training-bytes.ps1`,
`scripts/build-generation-tests.ps1`, `scripts/verify-generation-bytes.ps1`,
`README.md`, `AGENTS.md`, `.gitignore`, qualquer arquivo em `.git/`.

### 4.3 Artefatos descartáveis (ignorados)

`temp/e0-ctx/` (sondas e drivers de scratch), `temp/context-tests/` (casos
gerados), `temp/m7-*.log` e `temp/m7_*.py` (simulações desta fase). Nada é
rastreado; `git status --short` deve continuar mostrando apenas os arquivos
autorizados.

## 5. E0 — Sondas e congelamento

**Objetivo:** provar ou refutar as suposições da spec §3–§10 antes de escrever o
módulo.

**Arquivos permitidos:** apenas `temp/e0-ctx/*.por`, `temp/e0-ctx/*.ps1` e
`temp/e0-ctx/results.txt`.

**Procedimento:** um driver por sonda, executado com o mesmo runner
(`portugol-console.bat`, stdin `" "`), saída capturada em texto bruto e anotada em
§11. Nenhum teste do repositório é alterado antes de E6.

### 5.1 Sondas

| ID | Programa mínimo | Observação esperada | Se falhar |
| --- | --- | --- | --- |
| P1 | `inteiro w16[300]`; escrever `w16[0]=-16`, `w16[299]=15`; ler ambos | sem `AVISO`; valores preservados | G1 |
| P2 | `b16[25]`, `c16[12]`, `entradas[18]`, `alvos[6]`, `historico[33]`, `saida[64]` | seis arrays sem `AVISO` | G1 |
| P3 | pior caso: `12·16·16 + 16·16`, `25·6·3584²`, `2048·16 + 3584·16` | `3328`, `1926758400`, `90112` | G2 |
| P4 | `ctx_div_arredondada` com `(1,2)`, `(-1,2)`, `(3,2)`, `(-3,2)`, `(0,2048)`, `(1023,2048)`, `(-1023,2048)` | `1 -1 2 -2 0 0 0`; meio para longe de zero | G6 |
| P5 | função com 6 parâmetros, sendo 4 arrays (`w16,b16,prefixo,saida`) | compila e executa | G3 |
| P6 | `retorne` de dentro de dois `enquanto` aninhados com código de erro | retorno correto, sem continuação | G3 |
| P7 | argmax com 25 logits iguais; e com máximo único no fim | `0` no empate; índice certo no único | G7 |
| P8 | imprimir 25 linhas `PARAM16` (12 inteiros + viés) e uma linha `HISTORICO` com 33 inteiros | sem truncamento; hexdump confirma | G4 |
| P9 | passar `w16[300]` para função e mutar `w16[299]`; ler no chamador | mutação visível; sem cópia | G3 |
| P10 | concatenar `tokenizador + embeddings + rede + treino + gerador + contexto` + driver vazio | sem símbolo duplicado; compila | G8 |
| P11 | `ctx_gerar` com prefixo `9`, `maximo=64`; ler `saida[0..63]` | `N=64`, `PASSOS=63`, sem acesso fora do buffer | G5 |
| P12 | 6 exemplos × 32 épocas + geração de 64 tokens | < 20 s | G9 |
| P13 | o mesmo driver em dois processos consecutivos | bytes idênticos | G10 |
| P14 | BOM/CRLF/EOF de `.por`, `.expected` e scripts | ASCII, LF, sem BOM; `test.ps1` com BOM e último byte `0x7D` | G10 |
| P15 | composição M1–M6: IDs, `e16`, argmax M4/M5, mapa M6 | `IDS=9 12 13 14 24`; `E16_OK=100`; `M5_OK=25`; `M6_CADEIA=9 12 13 14 24` | G11 |
| P16 | estado `w16` todo `-16`, `b16` todo `0`, exemplo `[9,9,9]→0`, `n=1`, `epocas=1` | `ERRO=ESTOURO_NUMERICO`; `w16[0]=-20`, demais `-16`, `b16=0` | G12 |

### 5.2 Critérios de conclusão de E0

- As 16 sondas executadas e registradas com saída bruta.
- Formato congelado: `INFO=CTX 3 12 325 300`, `TAXA=1/8`, `GRADE=1/16`,
  `EPOCAS=7`, `ESCALA_PERDA=131072`, `LIMITE_PARAM=16`, `ORDEM=EXEMPLO`.
- Se qualquer valor canônico ou formato mudar, a spec sobe para `v1.1.0`
  **antes** de E1, e todos os `.expected` são gerados depois da mudança.
- Tabela de gates preenchida com o resultado real; nenhum gate disparado sem
  ação registrada.

### 5.3 Gates

| Gate | Gatilho | Ação pré-aprovada |
| --- | --- | --- |
| G1 | P1/P2: array de 300/33/64 emite `AVISO` ou falha | **BLOQUEAR**. Não reduzir `K`, `N` ou `maximo`; o formato e a prova de faixa dependem desses tamanhos |
| G2 | P3: qualquer valor excede 32 bits assinado | **BLOQUEAR**. Não reduzir `CTX_LIMITE` nem `N` para "caber" |
| G3 | P5/P6/P9: assinatura, retorno aninhado ou mutação de array falha | função única `ctx_executar_e_imprimir`/`ctx_gerar_e_imprimir`; API reduzida; spec `v1.1.0`; regenerar tudo |
| G4 | P8: linha de 33 inteiros truncada | **BLOQUEAR**; o formato `HISTORICO` não pode ser fatiado sem mudar a spec |
| G5 | P11: buffer de 64 emite `AVISO` ou `N` errado | `saida[65]` e checagem `n_atual < CTX_TOKENS_MAX`; nenhuma outra mudança |
| G6 | P4: arredondamento diverge do meio para longe de zero | **BLOQUEAR**; o ponto fixo e a tabela final dependem disso |
| G7 | P7: empate não fica com o menor `y` | **BLOQUEAR**; a M4/M5/M6 já congelaram essa regra |
| G8 | P10: colisão de símbolo ou separador extra | renomear com `ctx_`/`CTX_`; corrigir a escrita |
| G9 | P12 > 20 s | reduzir o caso `ctx_limites` para `epocas=8` e registrar a limitação; **não** alterar `ctx_treino` (7 épocas) |
| G10 | P13/P14: BOM, CR, EOF ou bytes divergentes | corrigir builder/inserção; não aceitar `.por` com CR |
| G11 | P15: `e16`, argmax ou mapa M6 diverge | **BLOQUEAR**; não mascarar, não usar tolerância, não "ajustar" valor |
| G12 | P16: estado parcial do estouro difere | **BLOQUEAR**; a ordem de escrita e o ponto de retorno são normativos |

Resultado medido em E0: **nenhum gate disparou**. As 16 sondas P1–P16
passaram; a evidência bruta está em `temp/e0-ctx/results.txt` e o resumo em
§11.1.

## 6. Etapas E1–E7

Cada etapa termina com um driver de scratch em `temp/e0-ctx/manual/` (não
rastreado) e só avança quando a saída bate com o oráculo.

### E1 — Esqueleto, constantes, validadores, contexto e config

- **Arquivos:** `src/contexto.por` (novo).
- **Conteúdo:** cabeçalho comentado, 18 constantes, `ctx_id_valido`,
  `ctx_n_valido`, `ctx_epocas_validas`, `ctx_maximo_valido`,
  `ctx_prefixo_valido`, `ctx_params_validos`, `ctx_e16`,
  `ctx_montar_contexto`, `ctx_contexto_de_exemplo`, `ctx_z256`, `ctx_argmax`,
  `ctx_inicializar`, `ctx_imprimir_config`, `ctx_imprimir_contexto`.
- **Teste local:** 7 linhas de config; tabela inicial de 25 linhas; `MAXIMO16=12
  4`; 5 linhas `CTX16` de §4.3; mapa inicial de 25 valores
  `0 11 19 19 24 11 1 19 2 10 11 19 19 6 11 11 19 23 10 11 19 19 6 0 11`.
- **Gates resolvidos aqui:** G1, G2, G3, G5, G6, G7.
- **Ponto crítico:** `ctx_e16` idêntico a `treino_emb16` nos 100 pares; padding
  zero distinto de `UNK`.

### E2 — Perda, acertos, validação e avaliação

- **Conteúdo:** `ctx_perda_escalada`, `ctx_acertos`, `ctx_div_arredondada`,
  `ctx_validar`, `ctx_imprimir_validacao`, `ctx_imprimir_avaliacao`.
- **Teste local:** `PERDA=6728768`, `ACERTOS=0`, `PRED=6 11 6 19 10 6`;
  códigos 1–4 na ordem de precedência; `INTACTO=OK` em todos os erros de
  validação.
- **Ponto crítico:** validar antes de acessar arrays; nenhuma escrita em
  `w16`/`b16`.

### E3 — Uma época e evidência de direção

- **Conteúdo:** `ctx_executar` com 1 época, histórico, alterados e estado.
- **Teste local:** `HISTORICO=6728768 465936`; `PERDA=465936`; `ACERTOS=4`;
  `PRED=9 0 10 24 11 9`; `ALTERADOS_W=254`; `ALTERADOS_B=24`.
- **Ponto crítico:** `δ` congelado por exemplo; ordem `n=0..5`, `y=0..24`,
  `p=0..11`, viés por último.

### E4 — Sete épocas, ponto fixo e estado final

- **Conteúdo:** execução de 7 épocas, tabela final, 8ª época de controle.
- **Teste local:** `HISTORICO` com 8 valores; `PERDA=153027`; `ACERTOS=6`;
  `PRED=14 24 10 24 11 9`; `ALTERADOS_W=249`; `ALTERADOS_B=24`;
  `MAXIMO16=11 5`; `MUDOU_W=0`; `MUDOU_B=0`.
- **Ponto crítico:** tabela final idêntica à spec §7.7; nenhum parâmetro em
  `|v| > 16`.

### E5 — Geração, erros e estouro

- **Conteúdo:** `ctx_gerar`, `ctx_imprimir_geracao`, validação de geração,
  códigos 1–3 e testemunho de estouro do treino (código 5).
- **Teste local:** cadeia `9 12 13 → 14 → 24`; `maximo=3/4`; prefixo `24` e
  `12 24`; 64 tokens a partir de `9`; códigos 1–5; estado parcial
  `w16[0]=-20`.
- **Ponto crítico:** `PARE` vence `MAXIMO`; erro não escreve em `saida`; o
  gerador não muta parâmetros.

### E6 — Builder, runner e 16 casos

- **Arquivos:** `scripts/build-context-tests.ps1`; bloco aditivo em
  `scripts/test.ps1`.
- **Teste local:** 16 `.por` + 16 `.expected`; suíte **100 PASS / 0 FAIL**, exit
  `0`; autoteste **0 PASS / 1 FAIL**, exit `1`; M1–M6 preservados.
- **Ponto crítico:** preservar BOM e último byte `0x7D` de `test.ps1`; o bloco é
  puramente aditivo; `temp/context-tests` não interfere nos diretórios antigos.

### E7 — Verificador, regressão final e documentação

- **Arquivos:** `scripts/verify-context-bytes.ps1`; atualização de status e
  evidências nos dois docs.
- **Conteúdo:** V1–V16; re-derivação independente das tabelas, trajetória,
  margens, ablações e geração; segunda execução A/B; conferência de hashes.
- **Teste local:** verificador **16/16**, exit `0`; M1 21/21, M3 19/19, M4 22/22,
  M5 23/23, M6 13/13; suíte 100/100; autoteste exit `1`.
- **Fechamento:** `git status --short` e `git diff --stat` restritos aos
  arquivos autorizados; evidências registradas na spec §18 e neste plano §11.

## 7. Matriz de testes

### 7.1 Convenções dos drivers

- Arrays padrão: `inteiro w16[300]`, `b16[25]`, `c16[12]`, `entradas[18]`,
  `alvos[6]`, `historico[33]`, `saida[64]`.
- Estado inicial: `ctx_inicializar(w16,b16)`.
- Estado treinado: `ctx_inicializar` + `ctx_executar(w16,b16,entradas,alvos,6,7,historico)`.
- Entradas canônicas: `9 12 13  12 13 14  12 9 13  9 13 12  13 12 9  14 12 13`.
- Alvos canônicos: `14 24 10 24 11 9`.
- Linhas derivadas são calculadas pelo driver com funções puras do módulo; não
  são impressoras e não alteram o formato do módulo (D17).
- Cada `.por` é autocontido (fragmentos + driver) e cada `.expected` termina sem
  LF, CR ou BOM.

### 7.2 Casos e saídas esperadas

| # | Caso | Setup | Saída esperada (resumo) |
| ---: | --- | --- | --- |
| 1 | `ctx_init` | config; init; avaliação | 7 linhas de config + 25 `PARAM16` + `MAXIMO16=12 4` + `PERDA=6728768`, `ACERTOS=0`, `PRED=6 11 6 19 10 6` |
| 2 | `ctx_contexto_k` | históricos de 1..5 tokens | 5 linhas `CTX16` de §7.3; `PAD_DISTINTO=OK` |
| 3 | `ctx_contexto_ordem` | 4 permutações de `{9,12,13}`; grupo do último `13` | 4 vetores distintos; `ORDEM_DISTINTOS=4`; `MESMO_ULTIMO=14 10 9` |
| 4 | `ctx_treino` | 7 épocas; tabela, histórico, alterados, margens | 25 `PARAM16`; `MAXIMO16=11 5`; `HISTORICO`; `PERDA=153027`; `ACERTOS=6`; `PRED=14 24 10 24 11 9`; `249/24`; `MARGENS=142 151 156 174 201 167` |
| 5 | `ctx_ponto_fixo` | 7 épocas, snapshot, 8ª época | `S7=153027`, `S8=153027`, `MUDOU_W=0`, `MUDOU_B=0` |
| 6 | `ctx_ablation` | estado final; fatias 0/1 zeradas; fatia 2 zerada | `ABL_FULL=6`; `ABL_ULTIMO=1`; `ABL_ULTIMO_S=916888`; `ABL_ANTIGOS=6`; `ABL_ANTIGOS_S=717503`; `ABL_ULTIMO_MAX=4`; `ABL_BAG_MAX=2` |
| 7 | `ctx_geracao_cadeia` | treinado; prefixo `9 12 13`, `maximo=64` | `9 12 13 14 24`; `N=5`; `PASSOS=2`; `PARE`; texto |
| 8 | `ctx_geracao_limites` | treinado; `maximo=4/3`; prefixos `24` e `12 24` | blocos de §7.4 |
| 9 | `ctx_geracao_semente` | treinado; prefixos `9` e `12`, `maximo=10` | `9 10 11 14 11 19 11 19 11 19`; `12 19 11 19 11 19 11 19 11 19`; `N=10`; `MAXIMO` |
| 10 | `ctx_erros_treino` | 11 chamadas inválidas + válida + estouro | códigos 1–5 na ordem; `INTACTO=OK`; `PARCIAL_W0=-20`; `PARCIAL_B0=0` |
| 11 | `ctx_erros_geracao` | 10 chamadas inválidas + pureza | códigos 1–3 na ordem; `SAIDA_INTACTA=OK`; `PARAMS_INTACTOS=OK` |
| 12 | `ctx_determinismo_a` | execução completa | 25 `PARAM16` + `MAXIMO16` + `HISTORICO` + 2 blocos de geração |
| 13 | `ctx_determinismo_b` | idêntico a A | bytes idênticos a A |
| 14 | `ctx_composicao` | M1/M3/M4/M5/M6 + contexto | `IDS=9 12 13 14 24`; `E16_OK=100`; `M4_OK=25`; `M5_OK=25`; `M6_OK=25`; `M6_CADEIA=9 12 13 14 24`; `COMPOE=OK` |
| 15 | `ctx_limites` | `n=6`, `epocas=32`, `maximo=64` | `HISTORICO` com 33 valores; `ACERTOS=6`; `N=64`; `PASSOS=63`; `MAXIMO` |
| 16 | `ctx_params_intactos` | forward, perda, contexto, geração válida e inválida | `PARAMS_INTACTOS=OK`; `SAIDA_INTACTA=OK` |

Total: **16 casos novos**; suíte **84 + 16 = 100**.

### 7.3 Blocos congelados de contexto

`ctx_contexto_k`:

```
CTX16=1 0 0 0 0 0 0 0 0 11 14 -15 -12
CTX16=2 0 0 0 0 15 -14 -11 -8 11 14 -15 -12
CTX16=3 15 -14 -11 -8 4 7 10 13 11 14 -15 -12
CTX16=4 15 -14 -11 -8 4 7 10 13 11 14 -15 -12
CTX16=5 5 8 11 14 12 15 -14 -11 -13 -10 -7 -4
PAD_DISTINTO=OK
```

`ctx_contexto_ordem`:

```
CTX16=3 15 -14 -11 -8 4 7 10 13 11 14 -15 -12
CTX16=3 4 7 10 13 15 -14 -11 -8 11 14 -15 -12
CTX16=3 15 -14 -11 -8 11 14 -15 -12 4 7 10 13
CTX16=3 11 14 -15 -12 4 7 10 13 15 -14 -11 -8
ORDEM_DISTINTOS=4
MESMO_ULTIMO=14 10 9
```

`ctx_treino` (fim do bloco):

```
MAXIMO16=11 5
HISTORICO=6728768 465936 282923 216490 193677 183943 167288 153027
PERDA=153027
ACERTOS=6
PRED=14 24 10 24 11 9
ALTERADOS_W=249
ALTERADOS_B=24
MARGENS=142 151 156 174 201 167
```

`ctx_ponto_fixo`:

```
S7=153027
S8=153027
MUDOU_W=0
MUDOU_B=0
```

`ctx_ablation`:

```
ABL_FULL=6
ABL_FULL_S=153027
ABL_ULTIMO=1
ABL_ULTIMO_S=916888
ABL_ANTIGOS=6
ABL_ANTIGOS_S=717503
ABL_ULTIMO_MAX=4
ABL_BAG_MAX=2
```

### 7.4 Blocos congelados de geração

`ctx_geracao_cadeia`:

```
GERADO=9 12 13 14 24
N=5
PASSOS=2
PARADA=PARE
TEXTO=se faca para ate pare
```

`ctx_geracao_limites` (quatro blocos, nesta ordem):

```
GERADO=9 12 13 14
N=4
PASSOS=1
PARADA=MAXIMO
TEXTO=se faca para ate
GERADO=9 12 13
N=3
PASSOS=0
PARADA=MAXIMO
TEXTO=se faca para
GERADO=24
N=1
PASSOS=0
PARADA=PARE
TEXTO=pare
GERADO=12 24
N=2
PASSOS=0
PARADA=PARE
TEXTO=faca pare
```

`ctx_geracao_semente` (dois blocos):

```
GERADO=9 10 11 14 11 19 11 19 11 19
N=10
PASSOS=9
PARADA=MAXIMO
TEXTO=se senao enquanto ate enquanto e enquanto e enquanto e
GERADO=12 19 11 19 11 19 11 19 11 19
N=10
PASSOS=9
PARADA=MAXIMO
TEXTO=faca e enquanto e enquanto e enquanto e enquanto e
```

`ctx_limites` (cauda do bloco de 64 tokens):

```
N=64
PASSOS=63
PARADA=MAXIMO
```

O bloco completo de `GERADO` com 64 IDs está na spec Apêndice C. O driver deve
imprimir `GERADO` em uma única linha; P8/G4 comprovam que não há truncamento.

### 7.5 Blocos congelados de erro

Treino — ordem e códigos:

```
ERRO=EXEMPLOS_INVALIDOS
INTACTO=OK
ERRO=EXEMPLOS_INVALIDOS
INTACTO=OK
ERRO=EPOCAS_INVALIDAS
INTACTO=OK
ERRO=EPOCAS_INVALIDAS
INTACTO=OK
ERRO=ID_INVALIDO
INTACTO=OK
ERRO=ID_INVALIDO
INTACTO=OK
ERRO=PARAMETROS_INVALIDOS
INTACTO=OK
ERRO=PARAMETROS_INVALIDOS
INTACTO=OK
ERRO=EXEMPLOS_INVALIDOS
INTACTO=OK
ERRO=EPOCAS_INVALIDAS
INTACTO=OK
ERRO=ID_INVALIDO
INTACTO=OK
VALIDO=OK
ERRO=ESTOURO_NUMERICO
PARCIAL_W0=-20
PARCIAL_W1=-16
PARCIAL_W299=-16
PARCIAL_B0=0
PARCIAL_B24=0
```

As chamadas, na ordem: `n=0`; `n=7`; `n=6,epocas=0`; `n=6,epocas=33`;
`entradas[0]=25`; `alvos[0]=-1`; `w16[0]=17`; `b16[0]=-17`; precedência
`n=0,epocas=0`; precedência `epocas=0,entradas[0]=25`; precedência
`entradas[0]=25,w16[0]=17`; chamada válida; estouro de §5.1/P16.

Geração — ordem e códigos:

```
ERRO=PREFIXO_INVALIDO
SAIDA_INTACTA=OK
ERRO=PREFIXO_INVALIDO
SAIDA_INTACTA=OK
ERRO=PREFIXO_INVALIDO
SAIDA_INTACTA=OK
ERRO=PREFIXO_INVALIDO
SAIDA_INTACTA=OK
ERRO=MAXIMO_INVALIDO
SAIDA_INTACTA=OK
ERRO=MAXIMO_INVALIDO
SAIDA_INTACTA=OK
ERRO=MAXIMO_INVALIDO
SAIDA_INTACTA=OK
ERRO=PARAMETROS_INVALIDOS
SAIDA_INTACTA=OK
ERRO=PREFIXO_INVALIDO
SAIDA_INTACTA=OK
ERRO=MAXIMO_INVALIDO
SAIDA_INTACTA=OK
PARAMS_INTACTOS=OK
```

As chamadas, na ordem: `n=0`; `n=4`; prefixo `[25]`; `[24,9]`; `maximo=0`;
`maximo=65`; prefixo de 3 com `maximo=2`; parâmetros com `|v|=17`; precedência
`n=0,maximo=0`; precedência `maximo=0,|v|=17`; conferência final de pureza.
Todos os buffers de saída são preenchidos com `99` antes de cada chamada
inválida; `SAIDA_INTACTA=OK` exige os 64 valores ainda `99`.

### 7.6 Codificação dos `.expected`

- ASCII ou UTF-8 sem BOM.
- LF apenas; nenhum CR.
- Sem LF final, pois `Normalize-Output` aplica `.Trim()`.
- Nenhuma linha com espaços à esquerda/direita.
- `TEXTO` com espaço simples entre palavras e sem espaço final.

## 8. Critérios de aceitação

| AC | Verificação | Resultado exigido | Status |
| ---: | --- | --- | --- |
| AC1 | pré-voo | `main`, `HEAD 38fc295…`, árvore limpa, 84/84 | **PASS** (medido em E0) |
| AC2 | `git status --short` | somente os 6 arquivos de §4.1 | **PASS** (6 arquivos; nenhum extra) |
| AC3 | `scripts/test.ps1` | `Passed: 100`, `Failed: 0`, exit `0` | **PASS** (100/0, exit 0) |
| AC4 | verificadores M1–M6 | 21/21, 19/19, 22/22, 23/23, 13/13, exit `0` | **PASS** (todos, exit 0) |
| AC5 | `scripts/test.ps1 -SelfTest` | `0 PASS / 1 FAIL`, exit `1` | **PASS** (0/1, exit 1) |
| AC6 | `scripts/verify-context-bytes.ps1` | `Checks: 16`, `Failures: 0`, exit `0` | **PASS** (16/0, exit 0) |
| AC7 | `ctx_init` | tabela de §5.2, `MAXIMO16=12 4` | **PASS** (e1.txt) |
| AC8 | `ctx_contexto_k` | 5 linhas `CTX16`, `PAD_DISTINTO=OK` | **PASS** (e1.txt) |
| AC9 | `ctx_contexto_ordem` | 4 vetores distintos, `ORDEM_DISTINTOS=4` | **PASS** (V7) |
| AC10 | `ctx_treino` | `HISTORICO` de §7.4, `6/6`, `PRED=14 24 10 24 11 9` | **PASS** (e4.txt) |
| AC11 | mesmo último token | `13` → `14,10,9` | **PASS** (`MESMO_ULTIMO=14 10 9`) |
| AC12 | ordem treinada | `{9,12,13}` → `14,10,24,11` | **PASS** (`PRED=14 24 10 24 11 9`) |
| AC13 | ponto fixo | 8ª época sem mudança | **PASS** (`S8=153027`, `MUDOU_*=0`) |
| AC14 | aprendizado | queda 97,7258%, margens ≥ 142, `249/24` | **PASS** (97,7258%; `MARGENS`) |
| AC15 | ablações | completo 6/6; último token 1/6; limites 4/6 e 2/6 | **PASS** (`6/1/4/2`) |
| AC16 | geração cadeia | `9 12 13 14 24`, `PARE`, texto | **PASS** (e5.txt) |
| AC17 | geração limites | `maximo` 3/4, prefixos `24`/`12 24`, `N=64` em `ctx_limites` | **PASS** (V11/V15) |
| AC18 | erros | códigos 1–5 e 1–3, precedência, estado/saída | **PASS** (V12) |
| AC19 | determinismo | A ≡ B nos `.expected` e nas execuções | **PASS** (V13) |
| AC20 | composição | M1/M3/M4/M5/M6; 25 seeds da M6 | **PASS** (`100/25/25/25`) |
| AC21 | pureza | parâmetros intactos; `SAIDA_INTACTA` | **PASS** (V12/V16) |
| AC22 | documentação | spec e plano com evidências medidas | **PASS** (§11.1 e §11.5) |

AC2 nesta fase é mais restrito que na execução: apenas os dois docs. Na
execução, AC2 passa a exigir somente os arquivos de §4.1.

## 9. Oráculo independente e verificador

### 9.1 Oráculo

O oráculo não lê `.expected` nem reutiliza funções do módulo. Ele é definido
pelas fórmulas da spec §4–§7 e foi implementado duas vezes nesta fase:

1. **inteiro** (`W16`, `b16`, `c16`, `Z256`, `δ256`, `r`);
2. **racional exato** (`fractions.Fraction`, estado em `1/16`, atualização e
   quantização em racionais).

As duas concordaram em `S0..S7`, na tabela final, nas predições, nas margens,
nas ablações e nos blocos de geração. Na implementação:

- o builder é uma terceira derivação;
- `src/contexto.por` é a quarta;
- `scripts/verify-context-bytes.ps1` é uma quinta, independente do builder;
- a auditoria de E7 refaz uma sexta derivação, sem consultar as anteriores.

Nenhuma delas decide o valor esperado lendo a saída do `.por`.

### 9.2 Verificador V1–V16

| ID | Verificação | Falha se |
| ---: | --- | --- |
| V1 | hashes dos 16 arquivos congelados e diff aditivo de `test.ps1` | qualquer hash mudar ou o diff tocar fora do bloco |
| V2 | codificação dos dois docs e dos 16 `.por`/`.expected` | BOM, CR, LF final indevido ou caractere não ASCII inesperado |
| V3 | 7 linhas de config | qualquer constante divergir |
| V4 | tabela inicial de 25 linhas e `MAXIMO16=12 4` | qualquer posição divergir |
| V5 | avaliação inicial `S0=6728768`, `PRED=6 11 6 19 10 6`, `0/6` | valor ou ordem divergir |
| V6 | contextos de 1..5 tokens, padding e `PAD_DISTINTO` | vetor, janela ou distinção de `UNK` falhar |
| V7 | 4 permutações de `{9,12,13}` e grupo do último `13` | colisão ou `ORDEM_DISTINTOS != 4` |
| V8 | trajetória `S0..S7`, tabela final, margens e alterados | qualquer valor divergir |
| V9 | 8ª época: `S7=S8`, `MUDOU_W=0`, `MUDOU_B=0` | qualquer mudança |
| V10 | ablações e limites superiores 4/6 e 2/6 | acurácia ou `S` divergir |
| V11 | blocos de geração de §7.4 e 64 tokens | `GERADO`, `N`, `PASSOS` ou `PARADA` divergir |
| V12 | códigos de erro, precedência, estado parcial e buffers | código, ordem ou integridade divergir |
| V13 | A ≡ B byte a byte | qualquer byte diferir |
| V14 | composição M1–M6: IDs, `e16`, argmax, mapa e cadeia | qualquer contagem ou mapa divergir |
| V15 | `n=6`, `epocas=32`, `maximo=64` | `HISTORICO` não tiver 33 valores ou `N != 64` |
| V16 | pureza + suíte 100/100 + M1–M6 + autoteste | qualquer regressão ou mutação |

O verificador imprime `Checks: 16`, `Failures: 0` e sai com `0` apenas se todas
as verificações passarem. Ele **recalcula** os valores a partir das fórmulas; não
compara `.expected` com `.expected`.

## 10. Riscos, fallbacks e limitações

| Risco | Probabilidade | Impacto | Mitigação | Fallback |
| --- | --- | --- | --- | --- |
| Array de 300 posições emite `AVISO` | baixa | alto | P1/P2 em E0 | **BLOQUEAR** (G1) |
| Linha de 33 inteiros truncada | baixa | alto | P8 | **BLOQUEAR** (G4) |
| Arredondamento diferente no ponto médio | média | alto | P4 com 7 casos | **BLOQUEAR** (G6) |
| Ordem de atualização alterada | média | alto | E3/E4 comparam trajetória exata | corrigir; não ajustar valores |
| `test.ps1` perde BOM ou `0x7D` | média | médio | inserção por bytes + P14 | corrigir e reexecutar |
| `.expected` com LF final | média | médio | builder grava sem LF; V2 | corrigir builder |
| `ctx_limites` lento | baixa | baixo | P12; orçamento 20 s | `epocas=8` no caso de limite (G9) |
| Ablação "tokens antigos" também acerta | certa | baixo | documentada na spec §8.4 | nenhum; é propriedade do conjunto |
| Conjunto pequeno não generaliza | certa | baixo | limitação explícita | nenhum; fora de escopo |
| Colisão de símbolo | baixa | médio | prefixo `ctx_`; P10 | renomear (G8) |
| Mutação acidental em geração | baixa | alto | `ctx_params_intactos`; V16 | corrigir; não relaxar teste |
| Overflow silencioso | baixa | alto | prova de faixa + P3 + código 5 | **BLOQUEAR** (G2) |

### 10.1 Limitações

- Contexto de **3 tokens**, não de longo prazo.
- Uma camada afim, sem atenção, recorrência ou camada oculta.
- Vocabulário fechado de 25 IDs; `UNK` sem semântica.
- 6 exemplos sintéticos; nenhuma generalização linguística demonstrada.
- Texto é projeção impressa, não detokenização inversa.
- O conjunto não força cada posição individualmente; a ablação "tokens antigos"
  também acerta 6/6. A ablação decisiva é "somente último token" (1/6).
- A parada é apenas `pare` ou limite; não há detecção de ciclo.
- Não há commit, push, tag ou operação remota nesta fase.

## 11. Registro de evidências e condição de parada

### 11.1 Evidências (medidas)

| Etapa | Evidência exigida | Caminho | Status |
| --- | --- | --- | --- |
| E0 | 16 sondas + tabela de gates | `temp/e0-ctx/results.txt` | **CONCLUÍDA** — P1–P16; P13 idêntico; P14 ASCII/sem BOM/sem CR/LF final |
| E1 | config, tabela inicial, 5 `CTX16`, mapa inicial | `temp/e0-ctx/manual/e1.txt` | **CONCLUÍDA** — `MAXIMO16=12 4`, `E16_OK=100` |
| E2 | `PERDA=6728768`, `0/6`, códigos 1–4 | `temp/e0-ctx/manual/e2.txt` | **CONCLUÍDA** — `PRED=6 11 6 19 10 6`, `VALIDO=OK` |
| E3 | `HISTORICO=6728768 465936`, `4/6`, `254/24` | `temp/e0-ctx/manual/e3.txt` | **CONCLUÍDA** — `PERDA=465936`, `PRED=9 0 10 24 11 9` |
| E4 | `S7=153027`, `6/6`, `249/24`, ponto fixo | `temp/e0-ctx/manual/e4.txt` | **CONCLUÍDA** — `MARGENS`, `S8=153027`, `MUDOU_*=0` |
| E5 | geração, códigos 1–5, estado parcial | `temp/e0-ctx/manual/e5.txt` | **CONCLUÍDA** — 7 blocos, `PARCIAL_W0=-20`, `PARAMS_INTACTOS=OK` |
| E6 | 16 casos, suíte 100/100, autoteste 1 FAIL | `temp/m7-suite.log`, `temp/m7-selftest.log` | **CONCLUÍDA** — 16/16; 100/0 exit 0; 0/1 exit 1 |
| E7 | V1–V16, M1–M6, hashes, diff | `temp/m7-verify.log`, `temp/m7-final.log` | **CONCLUÍDA** — 16/0 exit 0; M1–M6 21/19/22/23/13 |

### 11.2 Condição de parada da fase de planejamento

Registro histórico: a fase de planejamento parou **antes** da implementação e
satisfez as condições abaixo.

1. `docs/context-spec.md` e `docs/context-plan.md` existiam.
2. `git status --short` mostrava exatamente esses dois arquivos não rastreados.
3. Ambos eram UTF-8 sem BOM, LF apenas e terminavam em um único LF.
4. Nenhum arquivo de código, script, teste, README ou AGENTS.md havia sido
   alterado.
5. Nenhum `git add`, `commit`, `push`, `tag`, `reset`, `clean` ou `restore` foi
   executado.

### 11.3 Checklist de aprovação

Aprovado antes de E0–E7:

- [x] `K=3`, concatenação, padding zero à esquerda e ordem antigo→recente.
- [x] 325 parâmetros, uma camada afim, sem atenção/recorrência/softmax.
- [x] Conjunto canônico de 6 exemplos da spec §8.1.
- [x] `η=1/8`, 7 épocas, limite 16, `S7=153027` e tabela final de §7.7.
- [x] Geração com prefixo 1..3, `maximo` 1..64 e `pare` com precedência.
- [x] 16 casos novos e suíte 100/100.
- [x] Nenhuma alteração em M1–M6, README ou AGENTS.md.
- [x] Nenhum commit ou push nesta missão.

Com o checklist aprovado e E0–E7 concluídas, o status final é **PRONTA**; as
evidências medidas estão em §11.1 e em `docs/context-spec.md` §11.5.
