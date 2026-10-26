# Especificação — Primeiro treinamento supervisionado (M5)

- **Versão:** 1.0.0 (congelada em E0; nenhum valor canônico mudou na execução)
- **Status:** executada e verificada. Implementação em `src/treino.por`; casos em
  `temp/training-tests` (gerados por `scripts/build-training-tests.ps1`); verificação
  independente por `scripts/verify-training-bytes.ps1` (23/23, exit `0`).
  Evidências completas na §18.
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0).
- **Plano de execução:** `docs/training-plan.md`.
- **Fora de escopo:** Transformer, atenção, contexto, geração autoregressiva,
  embeddings treináveis, softmax, probabilidades, perplexidade, commit e push.

## 1. Contrato

Esta missão define **um** mecanismo de aprendizado supervisionado para previsão do
próximo token, executável no interpretador do Portugol Studio, com resultado
verificável byte a byte.

O contrato é:

1. receber pares `(entrada, alvo)` de IDs de token e um número de épocas;
2. ajustar **somente** `W` (100 pesos) e `b` (25 vieses) da camada afim da M4;
3. manter os embeddings da M3 **congelados**;
4. reduzir uma perda escalar mensurável no conjunto fixo;
5. provar que a redução decorre de mudança correta de parâmetros, e não apenas de
   "executar sem erro";
6. ser determinístico: duas execuções independentes produzem os mesmos bytes;
7. não alterar nenhum módulo anterior.

O entregável original desta missão de planejamento eram exatamente dois arquivos:
`docs/training-spec.md` e `docs/training-plan.md`. A execução posterior (E0–E7,
aprovada em 26/10/2026) adicionou apenas `src/treino.por`,
`scripts/build-training-tests.ps1`, `scripts/verify-training-bytes.ps1` e um bloco
aditivo em `scripts/test.ps1`; nenhum módulo anterior foi tocado.

### 1.1 Critério de "aprendeu"

Executar sem erro **não** é evidência. A evidência mínima é o conjunto:

| Evidência | Medida |
| --- | --- |
| perda cai | `S0 = 3.674.036` → `S5 = 27.804` (−99,2432%) |
| acurácia sobe | `0/4` → `2/4` (época 1) → `4/4` (época 2 em diante) |
| parâmetros mudam | `114/125` (91 `W` + 23 `b`) |
| mudança é dirigida | o logit do alvo cresce nos quatro exemplos e vira o máximo |
| gradiente confere | `125/125` diferenças centrais exatas; `GRAD_SOMA = -8.960` |
| determinismo | dois processos independentes, saída idêntica |
| não regressão | 58 testes anteriores + 12 novos = 70/70 |

## 2. Decisões de arquitetura

### 2.1 Modelo

Continua exatamente o da M4: uma camada afim `4 → 25`, sem ativação, sem camada
oculta e sem softmax.

```
z(id, y) = Σ_{d=0..3} W[y][d] · e(id, d) + b[y]
e(id, d) = (((id·7 + d·3) mod 32) − 16) / 16      (M3, congelado)
```

- `id ∈ 0..24`; `y ∈ 0..24`; `d ∈ 0..3`.
- `predição(id) = argmax_y z(id, y)`, com desempate pelo menor `y`.
- Apenas `W` e `b` são treináveis: **125 parâmetros**.
- Os 100 valores de `e` são constantes durante todo o treinamento.

### 2.2 Por que os embeddings ficam congelados

1. A M3 é contrato congelado; alterá-la invalidaria 19 testes e o verificador de bytes.
2. Treinar a tabela exigiria retropropagar pelo índice (uma escolha discreta), o que
   não é uma operação derivável e não cabe no escopo.
3. Com 125 parâmetros livres o conjunto de 4 pares já é ajustável (4/4), então
   treinar embeddings não é necessário para provar o laço.
4. O objetivo é validar o mecanismo de treinamento, não maximizar qualidade.

**Decisão explícita:** embeddings **congelados**; `src/embeddings.por` não é tocado.

### 2.3 Perda: MSE sobre logits ou entropia cruzada?

Comparação nas dimensões que importam para este repositório:

| Critério | MSE sobre logits | Entropia cruzada com softmax |
| --- | --- | --- |
| Gradiente | `∂L/∂z = (z − t)/N` | `∂L/∂z = (softmax(z) − t)/N` |
| Primitivas | `+`, `−`, `·`, `/` | `exp` e, para a perda, `log` |
| Exatidão | polinomial; exata na grade 1/16 | razão de exponenciais; irracional |
| Saída observável | logits (já é o contrato da M4) | probabilidades (ninguém consome) |
| Calibração | não fornece | fornece |
| Teste | comparação inteira exata | exigiria tolerância |
| Complexidade | uma linha | estabilização, `max`, normalização, `log` |

O runtime do Portugol Studio expõe `Matematica.potencia`, `raiz`, `arredondar` e
`logaritmo`, mas **não expõe `exp`**. Implementar `exp` por série truncada exigiria
escolher truncamento, tratar estouro e importar erro de aproximação para dentro do
laço de treinamento. Isso destruiria a propriedade mais valiosa do projeto:
saídas observáveis exatas, comparáveis byte a byte, sem tolerância.

**Decisão:** MSE sobre logits, sem softmax:

```
L = (1 / (2N)) · Σ_{n=0..N−1} Σ_{y=0..24} (z(entrada[n], y) − t[n][y])²
t[n][y] = 1 se y = alvo[n], senão 0
```

O gradiente por exemplo é `δ(n, y) = z(entrada[n], y) − t[n][y]`, e a atualização
por exemplo é `W ← W − η·δ·e`, `b ← b − η·δ`.

**Custo aceito:** MSE pune todos os 25 logits, inclusive os já corretos, e não
maximiza a margem diretamente. Para 4 exemplos e uma camada linear isso é
irrelevante: a perda cai 99,24% e a acurácia chega a 4/4. Se uma missão futura
precisar de probabilidades calibradas, a comparação acima deve ser refeita com um
`exp` provado e tolerância explícita.

### 2.4 Por que aritmética inteira

Todo o estado de treinamento é mantido em **numeradores inteiros sobre 16**:

```
W[y][d] = W16[y][d] / 16        b[y] = b16[y] / 16
e(id,d) = e16(id,d) / 16        z(id,y) = Z256(id,y) / 256
```

Como `W`, `b` e `e` estão na grade 1/16, `z` está na grade 1/256. Logo:

```
Z256(id,y) = Σ_d W16[y][d]·e16(id,d) + 16·b16[y]
δ256(n,y)  = Z256(entrada[n], y) − 256·[y = alvo[n]]
S          = Σ_{n,y} δ256(n,y)²
L          = S / 524288
```

Nenhum `real` é usado no treinamento. As vantagens:

- não há arredondamento binário, `−0.0`, `NaN` ou dependência de locale;
- o oráculo de teste é o mesmo cálculo inteiro, sem tolerância;
- a prova de faixa é elementar (§3.3);
- a única conversão para `real` é `treino_materializar`, que divide por `16.0`
  (exato, pois o numerador é inteiro e o divisor é potência de dois).

A alternativa "estado em `real` + quantização com `Matematica.arredondar`" foi
rejeitada: o modo de arredondamento da biblioteca não está provado, não existe cast
`inteiro(expr)` (`docs/embeddings-plan.md`, P14) e a atribuição `real → inteiro`
trunca com aviso. A formulação inteira elimina as três incertezas.

### 2.5 O que este treinamento não é

- Não é um modelo de linguagem: é memorização de **4 pares fixos**.
- Não há contexto: cada par é independente; `entrada` é um único ID.
- As palavras (`se`, `faca`, `para`, `ate`, `pare`) são apenas rótulos do
  vocabulário da M1; o experimento não afirma nada sobre sintaxe ou semântica.
- Não há amostragem, temperatura, perplexidade nem geração.
- Não há seed aleatória: a ordem dos exemplos é fixa e a inicialização é canônica.

## 3. Estado, layout e invariantes

### 3.1 Arrays

| Nome | Tipo | Tamanho | Índice | Papel |
| --- | --- | --- | --- | --- |
| `w16` | `inteiro` | 100 | `y*4 + d` | pesos em 1/16 |
| `b16` | `inteiro` | 25 | `y` | vieses em 1/16 |
| `entradas` | `inteiro` | 1..16 | `n` | IDs de entrada |
| `alvos` | `inteiro` | 1..16 | `n` | IDs de alvo |
| `historico` | `inteiro` | ≥ `epocas+1` | `e` | `S` após cada época |

Não há array de embeddings no módulo: `treino_emb16(id, d)` recalcula a fórmula da
M3 em unidades de 1/16. A duplicação é intencional e coberta por teste
(`trn_composicao` compara as 100 células com `emb_obter`).

### 3.2 Constantes

Todas literais (o interpretador rejeita `const` com expressão — M3, P9):

```
TREINO_TAM_VOCAB = 25     TREINO_DIM = 4        TREINO_SAIDAS = 25
TREINO_TOTAL_W = 100      TREINO_TOTAL_B = 25   TREINO_PARAMS = 125
TREINO_MAX_EXEMPLOS = 16  TREINO_MAX_EPOCAS = 256
TREINO_GRADE = 16         TREINO_ESCALA_PERDA = 524288
TREINO_LIMITE = 48        TREINO_EPOCAS = 5
TREINO_TAXA_NUM = 1       TREINO_TAXA_DEN = 4
TREINO_DIV_W = 1024       TREINO_DIV_B = 64
```

### 3.3 Invariantes e faixa

| ID | Invariante |
| --- | --- |
| I1 | `len(w16) = 100`, `len(b16) = 25` |
| I2 | `\|w16[y][d]\| ≤ 48` e `\|b16[y]\| ≤ 48` durante toda execução válida |
| I3 | `w16`, `b16` são múltiplos de 1 em unidades de 1/16 (triviais: são inteiros) |
| I4 | `1 ≤ n ≤ 16` e `1 ≤ epocas ≤ 256` |
| I5 | `entradas[n]`, `alvos[n] ∈ 0..24` |
| I6 | `historico[0..epocas]` é garantido apenas em caso de sucesso; em `ESTOURO_NUMERICO` o conteúdo não é especificado |

Prova de faixa (com I2):

```
|Z256| ≤ 4·48·16 + 16·48 = 3.840
|δ256| ≤ 3.840 + 256 = 4.096
S      ≤ 100 · 4.096² = 1.677.721.600 < 2³¹ = 2.147.483.648
```

Numeradores de atualização (pior caso):

```
W: |1024·48| + |4096·16| = 114.688
b: |64·48|  + |4096|     = 7.168
```

Todos cabem em `inteiro` de 32 bits. O limite 48 é folgado: o estado canônico
máximo observado é `|W16| = 11`, `|b16| = 6`.

## 4. Inicialização determinística

### 4.1 Fórmulas

Idênticas à M4, multiplicadas por 16:

```
W16[y][d] = (((y·7 + d·5) mod 25) − 12)
b16[y]    = (((y·7) mod 9) − 4)
```

`treino_inicializar(w16, b16)` grava as 125 posições sem ler o estado anterior.
É o único mecanismo de reinicialização.

### 4.2 Tabela canônica inicial

Formato `PARAM16=y w0 w1 w2 w3 b`:

```
PARAM16=0 -12 -7 -2 3 -4
PARAM16=1 -5 0 5 10 3
PARAM16=2 2 7 12 -8 1
PARAM16=3 9 -11 -6 -1 -1
PARAM16=4 -9 -4 1 6 -3
PARAM16=5 -2 3 8 -12 4
PARAM16=6 5 10 -10 -5 2
PARAM16=7 12 -8 -3 2 0
PARAM16=8 -6 -1 4 9 -2
PARAM16=9 1 6 11 -9 -4
PARAM16=10 8 -12 -7 -2 3
PARAM16=11 -10 -5 0 5 1
PARAM16=12 -3 2 7 12 -1
PARAM16=13 4 9 -11 -6 -3
PARAM16=14 11 -9 -4 1 4
PARAM16=15 -7 -2 3 8 2
PARAM16=16 0 5 10 -10 0
PARAM16=17 7 12 -8 -3 -2
PARAM16=18 -11 -6 -1 4 -4
PARAM16=19 -4 1 6 11 3
PARAM16=20 3 8 -12 -7 1
PARAM16=21 10 -10 -5 0 -1
PARAM16=22 -8 -3 2 7 -3
PARAM16=23 -1 4 9 -11 4
PARAM16=24 6 11 -9 -4 2
MAXIMO16=12 4
```

### 4.3 Propriedades

- `S0 = 3.674.036`, `L0 = 7,00766754150390625`.
- Predições iniciais: `10 19 6 11`; acurácia `0/4`.
- Contribuição por exemplo: `1.298.270 / 440.054 / 1.569.094 / 366.618`.
- Nenhum parâmetro no limite: `max |W16| = 12`, `max |b16| = 4`.

## 5. Forward e perda

### 5.1 Fórmula normativa

```
e16(id,d)  = (((id·7 + d·3) mod 32) − 16)
Z256(id,y) = Σ_{d=0..3} W16[y][d]·e16(id,d) + 16·b16[y]
δ256(n,y)  = Z256(entradas[n], y) − 256·(1 se y = alvos[n], senão 0)
S          = Σ_{n=0..N−1} Σ_{y=0..24} δ256(n,y)²
```

Ordem de acumulação obrigatória: `d = 0, 1, 2, 3`, soma começando em `0`,
viés por último. Idêntica à M4 (§5.2), o que garante que `materializar` + `rede_logit`
reproduz exatamente `Z256/256`.

### 5.2 Prova de exatidão

`W16`, `e16`, `b16` são inteiros. Logo `Z256` e `δ256` são inteiros e `S` é uma
soma de quadrados inteiros. Todos os valores reais correspondentes são múltiplos de
`1/256` (logits) e `1/524288` (perda), exatamente representáveis em binário. Não há
divisão no caminho quente.

### 5.3 Argmax e empates

```
melhor = 0
melhor_valor = Z256(id, 0)
para y = 1..24:
    se Z256(id, y) > melhor_valor:
        melhor_valor = Z256(id, y)
        melhor = y
```

Comparação estrita; empate fica com o menor `y`, igual a `rede_argmax`. Como a
comparação é entre inteiros, não há diferença entre `Z256` e `z` na ordenação.

## 6. Atualização dos parâmetros

### 6.1 Regra

SGD **por exemplo** (online), na ordem fixa `n = 0, 1, ..., N−1`, com:

- taxa `η = 1/4`;
- quantização `τ = 1/16` aplicada **ao novo valor** após cada parâmetro ser
  atualizado;
- arredondamento "meio para longe de zero".

Equações reais (para leitura):

```
δ(n, y) = z(entrada[n], y) − t[n][y]
W[y][d] ← quantiza16( W[y][d] − η·δ(n,y)·e(entrada[n], d) )
b[y]    ← quantiza16( b[y]    − η·δ(n,y) )
```

Equações inteiras (normativas, sem `real`):

```
r(num, den) = sinal(num) · ⌊ (|num| + den/2) / den ⌋      den ∈ {64, 1024}

W16[y][d] ← r( 1024·W16[y][d] − δ256(n,y)·e16(entrada[n], d), 1024 )
b16[y]    ← r(  64·b16[y]    − δ256(n,y),                     64  )
```

O denominador `64` vem de `16·η·δ·1 = 16·(1/4)·(δ256/256) = δ256/64`.
O denominador `1024` vem de `16·η·δ·e = 16·(1/4)·(δ256/256)·(e16/16) = δ256·e16/1024`.

### 6.2 Ordem interna obrigatória

Para cada exemplo `n`:

1. calcular e **congelar** os 25 valores `δ256(n, y)` a partir do estado corrente;
2. para `y = 0..24`, atualizar os quatro `W16[y][*]` e depois `b16[y]`, usando o
   `δ256(n, y)` congelado;
3. verificar I2 após cada escrita; se violar, retornar `ESTOURO_NUMERICO`.

O congelamento é obrigatório: atualizar `W16[y][0]` e **recalcular**
`δ256(n, y)` antes de atualizar `W16[y][1]` produz outro resultado. Como cada
linha `y` só depende de si mesma, processar linhas em qualquer ordem é
equivalente — mas a ordem dos **exemplos** e a quantização por parâmetro não são.

### 6.3 Prova de equivalência com a forma real

```
16 · (W − ηδe) = W16 − 16·(1/4)·(δ256/256)·(e16/16) = W16 − δ256·e16/1024
16 · (b − ηδ)  = b16 − 16·(1/4)·(δ256/256)          = b16 − δ256/64
```

Como `W16` é inteiro, quantizar `16·(W − ηδe)` é exatamente `r(num, 1024)`.
`r` implementa meio-para-longe-de-zero, inclusive em `±512/1024` e `±32/64`.

### 6.4 Ponto fixo

Depois da época 5, nenhum dos 125 parâmetros muda na época 6
(`mudou_neste_ep = 0`). O estado é um ponto fixo da atualização quantizada, e a
perda permanece `27.804` indefinidamente. Isso não é divergência nem "parada por
limite": é a consequência de `η = 1/4` com passo menor que meio quantum.

## 7. Justificativa dos hiperparâmetros

### 7.1 Grade `τ = 1/16`

A M3 e a M4 já produzem estado na grade 1/16. Usar outra grade exigiria converter
os módulos ou conviver com duas representações. `τ = 1/16` preserva
`materializar` exato e permite reutilizar `rede_logit`/`rede_argmax` sem tolerância.

### 7.2 Taxa `η = 1/4`

Varredura com aritmética racional exata, mesma inicialização, 5 épocas, `S` por época:

| `η` | `S0` | `S1` | `S2` | `S3` | `S4` | `S5` | acurácia | observação |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1/32 | 3.674.036 | 2.988.900 | 2.609.820 | 2.421.796 | 2.349.694 | 2.304.980 | 0/4 | não converge em 5 |
| 1/16 | 3.674.036 | 2.234.608 | 1.584.094 | 1.224.260 | 1.023.856 | 944.802 | 3/4 | não converge em 5 |
| 1/8 | 3.674.036 | 1.261.640 | 578.306 | 349.754 | 232.108 | 201.968 | 4/4 | não converge em 5 |
| **1/4** | **3.674.036** | **428.488** | **107.796** | **41.544** | **30.998** | **27.804** | **4/4** | **estrito, fixo na época 5** |
| 1/2 | 3.674.036 | 1.488.556 | 548.036 | 235.698 | 149.200 | 91.394 | 4/4 | ainda cai na época 8 |
| 3/8 | 3.674.036 | 490.556 | 34.094 | 16.768 | 17.114 | 14.998 | 4/4 | não monotônica |
| 1/1 | 3.674.036 | 31.254.666 | 84.385.078 | 472.882.828 | 1.656.269.276 | 11.815.073.482 | 2/4 | diverge |

Critério: maior taxa potência de dois que (a) decresce estritamente em todas as
cinco épocas e (b) atinge o ponto fixo quantizado na época 5. A taxa 1/4 é a única
que satisfaz as duas. `3/8` chega a uma perda menor, mas com uma época não
monotônica; fica registrada como alternativa, não como padrão.

### 7.3 Épocas `E = 5`

É o menor `E` com `S_E = S_{E+1}` (ponto fixo). `E = 4` ainda reduz
(`30.998 → 27.804`); `E = 6` não muda nada e só gasta tempo. O valor 5 é fixo no
código (`TREINO_EPOCAS`) e o parâmetro `epocas` permite outros valores em teste.

## 8. Dados canônicos

### 8.1 Conjunto

| `n` | palavra de entrada | `entradas[n]` | palavra alvo | `alvos[n]` |
| ---: | --- | ---: | --- | ---: |
| 0 | `se` | 9 | `faca` | 12 |
| 1 | `faca` | 12 | `para` | 13 |
| 2 | `para` | 13 | `ate` | 14 |
| 3 | `ate` | 14 | `pare` | 24 |

Propriedades:

- entradas distintas (`9, 12, 13, 14`), alvos distintos (`12, 13, 14, 24`);
- nenhuma entrada aparece com dois alvos (sem conflito);
- `24` é alvo e não é entrada; `9` é entrada e não é alvo — o modelo não pode
  vencer copiando a identidade;
- a matriz 4×4 das entradas tem determinante `−55.296 ≠ 0` (conferido por dois
  métodos independentes), então os quatro exemplos são linearmente independentes.

O conjunto é sintético. Não há relação gramatical entre as palavras; a cadeia
`9→12→13→14→24` é apenas uma escolha de IDs que evita colisões.

### 8.2 Execução canônica

`treino_executar(w16, b16, entradas, alvos, 4, 5, historico)` a partir do estado
canônico. Resultado exato:

| época | `S` | `L = S/524288` | acertos | predições |
| ---: | ---: | ---: | ---: | --- |
| 0 | 3.674.036 | 7,00766754150390625 | 0/4 | 10 19 6 11 |
| 1 | 428.488 | 0,8172760009765625 | 2/4 | 14 1 14 24 |
| 2 | 107.796 | 0,20560455322265625 | 4/4 | 12 13 14 24 |
| 3 | 41.544 | 0,0792388916015625 | 4/4 | 12 13 14 24 |
| 4 | 30.998 | 0,059123992919921875 | 4/4 | 12 13 14 24 |
| 5 | **27.804** | **0,05303192138671875** | **4/4** | **12 13 14 24** |
| 6 | 27.804 | 0,05303192138671875 | 4/4 | 12 13 14 24 |

Queda total: `3.646.232` (`99,2432%`). Quedas por época:
`3.245.548 / 320.692 / 66.252 / 10.546 / 3.194`.

### 8.3 Estado após 5 épocas

```
PARAM16=0 -1 0 -3 2 -1
PARAM16=1 0 0 -2 3 0
PARAM16=2 0 0 11 -10 2
PARAM16=3 1 0 -3 2 -2
PARAM16=4 0 0 -4 3 0
PARAM16=5 -1 0 10 -11 2
PARAM16=6 -1 0 -3 2 0
PARAM16=7 1 0 -3 3 -1
PARAM16=8 0 -1 -2 3 1
PARAM16=9 0 0 9 -10 1
PARAM16=10 1 0 -1 2 -1
PARAM16=11 -1 0 -1 2 1
PARAM16=12 8 -7 -3 3 2
PARAM16=13 1 2 3 6 6
PARAM16=14 1 8 -4 -2 2
PARAM16=15 0 -1 -2 3 0
PARAM16=16 0 1 10 -10 3
PARAM16=17 0 0 -3 2 -1
PARAM16=18 -1 -1 -3 4 0
PARAM16=19 1 -1 -2 3 0
PARAM16=20 -1 0 -4 3 0
PARAM16=21 0 0 -3 3 -1
PARAM16=22 0 0 -3 4 0
PARAM16=23 -1 0 10 -10 3
PARAM16=24 -9 -2 -4 0 4
MAXIMO16=11 6
```

Linhas de interesse na época 1 e na época 5:

| `y` | época 1 (`w0 w1 w2 w3 b`) | época 5 (`w0 w1 w2 w3 b`) |
| ---: | --- | --- |
| 9 | `1 1 9 -10 0` | `0 0 9 -10 1` |
| 12 | `5 -5 -1 5 3` | `8 -7 -3 3 2` |
| 13 | `-1 6 -1 3 0` | `1 2 3 6 6` |
| 14 | `8 0 -5 0 4` | `1 8 -4 -2 2` |

### 8.4 Evidência de mudança dirigida

| exemplo | `Z256` do alvo (época 0 → 5) | margem final sobre o 2º | contribuição `S` (0 → 5) |
| --- | --- | ---: | --- |
| 9→12 | `−262 → 259` | 231 | `1.298.270 → 2.632` |
| 12→13 | `−157 → 222` | 194 | `440.054 → 9.948` |
| 13→14 | `107 → 239` | 207 | `1.569.094 → 5.344` |
| 14→24 | `−81 → 244` | 212 | `366.618 → 9.880` |

O logit do alvo cresce nos quatro casos e o alvo vira o argmax com margem ≥ 194
(em unidades de 1/256). Isso é evidência de direção correta, não apenas de queda
agregada.

### 8.5 Alterações

- `W` alterados: **91/100**; inalterados: `(1,1) (7,2) (8,1) (14,2) (16,0)
  (16,2) (16,3) (18,3) (23,0)`.
- `b` alterados: **23/25**; inalterados: `11, 21`.
- Total: **114/125**.
- `max |W16| = 11`, `max |b16| = 6`; nenhum parâmetro chega perto do limite 48.
- Parâmetros que mudam **em cada época** (relativo à época anterior):
  `113 / 88 / 47 / 21 / 7 / 0` (épocas 1..6). Todos os 114 parâmetros alterados
  já haviam mudado até a época 4; nenhum muda pela primeira vez na época 5.
  A época 6 é ponto fixo exato.

### 8.6 Gradiente na inicialização

Diferença central com `h = 1` (um quantum de 1/16), avaliando só a linha afetada:

```
S(W16+1) − S(W16−1) = 4·G
G(y,d) = Σ_n δ256(n,y)·e16(entradas[n], d)
G_b(y) = 16·Σ_n δ256(n,y)
```

Resultados no estado inicial:

- `GRAD_EXATOS = 125`, `GRAD_TOTAL = 125` (todos exatos);
- `G_W = 5.376`, `G_B = −14.336`, `GRAD_SOMA = −8.960`.

A soma é o checksum dos 125 testes: um sinal trocado altera o valor, e um índice
deslocado produz outro resultado na prática. Após o teste, o estado é restaurado
(verificado por `MAXIMO16`).

## 9. API

Todas as funções ficam em `src/treino.por`, fragmento ASCII sem `programa` nem
`inicio`, com prefixo `treino_`/`TREINO_`. O módulo **não** chama funções de M1, M3
ou M4; a composição é feita pelo driver de teste.

### 9.1 Validadores puros

```portugol
funcao logico treino_id_valido(inteiro id)                  // 0..24
funcao logico treino_n_valido(inteiro n)                    // 1..16
funcao logico treino_epocas_validas(inteiro epocas)         // 1..256
funcao logico treino_params_validos(inteiro w16[], inteiro b16[])  // |v| <= 48
funcao inteiro treino_validar(inteiro entradas[], inteiro alvos[],
                              inteiro n, inteiro epocas,
                              inteiro w16[], inteiro b16[])
```

`treino_validar` retorna `0` (ok), `1` (exemplos), `2` (épocas), `3` (id) ou `4`
(parâmetros), nesta precedência. Não acessa `entradas`/`alvos` antes de validar `n`.

### 9.2 Aritmética e forward

```portugol
funcao inteiro treino_div_arredondada(inteiro numerador, inteiro denominador)
funcao inteiro treino_emb16(inteiro id, inteiro dimensao)
funcao inteiro treino_z256(inteiro w16[], inteiro b16[],
                           inteiro entrada, inteiro y)
funcao inteiro treino_delta256(inteiro w16[], inteiro b16[],
                               inteiro entrada, inteiro y, inteiro alvo)
funcao inteiro treino_argmax(inteiro w16[], inteiro b16[], inteiro entrada)
funcao inteiro treino_perda_escalada(inteiro w16[], inteiro b16[],
                                     inteiro entradas[], inteiro alvos[],
                                     inteiro n)
funcao inteiro treino_acertos(inteiro w16[], inteiro b16[],
                              inteiro entradas[], inteiro alvos[], inteiro n)
```

Pré-condições: `id`, `entrada`, `y`, `alvo` válidos; `n` válido; estado dentro de
I2. As funções puras não validam e não imprimem. `treino_perda_escalada` retorna
`S`; `treino_acertos` retorna `0..n`.

### 9.3 Estado e execução

```portugol
funcao treino_inicializar(inteiro w16[], inteiro b16[])
funcao inteiro treino_executar(inteiro w16[], inteiro b16[],
                               inteiro entradas[], inteiro alvos[],
                               inteiro n, inteiro epocas,
                               inteiro historico[])
funcao treino_materializar(inteiro w16[], inteiro b16[],
                           real pesos[], real vieses[])
funcao treino_calcular_gradiente(inteiro w16[], inteiro b16[],
                                 inteiro entradas[], inteiro alvos[],
                                 inteiro n, inteiro saida[])
```

- `treino_executar` valida primeiro; em erro `1..4` **não muta** nada. Em sucesso,
  grava `historico[0] = S` do estado inicial, executa as épocas e grava
  `historico[e] = S` ao fim da época `e` (`1..epocas`), retornando `0`. Em `5`
  (`ESTOURO_NUMERICO`), o estado pode estar parcialmente alterado: o chamador deve
  reinicializar. Não há rollback prometido, e o conteúdo de `historico` não é
  garantido nesse caso.
- `treino_materializar` grava `pesos[y*4+d] = w16[y*4+d] / 16.0` e
  `vieses[y] = b16[y] / 16.0`. Divisão por potência de dois: exata.
- `treino_calcular_gradiente` preenche `saida[0] = exatos`, `saida[1] = soma` e
  restaura o estado. Pré-condição: `|W16|, |b16| ≤ 47` (para `±1` não violar I2).
  Definições: `G(y,d) = Σ_n δ256(n,y)·e16(entradas[n],d)`,
  `G_b(y) = 16·Σ_n δ256(n,y)`, `soma` = soma dos 100 `G(y,d)` e dos 25 `G_b(y)`;
  `exatos` conta quantos dos 125 parâmetros satisfazem
  `S(v+1) − S(v−1) = 4G` com `h = 1` (§8.6).
- `treino_imprimir_gradiente` valida na ordem `n → ids → limite 47`. Se
  `|W16| > 47` ou `|b16| > 47`, emite **exatamente** `ERRO=PARAMETROS_INVALIDOS`
  e não imprime `GRAD_*` nem qualquer linha parcial. O limite é 47, não 48,
  porque o teste de diferença central avalia `W16 ± 1` e `b16 ± 1`; com 48 o
  estado temporário violaria I2 e o resultado deixaria de ser confiável.

### 9.4 Impressoras

```portugol
funcao treino_imprimir_config()
funcao treino_imprimir_validacao(inteiro entradas[], inteiro alvos[],
                                 inteiro n, inteiro epocas,
                                 inteiro w16[], inteiro b16[])
funcao treino_imprimir_avaliacao(inteiro w16[], inteiro b16[],
                                 inteiro entradas[], inteiro alvos[], inteiro n)
funcao treino_imprimir_historico(inteiro historico[], inteiro epocas)
funcao treino_imprimir_param16(inteiro w16[], inteiro b16[], inteiro y)
funcao treino_imprimir_estado(inteiro w16[], inteiro b16[])
funcao treino_imprimir_alterados(inteiro w16[], inteiro b16[])
funcao treino_imprimir_gradiente(inteiro w16[], inteiro b16[],
                                 inteiro entradas[], inteiro alvos[], inteiro n)
```

Todas validam antes de acessar arrays e emitem **uma única linha de erro** quando
aplicável, sem saída parcial. Conteúdo exato de cada impressora:

| Função | Linhas emitidas (nesta ordem) |
| --- | --- |
| `treino_imprimir_config` | `INFO`, `TAXA`, `GRADE`, `EPOCAS`, `ESCALA_PERDA`, `LIMITE_PARAM`, `ORDEM` |
| `treino_imprimir_validacao` | `VALIDO=OK` se `treino_validar` retornar `0`; senão `ERRO=<texto do código>` |
| `treino_imprimir_avaliacao` | `PERDA`, `ACERTOS`, `PRED` |
| `treino_imprimir_historico` | uma linha `HISTORICO=` com `epocas+1` inteiros |
| `treino_imprimir_param16` | uma linha `PARAM16=y w0 w1 w2 w3 b`; `ERRO=SAIDA_INVALIDA` se `y` fora de `0..24` |
| `treino_imprimir_estado` | 25 linhas `PARAM16` (`y = 0..24`) e depois `MAXIMO16=<maxW16> <maxb16>` |
| `treino_imprimir_alterados` | `ALTERADOS_W=<n>` e `ALTERADOS_B=<n>`, comparando com a fórmula canônica de §4.1 (sem baseline armazenado) |
| `treino_imprimir_gradiente` | `GRAD_EXATOS`, `GRAD_TOTAL`, `GRAD_SOMA`; guarda de 47 antes de qualquer linha |

As linhas `PARAM16`, `MAXIMO16` e `ALTERADOS_*` sempre se referem ao estado
corrente no momento da chamada. `EPOCAS` reporta a constante canônica
`TREINO_EPOCAS = 5`, não o argumento `epocas` de uma execução específica; o
número efetivo de épocas é observável pelo tamanho de `HISTORICO`. O driver é
responsável pela ordem entre impressoras; cada impressora não imprime nada além
do listado.

## 10. Formato observável

### 10.1 Gramática

```
INFO=TREINO 16 256 125 100
TAXA=1/4
GRADE=1/16
EPOCAS=5
ESCALA_PERDA=524288
LIMITE_PARAM=48
ORDEM=EXEMPLO
PERDA=<inteiro>
ACERTOS=<inteiro>
PRED=<id>[ <id>]*
HISTORICO=<inteiro>[ <inteiro>]*
PARAM16=<y> <w0> <w1> <w2> <w3> <b>
MAXIMO16=<inteiro> <inteiro>
ALTERADOS_W=<inteiro>
ALTERADOS_B=<inteiro>
GRAD_EXATOS=<inteiro>
GRAD_TOTAL=125
GRAD_SOMA=<inteiro>
VALIDO=OK
ERRO=<CODIGO>
```

- Tudo é ASCII, uma linha por registro, `\n` no fim de cada linha.
- `PERDA` é `S` (inteiro), nunca `L` em ponto flutuante. `L = S/524288` é derivado
  pela documentação e pelos testes; imprimi-lo exigiria confiar na formatação de
  `real`, que a missão evita.
- `PARAM16` usa os numeradores inteiros; não há `0.1875` na saída.
- `PRED` tem exatamente `n` IDs; `HISTORICO` tem exatamente `epocas+1` valores.
- Sucesso nunca contém `ERRO=`; erro nunca contém dados de avaliação.

### 10.2 Exemplo (estado inicial)

```
INFO=TREINO 16 256 125 100
TAXA=1/4
GRADE=1/16
EPOCAS=5
ESCALA_PERDA=524288
LIMITE_PARAM=48
ORDEM=EXEMPLO
PERDA=3674036
ACERTOS=0
PRED=10 19 6 11
```

### 10.3 Condição de congelamento

O formato congela em E0. Qualquer mudança depois disso exige atualizar esta spec
para `v1.1.0`, regenerar todos os `.expected` e reexecutar a matriz completa.

## 11. Erros

### 11.1 Códigos

| Código | Texto | Condição |
| ---: | --- | --- |
| 0 | `VALIDO=OK` | entrada válida |
| 1 | `EXEMPLOS_INVALIDOS` | `n < 1` ou `n > 16` |
| 2 | `EPOCAS_INVALIDAS` | `epocas < 1` ou `epocas > 256` |
| 3 | `ID_INVALIDO` | `entradas[n]` ou `alvos[n]` fora de `0..24` |
| 4 | `PARAMETROS_INVALIDOS` | `\|W16\| > 48` ou `\|b16\| > 48` na entrada |
| 5 | `ESTOURO_NUMERICO` | atualização produziria `\|v\| > 48` |
| — | `SAIDA_INVALIDA` | `y` fora de `0..24` em `treino_imprimir_param16` |

### 11.2 Precedência

`1 → 2 → 3 → 4`; `5` só pode ocorrer depois de `0`. Dentro de `3`, a ordem é
`entradas[0], alvos[0], entradas[1], alvos[1], ...`.

### 11.3 Estado em caso de erro

- `1..4`: nenhuma mutação (validação antes de qualquer escrita).
- `5`: mutação parcial possível; o chamador deve chamar `treino_inicializar`.
- `SAIDA_INVALIDA`: nenhuma mutação.

### 11.4 Testemunho determinístico de `ESTOURO_NUMERICO`

O caso `trn_erros` usa este estado, que passa em `treino_validar` (todos os
valores têm `|v| ≤ 48`):

```
w16[5][0..3] = -48 -48 -48 -48      b16[5] = 48
n = 1     entradas[0] = 12     alvos[0] = 0     epocas = 1
```

Cálculo exato:

```
e16(12, ·) = 4 7 10 13
Z256(12, 5) = -48·(4+7+10+13) + 16·48 = -864
δ256(0, 5)  = -864 - 0 = -864
b16[5] ← r(64·48 - (-864), 64) = r(3936, 64) = 62
```

`62 > 48` dispara a guarda I2 na linha `y = 5`, depois das quatro atualizações
de `W16[5][*]` (que resultam em `-45 -42 -40 -37`) e antes de qualquer linha
seguinte. O retorno é `5`. O estado fica parcialmente alterado, conforme §11.3.

## 12. Limites

| Limite | Valor | Justificativa |
| --- | ---: | --- |
| exemplos | 1..16 | mantém a saída e o tempo limitados |
| épocas | 1..256 | pior caso 16·256·25·4 ≈ 409.600 multiplicações |
| parâmetros | `\|v\| ≤ 48` | prova de faixa (§3.3) |
| histórico | `epocas+1` | um valor por época, mais o inicial |
| exemplos distintos | não exigido | duplicatas são permitidas e têm semântica de repetição |

`n = 16` com os 4 pares repetidos 4 vezes produz
`S0 = 14.696.144` e `S1 = 123.992` (1 época, 16/16 acertos). `n = 1` com `9→12`
produz `S0 = 1.298.270` e `S1 = 31.576` (1/1). Esses valores fazem parte da
matriz de testes.

## 13. Oráculo independente

O oráculo não lê `.expected` nem reutiliza funções do módulo. Ele é definido pelas
fórmulas inteiras da §5 e §6 e foi implementado duas vezes de forma independente
nesta missão:

1. **racional exato** (`fractions.Fraction`, Python 3.14): `W`, `b`, `e` em `1/16`;
   atualização e quantização em racionais; nenhuma representação binária.
2. **inteiro** (`inteiro` de 32 bits, PowerShell): `W16`, `b16`, `e16`, `Z256`,
   `δ256`, `r(num, den)`.

As duas deram exatamente a mesma trajetória, a mesma tabela final, os mesmos
`114/125` parâmetros alterados e o mesmo `GRAD_SOMA = −8.960`. Na execução, o
builder passou a ser o terceiro oráculo inteiro (PowerShell), a implementação em
Portugol a quarta e o verificador a quinta, re-derivando `S` das tabelas impressas
sem simular o treinamento. As cinco concordaram: o builder recusa publicar se
qualquer tabela canônica divergir, e o verificador (V5) recomputa `S`, `PRED`,
`ACERTOS`, `MAXIMO16` e `ALTERADOS_*` a partir das 25 linhas `PARAM16` impressas
pelo próprio interpretador.

O que o verificador `scripts/verify-training-bytes.ps1` deve conferir de forma
independente:

| ID | Conferência |
| --- | --- |
| V1 | fonte ASCII, sem BOM, LF, sem `programa`/`inicio`, sem `Matematica`, `aleatorio`, `tempo`, `leia` |
| V2 | conjunto de casos exatamente `trn_*` esperado (12), sem faltas nem extras |
| V3 | bytes crus: `\f` inicial, carga ASCII com LF, epílogo exato |
| V4 | `INFO`, `TAXA`, `GRADE`, `EPOCAS`, `ESCALA_PERDA`, `LIMITE_PARAM`, `ORDEM` |
| V5 | nos casos que imprimem a tabela completa de 25 `PARAM16` (`trn_perda_inicial`, `trn_estado_final`, `trn_determinismo_a`, `trn_determinismo_b`), re-derivar `S` a partir da tabela impressa e comparar com o `PERDA` do mesmo caso; nos demais casos, conferir apenas os valores literais já congelados |
| V6 | `HISTORICO` estritamente decrescente em 0..5 e `S5 = 27.804` |
| V7 | `ACERTOS`/`PRED` coerentes com a tabela final |
| V8 | `ALTERADOS_*`, `MAXIMO16` coerentes com a tabela final |
| V9 | `GRAD_EXATOS = GRAD_TOTAL = 125` e `GRAD_SOMA = −8.960` |
| V10 | `trn_determinismo_a.expected` idêntico a `trn_determinismo_b.expected` |
| V11 | `trn_composicao` usa os IDs da M1 e as 100 células da M3 |
| V12 | nenhum `.expected` com `\n` final, espaços nas pontas, CR ou byte > 0x7E |

## 14. Casos obrigatórios

| # | Caso | Verifica |
| ---: | --- | --- |
| 1 | `trn_info` | constantes, limites, validadores de fronteira, tabela de `r` |
| 2 | `trn_perda_inicial` | tabela inicial completa, `S0`, acurácia, `ALTERADOS=0` |
| 3 | `trn_gradiente` | `125/125`, `GRAD_SOMA`, estado restaurado, `ERRO=PARAMETROS_INVALIDOS` com `\|v\| = 48` |
| 4 | `trn_epoca_1` | primeira época, `S1`, `2/4`, quatro linhas de interesse (`9/12/13/14`) |
| 5 | `trn_cinco_epocas` | `HISTORICO`, `S5`, `4/4` |
| 6 | `trn_estado_final` | tabela final completa, `MAXIMO16`, `ALTERADOS` |
| 7 | `trn_erros` | códigos 1..5, precedência, estado intacto em 1..4 |
| 8 | `trn_limites` | `n=0,1,16,17`, `epocas=0,1,256,257` |
| 9 | `trn_determinismo_a` | execução completa no processo A |
| 10 | `trn_determinismo_b` | mesma execução no processo B, bytes iguais |
| 11 | `trn_composicao` | M1 → M3 → M4 → treino, sem divergência |
| 12 | `trn_reinicializacao` | mutar, reinicializar, estado canônico restaurado |

A matriz com entradas e saídas esperadas está em `docs/training-plan.md` §7. Na
execução, os 12 casos passaram; `trn_cinco_epocas` foi ampliado para reexecutar
uma época após as 5 e provar o ponto fixo (`PONTO_FIXO=OK`, `CODIGO6=0`), e
`trn_estado_final` passou a imprimir `PERDA`, `ACERTOS` e `PRED` antes da tabela
completa, permitindo ao verificador re-derivar a perda do estado final.

## 15. Critérios de aceitação

Cada critério é verificável por comando. "PASS" significa saída observada igual à
esperada, não ausência de exceção.

| ID | Critério | Verificação |
| --- | --- | --- |
| AC1 | apenas os arquivos autorizados foram criados/alterados | `git status --short` |
| AC2 | 58 testes anteriores continuam passando | `scripts/test.ps1` = 70 PASS / 0 FAIL |
| AC3 | M1, M3 e M4 sem regressão | `verify-bytes` 21/21, `verify-embedding-bytes` 19/19, `verify-network-bytes` 22/22 |
| AC4 | autoteste continua falhando de propósito | `test.ps1 -SelfTest` = 0 PASS / 1 FAIL, exit `1` |
| AC5 | 12 casos novos, todos PASS | suíte 70/70; `verify-training-bytes` ≥ 12/12 |
| AC6 | oráculo independente | verificador não lê `.expected` para decidir valores (V5–V11); a re-derivação de `S` vale só para os casos com tabela completa de 25 `PARAM16` |
| AC7 | perda cai | `HISTORICO` 0..5 estritamente decrescente; `S5 = 27.804` |
| AC8 | queda é material | `S5/S0 = 0,007568` (< 1%) |
| AC9 | acurácia sobe | `0/4 → 2/4 → 4/4` |
| AC10 | parâmetros mudam | `114/125`; `MAXIMO16=11 6` |
| AC11 | mudança é dirigida | logit do alvo cresce nos 4 exemplos (§8.4) |
| AC12 | gradiente confere | `125/125` exatos; `GRAD_SOMA=−8.960` |
| AC13 | quantização | `±512/1024 → ±1`, `±511/1024 → 0`, `±32/64 → ±1` |
| AC14 | determinismo | `trn_determinismo_a` ≡ `trn_determinismo_b` byte a byte |
| AC15 | composição | `ARGMAX_REDE` = `ARGMAX_TREINO`; `EMB16=OK`; `IDS=9 12 13 14 24` (saída de `tokenizar`) |
| AC16 | erros e precedência | `trn_erros` com os 6 cenários |
| AC17 | estado intacto em erro de validação | `INTACTO=OK` |
| AC18 | embeddings congelados | `src/embeddings.por` com hash de `HEAD`; nenhuma escrita em `emb` |
| AC19 | nenhum módulo anterior alterado | hashes de `HEAD` conferidos |
| AC20 | sem commit/push/tag/remote | `git log -1` e `git status` inalterados |
| AC21 | documentação atualizada | `docs/training-spec.md` e `docs/training-plan.md` com evidências reais |
| AC22 | nenhuma dependência nova | `src/treino.por` sem `inclua`, sem `Matematica`, sem `aleatorio` |

## 16. Limitações e trabalho futuro

- Memorização de 4 pares; não generaliza.
- MSE sobre logits não produz probabilidades e não é a escolha usual para
  classificação; este experimento não comparou a velocidade de convergência com
  entropia cruzada.
- Sem retropropagação além de uma camada; sem embeddings treináveis.
- O ponto fixo depende de `η` e da grade; outra grade muda os valores canônicos.
- A taxa 3/8 chega a uma perda menor (`14.998`), mas com época não monotônica;
  fica como alternativa documentada.
- Um `exp` exato (ou com tolerância formal) seria pré-requisito para entropia
  cruzada em missão futura.

## 17. Decisões registradas

| ID | Decisão |
| --- | --- |
| D1 | camada afim 4→25 da M4; sem ativação, sem softmax |
| D2 | MSE sobre logits; entropia cruzada rejeitada por ausência de `exp` exato |
| D3 | estado inteiro `w16[100]`, `b16[25]` em unidades de 1/16 |
| D4 | embeddings congelados; fórmula da M3 recalculada em `treino_emb16` |
| D5 | SGD por exemplo, ordem fixa, `η = 1/4` |
| D6 | quantização no novo valor, meio para longe de zero, após cada parâmetro |
| D7 | `E = 5` (ponto fixo); `epocas` parametrizável em 1..256 |
| D8 | conjunto de 4 pares `9→12, 12→13, 13→14, 14→24` |
| D9 | perda observável como inteiro `S`; `L = S/524288` apenas derivada |
| D10 | erros 1..5 com precedência `n → épocas → ids → parâmetros` |
| D11 | sem rollback em `ESTOURO_NUMERICO`; reinicializar é responsabilidade do chamador |
| D12 | oráculo inteiro independente + conferência racional exata |
| D13 | prefixos `treino_`/`TREINO_`; sem dependência de M1/M3/M4 no módulo |
| D14 | nenhum commit, push, tag ou operação remota |

## 18. Registro de execução

Execução autônoma aprovada em 26/10/2026. Nenhum valor canônico, oráculo ou
critério foi alterado para "fazer passar".

### 18.1 Pré-voo e E0

| Item | Resultado |
| --- | --- |
| branch / `HEAD` | `main` / `d7175dd6c7ccdbac5b3f669038f94ca29140f519`, 0 ahead / 0 behind |
| suíte de partida | 58 PASS / 0 FAIL, exit `0` |
| M1 / M3 / M4 | 21/21, 19/19, 22/22, exit `0` |
| autoteste de partida | 0 PASS / 1 FAIL, exit `1` |
| E0 | 14 sondas em `temp/e0-trn/`, todas PASS; nenhum gate G1–G9 disparado |

### 18.2 Etapas

| Etapa | Entrega | Evidência |
| --- | --- | --- |
| E1 | constantes, validadores, init, impressoras | tabela inicial canônica de 25 linhas confere |
| E2 | `treino_emb16`, `treino_z256`, `treino_delta256`, argmax, perda, acertos | `PERDA=3674036`, `ACERTOS=0`, `PRED=10 19 6 11` |
| E3 | `treino_div_arredondada`, execução de 1 época | `HISTORICO=3674036 428488`, `ACERTOS=2`, `PRED=14 1 14 24` |
| E4 | execução de E épocas, estado final, alterados | `HISTORICO=... 27804`, `MAXIMO16=11 6`, `91 W + 23 b` |
| E5 | gradiente por diferença central e restauração | `GRAD_EXATOS=125`, `GRAD_TOTAL=125`, `GRAD_SOMA=-8960` |
| E6 | builder, 12 casos, bloco aditivo no runner | suíte 70/70, exit `0`, duas execuções |
| E7 | verificador independente e regressão | 23/23, exit `0`; M1/M3/M4 sem regressão |

O bloco aditivo em `scripts/test.ps1` tem 26 inserções e 0 remoções; BOM UTF-8 e
último byte `0x7D` preservados. O runner concatena stdout e stderr, por isso os
drivers usam arrays de 16 posições (arrays de tamanho 1 emitem `AVISO`).

### 18.3 Evidência de aprendizado

```
HISTORICO=3674036 428488 107796 41544 30998 27804
PERDA=27804   ACERTOS=4   PRED=12 13 14 24
S5/S0 = 0,007567699391078367   queda = 3.646.232 (99,24323006089216%)
ALTERADOS_W=91   ALTERADOS_B=23   (114/125)
MAXIMO16=11 6
```

| época | `S` | acertos | predições |
| ---: | ---: | ---: | --- |
| 0 | 3674036 | 0/4 | 10 19 6 11 |
| 1 | 428488 | 2/4 | 14 1 14 24 |
| 2 | 107796 | 4/4 | 12 13 14 24 |
| 3 | 41544 | 4/4 | 12 13 14 24 |
| 4 | 30998 | 4/4 | 12 13 14 24 |
| 5 | 27804 | 4/4 | 12 13 14 24 |
| 6 | 27804 | 4/4 | 12 13 14 24 |

Ponto fixo comprovado: uma época adicional após as 5 não altera nenhum dos 125
parâmetros (`PONTO_FIXO=OK`, `CODIGO6=0`).

Logit do alvo em cada par, inicial → final (margem sobre o segundo colocado no
estado final entre parênteses):

```
9→12   -262 → 259  (231)
12→13  -157 → 222  (194)
13→14   107 → 239  (207)
14→24   -81 → 244  (212)
```

Contribuição de cada par para `S`: `1298270 → 2632`, `440054 → 9948`,
`1569094 → 5344`, `366618 → 9880` (soma `3674036 → 27804`).

Gradiente na inicialização: `125/125` diferenças centrais exatas,
`GRAD_SOMA = -8960`, estado restaurado (`PARAM16=12 -3 2 7 12 -1`).

Limites medidos: `n=1` (`9→12`) `HISTORICO=1298270 31576`, 1/1 acerto,
`PRED=12`; `n=16` (4 pares repetidos) `HISTORICO=14696144 123992`, 16/16,
`PRED=12 13 14 24` repetido 4 vezes. Estouro testemunho: `CODIGO=5` e estado
parcial `PARAM16=5 -45 -42 -40 -37 62`. Erros 1..4 preservam o estado
(`INTACTO=OK` em 5 cenários); a guarda do gradiente usa limite 47 e aceita
`|v| = 48`.

### 18.4 Comandos e saídas

```text
scripts/build-training-tests.ps1      Generated 12 training cases in temp/training-tests   exit 0
scripts/test.ps1                      Passed: 70  Failed: 0   exit 0   (execução 1)
scripts/test.ps1                      Passed: 70  Failed: 0   exit 0   (execução 2)
scripts/test.ps1 -SelfTest            Passed: 0   Failed: 1   exit 1
scripts/verify-bytes.ps1              Total: 21 verificacoes, 0 falha(s)   exit 0
scripts/verify-embedding-bytes.ps1    Total: 19 verificacoes, 0 falha(s)   exit 0
scripts/verify-network-bytes.ps1      Total: 22 verificacoes, 0 falha(s)   exit 0
scripts/verify-training-bytes.ps1     Total: 23 verificacoes, 0 falha(s)   exit 0
```

`temp/training-tests` contém 12 `.por` e 12 `.expected`; os `.expected` são ASCII,
sem BOM, LF interno e sem LF final; `trn_determinismo_a` e `trn_determinismo_b`
são byte a byte idênticos, tanto nos `.expected` quanto nas saídas dos processos.

### 18.5 Estado do repositório

```
 M scripts/test.ps1
?? docs/training-plan.md
?? docs/training-spec.md
?? scripts/build-training-tests.ps1
?? scripts/verify-training-bytes.ps1
?? src/treino.por
```

Hashes de `HEAD` inalterados em `src/tokenizador.por`, `src/embeddings.por`,
`src/rede.por`, `scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`,
`scripts/build-embedding-tests.ps1`, `scripts/verify-embedding-bytes.ps1`,
`scripts/build-network-tests.ps1` e `scripts/verify-network-bytes.ps1`. Nenhum
commit, push, tag ou operação remota foi executado.

```
S0 = 3674036      L0 = 7.00766754150390625
S1 = 428488       L1 = 0.8172760009765625
S2 = 107796       L2 = 0.20560455322265625
S3 = 41544        L3 = 0.0792388916015625
S4 = 30998        L4 = 0.059123992919921875
S5 = 27804        L5 = 0.05303192138671875
queda = 3646232   queda_pct = 99.2432
G_W = 5376        G_B = -14336       GRAD_SOMA = -8960
det(emb 4x4) = -55296
limite_S(48) = 1677721600
```

## Apêndice B — Tabela de `r(num, den)`

```
r(0,64)=0        r(31,64)=0       r(32,64)=1       r(33,64)=1
r(-31,64)=0      r(-32,64)=-1     r(-33,64)=-1
r(511,1024)=0    r(512,1024)=1    r(513,1024)=1
r(-511,1024)=0   r(-512,1024)=-1  r(-513,1024)=-1
r(1,1024)=0      r(-1,1024)=0
```
