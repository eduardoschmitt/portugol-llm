# Plano de execução — Geração autoregressiva determinística (M6)

- **Status:** execução concluída. E0–E7 implementadas, executadas e verificadas;
  AC1–AC20 satisfeitos (evidências em §10.1, §13 e §14). Nenhum commit ou push
  foi feito.
- **Especificação:** `docs/generation-spec.md` v1.0.0 (congelada em E0; nenhum
  gate disparou).
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0), M5
  (`docs/training-spec.md` v1.0.0).
- **Fora de escopo:** Transformer, atenção, contexto multi-token, memória, softmax,
  amostragem, temperatura, top-k, top-p, beam search, treinamento novo, embeddings
  treináveis, detokenização inversa, commit e push.

## 1. Estado de partida

Verificado nesta missão, por leitura e por comando, antes de escrever este plano:

| Item | Estado |
| --- | --- |
| `HEAD` | `0dd7ecb0ca55f918f319968de91eb4566c9db610` |
| Branch | `main` |
| Árvore de trabalho | limpa; apenas `docs/generation-spec.md` e `docs/generation-plan.md` não rastreados |
| Suíte de partida | `scripts/test.ps1` = **70 PASS / 0 FAIL**, exit `0` (medido na M5; baseline histórico) |
| M1 bytes | `scripts/verify-bytes.ps1` = **21/21** |
| M3 bytes | `scripts/verify-embedding-bytes.ps1` = **19/19** |
| M4 bytes | `scripts/verify-network-bytes.ps1` = **22/22** |
| M5 bytes | `scripts/verify-training-bytes.ps1` = **23/23** |
| Autoteste | `scripts/test.ps1 -SelfTest` = **0 PASS / 1 FAIL intencional**, exit `1` |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |
| Custo por caso | ~1,3–1,5 s por caso; suíte de 84 casos medida em E7: **215,5 s** (inclui os cinco builders) |

Composição da suíte de 70: 5 casos literais do runner + 20 de M1 + 19 de M3 + 14
de M4 + 12 de M5.

Estado final medido em E7 (M6): suíte **84 PASS / 0 FAIL**, exit `0`, com os 70
casos anteriores preservados; M6 **13/13**; autoteste **0 PASS / 1 FAIL**, exit
`1`. O detalhe está em §10.1 e §13.

Hashes de `HEAD` dos arquivos que **não podem** mudar (baseline de AC18/AC19):

```
src/tokenizador.por                    6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f
src/embeddings.por                     6f06aa820d163d3c1636383803b86105bf54cd85
src/rede.por                           fa9367a79bd2aefc373d30a94cfca2b7c86d9958
src/treino.por                         f5121423dd0aac6469b59b24b13d8a85b2c0d64d
scripts/build-tests.ps1                1cfb01202586a83c4d7ec08ff738a8e90fb19044
scripts/verify-bytes.ps1               851afbbad494778f019bf2ce70e82b0b575ab443
scripts/build-embedding-tests.ps1      94d1a3819b76b4d614f4422bf00b0cd2c008daaf
scripts/verify-embedding-bytes.ps1     4f3aa68e499a9dc3289d22ebae5b8d1c18086651
scripts/build-network-tests.ps1        998e91b2896e9ec40bc1814990a0a53ae740fb3e
scripts/verify-network-bytes.ps1       1f46800852fed34d840206ca97bc84badd109b31
scripts/build-training-tests.ps1       c587e161e19d353af23f0cb9d055119b288c2675
scripts/verify-training-bytes.ps1      f59fee82d337e13f619360e63d6e928aef8e0f6b
```

`scripts/test.ps1` em `HEAD` tem hash
`675c042443027f0ccc352fccc5da8d5456d04d83`. Ele muda por desenho (bloco
aditivo de 24 linhas), mas o restante do arquivo deve permanecer idêntico. O diff
é conferido em E6 e E7.

Comandos de referência:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-embedding-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-network-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-training-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-generation-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-generation-bytes.ps1
```

## 2. Restrições do runner

Comprovadas por leitura de `scripts/test.ps1` e pelas missões anteriores:

1. **Exit code do interpretador é sempre 0.** Falhas de execução precisam ser
   detectadas por texto; todos os casos de geração usam saídas normais.
2. **stdout começa com form feed (`0x0C`).** `Normalize-Output` remove um `\f`
   inicial.
3. **Epílogo de sucesso:**
   `"\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n"`. O corpo
   usa LF; o epílogo usa CRLF.
4. **`Normalize-Output` remove o epílogo, um `\n` final e aplica `.Trim()`.**
   Comparação `-ceq` (case-sensitive). `.expected` não pode ter `\n` final, CR,
   BOM ou espaços nas pontas.
5. **Entrada padrão:** o runner envia `" "` e fecha. Nenhum caso lê teclado.
6. **Casos gerados** são descobertos por `Get-ChildItem -Filter *.expected` em um
   diretório próprio, ordenados por nome, e anexados a `$testCases`.
7. **Autoteste** substitui `$testCases` por um único caso que deve falhar; todos os
   blocos de geração ficam dentro de `if (-not $SelfTest)`.
8. **`scripts/test.ps1` tem BOM UTF-8 e não termina em LF** (último byte `0x7D`).
   A inserção precisa preservar ambos.
9. **stdout e stderr são concatenados.** Qualquer `AVISO` (por exemplo, array
   declarado com tamanho 1) quebra o caso. O buffer é `inteiro saida[64]`.
10. **`.Trim()` é aplicado ao total.** Uma linha final `TEXTO=` sobrevive porque
    `=` não é whitespace; ainda assim, nenhum caso termina com `TEXTO=`.
11. **Nomes de caso** não podem colidir entre M0, M1, M3, M4 e M5; o prefixo `gen_`
    garante isso.
12. **Diretórios de teste independentes** (`temp/tests`, `temp/embedding-tests`,
    `temp/network-tests`, `temp/training-tests`) para que os verificadores
    anteriores continuem varrendo apenas o próprio diretório. O novo diretório é
    `temp/generation-tests`.

## 3. Decisões de execução

Herdadas da spec (§14) e fixadas para a implementação:

| ID | Decisão |
| --- | --- |
| D1 | `gerador.por` reutiliza `treino_argmax`; não duplica o forward |
| D2 | caminho inteiro `Z256`; nenhum `real` na geração |
| D3 | `argmax` com desempate pelo menor `y` |
| D4 | token inicial incluído na saída, no índice 0 |
| D5 | `maximo` conta tokens, faixa `1..64` |
| D6 | `pare` (24) é parada e é incluído |
| D7 | `PARE` tem precedência sobre `MAXIMO` |
| D8 | `UNK` (0) é token válido, não é parada |
| D9 | sem detecção de ciclo; limite garante terminação |
| D10 | repetições preservadas |
| D11 | parâmetros nunca são escritos; erro não escreve no buffer |
| D12 | texto é projeção impressa dos IDs |
| D13 | erros: `TOKEN_INVALIDO → LIMITE_INVALIDO → PARAMETROS_INVALIDOS` |
| D14 | prefixos `gerador_`/`GERADOR_`; módulo depende só da M5 |
| D15 | nenhum commit, push, tag ou remote |
| D16 | `saida[64]` é declarado pelo chamador (driver) para as chamadas diretas a `gerador_gerar`; `gerador_imprimir_geracao` declara um buffer local `saida[64]` e não recebe buffer do chamador |
| D17 | drivers de caso treinado executam a M5 de verdade (5 épocas), não usam tabela embutida |
| D18 | `CICLO`, `MAPA` e `PARAMS_INTACTOS` são calculados pelo driver, não pelo gerador |
| D19 | casos canônicos usam `treino_inicializar`; casos treinados usam `treino_executar(...,5,...)` |

D17 é o ponto que impede o teste de "provar" a cadeia com uma tabela copiada: se o
treinamento regredir, `gen_treinado_cadeia` falha.

## 4. Arquivos

### 4.1 Autorizados

| Arquivo | Ação | Conteúdo |
| --- | --- | --- |
| `src/gerador.por` | criar | fragmento ASCII: 7 constantes, 2 validadores, `gerador_proximo`, `gerador_gerar`, 5 impressoras e `gerador_escrever_palavra` |
| `scripts/build-generation-tests.ps1` | criar | gera 14 `.por` + 14 `.expected` em `temp/generation-tests/` |
| `scripts/verify-generation-bytes.ps1` | criar | V1–V13, oráculo independente, regressão embutida |
| `scripts/test.ps1` | alterar (aditivo) | quinto bloco de geração/anexo, 24 linhas, dentro de `if (-not $SelfTest)` |
| `docs/generation-spec.md` | atualizado em E7 | status e evidências medidas; nenhuma regra normativa mudou |
| `docs/generation-plan.md` | atualizado em E7 | este plano e log de execução |

### 4.2 Proibidos

`src/tokenizador.por`, `src/embeddings.por`, `src/rede.por`, `src/treino.por`,
`tests/*`, `scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`,
`scripts/build-embedding-tests.ps1`, `scripts/verify-embedding-bytes.ps1`,
`scripts/build-network-tests.ps1`, `scripts/verify-network-bytes.ps1`,
`scripts/build-training-tests.ps1`, `scripts/verify-training-bytes.ps1`,
`README.md`, `AGENTS.md`, `.gitignore`, qualquer arquivo em `.git/`.

### 4.3 Artefatos descartáveis (ignorados)

`temp/e0-gen/` (sondas e drivers de scratch), `temp/generation-tests/` (casos
gerados). Nada é rastreado; `git status --short` deve continuar mostrando apenas
os arquivos autorizados.

## 5. E0 — Sondas e congelamento

**Objetivo:** provar ou refutar as suposições da spec §2, §4, §6 e §9 antes de
escrever o módulo.

**Arquivos permitidos:** apenas `temp/e0-gen/*.por` e `temp/e0-gen/*.ps1`.

**Procedimento:** um driver por sonda, executado com o mesmo runner
(`portugol-console.bat`, stdin `" "`), saída capturada em texto bruto e anotada no
log (§13). Nenhum teste do repositório é alterado antes de E6.

### 5.1 Sondas

| ID | Programa mínimo | Observação esperada | Se falhar |
| --- | --- | --- | --- |
| P1 | concatenar `src/treino.por` + driver; `treino_argmax(w16,b16,9)` com estado canônico | `10` | G1 |
| P2 | concatenar os 5 fragmentos; compilar driver vazio | sem símbolo duplicado; compila | G8 |
| P3 | `inteiro saida[64]` e, como controle negativo, `inteiro um[1]` | `[64]` sem `AVISO`; `[1]` emite `AVISO` | G5 |
| P4 | função com 5 parâmetros (2 arrays + 2 inteiros + 1 array) chamada do driver | compila e executa (a M5 já usa 6 parâmetros com 3 arrays) | G3 |
| P5 | função `inteiro` com `retorne` dentro de `enquanto` | retorno correto (a M5 já usa isso em `treino_params_no_limite`) | G2 |
| P6 | linha com 64 IDs (~193 caracteres) e linha com 64 palavras (~480) | sem truncamento; hexdump confirma | G4 |
| P7 | `escreva("TEXTO=")` seguido de `"\n"`; caso terminando e caso com linha depois | `TEXTO=` preservado; `.Trim()` não remove | G7 |
| P8 | 5 `escreva` consecutivos, sem espaço | concatenação exata, sem separador | G8 |
| P9 | `treino_params_validos` com 48, -48, 49, -49 | aceita 48/-48; rejeita 49/-49 | G9 |
| P10 | 25 sementes × 16 tokens | < 5 s | G6 |
| P11 | `gerador_gerar` escreve `saida[]` e o driver lê `saida[0..N−1]` | mutação visível; `N` correto | G3 |
| P12 | semente 24, `maximo=1..64` | `N=1`, sem ler `saida[total−1]` inválido | G1 |
| P13 | mesmo driver em dois processos consecutivos | bytes idênticos | G10 |
| P14 | BOM/CRLF/EOF de `.por`, `.expected` e `test.ps1` | ASCII, LF, sem BOM; `test.ps1` com BOM e último byte `0x7D` | G10 |
| P15 | composição `tokenizador + embeddings + rede + treino + gerador` | `IDS=9 12 13 14 24`; `rede_argmax` = `treino_argmax`; geração `9 12 13 14 24` | G9 |

### 5.2 Critérios de conclusão de E0

- As 15 sondas executadas e registradas com saída bruta.
- Formato congelado: `INFO=GERADOR 25 64 4 125`, `TOKEN_PARADA=24`,
  `TOKEN_UNK=0`, `LIMITE_MAXIMO=64`.
- Se qualquer valor canônico ou formato mudar, a spec sobe para `v1.1.0` **antes**
  de E1, e todos os `.expected` são gerados depois da mudança.
- Tabela de gates preenchida com o resultado real.

### 5.3 Gates

| Gate | Gatilho | Ação pré-aprovada |
| --- | --- | --- |
| G1 | P1: `treino_argmax` não visível | inline `gerador_logit256` + `gerador_argmax` idênticos ao forward da M5; P1b confere o mapa nos 25 tokens; spec `v1.1.0`. Divergência numérica → **BLOQUEAR** |
| G2 | P5: `retorne` dentro de `enquanto` falha (improvável: já usado na M5) | laço com `logico parar` e retorno único no fim |
| G3 | P4/P11: assinatura ou mutação de array falha | função única `gerador_gerar_e_imprimir`; API reduzida; spec `v1.1.0` |
| G4 | P6: linha longa truncada | `GERADOR_MAX_TOKENS=32`; atualizar spec `v1.1.0`, `INFO`, `LIMITE_MAXIMO` e casos; regenerar tudo |
| G5 | P3: `saida[64]` emite `AVISO` | buffer `saida[128]`; nenhuma outra mudança |
| G6 | P10 > 5 s | `gen_mapa_treinado` com `maximo=8` (cadeias têm no máximo 5) |
| G7 | P7: `TEXTO=` final removido | nunca terminar caso com `TEXTO=`; o caso já imprime `PALAVRA` depois |
| G8 | P2/P8: colisão de símbolo ou separador extra | renomear com `gerador_`/`GERADOR_`; corrigir a escrita |
| G9 | P9/P15: parâmetros ou `argmax` divergem entre M4 e M5 | **BLOQUEAR**; não mascarar, não usar tolerância, não "ajustar" valor |
| G10 | P13/P14: BOM, CR, EOF ou bytes divergentes | corrigir builder/inserção; não aceitar `.por` com CR |

Resultado medido em E0 (`temp/e0-gen/results.txt`, 16 drivers: P3, P7 com controle
duplo):

| Gate | Medida | Resultado |
| --- | --- | --- |
| G1 | P1 `treino_argmax` com estado canônico: `9→10`, `19→11`, `24→11` | não disparou |
| G2 | P5 `retorne` dentro de `enquanto`: `3 -1` | não disparou |
| G3 | P4 função de 5 parâmetros: `15`; P11 `saida[]` mutada e visível: `N=8` | não disparou |
| G4 | P6: linha com 64 IDs e linha com 480 caracteres, ambas completas (`stdoutBytes=710`) | não disparou |
| G5 | P3: `saida[64]` sem `AVISO`; `um[1]` emite `AVISO` em stderr | não disparou |
| G6 | P10: 25 sementes × 16 tokens, 371 tokens em 3,75 s | não disparou |
| G7 | P7/P7b: `TEXTO=` vazio preservado, inclusive como última linha | não disparou |
| G8 | P2 compila os 5 fragmentos mais o stub; P8 = `ABCDE` | não disparou |
| G9 | P9: 48/-48 aceitos, 49/-49 rejeitados; P15 `rede_argmax` = `treino_argmax` = `12 13 14 24` | não disparou |
| G10 | P13 duas execuções: 172 bytes idênticos (SHA-256 `41F4CB52…`); P14: `.por` ASCII/LF/sem BOM, `.expected` sem CR e sem LF final, `test.ps1` com BOM e último byte `0x7D` | não disparou |

Nenhum gate disparou; o formato congela em `v1.0.0` sem emenda.

## 6. Etapas E1–E7

Cada etapa termina com um driver de scratch em `temp/e0-gen/manual/` (não
rastreado) e só avança quando a saída bate com o oráculo.

### E1 — Esqueleto, constantes, validadores, núcleo e config

- **Arquivos:** `src/gerador.por` (novo).
- **Conteúdo:** cabeçalho comentado, 7 constantes, `gerador_token_valido`,
  `gerador_limite_valido`, `gerador_proximo`, `gerador_gerar`,
  `gerador_imprimir_config`, `gerador_imprimir_validadores`.
- **Teste local:** estado canônico, semente 9, `maximo=8`; saída
  `GERADO=9 10 11 19 11 19 11 19`, `N=8`, `PASSOS=7`, `PARADA=MAXIMO`; as 12
  linhas de `gen_info`.
- **Gates resolvidos aqui:** G1, G2, G3, G4, G5.

### E2 — Projeção textual e palavra

- **Conteúdo:** `gerador_escrever_palavra`, `gerador_imprimir_texto`,
  `gerador_imprimir_palavra`.
- **Teste local:** `TEXTO` dos 25 IDs, `TEXTO=` vazio, `TEXTO=UNK UNK UNK UNK UNK
  UNK`, `SEQUENCIA_INVALIDA` (3×), 25 `PALAVRA`, `ID_INVALIDO` (2×).
- **Ponto crítico:** validar todos os IDs antes de imprimir qualquer palavra.

### E3 — Bloco completo, erros e preservação

- **Conteúdo:** `gerador_imprimir_geracao` e a ordem de validação.
- **Teste local:** `gen_erros` completo; `INTACTO=OK`; `SAIDA_INTACTA=OK`; bloco de
  5 linhas em caso válido.
- **Ponto crítico:** nenhum byte é escrito antes da validação; nenhuma posição
  `≥ N` é escrita.

### E4 — Limites, parada e UNK

- **Conteúdo:** nenhuma função nova; casos de fronteira.
- **Teste local:** `maximo=1/4/5/64` no estado treinado; `maximo=64` no canônico
  (64 tokens); semente 24; semente 0.
- **Ponto crítico:** `PARE` vence `MAXIMO` quando coincidem; `UNK` não para.

### E5 — Estado treinado, mapa e determinismo

- **Conteúdo:** drivers que executam 5 épocas da M5; `gen_mapa_treinado`,
  `gen_determinismo_a`, `gen_determinismo_b`.
- **Teste local:** cadeia `9 12 13 14 24`; as 25 linhas `MAPA`; A ≡ B.
- **Ponto crítico:** a cadeia tem de sair do estado treinado em tempo de execução,
  não de literais no driver.

### E6 — Builder, runner e 14 casos

- **Arquivos:** `scripts/build-generation-tests.ps1`; bloco aditivo em
  `scripts/test.ps1`.
- **Teste local:** 14 `.por` + 14 `.expected`; suíte **84 PASS / 0 FAIL**, exit
  `0`; autoteste **0 PASS / 1 FAIL**, exit `1`.
- **Ponto crítico:** preservar BOM e último byte `0x7D` de `test.ps1`; o bloco é
  puramente aditivo.

### E7 — Verificador e regressão final

- **Arquivos:** `scripts/verify-generation-bytes.ps1`.
- **Conteúdo:** V1–V13; re-derivação das cadeias a partir das tabelas canônicas e
  da tabela treinada da M5; segunda execução de A/B; conferência de hashes.
- **Teste local:** verificador ≥ 13/13, exit `0`; M1 21/21, M3 19/19, M4 22/22,
  M5 23/23; suíte 84/84; autoteste exit `1`.
- **Fechamento:** `git diff --stat` restrito aos arquivos autorizados; evidências
  registradas na spec e neste plano.

## 7. Matriz de testes

### 7.1 Casos e saídas esperadas

Todos os drivers declaram `inteiro w16[100]`, `inteiro b16[25]`,
`inteiro saida[64]` e preenchem `w16`/`b16` com `treino_inicializar` (canônico) ou
`treino_inicializar` + `treino_executar(...,4,5,historico)` com
`entradas={9,12,13,14}` e `alvos={12,13,14,24}` (treinado).

| # | Caso | Setup | Saída esperada (resumo) |
| ---: | --- | --- | --- |
| 1 | `gen_info` | config; 4 pares de validadores | 4 linhas de config + 8 linhas `VALIDO` |
| 2 | `gen_canonico` | canônico, semente 9, `maximo=8` | `9 10 11 19 11 19 11 19`, `N=8`, `PARADA=MAXIMO` |
| 3 | `gen_ciclo` | canônico, semente 19/`8` e semente 0/`5` | ciclo `19 11` com `CICLO=2`; auto-ciclo `0` com `CICLO=1` |
| 4 | `gen_treinado_cadeia` | 5 épocas, semente 9, `maximo=16` | `9 12 13 14 24`, `N=5`, `PASSOS=4`, `PARADA=PARE` |
| 5 | `gen_treinado_parada` | 5 épocas, semente 14, `maximo=16` | `14 24`, `N=2`, `PARADA=PARE` |
| 6 | `gen_unk` | 5 épocas, semente 0, `maximo=16` | `0 24`, `TEXTO=UNK pare` |
| 7 | `gen_inicial_pare` | 5 épocas, semente 24, `maximo=16` | `24`, `N=1`, `PASSOS=0`, `PARADA=PARE` |
| 8 | `gen_limites` | treinado 9 com `maximo=1,4,5,64`; canônico 9 com `maximo=64` | `MAXIMO` em 1 e 4; `PARE` em 5 e 64; 64 tokens no canônico |
| 9 | `gen_erros` | canônico; 8 chamadas inválidas | 8 códigos na ordem de precedência; `INTACTO=OK`; `SAIDA_INTACTA=OK` |
| 10 | `gen_texto` | `saida[0..24]=0..24` | `TEXTO` de 25 palavras; vazio; 3 `SEQUENCIA_INVALIDA`; 25 `PALAVRA`; 2 `ID_INVALIDO` |
| 11 | `gen_mapa_treinado` | 5 épocas; 25 sementes, `maximo=16` | 25 linhas `MAPA` |
| 12 | `gen_determinismo_a` | 5 épocas; estado + 6 sementes | 25 `PARAM16` + `MAXIMO16` + 6 blocos |
| 13 | `gen_determinismo_b` | idêntico a A | bytes idênticos a A |
| 14 | `gen_composicao` | 5 fragmentos; treina, materializa, gera | `IDS`, `ALVOS`, `EMB16=OK`, `ARGMAX_REDE`, `ARGMAX_TREINO`, bloco, `PARAMS_INTACTOS=OK`, `COMPOE=OK` |

Os 6 blocos de A/B são as sementes `0, 4, 9, 14, 19, 24` com `maximo=16`:

```
MAPA=0 0 24
MAPA=4 4 14 24
MAPA=9 9 12 13 14 24
MAPA=14 14 24
MAPA=19 19 24
MAPA=24 24
```

### 7.2 Blocos congelados

Saídas literais conferidas pelo oráculo em §10.1. `\n` representa LF.

**`gen_info`** (12 linhas):

```
INFO=GERADOR 25 64 4 125
TOKEN_PARADA=24
TOKEN_UNK=0
LIMITE_MAXIMO=64
VALIDO=TOKEN 0 1
VALIDO=LIMITE 1 1
VALIDO=TOKEN 24 1
VALIDO=LIMITE 64 1
VALIDO=TOKEN -1 0
VALIDO=LIMITE 0 0
VALIDO=TOKEN 25 0
VALIDO=LIMITE 65 0
```

**`gen_canonico`** (5 linhas):

```
GERADO=9 10 11 19 11 19 11 19
N=8
PASSOS=7
PARADA=MAXIMO
TEXTO=se senao enquanto e enquanto e enquanto e
```

**`gen_ciclo`** (12 linhas):

```
GERADO=19 11 19 11 19 11 19 11
N=8
PASSOS=7
PARADA=MAXIMO
TEXTO=e enquanto e enquanto e enquanto e enquanto
CICLO=2
GERADO=0 0 0 0 0
N=5
PASSOS=4
PARADA=MAXIMO
TEXTO=UNK UNK UNK UNK UNK
CICLO=1
```

**`gen_treinado_cadeia`** (5 linhas):

```
GERADO=9 12 13 14 24
N=5
PASSOS=4
PARADA=PARE
TEXTO=se faca para ate pare
```

**`gen_treinado_parada`** (5 linhas):

```
GERADO=14 24
N=2
PASSOS=1
PARADA=PARE
TEXTO=ate pare
```

**`gen_unk`** (5 linhas):

```
GERADO=0 24
N=2
PASSOS=1
PARADA=PARE
TEXTO=UNK pare
```

**`gen_inicial_pare`** (5 linhas):

```
GERADO=24
N=1
PASSOS=0
PARADA=PARE
TEXTO=pare
```

**`gen_limites`** (25 linhas; treinado, semente 9):

```
GERADO=9
N=1
PASSOS=0
PARADA=MAXIMO
TEXTO=se
GERADO=9 12 13 14
N=4
PASSOS=3
PARADA=MAXIMO
TEXTO=se faca para ate
GERADO=9 12 13 14 24
N=5
PASSOS=4
PARADA=PARE
TEXTO=se faca para ate pare
GERADO=9 12 13 14 24
N=5
PASSOS=4
PARADA=PARE
TEXTO=se faca para ate pare
```

O quinto bloco (canônico, `maximo=64`) está no Apêndice C.

**`gen_erros`** (10 linhas):

```
ERRO=TOKEN_INVALIDO
ERRO=TOKEN_INVALIDO
ERRO=LIMITE_INVALIDO
ERRO=LIMITE_INVALIDO
ERRO=TOKEN_INVALIDO
ERRO=PARAMETROS_INVALIDOS
ERRO=PARAMETROS_INVALIDOS
ERRO=TOKEN_INVALIDO
INTACTO=OK
SAIDA_INTACTA=OK
```

**`gen_texto`** (33 linhas):

```
TEXTO=UNK programa funcao inicio inteiro real logico cadeia vazio se senao enquanto faca para ate passo retorne escreva leia e ou nao verdadeiro falso pare
TEXTO=
TEXTO=UNK UNK UNK UNK UNK UNK
ERRO=SEQUENCIA_INVALIDA
ERRO=SEQUENCIA_INVALIDA
ERRO=SEQUENCIA_INVALIDA
PALAVRA=0 UNK
PALAVRA=1 programa
PALAVRA=2 funcao
PALAVRA=3 inicio
PALAVRA=4 inteiro
PALAVRA=5 real
PALAVRA=6 logico
PALAVRA=7 cadeia
PALAVRA=8 vazio
PALAVRA=9 se
PALAVRA=10 senao
PALAVRA=11 enquanto
PALAVRA=12 faca
PALAVRA=13 para
PALAVRA=14 ate
PALAVRA=15 passo
PALAVRA=16 retorne
PALAVRA=17 escreva
PALAVRA=18 leia
PALAVRA=19 e
PALAVRA=20 ou
PALAVRA=21 nao
PALAVRA=22 verdadeiro
PALAVRA=23 falso
PALAVRA=24 pare
ERRO=ID_INVALIDO
ERRO=ID_INVALIDO
```

**`gen_mapa_treinado`** (25 linhas):

```
MAPA=0 0 24
MAPA=1 1 24
MAPA=2 2 13 14 24
MAPA=3 3 13 14 24
MAPA=4 4 14 24
MAPA=5 5 24
MAPA=6 6 24
MAPA=7 7 13 14 24
MAPA=8 8 16 13 14 24
MAPA=9 9 12 13 14 24
MAPA=10 10 24
MAPA=11 11 13 14 24
MAPA=12 12 13 14 24
MAPA=13 13 14 24
MAPA=14 14 24
MAPA=15 15 24
MAPA=16 16 13 14 24
MAPA=17 17 16 13 14 24
MAPA=18 18 12 13 14 24
MAPA=19 19 24
MAPA=20 20 13 14 24
MAPA=21 21 13 14 24
MAPA=22 22 14 24
MAPA=23 23 24
MAPA=24 24
```

**`gen_composicao`** (12 linhas):

```
IDS=9 12 13 14 24
ALVOS=12 13 14 24
EMB16=OK
ARGMAX_REDE=12 13 14 24
ARGMAX_TREINO=12 13 14 24
GERADO=9 12 13 14 24
N=5
PASSOS=4
PARADA=PARE
TEXTO=se faca para ate pare
PARAMS_INTACTOS=OK
COMPOE=OK
```

**`gen_determinismo_a` / `gen_determinismo_b`**: bytes idênticos. Estrutura: 25
linhas `PARAM16` da tabela final da M5 (`docs/training-spec.md` §8.3), depois
`MAXIMO16=11 6`, depois os 6 blocos de §7.1. O builder gera o `.expected`, não o
driver.

### 7.3 Contagem

| Suíte | Origem dos `.expected` | Antes | Depois |
| --- | --- | ---: | ---: |
| Base do runner | 5 casos literais | 5 | 5 |
| M1 tokenizador | `temp/tests` | 20 | 20 |
| M3 embeddings | `temp/embedding-tests` | 19 | 19 |
| M4 rede | `temp/network-tests` | 14 | 14 |
| M5 treino | `temp/training-tests` | 12 | 12 |
| **M6 geração** | `temp/generation-tests` | 0 | **14** |
| **Total** | | **70** | **84** |

### 7.4 Regras dos arquivos esperados

- `.expected` ASCII puro, sem `\n` final, sem espaços nas pontas.
- `.por` ASCII puro, UTF-8 sem BOM, LF.
- Nenhum driver lê teclado, usa `aleatorio`, `tempo`, `leia` ou biblioteca.
- Nenhum caso termina com `TEXTO=`.
- `gen_determinismo_a.expected` ≡ `gen_determinismo_b.expected`.
- O diretório `temp/generation-tests` contém exatamente 14 `.por` e 14 `.expected`.

## 8. Integração em `scripts/test.ps1`

Inserir um quinto bloco **dentro** de `if (-not $SelfTest)`, imediatamente após o
`foreach` do bloco de treinamento (que termina na linha 291 em `HEAD`) e antes do
`}` que fecha o `if` (linha 292). O laço de execução começa depois, na linha 306,
e não deve ser tocado:

```powershell
    # Gerar e anexar os casos de geracao (M6). Diretorio proprio para nao
    # interferir nas verificacoes de bytes das missoes anteriores.
    $generationBuilder = Join-Path $PSScriptRoot "build-generation-tests.ps1"
    try {
        & $generationBuilder
    } catch {
        Write-Host "ERROR: generation test builder failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $generationRoot = "temp/generation-tests"
    $generationGenerated = @(Get-ChildItem -Path $generationRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($generationGenerated.Count -eq 0) {
        Write-Host "ERROR: no generation test cases found in $generationRoot" -ForegroundColor Red
        exit 1
    }

    foreach ($expectedFile in $generationGenerated) {
        $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
        $testCases += @{
            Name = $caseName
            File = "$generationRoot/$caseName.por"
            ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
        }
    }
```

Regras:

- Não alterar nenhuma linha existente; apenas inserir as 24 linhas.
- Preservar BOM UTF-8 e o último byte `0x7D` (sem `\n` final).
- `git diff --numstat -- scripts/test.ps1` deve mostrar `24 0`.
- O autoteste não executa o bloco (já está dentro de `if (-not $SelfTest)`).

## 9. Builder e verificador

### 9.1 `scripts/build-generation-tests.ps1`

Responsabilidades:

1. Gerar os 14 `.por` em `temp/generation-tests/` por concatenação ASCII+LF dos
   fragmentos necessários (`src/treino.por` sempre; `src/tokenizador.por`,
   `src/embeddings.por` e `src/rede.por` só em `gen_composicao`) mais
   `src/gerador.por` e o driver.
2. Gerar os 14 `.expected` a partir do **oráculo inteiro** (não da execução do
   `.por`).
3. Embutir as tabelas canônicas: inicialização explícita da M5, tabela final
   treinada (25×5 literais de `docs/training-spec.md` §8.3) e o mapa de palavras
   da M1.
4. Recusar-se a gerar se um `.expected` tiver `\n` final, CR, BOM, espaço nas
   pontas ou byte > `0x7E`.
5. Recusar-se a gerar se um `.por` tiver CR, BOM ou byte > `0x7E`.
6. Não tocar em `temp/tests`, `temp/embedding-tests`, `temp/network-tests` ou
   `temp/training-tests`.

Oráculo do builder (§10.1 do verificador), em pseudocódigo:

```
emb16(id, d) = ((id*7 + d*3) % 32) - 16
z256(W, B, t, y) = sum_{d=0..3} W[y][d]*emb16(t,d) + 16*B[y]
argmax(W, B, t):
    melhor = 0; valor = z256(W, B, t, 0)
    para y = 1..24:
        v = z256(W, B, t, y)
        se (v > valor): melhor = y; valor = v
    retornar melhor
gerar(W, B, s, maximo):
    saida[0] = s; total = 1
    enquanto (total < maximo):
        se (saida[total-1] == 24): retornar total
        saida[total] = argmax(W, B, saida[total-1]); total = total + 1
    retornar total
```

O oráculo do builder usa aritmética inteira de 64 bits do PowerShell e não chama
nenhuma função do `.por`.

### 9.2 `scripts/verify-generation-bytes.ps1`

| ID | Verificação |
| --- | --- |
| V1 | `src/gerador.por` ASCII, sem BOM, LF, sem `programa`/`inicio`/`inclua`, sem `aleatorio`/`tempo`/`leia`, sem `softmax`/`exp(`/`temperatura`/`top_`, sem aritmética `real`, com apenas as dependências `treino_argmax` e `treino_params_validos` |
| V2 | conjunto de casos exatamente os 14 `gen_*` esperados |
| V3 | bytes crus: `\f` inicial, carga ASCII com LF, epílogo exato |
| V4 | `INFO`, `TOKEN_PARADA`, `TOKEN_UNK`, `LIMITE_MAXIMO` e as 8 linhas `VALIDO` |
| V5 | `gen_mapa_treinado`: 25 cadeias re-derivadas da tabela treinada da M5 |
| V6 | `N`, `PASSOS`, `PARADA` coerentes com `GERADO` e com o `maximo` do caso |
| V7 | `gen_canonico` e `gen_ciclo`: cadeias canônicas e períodos 2 e 1 |
| V8 | `gen_unk`, `gen_inicial_pare`, `gen_treinado_parada`, `gen_limites`, incluindo `PARE` sobre `MAXIMO` |
| V9 | `gen_erros`: 8 códigos na ordem, `INTACTO=OK`, `SAIDA_INTACTA=OK` |
| V10 | A/B idênticos nos `.expected` e em segunda execução de ambos |
| V11 | `gen_composicao`: `IDS`, `EMB16=OK`, `ARGMAX_REDE` = `ARGMAX_TREINO` = `12 13 14 24`, `GERADO=9 12 13 14 24` |
| V12 | nenhum `.expected` com `\n` final, CR, BOM ou espaço nas pontas |
| V13 | mapa completo dos 25 inícios: 25 linhas, `saida[0]` = semente, último ID 24, comprimento ≤ 5 |

O verificador **não lê `.expected` para decidir valores**. Ele re-deriva as
cadeias do oráculo e usa os literais congelados; `.expected` é lido apenas para
conferências de bytes e igualdade (V3, V10, V12).

### 9.3 Independência

| # | Implementação | Papel |
| ---: | --- | --- |
| 1 | Python inteiro (planejamento) | primeira derivação dos mapas |
| 2 | Python `double` em 1/16 (planejamento) | confere `argmax` e diferença máxima `0` |
| 3 | PowerShell inteiro (planejamento) | terceira derivação, tabelas explícitas |
| 4 | oráculo do builder | quarta derivação, gera `.expected` |
| 5 | `src/gerador.por` | quinta implementação, executada pelo interpretador |
| 6 | verificador | sexta derivação, independente do builder |

Nenhuma delas lê a saída do `.por` para produzir o valor esperado.

## 10. Matriz de aceitação

| AC | Comando | Resultado exigido |
| ---: | --- | --- |
| AC1 | `git status --short` | somente `docs/generation-*.md`, `src/gerador.por`, `scripts/build-generation-tests.ps1`, `scripts/verify-generation-bytes.ps1`, `M scripts/test.ps1` |
| AC2 | `.\scripts\test.ps1` | `Passed: 84`, `Failed: 0`, exit `0` |
| AC3 | 4 verificadores anteriores | 21/21, 19/19, 22/22, 23/23, exit `0` |
| AC4 | `.\scripts\test.ps1 -SelfTest` | `Passed: 0`, `Failed: 1`, exit `1` |
| AC5 | `.\scripts\verify-generation-bytes.ps1` | ≥ 13/13, exit `0` |
| AC6 | inspeção do builder e do verificador | nenhum valor esperado derivado do `.por` |
| AC7 | `gen_treinado_cadeia` | `GERADO=9 12 13 14 24`, `PARADA=PARE` |
| AC8 | `gen_canonico` | `GERADO=9 10 11 19 11 19 11 19` |
| AC9 | `gen_ciclo` | `19 11 19 11 19 11 19 11`, `CICLO=2`, `PARADA=MAXIMO` |
| AC10 | `gen_treinado_parada`, `gen_inicial_pare` | `14 24`; `24` com `PASSOS=0` |
| AC11 | `gen_unk` | `GERADO=0 24`, `TEXTO=UNK pare` |
| AC12 | `gen_limites` | `maximo=1` → só a semente; `4` → `MAXIMO`; `5` e `64` → `PARE`; canônico `64` → 64 tokens |
| AC13 | `gen_erros`, `gen_texto` | `TOKEN_INVALIDO`, `LIMITE_INVALIDO`, `PARAMETROS_INVALIDOS`, `SEQUENCIA_INVALIDA`, `ID_INVALIDO` |
| AC14 | `gen_erros`, `gen_composicao` | `INTACTO=OK`, `SAIDA_INTACTA=OK`, `PARAMS_INTACTOS=OK` |
| AC15 | `gen_determinismo_a/b` | bytes idênticos nas duas execuções |
| AC16 | `gen_composicao` | `ARGMAX_REDE` = `ARGMAX_TREINO` = `12 13 14 24` |
| AC17 | V1 | sem `aleatorio`, `tempo`, `leia`, `softmax`, `exp(`, `temperatura`, `top_` |
| AC18 | `git hash-object` dos 12 arquivos da §1 | hashes iguais aos de `HEAD` |
| AC19 | `git diff --numstat -- scripts/test.ps1`; bytes do arquivo | `24 0`; BOM UTF-8 e último byte `0x7D` |
| AC20 | leitura da spec e do plano | evidências medidas, sem placeholders |

Resultado em E7: **AC1–AC20 satisfeitos**. As evidências por comando estão em §13
e o resumo em §10.1.

### 10.1 Resultado medido

Medições de E6/E7, executadas a partir da raiz do repositório com
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`:

| Verificação | Resultado medido | Exit |
| --- | --- | ---: |
| `.\scripts\build-generation-tests.ps1` | 14 `.por` + 14 `.expected` em `temp/generation-tests/` | `0` |
| `.\scripts\test.ps1` | `Passed: 84`, `Failed: 0`, `Total: 84`; 14 `gen_*` PASS | `0` |
| `.\scripts\test.ps1 -SelfTest` | `Passed: 0`, `Failed: 1` (intencional) | `1` |
| `.\scripts\verify-bytes.ps1` | 21/21, 0 falhas | `0` |
| `.\scripts\verify-embedding-bytes.ps1` | 19/19, 0 falhas | `0` |
| `.\scripts\verify-network-bytes.ps1` | 22/22, 0 falhas | `0` |
| `.\scripts\verify-training-bytes.ps1` | 23/23, 0 falhas | `0` |
| `.\scripts\verify-generation-bytes.ps1` | `Checks: 13`, `Failures: 0`; 14 casos executados | `0` |
| 12 arquivos protegidos | 12/12 hashes idênticos ao `HEAD` | — |
| `git diff --numstat -- scripts/test.ps1` | `24 0` | — |
| bytes de `scripts/test.ps1` | BOM `EF BB BF`; último byte `0x7D` | — |
| `git status --short` | 1 `M` + 5 `??`, somente os arquivos autorizados | — |

Notas:

- `gen_determinismo_a.expected` e `gen_determinismo_b.expected` têm 921 bytes
  idênticos; a segunda execução dos dois `.por` também é byte-idêntica.
- O verificador lê `.expected` apenas para as conferências de bytes/igualdade
  (V3, V10, V12); os valores são re-derivados das tabelas canônicas da M5.
- As 25 cadeias treinadas, os 25 mapas canônicos/treinados e `CICLO=2` foram
  reproduzidos independentemente na conferência adicional da auditoria de E7;
  `MAX_Z256=349` e a diferença `double` vs `Z256/256` foi `0`, como na spec §3.4.

## 11. Riscos e mitigações

| ID | Risco | Mitigação |
| --- | --- | --- |
| R1 | `treino_argmax` não visível na concatenação | G1: inline idêntico, com prova de igualdade nos 25 tokens |
| R2 | `retorne` dentro de `enquanto` não suportado | G2: laço com flag `parar` |
| R3 | array não muta entre funções | G3: função única; spec `v1.1.0` |
| R4 | linha de 64 tokens/64 palavras truncada | G4: limite 32; regenerar tudo |
| R5 | `AVISO` de array em stderr quebra o caso | G5: buffer `[128]`; `[1]` só como controle negativo em E0 |
| R6 | `TEXTO=` final removido pelo `.Trim()` | nunca terminar caso com `TEXTO=`; `PALAVRA` depois |
| R7 | custo do `gen_mapa_treinado` | G6: `maximo=8`; cadeias têm ≤ 5 |
| R8 | corromper BOM/EOF de `test.ps1` | inserção aditiva, `git diff --numstat`, checagem de bytes |
| R9 | `.expected` com `\n` final | builder escreve sem `\n`; V12 |
| R10 | oráculo divergir do `.por` | V5/V6 re-derivam das tabelas; divergência `argmax` para o processo (G9) |
| R11 | "ajustar" valores para passar | valores congelados na spec; mudança exige `v1.1.0` + regeneração + aprovação |
| R12 | confundir geração com generalização | AC7 declara memorização; relatório repete as limitações da spec §13 |

## 12. Execução autônoma

A execução descrita nesta seção só começa **após aprovação explícita** deste plano.
Uma vez aprovada, E0–E7 correm sem aprovação intermediária, respeitando os gates
pré-aprovados.

### 12.1 Laço

1. Executar E0 e preencher os gates.
2. Implementar E1–E7 em ordem, com driver de scratch antes de cada caso oficial.
3. Rodar a suíte completa e os cinco verificadores ao fim de E6 e E7.
4. Registrar comando, saída e exit code no log (§13).
5. Só declarar **PRONTO** com AC1–AC20 verificados.

### 12.2 Regras

- **Sem aprovação intermediária:** G1–G10 são pré-aprovados; ao disparar um gate,
  aplicar a alternativa, registrar e continuar.
- **Orçamento por falha:** até 3 tentativas de correção; depois, se não houver
  fallback, parar como PARCIAL.
- **Escalonamento:** no máximo 2 gates de formato/layout na mesma execução; um
  terceiro exige parar e reportar.
- **Nunca** alterar valores canônicos, o oráculo ou os critérios para "fazer
  passar".
- **Nunca** tocar nos arquivos proibidos (§4.2).
- **Nunca** executar `git add`, `git commit`, `git push`, `git tag` ou
  `git remote`.
- **Sempre** registrar o comando e a saída bruta relevante antes de concluir.

### 12.3 Condições de parada imediata

1. `HEAD` diferente de `0dd7ecb`, branch diferente de `main` ou alteração fora dos
   arquivos autorizados (§4.1).
2. Gate G9 disparado (`rede_argmax` ≠ `treino_argmax`).
3. Necessidade de alterar arquivo proibido.
4. Falha de AC sem fallback após 3 tentativas.
5. Interpretador ausente ou instável.
6. Qualquer efeito colateral em `src/tokenizador.por`, `src/embeddings.por`,
   `src/rede.por` ou `src/treino.por`.

### 12.4 Definição de pronto

**PRONTO** exige, simultaneamente:

- suíte 84/84, exit `0`, com os 70 casos anteriores inalterados;
- M1 21/21, M3 19/19, M4 22/22, M5 23/23, exit `0`;
- autoteste 0 PASS / 1 FAIL, exit `1`;
- `verify-generation-bytes` ≥ 13/13, exit `0`;
- 14 `.por` e 14 `.expected` presentes, A ≡ B;
- hashes de `HEAD` dos 12 arquivos protegidos inalterados;
- `git diff` restrito aos arquivos autorizados;
- nenhum commit/push;
- log de evidências preenchido.

Caso contrário: **PARCIAL** (com o que falta) ou **BLOQUEADO** (com o gate).

## 13. Registro de evidências

Medições registradas durante E0–E7. Todos os comandos foram executados a partir
da raiz do repositório; `Exit` é o código de saída real do processo.

| Etapa | Comando | Saída resumida | Exit | Status |
| --- | --- | --- | ---: | --- |
| E0 P1 | driver `p1.por` | `P1_9=10`, `P1_19=11`, `P1_24=11` | 0 | PASS |
| E0 P2 | driver `p2.por` | `P2=OK` (5 fragmentos + stub) | 0 | PASS |
| E0 P3 | drivers `p3a.por`, `p3b.por` | `[64]` sem AVISO; `[1]` com `AVISO` em stderr | 0 | PASS |
| E0 P4 | driver `p4.por` | `P4=15` | 0 | PASS |
| E0 P5 | driver `p5.por` | `P5=3 -1` | 0 | PASS |
| E0 P6 | driver `p6.por` | 64 IDs e 480 caracteres sem truncamento | 0 | PASS |
| E0 P7 | drivers `p7.por`, `p7b.por` | `TEXTO=` vazio preservado | 0 | PASS |
| E0 P8 | driver `p8.por` | `ABCDE` | 0 | PASS |
| E0 P9 | driver `p9.por` | 48/-48 `verdadeiro`; 49/-49 `falso` | 0 | PASS |
| E0 P10 | driver `p10.por` | `P10_SOMA=371` em 3,75 s | 0 | PASS |
| E0 P11 | driver `p11.por` | `P11_N=8`, `P11=9 10 11 19 11 19 11 19` | 0 | PASS |
| E0 P12 | driver `p12.por` | `P12_1=1 24`, `P12_64=1 24`, `P12_9=8` | 0 | PASS |
| E0 P13 | duas execuções de `p13.por` | 172 bytes idênticos, SHA-256 `41F4CB52…` | 0 | PASS |
| E0 P14 | script de bytes | ASCII/LF/sem BOM; `test.ps1` BOM + `0x7D` | 0 | PASS |
| E0 P15 | driver `p15.por` | `P15_GERADO=9 12 13 14 24`; REDE = TREINO; 25 mapas corretos | 0 | PASS |
| E6 | `.\scripts\build-generation-tests.ps1` | `Generated 14 generation cases in temp/generation-tests`; 14 `.por` + 14 `.expected` | 0 | PASS |
| E6 | `.\scripts\test.ps1` | `Passed: 84`, `Failed: 0`, `Total: 84`; 14 `gen_*` PASS; 215,5 s | 0 | PASS |
| E6 | `.\scripts\test.ps1 -SelfTest` | `Passed: 0`, `Failed: 1` (`THIS_WILL_NOT_MATCH` vs `UNEXPECTED_OUTPUT`) | 1 | PASS (intencional) |
| E7 | `.\scripts\verify-generation-bytes.ps1` | `Checks: 13`, `Failures: 0`; 14 casos executados | 0 | PASS |
| E7 | `.\scripts\verify-bytes.ps1` | `Total: 21 verificacoes, 0 falha(s)` | 0 | PASS |
| E7 | `.\scripts\verify-embedding-bytes.ps1` | `Total: 19 verificacoes, 0 falha(s)` | 0 | PASS |
| E7 | `.\scripts\verify-network-bytes.ps1` | `Total: 22 verificacoes, 0 falha(s)` | 0 | PASS |
| E7 | `.\scripts\verify-training-bytes.ps1` | `Total: 23 verificacoes, 0 falha(s)` | 0 | PASS |
| E7 | `git hash-object` dos 12 arquivos protegidos | 12/12 iguais ao `HEAD` | 0 | PASS |
| E7 | `git status --short`; `git diff --numstat -- scripts/test.ps1` | 1 `M` + 5 `??` autorizados; `24 0` | 0 | PASS |
| E7 | bytes de `scripts/test.ps1` | BOM UTF-8; último byte `0x7D`; sem CR | — | PASS |
| E7 | `git diff --check` | sem saída de erro | 0 | PASS |

## 14. Relatório final

1. **Estado:** **PRONTO**. AC1–AC20 verificados por comando: suíte 84/84, M6
   13/13, M1–M5 sem regressão e autoteste com falha intencional. Nenhum gate
   G1–G10 disparou.
2. **Arquivos:** criados `src/gerador.por`, `scripts/build-generation-tests.ps1`,
   `scripts/verify-generation-bytes.ps1`, `docs/generation-spec.md` e
   `docs/generation-plan.md`; alterado `scripts/test.ps1` (24 linhas aditivas).
   `git status --short` mostra exatamente esses seis itens, sem arquivos fora do
   escopo.
3. **Suíte:** **84 PASS / 0 FAIL**, exit `0`. Os 70 casos anteriores foram
   preservados: 5 literais + 20 M1 + 19 M3 + 14 M4 + 12 M5; os 14 `gen_*`
   passaram.
4. **Verificadores:** M1 **21/21**, M3 **19/19**, M4 **22/22**, M5 **23/23**,
   M6 **13/13**; todos com exit `0`.
5. **Casos de geração:** 14/14. Blocos de AC7–AC12:

   ```
   # AC7
   GERADO=9 12 13 14 24
   N=5
   PASSOS=4
   PARADA=PARE
   TEXTO=se faca para ate pare

   # AC8
   GERADO=9 10 11 19 11 19 11 19
   N=8
   PASSOS=7
   PARADA=MAXIMO
   TEXTO=se senao enquanto e enquanto e enquanto e

   # AC9
   GERADO=19 11 19 11 19 11 19 11
   N=8
   PASSOS=7
   PARADA=MAXIMO
   TEXTO=e enquanto e enquanto e enquanto e enquanto
   CICLO=2

   # AC10
   GERADO=14 24
   N=2
   PASSOS=1
   PARADA=PARE
   TEXTO=ate pare

   GERADO=24
   N=1
   PASSOS=0
   PARADA=PARE
   TEXTO=pare

   # AC11
   GERADO=0 24
   N=2
   PASSOS=1
   PARADA=PARE
   TEXTO=UNK pare

   # AC12 (treinado, semente 9; maximo 1, 4, 5, 64)
   GERADO=9
   N=1
   PASSOS=0
   PARADA=MAXIMO
   TEXTO=se

   GERADO=9 12 13 14
   N=4
   PASSOS=3
   PARADA=MAXIMO
   TEXTO=se faca para ate

   GERADO=9 12 13 14 24
   N=5
   PASSOS=4
   PARADA=PARE
   TEXTO=se faca para ate pare

   GERADO=9 12 13 14 24
   N=5
   PASSOS=4
   PARADA=PARE
   TEXTO=se faca para ate pare
   ```

   O bloco canônico com `maximo=64` (64 tokens) está no Apêndice C e foi
   conferido em `gen_limites`.
6. **Gates:** nenhum dos G1–G10 disparou. O formato congelou em v1.0.0 sem
   emenda; não houve fallback.
7. **Reprodutibilidade:** `gen_determinismo_a/b.expected` são byte-idênticos
   (921 bytes) e as duas execuções de cada `.por` são idênticas. Os 12 hashes de
   `HEAD` da §1 estão inalterados. `git diff --numstat -- scripts/test.ps1` =
   `24 0`; BOM UTF-8 e último byte `0x7D` preservados.
8. **Limitações:** memória de 4 transições (`9→12→13→14→24`), contexto de 1
   token, vocabulário fechado `0..24`, `UNK` sem semântica, texto não
   inversível, parada apenas em `pare`/limite e nenhuma generalização
   demonstrada. A cadeia treinada prova uso dos parâmetros da M5, não
   compreensão de programas.
9. **Pendências:** `git add`, `commit` e `push` não foram executados, por
   decisão da missão. Não há pendência técnica ou documental.

## Apêndice A — Ordem de implementação recomendada

1. E0: P1–P15, gates, congelamento da spec.
2. E1: constantes, validadores, `gerador_proximo`, `gerador_gerar`, config.
3. E2: projeção textual e `PALAVRA`.
4. E3: bloco completo e erros.
5. E4: limites, parada, UNK.
6. E5: estado treinado, mapa, determinismo.
7. E6: builder, runner, 84/84.
8. E7: verificador, regressão, hashes, evidências.

## Apêndice B — Checklist antes de E6

- [ ] `src/gerador.por` sem `programa`, `inicio`, `inclua`, `real`, `aleatorio`,
      `tempo`, `leia`, `softmax`, `exp(`, `temperatura`, `top_`.
- [ ] `GERADOR_MAX_TOKENS = 64` e `saida[64]` sem `AVISO`.
- [ ] `gerador_gerar` não escreve em `w16`/`b16`.
- [ ] Erro de validação não escreve em `saida`.
- [ ] Semente 24 gera `N=1` e não lê índice inválido.
- [ ] `UNK` não para a geração.
- [ ] `TEXTO=` vazio não é a última linha de nenhum caso.
- [ ] A/B têm `.expected` idêntico.
- [ ] `gen_composicao` compara M4 e M5 antes de gerar.
- [ ] Nenhum arquivo de M1–M5 foi tocado.

## Apêndice C — Bloco congelado do limite de 64 tokens

Estado canônico, semente 9, `maximo=64` (5 linhas):

```
GERADO=9 10 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19
N=64
PASSOS=63
PARADA=MAXIMO
TEXTO=se senao enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e
```

O bloco prova: 64 é aceito, o laço para no limite, `PARE` não aparece e o texto
tem 64 palavras (2 + 31 pares `enquanto e`).

## Apêndice D — Baseline de hashes

Os 12 hashes de `HEAD` da §1 são a referência de AC18. O hash de `test.ps1` é
capturado em E0 e reconferido em E7. Qualquer diferença em um arquivo protegido é
condição de parada (§12.3).
