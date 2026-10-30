# Especificação - Avaliação de generalização do modelo contextual (M9)

- **Status:** implementação e execução concluídas em 2026-10-30 (E0-E7).
  Veredito científico: `SEM_EVIDENCIA` (`QUALIFICACAO=FRACA`); veredito técnico
  da entrega: `PRONTA` (após correção de escopo em M7/M8, §11.1). Evidências em
  `docs/evaluation-plan.md` §9, §12 e §14.
  Nenhum commit ou push foi feito.
- **Versão:** `v0.1.1`.
- **Modelo avaliado:** estado determinístico produzido pela M8
  (`ctx_inicializar` + `corp_treinar` com o corpus congelado, `E=4`).
- **Missões reutilizadas:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0), M5
  (`docs/training-spec.md` v1.0.0), M6 (`docs/generation-spec.md` v1.0.0), M7
  (`docs/context-spec.md` v1.0.0) e M8 (`docs/corpus-spec.md` v0.1.0).
- **Fora de escopo:** alterar `src/contexto.por`, `src/corpus.por`, o corpus, os
  verificadores M1-M8, `scripts/test.ps1`, `README.md` ou `AGENTS.md`; treinar
  redes neurais novas; softmax, perplexidade, amostragem ou atenção; ampliar o
  vocabulário; ler arquivos em tempo de execução pelo `.por`; commit, push, tag
  ou operação remota.

## 1. Contrato

| Item | Definição |
| --- | --- |
| Entrada lógica | corpus de treino congelado da M8 e um holdout fixo de pares `(contexto de 3 IDs, alvo)`. |
| Entrada física | `corpus/m8-corpus-v1.txt` (treino) e literais de avaliação definidos em §4. |
| Modelo | `w16[300]`, `b16[25]`; uma camada afim `12 -> 25`; nenhuma mudança de arquitetura. |
| Estado | determinístico: `ctx_inicializar` seguido de `corp_treinar(..., E=4)` sobre os 10 exemplos de treino. |
| Unidade | uma predição top-1 de um par `(contexto, alvo)`. |
| Saída observável | relatório ASCII definido em §7.5, comparado byte a byte. |
| Aleatoriedade | nenhuma; sem tempo, `real`, locale ou ordem não fixada. |
| Mutação | avaliação estritamente somente leitura sobre `w16`/`b16`. |
| Critério de generalização | somente acurácia em contextos inéditos (conjunto C) contra baselines pré-registrados; nunca acurácia em exemplos vistos. |

## 2. O que a avaliação prova e não prova

| Conceito | O que é | O que não é |
| --- | --- | --- |
| Exemplo visto | par `(c,t)` presente nos 10 pares de treino | generalização |
| Contexto conhecido com alvo diferente | `c` visto, `(c,t')` ausente do treino | capacidade de obedecer a um novo alvo; o modelo não recebe o alvo na entrada |
| Contexto inédito | tripla `c` ausente dos 10 contextos de treino | texto natural, sintaxe ou semântica |
| Sequência inédita | sequência completa ausente do corpus | garantia de que todos os seus contextos são inéditos |
| Generalização medida | acurácia top-1 em contextos inéditos, acima dos baselines | compreensão de Portugol ou de linguagem |
| Memorização | acurácia nos 10 pares vistos | generalização, mesmo que seja 10/10 |

A distinção central desta missão: uma sequência nova pode conter contextos
vistos (conjunto B). Portanto, "sequência inédita" não é sinônimo de "contexto
inédito". Somente o conjunto C é disjointo por contexto e serve como evidência
primária. O conjunto A e a parte vista de B medem memorização; o conjunto D é
um controle de consistência, não uma prova de generalização.

## 3. Modelo e estado de partida

O estado avaliado é o mesmo da M8, sem qualquer ajuste:

```
w16, b16 = ctx_inicializar()
corp_treinar(w16, b16, entradas_treino, alvos_treino, 10, 4, historico)
```

O corpus tem 5 linhas, 25 tokens e 10 janelas `K=3`. O histórico canônico
observado na demonstração da M8 é:

```
8404936 1341188 651091 509249 436118
```

e os 10 exemplos de treino são, na ordem do corpus:

| # | Contexto | Alvo | Texto do contexto -> alvo |
| ---: | --- | ---: | --- |
| 1 | `1 3 17` | 22 | programa inicio escreva -> verdadeiro |
| 2 | `3 17 22` | 24 | inicio escreva verdadeiro -> pare |
| 3 | `2 3 17` | 23 | funcao inicio escreva -> falso |
| 4 | `3 17 23` | 24 | inicio escreva falso -> pare |
| 5 | `9 22 12` | 17 | se verdadeiro faca -> escreva |
| 6 | `22 12 17` | 24 | verdadeiro faca escreva -> pare |
| 7 | `9 23 10` | 18 | se falso senao -> leia |
| 8 | `23 10 18` | 24 | falso senao leia -> pare |
| 9 | `11 22 12` | 18 | enquanto verdadeiro faca -> leia |
| 10 | `22 12 18` | 24 | verdadeiro faca leia -> pare |

O corpus congelado tem 165 bytes e SHA-256
`d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113`.
O estado não é persistido em arquivo; ele é reconstruído deterministicamente a
cada execução. A avaliação não altera o corpus, a ordem, `E=4` nem a taxa de
aprendizado.

## 4. Protocolo de separação dos dados

### 4.1 Sem conjunto de validação

Não há conjunto de validação. A M8 já congelou todos os hiperparâmetros
relevantes: corpus, ordem dos exemplos, `E=4`, inicialização, taxa `1/8`,
quantização e arquitetura. Não existe seleção de modelo a fazer. Um conjunto de
validação seria usado uma vez e descartado, ou pior, convidaria a ajustes
posteriores ao teste. O conjunto C é usado uma única vez para o veredito final;
qualquer resultado negativo é relatado como tal.

### 4.2 Definições de igualdade

- **Contexto:** tripla ordenada de IDs `(a,b,c)`, comparada posição a posição.
- **Par:** `(contexto, alvo)`, comparado por igualdade exata dos quatro IDs.
- **Contexto visto:** pertence ao conjunto dos 10 contextos de treino.
- **Par visto:** pertence ao conjunto dos 10 pares de treino.
- **Contexto conhecido com alvo diferente:** contexto visto e par ausente.
- **Contexto inédito:** contexto ausente dos 10 contextos de treino.
- **Sequência inédita:** sequência completa ausente das 5 linhas do corpus.
- **Contagem:** cada predição é uma unidade; não há deduplicação. O conjunto C
  tem 32 contextos distintos. A e B_VISTO são o mesmo conjunto de 10 pares em
  ordens diferentes e não devem ser somados como se fossem 20 pares únicos.

### 4.3 Conjunto A - exemplos vistos (memorização)

Conjunto A = os 10 pares da tabela de §3, na mesma ordem. Serve para verificar
que o pipeline ajustou o treino e para medir memorização. **Não é evidência de
generalização.**

### 4.4 Conjunto B - sequências novas com contextos mistos

Cinco sequências de 7 tokens. Cada uma produz 4 predições (posições 0..3 do
contexto; o alvo é o token seguinte). Em cada sequência, as duas primeiras
predições usam contextos inéditos e as duas últimas usam pares vistos. O
conjunto tem 10 pares vistos + 10 contextos inéditos.

| # | Sequência (7 IDs) | Alvos das 4 predições | Tipos |
| ---: | --- | --- | --- |
| B1 | `4 7 9 22 12 17 24` | `22 12 17 24` | `INEDITO INEDITO VISTO VISTO` |
| B2 | `5 13 11 22 12 18 24` | `22 12 18 24` | `INEDITO INEDITO VISTO VISTO` |
| B3 | `6 14 9 23 10 18 24` | `23 10 18 24` | `INEDITO INEDITO VISTO VISTO` |
| B4 | `8 15 1 3 17 22 24` | `3 17 22 24` | `INEDITO INEDITO VISTO VISTO` |
| B5 | `7 16 2 3 17 23 24` | `3 17 23 24` | `INEDITO INEDITO VISTO VISTO` |

B_VISTO é uma permutação de A: os 10 pares são exatamente os mesmos. A
verificação deve exigir predições idênticas por par em A e B_VISTO. B_INEDITO
tem 10 contextos inéditos, mas foi construído em torno de janelas vistas; é
diagnóstico, não a evidência primária.

### 4.5 Conjunto C - contextos inéditos (evidência primária)

Oito sequências de 7 tokens, construídas para que **todos os 32 contextos das
posições 0..3 sejam inéditos**. As 8 sequências também são inéditas. Todas
terminam em 24 (`pare`), portanto 8 das 32 predições têm alvo 24; as outras 24
têm alvo diferente de 24. Nenhum contexto de C compartilha sequer um sufixo de
2 tokens com os contextos de treino (verificado estruturalmente nesta fase).

| # | Sequência (7 IDs) | Alvos das 4 predições |
| ---: | --- | --- |
| C1 | `4 7 5 13 6 18 24` | `13 6 18 24` |
| C2 | `8 19 14 21 15 5 24` | `21 15 5 24` |
| C3 | `6 16 1 20 2 13 24` | `20 2 13 24` |
| C4 | `7 11 4 19 5 20 24` | `19 5 20 24` |
| C5 | `13 8 21 16 14 2 24` | `16 14 2 24` |
| C6 | `15 9 20 3 10 6 24` | `3 10 6 24` |
| C7 | `5 14 2 8 19 11 24` | `8 19 11 24` |
| C8 | `20 6 15 7 21 4 24` | `7 21 4 24` |

C é deliberadamente difícil: não há sobreposição de 3 tokens nem de sufixo de
2 tokens com o treino. Isso mede transferência para contextos quase sem
similaridade local, não generalização gramatical ampla. O resultado deve ser
interpretado nesse limite.

### 4.6 Conjunto D - contexto conhecido com alvo diferente

Para cada um dos 10 contextos de treino, o alvo é trocado por
`t' = (t % 24) + 1`. A regra nunca produz 0 e nunca é igual a `t`.

| # | Contexto | Alvo de treino `t` | Alvo contrafactual `t'` |
| ---: | --- | ---: | ---: |
| D1 | `1 3 17` | 22 | 23 |
| D2 | `3 17 22` | 24 | 1 |
| D3 | `2 3 17` | 23 | 24 |
| D4 | `3 17 23` | 24 | 1 |
| D5 | `9 22 12` | 17 | 18 |
| D6 | `22 12 17` | 24 | 1 |
| D7 | `9 23 10` | 18 | 19 |
| D8 | `23 10 18` | 24 | 1 |
| D9 | `11 22 12` | 18 | 19 |
| D10 | `22 12 18` | 24 | 1 |

D é um controle de consistência. Como o modelo não recebe o alvo na entrada,
`pred(c)` é o mesmo para A e D. Se A acerta 10/10, então D só pode acertar
quando `t == t'`, o que nunca ocorre. Portanto `D_ACERTO = 0/10` e
`D_ADERENCIA_AO_TREINO = 10/10` são consequências esperadas, não um fracasso
do modelo. D serve para expor que o modelo não "obedece" a um alvo novo sem
retreino.

### 4.7 Contagens e unidades

| Conjunto | Unidades | Pares vistos | Contexto visto / alvo diferente | Contextos inéditos | Alvos 24 |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | 10 | 10 | 0 | 0 | 5 |
| B_VISTO | 10 | 10 | 0 | 0 | 5 |
| B_INEDITO | 10 | 0 | 0 | 10 | 0 |
| C | 32 | 0 | 0 | 32 | 8 |
| C_SEM_PARE | 24 | 0 | 0 | 24 | 0 |
| D | 10 | 0 | 10 | 0 | 1 |

Total de unidades: 72 predições; 62 pares distintos (A e B_VISTO são o mesmo
conjunto em ordem diferente; C_SEM_PARE é um subconjunto de C). Não existe
acurácia agregada única: misturar A, B, C e D produziria um número dominado por
memorização e sem significado. Cada conjunto é relatado separadamente.

### 4.8 Regras de ausência de vazamento

| ID | Regra | Verificação |
| --- | --- | --- |
| L1 | O treino contém exatamente os 10 pares de §3, extraídos por `corp_extrair` do corpus congelado. | hash do corpus + reconstrução independente das janelas |
| L2 | Nenhum par de C, B_INEDITO ou D é passado a `corp_treinar`, `corp_extrair` ou `ctx_executar`. | análise estática do módulo de avaliação + revisão do driver |
| L3 | C tem 0 contextos vistos e 0 pares vistos; os 32 contextos são distintos. | auditoria independente sobre os literais |
| L4 | B tem exatamente 10 pares vistos e 10 contextos inéditos; nenhum par conhecido com alvo diferente. | auditoria independente |
| L5 | D tem 10 contextos vistos, 10 pares ausentes, `t' != t`, `1 <= t' <= 24`. | auditoria independente |
| L6 | Nenhum ID fora de `0..24`; nenhum `0` (UNK) nos conjuntos de avaliação. | validação do builder |
| L7 | Nenhuma sequência de B ou C é uma linha do corpus. | comparação exata |
| L8 | A e B_VISTO produzem as mesmas predições por par. | verificação em tempo de execução |

O módulo de avaliação não contém chamadas a `corp_treinar`, `corp_extrair` ou
`ctx_executar`. O treino ocorre apenas no driver de construção do estado, sobre
os 10 pares de §3. Essa separação é verificada por regex e por revisão, além do
teste de não mutação.

### 4.9 Pré-registro e hash do holdout

O holdout foi congelado antes de qualquer execução do modelo sobre ele. A
serialização canônica está no Apêndice A: ASCII, LF, um LF final, 50 linhas,
724 bytes. O SHA-256 é:

```
e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10
```

O hash foi calculado apenas a partir dos literais, sem executar o modelo. A
auditoria estrutural desta fase (contagens, vazamento, sufixos, distribuição de
alvos) também não executou o modelo. Qualquer alteração posterior nos literais
invalida este pré-registro: deve criar `EVAL-V2`, com novo hash, e os resultados
de `EVAL-V1` continuam a ser relatados.

**Limite honesto:** o treino da M8 já estava concluído quando o holdout foi
escrito. Não é possível, retroativamente, fazer um split clássico "antes do
treino". O que este protocolo garante é que o modelo é uma função determinística
do corpus congelado e que o holdout foi fixado por hash antes de qualquer
predição. O risco remanescente é viés de desenho (escolher sequências depois de
ver resultados); ele é mitigado pelo hash e pela proibição de ajustar o holdout.

## 5. Métricas

### 5.1 Acurácia top-1

Para `N` predições e `A` acertos:

```
A = soma_i [ argmax(c_i) == t_i ]
BP = r(10000 * A, N)
```

`r` é a função existente `ctx_div_arredondada` (arredondamento half-up, sinal
preservado). `BP` é a acurácia em pontos-base (`10000` = 100%). A acurácia
também é impressa como `A/N` para leitura direta. Empates no argmax seguem a
regra da M7: comparação estrita, menor ID vence.

### 5.2 Perda

A perda escalada por exemplo é definida na M7:

```
d256(n,y) = Z256(c_n,y) - 256*[y == t_n]
S_b       = soma_{n no lote b} soma_{y=0..24} d256(n,y)^2
L         = soma_b S_b / (131072 * N)
```

`S_b` é sempre calculado em lotes de no máximo 6 exemplos, porque
`ctx_perda_escalada` não valida `n` e o limite de faixa da M7 é
`S_b <= 1.926.758.400 < 2^31`. O valor `S_b` de cada lote é impresso. A média
é impressa em milésimos inteiros:

```
m_b  = floor(1000 * S_b / (131072 * n_b))
M    = floor( soma_b (m_b * n_b) / N )
```

`m_b` é calculado por divisão longa inteira, sem materializar `1000*S_b` (que
estouraria 32 bits). O erro de `M` em relação ao piso exato de `1000*L` é menor
que 1 milésimo. `S_b` e `N` são impressos para permitir a reconstrução exata por
um oráculo de precisão arbitrária.

Para baselines discretos (memorização e majoritário) não há perda escalada
definida; a coluna de perda é `-1`. Para estados parametrizados (não treinado,
canônico, rótulo permutado, ordem inversa), a perda é calculada normalmente.

### 5.3 Margem e matriz de confusão

Para cada predição:

```
ZP = Z256(c, pred)
ZT = Z256(c, alvo)
MZ = ZP - ZT
```

`MZ >= 0` quando a predição está errada, por causa da regra de desempate: se
`ZP == ZT` e `pred != alvo`, o argmax teria escolhido o menor ID. Por isso a
margem não é uma "confiança" calibrável; é apenas uma diferença inteira
observável. A matriz de confusão é esparsa: apenas linhas
`CONF <alvo> <pred> <n>` com `n > 0`, ordenadas por alvo e depois por pred.

### 5.4 Baselines

| Baseline | Definição | A | B | C | D |
| --- | --- | ---: | ---: | ---: | ---: |
| Não treinado | `ctx_inicializar`, sem `corp_treinar` | medido | medido | medido | medido |
| Memorização | se `c` é visto, prediz o alvo de treino; senão prediz 24 | 10/10 | 10/20 | 8/32 | 0/10 |
| Majoritário | prediz sempre 24 | 5/10 | 5/20 | 8/32 | 1/10 |
| Rótulo permutado | treina com `pi(t) = (t % 24) + 1` e avalia nos alvos originais | medido | - | medido | - |
| Ordem inversa | treina com os 10 exemplos em ordem reversa | medido | - | medido | - |

Os valores de A, B, C e D para memorização e majoritário são exatos e
pré-registrados; o verificador deve reproduzi-los. O baseline não treinado é
medido em E0 e congelado antes do teste; não é presumido.

O baseline de memorização usa fallback 24 porque 24 é a classe majoritária do
treino (5/10). Em C, todos os contextos são inéditos, então o lookup cai
sempre no fallback: 8/32. Em B, acerta os 10 pares vistos e erra os 10 inéditos:
10/20. Em D, prediz o alvo de treino e erra os 10 contrafactuais: 0/10.

### 5.5 Comparação treino x teste

A tabela de resultados deve conter, para cada estado e conjunto:

```
RESUMO <estado> <conjunto> <N> <acertos> <BP> <milesimos>
DELTA_BP <conjunto> <BP_estado> <BP_baseline> <diferenca>
```

`DELTA_BP` é a diferença em pontos-base; `2000` = 20 pontos percentuais. A
comparação primária é `CANONICO/C` contra `NAO_TREINADO/C` e `MEMORIZACAO/C`.
A comparação `CANONICO/A` contra `MEMORIZACAO/A` mede apenas se o pipeline
reproduz o treino.

### 5.6 Tabela de erros e exemplos individuais

Para cada predição do estado canônico e do não treinado, imprimir uma linha
`EX` com contexto, alvo, predição, acerto, `ZP`, `ZT`, `MZ`, alvo de treino
(quando D), tipo (quando B) e as palavras do alvo e da predição. A tabela de
erros é derivada filtrando `ok=0`; não há uma segunda fonte de verdade.

### 5.7 Por que não softmax nem perplexidade

A perda da M7/M8 é um erro quadrático escalado sobre `Z256`, não uma
log-verossimilhança. Aplicar softmax mudaria a semântica do modelo e exigiria
exponenciais e `real`, contrariando o contrato inteiro e a repetibilidade byte a
byte. Perplexidade não tem definição natural aqui. A acurácia top-1 e a perda
escalada existente são suficientes para a pergunta desta missão.

### 5.8 Limites de capacidade e overflow

| Grandeza | Limite | Justificativa |
| --- | ---: | --- |
| exemplos por chamada `ctx_perda_escalada` | 6 | `S_b <= 1.926.758.400` (M7) |
| `S` por exemplo | 321.126.400 | `25 * 12.845.056` |
| `S` por lote de 6 | 1.926.758.400 | `< 2^31 - 1` |
| `m_b` | 2.450.000 | `L <= 2450` por exemplo |
| soma ponderada `m_b * n_b` | 156.800.000 | `N <= 64` |
| acertos | 64 | buffer fixo |
| `BP` | 10000 | `10000 * 64 = 640.000` |
| `|Z256|` | 3328 | estado válido da M7 |
| `|MZ|` | 6656 | diferença de dois `Z256` |
| confusão | 625 posições | `25 * 25` |
| checksum de estado | 727.600 | `16*(1+...+300) + 16*(1+...+25)` |
| unidades de avaliação | 64 | `AVAL_MAX` |

O acumulador de `S` nunca é global; ele é por lote. O total exato só existe no
oráculo de precisão arbitrária. Nenhum valor é armazenado em `real`.

## 6. Experimentos e controles

| ID | Estado | Treino | Conjuntos | Propósito |
| --- | --- | --- | --- | --- |
| X0 | não treinado | nenhum | A, B, C, D | baseline inferior |
| X1 | canônico | corpus, ordem natural, `E=4` | A, B, C, D | resultado primário |
| X2 | memorização | lookup, sem gradiente | A, B, C, D | baseline de memorização |
| X3 | majoritário | sempre 24 | A, B, C, D | baseline trivial |
| X4 | rótulo permutado | `pi(t)`, mesma arquitetura e `E=4` | A, C | controle negativo |
| X5 | ordem inversa | 10 exemplos invertidos, `E=4` | A, C | sensibilidade à ordem |
| X6 | canônico repetido | igual a X1, segunda execução | A, B, C, D | repetibilidade byte a byte |
| X7 | canônico, permutações | sem treino novo | C, 6 permutações por contexto | sensibilidade à ordem na inferência |

### 6.1 Resultados esperados, declarados antes da execução

| Experimento | Expectativa pré-registrada |
| --- | --- |
| X1/A | 10/10 se o treino convergiu; qualquer valor menor indica inconsistência com a M8 |
| X1/B_VISTO | predições idênticas a X1/A por par (mesma permutação de pares) |
| X1/B_INEDITO | diagnóstico; sem limiar |
| X1/C | desconhecido; é o resultado primário |
| X1/D | `D_ACERTO = 0/10` e `D_ADERENCIA_AO_TREINO = 10/10` se A = 10/10 |
| X4/A | >= 8/10 (o pipeline consegue memorizar rótulos arbitrários) |
| X4/C | próximo do baseline; se `>= 15/32`, o controle falhou e o experimento é inválido |
| X5/A | >= 8/10; o valor exato é relatado |
| X5/C | desconhecido; a diferença para X1 é relatada, não corrigida |
| X6 | bytes idênticos a X1 em todos os conjuntos |
| X7 | número de contextos cuja predição muda sob permutação; sem limiar |

### 6.2 Critério de sucesso primário

Sejam:

```
A_C  = acertos de X1 em C (0..32)
U_C  = acertos de X0 em C
M_C  = acertos de X2 em C  (= 8, pré-registrado)
BP_C = r(10000 * A_C, 32)
BP_U = r(10000 * U_C, 32)
BP_M = r(10000 * M_C, 32)  (= 2500)
```

Há **evidência de generalização** somente se todas as condições valerem:

1. `BP_C - BP_M >= 2000` (20 pontos percentuais acima da memorização);
2. `BP_C - BP_U >= 2000` (20 pontos percentuais acima do não treinado);
3. `A_C >= 15` (equivalente a >= 46,875% em 32 predições);
4. o conjunto C foi usado integralmente, sem exclusões ou filtros;
5. validade: sem vazamento, sem mutação, determinismo e regressão M1-M8 verdes.

O limiar de 15/32 decorre de 20 pp sobre `M_C = 8/32`; se `U_C` for maior que
`M_C`, a condição 2 pode elevar o limiar. O valor exato é calculado, não
arredondado para baixo. Em C, o baseline majoritário também acerta 8/32;
`M_C` é o máximo entre memorização e majoritário (ambos 8). Se os dois
divergirem, o maior prevalece.

### 6.3 Robustez secundária e qualificação

O conjunto `C_SEM_PARE` (24 predições, nenhum alvo 24) é relatado
separadamente. Como 24 é um alvo terminal e trivial, a qualificação do
resultado usa os acertos não terminais:

- `QUALIFICACAO=FORTE` se `A_C_SEM_PARE >= 10` (>= 41,7% de 24);
- `QUALIFICACAO=FRACA` caso contrário.

A qualificação não altera o critério primário de §6.2; ela apenas torna
explícito se o sinal vem majoritariamente de `pare`. O limiar 10/24 é
pré-registrado e fica bem acima da classe mais frequente desse subconjunto
(2/24). Se o critério primário falhar, o veredito é `SEM_EVIDENCIA` mesmo que
`C_SEM_PARE` seja alto.

### 6.4 Vereditos

| Veredito | Condição |
| --- | --- |
| `GENERALIZACAO` | §6.2 satisfeito; registrar `QUALIFICACAO=FORTE` ou `FRACA` |
| `SEM_EVIDENCIA` | válido, mas §6.2 não satisfeito |
| `INVALIDO` | vazamento, mutação, não determinismo, controle negativo `>= 15/32` ou regressão falhando |

`SEM_EVIDENCIA` é um resultado legítimo e deve ser publicado como tal. Não é
permitido alterar C, o limiar ou o baseline depois de ver o resultado. Também
não é permitido chamar A = 10/10, B_VISTO = 10/10 ou D_ADERENCIA = 10/10 de
generalização.

### 6.5 Limite estatístico

32 predições são poucas. O limiar de 20 pp corresponde a 7 predições adicionais
sobre o baseline de memorização. O resultado deve ser lido como um efeito
descritivo em um holdout fixo, não como uma estimativa precisa da acurácia
populacional. Nenhum teste de hipótese é usado na decisão; a margem foi
pré-registrada para evitar ajuste post hoc.

## 7. Arquitetura

### 7.1 Reúso verificado das APIs existentes

| Necessidade | API existente | Comportamento verificado | Lacuna |
| --- | --- | --- | --- |
| Montar contexto de um exemplo | `ctx_contexto_de_exemplo(entradas, i, c16)` | lê a tripla e aplica `e16`; não altera `w16`/`b16` | nenhuma |
| Predição top-1 | `ctx_argmax(w16, b16, c16)` | comparação estrita, menor ID em empate; somente leitura | nenhuma |
| Perda por lote | `ctx_perda_escalada(w16, b16, entradas, alvos, n)` | soma `d256^2`; **não valida `n`** | lote <= 6 no chamador |
| Contagem de acertos | `ctx_acertos(w16, b16, entradas, alvos, n)` | laço de `argmax`; não valida `n` | lote <= 6 por precaução |
| Logit escalado | `ctx_z256(w16, b16, c16, y)` | leitura pura | nenhuma |
| Divisão arredondada | `ctx_div_arredondada(num, den)` | half-up, sinal preservado | nenhuma |
| Palavra do vocabulário | `ctx_escrever_palavra(token)` | imprime `UNK` para 0 e a palavra para 1..24 | nenhuma |
| Treino | `corp_treinar(w16, b16, entradas, alvos, n, epocas, hist)` | valida `n <= 30`, `epocas <= 32`; muta `w16`/`b16` | usar só no driver de estado |
| Perda total | `corp_perda_total(...)` | lotes de 6, retorna 16 se `S > 2.000.000.000` | não serve para 32 unidades; usar lotes próprios |
| Extração do corpus | `corp_extrair(...)` | valida e extrai janelas `K=3` | usar só no treino |

Todas as APIs foram lidas no código real (`src/contexto.por` e
`src/corpus.por`). Nenhuma fórmula de embedding, forward, perda, atualização ou
geração será reimplementada no módulo de avaliação.

### 7.2 Módulo novo `src/avaliacao.por`

Fragmento sem `programa`/`inicio`, concatenado depois de `src/contexto.por` e
`src/corpus.por`. Responsabilidades:

1. validar `n`, IDs e parâmetros antes de avaliar;
2. copiar lotes de até 6 para buffers fixos;
3. chamar `ctx_acertos`, `ctx_argmax`, `ctx_perda_escalada` e `ctx_z256`
   somente para leitura;
4. calcular `BP`, `S_b`, `m_b`, `M` e `MZ` com inteiros;
5. preencher a confusão esparsa;
6. imprimir o relatório no formato de §7.5;
7. imprimir um checksum de estado antes/depois para o teste de não mutação.

API sugerida (provisória; o contrato obrigatório é o comportamento e o formato):

```por
const inteiro AVAL_MAX = 64
const inteiro AVAL_LOTE = 6
const inteiro AVAL_ESCALA = 131072
const inteiro AVAL_S_MAX_LOTE = 1926758400

funcao inteiro aval_div_piso(inteiro num, inteiro den)
funcao inteiro aval_milesimos(inteiro s, inteiro den)
funcao inteiro aval_checksum(inteiro w16[], inteiro b16[])
funcao logico aval_ids_validos(inteiro entradas[], inteiro alvos[], inteiro n)
funcao inteiro aval_copiar_lote(inteiro entradas[], inteiro alvos[],
                                inteiro base, inteiro tam,
                                inteiro lote_entradas[], inteiro lote_alvos[])
funcao inteiro aval_avaliar(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[], inteiro n,
                            inteiro conf[], inteiro saida[])
funcao inteiro aval_margem(inteiro w16[], inteiro b16[],
                           inteiro entradas[], inteiro i,
                           inteiro alvo, inteiro pred)
funcao inteiro aval_relatorio(cadeia estado, cadeia conjunto,
                              inteiro w16[], inteiro b16[],
                              inteiro entradas[], inteiro alvos[], inteiro n,
                              inteiro modo)
```

Layout de `saida[]` (tamanho 16): `saida[0] = acertos`, `saida[1] = n_lotes`,
`saida[2..12] = S_b` (até 11 lotes), `saida[13..15]` reservados. Códigos de
erro previstos: `21` `N_INVALIDO`, `22` `ID_INVALIDO`, `23` `PARAMS_INVALIDOS`,
`24` `CATEGORIA_INVALIDA`, `25` `S_FORA_DA_FAIXA`, `26` `BUFFER_INSUFICIENTE`.
Nenhum código existente da M7/M8 é alterado.

`modo`: `0` normal (A/C), `1` D (imprime alvo de treino), `2` B (imprime
`VISTO`/`INEDITO`). A impressão usa `escreva` e `ctx_escrever_palavra`, sem
`real`, sem `\t`, sem locale.

### 7.3 Representação dos conjuntos

O `.por` não lê arquivos em tempo de execução. Os conjuntos são literais
`inteiro` gerados pelo builder:

```
inteiro train_e[30]   // 10 contextos * 3
inteiro train_t[10]
inteiro a_e[30]       // mesma coisa que train
inteiro a_t[10]
inteiro b_seq[35]     // 5 sequências * 7
inteiro c_seq[56]     // 8 sequências * 7
inteiro d_e[30]
inteiro d_t[10]       // alvo contrafactual
inteiro d_orig[10]    // alvo de treino, para diagnóstico
```

O driver expande cada sequência de 7 tokens nas 4 predições das posições
0..3. Não há tokenização em tempo de execução para B/C/D: os IDs já são
literais. A tokenização da M1 é usada apenas para o corpus de treino e para
imprimir palavras.

### 7.4 Prevenção de vazamento

- **Build-time:** o builder recalcula as janelas do corpus, compara com
  `train_e/train_t`, rejeita qualquer contexto de C presente no treino, rejeita
  qualquer par de D presente no treino, rejeita IDs fora de `0..24` e `0` nos
  conjuntos de avaliação.
- **Runtime:** o módulo de avaliação não chama `corp_treinar`, `corp_extrair`
  nem `ctx_executar`. O driver chama `corp_treinar` uma única vez, com os 10
  pares de treino, antes de qualquer avaliação.
- **Estático:** o verificador procura no módulo por `corp_treinar`,
  `corp_extrair`, `ctx_executar` e por atribuições `w16[...] =` / `b16[...] =`.
  Qualquer ocorrência reprova.
- **Tempo de execução:** o estado completo (325 valores) é impresso antes e
  depois de cada conjunto; o verificador compara byte a byte.

### 7.5 Formato do relatório

ASCII puro, uma linha por registro, LF, sem espaços à direita, sem `real`.
Linhas, nesta ordem:

```
AVAL V1
ESTADO <NAO_TREINADO|CANONICO|ROTULO_PERMUTADO|ORDEM_INVERSA|MEMORIZACAO|MAJORITARIO>
TREINO <n>
W16 <y> <12 inteiros>            (25 linhas; omitido em baselines discretos)
B16 <25 inteiros>                (omitido em baselines discretos)
CHECK <estado> MUTACAO <OK|FALHA|NA>
CHECK <estado> ACERTOS <OK|FALHA>
RESUMO <estado> <A|B|B_VISTO|B_INEDITO|C|C_SEM_PARE|D> <N> <acertos> <BP> <milesimos|-1>
PERDA <estado> <conjunto> <lote> <n_lote> <S>
EX <estado> <conjunto> <indice> <pos> <a> <b> <c> <alvo> <pred> <ok> <ZP> <ZT> <MZ> <alvo_treino|-1> <tipo|-> <palavra_alvo> <palavra_pred>
CONF <estado> <conjunto> <alvo> <pred> <n>
DELTA_BP <conjunto> <BP_estado> <BP_baseline> <diferenca>
W16_FIM <y> <12 inteiros>        (25 linhas; omitido em baselines discretos)
B16_FIM <25 inteiros>            (omitido em baselines discretos)
FIM
```

Para o teste de não mutação, o driver imprime o bloco `W16`/`B16` no início e
um bloco idêntico `W16_FIM`/`B16_FIM` antes de `FIM`; o verificador compara os
dois blocos byte a byte. O SHA-256 do estado é calculado sobre os bytes ASCII
das 26 linhas iniciais (`W16 0` a `W16 24` e `B16`), LF, com um LF final.

Regras:

- `indice` é 1-based dentro do conjunto; `pos` é 0..3 para sequências e 0 para
  pares.
- `tipo` é `VISTO` ou `INEDITO` em B; `-` nos demais.
- `alvo_treino` só é diferente de `-1` em D.
- `EX` é impresso para os estados `NAO_TREINADO` e `CANONICO` em todos os
  conjuntos; para os demais estados, apenas `RESUMO`, `PERDA` e `CONF`.
- `CONF` é impresso para A, B, C e D do estado canônico; para os demais, no
  mínimo para C.
- `DELTA_BP` compara o estado canônico com `MEMORIZACAO` e `NAO_TREINADO` em C,
  e com `MEMORIZACAO` em A/B/D.
- Nenhuma linha depende de ordem de hash, tempo, PID ou ambiente.

### 7.6 Contrato de bytes

- `.por` de entrada: ASCII, LF, sem BOM.
- `.expected`: ASCII, LF, exatamente um LF final, sem CR, sem BOM.
- Saída do interpretador: remover um `0x0C` inicial e o epílogo exato
  `\nPrograma finalizado\r\n\r\nPressione ENTER para continuar\r\n`; o restante
  deve ser byte a byte igual ao `.expected`.
- Duas execuções independentes do mesmo caso devem produzir o mesmo SHA-256.
- O relatório não contém `NaN`, `-0`, `Infinity`, notação científica, vírgula
  decimal, acentos ou caracteres fora de `0x20..0x7E` e `0x0A`.

## 8. Matriz de testes

Os 116 testes existentes são preservados sem alteração. Os testes novos ficam
em um runner separado (`scripts/test-evaluation.ps1`) e em
`temp/evaluation-tests/`. Nenhum caso novo é inserido em `scripts/test.ps1`
nesta fase; a razão está em `docs/evaluation-plan.md` §3.

| Caso | Tipo | Cobertura | Oráculo | Chave esperada |
| --- | --- | --- | --- | --- |
| `eval_separacao` | verificação PowerShell | hash, contagens, vazamento, B/D | literais independentes | 724 bytes, SHA `e8aa354e...`, 0 vazamentos |
| `eval_nao_treinado` | `.por` | init + métricas A/B/C/D | O1/O2 | estado inicial canônico; sem mutação |
| `eval_treinado` | `.por` | estado canônico + relatório completo | O1/O2 | A = 10/10; C medido |
| `eval_baselines` | `.por` | lookup + majoritário | O1 | 10/10, 10/20, 8/32, 0/10; 5/10, 5/20, 8/32, 1/10 |
| `eval_controle_rotulo` | `.por` | `pi(t)` | O1 | A >= 8/10; C < 15/32 |
| `eval_controle_ordem` | `.por` | ordem inversa | O1 | A >= 8/10; C relatado |
| `eval_ordem_permutacoes` | `.por` | 6 permutações por contexto | O1 | contagem de mudanças |
| `eval_limites` | `.por` | `n=0`, `n=64`, ID inválido, `S` máximo, denominador 0 | O1/O3 | códigos 21..26 |
| `eval_determinismo_a` | `.por` | execução completa | bytes | SHA-256 |
| `eval_determinismo_b` | `.por` | repetição de A | bytes | SHA-256 igual a A |
| `eval_regressao` | PowerShell | `scripts/test.ps1` 116/116 + M1-M8 | logs | 116 PASS / 0 FAIL |

Cada caso `.por` valida também:

- nenhuma mutação de `w16`/`b16` (estado completo antes/depois);
- soma dos `ok` das linhas `EX` igual a `acertos`;
- `BP` e `milesimos` dentro dos limites;
- nenhuma linha fora da gramática;
- A e B_VISTO com predições iguais por par.

## 9. Oráculos independentes

| Oráculo | Implementação | O que verifica | Independência |
| --- | --- | --- | --- |
| O1 | PowerShell inteiro de 32 bits | init, treino, forward, argmax, perda, métricas, relatório | não lê `.expected` nem a saída do `.por` |
| O2 | PowerShell com `BigInteger` | soma exata de `S`, `m_b`, total e limites | aritmética diferente, sem overflow |
| O3 | literais calculados à mão | subconjunto de 2 exemplos de A e 2 de C | não usa O1/O2 |
| O4 | `src/avaliacao.por` | execução real | quarta derivação, comparada com O1/O2/O3 |

O1 e O2 não podem importar funções do módulo `.por`. O builder pode usar O1
para gerar `.expected`, mas o verificador recalcula com O1 e O2 e compara com a
saída real; um erro compartilhado entre builder e verificador só seria pego por
O2/O3. O2 é um auditor de agregação, não uma segunda implementação do modelo.

## 10. Critérios de aceitação

| ID | Critério | Evidência |
| --- | --- | --- |
| AC1 | Somente os arquivos autorizados da fase de implementação foram criados/alterados. | `git status --short`: 8 `??` + 2 ` M` (apenas os 10 autorizados) |
| AC2 | `scripts/test.ps1` continua 116/116, exit 0, sem edição. | V12: 116/0/116, exit 0; hash e tamanho congelados em V1 |
| AC3 | O runner de avaliação passa todos os casos, exit 0. | `Passed: 11 Total: 11`, exit 0 |
| AC4 | Hash do holdout `e8aa354e...`, 724 bytes, 0 vazamentos. | V2 e V4 verdes |
| AC5 | Estado canônico reproduzido; A = 10/10; nenhuma mutação. | V6, V10 e `RESUMO CANONICO A 10 10 10000 332` |
| AC6 | Métricas de C iguais em O1, O2 e `.por`. | V8: 4/32, `BP=1250`, perda 1530 em O1/O2/O3 |
| AC7 | Baselines exatos: 10/10, 10/20, 8/32, 0/10 e 5/10, 5/20, 8/32, 1/10. | V9 verde |
| AC8 | Controle negativo: A >= 8/10 e C < 15/32. | 9/10 e 2/32 |
| AC9 | Determinismo: A = B byte a byte; sem `real`; ASCII/LF. | V11 verde, SHA-256 `f36fb839...` |
| AC10 | M1-M8 sem regressão; M8 18/18 e M7 16/16 uma vez em E7. | M8 18/18 (1169 s), M7 16/16 (462 s), ambos exit 0; M1-M6 verdes; suíte 116/116 |
| AC11 | Veredito de §6.4 emitido com os números reais, inclusive negativo. | `docs/evaluation-plan.md` §12: `SEM_EVIDENCIA` |
| AC12 | Nenhum commit, push, tag ou branch na fase de implementação sem autorização. | `HEAD` ainda `6f6ec0e`, árvore sem commit |

## 11. Arquivos da implementação (autorizados e criados)

| Arquivo | Ação | Papel |
| --- | --- | --- |
| `src/avaliacao.por` | novo | orquestração somente leitura e relatório |
| `scripts/eval-datasets.ps1` | novo | literais canônicos A/B/C/D + serialização + hash |
| `scripts/eval-oracle.ps1` | novo | O1 (32 bits) e O2 (BigInteger) |
| `scripts/build-evaluation-tests.ps1` | novo | gera `.por` e `.expected` |
| `scripts/test-evaluation.ps1` | novo | executa os casos e compara bytes |
| `scripts/verify-evaluation-bytes.ps1` | novo | V1-V13, hash, vazamento, oráculos, suíte 116 |
| `docs/evaluation-plan.md` | novo nesta fase; atualizado em E7 | plano e evidências E0-E7 |
| `docs/evaluation-spec.md` | novo nesta fase; atualizado em E7 | contrato e status final |
| `scripts/verify-context-bytes.ps1` | autorizado na correção de compatibilidade | allowlist V1 do M7 + 9 caminhos |
| `scripts/verify-corpus-bytes.ps1` | autorizado na correção de compatibilidade | allowlist V1 do M8 + 9 caminhos + pin do M7 |
| `temp/evaluation-tests/*` | gerado | casos e logs, ignorados pelo Git |

**Não autorizados (permanecem intocados):** `src/contexto.por`, `src/corpus.por`, `corpus/`,
`scripts/test.ps1`, `scripts/build-*.ps1` de M1-M8,
`README.md`, `AGENTS.md` e `tests/`.

### 11.1 Correção de compatibilidade das allowlists

As V1 de M7/M8 comparavam `git status --short` com uma lista literal do estado
de trabalho de suas missões; os 8 arquivos do M9 apareciam como "fora do
escopo". A ampliação autorizada acrescentou somente esses 8 caminhos (mais a
linha `" M scripts/verify-corpus-bytes.ps1"`) às duas allowlists e atualizou o
pin do verificador M7:

- `verify-context-bytes.ps1`: novo blob
  `200b911fd3e15d43df28b1ca1942dc318359bbd7`.
- `verify-corpus-bytes.ps1` e `verify-evaluation-bytes.ps1`: pin atualizado para
  esse blob; 0 divergências nos 18 hashes congelados de cada um.

Nenhuma verificação matemática, hash de módulo, contagem ou resultado esperado
foi alterado. A prova de patch mínimo (blobs reconstruídos iguais aos pré-patch),
os testes direcionados e os resultados oficiais estão em
`docs/evaluation-plan.md` §14.

## 12. Limitações e interpretação

1. O corpus tem 5 linhas e 10 exemplos; o modelo tem 325 parâmetros. Qualquer
   resultado positivo é limitado a esse vocabulário de 25 tokens e a essa
   família de frases.
2. C não compartilha nem 3-gramas nem sufixos de 2 tokens com o treino. É um
   teste de transferência difícil, não de generalização gramatical ampla.
3. 32 predições são poucas; o intervalo de incerteza é largo. O limiar é
   descritivo e pré-registrado, não uma inferência populacional.
4. O holdout foi escrito após o treino da M8; o hash mitiga, mas não elimina,
   viés de desenho.
5. O modelo não recebe o alvo na entrada. D não pode medir "obediência a um
   alvo novo"; mede apenas que a predição é função do contexto.
6. Não há validação cruzada nem teste com corpus maior. Deixar uma linha do
   corpus de fora e re-treinar seria outro experimento, não a avaliação do
   estado congelado da M8.
7. Um resultado `SEM_EVIDENCIA` é informativo: mostra que o ajuste de 10
   exemplos não se transfere para contextos quase disjuntos. Ele não deve ser
   escondido nem "corrigido" com novos testes escolhidos depois.

## Apêndice A - Serialização canônica do holdout

ASCII, LF, um LF final, 50 linhas, 724 bytes. SHA-256
`e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10`.
As linhas `T` são o treino, `A` o conjunto visto, `B`/`C` as sequências e `D`
os pares contrafactuais (`contexto`, `alvo de treino`, `alvo contrafactual`).

```
EVAL-V1
TRAIN 10
T 1 3 17 22
T 3 17 22 24
T 2 3 17 23
T 3 17 23 24
T 9 22 12 17
T 22 12 17 24
T 9 23 10 18
T 23 10 18 24
T 11 22 12 18
T 22 12 18 24
A 10
A 1 3 17 22
A 3 17 22 24
A 2 3 17 23
A 3 17 23 24
A 9 22 12 17
A 22 12 17 24
A 9 23 10 18
A 23 10 18 24
A 11 22 12 18
A 22 12 18 24
B 5
B 4 7 9 22 12 17 24
B 5 13 11 22 12 18 24
B 6 14 9 23 10 18 24
B 8 15 1 3 17 22 24
B 7 16 2 3 17 23 24
C 8
C 4 7 5 13 6 18 24
C 8 19 14 21 15 5 24
C 6 16 1 20 2 13 24
C 7 11 4 19 5 20 24
C 13 8 21 16 14 2 24
C 15 9 20 3 10 6 24
C 5 14 2 8 19 11 24
C 20 6 15 7 21 4 24
D 10
D 1 3 17 22 23
D 3 17 22 24 1
D 2 3 17 23 24
D 3 17 23 24 1
D 9 22 12 17 18
D 22 12 17 24 1
D 9 23 10 18 19
D 23 10 18 24 1
D 11 22 12 18 19
D 22 12 18 24 1
END
```
