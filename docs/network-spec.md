# Especificação — Camada de saída linear para previsão do próximo token (M4)

- **Status:** implementada e verificada em 2026-10-26 (M4, E0–E7).
- **Versão:** `v1.0.0` (congelada após E0; nenhum gate disparou — §14.3).
- **Depende de:** M1 (`docs/tokenizer-spec.md` v0.2.1), que fixa o vocabulário de 25 IDs;
  M3 (`docs/embeddings-spec.md` v0.1.1), que fixa a matriz 25×4 e sua fórmula.
- **Escopo:** dada a linha de embedding de **um** token, calcular 25 escores (logits) e
  selecionar o de maior valor (argmax), com aritmética exata, saída textual verificável e
  parâmetros atualizáveis por célula.
- **Fora de escopo:** treinamento, backpropagation, softmax, probabilidades, amostragem,
  atenção, Transformer, camadas ocultas, funções de ativação, contexto de sequência,
  geração autoregressiva, leitura de arquivos, números aleatórios, bibliotecas externas.

## 1. Contrato

| Item | Definição |
| --- | --- |
| Entrada lógica | um ID de token `id` em `0..24` e o estado dos parâmetros `(pesos, vieses)`. |
| Entrada auxiliar | a linha de embedding do token, `emb[id*4 .. id*4+3]`, produzida pela M3. |
| Saída lógica | vetor de 25 `real` (logits) e/ou o índice `y` de maior logit. |
| Saída observável | linhas ASCII terminadas em `\n`, uma por consulta, conforme §8. |
| Unidade de parâmetro | `real` escalar: 100 pesos + 25 vieses = **125**. |
| Determinismo | total: nenhuma dependência de tempo, aleatoriedade, entrada do usuário ou ambiente. |
| Dependência numérica | apenas `real` (IEEE 754 binário), `%` inteiro não negativo e literais. |
| Efeito colateral | apenas escrita em stdout e mutação explícita dos vetores de parâmetros. |

O módulo é um **fragmento** (`src/rede.por`): não declara `programa` nem `inicio`, não inclui
bibliotecas e é concatenado a um driver pelos scripts de teste, exatamente como
`src/embeddings.por`.

## 2. Arquitetura

### 2.1 Forma escolhida

Uma única camada linear (projeção afim) de 4 entradas para 25 saídas:

```
logit(id, y) = b[y] + Σ_{d=0..3} W[y][d] * emb[id][d]
```

com `W` 25×4 e `b` 25. Não há camada oculta, ativação, normalização nem softmax.

### 2.2 Justificativa

1. **É a menor rede possível que ainda é uma rede.** Produz 25 escores a partir de uma
   entrada vetorial, com parâmetros aprendíveis e gradiente bem definido.
2. **É o alvo correto do próximo passo.** Um modelo de linguagem didático precisa de uma
   função `R^4 -> R^25`; a forma afim é o bloco elementar que qualquer camada futura
   substituirá ou empilhará.
3. **Não antecipa decisões de treinamento.** Sem ativação e sem softmax, a missão não fica
   presa a uma escolha de função de perda ou de inicialização pensada para treino.
4. **É verificável byte a byte.** Com a grade 1/16 nos parâmetros e nos embeddings, todo
   logit é um múltiplo exato de 1/256 (§5.3), o que permite comparação textual exata sem
   tolerância.
5. **Cabe no interpretador.** 125 `real` e 100 multiplicações por consulta; nenhum recurso
   além de arrays, funções e `%`, todos já comprovados nas M1/M3.

### 2.3 Por que não softmax

`softmax` é estritamente monótona e preserva a ordem dos logits; portanto o argmax de
`softmax(z)` é idêntico ao argmax de `z`. Nesta missão a única decisão tomada a partir dos
escores é o argmax. Introduzir `exp` e divisão em `real` adicionaria arredondamento não
especificado, sem mudar nenhuma saída observável. Softmax e probabilidades ficam para a
missão de treinamento, quando passam a ser necessários para a perda.

### 2.4 O que esta camada não é

- Não é um modelo treinado: os pesos canônicos são uma grade determinística, não aprendida.
- Não é um bigrama estatístico: não conta frequências nem consulta corpus.
- Não tem contexto: a entrada é **um** token, não uma sequência.
- Não gera texto: apenas ranqueia os 25 IDs para um token de entrada.

A limitação de expressividade é real e mensurável: a inicialização canônica produz apenas
**9 classes de argmax distintas** em 25 entradas (§6.5). Isso é aceitável e esperado; é
exatamente o que o treinamento futuro deve mudar.

## 3. Estado, layout e invariantes

### 3.1 Arrays

```portugol
real pesos[100]   // W[y][d] em y * 4 + d, y em 0..24, d em 0..3
real vieses[25]   // b[y] em y
```

Layout linear (sem arrays bidimensionais, que não foram comprovados no interpretador):

| Índice | Conteúdo |
| --- | --- |
| `pesos[y * 4 + d]` | peso da saída `y` para a dimensão `d` |
| `vieses[y]` | viés da saída `y` |

### 3.2 Constantes

```portugol
const inteiro REDE_TAM_VOCAB = 25
const inteiro REDE_ENTRADAS  = 4
const inteiro REDE_SAIDAS    = 25
const inteiro REDE_TOTAL     = 100
const inteiro REDE_PARAMS    = 125
```

`REDE_TOTAL` é o tamanho do vetor de pesos (100), não o total de parâmetros (125).
`const` exige literal inteiro — limitação já comprovada na M3.

### 3.3 Invariantes

| ID | Invariante |
| --- | --- |
| I1 | `REDE_SAIDAS * REDE_ENTRADAS == REDE_TOTAL` |
| I2 | `REDE_TOTAL + REDE_SAIDAS == REDE_PARAMS` |
| I3 | `REDE_TAM_VOCAB == REDE_SAIDAS == 25` |
| I4 | `pesos` tem exatamente 100 posições; `vieses`, 25 |
| I5 | nenhuma posição é lida fora de `0..99` / `0..24` (validação antes do acesso) |
| I6 | `inicializar_rede` não lê estado anterior (idempotente) |
| I7 | `rede_logit` e `rede_argmax` não mutam `pesos`, `vieses` nem `emb` |

I1 e I2 são verificadas em tempo de execução por `rede_imprimir_layout`; I3 e I4 são
verificadas pelo oráculo e pelos testes. O interpretador não tem `assert`.

### 3.4 Acoplamento com a M3

`REDE_ENTRADAS` **deve** ser igual a `EMB_DIM` (4). O fragmento da rede não referencia
`EMB_DIM` nem importa `src/embeddings.por`; o acoplamento é por contrato de layout e é
exercitado pelo caso de composição (§12, `net_composicao`). Se a M3 mudar de dimensão, a
rede precisa mudar junto; o teste de composição falha se isso não acontecer.

## 4. Inicialização determinística

### 4.1 Fórmulas

Para `y` em `0..24` e `d` em `0..3`:

```
p(y,d) = ((y * 7 + d * 5) % 25) - 12        // inteiro em -12..12
W[y][d] = p(y,d) / 16.0                     // grade 1/16

r(y)   = ((y * 7) % 9) - 4                  // inteiro em -4..4
b[y]   = r(y) / 16.0                        // grade 1/16
```

Todos os operandos de `%` são não negativos (`y*7 + d*5 >= 0`, `y*7 >= 0`), portanto o
resultado de `%` não depende da convenção de módulo para negativos. `p` e `r` são gravados
como inteiros e só então divididos por `16.0`; a divisão por `16.0` (não por `16`) força
aritmética `real` exata.

### 4.2 Tabela canônica de pesos

Valores decimais exatos de `W[y][d]`:

| y | d=0 | d=1 | d=2 | d=3 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | -0.75 | -0.4375 | -0.125 | 0.1875 |
| 1 | -0.3125 | 0.0 | 0.3125 | 0.625 |
| 2 | 0.125 | 0.4375 | 0.75 | -0.5 |
| 3 | 0.5625 | -0.6875 | -0.375 | -0.0625 |
| 4 | -0.5625 | -0.25 | 0.0625 | 0.375 |
| 5 | -0.125 | 0.1875 | 0.5 | -0.75 |
| 6 | 0.3125 | 0.625 | -0.625 | -0.3125 |
| 7 | 0.75 | -0.5 | -0.1875 | 0.125 |
| 8 | -0.375 | -0.0625 | 0.25 | 0.5625 |
| 9 | 0.0625 | 0.375 | 0.6875 | -0.5625 |
| 10 | 0.5 | -0.75 | -0.4375 | -0.125 |
| 11 | -0.625 | -0.3125 | 0.0 | 0.3125 |
| 12 | -0.1875 | 0.125 | 0.4375 | 0.75 |
| 13 | 0.25 | 0.5625 | -0.6875 | -0.375 |
| 14 | 0.6875 | -0.5625 | -0.25 | 0.0625 |
| 15 | -0.4375 | -0.125 | 0.1875 | 0.5 |
| 16 | 0.0 | 0.3125 | 0.625 | -0.625 |
| 17 | 0.4375 | 0.75 | -0.5 | -0.1875 |
| 18 | -0.6875 | -0.375 | -0.0625 | 0.25 |
| 19 | -0.25 | 0.0625 | 0.375 | 0.6875 |
| 20 | 0.1875 | 0.5 | -0.75 | -0.4375 |
| 21 | 0.625 | -0.625 | -0.3125 | 0.0 |
| 22 | -0.5 | -0.1875 | 0.125 | 0.4375 |
| 23 | -0.0625 | 0.25 | 0.5625 | -0.6875 |
| 24 | 0.375 | 0.6875 | -0.5625 | -0.25 |

As 25 linhas são distintas (verificado por enumeração); não há duas saídas com o mesmo
vetor de pesos.

### 4.3 Tabela canônica de vieses

| y | b[y] | y | b[y] | y | b[y] | y | b[y] | y | b[y] |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | -0.25 | 5 | 0.25 | 10 | 0.1875 | 15 | 0.125 | 20 | 0.0625 |
| 1 | 0.1875 | 6 | 0.125 | 11 | 0.0625 | 16 | 0.0 | 21 | -0.0625 |
| 2 | 0.0625 | 7 | 0.0 | 12 | -0.0625 | 17 | -0.125 | 22 | -0.1875 |
| 3 | -0.0625 | 8 | -0.125 | 13 | -0.1875 | 18 | -0.25 | 23 | 0.25 |
| 4 | -0.1875 | 9 | -0.25 | 14 | 0.25 | 19 | 0.1875 | 24 | 0.125 |

Sequência completa em `y = 0..24`:
`-0.25 0.1875 0.0625 -0.0625 -0.1875 0.25 0.125 0.0 -0.125 -0.25 0.1875 0.0625 -0.0625 -0.1875 0.25 0.125 0.0 -0.125 -0.25 0.1875 0.0625 -0.0625 -0.1875 0.25 0.125`

### 4.4 Embeddings consumidos

A rede **não** inicializa embeddings; recebe `emb` já preenchido. A M3 define
`emb[id*4+d] = ((((id*7 + d*3) % 32) - 16) / 16.0)`. Linhas usadas diretamente nos casos
desta missão:

| id | emb[id][0..3] |
| ---: | --- |
| 0 | -1.0 -0.8125 -0.625 -0.4375 |
| 1 | -0.5625 -0.375 -0.1875 0.0 |
| 7 | 0.0625 0.25 0.4375 0.625 |
| 9 | 0.9375 -0.875 -0.6875 -0.5 |
| 24 | -0.5 -0.3125 -0.125 0.0625 |

A tabela completa está em `docs/embeddings-spec.md` §4.1; o oráculo da rede recalcula a
fórmula, não lê aquela tabela.

### 4.5 Propriedades da inicialização

- Determinística e independente de ordem de chamada (sobrescreve tudo).
- Idempotente: `inicializar_rede` duas vezes produz o mesmo estado.
- Todos os valores são múltiplos de `1/16` e têm representação decimal finita.
- Não usa `aleatorio`, tempo, hash, arquivo ou entrada.

## 5. Cálculo dos logits

### 5.1 Fórmula normativa

Para `id` em `0..24` e `y` em `0..24`:

```
logit(id, y) = b[y] + Σ_{d=0..3} W[y][d] * emb[id][d]
```

Equivalente em índices lineares:

```
logit(id, y) = vieses[y] + Σ_{d=0..3} pesos[y*4 + d] * emb[id*4 + d]
```

### 5.2 Ordem de acumulação

A ordem é normativa porque afeta o sinal de zero:

```portugol
real soma = 0.0
dimensao = 0
enquanto (dimensao < REDE_ENTRADAS)
{
    soma = soma + pesos[y*4 + dimensao] * emb[id*4 + dimensao]
    dimensao = dimensao + 1
}
soma = soma + vieses[y]
retorne soma
```

Produtos são somados da esquerda para a direita, começando em `0.0`, e o viés entra por
último. Isso garante que:

- um produto `-0.0` (por exemplo `(-0.75) * 0.0`) somado a `0.0` resulte em `+0.0`;
- o viés `0.0` não introduza `-0.0`;
- nenhum logit zero seja impresso como `-0.0`.

A ordem também é irrelevante para o **valor**: a prova abaixo mostra que toda soma parcial
é exata, logo qualquer ordem produz o mesmo real.

### 5.3 Prova de exatidão

Sejam `q = emb[id][d] * 16`, `p = W[y][d] * 16` e `r = b[y] * 16`. Por construção:

- `q ∈ [-16, 15]`, `p ∈ [-12, 12]`, `r ∈ [-4, 4]`, todos inteiros;
- `emb = q/16`, `W = p/16`, `b = r/16`, todos exatos em ponto flutuante binário;
- cada produto é `p*q/256`, com `p*q ∈ [-192, 192]` — inteiro representável exatamente
  (no máximo 8 bits de significando);
- cada soma parcial é um múltiplo inteiro de `1/256` com módulo no máximo
  `4*192/256 = 3`; o resultado exato de cada adição é representável (≤ 10 bits de
  significando), logo **nenhum arredondamento ocorre**;
- o viés contribui `16r/256`, com `|16r| <= 64`;
- o numerador final

```
N(id, y) = 16*r(y) + Σ_{d=0..3} p(y,d) * q(id,d)
```

é inteiro e satisfaz `|N| <= 64 + 4*192 = 832`.

Portanto `logit = N/256`, exatamente. Consequências:

1. O resultado é independente da ordem de soma e do agrupamento.
2. Toda expansão decimal de `N/256` termina em no máximo **8 casas** (pois
   `N/256 = N*390625/10^8`).
3. A prova vale para qualquer formato binário com pelo menos 10 bits de significando e
   expoente suficiente; não depende de `real` ser `double` e sim de ser ponto flutuante
   binário.
4. Não é necessário tolerar erro: a comparação textual pode ser exata.

O que **não** está provado por construção e precisa de sonda (E0):

- que `real` no Portugol Studio seja ponto flutuante binário IEEE 754 (P3, P9);
- que a impressão use a expansão decimal mais curta que reconstrói o valor (P3);
- que a ordem de acumulação acima não produza `-0.0` (P4).

### 5.4 Faixa e zeros canônicos

Sobre os 625 pares `(id, y)` com a inicialização canônica:

| Métrica | Valor |
| --- | --- |
| menor logit | `-1.2421875` (id 4, y 0) |
| maior logit | `1.7265625` (id 18, y 10) |
| logits iguais a zero | `(id 9, y 5)`, `(id 16, y 4)`, `(id 21, y 16)` |

Os três zeros são canários de `-0.0`: se algum for impresso como `-0.0`, o formato está
errado e o caso falha.

### 5.5 Argmax e empates

Definição normativa:

```
melhor = 0
melhor_valor = logit(id, 0)
para y = 1..24:
    se logit(id, y) > melhor_valor:
        melhor_valor = logit(id, y)
        melhor = y
retorne melhor
```

Regras:

- A comparação é **estrita** (`>`); em empate, o menor `y` vence.
- O inicializador é `logit(id, 0)`, não uma constante sentinela. Usar `-1.0` seria um bug:
  há logits menores que `-1.0` (mínimo `-1.2421875`).
- O desempate é determinístico e reprodutível, mas arbitrário; a regra precisa ser mantida
  em qualquer missão futura para não invalidar os testes.
- Os 25 vetores canônicos não têm empate; a margem mínima é `2/256` (ids 4, 6, 13 e 20).
- Empates são exercitados por construção no caso `net_empate` (§12).

## 6. Dados canônicos de referência

### 6.1 Argmax por id (inicialização canônica)

| id | argmax | N máximo | margem (1/256) | logit máximo |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 218 | 12 | 0.8515625 |
| 1 | 11 | 136 | 38 | 0.53125 |
| 2 | 19 | 158 | 10 | 0.6171875 |
| 3 | 19 | 256 | 26 | 1.0 |
| 4 | 24 | 439 | 2 | 1.71484375 |
| 5 | 11 | 176 | 12 | 0.6875 |
| 6 | 1 | 108 | 2 | 0.421875 |
| 7 | 19 | 200 | 22 | 0.78125 |
| 8 | 2 | 397 | 6 | 1.55078125 |
| 9 | 10 | 429 | 38 | 1.67578125 |
| 10 | 11 | 146 | 36 | 0.5703125 |
| 11 | 19 | 144 | 6 | 0.5625 |
| 12 | 19 | 242 | 30 | 0.9453125 |
| 13 | 6 | 437 | 2 | 1.70703125 |
| 14 | 11 | 186 | 4 | 0.7265625 |
| 15 | 11 | 116 | 14 | 0.453125 |
| 16 | 19 | 186 | 18 | 0.7265625 |
| 17 | 23 | 390 | 6 | 1.5234375 |
| 18 | 10 | 442 | 50 | 1.7265625 |
| 19 | 11 | 156 | 28 | 0.609375 |
| 20 | 19 | 130 | 2 | 0.5078125 |
| 21 | 19 | 228 | 30 | 0.890625 |
| 22 | 6 | 437 | 4 | 1.70703125 |
| 23 | 0 | 200 | 4 | 0.78125 |
| 24 | 11 | 126 | 26 | 0.4921875 |

Sequência completa de argmax (`id = 0..24`), normativa:

```
0 11 19 19 24 11 1 19 2 10 11 19 19 6 11 11 19 23 10 11 19 19 6 0 11
```

### 6.2 Valores pontuais de referência

| Consulta | Valor | Observação |
| --- | ---: | --- |
| `LOGIT 0 0` | 0.8515625 | positivo simples |
| `LOGIT 0 10` | 0.625 | positivo |
| `LOGIT 3 19` | 1.0 | múltiplo inteiro de 1/256 com parte decimal `.0` |
| `LOGIT 4 24` | 1.71484375 | maior logit do id 4, margem mínima |
| `LOGIT 9 5` | 0.0 | zero canônico (canário de `-0.0`) |
| `LOGIT 9 6` | 0.45703125 | usado no caso de atualização |
| `LOGIT 16 4` | 0.0 | zero canônico |
| `LOGIT 21 16` | 0.0 | zero canônico |
| `PARAM 0 0` | -0.75 | peso negativo |
| `PARAM 0 3` | 0.1875 | peso positivo |
| `PARAM 5 2` | 0.5 | célula alterada em `net_atualizacao` |
| `PARAM 12 2` | 0.4375 | peso |
| `PARAM 24 0` | 0.375 | peso |
| `PARAM 24 3` | -0.25 | peso |
| `BIAS 0` | -0.25 | viés negativo |
| `BIAS 5` | 0.25 | viés alterado em `net_atualizacao` |
| `BIAS 7` | 0.0 | viés zero |
| `BIAS 12` | -0.0625 | viés negativo |
| `BIAS 16` | 0.0 | viés zero |
| `BIAS 24` | 0.125 | viés positivo |

### 6.3 `LOGITS` canônico do id 0

```
LOGITS=0 0.8515625 0.03125 -0.66796875 0.1953125 0.375 0.23828125 -0.16796875 -0.28125 -0.1015625 -0.80078125 0.625 0.8046875 -0.578125 -0.30078125 0.1484375 0.328125 -0.37109375 -0.77734375 0.671875 -0.1484375 0.12890625 0.015625 0.1953125 0.05859375 -0.34765625
```

### 6.4 `LOGITS` canônico do id 24

```
LOGITS=24 0.2890625 0.34375 -0.26171875 -0.0859375 0.1875 0.14453125 -0.16796875 -0.1875 0.0859375 -0.51953125 0.21875 0.4921875 -0.015625 -0.42578125 0.1171875 0.390625 -0.21484375 -0.52734375 0.234375 0.2890625 -0.12109375 -0.140625 0.1328125 0.08984375 -0.22265625
```

### 6.5 Distribuição dos argmax canônicos

| classe | ids com esse argmax | quantidade |
| ---: | --- | ---: |
| 0 | 0, 23 | 2 |
| 1 | 6 | 1 |
| 2 | 8 | 1 |
| 6 | 13, 22 | 2 |
| 10 | 9, 18 | 2 |
| 11 | 1, 5, 10, 14, 15, 19, 24 | 7 |
| 19 | 2, 3, 7, 11, 12, 16, 20, 21 | 8 |
| 23 | 17 | 1 |
| 24 | 4 | 1 |

**9 classes distintas**, histograma `0x2 1x1 2x1 6x2 10x2 11x7 19x8 23x1 24x1`.
As 16 classes nunca previstas são `3, 4, 5, 7, 8, 9, 12, 13, 14, 15, 16, 17, 18, 20, 21,
22`. Essa limitação é o argumento quantitativo para treinamento futuro: a camada tem
capacidade para 25 classes, mas a inicialização determinística usa apenas 9.

## 7. API

Todas as funções são públicas no fragmento. Prefixo `rede_` para evitar colisão com
`emb_` (M3) e com o tokenizador (M1) quando os três fragmentos são concatenados.

### 7.1 Validadores puros

```portugol
funcao logico rede_id_valido(inteiro id)        // 0 <= id < 25
funcao logico rede_saida_valida(inteiro y)      // 0 <= y < 25
funcao logico rede_dim_valida(inteiro d)        // 0 <= d < 4
```

### 7.2 Inicialização

```portugol
funcao inicializar_rede(real pesos[], real vieses[])
```

Sobrescreve as 125 posições pela §4.1. Idempotente. Não valida nada (não há índices).

### 7.3 Cálculo puro

```portugol
funcao real rede_logit(real pesos[], real vieses[], real emb[], inteiro id, inteiro y)
funcao inteiro rede_argmax(real pesos[], real vieses[], real emb[], inteiro id)
```

Pré-condições (responsabilidade do chamador, verificadas apenas nos `imprimir_*`):
`rede_id_valido(id)`, `rede_saida_valida(y)`, `emb` com 100 posições preenchidas.
Não escrevem nada, não mutam nada.

### 7.4 Impressão com validação

| Função | Saída em caso válido | Erros possíveis |
| --- | --- | --- |
| `rede_imprimir_info()` | `INFO=25 4 125` (usa `REDE_TAM_VOCAB`, `REDE_ENTRADAS`, `REDE_PARAMS`) | nenhum |
| `rede_imprimir_layout()` | `LAYOUT=OK` ou `LAYOUT=ERRO` (OK se I1 e I2 valem) | nenhum |
| `rede_imprimir_logits(pesos, vieses, emb, id)` | `LOGITS=<id> <25 logits>` | `ID_INVALIDO` |
| `rede_imprimir_logit(pesos, vieses, emb, id, y)` | `LOGIT=<id> <y> <logit>` | `ID_INVALIDO`, `SAIDA_INVALIDA` |
| `rede_imprimir_argmax(pesos, vieses, emb, id)` | `ARGMAX=<id> <y>` | `ID_INVALIDO` |
| `rede_imprimir_peso(pesos, y, d)` | `PARAM=<y> <d> <valor>` | `SAIDA_INVALIDA`, `DIMENSAO_INVALIDA` |
| `rede_imprimir_bias(vieses, y)` | `BIAS=<y> <valor>` | `SAIDA_INVALIDA` |
| `rede_imprimir_validadores(id, y, d)` | três linhas `VALIDO=...` | nenhum (reporta validade) |

Assinaturas completas:

```portugol
funcao rede_imprimir_info()
funcao rede_imprimir_layout()
funcao rede_imprimir_logits(real pesos[], real vieses[], real emb[], inteiro id)
funcao rede_imprimir_logit(real pesos[], real vieses[], real emb[], inteiro id, inteiro y)
funcao rede_imprimir_argmax(real pesos[], real vieses[], real emb[], inteiro id)
funcao rede_imprimir_peso(real pesos[], inteiro y, inteiro dimensao)
funcao rede_imprimir_bias(real vieses[], inteiro y)
funcao rede_imprimir_validadores(inteiro id, inteiro y, inteiro dimensao)
```

`rede_imprimir_validadores` emite, nesta ordem:

```
VALIDO=ID <0|1>
VALIDO=SAIDA <0|1>
VALIDO=DIM <0|1>
```

Ela usa um auxiliar interno `funcao inteiro rede_bit(logico valor)` (1 para verdadeiro,
0 para falso). `rede_bit` não faz parte do contrato público e não é usada pelos testes
diretamente.

### 7.5 Mutação

```portugol
funcao rede_definir_peso(real pesos[], inteiro y, inteiro dimensao, real valor)
funcao rede_definir_bias(real vieses[], inteiro y, real valor)
```

Pré-condições: índices válidos. Gravam `valor` sem clamp, sem arredondamento e sem
normalização. Não emitem saída. São a futura porta de entrada do treinamento.

## 8. Formato observável

### 8.1 Gramática (Formato A)

```
linha      := "INFO=" int " " int " " int
            | "LAYOUT=" ("OK" | "ERRO")
            | "LOGITS=" int (SP num){25}
            | "LOGIT=" int " " int " " num
            | "ARGMAX=" int " " int
            | "PARAM=" int " " int " " num
            | "BIAS=" int " " num
            | "VALIDO=" ("ID" | "SAIDA" | "DIM") " " bit
            | "ERRO=" codigo
num        := "-" ? ( "0" | [1-9][0-9]* ) "." [0-9]{1,8}
int        := "-" ? ( "0" | [1-9][0-9]* )
bit        := "0" | "1"
codigo     := "ID_INVALIDO" | "SAIDA_INVALIDA" | "DIMENSAO_INVALIDA"
```

Toda linha termina com exatamente um `\n` (LF). Não há linha vazia, espaço no fim,
`+`, notação científica, `NaN`, `Infinity` nem `-0.0`.

O limite de 8 casas vem da §5.3: todo logit é `N/256`; `1/256 = 0.00390625` (8 casas).
Valores gravados por `rede_definir_*` podem não estar na grade (§10) e, nesse caso, a
garantia de 8 casas não se aplica — por isso os casos de mutação só imprimem valores
conhecidos ou logits de linhas não afetadas.

### 8.2 Exemplos

```
INFO=25 4 125
LAYOUT=OK
ARGMAX=7 0
LOGIT=9 5 0.0
PARAM=0 0 -0.75
BIAS=7 0.0
VALIDO=SAIDA 0
ERRO=DIMENSAO_INVALIDA
```

### 8.3 Formatos alternativos pré-aprovados

O Formato A é **provisório** até E0. Se as sondas falharem, aplica-se um destes formatos,
registrado no log de evidências:

| Formato | Gatilho | Mudança |
| --- | --- | --- |
| **N-B** | P3/P9: impressão de 8 casas não é exata/estável | `W` e `b` passam a inteiros (`p`, `r`), `LOGIT` vira `(16r + Σpq)/16`; 1–4 casas; reutiliza a gramática da M3 |
| **N-C** | P5: linha de 25 valores excede o limite do console | `LOGITS=` é substituído por 25 linhas `LOGIT=`; os casos 3, 4, 12 e 13 mudam de forma, mas continuam 14 casos |

Formato N-C **não** é usado para esconder divergência aritmética: se o valor calculado
diferir do oráculo inteiro, a missão para como BLOQUEADA (§14.3, G2). Comparar rótulos em
vez de números seria uma regressão de verificação, não uma alternativa válida.

### 8.4 Condição de congelamento

O Formato A congela quando P3, P4, P5 e P9 passam com os valores canônicos desta
especificação. Antes disso, nenhum caso é escrito em definitivo.

## 9. Erros

### 9.1 Códigos

| Código | Significado | Condição |
| --- | --- | --- |
| `ID_INVALIDO` | ID de token fora do vocabulário | `id < 0` ou `id >= 25` |
| `SAIDA_INVALIDA` | índice de saída inválido | `y < 0` ou `y >= 25` |
| `DIMENSAO_INVALIDA` | dimensão de embedding inválida | `d < 0` ou `d >= 4` |

### 9.2 Precedência

A validação é feita **antes** de qualquer acesso a array e na ordem declarada:

| Chamada | Ordem |
| --- | --- |
| `rede_imprimir_logits(id)` | `id` |
| `rede_imprimir_argmax(id)` | `id` |
| `rede_imprimir_logit(id, y)` | `id` → `y` |
| `rede_imprimir_peso(y, d)` | `y` → `d` |
| `rede_imprimir_bias(y)` | `y` |
| `rede_imprimir_validadores(id, y, d)` | nenhuma (reporta os três) |

Consequências normativas:

- `LOGIT(-1, 25)` produz **um** `ERRO=ID_INVALIDO` (não `SAIDA_INVALIDA`).
- `PARAM(-1, 4)` produz `ERRO=SAIDA_INVALIDA` (não `DIMENSAO_INVALIDA`).
- `PARAM(0, -1)` e `PARAM(0, 4)` produzem `ERRO=DIMENSAO_INVALIDA`.
- Cada chamada inválida emite **exatamente uma** linha `ERRO=...` e retorna sem acessar
  os vetores. Não há saída parcial antes do erro.
- `rede_logit` e `rede_argmax` não validam: com índice inválido o comportamento é
  indefinido (pode abortar). Os testes só as chamam com índices válidos.

## 10. Atualização de parâmetros

- `rede_definir_peso` e `rede_definir_bias` gravam qualquer `real`, inclusive fora da grade
  1/16 e com muitas casas decimais.
- Não há clamp, normalização, validação de faixa nem arredondamento.
- A garantia de exatidão da §5.3 vale **por linha**: um logit é exato se todos os
  `W[y][*]` e `b[y]` que ele usa estão na grade canônica. Um peso como `1.7` não é exato
  em binário; o valor impresso é a menor expansão decimal que reconstrói o `real`, mas
  somas com ele podem arredondar.
- Por isso, os testes de mutação:
  1. imprimem o valor gravado (`PARAM`, `BIAS`) para provar que a gravação é fiel;
  2. imprimem logits de linhas **não afetadas** pela mutação (ex.: `LOGIT 9 6` após
     alterar `W[5][2]` e `b[5]`);
  3. nunca comparam o logit de uma linha com peso `1.7` contra um decimal exato.
- `inicializar_rede` restaura o estado canônico e é o único mecanismo de reset.

Essa separação é deliberada: o treinamento futuro vai produzir pesos arbitrários e exigirá
comparação com tolerância (ou truncamento para uma grade). A missão atual não finge que
isso já está resolvido.

## 11. Oráculo independente

O verificador `scripts/verify-network-bytes.ps1` recalcula tudo a partir das fórmulas,
sem ler `.expected` e sem reutilizar constantes do código Portugol:

1. `q(id,d) = ((id*7 + d*3) % 32) - 16`
2. `p(y,d) = ((y*7 + d*5) % 25) - 12`
3. `r(y) = ((y*7) % 9) - 4`
4. `N(id,y) = 16*r(y) + Σ p(y,d)*q(id,d)` — aritmética **inteira** (`[int]`/`[long]`),
   nunca `[double]`, para não herdar o erro que está sendo testado.
5. `logit = N/256` formatado por um formatador próprio:

```
sinal = N < 0 ? "-" : ""
a = abs(N)
parte_inteira = a / 256        (divisão inteira)
resto = a % 256
se resto == 0: sinal + parte_inteira + ".0"
senão: sinal + parte_inteira + "." + (resto * 390625 com 8 dígitos, zeros à direita removidos)
```

O formatador é escrito no verificador e é independente do formatador do interpretador.
Ele é validado contra valores conhecidos (`1/256`, `1.0`, `0.0`, `-1.2421875`) antes de
comparar qualquer caso.

O oráculo também:

- recalcula a tabela `W`, a tabela `b`, os 25 argmax, as margens, os zeros e a faixa, e
  falha se qualquer valor não bater com as tabelas desta especificação (proteção contra
  erro de transcrição no próprio spec);
- simula as mutações de `net_atualizacao`, `net_reinicializacao` e `net_empate` no estado
  em memória, com os mesmos valores gravados;
- para `net_composicao`, trata a linha `IDS=1 9` como contrato da M1 (texto `programa se`)
  e calcula os argmax de 1 e 9 pela rede.

O verificador **não** pode importar `src/rede.por`, chamar as funções do fragmento nem ler
`temp/network-tests/*.expected` para decidir o resultado esperado.

## 12. Casos obrigatórios

Nomes e propósitos (a matriz completa, com entradas e saídas, está em
`docs/network-plan.md` §7):

| # | Caso | Verifica |
| ---: | --- | --- |
| 1 | `net_info` | `INFO` e `LAYOUT` |
| 2 | `net_parametros` | inicialização de `W` e `b` em células escolhidas |
| 3 | `net_logits_0` | vetor completo de 25 logits do id 0 |
| 4 | `net_logits_24` | vetor completo de 25 logits do id 24 |
| 5 | `net_logit_pontual` | 8 logits pontuais, incluindo os três zeros |
| 6 | `net_argmax_todos` | argmax dos 25 IDs |
| 7 | `net_validadores` | fronteiras `-1`, `0`, `24`, `25` e `3`, `4` para `d` |
| 8 | `net_erros` | 12 erros + precedência + estado intacto |
| 9 | `net_empate` | desempate por menor `y` em três cenários |
| 10 | `net_atualizacao` | setters gravam valores fora da grade; linha vizinha intacta |
| 11 | `net_reinicializacao` | `inicializar_rede` restaura o estado canônico |
| 12 | `net_determinismo_a` | 25 vetores completos, processo A |
| 13 | `net_determinismo_b` | 25 vetores completos, processo B |
| 14 | `net_composicao` | tokenizador + embeddings + rede no mesmo programa |

Regras:

- Exatamente 14 arquivos `.expected` em `temp/network-tests/`, sem faltas nem extras.
- `net_determinismo_a` e `_b` têm drivers idênticos e `.expected` idênticos; a execução
  como processos separados é o que prova o determinismo.
- Nenhum caso depende de tempo, ambiente, entrada do usuário ou ordem de execução.
- Nenhum caso imprime logit de linha cujo peso foi alterado para fora da grade.

## 13. Critérios de aceitação

| ID | Critério |
| --- | --- |
| AC1 | `HEAD` de partida `370c296`, branch `main`, árvore limpa, `origin/main` sincronizado. |
| AC2 | Apenas os arquivos autorizados mudam: `src/rede.por`, `scripts/build-network-tests.ps1`, `scripts/verify-network-bytes.ps1`, `scripts/test.ps1` (bloco aditivo), `docs/network-spec.md`, `docs/network-plan.md`. |
| AC3 | `src/rede.por` é ASCII puro, fragmento (sem `programa`/`inicio`), sem `inclua`, UTF-8 sem BOM, LF. |
| AC4 | Constantes exatamente `25`, `4`, `25`, `100`, `125` com os nomes da §3.2. |
| AC5 | `inicializar_rede` reproduz a §4.1 e é idempotente. |
| AC6 | `rede_logit` implementa a §5.1 na ordem da §5.2. |
| AC7 | Todo logit canônico é múltiplo de `1/256`; prova registrada e conferida pelo oráculo inteiro. |
| AC8 | `rede_argmax` usa `>` estrito; empate resolve para o menor `y`; mínimo de margem canônico é `2/256`. |
| AC9 | Códigos e precedência de erro da §9 são observados nos testes. |
| AC10 | Toda saída casa com a gramática da §8.1; nenhum `-0.0`. |
| AC11 | Existem exatamente 14 casos `net_*` em `temp/network-tests/`. |
| AC12 | `scripts/test.ps1` termina `58 PASS / 0 FAIL`, exit `0`. |
| AC13 | `scripts/verify-bytes.ps1` continua `21/21`, exit `0`, sem alteração. |
| AC14 | `scripts/verify-embedding-bytes.ps1` continua `19/19`, exit `0`, sem alteração. |
| AC15 | `scripts/verify-network-bytes.ps1` passa com o oráculo independente; o número de verificações é registrado no log. |
| AC16 | `scripts/test.ps1 -SelfTest` termina `0 PASS / 1 FAIL` e exit `1`. |
| AC17 | `net_determinismo_a` e `_b`, executados em processos separados e duas vezes cada, produzem bytes idênticos entre si e entre execuções. |
| AC18 | Nenhum uso de `aleatorio`, tempo, arquivo, teclado, acesso a rede ou biblioteca em `src/rede.por`. |
| AC19 | Hashes de `src/tokenizador.por`, `src/embeddings.por`, `scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`, `scripts/build-embedding-tests.ps1`, `scripts/verify-embedding-bytes.ps1` iguais aos de `HEAD`. |
| AC20 | `temp/network-tests/` e `temp/e0-net/` são artefatos ignorados; nada deles é rastreado. |
| AC21 | Nenhum commit, push, tag ou alteração de remoto. |
| AC22 | Log de evidências (§13 do plano) preenchido com comandos e resultados reais. |
| AC23 | Nenhum código de treinamento, softmax, atenção, Transformer ou geração. |
| AC24 | O veredito final só é PRONTO se AC1–AC23 forem comprovados; caso contrário, PARCIAL ou BLOQUEADO com a lista do que faltou. |

## 14. Suposições do interpretador e gates de E0

### 14.1 Sondas

| ID | Sonda | Usada por |
| --- | --- | --- |
| P1 | duas funções/parâmetros `real[]` na mesma assinatura; passagem por referência | toda a API |
| P2 | `%` com operandos não negativos; `const` com literal inteiro | init |
| P3 | impressão de `1/256`: `0.00390625`, `0.8515625`, `1.7265625`, `-1.2421875`, `11.0`, `0.0` | §5.3, §8 |
| P4 | somar `0.0` a um produto que resulta em `-0.0` e depois somar `0.0` | imprime `0.0`, não `-0.0` | zeros |
| P5 | linha de ~300 caracteres com 25 `real`; `escreva` repetido em laço | `LOGITS` |
| P6 | `real[100]` e `real[25]` simultâneos, com mutação visível ao chamador | estado |
| P7 | funções que retornam `real` e `inteiro`; `retorne` cedo | API |
| P8 | laços aninhados 25×4 com `%` | init |
| P9 | `p/16.0`, `q/16.0`, produto e soma batem com o oráculo inteiro em 625 pares | §5.3 |
| P10 | `(0.0 - 0.75) * 0.0` e acúmulo; sinal de zero | §5.2 |
| P11 | concatenação de três fragmentos sem colisão de nomes; `inclua` no topo | composição |
| P12 | `const` duplicada com nome distinto entre fragmentos | composição |
| P13 | custo de 25 argmax + 25 vetores completos no console | determinismo |
| P14 | BOM/CRLF/EOF na concatenação; fonte ASCII | empacotamento |

### 14.2 Gates

| Gate | Condição | Ação pré-aprovada |
| --- | --- | --- |
| G1 | P3 ou P9 falha na grade 1/256 | adotar Formato N-B (parâmetros inteiros, logits na grade 1/16); se N-B também falhar, BLOQUEAR |
| G2 | P9 divergir do oráculo inteiro | **parar** como BLOQUEADO; não ajustar valores, não adotar N-C |
| G3 | P1 falha (duas arrays na mesma assinatura) | usar um único `real estado[225]`: `W` em `0..99`, `b` em `100..124`, cópia da linha de embedding em `125..224`; todas as funções passam a receber só `estado[]` e o driver copia `emb[id*4+d]` para `estado[125+d]` antes de consultar |
| G4 | P5 falha (linha longa) | adotar Formato N-C (25 linhas `LOGIT`); mantêm-se 14 casos |
| G5 | P6/P13 falha | P13 (tempo): reduzir o determinismo a `ARGMAX` + logit máximo, mantendo 14 casos. P6 (arrays de 100/25 posições): **parar** BLOQUEADO; não há layout alternativo verificável |
| G6 | P11/P12 falha por colisão | renomear com prefixo `rede_`/`REDE_` (já previsto) |
| G7 | P2 falha | reescrever a init com literais e redução manual; se impossível, BLOQUEAR |

### 14.3 Regra de congelamento

A especificação só é considerada congelada (`v1.0.0`) depois que P3, P4, P5 e P9 passam.
Se qualquer gate mudar o formato ou o layout, a spec é revisada para `v0.2.0` **antes** de
implementar, e o log registra o gatilho. Nenhuma mudança de formato pode ocorrer
silenciosamente no meio da implementação.

**Resultado (E0, 2026-10-26):** P1–P14 PASS; P3, P4, P5 e P9 PASS; nenhum gate disparou.
Formato A e layout `real pesos[100]` + `real vieses[25]` mantidos. Spec congelada em
`v1.0.0` antes de E1.

## 15. Limitações e caminho para treinamento

| Limitação | Consequência | Missão futura |
| --- | --- | --- |
| Sem softmax | não há probabilidades; só ranking | perda e gradiente exigirão softmax/log-softmax |
| Sem camada oculta | capacidade restrita a uma transformação afim de 4 dimensões | empilhar camadas |
| Inicialização não treinada | 9 classes de argmax em 25 entradas | treinar `W` e `b` |
| Contexto de 1 token | não modela sequência | janela de contexto / atenção |
| Valores fora da grade | comparação byte a byte deixa de valer | testes com tolerância ou quantização |
| `%` e `real` apenas | sem `exp`, `log`, `sqrt` comprovados | sondar funções matemáticas |

O treinamento futuro pode usar exatamente o layout atual:

```
dL/dW[y][d] = delta[y] * emb[id][d]
dL/db[y]    = delta[y]
```

Nada nesta missão calcula `delta`, perda ou atualização automática; `rede_definir_peso` e
`rede_definir_bias` apenas gravam valores fornecidos pelo chamador.

## 16. Decisões registradas

| ID | Decisão |
| --- | --- |
| D1 | camada única afim 4→25, sem ativação e sem softmax |
| D2 | `W` em `pesos[100]`, `b` em `vieses[25]` (alternativa: `estado[225]` com a linha de `emb` copiada em `125..224`, gate G3) |
| D3 | init `p/16`, `r/16` com as fórmulas da §4.1 |
| D4 | acúmulo começando em `0.0`, viés por último |
| D5 | argmax com `>` estrito, varrendo `1..24` a partir do índice 0 |
| D6 | erros `ID_INVALIDO`, `SAIDA_INVALIDA`, `DIMENSAO_INVALIDA`; precedência da §9.2 |
| D7 | impressão e cálculo separados (`rede_imprimir_*` valida; `rede_logit` não) |
| D8 | setters não validam e não fazem clamp (pré-condição do chamador) |
| D9 | prefixo `rede_`/`REDE_` para evitar colisão na composição |
| D10 | Formato A provisório, congelado após E0; N-B/N-C pré-aprovados |
| D11 | oráculo em aritmética inteira, sem ler `.expected` |
| D12 | determinismo por 25 vetores completos em dois processos |
| D13 | nenhuma alteração em módulos anteriores; nenhum commit/push |
| D14 | `REDE_ENTRADAS` deve igualar `EMB_DIM`; acoplamento verificado por composição |
