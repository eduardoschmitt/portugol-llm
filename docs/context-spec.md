# Especificação — Contexto de múltiplos tokens (M7)

- **Versão:** 1.0.0 (congelada em E0; nenhum gate disparou)
- **Status:** implementada e verificada (**PRONTA**). E0–E7 executadas em
  2026-10-27; o contrato normativo não foi alterado. Evidências em §11.5.
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0), M5
  (`docs/training-spec.md` v1.0.0), M6 (`docs/generation-spec.md` v1.0.0).
- **Plano de execução:** `docs/context-plan.md`.
- **Fora de escopo:** Transformer, atenção, redes recorrentes, memória externa,
  softmax, amostragem, temperatura, top-k, top-p, beam search, dependências
  externas, aleatoriedade, embeddings treináveis, detokenização inversa, commit
  e push.

## 1. Contrato

Esta missão define **um** modelo linear mínimo que prevê o próximo token a
partir dos **três últimos tokens** da sequência, preservando o caminho inteiro,
determinístico e verificável byte a byte das missões anteriores.

O contrato é:

1. representar um contexto de até `K = 3` tokens como a concatenação dos
   embeddings dos três últimos tokens, com preenchimento à esquerda quando a
   sequência tem menos de três tokens;
2. calcular 25 logits com **uma única camada afim** de 12 entradas para 25
   saídas, sem camada oculta, ativação, normalização ou softmax;
3. treinar **somente** os 300 pesos e 25 vieses dessa camada; os embeddings da
   M3 permanecem congelados;
4. reduzir uma perda escalar mensurável no conjunto contextual fixo;
5. provar que a redução decorre de mudança dirigida dos parâmetros e que o
   modelo usa os tokens anteriores, não apenas o último;
6. gerar tokens autoregressivamente a partir de um prefixo de 1 a 3 tokens,
   parando em `pare` (24) ou no limite de tokens;
7. ser determinístico: duas execuções independentes produzem os mesmos bytes;
8. não alterar nenhum módulo, script, teste ou contrato das missões M1–M6.

### 1.1 O que esta missão entrega

A missão entrega:

- `docs/context-spec.md` (este documento);
- `docs/context-plan.md`;
- `src/contexto.por` (fragmento novo);
- `scripts/build-context-tests.ps1` (novo);
- `scripts/verify-context-bytes.ps1` (novo);
- um bloco aditivo de 24 linhas em `scripts/test.ps1`;
- a atualização documental de status e evidências nos dois documentos.

Nenhum arquivo de M1–M6 foi modificado.

### 1.2 O que "contexto" prova e não prova

| Conceito | O que é | O que não é |
| --- | --- | --- |
| Contexto de 3 tokens | concatenação posicional de três vetores de 4 dimensões | atenção, memória de longo prazo ou compreensão sintática |
| Modelo contextual | uma camada afim `12 → 25` sobre essa concatenação | rede profunda, recorrente ou Transformer |
| Aprendizado | ajuste de 325 parâmetros em 6 exemplos sintéticos fixos | treinamento de um LLM ou generalização linguística |
| Ordem | posições distintas no vetor de 12 entradas | permutação aprendida ou atenção a posições |
| Geração | realimentação determinística do token previsto | amostragem, temperatura ou busca |

A demonstração prova que o modelo **usa** os três últimos tokens e **distingue**
ordens no conjunto fixo. Ela não prova que o modelo aprendeu Portugol, sintaxe,
semântica ou que generaliza para sequências fora do conjunto.

### 1.3 Critério de "aprendeu"

Executar sem erro não é evidência. A evidência mínima é o conjunto:

| Evidência | Medida |
| --- | --- |
| perda cai | `S0 = 6.728.768` → `S7 = 153.027` (−97,7258%) |
| acurácia sobe | `0/6` → `4/6` (época 1) → `5/6` (época 2) → `6/6` (época 6) |
| parâmetros mudam | `249/300` pesos e `24/25` vieses |
| mudança é dirigida | o logit do alvo cresce nos seis exemplos e vira o máximo, com margem ≥ 142 |
| contexto é usado | ablação "somente último token": `1/6`; modelo completo: `6/6` |
| ordem é necessária | qualquer função invariante à ordem atinge no máximo `2/6`; o modelo atinge `6/6` |
| determinismo | dois processos independentes, saída idêntica |
| não regressão | 84 testes anteriores + 16 novos = 100/100 |

Os valores acima foram derivados nesta fase por duas implementações exatas
independentes (inteiro e racional) e devem ser reproduzidos em E0–E4. Se não
forem, o gate correspondente dispara; nenhum valor será ajustado para "fazer
passar".

## 2. Análise arquitetural

### 2.1 Alternativas mínimas

Foram comparadas três formas de incorporar os últimos `K` tokens a uma camada
afim, sem atenção, recorrência, dependências externas ou aleatoriedade.

#### 2.1.1 Média dos embeddings

```
c_d = (1/K) · Σ_{k=0..K−1} e(id_k, d)
logit(y) = b[y] + Σ_d W[y][d] · c_d
```

Vantagem: entrada de 4 dimensões, 125 parâmetros, mesmo formato da M4/M5.

Problema decisivo: a soma é comutativa. Para qualquer permutação dos mesmos
`K` tokens, `c` é idêntico. Logo o modelo **não consegue** distinguir
`(9,12,13)` de `(12,9,13)` nem de `(13,12,9)`, que é um requisito obrigatório.
Uma não linearidade posterior também não resolve, pois a entrada já é invariante.

Veredito: **rejeitada**.

#### 2.1.2 Representação ponderada pela posição

```
c_d = Σ_{k=0..K−1} α_k · e(id_k, d),  α = (1, 2, 3) fixo
logit(y) = b[y] + Σ_d W[y][d] · c_d
```

Vantagem: é sensível à ordem, mantém 4 dimensões e 125 parâmetros.

Problemas:

1. **Colisões.** O mapa de uma tripla para 4 dimensões não é injetivo. Duas
   sequências diferentes podem produzir o mesmo `c`, tornando a distinção
   impossível para o modelo.
2. **Capacidade amarrada.** A contribuição da posição `k` é `α_k · W[y][d]`;
   as três posições compartilham a mesma matriz, apenas escalada. É uma
   concatenação de posto 1, não uma camada posicional completa.
3. **Faixa.** Com `α = (1,2,3)`, `|c16| ≤ 6·16 = 96`. Com `|W16| ≤ 12`,
   `|Z256| ≤ 4·12·96 + 16·12 = 4.800`, `|δ256| ≤ 5.056` e
   `S ≤ 25·6·5.056² = 3.834.470.400`, que **excede** o limite de 32 bits
   assinado (`2.147.483.647`). Para caber, seria preciso baixar o limite de
   parâmetros para 8 ou reduzir o conjunto para 3 exemplos, alterando contratos
   já provados.

Veredito: **rejeitada** nesta missão. Fica registrada como alternativa, não como
plano B.

#### 2.1.3 Concatenação dos embeddings

```
c[k*4 + d] = e(id_k, d),  k = 0,1,2 (mais antigo → mais recente)
logit(y) = b[y] + Σ_{p=0..11} W[y][p] · c[p]
```

Vantagens:

1. É sensível à ordem e **injetiva**: como as 25 linhas de embedding são
   distintas, a concatenação identifica a tripla ordem por ordem (§4.5).
2. Usa exatamente a mesma aritmética inteira da M4/M5, apenas com 12 colunas
   em vez de 4.
3. Permite inicializar as duas primeiras fatias com zero e a última com os
   parâmetros canônicos da M5. Nesse estado, o modelo é **exatamente** a M6
   para contextos de um token (§5.3), o que dá uma regressão forte.
4. O custo é 300 multiplicações por token (12 por logit), ainda trivial.
5. Cabe no interpretador com um único vetor `w16[300]`, sem arrays
   bidimensionais.

Veredito: **escolhida**.

### 2.2 Comparação consolidada

| Critério | Média | Ponderada por posição | Concatenação |
| --- | --- | --- | --- |
| Distingue ordem | **não** | sim | **sim, sempre** |
| Injetiva na tripla | não | não | **sim** |
| Dimensão de entrada | 4 | 4 | **12** |
| Pesos + vieses | 125 | 125 | **325** |
| Multiplicações por token | 100 | 100 (+12 de contexto) | **300** |
| Estado de pesos | `w16[100]` | `w16[100]` | **`w16[300]`** |
| Faixa com `|W|≤12`, `N=6` | cabe | **estoura 32 bits** | **cabe** |
| Compatibilidade exata com M6 | não (ordem perdida) | não (escala/viés) | **sim, com fatias 0/1 zeradas** |
| Complexidade em Portugol | baixa | baixa/média | **baixa** |
| Veredito | rejeitada | rejeitada | **escolhida** |

### 2.3 O que o modelo não é

- Não é um Transformer, não tem atenção, não tem recorrência, não tem memória
  além dos três últimos tokens.
- Não tem camada oculta, ativação, normalização, dropout ou softmax.
- Não tem embeddings treináveis; a M3 permanece congelada.
- Não usa `real` no caminho de treinamento, geração ou perda.
- Não usa bibliotecas, tempo, teclado, arquivos ou aleatoriedade.
- Não é um LLM treinado; é um experimento linear controlado sobre 6 exemplos
  sintéticos.

## 3. Estado, layout e invariantes

### 3.1 Arrays

| Nome | Tipo | Tamanho | Índice | Papel |
| --- | --- | --- | --- | --- |
| `w16` | `inteiro` | 300 | `y*12 + k*4 + d` | pesos em 1/16 |
| `b16` | `inteiro` | 25 | `y` | vieses em 1/16 |
| `c16` | `inteiro` | 12 | `k*4 + d` | contexto em 1/16 |
| `entradas` | `inteiro` | 18 | `n*3 + k` | 6 exemplos × 3 tokens |
| `alvos` | `inteiro` | 6 | `n` | alvos dos 6 exemplos |
| `historico` | `inteiro` | ≥ 33 | `e` | `S` após cada época |
| `saida` | `inteiro` | 64 | `i` | prefixo + tokens gerados |
| `historico_seq` | `inteiro` | 64 | `i` | sequência usada na geração |

O layout é linear, sem arrays bidimensionais, seguindo o padrão já comprovado
nas M1/M3/M4/M5.

### 3.2 Constantes

Todas literais (o interpretador rejeita `const` com expressão — M3, P9b):

```
CTX_K = 3
CTX_TAM_VOCAB = 25
CTX_DIM = 4
CTX_ENTRADAS = 12
CTX_TOTAL_W = 300
CTX_TOTAL_B = 25
CTX_PARAMS = 325
CTX_MAX_EXEMPLOS = 6
CTX_MAX_EPOCAS = 32
CTX_GRADE = 16
CTX_ESCALA_PERDA = 131072
CTX_LIMITE = 16
CTX_TAXA_NUM = 1
CTX_TAXA_DEN = 8
CTX_DIV_W = 2048
CTX_DIV_B = 128
CTX_EPOCAS = 7
CTX_TOKENS_MAX = 64
```

`CTX_ENTRADAS = 12 = CTX_K · CTX_DIM`.
`CTX_TOTAL_W = 300 = 25 · 12`.
`CTX_PARAMS = 325 = 300 + 25`.
`CTX_ESCALA_PERDA = 131072 = 2 · 65536`; a perda é
`L = S / (CTX_ESCALA_PERDA · N)`.

### 3.3 Invariantes e prova de faixa

| ID | Invariante |
| --- | --- |
| I1 | `CTX_K · CTX_DIM == CTX_ENTRADAS == 12` |
| I2 | `25 · CTX_ENTRADAS == CTX_TOTAL_W == 300` |
| I3 | `CTX_TOTAL_W + 25 == CTX_PARAMS == 325` |
| I4 | `w16` tem 300 posições; `b16`, 25; `c16`, 12 |
| I5 | nenhuma leitura/escrita fora de `0..299`, `0..24` ou `0..11` |
| I6 | `ctx_inicializar` não lê estado anterior (idempotente) |
| I7 | forward, argmax, perda, acurácia, contexto e geração não mutam `w16`/`b16` |
| I8 | erros de validação 1–4 não mutam o estado |
| I9 | `|W16| ≤ 16` e `|b16| ≤ 16` em estado válido |
| I10 | `|S| ≤ 1.926.758.400 < 2.147.483.647` |

Prova de I10, para `N ≤ 6`, `|W16| ≤ 16`, `|b16| ≤ 16`, `|c16| ≤ 16`:

```
|Z256| ≤ 12·16·16 + 16·16 = 3.328
|δ256| ≤ |Z256| + 256      = 3.584
S      ≤ 25·6·3.584²       = 1.926.758.400
```

A atualização também cabe em 32 bits:

```
|2048·W16| + |δ256·c16| ≤ 2048·16 + 3.584·16 = 32.768 + 57.344 = 90.112
|128·b16|  + |δ256|      ≤ 128·16 + 3.584   = 2.048 + 3.584   = 5.632
```

Nenhuma dessas operações depende de `real`; todos os valores são inteiros.

### 3.4 Acoplamento com M3/M4/M5/M6

- `CTX_DIM` **deve** ser igual a `EMB_DIM = 4` e a `REDE_ENTRADAS = 4`.
- `ctx_e16(id,d)` **deve** ser igual a `treino_emb16(id,d)` e a
  `emb_obter(w,id,d) · 16` para os 100 pares.
- A fatia `k=2` de `w16` tem o mesmo layout de `w16` da M5: `y*4 + d`. Com as
  fatias 0 e 1 zeradas, o forward é idêntico ao da M5/M6 para o último token.
- O gerador da M6 (`src/gerador.por`) **não** é alterado. O gerador contextual
  é uma função nova, `ctx_gerar`, que generaliza a M6 para prefixos de 1 a 3
  tokens.
- A composição é feita pelo driver de teste, não por `inclua` entre fragmentos.
  `src/contexto.por` não inclui bibliotecas e não chama funções de M1–M6.

## 4. Representação do contexto

### 4.1 Janela e ordem

`K = 3`. Para uma sequência `s[0..n−1]` com `n ≥ 1`, o contexto usado para
prever `s[n]` é:

```
se n >= K:
    tokens = s[n−K .. n−1]          // os três mais recentes, em ordem
senão:
    tokens = [PAD]·(K−n) + s[0..n−1] // preenchimento à esquerda
```

A posição `k = 0` é a mais antiga e `k = K−1 = 2` é a mais recente. O último
token está **sempre** em `k=2`. O preenchimento é o vetor zero de 4 posições,
não o token 0 (`UNK`).

### 4.2 Embedding

A fórmula é a da M3, em unidades de 1/16:

```
e16(id,d) = (((id·7 + d·3) mod 32) − 16)     id ∈ 0..24, d ∈ 0..3
```

O valor real correspondente é `e16/16`. A fórmula é duplicada em
`src/contexto.por` (como a M5 já duplica a M3); a igualdade é testada em
`ctx_composicao`.

### 4.3 Vetor de contexto

```
c16[k*4 + d] = e16(tokens[k], d)   se tokens[k] != PAD
c16[k*4 + d] = 0                   se tokens[k] == PAD
```

Exemplos canônicos:

| sequência | `c16` |
| --- | --- |
| `[13]` | `0 0 0 0 0 0 0 0 11 14 -15 -12` |
| `[9,13]` | `0 0 0 0 15 -14 -11 -8 11 14 -15 -12` |
| `[9,12,13]` | `15 -14 -11 -8 4 7 10 13 11 14 -15 -12` |
| `[12,9,12,13]` | `15 -14 -11 -8 4 7 10 13 11 14 -15 -12` |
| `[1,2,3,4,5]` | `5 8 11 14 12 15 -14 -11 -13 -10 -7 -4` |

As duas últimas linhas mostram que uma sequência longa usa apenas os três
últimos tokens: `[12,9,12,13]` e `[9,12,13]` produzem o mesmo contexto.

### 4.4 Prova de injetividade e de ordem

Suponha duas triplas `(a0,a1,a2)` e `(b0,b1,b2)` com o mesmo vetor de contexto.
Então, para cada `k` e `d`, `e16(a_k,d) = e16(b_k,d)`. Em particular, as linhas
de embedding são iguais. Pela prova da M3 (§4), se duas linhas `a` e `b` são
iguais, então `7(a−b) ≡ 0 (mod 32)`; como `mdc(7,32)=1`, `a ≡ b (mod 32)`; com
`a,b ∈ 0..24`, `a = b`. Logo `a_k = b_k` para cada `k`, e a tripla é idêntica.

Consequência: a concatenação **nunca** confunde duas triplas distintas, em
particular as quatro permutações de `{9,12,13}`. A ordem é representada
explicitamente pelas posições.

### 4.5 Preenchimento não colide com `UNK`

Nenhuma linha de embedding é o vetor zero. Se `e16(id,d)=0` para todo `d`,
então em particular `e16(id,0)=e16(id,1)`, o que exigiria `3 ≡ 0 (mod 32)`,
falso. Logo o vetor zero é distinto de todas as 25 linhas, e `PAD` não se
confunde com o token 0 (`UNK`). O caso `ctx_contexto_k` testa essa distinção.

### 4.6 Sequências curtas e longas

- `n = 1`: duas posições zero e o token em `k=2`.
- `n = 2`: uma posição zero e os dois tokens em `k=1,2`.
- `n = 3`: sem preenchimento.
- `n > 3`: apenas os três últimos tokens; os anteriores são descartados.
- `n = 0` não é um contexto válido para geração; o prefixo deve ter 1 a 3
  tokens.

O treinamento usa sempre exemplos completos de 3 tokens. Contextos de 1 e 2
tokens são exercitados pela construção de contexto e pela geração, não pelo
conjunto de treino. Isso é deliberado: o conjunto é mínimo e o preenchimento é
uma propriedade do forward, não um exemplo aprendido.

## 5. Inicialização determinística

### 5.1 Fórmulas

Para `y ∈ 0..24`, `k ∈ 0..2`, `d ∈ 0..3`:

```
W16[y][k][d] = 0                                  se k = 0 ou k = 1
W16[y][2][d] = (((y·7 + d·5) mod 25) − 12)        se k = 2
b16[y]       = (((y·7) mod 9) − 4)
```

É a inicialização canônica da M4/M5 aplicada somente à fatia mais recente. As
duas fatias antigas começam em zero.

### 5.2 Tabela canônica inicial

Formato `PARAM16=y w0..w11 b`:

```
PARAM16=0 0 0 0 0 0 0 0 0 -12 -7 -2 3 -4
PARAM16=1 0 0 0 0 0 0 0 0 -5 0 5 10 3
PARAM16=2 0 0 0 0 0 0 0 0 2 7 12 -8 1
PARAM16=3 0 0 0 0 0 0 0 0 9 -11 -6 -1 -1
PARAM16=4 0 0 0 0 0 0 0 0 -9 -4 1 6 -3
PARAM16=5 0 0 0 0 0 0 0 0 -2 3 8 -12 4
PARAM16=6 0 0 0 0 0 0 0 0 5 10 -10 -5 2
PARAM16=7 0 0 0 0 0 0 0 0 12 -8 -3 2 0
PARAM16=8 0 0 0 0 0 0 0 0 -6 -1 4 9 -2
PARAM16=9 0 0 0 0 0 0 0 0 1 6 11 -9 -4
PARAM16=10 0 0 0 0 0 0 0 0 8 -12 -7 -2 3
PARAM16=11 0 0 0 0 0 0 0 0 -10 -5 0 5 1
PARAM16=12 0 0 0 0 0 0 0 0 -3 2 7 12 -1
PARAM16=13 0 0 0 0 0 0 0 0 4 9 -11 -6 -3
PARAM16=14 0 0 0 0 0 0 0 0 11 -9 -4 1 4
PARAM16=15 0 0 0 0 0 0 0 0 -7 -2 3 8 2
PARAM16=16 0 0 0 0 0 0 0 0 0 5 10 -10 0
PARAM16=17 0 0 0 0 0 0 0 0 7 12 -8 -3 -2
PARAM16=18 0 0 0 0 0 0 0 0 -11 -6 -1 4 -4
PARAM16=19 0 0 0 0 0 0 0 0 -4 1 6 11 3
PARAM16=20 0 0 0 0 0 0 0 0 3 8 -12 -7 1
PARAM16=21 0 0 0 0 0 0 0 0 10 -10 -5 0 -1
PARAM16=22 0 0 0 0 0 0 0 0 -8 -3 2 7 -3
PARAM16=23 0 0 0 0 0 0 0 0 -1 4 9 -11 4
PARAM16=24 0 0 0 0 0 0 0 0 6 11 -9 -4 2
MAXIMO16=12 4
```

### 5.3 Propriedades

- `max |W16| = 12`, `max |b16| = 4`; o estado passa em `|v| ≤ 16`.
- As 200 posições das fatias 0 e 1 são zero; a fatia 2 contém exatamente a
  tabela canônica da M5.
- Para qualquer contexto de um token `[PAD,PAD,t]`, o forward é idêntico ao da
  M5 canônica. Logo `ctx_argmax` reproduz `treino_argmax` da M5 para os 25
  tokens. O mapa inicial é:

  ```
  0 11 19 19 24 11 1 19 2 10 11 19 19 6 11 11 19 23 10 11 19 19 6 0 11
  ```

  (índice `t = 0..24`; por exemplo, `t=9 → 10`, `t=12 → 19`, `t=13 → 6`,
  `t=14 → 11`).
- As predições iniciais nos seis exemplos são `6 11 6 19 10 6` (0/6), que são
  exatamente as predições da M5 canônica para os últimos tokens
  `13, 14, 13, 12, 9, 13`.
- A inicialização não lê estado anterior; `ctx_inicializar` é a única forma de
  reinicializar.

## 6. Forward e perda

### 6.1 Fórmula normativa

Para um contexto `c16[0..11]`, `y ∈ 0..24`:

```
Z256(c,y) = Σ_{p=0..11} W16[y][p] · c16[p] + 16 · b16[y]
```

Ordem de acumulação obrigatória: `p = 0,1,...,11`, soma começando em `0`, viés
por último. É a mesma ordem da M4/M5, estendida de 4 para 12 posições.

O logit real correspondente é `z = Z256/256`.

### 6.2 Prova de exatidão

`W16`, `c16` e `b16` são inteiros. Logo `Z256` é inteiro e `z` é um múltiplo
exato de `1/256`. Cada produto `W16·c16` é um inteiro; a soma de 12 produtos
mais `16·b16` é inteira. Não há divisão, arredondamento binário, `-0.0`, `NaN`
ou dependência de locale no caminho quente.

A faixa máxima em estado válido é `|Z256| ≤ 3.328` (§3.3), muito abaixo de
32 bits. A ordenação de `Z256` é idêntica à de `z`, pois a escala `1/256` é
positiva.

### 6.3 Argmax e empates

```
melhor = 0
melhor_valor = Z256(c, 0)
para y = 1..24:
    se Z256(c, y) > melhor_valor:
        melhor_valor = Z256(c, y)
        melhor = y
retorne melhor
```

Comparação estrita; empate fica com o menor `y`. É a mesma regra da M4/M5/M6.

### 6.4 Perda

```
δ256(n,y) = Z256(c_n, y) − 256·(1 se y = alvo[n], senão 0)
S          = Σ_{n=0..N−1} Σ_{y=0..24} δ256(n,y)²
L          = S / (131072 · N)
```

`S` é o valor observável (inteiro). `L` é derivado e não precisa ser impresso.
Para o conjunto canônico, `N = 6`:

```
L0 = 6.728.768 / 786.432 = 8,556070963541666...
L7 = 153.027 / 786.432   = 0,19458389282226562...
```

### 6.5 Duas derivações independentes

Nesta fase, os valores canônicos foram calculados por:

1. uma implementação **inteira** (`W16`, `b16`, `c16`, `Z256`, `δ256`, `r`);
2. uma implementação **racional exata** (`fractions.Fraction`, estado em
   `1/16`, atualização e quantização em racionais).

As duas produziram a mesma trajetória `S0..S7`, a mesma tabela final de 325
parâmetros, as mesmas predições e as mesmas margens. A implementação em
Portuguol será uma terceira derivação; o verificador, uma quarta.

## 7. Treinamento

### 7.1 Taxa de aprendizado

SGD **por exemplo** (online), na ordem fixa `n = 0..5`, com `η = 1/8`.

A escolha foi feita por varredura exata na mesma inicialização, 8 épocas,
`N = 6`:

| `η` | `S7` | acurácia | observação |
| --- | ---: | ---: | --- |
| 1/32 | 3.922.207 | 0/6 | não converge |
| 1/16 | 1.011.222 | 6/6 | converge, mas platô pior |
| **1/8** | **153.027** | **6/6** | **estrito até o ponto fixo** |
| 1/4 | 521.726 | 6/6 | não monotônica (`850.532 → 875.548`) |
| 1/2 | — | 0/6 | estoura o limite já na 1ª época |

Critério: maior taxa potência de dois que (a) decresce estritamente em todas as
épocas até o ponto fixo, (b) atinge `6/6` e (c) mantém `|W16|,|b16| ≤ 16`.
`η = 1/8` é a única que satisfaz as três.

### 7.2 Equações de atualização

Forma real (para leitura):

```
δ(n,y) = z(c_n,y) − t(n,y)
W[y][p] ← quantiza16( W[y][p] − (1/8)·δ(n,y)·c_n[p] )
b[y]    ← quantiza16( b[y]    − (1/8)·δ(n,y) )
```

Forma inteira (normativa, sem `real`):

```
r(num, den) = sinal(num) · ⌊ (|num| + den/2) / den ⌋      den ∈ {2048, 128}

W16[y][p] ← r( 2048·W16[y][p] − δ256(n,y)·c_n[p], 2048 )
b16[y]    ← r(  128·b16[y]    − δ256(n,y),          128 )
```

Derivação:

```
16·(W − ηδc) = W16 − 16·(1/8)·(δ256/256)·(c16/16) = W16 − δ256·c16/2048
16·(b − ηδ)  = b16 − 16·(1/8)·(δ256/256)          = b16 − δ256/128
```

A quantização é "meio para longe de zero", como na M5. Para posições de
preenchimento, `c_n[p] = 0`, logo a atualização de `W16[y][p]` é a identidade
(`r(2048·W16,2048) = W16`); o preenchimento não altera pesos.

### 7.3 Ordem interna obrigatória

Para cada exemplo `n`:

1. calcular e **congelar** os 25 valores `δ256(n,y)` a partir do estado
   corrente;
2. para `y = 0..24`, atualizar os 12 `W16[y][*]` e depois `b16[y]`, usando o
   `δ256(n,y)` congelado;
3. verificar `|v| ≤ 16` após cada escrita; se violar, retornar
   `ESTOURO_NUMERICO`.

O congelamento é obrigatório: recalcular `δ256` depois de atualizar
`W16[y][0]` produz outro resultado. Como cada linha `y` só depende de si
mesma, a ordem das linhas é equivalente; a ordem dos exemplos e a quantização
por parâmetro não são.

### 7.4 Ponto fixo

Após 7 épocas, uma 8ª época não altera nenhum dos 325 parâmetros
(`MUDOU_W=0`, `MUDOU_B=0`) e `S7 = S8 = 153.027`. O estado é um ponto fixo da
atualização quantizada. Isso não é divergência nem parada por limite: é a
consequência de `η = 1/8` com passo menor que meio quantum em todos os
parâmetros.

A trajetória é estritamente decrescente até o ponto fixo:

```
S0..S7 = 6.728.768  465.936  282.923  216.490  193.677  183.943  167.288  153.027
```

### 7.5 Épocas

`CTX_EPOCAS = 7` é o menor `E` com `S_E = S_{E+1}` e nenhuma mudança de
parâmetro na época seguinte. `E = 6` ainda reduz (`167.288 → 153.027`); `E = 8`
não muda nada e só gasta tempo. O parâmetro `epocas` permite outros valores em
teste (1..32).

### 7.6 Evidência de mudança dirigida

| exemplo | `Z256` do alvo (época 0 → 7) | margem final sobre o 2º | contribuição `S` (0 → 7) |
| --- | --- | ---: | --- |
| 9,12,13 → 14 | `107 → 193` | 142 | `1.569.094 → 26.593` |
| 12,13,14 → 24 | `−81 → 199` | 151 | `366.618 → 25.296` |
| 12,9,13 → 10 | `97 → 205` | 156 | `1.574.214 → 18.458` |
| 9,13,12 → 24 | `−9 → 235` | 174 | `364.278 → 30.261` |
| 13,12,9 → 11 | `−104 → 264` | 201 | `1.217.374 → 30.217` |
| 14,12,13 → 9 | `−26 → 206` | 167 | `1.637.190 → 22.202` |

O logit do alvo cresce nos seis casos e o alvo vira o máximo com margem ≥ 142
(em unidades de 1/256). Isso é evidência de direção correta, não apenas de
queda agregada.

Alterações: **249/300** pesos e **24/25** vieses. `max |W16| = 11`,
`max |b16| = 5`; nenhum parâmetro chega perto do limite 16. Por época, o número
de pesos que mudam é `254 / 85 / 36 / 18 / 14 / 10 / 10` e o de vieses é
`24 / 9 / 6 / 0 / 2 / 1 / 1`. A 8ª época muda `0 / 0`.

### 7.7 Estado final canônico

Formato `PARAM16=y w0..w11 b`:

```
PARAM16=0 2 -2 -2 0 2 -3 0 1 -6 -1 -3 -1 -2
PARAM16=1 0 1 0 1 0 -2 2 3 -3 2 1 5 5
PARAM16=2 0 2 2 0 0 2 1 0 0 3 10 -9 2
PARAM16=3 -2 -4 2 1 0 0 -2 -2 7 -8 -4 0 -2
PARAM16=4 1 -1 -1 0 3 -2 2 2 -5 1 -4 3 -1
PARAM16=5 -1 1 1 -1 0 -1 0 0 -2 2 9 -11 2
PARAM16=6 -1 3 -2 -2 -3 2 -2 -3 1 4 -3 1 -2
PARAM16=7 0 -5 2 2 -1 1 -1 -2 8 -5 -2 2 -1
PARAM16=8 1 0 0 1 2 -1 1 2 -3 1 -1 5 1
PARAM16=9 -7 2 0 1 1 5 0 1 2 4 9 -9 2
PARAM16=10 -1 -3 2 1 0 -4 -2 -3 7 -5 -4 -1 1
PARAM16=11 2 4 -3 -3 3 -4 4 1 -3 -4 -3 3 3
PARAM16=12 1 2 2 1 1 0 2 3 -2 2 1 6 2
PARAM16=13 0 1 0 -3 -2 4 -3 -2 1 4 -5 0 -5
PARAM16=14 6 -7 3 2 -4 1 4 -1 2 -1 -4 0 -2
PARAM16=15 1 1 1 0 0 -2 2 1 -4 0 -1 5 3
PARAM16=16 1 2 -1 0 0 1 0 1 0 2 11 -10 0
PARAM16=17 -1 3 -1 -1 -1 4 -1 -3 2 4 -3 2 -5
PARAM16=18 2 0 -2 -1 2 -4 1 1 -5 -1 -5 2 0
PARAM16=19 0 3 1 0 -1 -2 2 3 -2 1 2 7 5
PARAM16=20 -1 1 -3 -2 -1 2 -2 -4 1 3 -5 0 -4
PARAM16=21 -2 -5 2 3 -1 1 -3 -2 7 -6 -3 0 -2
PARAM16=22 1 0 0 0 2 -2 1 2 -5 1 -2 3 0
PARAM16=23 0 2 0 -1 -1 0 0 0 -1 2 10 -10 3
PARAM16=24 0 3 -2 -1 -1 8 -4 -5 0 2 -4 4 0
MAXIMO16=11 5
```

Predições finais: `14 24 10 24 11 9` (6/6).
Margens finais: `142 151 156 174 201 167`.

## 8. Conjunto contextual

### 8.1 Tabela

| `n` | palavras (rótulos) | `entradas[n*3..n*3+2]` | alvo | `alvos[n]` |
| ---: | --- | --- | --- | ---: |
| 0 | `se faca para` | `9 12 13` | `ate` | 14 |
| 1 | `faca para ate` | `12 13 14` | `pare` | 24 |
| 2 | `faca se para` | `12 9 13` | `senao` | 10 |
| 3 | `se para faca` | `9 13 12` | `pare` | 24 |
| 4 | `para faca se` | `13 12 9` | `enquanto` | 11 |
| 5 | `ate faca para` | `14 12 13` | `se` | 9 |

As palavras são apenas rótulos do vocabulário da M1; não há relação gramatical
entre elas. O conjunto é sintético e fixo.

### 8.2 Propriedades

- **Mesmo último token, contextos diferentes.** Os exemplos 0, 2 e 5 terminam
  em `13` e têm alvos `14`, `10` e `9`. Nenhum modelo que olhe apenas o último
  token pode acertar os três.
- **Mesmos tokens, ordens diferentes.** Os exemplos 0, 2, 3 e 4 são as quatro
  permutações de `{9,12,13}`, com alvos `14`, `10`, `24` e `11`. Um modelo
  invariante à ordem não pode acertar mais de um deles.
- **Segundo grupo de ordem.** Os exemplos 1 e 5 são permutações de
  `{12,13,14}`, com alvos `24` e `9`.
- **Cadeia de geração.** `9,12,13 → 14` e `12,13,14 → 24`; a partir do prefixo
  `9 12 13`, o modelo gera `14` e depois `24`, parando em `pare`.
- **Sem conflito.** Não há duas linhas com a mesma tripla e alvos diferentes.
- **Não é cópia.** Em nenhum exemplo o alvo é igual ao último token.

### 8.3 Impossibilidade para modelos mais simples

Limite superior para qualquer função que dependa **somente do último token**:
os grupos são `13 → {14,10,9}`, `14 → {24}`, `12 → {24}`, `9 → {11}`. O melhor
possível é `1 + 1 + 1 + 1 = 4/6`.

Limite superior para qualquer função **invariante à ordem** (média, soma,
bag-of-tokens): os grupos de multiconjunto são `{9,12,13} → {14,10,24,11}` e
`{12,13,14} → {24,9}`. O melhor possível é `1 + 1 = 2/6`.

O modelo completo atinge `6/6`. A diferença não é estatística: é uma
consequência combinatória do conjunto.

### 8.4 Ablações

| Modelo | Acurácia | `S` | Predições |
| --- | ---: | ---: | --- |
| M7 completo | **6/6** | 153.027 | `14 24 10 24 11 9` |
| Somente último token (fatias 0/1 zeradas) | 1/6 | 916.888 | `10 11 10 19 10 10` |
| Somente tokens antigos (fatia 2 zerada) | 6/6 | 717.503 | `14 24 10 24 11 9` |
| Qualquer função só do último token | ≤ 4/6 | — | — |
| Qualquer função invariante à ordem | ≤ 2/6 | — | — |

A ablação "somente tokens antigos" também acerta o conjunto porque, neste
conjunto específico, os dois primeiros tokens são únicos. Isso **não** enfraquece
a demonstração: a ablação decisiva é "somente último token" (1/6), que isola o
comportamento da M6 e mostra que o contexto é necessário. A arquitetura, por
construção, usa as três posições; o conjunto não foi escolhido para forçar cada
posição individualmente.

### 8.5 Por que este conjunto é mínimo

- 6 exemplos, o máximo permitido pela prova de faixa com `|W| ≤ 16`.
- 2 exemplos formam a cadeia de geração.
- 4 exemplos formam o grupo de ordem `{9,12,13}`.
- 1 exemplo adicional (`14,12,13 → 9`) fecha o grupo de mesmo último token.
- Os alvos usam 5 IDs distintos (`9,10,11,14,24`), sem colisão com o último
  token.
- O conjunto não foi ajustado depois de ver o resultado; os valores canônicos
  foram derivados das fórmulas antes de qualquer implementação em Portugol.

## 9. Geração contextual

### 9.1 API

```
funcao inteiro ctx_gerar(inteiro w16[], inteiro b16[],
                         inteiro prefixo[], inteiro n_prefixo,
                         inteiro maximo, inteiro saida[])
```

- Valida `prefixo` (1..3 IDs em 0..24, `pare` somente na última posição),
  `maximo` (1..64 e `maximo >= n_prefixo`) e os parâmetros (`|v| ≤ 16`), nesta
  precedência.
- Copia o prefixo para `saida[0..n_prefixo−1]`.
- Se o último token do prefixo é `pare` (24), para imediatamente com
  `PASSOS=0`, `PARADA=PARE`.
- Caso contrário, enquanto `n_atual < maximo`:
  1. monta o contexto dos três últimos tokens de `saida` (com preenchimento à
     esquerda se `n_atual < 3`);
  2. calcula `proximo = ctx_argmax(w16,b16,c16)`;
  3. grava `saida[n_atual] = proximo`; `n_atual = n_atual + 1`;
  4. se `proximo == 24`, para com `PARADA=PARE`.
- Se o limite for atingido sem `pare`, `PARADA=MAXIMO`.
- `N = n_atual`, `PASSOS = N − n_prefixo`.

### 9.2 Preenchimento e janela

O prefixo pode ter 1, 2 ou 3 tokens. Para `n_prefixo = 1`, o primeiro passo usa
`[PAD,PAD,t]`; para `n_prefixo = 2`, usa `[PAD,t0,t1]`; para `n_prefixo = 3`,
usa `[t0,t1,t2]`. Depois do primeiro passo, a janela desliza normalmente.

O limite `maximo` conta o prefixo e os tokens gerados, igual à M6. Se
`maximo == n_prefixo`, nenhum token é gerado (`PASSOS=0`, `PARADA=MAXIMO`),
exceto se o último token do prefixo é 24 (`PARADA=PARE`, precedência).

### 9.3 Política de parada

- `pare` (24) tem precedência sobre `MAXIMO`.
- `UNK` (0) é token válido, não é parada.
- Não há detecção de ciclo; o limite garante terminação.
- Repetições são preservadas.
- O gerador não altera `w16`/`b16`; em erro, não escreve em `saida`.

### 9.4 Saídas canônicas

Com o estado treinado de §7.7:

| prefixo | `maximo` | `GERADO` | `N` | `PASSOS` | `PARADA` |
| --- | ---: | --- | ---: | ---: | --- |
| `9 12 13` | 64 | `9 12 13 14 24` | 5 | 2 | `PARE` |
| `9 12 13` | 4 | `9 12 13 14` | 4 | 1 | `MAXIMO` |
| `9 12 13` | 3 | `9 12 13` | 3 | 0 | `MAXIMO` |
| `9` | 10 | `9 10 11 14 11 19 11 19 11 19` | 10 | 9 | `MAXIMO` |
| `24` | 64 | `24` | 1 | 0 | `PARE` |
| `12 24` | 64 | `12 24` | 2 | 0 | `PARE` |
| `9` | 64 | 64 tokens; após `14`, ciclo `11 19` | 64 | 63 | `MAXIMO` |

Textos correspondentes (tabela da M1/M6):

- `9 12 13 14 24` → `se faca para ate pare`
- `9 12 13 14` → `se faca para ate`
- `9 10 11 14 11 19 11 19 11 19` → `se senao enquanto ate enquanto e enquanto e enquanto e`
- `24` → `pare`
- `12 24` → `faca pare`

### 9.5 Integração com a M6

O gerador da M6 não é alterado. A compatibilidade é demonstrada em dois níveis:

1. **Estado inicial canônico.** As fatias 0 e 1 são zero e a fatia 2 é a M5
   canônica. Para todo `t`, `ctx_argmax([PAD,PAD,t])` é igual a
   `treino_argmax` da M5 canônica. O mapa inicial está em §5.3.
2. **Estado treinado da M5 embutido.** Construa um `w16[300]` com as fatias 0 e
   1 zeradas e a fatia 2 igual à tabela final da M5 (§8.3 de
   `docs/training-spec.md`); `b16` igual aos 25 vieses finais. Esse estado passa
   em `|v| ≤ 16`. Então `ctx_gerar` com prefixo de 1 token reproduz
   `gerador_gerar` da M6 para os 25 tokens. O mapa é:

   ```
   0 24   1 24   2 13   3 13   4 14   5 24   6 24   7 13   8 16
   9 12  10 24  11 13  12 13  13 14  14 24  15 24  16 13  17 16
   18 12 19 24  20 13  21 13  22 14  23 24  24 24
   ```

   e a cadeia `9 → 12 → 13 → 14 → 24` é reproduzida.

O modelo M7 treinado não é igual à M6; ele aprendeu a usar o contexto e pode
prever diferente para o mesmo último token. A compatibilidade é uma
propriedade da construção e do estado inicial/embutido, não uma promessa de que
o M7 treinado se comporte como a M6.

## 10. API, erros, limites e formato observável

### 10.1 Validadores e funções

Todas as funções ficam em `src/contexto.por`, fragmento ASCII sem `programa`
nem `inicio`, com prefixo `ctx_`/`CTX_`. O módulo não inclui bibliotecas e não
chama funções de M1–M6.

```portugol
funcao logico ctx_id_valido(inteiro id)                         // 0..24
funcao logico ctx_n_valido(inteiro n)                           // 1..6
funcao logico ctx_epocas_validas(inteiro e)                     // 1..32
funcao logico ctx_params_validos(inteiro w16[], inteiro b16[])  // |v| <= 16
funcao logico ctx_maximo_valido(inteiro m)                      // 1..64
funcao logico ctx_prefixo_valido(inteiro p[], inteiro n)        // 1..3 ids
funcao inteiro ctx_validar(inteiro entradas[], inteiro alvos[],
                           inteiro n, inteiro epocas,
                           inteiro w16[], inteiro b16[])        // 0..4
funcao inteiro ctx_validar_geracao(inteiro w16[], inteiro b16[],
                                   inteiro p[], inteiro n,
                                   inteiro maximo)              // 0..3
```

```portugol
funcao inteiro ctx_e16(inteiro id, inteiro d)
funcao ctx_montar_contexto(inteiro historico[], inteiro n, inteiro c16[])
funcao ctx_contexto_de_exemplo(inteiro entradas[], inteiro n, inteiro c16[])
funcao inteiro ctx_z256(inteiro w16[], inteiro b16[], inteiro c16[], inteiro y)
funcao inteiro ctx_argmax(inteiro w16[], inteiro b16[], inteiro c16[])
funcao inteiro ctx_perda_escalada(inteiro w16[], inteiro b16[],
                                  inteiro entradas[], inteiro alvos[], inteiro n)
funcao inteiro ctx_acertos(inteiro w16[], inteiro b16[],
                           inteiro entradas[], inteiro alvos[], inteiro n)
funcao inteiro ctx_div_arredondada(inteiro num, inteiro den)
```

```portugol
funcao ctx_inicializar(inteiro w16[], inteiro b16[])
funcao inteiro ctx_executar(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[],
                            inteiro n, inteiro epocas,
                            inteiro historico[])
funcao inteiro ctx_gerar(inteiro w16[], inteiro b16[],
                         inteiro prefixo[], inteiro n_prefixo,
                         inteiro maximo, inteiro saida[])
```

Impressoras:

```portugol
funcao ctx_imprimir_config()
funcao ctx_imprimir_validacao(inteiro entradas[], inteiro alvos[],
                              inteiro n, inteiro epocas,
                              inteiro w16[], inteiro b16[])
funcao ctx_imprimir_avaliacao(inteiro w16[], inteiro b16[],
                              inteiro entradas[], inteiro alvos[], inteiro n)
funcao ctx_imprimir_historico(inteiro historico[], inteiro epocas)
funcao ctx_imprimir_param16(inteiro w16[], inteiro b16[], inteiro y)
funcao ctx_imprimir_estado(inteiro w16[], inteiro b16[])
funcao ctx_imprimir_alterados(inteiro w16[], inteiro b16[])
funcao ctx_imprimir_contexto(inteiro historico[], inteiro n)
funcao ctx_imprimir_geracao(inteiro saida[], inteiro n_saida,
                            inteiro n_prefixo, inteiro parada)
```

Pré-condições: os IDs, `n`, `epocas`, `y` e `maximo` são válidos; o estado está
dentro de I9. As funções puras não validam e não imprimem. As impressoras
validam antes de acessar arrays e emitem **uma única linha de erro** quando
aplicável, sem saída parcial.

### 10.2 Códigos de erro

Treinamento:

| Código | Texto | Condição |
| ---: | --- | --- |
| 0 | `VALIDO=OK` | entrada válida |
| 1 | `EXEMPLOS_INVALIDOS` | `n < 1` ou `n > 6` |
| 2 | `EPOCAS_INVALIDAS` | `epocas < 1` ou `epocas > 32` |
| 3 | `ID_INVALIDO` | `entradas` ou `alvos` fora de `0..24` |
| 4 | `PARAMETROS_INVALIDOS` | `\|W16\| > 16` ou `\|b16\| > 16` |
| 5 | `ESTOURO_NUMERICO` | atualização produziria `\|v\| > 16` |

Geração:

| Código | Texto | Condição |
| ---: | --- | --- |
| 0 | `VALIDO=OK` | prefixo, limite e parâmetros válidos |
| 1 | `PREFIXO_INVALIDO` | `n < 1`, `n > 3`, ID fora de `0..24`, ou `pare` fora da última posição |
| 2 | `MAXIMO_INVALIDO` | `maximo < 1`, `maximo > 64` ou `maximo < n_prefixo` |
| 3 | `PARAMETROS_INVALIDOS` | `\|v\| > 16` |

Impressão: `SAIDA_INVALIDA` para `y` fora de `0..24` em
`ctx_imprimir_param16`.

### 10.3 Precedência

- Treinamento: `1 → 2 → 3 → 4`; `5` só ocorre depois de `0`.
- Dentro de `3`: `entradas[0], alvos[0], entradas[1], alvos[1], ...`.
- Geração: `1 → 2 → 3`.
- `pare` fora da última posição é `1`; `maximo < n_prefixo` é `2`.

### 10.4 Estado em caso de erro

- Treinamento `1..4`: nenhuma mutação (validação antes de qualquer escrita).
- Treinamento `5`: mutação parcial possível; o chamador deve chamar
  `ctx_inicializar`.
- Geração `1..3`: nenhuma escrita em `saida` e nenhuma mutação em `w16`/`b16`.
- `SAIDA_INVALIDA`: nenhuma mutação.

### 10.5 Limites

| Limite | Valor | Justificativa |
| --- | ---: | --- |
| janela `K` | 3 | menor janela que permite o grupo de 4 permutações |
| exemplos | 1..6 | prova de faixa `S ≤ 1,926e9` |
| épocas | 1..32 | pior caso 6·32·25·12 = 57.600 multiplicações |
| parâmetros | `\|v\| ≤ 16` | prova de faixa §3.3 |
| histórico | `epocas+1` | um valor por época, mais o inicial |
| prefixo de geração | 1..3 | janela `K` |
| `maximo` | 1..64 | buffer `saida[64]` |
| multiplicações por token | 300 | 12 por logit |

Não há limite de tempo na aceitação; o custo é medido em E0 e registrado como
evidência, não como critério.

### 10.6 Gramática observável

```
INFO=CTX 3 12 325 300
TAXA=1/8
GRADE=1/16
EPOCAS=7
ESCALA_PERDA=131072
LIMITE_PARAM=16
ORDEM=EXEMPLO
PERDA=<inteiro>
ACERTOS=<0..6>
PRED=<id>[ <id>]*
HISTORICO=<inteiro>[ <inteiro>]*
PARAM16=<y> <12 inteiros> <inteiro>
MAXIMO16=<inteiro> <inteiro>
ALTERADOS_W=<inteiro>
ALTERADOS_B=<inteiro>
CTX16=<n> <12 inteiros>
GERADO=<id>[ <id>]*
N=<inteiro>
PASSOS=<inteiro>
PARADA=PARE|MAXIMO
TEXTO=<palavra>[ <palavra>]*
VALIDO=OK
ERRO=<CODIGO>
INTACTO=OK
SAIDA_INTACTA=OK
PARAMS_INTACTOS=OK
```

- Tudo é ASCII, uma linha por registro, `\n` no fim.
- `PERDA` é `S`, nunca `L` em ponto flutuante.
- `PARAM16` usa os numeradores inteiros; não há `0.1875` na saída.
- `CTX16` começa com o comprimento `n` do histórico (1..64) e imprime os 12
  inteiros do contexto.
- `GERADO` contém o prefixo e os tokens gerados; `N` é o total; `PASSOS` é
  `N − n_prefixo`.
- `TEXTO` é a projeção impressa dos IDs, com `UNK` para 0, separada por um
  espaço e sem espaço final.
- Sucesso nunca contém `ERRO=`; erro nunca contém dados de avaliação.
- Linhas de diagnóstico derivadas (`ORDEM_DISTINTOS`, `MESMO_ULTIMO`,
  `PAD_DISTINTO`, `MARGENS`, `MUDOU_W`, `MUDOU_B`, `ABL_*`, `E16_OK`, `M4_OK`,
  `M5_OK`, `M6_OK`, `M6_CADEIA`, `COMPOE`, `PARCIAL_*`) são calculadas e
  impressas pelos **drivers de teste**, não pelas impressoras do módulo. Elas
  não fazem parte da API de `src/contexto.por` e não alteram este formato.

### 10.7 Condição de congelamento

O formato e as fórmulas congelam em E0, se nenhum gate disparar. Qualquer
mudança depois disso exige incrementar a versão para `v1.1.0`, regenerar todos
os `.expected` e reexecutar a matriz completa. Nenhum valor canônico será
alterado para "fazer passar".

## 11. Oráculo, testes, aceitação e limitações

### 11.1 Oráculo independente

O oráculo não lê `.expected` nem reutiliza funções do módulo. Ele é definido
pelas fórmulas de §4–§7 e foi implementado duas vezes de forma independente
nesta fase:

1. **inteiro** (`W16`, `b16`, `c16`, `Z256`, `δ256`, `r`);
2. **racional exato** (`fractions.Fraction`, estado em `1/16`, atualização e
   quantização em racionais).

As duas concordaram em todos os valores canônicos. Na implementação:

- o builder é uma terceira derivação;
- `src/contexto.por` é a quarta;
- o verificador é uma quinta, independente do builder;
- a auditoria de E7 refaz uma sexta derivação.

Nenhuma delas decide o valor esperado lendo a saída do `.por`.

### 11.2 Matriz de testes

| Caso | Cobertura | Resultado exigido |
| --- | --- | --- |
| `ctx_init` | config, tabela inicial, avaliação inicial | `S0`, `0/6`, `PRED`, `MAXIMO16=12 4` |
| `ctx_contexto_k` | comprimentos 1..5, padding, janela | 5 linhas `CTX16` canônicas; `PAD_DISTINTO=OK` |
| `ctx_contexto_ordem` | 4 permutações, mesmo último token | 4 vetores distintos; `ORDEM_DISTINTOS=4` |
| `ctx_treino` | 7 épocas, estado, alterados, margens | `HISTORICO`, `PERDA=153027`, `ACERTOS=6`, `PRED`, `249/24` |
| `ctx_ponto_fixo` | 8ª época | `S7=S8`, `MUDOU_W=0`, `MUDOU_B=0` |
| `ctx_ablation` | último token, ordem | `ABL_FULL=6`, `ABL_ULTIMO=1`, `ABL_ULTIMO_MAX=4`, `ABL_BAG_MAX=2` |
| `ctx_geracao_cadeia` | prefixo 3, cadeia | `9 12 13 14 24`, `PARE`, texto |
| `ctx_geracao_limites` | `maximo` 3/4, `pare` no prefixo | blocos canônicos de §9.4 (o caso de 64 tokens fica em `ctx_limites`) |
| `ctx_geracao_semente` | prefixos 1 token | `[9]` e `[12]` com 10 tokens |
| `ctx_erros_treino` | códigos 1..5, precedência, estado | `ERRO`, `INTACTO=OK`, estado parcial do estouro |
| `ctx_erros_geracao` | códigos 1..3, precedência, saída | `ERRO`, `SAIDA_INTACTA=OK` |
| `ctx_determinismo_a` | execução completa | saída A |
| `ctx_determinismo_b` | execução completa | saída B = A, byte a byte |
| `ctx_composicao` | M1/M3/M4/M5/M6 | `E16_OK=100`, `M4_OK=25`, `M5_OK=25`, `M6_OK=25`, `M6_CADEIA` |
| `ctx_limites` | `n=6`, `epocas=32`, `maximo=64` | `HISTORICO` com 33 valores, 6/6, `N=64` |
| `ctx_params_intactos` | pureza | `PARAMS_INTACTOS=OK`, `SAIDA_INTACTA=OK` |

Total: **16 casos novos**; suíte **100/100**.

### 11.3 Critérios de aceitação

| AC | Comando/verificação | Resultado exigido |
| ---: | --- | --- |
| AC1 | pré-voo | `main`, `HEAD 38fc295…`, árvore limpa, 84/84 |
| AC2 | `git status --short` | somente os arquivos autorizados |
| AC3 | `scripts/test.ps1` | `Passed: 100`, `Failed: 0`, exit `0` |
| AC4 | verificadores M1–M6 | 21/21, 19/19, 22/22, 23/23, 13/13, exit `0` |
| AC5 | `scripts/test.ps1 -SelfTest` | `0 PASS / 1 FAIL`, exit `1` |
| AC6 | `scripts/verify-context-bytes.ps1` | `Checks: 16`, `Failures: 0`, exit `0` |
| AC7 | `ctx_init` | tabela de §5.2, `MAXIMO16=12 4` |
| AC8 | `ctx_contexto_k` | padding e janela de §4.3 |
| AC9 | `ctx_contexto_ordem` | 4 vetores distintos para `{9,12,13}` |
| AC10 | `ctx_treino` | `HISTORICO` de §7.4, `6/6`, `PRED=14 24 10 24 11 9` |
| AC11 | mesmo último token | `13` → `14,10,9` |
| AC12 | ordem treinada | `{9,12,13}` → `14,10,24,11` (4 ordens) |
| AC13 | ponto fixo | 8ª época sem mudança |
| AC14 | aprendizado | queda 97,7258%, margens ≥ 142, `249/24` |
| AC15 | ablações | completo 6/6; último token 1/6; limites 4/6 e 2/6 |
| AC16 | geração cadeia | `9 12 13 14 24`, `PARE`, texto |
| AC17 | geração limites | `maximo` 3/4/64, prefixo `24`/`12 24`, `N=64` |
| AC18 | erros | códigos 1..5 e 1..3, precedência, estado/saída |
| AC19 | determinismo | A ≡ B nos `.expected` e nas execuções |
| AC20 | composição | M1/M3/M4/M5/M6; 25 seeds da M6 |
| AC21 | pureza | parâmetros intactos; `SAIDA_INTACTA` |
| AC22 | documentação | este documento e o plano com evidências medidas |

### 11.4 Limitações

- Contexto de **3 tokens**, não de longo prazo.
- Uma camada afim, sem atenção ou recorrência.
- Vocabulário fechado de 25 IDs; `UNK` sem semântica.
- 6 exemplos sintéticos; nenhuma generalização linguística demonstrada.
- Texto é projeção impressa, não detokenização inversa.
- O modelo usa os três últimos tokens, mas o conjunto não força cada posição
  individualmente (a ablação "tokens antigos" também acerta).
- A parada é apenas `pare` ou limite; não há detecção de ciclo.
- Não há commit, push, tag ou operação remota nesta fase.

### 11.5 Registro de execução (E0–E7)

Execução em 2026-10-27, a partir de `main` em
`38fc295be84c7f62ee14b337b76bffb433387938`, com a suíte de partida em
**84 PASS / 0 FAIL**. O contrato normativo de §1–§10 permaneceu inalterado; a
versão foi congelada em E0 porque nenhum gate disparou.

| Etapa | Evidência medida | Arquivo |
| --- | --- | --- |
| E0 | 16 sondas P1–P16; P13 reproduziu bytes idênticos; P14 confirmou ASCII puro, sem BOM, sem CR e com LF final; gates aprovados | `temp/e0-ctx/results.txt` |
| E1 | 7 linhas de config, 25 linhas `PARAM16`, `MAXIMO16=12 4`, 5 linhas `CTX16`, `MAPA` e `E16_OK=100` | `temp/e0-ctx/manual/e1.txt` |
| E2 | `PERDA=6728768`, `ACERTOS=0`, `PRED=6 11 6 19 10 6`, códigos 1–4, `VALIDO=OK` | `temp/e0-ctx/manual/e2.txt` |
| E3 | `CODIGO=0`, `HISTORICO=6728768 465936`, `ACERTOS=4`, `PRED=9 0 10 24 11 9`, `ALTERADOS_W=254`, `ALTERADOS_B=24` | `temp/e0-ctx/manual/e3.txt` |
| E4 | tabela final de §7.7, `MAXIMO16=11 5`, `HISTORICO` de §7.4, `PERDA=153027`, `ACERTOS=6`, `PRED=14 24 10 24 11 9`, `249/24`, `MARGENS=142 151 156 174 201 167`, `S8=153027`, `MUDOU_W=0`, `MUDOU_B=0` | `temp/e0-ctx/manual/e4.txt` |
| E5 | 7 blocos de geração canônicos, códigos 1–4 de geração, código 5 de treino com `PARCIAL_W0=-20`, `PARCIAL_W1=-16`, `PARCIAL_W299=-16`, `PARCIAL_B0=0`, `PARCIAL_B24=0`, `PARAMS_INTACTOS=OK` | `temp/e0-ctx/manual/e5.txt` |
| E6 | builder gerou 16 `.por` + 16 `.expected`; suíte **100 PASS / 0 FAIL**, exit `0`; autoteste **0 PASS / 1 FAIL**, exit `1` | `temp/m7-suite.log`, `temp/m7-selftest.log` |
| E7 | verificador **Checks: 16 / Failures: 0**, exit `0`, 16 casos executados; V16 reexecutou suíte e M1–M6 | `temp/m7-verify.log`, `temp/m7-verify-suite.log`, `temp/m7-verify-selftest.log` |

A regressão de E7 confirmou os verificadores anteriores sem falhas:
M1 **21/21**, M3 **19/19**, M4 **22/22**, M5 **23/23** e M6 **13/13**, todos com
exit `0`. Os 15 hashes congelados de §1.1 do plano permaneceram idênticos; o
diff de `scripts/test.ps1` é puramente aditivo, com 24 linhas inseridas dentro
de `if (-not $SelfTest)`, e a remoção desse bloco reconstrói o hash original
`2a37138a…`. A árvore terminou com apenas os seis arquivos autorizados e nenhum
`add`, commit, tag, push, `reset`, `clean` ou `restore` foi executado.

## Apêndice A — Tabela canônica inicial

Ver §5.2.

## Apêndice B — Tabela canônica final

Ver §7.7.

## Apêndice C — Geração de 64 tokens

Prefixo `9`, `maximo = 64`, estado de §7.7:

```
GERADO=9 10 11 14 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19 11 19
N=64
PASSOS=63
PARADA=MAXIMO
TEXTO=se senao enquanto ate enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e enquanto e
```
