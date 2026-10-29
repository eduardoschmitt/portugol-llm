# Especificação — Treinamento a partir de corpus textual (M8)

- **Status:** concluída e verificada em 2026-10-29. `corpus/m8-corpus-v1.txt`
  existe (165 bytes, SHA-256
  `d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113`), os 16
  casos novos passam, a suíte chega a **116/116**, o verificador M7 reporta
  **16/16** e o M8 **18/18**, ambos exit `0`. A incompatibilidade anterior
  (M7 14/16, M8 17/18) era estrutural: o verificador congelado da M7 exigia
  `test.ps1` com 377 linhas/hash pré-M7 e suíte 100/100. A missão seguinte
  autorizou a edição exclusiva de `scripts/verify-context-bytes.ps1`; o patch
  aplicado está em `docs/corpus-plan.md` §12.2. Nenhum valor canônico divergiu.
  Ver §10 e §12 do plano.
- **Versão:** `v0.1.0`.
- **Substitui:** no novo caminho da M8, o dataset sintético fixo da M7 por
  exemplos extraídos de um corpus textual fixo, versionado e reproduzível. A M7
  permanece intacta como regressão.
- **Fora de escopo:** ampliar o vocabulário, alterar `src/contexto.por`,
  embeddings treináveis, softmax, amostragem, atenção, Transformer, leitura de
  arquivos em tempo de execução pelo `.por`, generalização em texto natural,
  commit e push.
- **Missões reutilizadas:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M6 (`docs/generation-spec.md` v1.0.0) e
  M7 (`docs/context-spec.md` v1.0.0).

## 1. Contrato

| Item | Definição |
| --- | --- |
| Entrada lógica | um corpus textual fixo, com uma frase por linha. |
| Entrada física | `corpus/m8-corpus-v1.txt`, ASCII, LF, um LF final. |
| Pipeline | texto → tokenização → IDs → janelas K=3 → alvos → treinamento → geração. |
| Saída lógica | `w16[300]` e `b16[25]` treinados a partir dos exemplos extraídos. |
| Saída observável | linhas ASCII do driver de teste, definidas em §11.4. |
| Unidade de exemplo | `(contexto de 3 IDs, alvo de 1 ID)`. |
| Vocabulário | exatamente os 25 IDs da M1; `0=UNK`, `24=pare`; nenhum ID novo. |
| Janela | `K=3`; contexto é sempre a tripla imediatamente anterior ao alvo. |
| Fronteira | nenhuma janela atravessa o fim de uma linha. |
| Token de término | `pare` (24), já existente na M6/M7. |
| Aleatoriedade | nenhuma; ordem, inicialização e atualização são fixas. |

O objetivo é demonstrar que o modelo contextual K=3 da M7 aprende
**efetivamente** os exemplos extraídos do corpus, e não pares pré-programados.
O corpus é pequeno e controlado. O resultado é ajuste ao corpus, não
generalização.

## 2. Arquitetura e reutilização

```
corpus/m8-corpus-v1.txt
        │  (builder valida bytes e injeta as linhas como literais)
        ▼
cadeia linhas[6]
        │  corp_tokenizar  ──► id_do_campo (M1)
        ▼
IDs por linha
        │  corp_extrair    ──► janelas K=3, sem cruzar linhas
        ▼
entradas[90] / alvos[30]   (N exemplos, N ≤ 30)
        │  corp_treinar    ──► lotes de até 6
        ▼
ctx_executar(..., lote, 1, ...)   (M7, sem alteração)
        │
        ▼
w16[300] / b16[25]
        │  ctx_gerar       (M7/M6)
        ▼
IDs gerados → TEXTO
```

| Componente | Origem | Uso na M8 | Alteração |
| --- | --- | --- | --- |
| Vocabulário e IDs | M1 | tabela fixa `0..24`; `id_do_campo` | nenhuma |
| Tokenização de palavra | M1 | `id_do_campo(texto, ini, fim)` | nenhuma |
| Varredura de campos | M8 | `corp_tokenizar`, estrita ao formato do corpus | nova, mínima |
| Embeddings `e16` | M3 via M7 | `ctx_e16`/`ctx_montar_contexto` | nenhuma |
| Rede linear e forward | M7 | `ctx_z256`, `ctx_argmax` | nenhuma |
| Inicialização | M7 | `ctx_inicializar` | nenhuma |
| Atualização e perda | M7 | `ctx_executar`, `ctx_perda_escalada` | nenhuma |
| Orquestração de lotes | M8 | `corp_perda_total`, `corp_treinar` | nova, mínima |
| Geração autoregressiva | M7/M6 | `ctx_gerar` | nenhuma |

### 2.1 O que não é duplicado

- A fórmula de embedding não é reimplementada: `ctx_montar_contexto` já usa
  `ctx_e16`, cuja igualdade com a M3 é coberta por `ctx_composicao`.
- O forward, o `argmax`, a perda, a atualização quantizada e a inicialização não
  são reimplementados: são chamados de `src/contexto.por`.
- A geração não é reimplementada: `ctx_gerar` já generaliza a M6 para prefixos
  de 1 a 3 tokens.
- O vocabulário não é reimplementado: `corp_tokenizar` chama `id_do_campo`.

### 2.2 Duplicações justificadas

1. **Varredura de campos.** A M1 expõe `tokenizar(cadeia)`, que imprime
   `IDS=...`; ela não expõe uma função que devolva um array de IDs. A M8 precisa
   dos IDs em memória para montar janelas. `corp_tokenizar` varre os campos e
   delega cada palavra a `id_do_campo`. A tabela de 24 palavras não é copiada.
2. **Orquestração de lotes.** `ctx_executar` aceita `n ≤ 6`. A M8 precisa de
   `N > 6`. `corp_treinar` copia até 6 exemplos por vez para buffers e chama
   `ctx_executar` com `epocas=1`, preservando a ordem global. O laço de
   atualização não é copiado.

### 2.3 Dependência de composição

`src/corpus.por` é um fragmento, não um programa. Ele pressupõe que
`src/tokenizador.por` seja concatenado **antes** dele, pois usa o alias `tx` e a
função `id_do_campo`. Os builders devem impor essa ordem. Se a ordem for
invertida, o programa não compila; não há fallback silencioso.

## 3. Corpus v1

### 3.1 Arquivo e bytes

| Propriedade | Valor |
| --- | --- |
| Caminho | `corpus/m8-corpus-v1.txt` |
| Codificação | ASCII puro (`0x20..0x7E` e `0x0A`) |
| Fim de linha | LF (`0x0A`), sem CR |
| BOM | proibido |
| Linhas | 5 |
| Tokens | 25 |
| Bytes | 165 |
| SHA-256 | `d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113` |
| LF final | exatamente um |

Conteúdo normativo, byte a byte:

```text
programa inicio escreva verdadeiro pare
funcao inicio escreva falso pare
se verdadeiro faca escreva pare
se falso senao leia pare
enquanto verdadeiro faca leia pare
```

Cada linha tem exatamente 5 tokens separados por um único espaço, sem espaço
inicial ou final. A última linha também termina em LF.

### 3.2 Gramática

```
linha   := palavra (" " palavra)*
palavra := uma das 24 palavras com ID 1..24
linha   := ... " " "pare"          (pare é o último token)
```

Regras adicionais:

- `pare` aparece exatamente uma vez por linha e somente na última posição.
- `UNK` (0) não é permitido no corpus.
- Não há normalização de caixa, acento, Unicode ou pontuação. `Programa`,
  `programa.` e `programação` são palavras desconhecidas.
- Não há TAB, CR, BOM, linha vazia, espaço duplo, espaço inicial ou final.
- O corpus v1 tem 5 tokens por linha. O extrator genérico aceita 4 a 8 tokens
  por linha, para testes; o arquivo v1 não usa essa folga.

### 3.3 Por que este corpus

- Cobre os contextos de abertura `programa`, `funcao`, `se`, `senao`,
  `enquanto`, `faca`, `escreva`, `leia` e os booleanos `verdadeiro`/`falso`.
- Produz 10 exemplos, quantidade maior que 6, exercitando o particionamento em
  lotes 6 + 4.
- Todos os 10 contextos são distintos e todos os 10 pares
  `(contexto, alvo)` são únicos. Não há conflito.
- Cinco exemplos têm alvo `pare`; cinco têm alvo de conteúdo. Isso impede que
  uma regra trivial “sempre `pare`” acerte tudo.
- Nenhum alvo é igual ao último token do contexto; não há exemplo de cópia
  trivial.
- Mesmo último token, alvos diferentes: `1 3 17 → 22` e `2 3 17 → 23`;
  `9 22 12 → 17` e `11 22 12 → 18`. Um modelo que olhe apenas o último token
  não pode acertar os quatro.
- O corpus é curto o suficiente para manter `S` muito abaixo do limite inteiro
  e para permitir um oráculo independente completo.
- O corpus foi fixado antes da implementação. Não será ajustado para “fazer
  passar”.

### 3.4 Tratamento de UNK

O corpus válido não contém UNK. Se qualquer palavra não tiver igualdade exata
com uma das 24 palavras, `corp_tokenizar` retorna código `3`
(`PALAVRA_DESCONHECIDA`) e não escreve no array de IDs. A extração propaga o
código com a linha e a posição do token. Não há substituição silenciosa por 0:
um corpus com UNK é inválido e não treina.

### 3.5 Tokens especiais

- `pare` (24) é o único token de término, herdado da M6/M7.
- Não há BOS, EOS, PAD ou SEP novos. O preenchimento de contextos com menos de
  3 tokens na geração é o vetor zero implícito da M7, não um ID de vocabulário.
- `UNK` (0) existe no vocabulário, mas é proibido no corpus.

## 4. Tokenização

### 4.1 Contrato

`corp_tokenizar(linha, ids[], diagnostico[])`:

1. valida o formato estrito da linha;
2. conta os campos;
3. chama `id_do_campo` para cada campo;
4. rejeita IDs 0;
5. exige `pare` na última posição e em nenhuma outra;
6. só então copia os IDs para `ids[]`.

Retorno: número de tokens (4..8) em sucesso; `-código` em erro. Em erro, `ids[]`
permanece intacto.

### 4.2 IDs canônicos

| Linha | Texto | IDs |
| ---: | --- | --- |
| 1 | `programa inicio escreva verdadeiro pare` | `1 3 17 22 24` |
| 2 | `funcao inicio escreva falso pare` | `2 3 17 23 24` |
| 3 | `se verdadeiro faca escreva pare` | `9 22 12 17 24` |
| 4 | `se falso senao leia pare` | `9 23 10 18 24` |
| 5 | `enquanto verdadeiro faca leia pare` | `11 22 12 18 24` |

### 4.3 Erros de linha

| Código | Nome | Condição |
| ---: | --- | --- |
| 2 | `FORMATO_INVALIDO` | vazio, BOM, CR, TAB, não ASCII, espaço duplo/inicial/final |
| 3 | `PALAVRA_DESCONHECIDA` | campo sem igualdade exata; inclui `UNK` literal e maiúsculas |
| 4 | `SEM_PARADA` | último token não é `pare` |
| 5 | `PARADA_INVALIDA` | `pare` no meio, ou mais de um `pare` |
| 6 | `LINHA_CURTA` | menos de 4 tokens |
| 7 | `LINHA_LONGA` | mais de 8 tokens |

A precedência dentro da linha é: `2 → 3 → 6 → 7 → 4 → 5`. Assim, uma linha de
3 tokens sem `pare` retorna `6` (curta), não `4`.

### 4.4 Composição com a M1

Para cada uma das 5 linhas, a sequência de IDs de `corp_tokenizar` deve ser
idêntica à sequência impressa por `tokenizar` da M1. O caso `corp_composicao`
imprime as duas sequências e compara. Nenhuma palavra é adicionada ao
vocabulário.

## 5. Extração de exemplos

### 5.1 Janelas

Para uma linha com IDs `t[0..L-1]`, com `L` entre 4 e 8:

```
para i = 3 .. L-1:
    contexto = (t[i-3], t[i-2], t[i-1])
    alvo     = t[i]
```

- A janela é sempre completa (3 tokens). Não há padding no treinamento.
- Os três primeiros tokens da linha nunca são alvos; eles só aparecem como
  contexto.
- O último token da linha é sempre um alvo.
- Nenhuma janela usa tokens de outra linha.
- A ordem canônica é: linha 0, depois `i=3,4,...`; depois linha 1, e assim por
  diante. Não há embaralhamento.

### 5.2 Exemplos canônicos

| # | Linha | `i` | Contexto | Alvo | Palavras |
| ---: | ---: | ---: | --- | ---: | --- |
| 0 | 1 | 3 | `1 3 17` | 22 | `programa inicio escreva` → `verdadeiro` |
| 1 | 1 | 4 | `3 17 22` | 24 | `inicio escreva verdadeiro` → `pare` |
| 2 | 2 | 3 | `2 3 17` | 23 | `funcao inicio escreva` → `falso` |
| 3 | 2 | 4 | `3 17 23` | 24 | `inicio escreva falso` → `pare` |
| 4 | 3 | 3 | `9 22 12` | 17 | `se verdadeiro faca` → `escreva` |
| 5 | 3 | 4 | `22 12 17` | 24 | `verdadeiro faca escreva` → `pare` |
| 6 | 4 | 3 | `9 23 10` | 18 | `se falso senao` → `leia` |
| 7 | 4 | 4 | `23 10 18` | 24 | `falso senao leia` → `pare` |
| 8 | 5 | 3 | `11 22 12` | 18 | `enquanto verdadeiro faca` → `leia` |
| 9 | 5 | 4 | `22 12 18` | 24 | `verdadeiro faca leia` → `pare` |

`N = 10`. Todos os contextos são distintos. Todos os pares são únicos.

### 5.3 Fronteiras

A extração é estritamente por linha. O teste `corp_fronteiras` usa três linhas
sintéticas e verifica:

- nenhuma janela tem como alvo o primeiro token de uma linha seguinte;
- nenhum contexto combina os últimos tokens de uma linha com tokens da linha
  seguinte;
- os três primeiros tokens de cada linha não aparecem como alvo;
- o último token de cada linha aparece como alvo;
- o número de exemplos é `Σ (L_i − 3)`.

### 5.4 Duplicação e conflito

Após montar cada exemplo, a extração compara o contexto com todos os anteriores:

- mesmo contexto e mesmo alvo → código `9` (`EXEMPLO_DUPLICADO`);
- mesmo contexto e alvo diferente → código `10` (`CONTEXTO_CONFLITANTE`);
- contextos diferentes → prossegue.

Não há deduplicação silenciosa. O corpus canônico não dispara nenhum dos dois.

### 5.5 Capacidade

| Limite | Valor | Consequência |
| --- | ---: | --- |
| linhas | 1..6 | `CORP_MAX_LINHAS = 6` |
| tokens por linha | 4..8 | `CORP_MIN_TOKENS = 4`, `CORP_MAX_TOKENS = 8` |
| exemplos | 1..30 | `6 × (8 − 3) = 30` |
| contexto | 3 | `CORP_K = 3` |
| lote de treino | até 6 | `CORP_LOTE = 6` |
| épocas | 1..32 | herdado da M7 |
| parâmetros | `|v| ≤ 16` | herdado da M7 |
| prefixo de geração | 1..3 | herdado da M7 |
| `maximo` de geração | 1..64 | herdado da M7 |

`N > 30` é impossível dentro dos limites de linhas e tokens; não é um código de
erro separado. O caso `corp_capacidade` exercita `N=30` com 6 linhas de 8
tokens e verifica 5 lotes de 6. A fixture é fixa e não faz parte do corpus v1:

```text
programa inicio inteiro real logico cadeia vazio pare
funcao inicio logico real cadeia vazio inteiro pare
se verdadeiro faca leia escreva retorne passo pare
enquanto falso faca escreva leia retorne passo pare
para real ate passo leia faca escreva pare
se falso senao leia retorne escreva passo pare
```

Ela tem 30 contextos distintos e 30 pares únicos; `S0 = 19.563.100` com a
inicialização canônica.

## 6. Estado, arrays e constantes

### 6.1 Arrays do chamador

| Nome | Tipo | Tamanho | Índice | Papel |
| --- | --- | ---: | --- | --- |
| `linhas` | `cadeia` | 6 | linha | corpus em memória |
| `entradas` | `inteiro` | 90 | `n*3 + k` | contextos de todos os exemplos |
| `alvos` | `inteiro` | 30 | `n` | alvos |
| `w16` | `inteiro` | 300 | `y*12 + p` | pesos em 1/16 (M7) |
| `b16` | `inteiro` | 25 | `y` | vieses em 1/16 (M7) |
| `historico` | `inteiro` | 33 | `e` | `S` inicial + uma por época |
| `saida` | `inteiro` | 64 | `i` | geração |
| `diagnostico` | `inteiro` | 2 | `0=linha, 1=token` | erro de extração |
| `n_exemplos` | `inteiro` | 1 | `0` | `N` extraído |

### 6.2 Constantes de `src/corpus.por`

Todas literais, sem expressão em `const` (restrição da M3/M7):

```
CORP_MAX_LINHAS   = 6
CORP_MIN_TOKENS   = 4
CORP_MAX_TOKENS   = 8
CORP_MAX_EXEMPLOS = 30
CORP_K            = 3
CORP_LOTE         = 6
CORP_MAX_EPOCAS   = 32
CORP_LIMITE_PERDA = 2000000000
```

`CORP_LIMITE_PERDA` é o teto do acumulador agregado de `S`, abaixo de `2^31−1`.
Ele não substitui o limite de 16 dos parâmetros.

### 6.3 Invariantes

| ID | Invariante |
| --- | --- |
| I1 | `CORP_K == 3` e `CORP_LOTE == CTX_MAX_EXEMPLOS == 6` |
| I2 | `CORP_MAX_EXEMPLOS == CORP_MAX_LINHAS × (CORP_MAX_TOKENS − CORP_K) == 30` |
| I3 | `N` extraído é `1..30`; cada linha contribui com `L−3` exemplos |
| I4 | `entradas` tem `3N` posições válidas; `alvos` tem `N` |
| I5 | `historico` tem `E+1` posições válidas |
| I6 | `corp_treinar` não altera a ordem dos exemplos |
| I7 | `corp_treinar` não lê estado anterior além de `w16`/`b16` |
| I8 | `corp_extrair` e `corp_tokenizar` não alteram `w16`/`b16` |
| I9 | Em erro de validação de treino, `w16`/`b16` não mudam |

## 7. Inicialização

Não há inicialização nova. `corp_treinar` recebe `w16`/`b16` já preenchidos por
`ctx_inicializar`, que é a inicialização canônica da M7 §5.1:

```
W16[y][k][d] = 0                                  se k = 0 ou k = 1
W16[y][2][d] = (((y·7 + d·5) mod 25) − 12)        se k = 2
b16[y]       = (((y·7) mod 9) − 4)
```

Propriedades: `max |W16| = 12`, `max |b16| = 4`; as fatias 0 e 1 começam
zeradas; a tabela inicial completa está em `docs/context-spec.md` §5.2. A M8 não
tem seed, não tem reinicialização aleatória e não altera essa tabela.

## 8. Forward, perda e exatidão

### 8.1 Fórmulas herdadas

Para um contexto `c16[0..11]` e `y ∈ 0..24`:

```
Z256(c,y) = Σ_{p=0..11} W16[y][p] · c16[p] + 16 · b16[y]
δ256(c,y,t) = Z256(c,y) − 256·[y = t]
S = Σ_{exemplos n} Σ_{y=0..24} δ256(c_n,y,t_n)²
L = S / (131072 · N) = (1/(2N)) · Σ (z_n,y − [y=t_n])²
```

A ordem de acumulação é `p=0..11`, começando em 0, com o viés por último. Todos
os valores são inteiros; não há `float`, `NaN`, `-0.0` ou dependência de locale.

### 8.2 Perda total em lotes

`corp_perda_total` não chama `ctx_perda_escalada` com `N=30` de uma vez. Ela
itera lotes de até 6, chama `ctx_perda_escalada` por lote e soma:

```
total = 0
para cada lote de até 6 exemplos:
    parcial = ctx_perda_escalada(w16, b16, lote_entradas, lote_alvos, tam)
    se total > CORP_LIMITE_PERDA − parcial: retorne 16
    total = total + parcial
saida[0] = total
```

Cada `parcial` de um lote de 6 é no máximo `1.926.758.400`, pela prova da M7
§3.3. O teste antes da soma impede que o acumulador de 32 bits estoure. O
resultado é idêntico à soma global, pois `S` é aditiva por exemplo.

### 8.3 Provas de faixa

- `|Z256| ≤ 12·16·16 + 16·16 = 3.328` em estado válido.
- `|δ256| ≤ 3.328 + 256 = 3.584`.
- `δ256² ≤ 12.845.056`.
- Lote de 6: `25·6·12.845.056 = 1.926.758.400 < 2^31`.
- Acumulador: guardado em `2.000.000.000 < 2^31`.
- Estado canônico: `S0 = 8.404.936`, muito abaixo do limite.

## 9. Treinamento

### 9.1 Algoritmo de `corp_treinar`

```
valida N (1..30), épocas (1..32), IDs (0..24), |W16|,|b16| ≤ 16
historico[0] = corp_perda_total(...)
para ep = 1 .. epocas:
    para inicio = 0, 6, 12, ... < N:
        tam = min(6, N − inicio)
        copia entradas/alvos do lote para buffers de 18/6
        codigo = ctx_executar(w16, b16, lote_entradas, lote_alvos,
                              tam, 1, hist_lote)
        se codigo != 0: retorne mapa(codigo)
    historico[ep] = corp_perda_total(...)
retorne 0
```

- `ctx_executar` é chamado com `epocas=1`; o laço de épocas é da M8.
- A ordem global é a concatenação dos lotes na ordem do array. Não há
  embaralhamento entre épocas.
- `hist_lote` é um buffer local de 2 inteiros; seu conteúdo não é usado.
- O `historico[ep]` é sempre a perda do conjunto completo, não a do último lote.

### 9.2 Equivalência com uma passagem global

Suponha `N=10` e lotes `B0=[0..5]`, `B1=[6..9]`. `ctx_executar(B0,1)` executa
as atualizações dos exemplos 0..5, em ordem, e para. `ctx_executar(B1,1)`
executa 6..9 a partir do estado deixado por B0. Como a atualização de cada
exemplo depende apenas do estado atual e do próprio exemplo, e não de `N` nem de
estatísticas globais, a concatenação é idêntica a uma passagem única sobre
0..9. O mesmo argumento vale para qualquer `N` e qualquer número de épocas. O
caso `corp_lotes` verifica isso com `N=6` (um lote, comparação direta com
`ctx_executar`) e com `N=10` (6+4, comparação com o oráculo).

### 9.3 Hiperparâmetros

| Item | Valor | Justificativa |
| --- | ---: | --- |
| taxa `η` | `1/8` | herdada da M7; não há novo sweep |
| época canônica `E` | 4 | menor `E` com `10/10` e `S` estritamente decrescente até `E` |
| épocas aceitas | 1..32 | limite da M7 |
| lote | 6 | limite de `ctx_executar` |
| atualização | `r(2048·W16 − δ256·c16, 2048)` e `r(128·b16 − δ256, 128)` | M7 §7 |
| ordem | linha, depois `i` crescente | fixa, sem RNG |
| inicialização | `ctx_inicializar` | canônica |

A época 4 é escolhida por um critério objetivo fixado antes da implementação:
**o menor `E` em 1..32 tal que a acurácia no conjunto completo seja `N/N` e
`S_e < S_{e−1}` para todo `e ≤ E`**. Em `E=1,2,3` a acurácia é `6/10`, `8/10`,
`7/10`; em `E=4` é `10/10`. A época 5 não é usada porque a acurácia cai para
`9/10`; isso é relatado, não escondido.

### 9.4 Critérios de parada do treino

- `ctx_executar` retorna 0 em todos os lotes → prossegue.
- Retorna 5 (`ESTOURO_NUMERICO`) → `corp_treinar` retorna 15; o estado pode ter
  mutação parcial; o chamador deve reinicializar.
- `corp_perda_total` retorna 16 (`ESTOURO_AGREGADO`) → `corp_treinar` retorna
  16; o estado está válido, mas a perda não é representável no acumulador.
- Qualquer código de validação (11..14) → retorna antes de qualquer mutação.

### 9.5 Determinismo

Não há `aleatorio`, relógio, teclado, arquivo, ambiente ou paralelismo no
caminho de treino. A ordem dos exemplos é a ordem do array. A inicialização é
canônica. Duas execuções com o mesmo corpus, a mesma ordem e o mesmo `E`
produzem os mesmos 325 parâmetros e o mesmo `historico`, byte a byte.

## 10. Geração

`corp_treinar` não implementa geração. O driver chama `ctx_gerar` da M7, que:

- aceita prefixo de 1 a 3 IDs;
- rejeita `pare` fora da última posição;
- aceita `maximo` de 1 a 64, com `maximo ≥ n_prefixo`;
- gera por `argmax` do contexto dos últimos 3 tokens;
- para em `pare` (24), que tem precedência sobre o limite;
- devolve `N` e escreve `saida[]`.

Prefixos canônicos e saídas em `E=4`:

| Prefixo | Saída | Texto | `N` | `PASSOS` | `PARADA` |
| --- | --- | --- | ---: | ---: | --- |
| `1 3 17` | `1 3 17 22 24` | `programa inicio escreva verdadeiro pare` | 5 | 2 | `PARE` |
| `9 22 12` | `9 22 12 17 24` | `se verdadeiro faca escreva pare` | 5 | 2 | `PARE` |
| `11 22 12` | `11 22 12 18 24` | `enquanto verdadeiro faca leia pare` | 5 | 2 | `PARE` |
| `9 23 10` | `9 23 10 18 24` | `se falso senao leia pare` | 5 | 2 | `PARE` |
| `2 3 17` | `2 3 17 23 24` | `funcao inicio escreva falso pare` | 5 | 2 | `PARE` |

Esses prefixos são contextos que aparecem no corpus. A geração correspondente é
**reprodução de janelas vistas**, não generalização. Um prefixo com `pare` na
última posição, por exemplo `22 12 24`, retorna `N=3`, `PASSOS=0`, `PARE`. Com
`maximo=4`, `1 3 17` retorna `1 3 17 22`, `PASSOS=1`, `MAXIMO`.

### 10.1 Sondagem fora do corpus

Para documentar a ausência de generalização, o plano inclui uma sonda
diagnóstica com cinco linhas que não pertencem ao corpus:

```
para inteiro ate passo pare
programa inicio leia falso pare
se falso faca escreva pare
funcao inicio retorne verdadeiro pare
enquanto falso faca escreva pare
```

Em `E=4`, o modelo acerta 1 dos 10 alvos dessas linhas. Esse número é evidência
de limitação, não critério de aceitação. Nenhuma alegação de generalização pode
ser feita a partir dele.

## 11. API, erros e formato observável

### 11.1 Funções de `src/corpus.por`

```portugol
funcao inteiro corp_tokenizar(cadeia linha, inteiro ids[],
                              inteiro diagnostico[])
funcao inteiro corp_extrair(cadeia linhas[], inteiro n_linhas,
                            inteiro entradas[], inteiro alvos[],
                            inteiro n_exemplos[], inteiro diagnostico[])
funcao inteiro corp_perda_total(inteiro w16[], inteiro b16[],
                                inteiro entradas[], inteiro alvos[],
                                inteiro n, inteiro saida[])
funcao inteiro corp_treinar(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[],
                            inteiro n, inteiro epocas,
                            inteiro historico[])
```

`corp_tokenizar` devolve a contagem de tokens ou `-código`. `corp_extrair`,
`corp_perda_total` e `corp_treinar` devolvem `0` ou um código positivo.

### 11.2 Códigos de erro

| Código | Nome | Condição |
| ---: | --- | --- |
| 1 | `CORPUS_VAZIO` | `n_linhas = 0` |
| 2 | `FORMATO_INVALIDO` | formato estrito violado |
| 3 | `PALAVRA_DESCONHECIDA` | palavra fora do vocabulário (UNK) |
| 4 | `SEM_PARADA` | última palavra não é `pare` |
| 5 | `PARADA_INVALIDA` | `pare` fora do fim ou duplicado |
| 6 | `LINHA_CURTA` | menos de 4 tokens |
| 7 | `LINHA_LONGA` | mais de 8 tokens |
| 8 | `MUITAS_LINHAS` | mais de 6 linhas |
| 9 | `EXEMPLO_DUPLICADO` | mesmo contexto e mesmo alvo |
| 10 | `CONTEXTO_CONFLITANTE` | mesmo contexto e alvo diferente |
| 11 | `EPOCAS_INVALIDAS` | `epocas < 1` ou `> 32` |
| 12 | `EXEMPLOS_INVALIDOS` | `n < 1` ou `> 30` |
| 13 | `ID_INVALIDO` | ID fora de `0..24` |
| 14 | `PARAMETROS_INVALIDOS` | `|W16| > 16` ou `|b16| > 16` |
| 15 | `ESTOURO_NUMERICO` | atualização produziria `|v| > 16` |
| 16 | `ESTOURO_AGREGADO` | soma de `S` ultrapassaria `2.000.000.000` |

### 11.3 Precedência e estado em erro

- Extração: `1 → 8 → 2 → 3 → 6 → 7 → 4 → 5 → 9 → 10`.
- Treino: `12 → 11 → 13 → 14 → 15/16`.
- Em `corp_tokenizar`, `diagnostico[0]` é a posição 1-based do token culpado
  (0 quando não se aplica) e `diagnostico[1]=0`. Em `corp_extrair`,
  `diagnostico[0]` é a linha 1-based e `diagnostico[1]` é o token 1-based
  (0 quando não se aplica). Para 6/7, o token é a contagem encontrada; para 4,
  é 0; para 5, é a posição do primeiro `pare`.
- Extração e tokenização: nenhuma escrita em `entradas`, `alvos`,
  `n_exemplos` ou `ids` antes da validação completa. Em erro, os buffers ficam
  intactos.
- Treino 11..14: nenhuma mutação em `w16`/`b16`.
- Treino 15: mutação parcial possível; reinicializar.
- Treino 16: estado válido, mas `historico[ep]` não é gravado.
- Geração: os códigos e o estado em erro são os da M7 §10.3–§10.4.

### 11.4 Gramática observável dos drivers

As linhas abaixo são emitidas pelos **drivers de teste**, não por
`src/corpus.por`. Tudo é ASCII, uma linha por registro, `\n` no fim.

```
CORPUS=OK LINHAS=<n> TOKENS=<n> EXEMPLOS=<n>
CORPUS_SHA256=<64 hex>
IDS=<id>[ <id>]*
EXEMPLO=<i> CTX=<a> <b> <c> ALVO=<t>
HISTORICO=<S0>[ <S1> ... <SE>]
PERDA=<inteiro>
ACERTOS=<0..N>
PRED=<id>[ <id>]*
MARGENS=<inteiro>[ <inteiro>]*
ALTERADOS_W=<inteiro>
ALTERADOS_B=<inteiro>
MAXIMO16=<inteiro> <inteiro>
ABL_ULTIMO=<0..N>
ABL_ANTIGOS=<0..N>
ABL_ULTIMO_PERDA=<inteiro>
ABL_ANTIGOS_PERDA=<inteiro>
GERADO=<id>[ <id>]*
N=<inteiro>
PASSOS=<inteiro>
PARADA=PARE|MAXIMO
TEXTO=<palavra>[ <palavra>]*
ORDEM=DIRETA|INVERSA
DIF_PARAMS=<inteiro>
PARAM16=<y> <12 inteiros> <inteiro>
ERRO=<1..16> LINHA=<n> TOKEN=<n>
DETERMINISMO=OK
PARAMS_INTACTOS=OK
IDS_INTACTOS=OK
SAIDA_INTACTA=OK
M1_IDS=OK
M3_OK=<inteiro>
M7_OK=<inteiro>
M8_OK=<inteiro>
```

`CORPUS_SHA256` é calculado pelo builder/verificador, não pelo `.por`. `ERRO`
usa `LINHA=0 TOKEN=0` quando a posição não se aplica. `TEXTO` usa a mesma
projeção da M7: `UNK` para 0, a palavra da tabela para 1..24, separada por um
espaço e sem espaço final. Sucesso nunca contém `ERRO=`; erro nunca contém dados
de treino.

## 12. Valores canônicos

Os valores desta seção foram derivados por dois oráculos independentes:
aritmética inteira (`W16`, `b16`, `c16`, `Z256`, `δ256`, `r`) e aritmética
racional exata (`fractions.Fraction`, estado em 1/16, quantização para 1/16).
Os dois concordaram em todos os 325 parâmetros, no histórico, nas predições e
nas margens. O builder será uma terceira derivação; a implementação, uma quarta;
o verificador, uma quinta.

### 12.1 Trajetória

| Época | `S` | `L = S/(131072·10)` | Acertos |
| ---: | ---: | ---: | ---: |
| 0 | 8.404.936 | 6,4125… | 1/10 |
| 1 | 1.341.188 | 1,0232… | 6/10 |
| 2 | 651.091 | 0,4967… | 8/10 |
| 3 | 509.249 | 0,3884… | 7/10 |
| 4 | 436.118 | 0,3327… | 10/10 |

Queda total: `7.968.818` (`94,81%`). A acurácia não é monótona
(`6 → 8 → 7 → 10`); a perda é estritamente decrescente até `E=4`. A época 5
não faz parte do valor canônico; foi medida em `9/10` e é registrada como
limitação.

### 12.2 Estado em `E=4`

Predições: `22 24 23 24 17 24 18 24 18 24` (`10/10`).

Margens do alvo sobre o segundo colocado, em unidades de 1/256:

```
11 350 17 119 4 102 161 115 125 224
```

Todas são positivas; a menor é `4`.

Parâmetros alterados em relação à inicialização: **253/300** pesos e **22/25**
vieses. Mudanças por época (pesos/vieses): `259/23`, `176/16`, `119/15`,
`52/7`. Máximos: `max |W16| = 9`, `max |b16| = 6`.

Tabela final `PARAM16=y w0..w11 b`:

```
PARAM16=0 -2 -2 -4 0 3 1 0 1 -3 0 -1 -1 0
PARAM16=1 -2 1 0 1 -1 -1 3 1 -1 2 1 5 2
PARAM16=2 1 1 1 -1 -1 -2 -1 -5 2 -2 3 -4 -2
PARAM16=3 1 -1 1 0 2 1 -1 0 3 -3 2 -1 -1
PARAM16=4 -1 -1 0 0 1 2 2 2 -2 1 -1 3 1
PARAM16=5 1 1 2 -2 0 0 -4 -3 -1 -3 2 -7 -2
PARAM16=6 0 0 -1 -2 1 0 -3 3 -3 3 -5 -2 0
PARAM16=7 3 0 1 2 1 -1 1 0 4 -4 4 0 -1
PARAM16=8 0 0 -1 0 -1 -2 4 1 -2 2 0 3 3
PARAM16=9 1 2 0 -1 -1 0 -4 -5 2 -2 2 -6 -3
PARAM16=10 2 -1 3 1 1 0 -1 2 3 -3 2 -1 0
PARAM16=11 -2 -1 -1 0 1 1 2 1 -3 1 0 3 1
PARAM16=12 -2 1 -1 1 -3 -3 4 1 0 1 1 6 5
PARAM16=13 1 0 -1 -2 2 1 -4 1 -3 3 -5 -3 -1
PARAM16=14 2 0 2 1 1 -1 0 0 3 -3 3 2 0
PARAM16=15 -3 0 -1 0 -2 0 2 1 -2 2 0 5 3
PARAM16=16 1 1 -1 0 -2 0 -1 -4 1 -2 2 -6 -2
PARAM16=17 2 -5 -3 -2 4 3 1 0 0 2 -3 1 -1
PARAM16=18 1 0 -2 3 -3 0 -4 0 -4 0 1 4 6
PARAM16=19 -1 0 1 2 -3 -1 3 2 0 1 1 6 3
PARAM16=20 0 -1 -1 -3 2 1 -2 1 -3 4 -5 -3 -1
PARAM16=21 4 -3 2 3 0 0 1 0 6 -3 3 1 -2
PARAM16=22 -5 -1 -1 -2 0 1 3 1 -3 0 2 2 2
PARAM16=23 -1 0 -1 4 3 -2 -4 -2 0 -3 3 -9 0
PARAM16=24 -1 2 -2 -1 -1 3 3 -3 2 2 -8 -6 4
MAXIMO16=9 6
```

### 12.3 Ablações

| Modelo | Acertos | `S` |
| --- | ---: | ---: |
| Completo | **10/10** | 436.118 |
| Só o último token (fatias 0/1 zeradas) | 5/10 | 1.058.696 |
| Só os tokens antigos (fatia 2 zerada) | 8/10 | 1.180.874 |

A ablação decisiva é “só o último token”: ela isola o comportamento da M6 e
mostra que o último token sozinho não pode acertar os 10; o contexto de três
posições é necessário para a acurácia completa. O limite superior de qualquer
função que dependa só do último token é **7/10**: os grupos são
`17 → {22,23}`, `22 → {24}`, `23 → {24}`, `12 → {17,18}`, `10 → {24}` e
`18 → {24,24}`. A ablação treinada obtém 5/10. A ablação “só antigos” acerta
8/10 porque, neste corpus, os dois primeiros tokens de várias janelas são
únicos; isso não enfraquece a demonstração, apenas mostra que o corpus não foi
desenhado para forçar cada posição individualmente.

### 12.4 Sensibilidade à ordem

Mesma inicialização, mesmos 10 exemplos, mesma `η`, mesmo `E=4`, ordem
**inversa** (exemplo 9 → 0):

| Métrica | Ordem direta | Ordem inversa |
| --- | ---: | ---: |
| `S0` | 8.404.936 | 8.404.936 |
| `S4` | 436.118 | 377.464 |
| Acertos | 10/10 | 8/10 |
| `PRED` | `22 24 23 24 17 24 18 24 18 24` | `24 17 24 18 24 17 24 22 24 22` |
| `max |W16|` | 9 | 7 |
| `max |b16|` | 6 | 4 |
| Parâmetros diferentes | — | 213 (197 W + 16 b) |

Histórico inverso: `8.404.936 1.941.318 727.037 491.309 377.464`.

A ordem inversa tem `S4` **menor** e acurácia **menor**. Isso mostra que a perda
agregada, sozinha, não identifica o modelo correto, e que a ordem dos exemplos
muda o estado final. Primeira diferença de parâmetro: `W16[0][0] = −2` na ordem
direta e `−1` na inversa.

### 12.5 Geração

As saídas de §10 são canônicas. Além delas:

- prefixo `22 12 24` → `22 12 24`, `N=3`, `PASSOS=0`, `PARE`;
- prefixo `1 3 17`, `maximo=4` → `1 3 17 22`, `N=4`, `PASSOS=1`, `MAXIMO`;
- prefixo `1 3` → `1 3 12 12 19 18 24`, `N=7`, `PARE` (prefixo de 2 tokens,
  sem correspondência direta no corpus).

### 12.6 Sonda fora do corpus

Cinco linhas fora do corpus, 10 alvos, **1 acerto** em `E=4`. O único acerto é
`funcao inicio retorne verdadeiro` → `pare`. As demais transições não são
aprendidas. Isso é evidência de memorização, não de generalização.

## 13. Oráculo, testes e aceitação

### 13.1 Independência

| Derivação | Papel |
| --- | --- |
| Oráculo inteiro em Python | primeira derivação dos valores canônicos |
| Oráculo racional exato em Python | segunda derivação, independente da primeira |
| `scripts/build-corpus-tests.ps1` | terceira derivação, em PowerShell inteiro |
| `src/corpus.por` | quarta derivação, executada pelo interpretador |
| `scripts/verify-corpus-bytes.ps1` | quinta derivação, independente do builder |

Nenhuma lê `.expected` para decidir o valor esperado. Os valores canônicos de
§12 são literais de conferência no builder. Se o builder discordar, ele falha;
não regenera o esperado.

### 13.2 Matriz de testes

| Caso | Cobertura | Resultado exigido |
| --- | --- | --- |
| `corp_integridade` | corpus canônico | 5 linhas, 25 tokens, 10 exemplos, IDs de §4.2 |
| `corp_tokenizacao` | tokenização | 5 linhas `IDS` canônicas; `M1_IDS=OK` |
| `corp_janelas` | janelas K=3 | 10 linhas `EXEMPLO` de §5.2; `N=10` |
| `corp_fronteiras` | fronteiras | nenhuma janela atravessa linha; `Σ(L−3)` |
| `corp_unk` | UNK | código 3, linha/token, `IDS_INTACTOS=OK` |
| `corp_invalido` | corpus vazio/inválido | códigos 1,2,4,5,6,7,8 e precedência |
| `corp_duplicados` | dedup/conflito | códigos 9 e 10 |
| `corp_capacidade` | N=30, lotes | 30 exemplos, 5 lotes de 6, `S0=19563100` |
| `corp_lotes` | equivalência | N=6 direto; N=10 6+4; histórico igual ao oráculo |
| `corp_treino` | treino canônico | histórico, `10/10`, margens, 253/22, `9/6` |
| `corp_ordem` | ordem inversa | histórico, `8/10`, 213 diferenças |
| `corp_geracao` | geração | 5 prefixos, `PARE`, `MAXIMO`, `TEXTO` |
| `corp_determinismo_a` | execução completa | saída A |
| `corp_determinismo_b` | execução completa | saída B = A, byte a byte |
| `corp_composicao` | M1/M3/M7/M6 | `M1_IDS=OK`, `M3_OK=100`, `M7_OK=10/10` |
| `corp_pureza` | pureza | `PARAMS_INTACTOS=OK`, `IDS_INTACTOS=OK`, `SAIDA_INTACTA=OK` |

Total: **16 casos novos**; suíte **116/116**.

### 13.3 Critérios de aceitação

| AC | Verificação | Resultado exigido |
| ---: | --- | --- |
| AC1 | pré-voo | `main`, `HEAD 54ed948…`, árvore limpa, 100/100 |
| AC2 | `git status --short` | somente os arquivos autorizados |
| AC3 | `scripts/test.ps1` | `Passed: 116`, `Failed: 0`, exit `0` |
| AC4 | verificadores M1–M7 | 21/21, 19/19, 22/22, 23/23, 13/13, 16/16, exit `0` |
| AC5 | `scripts/test.ps1 -SelfTest` | `0 PASS / 1 FAIL`, exit `1` |
| AC6 | `scripts/verify-corpus-bytes.ps1` | `Checks: 18`, `Failures: 0`, exit `0` |
| AC7 | corpus | 165 bytes, SHA-256 de §3.1, 5×5 |
| AC8 | tokenização | 5 sequências de §4.2; nenhum UNK |
| AC9 | extração | 10 exemplos de §5.2; nenhuma fronteira |
| AC10 | treino | histórico de §12.1, `10/10`, margens de §12.2 |
| AC11 | parâmetros | tabela de §12.2, 253/22, `MAXIMO16=9 6` |
| AC12 | ordem | histórico inverso, `8/10`, 213 diferenças |
| AC13 | geração | 5 prefixos de §10, `PARE`/`MAXIMO` |
| AC14 | determinismo | A = B byte a byte |
| AC15 | vocabulário | 25 IDs, nenhum token novo |
| AC16 | escopo | nenhum arquivo não autorizado alterado |
| AC17 | commit/push | não executados nesta fase |

Resultado final medido em 2026-10-29: **AC1–AC17 satisfeitos**. M7 16/16 e M8
18/18, ambos exit `0`; suíte 116/116; autoteste 0/1 intencional; corpus e
determinismo inalterados. A correção autorizada de
`scripts/verify-context-bytes.ps1` está registrada em `docs/corpus-plan.md`
§12.2–12.3.

## 14. Limitações

- O corpus tem 5 frases e 10 exemplos. O modelo é uma rede linear de contexto
  K=3, não um LLM. O resultado é ajuste ao corpus, não compreensão.
- Todos os exemplos de treino são janelas vistas. A geração canônica reproduz
  janelas vistas. A sonda fora do corpus acerta 1/10 e não autoriza alegação de
  generalização.
- A margem mínima em `E=4` é 4/256. É positiva e determinística, mas pequena;
  não é robustez a mudanças de corpus ou de ordem.
- A acurácia cai de `10/10` em `E=4` para `9/10` em `E=5`. A época 4 é um ponto
  escolhido por critério objetivo, não um platô estável.
- A ordem inversa reduz a perda e reduz a acurácia; a perda agregada não é
  suficiente para selecionar o modelo.
- O corpus não contém UNK, acentos, maiúsculas, pontuação ou texto natural. A
  tokenização é sensível a qualquer variação.
- Não há leitura de arquivo em tempo de execução pelo `.por`; o builder injeta
  as linhas como literais e verifica a igualdade byte a byte com o arquivo.
- Não há commit, push, tag ou operação remota nesta fase.
