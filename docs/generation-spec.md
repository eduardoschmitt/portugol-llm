# Especificação — Geração autoregressiva determinística (M6)

- **Versão:** 1.0.0 (congelada em E0; nenhum gate disparou)
- **Status:** contrato congelado v1.0.0; implementação de E0–E7 concluída e
  validada (M6). Evidências em `docs/generation-plan.md` §10.1, §13 e §14.
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0), M5
  (`docs/training-spec.md` v1.0.0).
- **Plano de execução:** `docs/generation-plan.md`.
- **Fora de escopo:** Transformer, atenção, contexto multi-token, memória, softmax,
  amostragem aleatória, temperatura, top-k, top-p, beam search, treinamento,
  embeddings treináveis, detokenização inversa, commit e push.

## 1. Contrato

Esta missão define **um** gerador autoregressivo mínimo sobre os parâmetros já
treinados pela M5. O contrato é:

1. receber um token inicial `semente` em `0..24`;
2. receber o estado treinado `w16[100]` e `b16[25]` da M5, sem alterá-lo;
3. calcular, para o token atual, os 25 logits da camada afim da M4;
4. selecionar o próximo token por `argmax` determinístico, com desempate pelo
   menor `y`;
5. acrescentar o token previsto ao fim da sequência;
6. realimentar esse token como entrada da próxima iteração;
7. parar ao atingir o limite de tokens ou ao emitir o token de parada `pare` (24).

O gerador não aprende, não atualiza parâmetros, não lê teclado, não usa tempo,
não usa aleatoriedade e não abre arquivos. É uma função pura de
`(w16, b16, semente, maximo)`.

### 1.1 O que esta missão entrega

O contrato normativo está congelado em v1.0.0. A missão entregou:

- `docs/generation-spec.md` (este documento);
- `docs/generation-plan.md`;
- `src/gerador.por`;
- `scripts/build-generation-tests.ps1`;
- `scripts/verify-generation-bytes.ps1`;
- bloco aditivo de 24 linhas em `scripts/test.ps1`.

A implementação de E0–E7 está concluída e as evidências medidas estão no plano
§10.1, §13 e §14. Nenhuma regra normativa desta spec mudou depois do
congelamento em E0.

### 1.2 O que "gerar" prova e não prova

| Conceito | O que é | O que não é |
| --- | --- | --- |
| Token previsto | saída de `argmax` sobre 25 logits inteiros | amostra de uma distribuição |
| Texto reconstruído | concatenação literal das palavras do vocabulário, com `UNK` para 0 | inverso fiel do tokenizador |
| Sequência memorizada | as transições dos 4 pares da M5: `9→12`, `12→13`, `13→14`, `14→24` | compreensão de programas |
| Generalização | nada além de consultar a mesma camada afim para o último token | capacidade de continuar código novo |

A cadeia `9 12 13 14 24` é a justaposição exata das quatro transições memorizadas.
Ela demonstra que o laço usa os parâmetros treinados, não que o modelo aprendeu a
linguagem. Sementes fora de `{9,12,13,14}` produzem o `argmax` das linhas
treinadas, mas não há evidência de generalização.

## 2. Decisões de arquitetura

### 2.1 Menor mecanismo viável

O gerador **não reimplementa** o modelo. Ele reutiliza o forward da M5:

```
próximo(token) = treino_argmax(w16, b16, token)
```

`treino_argmax` já calcula, para o token dado, os 25 `Z256` e devolve o índice do
maior valor com desempate pelo menor `y`. O gerador acrescenta somente:

1. o laço de realimentação;
2. a política de parada;
3. a cópia do token inicial para a saída;
4. a serialização observável e a reconstrução textual.

Essa escolha mantém uma única definição do forward e impede divergência entre
treino, rede e geração.

### 2.2 Por que o caminho é inteiro

O estado treinado é `w16`/`b16` em unidades de `1/16`. O forward da M5 produz
`Z256 = 256·z`, com valores absolutos limitados por

```
|Z256| ≤ 4·48·16 + 16·48 = 3840
```

Portanto:

- não há estouro em 32 bits;
- o `argmax` de `Z256` é idêntico ao `argmax` de `z`, pois a escala é positiva;
- nenhum `real` é necessário no caminho da geração;
- a decisão é exata e reproduzível byte a byte.

A equivalência com a M4 foi conferida nas três implementações independentes do
oráculo (§10): o mapa `rede_argmax` sobre os parâmetros materializados é idêntico
ao mapa `treino_argmax` para os 25 tokens, nos estados inicial e treinado.

### 2.3 Por que `pare` é o token de parada

`pare` é o ID 24, o último token do vocabulário e o alvo do quarto par da M5
(`14→24`). Usá-lo como parada:

- não inventa um token especial fora do vocabulário;
- encerra a cadeia memorizada exatamente no alvo treinado;
- permite demonstrar parada antecipada sem `if` específico de exemplo;
- mantém o conjunto de IDs fechado em `0..24`.

`UNK` (0) **não** é parada. É um token válido, com embedding próprio, e pode
aparecer na saída.

### 2.4 Por que o token inicial é incluído

A saída contém o token inicial na posição 0. Justificativas:

- a sequência `9 12 13 14 24` é diretamente comparável à cadeia do dataset;
- `N` é o comprimento total e `PASSOS = N − 1` é o número de `argmax` executados;
- não há duas convenções possíveis para o mesmo caso (incluir/excluir);
- o token inicial faz parte da "sequência produzida a partir de uma semente".

Consequência: `maximo = 1` produz exatamente a semente; `maximo` conta tokens,
não passos.

### 2.5 Por que não há detecção de ciclo

O gerador é uma função determinística de 25 tokens para 25 tokens. Ciclos são
possíveis e legítimos:

- com o estado canônico, `11→19→11` é um ciclo de período 2 e `0→0` é um
  auto-ciclo;
- com o estado treinado da M5, todo token alcança `pare` em até 4 passos.

Não há conjunto de visitados, porque:

1. detectar ciclo exigiria memória auxiliar e uma segunda política de parada;
2. o limite `maximo` já garante terminação;
3. repetições são parte observável do comportamento e devem ser impressas, não
   escondidas.

### 2.6 Por que não há amostragem

A missão proíbe aleatoriedade, temperatura, top-k e top-p. Além disso, amostragem
exigiria uma fonte de entropia e/ou uma distribuição normalizada; o projeto não
tem `exp` exato e não aceita tolerância. `argmax` é a única seleção compatível com
a propriedade de bytes determinísticos.

### 2.7 Por que a reconstrução textual é impressa, não armazenada

Não existe função pública que retorne `cadeia` em nenhum módulo anterior, e a
M1 não é inversível: `Se`, `se,` e `inicio()` perdem informação. Portanto:

- a representação normativa da sequência é o array de IDs;
- o texto é uma **projeção legível** dos IDs, gerada na impressão;
- `0` imprime `UNK`;
- não se promete recuperar o texto original.

### 2.8 O que não entra

- contexto de mais de um token;
- janela deslizante;
- cache de atenção;
- estados ocultos;
- probabilidades;
- escolha de top-k/top-p;
- parada por pontuação;
- detokenização com pontuação ou caixa.

## 3. Estado, layout e invariantes

### 3.1 Arrays

| Array | Tamanho | Papel | Mutação |
| --- | ---: | --- | --- |
| `w16[100]` | 100 | pesos treinados, `W[y][d]` em `y*4+d` | nenhuma |
| `b16[25]` | 25 | vieses treinados, `b[y]` | nenhuma |
| `saida[64]` | 64 | sequência produzida, IDs em `0..24` | escrita só em `0..N−1` |

O chamador declara os três arrays. O gerador não aloca estado interno persistente.

### 3.2 Constantes

| Constante | Valor | Uso |
| --- | ---: | --- |
| `GERADOR_TAM_VOCAB` | 25 | IDs válidos `0..24` |
| `GERADOR_DIM` | 4 | dimensão dos embeddings |
| `GERADOR_SAIDAS` | 25 | número de logits |
| `GERADOR_PARAMS` | 125 | parâmetros consumidos |
| `GERADOR_MAX_TOKENS` | 64 | limite máximo de tokens na saída |
| `GERADOR_TOKEN_UNK` | 0 | `UNK`, token válido |
| `GERADOR_TOKEN_PARADA` | 24 | `pare` |

### 3.3 Invariantes

| ID | Invariante |
| --- | --- |
| I1 | `0 ≤ saida[i] ≤ 24` para todo `i < N` |
| I2 | `1 ≤ maximo ≤ 64` |
| I3 | `1 ≤ N ≤ maximo` |
| I4 | `saida[0] = semente` |
| I5 | `saida[i+1] = treino_argmax(w16, b16, saida[i])` para `i < N−1` |
| I6 | se `saida[N−1] = 24`, então `PARADA=PARE`; senão `PARADA=MAXIMO` |
| I7 | `PASSOS = N − 1` |
| I8 | `w16` e `b16` não são escritos em nenhum caminho |
| I9 | em erro de validação, `saida` não é escrita |
| I10 | `N < maximo` só é possível quando `saida[N−1] = 24` |

A invariante I10 é a recíproca de I6 para o caso de parada antecipada: se o laço
parou antes do limite, foi porque encontrou `pare`.

### 3.4 Faixa dos logits

Com `|W16| ≤ 48`, `|e16| ≤ 16` e `|b16| ≤ 48`:

```
|Z256| ≤ 4·48·16 + 16·48 = 3840
```

O maior valor observado no estado treinado da M5 é `349`. Não há multiplicação
de dois estados variáveis, então não existe risco de estouro em 32 bits.

## 4. Algoritmo normativo

### 4.1 Pseudocódigo

```
funcao gerador_gerar(w16, b16, semente, maximo, saida[]) -> inteiro
    // Pre-condicao: semente em 0..24, maximo em 1..64,
    // saida tem capacidade >= 64.
    saida[0] = semente
    total = 1

    enquanto (total < maximo)
        se (saida[total - 1] == GERADOR_TOKEN_PARADA)
            retorne total

        proximo = treino_argmax(w16, b16, saida[total - 1])
        saida[total] = proximo
        total = total + 1

    retorne total
```

O laço verifica `pare` **antes** de calcular o próximo token. Assim, a semente
`24` não gera nenhum passo e o token `24` previsto é incluído e encerra a
sequência.

### 4.2 Derivação da parada

```
se (saida[total - 1] == 24)
    PARADA = PARE
senao
    PARADA = MAXIMO
```

Consequências:

| Situação | `N` | `PASSOS` | `PARADA` |
| --- | ---: | ---: | --- |
| semente `24`, qualquer `maximo ≥ 1` | 1 | 0 | `PARE` |
| semente `9`, `maximo = 1` | 1 | 0 | `MAXIMO` |
| semente `9`, `maximo = 4` | 4 | 3 | `MAXIMO` |
| semente `9`, `maximo = 5` | 5 | 4 | `PARE` |
| semente `14`, `maximo = 64` | 2 | 1 | `PARE` |

`PARE` tem precedência sobre `MAXIMO` quando os dois coincidem: com
`maximo = 5`, a cadeia termina em `24` no último slot e a saída é `PARE`.

### 4.3 Ordem de validação

`gerador_imprimir_geracao` valida **antes** de escrever qualquer byte:

1. `semente` em `0..24` → senão `ERRO=TOKEN_INVALIDO`;
2. `maximo` em `1..64` → senão `ERRO=LIMITE_INVALIDO`;
3. `|w16[i]| ≤ 48` e `|b16[y]| ≤ 48` → senão `ERRO=PARAMETROS_INVALIDOS`.

A ordem é fixa. `semente = -1` e `maximo = 0` produz `TOKEN_INVALIDO`, não
`LIMITE_INVALIDO`.

### 4.4 Escrita na saída

- `saida[0]` recebe a semente;
- cada iteração escreve exatamente `saida[total]` e incrementa `total`;
- posições `≥ N` nunca são escritas;
- em erro de validação, nenhuma posição é escrita;
- em sucesso, `total` é o retorno e `N = total`.

## 5. API

### 5.1 Validadores puros

```portugol
funcao logico gerador_token_valido(inteiro token)
funcao logico gerador_limite_valido(inteiro maximo)
```

- `gerador_token_valido`: `verdadeiro` se `0 ≤ token ≤ 24`.
- `gerador_limite_valido`: `verdadeiro` se `1 ≤ maximo ≤ 64`.
- Não acessam arrays e não imprimem.

### 5.2 Núcleo

```portugol
funcao inteiro gerador_proximo(inteiro w16[], inteiro b16[], inteiro token)
funcao inteiro gerador_gerar(inteiro w16[], inteiro b16[],
                            inteiro semente, inteiro maximo,
                            inteiro saida[])
```

- `gerador_proximo`: pré-condição `0 ≤ token ≤ 24`; retorna
  `treino_argmax(w16, b16, token)` em `0..24`; não imprime e não muta nada.
- `gerador_gerar`: pré-condições de §4.1; preenche `saida[0..N−1]` e retorna
  `N`; não imprime e não valida (o chamador valida ou usa o wrapper).
- Ambas são puras em relação a `w16`/`b16`.

### 5.3 Impressoras

```portugol
funcao gerador_imprimir_config()
funcao gerador_imprimir_validadores(inteiro token, inteiro maximo)
funcao gerador_imprimir_geracao(inteiro w16[], inteiro b16[],
                                inteiro semente, inteiro maximo)
funcao gerador_imprimir_texto(inteiro saida[], inteiro total)
funcao gerador_imprimir_palavra(inteiro token)
```

| Função | Saída | Validação |
| --- | --- | --- |
| `gerador_imprimir_config` | `INFO=GERADOR 25 64 4 125`, `TOKEN_PARADA=24`, `TOKEN_UNK=0`, `LIMITE_MAXIMO=64` | nenhuma |
| `gerador_imprimir_validadores` | `VALIDO=TOKEN <token> <0\|1>`, `VALIDO=LIMITE <maximo> <0\|1>` | nenhuma |
| `gerador_imprimir_geracao` | bloco de 5 linhas (§6.1) | semente, limite, parâmetros |
| `gerador_imprimir_texto` | `TEXTO=<palavra>...` | total `0..64`; cada ID `0..24` |
| `gerador_imprimir_palavra` | `PALAVRA=<id> <palavra>` | ID `0..24` |

`gerador_imprimir_geracao` é a única função que produz o bloco completo; ela
chama `gerador_imprimir_texto` internamente para a última linha.

### 5.4 Auxiliar interna

```portugol
funcao gerador_escrever_palavra(inteiro token)
```

Escreve apenas a palavra correspondente ao ID, sem espaço e sem `\n`.
Pré-condição: `0 ≤ token ≤ 24`. É usada por `gerador_imprimir_texto` e por
`gerador_imprimir_palavra`.

### 5.5 Nomes e prefixos

- Funções e constantes usam `gerador_`/`GERADOR_`.
- Nenhum identificador usa `e` isolado (restrição observada na M5).
- O módulo não declara `programa`, `inicio` ou `inclua`.
- O módulo não chama M1, M3 ou M4 em tempo de execução; depende apenas de
  `treino_argmax` e `treino_params_validos` da M5.

### 5.6 Mapa de palavras

| ID | Palavra | ID | Palavra | ID | Palavra |
| ---: | --- | ---: | --- | ---: | --- |
| 0 | `UNK` | 9 | `se` | 18 | `leia` |
| 1 | `programa` | 10 | `senao` | 19 | `e` |
| 2 | `funcao` | 11 | `enquanto` | 20 | `ou` |
| 3 | `inicio` | 12 | `faca` | 21 | `nao` |
| 4 | `inteiro` | 13 | `para` | 22 | `verdadeiro` |
| 5 | `real` | 14 | `ate` | 23 | `falso` |
| 6 | `logico` | 15 | `passo` | 24 | `pare` |
| 7 | `cadeia` | 16 | `retorne` | | |
| 8 | `vazio` | 17 | `escreva` | | |

`UNK` é o único texto que não é uma palavra do vocabulário; ele representa o
próprio ID 0.

## 6. Formato observável

### 6.1 Bloco de geração

Sucesso produz exatamente cinco linhas, nesta ordem:

```
GERADO=<id>[ <id>]*
N=<total>
PASSOS=<total - 1>
PARADA=<PARE|MAXIMO>
TEXTO=<palavra>[ <palavra>]*
```

Regras:

- `GERADO` contém `N` IDs em decimal ASCII, separados por um espaço, sem espaço
  antes do primeiro nem depois do último;
- `N` é o número de IDs;
- `PASSOS = N − 1`;
- `PARADA` é `PARE` se o último ID for 24; senão `MAXIMO`;
- `TEXTO` contém `N` palavras, com `UNK` para 0, separadas por um espaço;
- `TEXTO=` (vazio) só é possível na impressora isolada com `total = 0`;
- todas as linhas usam LF; não há linha em branco.

### 6.2 Impressão textual isolada

`gerador_imprimir_texto(saida, total)` produz uma única linha:

```
TEXTO=<palavra>[ <palavra>]*
```

- `total = 0` produz `TEXTO=` + LF;
- `total` fora de `0..64` ou ID fora de `0..24` produz
  `ERRO=SEQUENCIA_INVALIDA` + LF, sem `TEXTO=`;
- a validação percorre todos os IDs antes de imprimir qualquer palavra.

### 6.3 Impressão de palavra

`gerador_imprimir_palavra(token)` produz:

```
PALAVRA=<id> <palavra>
```

- ID inválido produz `ERRO=ID_INVALIDO` (mesmo texto da M3/M4 para simetria);
- o mapa é o de §5.6.

### 6.4 Configuração e validadores

```
INFO=GERADOR 25 64 4 125
TOKEN_PARADA=24
TOKEN_UNK=0
LIMITE_MAXIMO=64
```

```
VALIDO=TOKEN <token> <0|1>
VALIDO=LIMITE <maximo> <0|1>
```

### 6.5 Exemplos canônicos

Estado treinado (5 épocas da M5), semente 9, `maximo = 16`:

```
GERADO=9 12 13 14 24
N=5
PASSOS=4
PARADA=PARE
TEXTO=se faca para ate pare
```

Estado canônico (sem treino), semente 9, `maximo = 8`:

```
GERADO=9 10 11 19 11 19 11 19
N=8
PASSOS=7
PARADA=MAXIMO
TEXTO=se senao enquanto e enquanto e enquanto e
```

Estado canônico, semente 19, `maximo = 8` (ciclo de período 2):

```
GERADO=19 11 19 11 19 11 19 11
N=8
PASSOS=7
PARADA=MAXIMO
TEXTO=e enquanto e enquanto e enquanto e enquanto
```

Estado treinado, semente 0 (`UNK`), `maximo = 16`:

```
GERADO=0 24
N=2
PASSOS=1
PARADA=PARE
TEXTO=UNK pare
```

Estado treinado, semente 24 (`pare`), `maximo = 16`:

```
GERADO=24
N=1
PASSOS=0
PARADA=PARE
TEXTO=pare
```

### 6.6 Condição de congelamento

O formato congela em E0. Qualquer mudança posterior exige atualizar esta spec
para `v1.1.0`, regenerar todos os `.expected` e reexecutar a matriz completa.

## 7. Erros

### 7.1 Códigos

| Texto | Condição | Mutação |
| --- | --- | --- |
| `ERRO=TOKEN_INVALIDO` | `semente < 0` ou `semente > 24` | nenhuma |
| `ERRO=LIMITE_INVALIDO` | `maximo < 1` ou `maximo > 64` | nenhuma |
| `ERRO=PARAMETROS_INVALIDOS` | `\|w16[i]\| > 48` ou `\|b16[y]\| > 48` | nenhuma |
| `ERRO=SEQUENCIA_INVALIDA` | `total` fora de `0..64` ou ID fora de `0..24` em `gerador_imprimir_texto` | nenhuma |
| `ERRO=ID_INVALIDO` | ID fora de `0..24` em `gerador_imprimir_palavra` | nenhuma |

### 7.2 Precedência

- `gerador_imprimir_geracao`: `TOKEN_INVALIDO → LIMITE_INVALIDO →
  PARAMETROS_INVALIDOS`.
- `gerador_imprimir_texto`: `total` antes dos IDs.
- `gerador_imprimir_palavra`: apenas o ID.

### 7.3 Estado em caso de erro

Nenhum erro de validação escreve em `saida`, `w16` ou `b16`. O chamador pode
reutilizar o buffer sem limpeza. Não existe erro parcial: ou a linha de erro é a
única saída da chamada, ou o bloco completo é emitido.

### 7.4 Sem rollback necessário

O gerador não muta o estado, então não há análogo ao `ESTOURO_NUMERICO` da M5.
A única escrita é no buffer de saída, e ela só ocorre depois da validação.

## 8. Determinismo

O gerador é determinístico por construção:

1. não usa `aleatorio`, tempo, `leia`, arquivos ou ambiente;
2. usa apenas `+`, `−`, `*`, `/` inteiros e comparações;
3. a ordem dos laços é fixa (`y = 0..24`, `d = 0..3` dentro de
   `treino_argmax`);
4. o desempate do `argmax` é fixo (menor `y`);
5. a saída é uma função pura de `(w16, b16, semente, maximo)`.

Duas execuções em processos separados, com os mesmos argumentos, produzem os
mesmos bytes. Não há dependência de locale, de histórico de chamadas nem de
estado global mutável.

## 9. Integração

### 9.1 Fluxo completo

```
texto --M1--> IDs --M3--> embeddings --M4--> logits --M5--> w16/b16
                                                     |
                                                     v
                                    M6: semente -> argmax -> ... -> pare/limite
```

### 9.2 Contratos preservados

| Módulo | Uso | Alteração |
| --- | --- | --- |
| M1 `tokenizar` | produz IDs para a semente e para a comparação textual | nenhuma |
| M3 `inicializar_embeddings`/`emb_obter` | embeddings congelados | nenhuma |
| M4 `rede_argmax`/`rede_logit` | conferência independente do passo | nenhuma |
| M5 `treino_argmax` | forward inteiro usado pelo gerador | nenhuma |
| M5 `treino_params_validos` | validação dos 125 parâmetros | nenhuma |
| M5 `treino_materializar` | converte o estado para a conferência M4 | nenhuma |

O gerador **não** importa nem chama M1/M3/M4 em tempo de execução. A composição
é provada por um caso de teste que concatena os cinco fragmentos.

### 9.3 Compatibilidade real × inteiro

Para qualquer estado válido da M5, `treino_materializar` produz valores
múltiplos de `1/16`. Como `e16` também é múltiplo de `1/16`, cada produto é
múltiplo de `1/256` e a soma é exata em `double` para a faixa da §3.4. Logo:

```
rede_argmax(pesos, vieses, emb, id) = treino_argmax(w16, b16, id)
```

para todo `id` em `0..24`. Essa igualdade é conferida em E0 e no caso
`gen_composicao`; uma divergência não é mascarada: para a missão e exige
investigação (G9).

### 9.4 Sem modificação dos módulos anteriores

Nenhum arquivo de M1–M5 é alterado. O gerador é um fragmento novo concatenado
aos anteriores apenas nos drivers de teste. O tokenizador continua com 25 IDs,
os embeddings com dimensão 4 e a rede com 125 parâmetros.

## 10. Oráculo independente

Durante o planejamento, os valores canônicos foram calculados por **três**
implementações independentes:

1. Python inteiro (Anexo A);
2. Python `double` com os mesmos valores em `1/16`, comparando `argmax`;
3. PowerShell inteiro, com tabelas canônicas explícitas.

As três produziram exatamente o mesmo mapa de transição, as mesmas cadeias e a
mesma igualdade `rede_argmax = treino_argmax` nos 25 tokens. A diferença máxima
entre `z` em `double` e `Z256/256` foi `0`.

Na implementação, o builder foi a quarta implementação (PowerShell inteiro), o
fragmento em Portugol a quinta e o verificador a sexta; os três re-derivaram as
cadeias a partir das tabelas canônicas, sem ler `.expected` para decidir valores.
As seis implementações concordaram nos 25 mapas e nas cadeias de `0..24`. O
verificador `scripts/verify-generation-bytes.ps1` confere:

| ID | Conferência |
| --- | --- |
| V1 | fonte ASCII, sem BOM, LF, sem `programa`/`inicio`/`inclua`, sem `aleatorio`/`tempo`/`leia`, sem `softmax`/`exp(`/`temperatura`/`top_` |
| V2 | conjunto exatamente igual a 14 casos `gen_*` |
| V3 | bytes crus de todos os casos: `\f` inicial, carga ASCII com LF, epílogo exato |
| V4 | configuração e validadores de fronteira |
| V5 | cadeias treinadas re-derivadas das tabelas canônicas da M5 |
| V6 | `N`, `PASSOS`, `PARADA` coerentes com a sequência e com `maximo` |
| V7 | cadeias canônicas e ciclo de período 2 |
| V8 | `UNK`, semente `pare`, parada antecipada e precedência `PARE`/`MAXIMO` |
| V9 | erros e preservação de estado/buffer |
| V10 | determinismo A/B byte a byte, incluindo segunda execução |
| V11 | composição: IDs da M1, mapa da M4 e mapa da M5 coincidem |
| V12 | `.expected` sem LF final, CR, BOM ou espaços nas pontas |
| V13 | mapa completo dos 25 inícios no estado treinado |

## 11. Casos obrigatórios

| # | Caso | Verifica |
| ---: | --- | --- |
| 1 | `gen_info` | configuração, validadores e limites |
| 2 | `gen_canonico` | estado canônico, semente 9, `maximo=8` |
| 3 | `gen_ciclo` | ciclo canônico `19↔11`, período 2, limite |
| 4 | `gen_treinado_cadeia` | cadeia `9 12 13 14 24` após 5 épocas |
| 5 | `gen_treinado_parada` | semente 14, parada imediata em `24` |
| 6 | `gen_unk` | semente 0, `UNK` não é parada |
| 7 | `gen_inicial_pare` | semente 24, zero passos |
| 8 | `gen_limites` | `maximo=1,4,5,64`; precedência `PARE` |
| 9 | `gen_erros` | semente/limite/parâmetros inválidos; estado intacto |
| 10 | `gen_texto` | 25 palavras, `UNK`, texto vazio e erros |
| 11 | `gen_mapa_treinado` | os 25 inícios no estado treinado |
| 12 | `gen_determinismo_a` | execução completa no processo A |
| 13 | `gen_determinismo_b` | mesma execução no processo B, bytes iguais |
| 14 | `gen_composicao` | M1→M3→M4→M5→M6, `PARAMS_INTACTOS=OK` |

A matriz completa de entradas e saídas está em `docs/generation-plan.md` §7.
Qualquer caso extra deve ser aditivo e não pode alterar os 14 anteriores.

## 12. Critérios de aceitação

Cada critério é verificável por comando. "PASS" significa saída observada igual
à esperada, não ausência de exceção.

| ID | Critério | Verificação |
| --- | --- | --- |
| AC1 | apenas os arquivos autorizados foram criados/alterados | `git status --short` |
| AC2 | 70 testes anteriores preservados | `scripts/test.ps1` = 84 PASS / 0 FAIL |
| AC3 | M1/M3/M4/M5 sem regressão | 21/21, 19/19, 22/22, 23/23, exit `0` |
| AC4 | autoteste continua falhando de propósito | `test.ps1 -SelfTest` = 0 PASS / 1 FAIL, exit `1` |
| AC5 | 14 casos novos, todos PASS | suíte 84/84; verificador ≥ 13/13 |
| AC6 | oráculo independente | verificador re-deriva as cadeias das tabelas canônicas |
| AC7 | cadeia treinada | `GERADO=9 12 13 14 24`, `PARADA=PARE` |
| AC8 | geração canônica | `GERADO=9 10 11 19 11 19 11 19` |
| AC9 | ciclo | `19 11 19 11 19 11 19 11`, `CICLO=2`, `PARADA=MAXIMO` |
| AC10 | `pare` | semente 14 → `14 24`; semente 24 → `24`, `PASSOS=0` |
| AC11 | `UNK` | semente 0 → `0 24`, `TEXTO=UNK pare` |
| AC12 | limites | `maximo=1` → só a semente; `maximo=4` → `MAXIMO`; `maximo=5` → `PARE`; `maximo=64` aceito |
| AC13 | erros | `TOKEN_INVALIDO`, `LIMITE_INVALIDO`, `PARAMETROS_INVALIDOS`, `SEQUENCIA_INVALIDA` |
| AC14 | preservação | `INTACTO=OK`, `SAIDA_INTACTA=OK`, `PARAMS_INTACTOS=OK` |
| AC15 | determinismo | `trn`/`gen` A ≡ B byte a byte |
| AC16 | composição | `ARGMAX_REDE` = `ARGMAX_TREINO` = `12 13 14 24` |
| AC17 | sem aleatoriedade | V1 do verificador |
| AC18 | módulos anteriores intactos | 12 hashes de `HEAD` conferidos |
| AC19 | runner preservado | BOM e último byte `0x7D`; 24 linhas aditivas |
| AC20 | documentação | este documento e o plano com evidências medidas |

Resultado medido em E7: AC1–AC20 satisfeitos. Os comandos, saídas e exit codes
estão em `docs/generation-plan.md` §10.1 e §13.

## 13. Limitações

1. **Memorização de 4 transições.** A cadeia de 5 tokens não é generalização.
2. **Contexto de 1 token.** O próximo token depende apenas do último; não há
   histórico.
3. **Vocabulário fechado.** Só `0..24`; palavras fora da tabela nunca são
   produzidas.
4. **UNK sem semântica.** `UNK` é um ID como outro qualquer; não há
   desconhecimento explícito nem abstenção.
5. **Texto não inversível.** `TEXTO` não recupera caixa, acentos, pontuação ou
   campos UNK.
6. **Parada única.** Apenas `pare` e o limite; não há pontuação, quebra de linha
   ou EOS alternativo.
7. **Ciclos possíveis com outros estados.** O limite garante terminação, mas não
   garante progresso semântico.
8. **Estado não validado no núcleo.** `gerador_gerar` assume o contrato da §4.1;
   apenas o wrapper imprime erros.
9. **Sem qualidade de linguagem.** A saída é o comportamento de uma camada afim
   treinada em 4 pares, não um modelo de linguagem.

## 14. Decisões registradas

| ID | Decisão |
| --- | --- |
| D1 | gerador reutiliza `treino_argmax`; não duplica o forward |
| D2 | caminho inteiro (`Z256`); nenhum `real` na geração |
| D3 | seleção por `argmax` com desempate pelo menor `y` |
| D4 | token inicial incluído na saída, no índice 0 |
| D5 | `maximo` conta tokens, não passos; faixa `1..64` |
| D6 | `pare` (24) é o token de parada e é incluído na saída |
| D7 | `PARE` tem precedência sobre `MAXIMO` quando coincidem |
| D8 | `UNK` (0) é token válido e não é parada |
| D9 | não há detecção de ciclo; o limite garante terminação |
| D10 | repetições são preservadas na saída |
| D11 | estado não é mutado; erros não escrevem no buffer |
| D12 | texto é projeção impressa dos IDs, não detokenização inversa |
| D13 | erros: `TOKEN_INVALIDO → LIMITE_INVALIDO → PARAMETROS_INVALIDOS` |
| D14 | prefixos `gerador_`/`GERADOR_`; módulo depende só da M5 |
| D15 | nenhum commit, push, tag ou operação remota |

## Apêndice A — Mapas de transição

Estado canônico (`treino_inicializar`, idêntico à M4):

```
0→0   1→11  2→19  3→19  4→24  5→11  6→1   7→19  8→2
9→10  10→11 11→19 12→19 13→6  14→11 15→11 16→19 17→23
18→10 19→11 20→19 21→19 22→6  23→0  24→11
```

Estado treinado (5 épocas da M5, `HISTORICO=... 27804`):

```
0→24  1→24  2→13  3→13  4→14  5→24  6→24  7→13  8→16
9→12  10→24 11→13 12→13 13→14 14→24 15→24 16→13 17→16
18→12 19→24 20→13 21→13 22→14 23→24 24→24
```

Cadeias canônicas:

```
9  → 9 10 11 19 11 19 ...   (ciclo 11↔19 após 10)
19 → 19 11 19 11 ...        (ciclo 11↔19)
0  → 0 0 0 ...              (auto-ciclo)
```

Cadeias treinadas (até `pare`):

```
0  → 0 24
1  → 1 24
2  → 2 13 14 24
3  → 3 13 14 24
4  → 4 14 24
5  → 5 24
6  → 6 24
7  → 7 13 14 24
8  → 8 16 13 14 24
9  → 9 12 13 14 24
10 → 10 24
11 → 11 13 14 24
12 → 12 13 14 24
13 → 13 14 24
14 → 14 24
15 → 15 24
16 → 16 13 14 24
17 → 17 16 13 14 24
18 → 18 12 13 14 24
19 → 19 24
20 → 20 13 14 24
21 → 21 13 14 24
22 → 22 14 24
23 → 23 24
24 → 24
```

## Apêndice B — Exemplo trabalhado (semente 9, estado treinado)

Token 9 (`se`):

```
e16(9,·) = (15, -14, -11, -8)
Z256(9,12) = 259     (maior; margem 231 sobre o segundo)
```

O `argmax` devolve 12; 12 é escrito em `saida[1]`. O laço repete com 12:

```
12 → 13   (margem 194)
13 → 14   (margem 207)
14 → 24   (margem 212)
```

Ao escrever 24, o próximo teste do laço vê `pare` e encerra. Resultado:

```
GERADO=9 12 13 14 24
N=5
PASSOS=4
PARADA=PARE
TEXTO=se faca para ate pare
```

Observe que a cadeia não "continua" depois de `24`: o token de parada não é
realimentado.

## Apêndice C — Vocabulário e texto

| ID | Texto | ID | Texto | ID | Texto |
| ---: | --- | ---: | --- | ---: | --- |
| 0 | `UNK` | 9 | `se` | 18 | `leia` |
| 1 | `programa` | 10 | `senao` | 19 | `e` |
| 2 | `funcao` | 11 | `enquanto` | 20 | `ou` |
| 3 | `inicio` | 12 | `faca` | 21 | `nao` |
| 4 | `inteiro` | 13 | `para` | 22 | `verdadeiro` |
| 5 | `real` | 14 | `ate` | 23 | `falso` |
| 6 | `logico` | 15 | `passo` | 24 | `pare` |
| 7 | `cadeia` | 16 | `retorne` | | |
| 8 | `vazio` | 17 | `escreva` | | |

A reconstrução é literal e sem separadores além de um espaço. Exemplos:

| IDs | `TEXTO` |
| --- | --- |
| `9` | `se` |
| `0` | `UNK` |
| `9 12 13 14 24` | `se faca para ate pare` |
| `19 11` | `e enquanto` |
| `0 0` | `UNK UNK` |
| vazio | vazio |
