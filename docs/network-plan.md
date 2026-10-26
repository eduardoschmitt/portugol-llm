# Plano de execução — Camada de saída linear (M4)

- **Status:** executada e verificada em 2026-10-26. E0–E7 concluídas; veredito **PRONTO**.
- **Especificação:** `docs/network-spec.md` v1.0.0 (congelada em E0).
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3 (`docs/embeddings-spec.md` v0.1.1).
- **Execução:** prevista para ocorrer de forma autônoma, etapa por etapa, sem aprovação
  intermediária (§12).
- **Fora de escopo:** treinamento, backpropagation, softmax, atenção, Transformer, geração
  autoregressiva, commit e push.

## 1. Estado de partida

Verificado nesta missão, antes de escrever este plano:

| Item | Estado |
| --- | --- |
| `HEAD` | `370c296810c96e215fb17f3c03cbe0d8dd8d782b` (`feat(embeddings): implement deterministic token embeddings`) |
| Branch | `main`, 0 ahead / 0 behind de `origin/main` |
| Árvore de trabalho | limpa; apenas `docs/network-spec.md` e `docs/network-plan.md` não rastreados |
| Suíte | `scripts/test.ps1` = **44 PASS / 0 FAIL**, exit `0` (executado agora) |
| M1 bytes | `scripts/verify-bytes.ps1` = **21/21**, exit `0` (executado agora) |
| M3 bytes | `scripts/verify-embedding-bytes.ps1` = **19/19**, exit `0` (executado agora) |
| Autoteste | `scripts/test.ps1 -SelfTest` = **0 PASS / 1 FAIL intencional**, exit `1` (executado agora) |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |
| Custo por caso | ~1,3 s; suíte de 58 casos ≈ 75 s |

Hashes de `HEAD` dos arquivos que **não podem** mudar (baseline de AC19):

```
src/tokenizador.por                    6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f
src/embeddings.por                     6f06aa820d163d3c1636383803b86105bf54cd85
scripts/build-tests.ps1                1cfb01202586a83c4d7ec08ff738a8e90fb19044
scripts/verify-bytes.ps1               851afbbad494778f019bf2ce70e82b0b575ab443
scripts/build-embedding-tests.ps1      94d1a3819b76b4d614f4422bf00b0cd2c008daaf
scripts/verify-embedding-bytes.ps1     4f3aa68e499a9dc3289d22ebae5b8d1c18086651
```

O hash de `scripts/test.ps1` em `HEAD` é capturado em E0 e reconferido em E7; ele muda por
desenho (bloco aditivo), mas o restante do arquivo deve permanecer idêntico.

Comandos de referência:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-embedding-bytes.ps1
```

## 2. Restrições do runner

Comprovadas por leitura de `scripts/test.ps1` e pelas missões anteriores:

1. **Exit code do interpretador é sempre 0.** Falhas de execução precisam ser detectadas
   por texto; por isso os testes da rede usam apenas saídas normais.
2. **stdout começa com form feed (`0x0C`).** `Normalize-Output` remove um `\f` inicial.
3. **Epílogo de sucesso** (bytes, após a carga útil):
   `"\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n"`.
   O corpo do programa usa LF; o epílogo usa CRLF.
4. **`Normalize-Output` remove o epílogo, um `\n` final e aplica `.Trim()`.** A comparação
   com `.expected` é `-ceq` (case-sensitive). `.expected` não deve ter `\n` final nem
   espaços nas pontas.
5. **Entrada padrão**: o runner envia uma linha (`" "`) e fecha; nenhum teste pode ler
   teclado.
6. **Casos gerados** são descobertos por `Get-ChildItem -Filter *.expected` em um
   diretório próprio, ordenados por nome, e anexados a `$testCases`.
7. **Autoteste** substitui `$testCases` por um único caso que deve falhar; o bloco de
   geração fica dentro de `if (-not $SelfTest)`.
8. **`scripts/test.ps1` tem BOM UTF-8 e não termina em LF** (último byte `0x7D`). A edição
   aditiva precisa preservar ambos.
9. **Nomes de caso** não podem colidir entre M0, M1, M3 e M4; o prefixo `net_` garante isso.
10. **Diretórios de teste** são independentes (`temp/tests`, `temp/embedding-tests`,
    `temp/network-tests`) para que `verify-bytes.ps1` continue varrendo apenas `temp/tests`.

## 3. Decisões de execução

Herdadas da spec (§16) e fixadas para a implementação:

| ID | Decisão |
| --- | --- |
| D1 | camada afim única 4→25; sem ativação, sem softmax, sem estado oculto |
| D2 | `real pesos[100]` + `real vieses[25]`; fallback G3 para `real estado[225]` (W `0..99`, b `100..124`, emb `125..224`) |
| D3 | init `W = p/16.0`, `b = r/16.0` com as fórmulas da spec §4.1 |
| D4 | acúmulo `soma = 0.0`, quatro produtos, depois `+ vieses[y]` |
| D5 | argmax: `melhor = 0`, inicializa com `logit(id,0)`, varre `1..24` com `>` |
| D6 | erros `ID_INVALIDO`, `SAIDA_INVALIDA`, `DIMENSAO_INVALIDA`; precedência id→y→d |
| D7 | `rede_logit`/`rede_argmax` puros; validação só nos `rede_imprimir_*` |
| D8 | setters gravam qualquer `real`, sem validação nem clamp |
| D9 | prefixos `rede_`/`REDE_` para evitar colisão com `emb_`/`EMB_` |
| D10 | Formato A provisório; N-B (parâmetros inteiros, 1–4 casas) e N-C (linha longa) pré-aprovados |
| D11 | oráculo em aritmética inteira, independente de `.expected` |
| D12 | determinismo por 25 vetores completos em dois processos independentes |
| D13 | nenhum commit/push; nenhuma alteração em módulos anteriores |
| D14 | `REDE_ENTRADAS == EMB_DIM`; acoplamento coberto por `net_composicao` |

## 4. Arquivos

### 4.1 Autorizados

| Arquivo | Ação | Conteúdo |
| --- | --- | --- |
| `src/rede.por` | criar | fragmento ASCII: constantes, validadores, init, logit, argmax, impressoras, setters |
| `scripts/build-network-tests.ps1` | criar | gera 14 `.por` + 14 `.expected` em `temp/network-tests/` |
| `scripts/verify-network-bytes.ps1` | criar | verificação de bytes + oráculo inteiro independente |
| `scripts/test.ps1` | alterar (aditivo) | terceiro bloco de geração/anexo dentro de `if (-not $SelfTest)` |
| `docs/network-spec.md` | criar | especificação (esta missão) |
| `docs/network-plan.md` | criar | este plano (esta missão) |

### 4.2 Proibidos

`src/tokenizador.por`, `src/embeddings.por`, `tests/*`, `scripts/build-tests.ps1`,
`scripts/verify-bytes.ps1`, `scripts/build-embedding-tests.ps1`,
`scripts/verify-embedding-bytes.ps1`, `README.md`, `AGENTS.md`, `.gitignore`, qualquer
arquivo em `.git/`.

### 4.3 Artefatos descartáveis (ignorados)

`temp/e0-net/` (sondas) e `temp/network-tests/` (casos gerados). Nada deles é rastreado;
`git status --short` deve continuar mostrando apenas os arquivos autorizados.

## 5. E0 — Sondas e congelamento

**Objetivo:** provar ou refutar as suposições da spec §14 antes de escrever o módulo.

**Arquivos permitidos:** apenas `temp/e0-net/*.por` e `temp/e0-net/*.ps1`.

**Procedimento:** um driver por sonda, executado com o mesmo runner (`portugol-console.bat`,
stdin `" "`). Cada saída é capturada em texto bruto e anotada no log (§13).

### 5.1 Sondas

| ID | Programa mínimo | Observação esperada | Se falhar |
| --- | --- | --- | --- |
| P1 | `funcao f(real a[], real b[])` que soma e muta `a[0]`; chamar com dois vetores | compila; mutação visível no chamador | G3 |
| P2 | `const inteiro N = 25`; `(17 % 25) - 12`; `(0 % 9) - 4` | `5` e `-4`; nenhum aviso de `const` | G7 |
| P3 | imprimir `0.00390625`, `0.8515625`, `1.7265625`, `0.0 - 1.2421875`, `11.0`, `0.0` | `-1.2421875` e os demais idênticos; sem notação científica | G1 |
| P4 | `real s = 0.0`; `s = s + (0.0 - 0.75)*0.0`; `s = s + 0.0`; imprimir | `0.0`, não `-0.0` | G1 |
| P5 | imprimir 25 `real` em uma linha (~300 caracteres) com `escreva` em laço | linha completa, sem truncamento | G4 |
| P6 | `real p[100]`, `real v[25]`; preencher e ler as 125 posições | sem estouro, valores corretos | BLOQUEAR |
| P7 | função que retorna `real`; função que retorna `inteiro` com `retorne` cedo | retornos corretos | BLOQUEAR |
| P8 | laço 25×4 calculando `((y*7 + d*5) % 25) - 12` | 100 valores corretos | G7 |
| P9 | calcular `logit(0,0)` e `logit(18,10)` pela fórmula e imprimir | `0.8515625` e `1.7265625` | G1/G2 |
| P10 | `(0.0 - 0.75) * 0.0` e `((0.0 - 12.0)/16.0) * (0.0/16.0)` | sinal de zero conhecido; acúmulo neutraliza | G1 |
| P11 | concatenar tokenizador + embeddings + rede + driver | compila; `tokenizar` e `emb_*` funcionam | G6 |
| P12 | duas `const` de nomes distintos em fragmentos distintos | compila | G6 |
| P13 | 25 argmax + 25 vetores completos (625 logits) | termina em tempo aceitável (< 10 s) | G5 |
| P14 | medir BOM/CRLF/EOF dos fragmentos concatenados; conferir ASCII | ASCII puro, sem BOM, LF | corrigir no builder |

### 5.2 Critérios de conclusão de E0

- Todas as 14 sondas executadas e registradas.
- Formato escolhido (A, N-B ou N-C) e layout escolhido (duas arrays ou `estado[225]`).
- Se houve mudança, `docs/network-spec.md` atualizado para `v0.2.0` **antes** de E1.
- Tabela de gates preenchida com o resultado real.

### 5.3 Gates

| Gate | Gatilho | Ação pré-aprovada |
| --- | --- | --- |
| G1 | P3/P4/P9 falham na grade 1/256 | adotar N-B (parâmetros inteiros, logits 1/16); se N-B falhar, BLOQUEAR |
| G2 | P9 diverge do oráculo inteiro | **parar** BLOQUEADO; não ajustar valores |
| G3 | P1 falha | layout `real estado[225]` (W `0..99`, b `100..124`, emb `125..224`); API recebe só `estado[]`; driver copia a linha da M3 |
| G4 | P5 falha | N-C: 25 linhas `LOGIT` no lugar de `LOGITS` |
| G5 | P6/P13 falha | P13: reduzir determinismo a `ARGMAX` + logit máximo; P6 (arrays grandes): **parar** BLOQUEADO |
| G6 | P11/P12 colidem | renomear com `rede_`/`REDE_` |
| G7 | P2/P8 falham | init com literais e redução manual; se impossível, BLOQUEAR |

## 6. Etapas E1–E7

Cada etapa termina com um driver de scratch em `temp/e0-net/manual/` (não rastreado) e só
avança quando a saída bate com o oráculo manual. Nenhum teste do repositório é alterado
antes de E6.

### E1 — Esqueleto, inicialização e consulta de parâmetros

- **Arquivos:** `src/rede.por` (novo).
- **Conteúdo:** cabeçalho comentado, constantes, três validadores, `inicializar_rede`,
  `rede_imprimir_info`, `rede_imprimir_layout`, `rede_imprimir_validadores`,
  `rede_imprimir_peso`, `rede_imprimir_bias`, `rede_bit`.
- **Teste local:** driver que inicializa e imprime `INFO`, `LAYOUT`, 6 `PARAM`, 6 `BIAS`,
  15 linhas de `VALIDO`; comparar com a spec §6.2 e §12.
- **Conclusão:** todos os valores da grade 1/16 corretos; `LAYOUT=OK`; sem `-0.0`.
- **Fallback:** G3 (array único `estado[225]`) e G7 (init).

### E2 — Logits

- **Arquivos:** `src/rede.por`.
- **Conteúdo:** `rede_logit`, `rede_imprimir_logits`, `rede_imprimir_logit`.
- **Teste local:** `LOGITS` dos ids 0 e 24 + os 8 logits pontuais da spec §6.2; conferir
  os três zeros e a faixa `-1.2421875 .. 1.7265625`.
- **Conclusão:** 58 valores conferidos; zeros impressos como `0.0`; gramática de 8 casas.
- **Fallback:** G1 (N-B) e G4 (N-C, que remove `LOGITS` e mantém `LOGIT`).

### E3 — Argmax e empates

- **Arquivos:** `src/rede.por`.
- **Conteúdo:** `rede_argmax`, `rede_imprimir_argmax`.
- **Teste local:** 25 argmax canônicos + três cenários de empate da spec §5.5.
- **Conclusão:** sequência `0 11 19 19 24 11 1 19 2 10 11 19 19 6 11 11 19 23 10 11 19 19 6 0 11`;
  empates em `7 -> 0`, `7 -> 19`, `7 -> 3`.
- **Fallback:** nenhum; erro aqui é bug de implementação.

### E4 — Erros e precedência

- **Arquivos:** `src/rede.por`.
- **Conteúdo:** validações já presentes; revisão da ordem id→y→d e do retorno imediato.
- **Teste local:** sequência de 12 erros do §7.1.8 (`net_erros`) seguida de
  `ARGMAX=0 0`.
- **Conclusão:** cada chamada inválida emite exatamente uma linha; nenhum acesso fora dos
  vetores; estado intacto após os erros.
- **Fallback:** nenhum; erro de precedência é bug.

### E5 — Setters, atualização e reinicialização

- **Arquivos:** `src/rede.por`.
- **Conteúdo:** `rede_definir_peso`, `rede_definir_bias`.
- **Teste local:** `net_atualizacao` e `net_reinicializacao` (spec §12), com `1.7`,
  `-2.25` e `0.5`.
- **Conclusão:** `PARAM=5 2 1.7`, `BIAS=5 -2.25`, linha 6 intacta; reinit restaura
  `0.5`/`0.25`; `ARGMAX=5 11`.
- **Fallback:** se `1.7` não for impresso como `1.7`, restringir o caso a valores da grade
  1/16 e registrar a limitação (sem alterar a spec da API).

### E6 — Builder e 14 casos

- **Arquivos:** `scripts/build-network-tests.ps1` (novo), `temp/network-tests/` (gerado).
- **Conteúdo:** oráculo inteiro, tabelas canônicas, 14 drivers, 14 `.expected`, guardas.
- **Teste:** executar o builder duas vezes; comparar hashes dos 28 arquivos entre execuções
  (determinismo do gerador); conferir que existem exatamente 14 nomes.
- **Conclusão:** `.por` ASCII/UTF-8 sem BOM; `.expected` sem `\n` final; Apêndice A
  reproduzido byte a byte para os 25 `LOGITS`.
- **Fallback:** N-C altera a forma dos casos 3/4/12/13; nomes e contagem permanecem.

### E7 — Runner, verificador e regressão

- **Arquivos:** `scripts/test.ps1` (bloco aditivo), `scripts/verify-network-bytes.ps1` (novo).
- **Conteúdo:** integração do terceiro bloco; verificador com oráculo e checagens de bytes.
- **Teste:** suíte completa duas vezes; `verify-bytes.ps1`; `verify-embedding-bytes.ps1`;
  `verify-network-bytes.ps1`; autoteste; `git status`; hashes de AC19.
- **Conclusão:** 58/58, 21/21, 19/19, verificador novo 0 falhas, autoteste 1 FAIL + exit 1,
  determinismo A/B idêntico, nenhuma alteração proibida.
- **Fallback:** nenhum; qualquer falha restante vira PARCIAL/BLOQUEADO com diagnóstico.

## 7. Matriz de testes

### 7.1 Casos e saídas esperadas

Todos os drivers que consultam logits ou argmax inicializam `emb` (M3) e a rede antes da
primeira consulta; os casos indicam quando isso não é necessário. `\n` ao final de cada
linha é implícito.

#### 7.1.1 `net_info`

Driver: `rede_imprimir_info(); rede_imprimir_layout()`.

```
INFO=25 4 125
LAYOUT=OK
```

#### 7.1.2 `net_parametros`

Driver: imprime `PARAM(0,0)`, `PARAM(0,3)`, `PARAM(5,2)`, `PARAM(12,2)`,
`PARAM(24,0)`, `PARAM(24,3)`, `BIAS(0)`, `BIAS(5)`, `BIAS(7)`, `BIAS(12)`,
`BIAS(16)`, `BIAS(24)`.

```
PARAM=0 0 -0.75
PARAM=0 3 0.1875
PARAM=5 2 0.5
PARAM=12 2 0.4375
PARAM=24 0 0.375
PARAM=24 3 -0.25
BIAS=0 -0.25
BIAS=5 0.25
BIAS=7 0.0
BIAS=12 -0.0625
BIAS=16 0.0
BIAS=24 0.125
```

#### 7.1.3 `net_logits_0`

Driver: `rede_imprimir_logits(pesos, vieses, emb, 0)`.

```
LOGITS=0 0.8515625 0.03125 -0.66796875 0.1953125 0.375 0.23828125 -0.16796875 -0.28125 -0.1015625 -0.80078125 0.625 0.8046875 -0.578125 -0.30078125 0.1484375 0.328125 -0.37109375 -0.77734375 0.671875 -0.1484375 0.12890625 0.015625 0.1953125 0.05859375 -0.34765625
```

#### 7.1.4 `net_logits_24`

Driver: `rede_imprimir_logits(pesos, vieses, emb, 24)`.

```
LOGITS=24 0.2890625 0.34375 -0.26171875 -0.0859375 0.1875 0.14453125 -0.16796875 -0.1875 0.0859375 -0.51953125 0.21875 0.4921875 -0.015625 -0.42578125 0.1171875 0.390625 -0.21484375 -0.52734375 0.234375 0.2890625 -0.12109375 -0.140625 0.1328125 0.08984375 -0.22265625
```

#### 7.1.5 `net_logit_pontual`

Driver: imprime `LOGIT` para `(0,0)`, `(0,10)`, `(3,19)`, `(4,24)`, `(9,5)`, `(9,6)`,
`(16,4)`, `(21,16)`.

```
LOGIT=0 0 0.8515625
LOGIT=0 10 0.625
LOGIT=3 19 1.0
LOGIT=4 24 1.71484375
LOGIT=9 5 0.0
LOGIT=9 6 0.45703125
LOGIT=16 4 0.0
LOGIT=21 16 0.0
```

#### 7.1.6 `net_argmax_todos`

Driver: `rede_imprimir_argmax` para `id = 0..24`.

```
ARGMAX=0 0
ARGMAX=1 11
ARGMAX=2 19
ARGMAX=3 19
ARGMAX=4 24
ARGMAX=5 11
ARGMAX=6 1
ARGMAX=7 19
ARGMAX=8 2
ARGMAX=9 10
ARGMAX=10 11
ARGMAX=11 19
ARGMAX=12 19
ARGMAX=13 6
ARGMAX=14 11
ARGMAX=15 11
ARGMAX=16 19
ARGMAX=17 23
ARGMAX=18 10
ARGMAX=19 11
ARGMAX=20 19
ARGMAX=21 19
ARGMAX=22 6
ARGMAX=23 0
ARGMAX=24 11
```

#### 7.1.7 `net_validadores`

Driver: `rede_imprimir_validadores` para `(-1,0,0)`, `(0,-1,0)`, `(0,0,-1)`,
`(24,24,3)`, `(25,25,4)`.

```
VALIDO=ID 0
VALIDO=SAIDA 1
VALIDO=DIM 1
VALIDO=ID 1
VALIDO=SAIDA 0
VALIDO=DIM 1
VALIDO=ID 1
VALIDO=SAIDA 1
VALIDO=DIM 0
VALIDO=ID 1
VALIDO=SAIDA 1
VALIDO=DIM 1
VALIDO=ID 0
VALIDO=SAIDA 0
VALIDO=DIM 0
```

#### 7.1.8 `net_erros`

Driver, nesta ordem:

1. `rede_imprimir_logits(...,-1)`
2. `rede_imprimir_argmax(...,25)`
3. `rede_imprimir_logit(...,-1,0)`
4. `rede_imprimir_logit(...,-1,25)`
5. `rede_imprimir_logit(...,0,-1)`
6. `rede_imprimir_logit(...,0,25)`
7. `rede_imprimir_peso(...,25,0)`
8. `rede_imprimir_peso(...,0,-1)`
9. `rede_imprimir_peso(...,0,4)`
10. `rede_imprimir_peso(...,-1,4)`
11. `rede_imprimir_bias(...,-1)`
12. `rede_imprimir_bias(...,25)`
13. `rede_imprimir_argmax(...,0)`

```
ERRO=ID_INVALIDO
ERRO=ID_INVALIDO
ERRO=ID_INVALIDO
ERRO=ID_INVALIDO
ERRO=SAIDA_INVALIDA
ERRO=SAIDA_INVALIDA
ERRO=SAIDA_INVALIDA
ERRO=DIMENSAO_INVALIDA
ERRO=DIMENSAO_INVALIDA
ERRO=SAIDA_INVALIDA
ERRO=SAIDA_INVALIDA
ERRO=SAIDA_INVALIDA
ARGMAX=0 0
```

#### 7.1.9 `net_empate`

Driver:

```
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
zerar(pesos, vieses)                       // 125 posições = 0.0
rede_imprimir_argmax(...,7)                // tudo zero -> menor y
vieses[19] = 0.5
vieses[24] = 0.5
rede_imprimir_argmax(...,7)                // empate 19/24 -> 19
inicializar_rede(pesos, vieses)
zerar(pesos, vieses)
pesos[3*4 + d] = 0.5, d = 0..3
pesos[7*4 + d] = 0.5, d = 0..3
rede_imprimir_argmax(...,7)                // q7 = (1,4,7,10), soma 22 -> 11.0
```

```
ARGMAX=7 0
ARGMAX=7 19
ARGMAX=7 3
```

#### 7.1.10 `net_atualizacao`

Driver: init; imprimir `PARAM(5,2)` e `BIAS(5)`; definir `W(5,2)=1.7` e `B(5)=-2.25`;
imprimir de novo; imprimir `PARAM(5,1)`, `PARAM(6,2)`, `LOGIT(9,6)`.

```
PARAM=5 2 0.5
BIAS=5 0.25
PARAM=5 2 1.7
BIAS=5 -2.25
PARAM=5 1 0.1875
PARAM=6 2 -0.625
LOGIT=9 6 0.45703125
```

#### 7.1.11 `net_reinicializacao`

Driver: init; definir `W(5,2)=1.7`, `B(5)=-2.25`; init; imprimir `PARAM(5,2)`,
`BIAS(5)`, `ARGMAX(5)`.

```
PARAM=5 2 0.5
BIAS=5 0.25
ARGMAX=5 11
```

#### 7.1.12 `net_determinismo_a` e 7.1.13 `net_determinismo_b`

Driver idêntico: init de embeddings e rede; `rede_imprimir_logits` para `id = 0..24`.
Saída = as 25 linhas do **Apêndice A**, na ordem dos ids. Os dois `.expected` são
byte-idênticos; a execução em processos separados é o teste.

#### 7.1.14 `net_composicao`

Driver (fragmentos na ordem: tokenizador, embeddings, rede):

```
tokenizar("programa se")
inicializar_embeddings(emb)
inicializar_rede(pesos, vieses)
rede_imprimir_argmax(...,1)
rede_imprimir_argmax(...,9)
rede_imprimir_info()
```

```
IDS=1 9
ARGMAX=1 11
ARGMAX=9 10
INFO=25 4 125
```

A linha `IDS=1 9` é o contrato da M1 para o texto `programa se`; os dois `ARGMAX` provam
que os IDs produzidos pelo vocabulário alimentam a rede. O driver usa `1` e `9` como
constantes porque `tokenizar` imprime e não retorna a lista; a coerência é garantida pela
própria linha `IDS` no mesmo caso (se o tokenizador regredir, o caso falha).

### 7.2 Contagem

| Origem | Casos |
| --- | ---: |
| M0 (`tests/`) | 5 |
| M1 (`temp/tests`) | 20 |
| M3 (`temp/embedding-tests`) | 19 |
| M4 (`temp/network-tests`) | 14 |
| **Total** | **58** |

### 7.3 Regras dos arquivos esperados

- `.expected` contém exatamente as linhas acima, unidas por `\n`, **sem** `\n` final
  (o runner aplica `.Trim()` e compara com `-ceq`).
- `.por` é ASCII puro, UTF-8 sem BOM, LF, terminando em `\n`.
- Nenhum caso depende de aleatoriedade, tempo, ambiente ou entrada do usuário.
- Se G4 (N-C) for adotado, os casos 3, 4, 12 e 13 passam a emitir 25 linhas `LOGIT`
  (uma por `y`), mantendo os mesmos 14 nomes e a mesma contagem total.

## 8. Integração em `scripts/test.ps1`

Inserir o bloco **imediatamente após** o `foreach` dos embeddings e **antes** do `}` que
fecha `if (-not $SelfTest)` (hoje, entre as linhas 239 e 240):

```powershell
    # Gerar e anexar os casos da rede neural (M4). Diretorio proprio para nao
    # interferir nas verificacoes de bytes da M1 nem da M3.
    $networkBuilder = Join-Path $PSScriptRoot "build-network-tests.ps1"
    try {
        & $networkBuilder
    } catch {
        Write-Host "ERROR: network test builder failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $networkRoot = "temp/network-tests"
    $networkGenerated = @(Get-ChildItem -Path $networkRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($networkGenerated.Count -eq 0) {
        Write-Host "ERROR: no network test cases found in $networkRoot" -ForegroundColor Red
        exit 1
    }

    foreach ($expectedFile in $networkGenerated) {
        $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
        $testCases += @{
            Name = $caseName
            File = "$networkRoot/$caseName.por"
            ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
        }
    }
```

Cuidados de edição:

- Preservar o BOM UTF-8 e o fato de o arquivo **não** terminar em LF.
- Usar LF nas linhas novas (o arquivo é LF; o Git avisa sobre CRLF no checkout, mas o
  blob permanece LF).
- Não tocar em `Normalize-Output`, `Run-PortugolTest`, nos casos M0 nem nos blocos M1/M3.
- Após editar: `git diff -- scripts/test.ps1` deve mostrar apenas o bloco acima; conferir
  primeiro byte `0xEF 0xBB 0xBF` e último byte `0x7D`.

## 9. Builder e verificador

### 9.1 `scripts/build-network-tests.ps1`

Parâmetros: `SourcePath = "src/rede.por"`, `EmbeddingSourcePath = "src/embeddings.por"`,
`TokenizerSourcePath = "src/tokenizador.por"`, `OutputRoot = "temp/network-tests"`.

Responsabilidades:

1. Guardar que `OutputRoot` está sob `temp/` e recriar apenas esse diretório.
2. Ler os fragmentos e exigir ASCII puro, LF, sem BOM, terminando em `\n`.
3. Recalcular em aritmética inteira: `W`, `b`, os 625 `N`, os 25 argmax, margens, zeros,
   faixa e histograma; falhar se divergirem das tabelas da spec (proteção contra
   transcrição errada).
4. Formatar números com o formatador da spec §11 e conferir que todo valor canônico tem
   ≤ 8 casas e nunca é `-0.0`.
5. Montar cada caso como `fragmento(s) + driver` (cada fragmento já termina em `\n`) e
   cada `.expected` como `linhas -join "\n"`.
6. Gravar UTF-8 sem BOM, LF, sem `\n` final em `.expected`.
7. Exigir exatamente os 14 nomes da §7; falhar em nome duplicado, faltante ou extra.
8. Não usar `[double]` em nenhum cálculo de valor esperado.

### 9.2 `scripts/verify-network-bytes.ps1`

Parâmetros: `GeneratedRoot = "temp/network-tests"`, `SourcePath = "src/rede.por"`,
`EmbeddingSourcePath`, `TokenizerSourcePath`, `InterpreterPath`.

Checagens mínimas:

| ID | Checagem |
| --- | --- |
| V1 | `src/rede.por` é ASCII, fragmento, sem `inclua`, sem `aleatorio`, com as 5 constantes |
| V2 | conjunto de casos é exatamente os 14 nomes; sem faltas nem extras |
| V3 | cada `.por` compila e executa; stdout bruto começa com `0x0C` |
| V4 | carga útil usa LF puro; epílogo exato; nada depois dele |
| V5 | cada linha casa com a gramática da spec §8.1; nenhum `-0.0` |
| V6 | cada valor numérico é igual ao oráculo inteiro (comparação de string) |
| V7 | o oráculo reconfere `W`, `b`, argmax, margens, zeros, faixa e histograma |
| V8 | `net_empate` produz `ARGMAX=7 0`, `7 19`, `7 3` |
| V9 | `net_erros` produz a sequência exata e `ARGMAX=0 0` no fim |
| V10 | `net_composicao` produz `IDS=1 9` e os dois argmax |
| V11 | determinismo: A e B, duas execuções cada, bytes idênticos entre si e entre execuções |
| V12 | `.expected` de cada caso é byte-idêntico à saída do oráculo |

O verificador imprime `Total: N verificacoes, 0 falha(s)`; o valor real de `N` é anotado
no log (não é fixado aqui para não inventar número).

### 9.3 Independência

- O verificador **não** lê `.expected` para decidir valor (só para V12).
- O builder **não** chama o interpretador.
- Nenhum dos dois importa `src/rede.por` como texto executável.
- O oráculo usa `[int]`/`[long]`, nunca `[double]`, para os numeradores.

## 10. Matriz de aceitação

| ID | AC | Comando/evidência | Aprovação |
| --- | --- | --- | --- |
| MA1 | AC1 | `git rev-parse HEAD`, `git status --short`, `git rev-list --left-right --count origin/main...HEAD` | HEAD `370c296`, status limpo, `0 0` |
| MA2 | AC2 | `git status --short` + `git diff --stat` | só os 6 arquivos autorizados |
| MA3 | AC3, AC4 | inspeção de bytes + `Select-String` das constantes | ASCII, sem BOM, LF, 5 constantes |
| MA4 | AC5, AC6 | `net_parametros`, `net_logits_0`, `net_logits_24` | valores idênticos à spec §4/§6 |
| MA5 | AC7 | `verify-network-bytes.ps1` (oráculo inteiro) | 0 divergências nos 625 pares |
| MA6 | AC8 | `net_argmax_todos`, `net_empate` | 25 argmax + 3 empates corretos |
| MA7 | AC9, AC10 | `net_erros`, `net_validadores` + V5 | sequência exata, gramática, sem `-0.0` |
| MA8 | AC11 | `(Get-ChildItem temp/network-tests -Filter *.expected).Count` | `14` |
| MA9 | AC12 | `.\scripts\test.ps1` | `58 PASS / 0 FAIL`, exit `0` |
| MA10 | AC13, AC14 | verifiers M1 e M3 | `21/21` e `19/19`, exit `0` |
| MA11 | AC15 | `.\scripts\verify-network-bytes.ps1` | `0 falha(s)`, exit `0` |
| MA12 | AC16 | `.\scripts\test.ps1 -SelfTest` | `0 PASS / 1 FAIL`, exit `1` |
| MA13 | AC17 | duas execuções de A e B; comparar bytes | 4 execuções idênticas |
| MA14 | AC19 | `git hash-object` dos 6 arquivos protegidos | iguais aos hashes da §1 |
| MA15 | AC18, AC23 | busca no fragmento por `aleatorio`, `inclua`, `exp(`, `softmax` e funções de treino | nenhuma chamada/identificador proibido |
| MA16 | AC20, AC21 | `git status --short`, `git log -1` | temp ignorado; HEAD inalterado |
| MA17 | AC22, AC24 | log §13 preenchido + veredito | consistente com os resultados |

## 11. Riscos e mitigações

| ID | Risco | Probabilidade | Impacto | Mitigação |
| --- | --- | --- | --- | --- |
| R1 | linha de 25 logits truncada pelo console | média | alto | P5; G4 (N-C) |
| R2 | duas arrays na mesma assinatura não suportadas | média | alto | P1; G3 (`estado[225]` com cópia da linha de `emb`) |
| R3 | impressão de 8 casas não reproduzível | baixa | alto | P3; G1 (N-B) |
| R4 | `-0.0` em logit zero | média | médio | P4/P10; ordem da §5.2; canários `(9,5)`, `(16,4)`, `(21,16)` |
| R5 | colisão de nomes na composição | baixa | alto | P11/P12; prefixos `rede_`/`REDE_` |
| R6 | arrays de 100/25 posições estouram | baixa | alto | P6; falha = BLOQUEADO |
| R7 | regressão em M1/M3 | média | alto | AC12–AC14, AC19; verificação antes e depois |
| R8 | erro no oráculo (mesmo bug do código) | média | alto | aritmética inteira, tabelas conferidas à mão, V12 |
| R9 | `real` não é IEEE 754 binário | baixa | alto | P3/P9; se não for, BLOQUEAR |
| R10 | tempo da suíte cresce demais | baixa | médio | P13; 58 casos ≈ 75 s |
| R11 | edição do `test.ps1` quebra BOM/EOF | média | médio | checagem de bytes após editar |
| R12 | commit/push acidental | baixa | alto | AC21; nenhum `git add/commit/push` |
| R13 | `.expected` com `\n` final | média | baixo | builder grava `-join "\n"`; V12 |
| R14 | `Normalize-Output` mascara espaço final | baixa | médio | V4/V5 verificam bytes crus |
| R15 | mutação com `1.7` comparada como exata | alta (se mal feita) | médio | caso 10 imprime só valor gravado e linha não afetada |

## 12. Execução autônoma

### 12.1 Laço

```
0. Preflight: HEAD/branch/remoto/árvore; rodar as três suítes e o autoteste; registrar.
1. E0: executar P1..P14; decidir formato/layout; atualizar a spec se necessário.
2. E1..E5: implementar em src/rede.por; validar cada etapa em temp/e0-net/manual/.
3. E6: escrever o builder; gerar 14 casos; conferir o Apêndice A.
4. E7: escrever o verificador; integrar test.ps1; rodar tudo.
5. Repetir suíte + verificadores + autoteste uma segunda vez.
6. Preencher o log (§13) e emitir o relatório final (§14).
```

### 12.2 Regras

- **Sem aprovação intermediária:** os gates G1–G7 são pré-aprovados; ao disparar um gate,
  aplicar a alternativa, registrar e continuar.
- **Orçamento por falha:** até 3 tentativas de correção; depois disso, se não houver
  fallback, parar como PARCIAL.
- **Escalonamento de fallback:** no máximo 2 gates de formato/layout na mesma execução
  (por exemplo, G3 e G4); um terceiro exige parar e reportar.
- **Nunca** alterar valores canônicos, o oráculo ou os critérios para “fazer passar”.
- **Nunca** tocar nos arquivos proibidos (§4.2).
- **Nunca** executar `git add`, `git commit`, `git push`, `git tag` ou `git remote`.
- **Sempre** registrar o comando e a saída bruta relevante no log antes de concluir.

### 12.3 Condições de parada imediata

1. `HEAD` diferente de `370c296`, branch diferente de `main` ou alteração fora dos
   arquivos autorizados (§4.1).
2. Gate G2 (divergência aritmética) disparado.
3. Necessidade de alterar arquivo proibido.
4. Falha de AC sem fallback após 3 tentativas.
5. Interpretador ausente ou indisponível.

Em qualquer parada, o veredito é **BLOQUEADO** (itens 1, 2, 3, 5) ou **PARCIAL** (item 4),
com a lista exata do que foi executado e do que faltou.

### 12.4 Definição de pronto

**PRONTO** somente se AC1–AC23 forem comprovados com evidência no log, incluindo as duas
execuções completas e a comparação de bytes A/B. Caso contrário, PARCIAL ou BLOQUEADO.

## 13. Registro de evidências

Registro preenchido durante a execução (2026-10-26):

| Etapa | Comando | Resultado | Conclusão |
| --- | --- | --- | --- |
| Preflight | `git rev-parse HEAD`; `git status --short`; `scripts/test.ps1`; verificadores M1/M3; autoteste | HEAD `370c296`, branch `main`, origin `0 0`; suíte 44/44 exit 0; M1 21/21; M3 19/19; self-test 0/1 exit 1 | linha de base íntegra |
| E0/P1 | `run-probes.ps1` | PASS; duas arrays por referência, mutação visível | G3 não disparou |
| E0/P2 | idem | PASS; `(17 % 25) - 12 = 5`, `(0 % 9) - 4 = -4` | G7 não disparou |
| E0/P3 | idem | PASS; `0.00390625 0.8515625 1.7265625 -1.2421875 11.0 0.0` | G1 não disparou |
| E0/P4 | idem | PASS; `P4=-0.0 0.0` (acúmulo neutraliza) | G1 não disparou |
| E0/P5 | idem | PASS; 25 reais em uma linha, 224 bytes | G4 não disparou |
| E0/P6 | idem | PASS; `real[100]` + `real[25]`, 125 posições | sem bloqueio |
| E0/P7 | idem | PASS; retornos `real`/`inteiro` e `retorne` cedo | sem bloqueio |
| E0/P8 | idem | PASS; 100 valores de `((y*7 + d*5) % 25) - 12` | G7 não disparou |
| E0/P9 | idem | PASS; `logit(0,0)=0.8515625`, `logit(18,10)=1.7265625` | G1/G2 não dispararam |
| E0/P10 | idem | PASS; `P10=-0.0 -0.0 0.0` | G1 não disparou |
| E0/P11 | idem | PASS; tokenizador + embeddings + rede compilam; 4 linhas | G6 não disparou |
| E0/P12 | idem | PASS; `const` distintas coexistem | G6 não disparou |
| E0/P13 | idem | PASS; 25 argmax + 625 logits em 1907 ms (< 10 s) | G5 não disparou |
| E0/P14 | idem | PASS; fontes e composição ASCII, sem BOM, LF, EOF LF | empacotamento conforme |
| E1 | `run-manual.ps1 -Driver E1 -Embeddings` | PASS (INFO/PARAM/BIAS) | init e consulta de parâmetros |
| E2 | `run-manual.ps1 -Driver E2 -Embeddings` | PASS | logits |
| E3 | `run-manual.ps1 -Driver E3 -Embeddings` | PASS | argmax e empates |
| E4 | `run-manual.ps1 -Driver E4 -Embeddings` | PASS | erros e precedência |
| E5 | `run-manual.ps1 -Driver E5a/E5b -Embeddings` | PASS nos dois drivers | setters, atualização e reinicialização |
| E6 | `build-network-tests.ps1` duas vezes | 14 `.por` + 14 `.expected`; 28 arquivos, 0 hash alterado | builder determinístico; Apêndice A confere |
| E7/suíte 1 | `scripts/test.ps1` | 58 PASS / 0 FAIL, exit 0 | AC12 |
| E7/suíte 2 | `scripts/test.ps1` | 58 PASS / 0 FAIL, exit 0 | AC12 confirmado |
| E7/M1 | `scripts/verify-bytes.ps1` | 21/21, exit 0 | AC13 |
| E7/M3 | `scripts/verify-embedding-bytes.ps1` | 19/19, exit 0 | AC14 |
| E7/rede | `scripts/verify-network-bytes.ps1` | 22/22, exit 0 | AC15 |
| E7/A-B | duas execuções de `net_determinismo_a` e `_b`; SHA-256 | 4 saídas idênticas: `60ffd998…f872676`, 6680 bytes | AC17 |
| E7/self-test | `scripts/test.ps1 -SelfTest` | 0 PASS / 1 FAIL, exit 1 | AC16 |
| E7/git | `git status --short`; `git hash-object`; `git log -1` | 6 arquivos autorizados; hashes protegidos iguais ao HEAD; HEAD inalterado | AC2/AC19/AC20/AC21 |

**Resultado:** AC1–AC23 comprovados; AC24 satisfeito. Veredito **PRONTO**. Pendências:
nenhuma. Sem commit, push, tag ou alteração de remoto (AC21).

## 14. Relatório final (modelo)

```markdown
# MISSION 004 — Implementação da camada de saída linear

## Veredito
PRONTO | PARCIAL | BLOQUEADO

## Suítes
- test.ps1: 58 PASS / 0 FAIL, exit 0 (execução 1 e 2)
- verify-bytes.ps1: 21/21
- verify-embedding-bytes.ps1: 19/19
- verify-network-bytes.ps1: N/N
- autoteste: 0 PASS / 1 FAIL, exit 1

## Arquivos
(lista com hashes)

## AC1–AC24
(tabela com evidência de cada um)

## Desvios e gates
(qual gate disparou, qual alternativa foi aplicada)

## Pendências
(nenhuma ou lista)
```

## Apêndice A — 25 linhas canônicas de `LOGITS`

Fonte normativa para os casos `net_determinismo_a`/`_b` e para a conferência do builder.
Geradas por aritmética inteira (`N/256`), na ordem `id = 0..24`.

```
LOGITS=0 0.8515625 0.03125 -0.66796875 0.1953125 0.375 0.23828125 -0.16796875 -0.28125 -0.1015625 -0.80078125 0.625 0.8046875 -0.578125 -0.30078125 0.1484375 0.328125 -0.37109375 -0.77734375 0.671875 -0.1484375 0.12890625 0.015625 0.1953125 0.05859375 -0.34765625
LOGITS=1 0.359375 0.3046875 -0.3125 -0.05078125 0.2109375 0.15625 -0.16796875 -0.19921875 0.0625 -0.5546875 0.26953125 0.53125 -0.0859375 -0.41015625 0.12109375 0.3828125 -0.234375 -0.55859375 0.2890625 0.234375 -0.08984375 -0.12109375 0.140625 0.0859375 -0.23828125
LOGITS=2 -0.1328125 0.578125 0.04296875 -0.296875 0.046875 0.07421875 -0.16796875 -0.1171875 0.2265625 -0.30859375 -0.0859375 0.2578125 0.40625 -0.51953125 0.09375 0.4375 -0.09765625 -0.33984375 -0.09375 0.6171875 -0.30859375 -0.2578125 0.0859375 0.11328125 -0.12890625
LOGITS=3 -0.625 0.8515625 0.3984375 -0.54296875 -0.1171875 -0.0078125 -0.16796875 -0.03515625 0.390625 -0.0625 -0.44140625 -0.015625 0.8984375 -0.62890625 0.06640625 0.4921875 0.0390625 -0.12109375 -0.4765625 1.0 -0.52734375 -0.39453125 0.03125 0.140625 -0.01953125
LOGITS=4 -1.2421875 -0.75 0.25390625 0.0859375 -1.15625 0.41015625 1.70703125 0.171875 -1.0703125 -0.06640625 0.328125 -0.9140625 -0.984375 1.38671875 0.4140625 -0.828125 0.17578125 1.47265625 -1.234375 -0.7421875 1.62890625 0.09375 -1.1484375 0.41796875 1.71484375
LOGITS=5 0.640625 0.1484375 -0.515625 0.08984375 0.3046875 0.203125 -0.16796875 -0.24609375 -0.03125 -0.6953125 0.47265625 0.6875 -0.3671875 -0.34765625 0.13671875 0.3515625 -0.3125 -0.68359375 0.5078125 0.015625 0.03515625 -0.04296875 0.171875 0.0703125 -0.30078125
LOGITS=6 0.1484375 0.421875 -0.16015625 -0.15625 0.140625 0.12109375 -0.16796875 -0.1640625 0.1328125 -0.44921875 0.1171875 0.4140625 0.125 -0.45703125 0.109375 0.40625 -0.17578125 -0.46484375 0.125 0.3984375 -0.18359375 -0.1796875 0.1171875 0.09765625 -0.19140625
LOGITS=7 -0.34375 0.6953125 0.1953125 -0.40234375 -0.0234375 0.0390625 -0.16796875 -0.08203125 0.296875 -0.203125 -0.23828125 0.140625 0.6171875 -0.56640625 0.08203125 0.4609375 -0.0390625 -0.24609375 -0.2578125 0.78125 -0.40234375 -0.31640625 0.0625 0.125 -0.08203125
LOGITS=8 -1.2109375 -0.28125 1.55078125 -0.5234375 -0.9375 1.45703125 0.45703125 -0.25 -0.6640625 1.16796875 -0.34375 -0.7578125 -0.390625 0.07421875 -0.0703125 -0.484375 1.34765625 0.34765625 -1.140625 -0.2109375 0.25390625 -0.453125 -0.8671875 1.52734375 0.52734375
LOGITS=9 -0.578125 -0.6328125 -0.46875 1.35546875 -0.7265625 0.0 0.45703125 1.20703125 -0.875 -0.7109375 1.67578125 -0.40625 -1.0234375 0.21484375 1.52734375 -0.5546875 -0.390625 0.06640625 -0.6484375 -0.703125 0.53515625 1.28515625 -0.796875 -0.0703125 0.38671875
LOGITS=10 0.4296875 0.265625 -0.36328125 -0.015625 0.234375 0.16796875 -0.16796875 -0.2109375 0.0390625 -0.58984375 0.3203125 0.5703125 -0.15625 -0.39453125 0.125 0.375 -0.25390625 -0.58984375 0.34375 0.1796875 -0.05859375 -0.1015625 0.1484375 0.08203125 -0.25390625
LOGITS=11 -0.0625 0.5390625 -0.0078125 -0.26171875 0.0703125 0.0859375 -0.16796875 -0.12890625 0.203125 -0.34375 -0.03515625 0.296875 0.3359375 -0.50390625 0.09765625 0.4296875 -0.1171875 -0.37109375 -0.0390625 0.5625 -0.27734375 -0.23828125 0.09375 0.109375 -0.14453125
LOGITS=12 -0.5546875 0.8125 0.34765625 -0.5078125 -0.09375 0.00390625 -0.16796875 -0.046875 0.3671875 -0.09765625 -0.390625 0.0234375 0.828125 -0.61328125 0.0703125 0.484375 0.01953125 -0.15234375 -0.421875 0.9453125 -0.49609375 -0.375 0.0390625 0.13671875 -0.03515625
LOGITS=13 -1.171875 -0.7890625 0.203125 0.12109375 -1.1328125 0.421875 1.70703125 0.16015625 -1.09375 -0.1015625 0.37890625 -0.875 -1.0546875 1.40234375 0.41796875 -0.8359375 0.15625 1.44140625 -1.1796875 -0.796875 1.66015625 0.11328125 -1.140625 0.4140625 1.69921875
LOGITS=14 0.7109375 0.109375 -0.56640625 0.125 0.328125 0.21484375 -0.16796875 -0.2578125 -0.0546875 -0.73046875 0.5234375 0.7265625 -0.4375 -0.33203125 0.140625 0.34375 -0.33203125 -0.71484375 0.5625 -0.0390625 0.06640625 -0.0234375 0.1796875 0.06640625 -0.31640625
LOGITS=15 0.21875 0.3828125 -0.2109375 -0.12109375 0.1640625 0.1328125 -0.16796875 -0.17578125 0.109375 -0.484375 0.16796875 0.453125 0.0546875 -0.44140625 0.11328125 0.3984375 -0.1953125 -0.49609375 0.1796875 0.34375 -0.15234375 -0.16015625 0.125 0.09375 -0.20703125
LOGITS=16 -0.2734375 0.65625 0.14453125 -0.3671875 0.0 0.05078125 -0.16796875 -0.09375 0.2734375 -0.23828125 -0.1875 0.1796875 0.546875 -0.55078125 0.0859375 0.453125 -0.05859375 -0.27734375 -0.203125 0.7265625 -0.37109375 -0.296875 0.0703125 0.12109375 -0.09765625
LOGITS=17 -1.140625 -0.3203125 1.5 -0.48828125 -0.9140625 1.46875 0.45703125 -0.26171875 -0.6875 1.1328125 -0.29296875 -0.71875 -0.4609375 0.08984375 -0.06640625 -0.4921875 1.328125 0.31640625 -1.0859375 -0.265625 0.28515625 -0.43359375 -0.859375 1.5234375 0.51171875
LOGITS=18 -0.5078125 -0.671875 -0.51953125 1.390625 -0.703125 0.01171875 0.45703125 1.1953125 -0.8984375 -0.74609375 1.7265625 -0.3671875 -1.09375 0.23046875 1.53125 -0.5625 -0.41015625 0.03515625 -0.59375 -0.7578125 0.56640625 1.3046875 -0.7890625 -0.07421875 0.37109375
LOGITS=19 0.5 0.2265625 -0.4140625 0.01953125 0.2578125 0.1796875 -0.16796875 -0.22265625 0.015625 -0.625 0.37109375 0.609375 -0.2265625 -0.37890625 0.12890625 0.3671875 -0.2734375 -0.62109375 0.3984375 0.125 -0.02734375 -0.08203125 0.15625 0.078125 -0.26953125
LOGITS=20 0.0078125 0.5 -0.05859375 -0.2265625 0.09375 0.09765625 -0.16796875 -0.140625 0.1796875 -0.37890625 0.015625 0.3359375 0.265625 -0.48828125 0.1015625 0.421875 -0.13671875 -0.40234375 0.015625 0.5078125 -0.24609375 -0.21875 0.1015625 0.10546875 -0.16015625
LOGITS=21 -0.484375 0.7734375 0.296875 -0.47265625 -0.0703125 0.015625 -0.16796875 -0.05859375 0.34375 -0.1328125 -0.33984375 0.0625 0.7578125 -0.59765625 0.07421875 0.4765625 0.0 -0.18359375 -0.3671875 0.890625 -0.46484375 -0.35546875 0.046875 0.1328125 -0.05078125
LOGITS=22 -1.1015625 -0.828125 0.15234375 0.15625 -1.109375 0.43359375 1.70703125 0.1484375 -1.1171875 -0.13671875 0.4296875 -0.8359375 -1.125 1.41796875 0.421875 -0.84375 0.13671875 1.41015625 -1.125 -0.8515625 1.69140625 0.1328125 -1.1328125 0.41015625 1.68359375
LOGITS=23 0.78125 0.0703125 -0.6171875 0.16015625 0.3515625 0.2265625 -0.16796875 -0.26953125 -0.078125 -0.765625 0.57421875 0.765625 -0.5078125 -0.31640625 0.14453125 0.3359375 -0.3515625 -0.74609375 0.6171875 -0.09375 0.09765625 -0.00390625 0.1875 0.0625 -0.33203125
LOGITS=24 0.2890625 0.34375 -0.26171875 -0.0859375 0.1875 0.14453125 -0.16796875 -0.1875 0.0859375 -0.51953125 0.21875 0.4921875 -0.015625 -0.42578125 0.1171875 0.390625 -0.21484375 -0.52734375 0.234375 0.2890625 -0.12109375 -0.140625 0.1328125 0.08984375 -0.22265625
```
