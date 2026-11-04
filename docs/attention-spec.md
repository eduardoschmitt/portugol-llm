# Especificação - Mecanismo de atenção causal mínimo (M10)

- **Status:** planejamento apenas. Nenhum arquivo de código, script, corpus ou
  teste foi criado ou alterado nesta fase. Nenhum commit, push, tag ou branch.
- **Versão:** `v0.1.0` (congelada ao fim do planejamento; qualquer mudança exige
  nova aprovação).
- **Plano de execução:** `docs/attention-plan.md`.
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md`), M3
  (`docs/embeddings-spec.md`), M4 (`docs/network-spec.md`), M5
  (`docs/training-spec.md`), M6 (`docs/generation-spec.md`), M7
  (`docs/context-spec.md`), M8 (`docs/corpus-spec.md`) e M9
  (`docs/evaluation-spec.md`).
- **Fora de escopo:** Transformer completo, múltiplas cabeças, softmax,
  exponencial, camada residual, layer norm, feed-forward, pilha de camadas,
  attention treinada por retropropagação, embeddings treináveis, dados novos,
  alteração de M1-M9, commit, push e operação remota.

## 1. Contrato

Esta missão define **um** mecanismo de atenção causal, determinístico e
inteiro, aplicado sobre os mesmos três tokens de contexto da M7, com pesos de
atenção observáveis e aprendidos por um método declarado. O contrato é:

1. representar no máximo `T = 3` posições, cada uma com o embedding congelado
   `e16` da M3 (4 dimensões em 1/16);
2. calcular, para cada consulta `i`, escores `s(i,j)` apenas para `j <= i`
   (máscara causal), com `j > i` valendo zero e sendo proibido de influenciar a
   saída;
3. normalizar os escores em pesos `p(i,j) >= 0` que somam 1, sem exponencial;
4. produzir um contexto agregado `c[4]`, em 1/16, como média ponderada dos
   embeddings permitidos;
5. prever o próximo token com uma camada afim `4 -> 25`, em aritmética inteira
   idêntica em convenção à M7;
6. aprender os 7 parâmetros de atenção (`a[4]` e `beta[3]`) e os 125 parâmetros
   da camada afim (`w[100]`, `b[25]`) a partir dos **mesmos 10 exemplos** da M8;
7. ser determinístico byte a byte e não mutar o estado durante inferência;
8. não alterar nenhum módulo, corpus, teste ou verificador de M1-M9.

### 1.1 O que esta missão entrega (planejado)

- `docs/attention-spec.md` (este documento) e `docs/attention-plan.md`;
- `src/atencao.por` (fragmento novo, autossuficiente);
- `scripts/attention-oracle.ps1` (O1/O2 independentes);
- `scripts/build-attention-tests.ps1` (gera casos `.por` e `.expected`);
- `scripts/test-attention.ps1` (runner M10 separado);
- `scripts/verify-attention-bytes.ps1` (V1-V13);
- atualização **somente de escopo** em `scripts/verify-context-bytes.ps1`,
  `scripts/verify-corpus-bytes.ps1` e `scripts/verify-evaluation-bytes.ps1`,
  com os pins correspondentes.

Nenhum arquivo de M1-M9 é alterado em conteúdo funcional.

### 1.2 Atenção não é Transformer

| Conceito | Esta missão | Não é |
| --- | --- | --- |
| Atenção | média ponderada causal de embeddings por escores aprendidos | autoatenção multi-head com projeções Q/K/V |
| Normalização | ReLU + divisão inteira (sem exp) | softmax |
| Valores | embeddings congelados (V = identidade) | V projetado e treinado |
| Consulta | constante por sequência (pesos dependem da chave e da posição) | consulta como vetor de conteúdo |
| Profundidade | uma única agregação + uma camada afim | bloco Transformer (residual + norm + FFN) |
| Treinamento | regra delta na afim + descida coordenada discreta na atenção | retropropagação através de softmax |

A missão mede se **ponderação seletiva de contexto** ajuda. Ela não prova
equivalência com atenção de Transformers nem que atenção melhora generalização.

## 2. Estudo comparativo de arquiteturas

Todas as alternativas foram avaliadas contra as restrições do projeto:
Portuguol inteiro, sem `real` no caminho quente, sem bibliotecas, sem
exponencial, determinístico, verificável byte a byte e treinável com oráculo
independente.

| Arquitetura | Parâmetros | Custo em Portugol | Overflow | Treinamento | Interpretabilidade | Veredito |
| --- | --- | --- | --- | --- | --- | --- |
| Aditiva com viés posicional (escolhida) | 7 | baixo: 4 multiplicações por escore | limitado e provado (§5) | descida coordenada discreta + regra delta | pesos `p(i,j)` e `a`,`beta` impressos | **escolhida** |
| Produto escalar com Q, K, V e softmax | 32+ e exp | alto: projeções, exp e normalização | exp e somas exigem escala extra | retropropagação com Jacobiano do softmax | alta, mas não verificável sem `real` | rejeitada |
| Produto escalar sem softmax (ReLU) | 32 | médio-alto | moderado | coordenada sobre 32 parâmetros | média | rejeitada por custo |
| Atenção dura (`argmax`) | 4 a 7 | baixo | baixo | não diferenciável; busca combinatória | alta | rejeitada |
| Pesos fixos uniformes | 0 | trivial | trivial | não aprende | total | mantida como baseline X2 |
| Pesos fixos de recência | 0 | trivial | trivial | não aprende | total | mantida como baseline X3 |

### 2.1 Por que Q/K/V com softmax foi rejeitada

1. `exp` não existe em Portugol inteiro; aproximá-la por série truncada cria
   divergência entre `.por` e oráculo e destrói a comparação byte a byte.
2. O gradiente do softmax exige o Jacobiano `diag(p) - p p^T`; implementá-lo
   em inteiro com divisões introduces erro de arredondamento acumulado sem
   oráculo simples.
3. A faixa de `exp` estoura 32 bits para escores acima de ~88 em ponto fixo.
4. 32 parâmetros extras aumentam o custo da busca discreta sem ganho
   demonstrável em 10 exemplos.

### 2.2 Por que pesos fixos não contam como aprendizado

Pesos uniformes ou de recência são **baselines**, não atenção aprendida. Eles
aparecem na avaliação (X2/X3) exatamente para medir quanto do efeito, se
houver, vem de aprender os pesos. Nenhum documento desta missão chama pesos
fixos de "atenção treinada".

### 2.3 Por que a escolhida é aditiva

- O escore é uma soma de produtos inteiros, sem exponencial.
- Os 7 parâmetros cabem em uma busca discreta exata (`-16..16`), com perda
  avaliada por aritmética inteira idêntica à do `.por`.
- Cada peso `p(i,j)` é diretamente impresso e auditável.
- O limite de overflow é demonstrável (§5) e o pior caso fica abaixo de 2^31.
- A implementação reutiliza as convenções da M7 (`e16`, unidades 1/16,
  arredondamento meio para longe de zero, argmax com empate no menor `y`).

## 3. Arquitetura escolhida

### 3.1 Dimensões e constantes

| Constante | Valor | Significado |
| --- | --- | --- |
| `AT_T` | 3 | posições máximas (igual a `K=3` da M7) |
| `AT_D` | 4 | dimensão do embedding (M3) |
| `AT_V` | 25 | vocabulário (M1) |
| `AT_PARAMS_AT` | 7 | `a[4]` + `beta[3]` |
| `AT_W` | 100 | `w[y*4 + d]` |
| `AT_B` | 25 | `b[y]` |
| `AT_PARAMS` | 132 | 7 + 100 + 25 |
| `AT_LIMITE` | 16 | `|a|, |beta|, |w|, |b| <= 16` (1/16) |
| `AT_VALOR_MIN` | -16 | menor valor de busca |
| `AT_VALOR_MAX` | 16 | maior valor de busca |
| `AT_RODADAS` | 6 | rodadas de treinamento alternado |
| `AT_EPOCAS` | 4 | épocas da regra delta por rodada |
| `AT_LOTE` | 6 | exemplos por lote (como M8) |
| `AT_ESCALA` | 131072 | escala da perda (igual a M7) |
| `AT_MAX_EXEMPLOS` | 10 | exemplos do corpus M8 |

### 3.2 Embedding congelado

Igual à M3/M7, sem depender do módulo:

```
e16(id, d) = ((id * 7 + d * 3) mod 32) - 16
```

para `0 <= id <= 24` e `0 <= d <= 3`. `UNK = 0` é um token válido.
**Padding não é um ID**: posições inexistentes simplesmente não entram na
soma; nunca se usa `id = 0` como marcador de padding.

### 3.3 Escore causal

Para consulta `i` (0-based, `0 <= i < n`) e chave `j`:

```
s(i,j) = soma_{d=0..3} a[d] * e16(id_j, d) + beta[j]     se j <= i
s(i,j) = 0 e p(i,j) = 0                                   se j > i
```

Observação explícita: a consulta é **constante**; os escores dependem apenas
da chave e da posição. Isso é uma forma mínima de atenção aditiva, não a
atenção Q/K/V completa (§1.2).

### 3.4 Pesos

```
u_j    = max(0, s(i,j))
U      = soma_{j=0..i} u_j
p(i,j) = u_j / U                       se U > 0
p(i,j) = 1 / (i + 1)                   se U = 0   (fallback uniforme)
```

`p` é reportado em permilagem: `permil(i,j) = r(1000 * u_j, U)`, com
`r(num, den)` definido em §3.7. A soma das permilagens pode diferir de 1000
em no máximo `i` unidades por arredondamento; o teste de normalização usa
essa tolerância explícita.

### 3.5 Contexto agregado

```
c[d] = r( soma_{j=0..i} u_j * e16(id_j, d), U )      se U > 0
c[d] = r( soma_{j=0..i} e16(id_j, d), i + 1 )        se U = 0
```

`c` permanece em 1/16, pois `u_j` cancela no quociente.

### 3.6 Predição

```
Z256(c, y) = soma_{d=0..3} w[y*4 + d] * c[d] + 16 * b[y]
pred       = argmax_y Z256(c, y)
```

`Z256` está em 1/256; `argmax` percorre `y = 0..24`, inicializa em `y = 0` e
troca apenas com `>` estrito (empate: menor `y`). Convenção idêntica à M7.

### 3.7 Arredondamento

```
r(num, den) = sinal(num) * floor((|num| + den/2) / den),  den > 0
```

Meio para longe de zero. `den` pode ser `U` (inclusive ímpar) ou `i+1`; a
divisão inteira de `(|num| + den/2)` é determinística e idêntica em O1/O2/O3.

### 3.8 Inicialização canônica

```
a[d]    = 0                      (0 <= d <= 3)
beta[j] = 0                      (0 <= j <= 2)
b[y]    = 0
w[y*4+d] = ((y * 7 + d * 3) mod 9) - 4
```

`a = beta = 0` implica `u_j = 0` e o fallback uniforme: a atenção começa
uniforme, o que é declarado e testado. `w` fica em `[-4, 4]`, sem estourar o
limite de 16.

## 4. Exemplo numérico completo

Todos os números abaixo foram calculados com as equações acima (verificados
por script durante o planejamento; serão reimplementados em O1/O2/O3).

### 4.1 Entradas

Sequência `ids = (3, 12, 5)`, consulta `i = 2` (última posição). Embeddings:

| id | `e16(id,0)` | `e16(id,1)` | `e16(id,2)` | `e16(id,3)` |
| --- | --- | --- | --- | --- |
| 3 | 5 | 8 | 11 | 14 |
| 12 | 4 | 7 | 10 | 13 |
| 5 | -13 | -10 | -7 | -4 |

Parâmetros de atenção: `a = (16, 16, 16, 16)`, `beta = (0, 1, -1)`.

### 4.2 Escores e pesos

| j | `a . e_j` | `beta[j]` | `s(2,j)` | `u_j` | `permil` |
| --- | --- | --- | --- | --- | --- |
| 0 | 608 | 0 | 608 | 608 | 527 |
| 1 | 544 | 1 | 545 | 545 | 473 |
| 2 | -544 | -1 | -545 | 0 | 0 |

`U = 608 + 545 + 0 = 1153`. `p = (608/1153, 545/1153, 0)`, ou seja
`(0,527; 0,473; 0,000)`. A posição 2 recebe peso zero porque o escore é
negativo (ReLU).

### 4.3 Contexto agregado

| d | numerador `soma u_j e_j[d]` | divisão | `c[d]` |
| --- | --- | --- | --- |
| 0 | 608*5 + 545*4 = 5220 | 5220/1153 = 4,527 | 5 |
| 1 | 608*8 + 545*7 = 8679 | 8679/1153 = 7,527 | 8 |
| 2 | 608*11 + 545*10 = 12138 | 12138/1153 = 10,527 | 11 |
| 3 | 608*14 + 545*13 = 15597 | 15597/1153 = 13,527 | 14 |

`c = (5, 8, 11, 14)`.

### 4.4 Predição e perda de uma linha

Tome a linha `y = 7` com `w[7*4+d] = (1, 0, -1, 2)` e `b[7] = 1`:

```
Z256 = 1*5 + 0*8 + (-1)*11 + 2*14 + 16*1 = 5 - 11 + 28 + 16 = 38
```

Se o alvo do exemplo fosse `t = 7`:

```
delta_7 = Z256 - 256 = 38 - 256 = -218
delta_7^2 = 47524
```

A perda total do exemplo é `soma_{y=0..24} delta_y^2`; este exemplo mostra
apenas a parcela da linha alvo.

### 4.5 Uma atualização da regra delta

Com `delta_7 = -218`:

```
w_novo[d] = r(2048 * w[d] - delta_7 * c[d], 2048)
```

| d | conta | novo |
| --- | --- | --- |
| 0 | (2048*1 + 218*5)/2048 = 3138/2048 = 1,532 | 2 |
| 1 | (2048*0 + 218*8)/2048 = 1744/2048 = 0,852 | 1 |
| 2 | (2048*(-1) + 218*11)/2048 = 350/2048 = 0,171 | 0 |
| 3 | (2048*2 + 218*14)/2048 = 7148/2048 = 3,490 | 3 |

`b_novo[7] = r(128*1 + 218, 128) = r(346, 128) = 3`.

### 4.6 Máscara e padding

- Com `a = (0,0,0,0)` e `beta = (0,0,10)`: `s = (0,0,10)`, `u = (0,0,10)`,
  `p = (0,0,1)`, `c = e16(5) = (-13,-10,-7,-4)`.
- Para a mesma configuração com `n = 2` (ids 3 e 12), o índice `j = 2` está
  fora da máscara e não entra na soma; `U = 0` e o fallback uniforme dá
  `p = (1/2, 1/2)` e `c[d] = r(e16(3,d) + e16(12,d), 2)`, isto é
  `(5, 8, 11, 14)` por arredondamento de `4,5`, `7,5`, `10,5`, `13,5`.
- Para `n = 1` (id 3), `p = (1)`, `c = (5,8,11,14)`.
- Acrescentar tokens depois da consulta não pode mudar `p` nem `c`; esse é o
  teste de causalidade V4 (§12).

### 4.7 Plataforma da busca coordenada

Trocar `a[0]` de 16 para 15 mantém `c = (5,8,11,14)` (os pesos mudam para
`(325, 297, 0)`, mas a média ponderada arredonda para o mesmo vetor). Como a
perda não diminui estritamente, a troca é rejeitada. Isso ilustra o platô
discreto que o plano trata como risco.

## 5. Limites numéricos

Estado válido: `|a|, |beta|, |w|, |b| <= 16`; `|e16| <= 16`; `c` é média de
embeddings e também satisfaz `|c| <= 16`.

| Grandeza | Pior caso | Conta |
| --- | --- | --- |
| `|s|` | 1040 | 4*16*16 + 16 |
| `U` | 3120 | 3*1040 |
| numerador de `c` | 49920 | 3120*16 |
| `|Z256|` | 1280 | 4*16*16 + 16*16 |
| `|delta|` | 1536 | 1280 + 256 |
| `delta^2` | 2359296 | 1536^2 |
| perda com 10 exemplos | 589824000 | 25*10*2359296 |
| `|2048*w - delta*c|` | 57344 | 2048*16 + 1536*16 |
| `|128*b - delta|` | 3584 | 128*16 + 1536 |

O maior valor, `589824000`, é menor que `2^31 - 1 = 2147483647`. Não há
necessidade de `BigInteger` no `.por`; o oráculo O2 usa `BigInteger` apenas
para auditar somas e o limite.

A perda escalada publicada é:

```
L_escala = soma_{exemplos} soma_y delta_y^2
MILES    = r(1000 * L_escala, 25 * n * 131072)
```

com `n` exemplos avaliados. `MILES` fica em `0..~1000` e é comparável entre
estados, como na M9.

## 6. Dados

- **Treino:** exatamente os 10 exemplos `(contexto de 3 IDs, alvo)` extraídos
  do corpus congelado M8 (`corpus/m8-corpus-v1.txt`, SHA-256 `d6eb8a78...`),
  sem cruzar linhas. Nenhum dado novo.
- **Avaliação:** conjuntos A (10 vistos), B (10 vistos + 10 inéditos), C (32
  contextos inéditos), C_SEM_PARE (24), D (10 com alvo trocado), definidos em
  `docs/evaluation-spec.md`. Os literais vêm de `scripts/eval-datasets.ps1`
  por dot-sourcing, sem cópia manual.
- **Holdout M9:** reutilizado como **benchmark histórico**, não como teste
  independente. O resultado de M10 em C não é uma segunda confirmação
  out-of-sample; é uma comparação no mesmo benchmark já observado. Isso fica
  explícito no relatório e no veredito.
- Nenhum hiperparâmetro de M10 é escolhido olhando C.

## 7. Treinamento

### 7.1 Função de perda

```
L(w, b, a, beta) = soma_{n=0..N-1} soma_{y=0..24}
                   (Z256(c_n, y) - 256 * [y == t_n])^2
```

Idêntica em forma à M7, mas com `c_n` produzido pela atenção. `L` é inteira e
não negativa.

### 7.2 Regra delta para a camada afim

Para cada exemplo, com `delta_y = Z256(c, y) - 256*[y == t]` congelado antes
de qualquer escrita:

```
w[y*4+d] <- r(2048*w[y*4+d] - delta_y * c[d], 2048)
b[y]     <- r(128*b[y] - delta_y, 128)
```

Essa é a mesma regra da M7/M8, com `2048` e `128` como taxas inteiras. Ela é
uma descida de gradiente escalada em `1/2048` e `1/128` sobre `L` (o fator 2
do gradiente é absorvido pela taxa). Não é retropropagação através da
atenção.

### 7.3 Atenção por descida coordenada

Os 7 parâmetros de atenção são inteiros em `[-16, 16]`. Para cada rodada:

1. reajustar `w,b` para a configuração atual: reiniciar pela fórmula canônica
   (§3.8) e aplicar `AT_EPOCAS = 4` épocas da regra delta;
2. para cada parâmetro na ordem fixa `a[0], a[1], a[2], a[3], beta[0],
   beta[1], beta[2]`:
   - avaliar a perda para cada valor candidato `v = -16..16`, **reiniciando
     `w,b` pela fórmula canônica e refazendo as 4 épocas** para cada candidato;
   - escolher o `v` de menor perda; empate: menor `|v|`, depois menor `v`;
   - aceitar somente se a perda for **estritamente** menor que a atual;
3. se nenhum parâmetro mudou, parar;
4. aceitar a rodada somente se `L_final <= L_inicial`; caso contrário, reverter
   `w,b,a,beta` ao início da rodada e parar;
5. repetir até `AT_RODADAS = 6`.

**Correção registrada em E4.** A primeira redação desta seção avaliava os
candidatos com `w,b` congelados. Com `w,b` ótimos para a atenção anterior, a
perda `L(w,b,a,beta)` não pode melhorar trocando apenas `(a,beta)` e mantendo
`w,b`: a varredura nunca sairia do ponto inicial. O procedimento acima
reajusta a leitura para cada candidato, tornando a perda comparada uma função
determinística de `(a,beta)`. Isso é correção de uma inconsistência
matemática, não ajuste de hiperparâmetro para atingir limiar: arquitetura,
faixas, ordem, desempate, rodadas e épocas permanecem os pré-registrados.

Cada varredura custa `7 * 33 = 231` reajustes de leitura; cada reajuste
percorre 4 épocas sobre 10 exemplos e 25 classes. Isso é uma busca discreta
exata sobre a grade, não gradiente através da atenção: a perda é reavaliada,
não aproximada.

### 7.4 Convergência e parada

- **Convergência:** rodada completa sem nenhuma alteração de parâmetro.
- **Parada antecipada:** perda da rodada não diminui (reversão e parada).
- **Limite duro:** 6 rodadas.
- **Critério de falha (gate G3):** se a perda final for maior ou igual à
  inicial, o treinamento é declarado não convergente e o experimento segue
  apenas como diagnóstico, sem alegar aprendizado.
- A perda é registrada por rodada como inteiro **bruto** `L`, não em permilagem
  (`MILES`): `1000*L` estouraria 32 bits nos casos extremos. O relatório
  publica `L`, e os limites de §5 são calculados sobre `L`.

### 7.5 O que é e não é aprendido

- Aprendido: `a[4]` (saliência de chave), `beta[3]` (viés posicional),
  `w[100]` e `b[25]` (leitura).
- Não aprendido: embeddings (congelados), projeções Q/K/V (inexistentes),
  número de cabeças (1), máscara causal (fixa), fallback uniforme (fixo).
- A atenção é aprendida no sentido estrito de que os pesos `p(i,j)` são
  função de parâmetros ajustados por minimização de `L`, não fixados a priori.

## 8. API pública planejada

`src/atencao.por` é um fragmento sem `programa`/`inicio`, concatenado pelo
builder. Todas as funções usam apenas `inteiro`, `logico` e `cadeia`.

| Função | Assinatura | Retorno |
| --- | --- | --- |
| `at_abs` | `(inteiro v)` | `|v|` |
| `at_id_valido` | `(inteiro id)` | `0 <= id <= 24` |
| `at_n_valido` | `(inteiro n)` | `1 <= n <= 3` |
| `at_seq_valida` | `(inteiro ids[], inteiro n)` | `logico` |
| `at_params_validos` | `(inteiro a[], beta[], w[], b[])` | todos em `[-16,16]` |
| `at_div_arredondada` | `(inteiro num, den)` | `r(num,den)` |
| `at_e16` | `(inteiro id, d)` | `e16` |
| `at_escopo` | `(inteiro i, j)` | `j <= i` |
| `at_score` | `(inteiro a[], beta[], ids[], i, j)` | `s(i,j)` ou 0 fora da máscara |
| `at_pesos` | `(a[], beta[], ids[], n, i, modo, u[], permil[])` | `U`; `u`/`permil` preenchidos |
| `at_contexto` | `(a[], beta[], ids[], n, i, modo, c[4])` | `U`; `c` preenchido |
| `at_ctx_interno` | `(a[], beta[], ids[], i, modo, c[4])` | `U`, sem validação |
| `at_pesos_interno` | `(a[], beta[], ids[], i, modo, u[], permil[])` | `U`, sem validação |
| `at_z256` | `(w[], b[], c[], y)` | `Z256` |
| `at_argmax` | `(w[], b[], c[])` | `y` |
| `at_perda` | `(w[], b[], a[], beta[], entradas[], alvos[], n, modo, saida[2])` | código; `saida[0] = L` |
| `at_validar` | `(a[], beta[], w[], b[], entradas[], alvos[], n, modo, epocas)` | código 0 ou erro |
| `at_treinar_afim` | `(w[], b[], a[], beta[], entradas[], alvos[], n, modo, epocas)` | código |
| `at_ajustar_leitura` | `(w[], b[], a[], beta[], entradas[], alvos[], n, modo)` | código; reinicia `w,b` e aplica 4 épocas |
| `at_varredura` | `(w[], b[], a[], beta[], entradas[], alvos[], n, modo)` | alterações `0..7` ou `-código` |
| `at_treinar` | `(w[], b[], a[], beta[], entradas[], alvos[], n, modo, hist[7], info[3])` | código |
| `at_acertos` | `(w[], b[], a[], beta[], entradas[], alvos[], n, modo)` | acertos |
| `at_acertos_tipo` | `(w[], b[], a[], beta[], entradas[], alvos[], tipo[], n, modo, filtro)` | acertos |
| `at_margem` | `(w[], b[], a[], beta[], ids[], n, alvo)` | `Z256(alvo) - max_{y!=alvo}` |
| `at_limites` | `()` | imprime casos extremos |
| `at_imprimir_*` | várias | relatório ASCII |

Dimensões: `a[4]`, `beta[3]`, `w[100]`, `b[25]`, `c[4]`, `u[3]`,
`permil[3]`, `ids[3]`, `entradas[30]`, `alvos[10]`, `hist[7]`, `info[3]`.

### 8.1 Códigos de erro

| Código | Significado | Precedência |
| --- | --- | --- |
| 1 | `n` fora de `1..3` | 1 |
| 2 | ID fora de `0..24` | 2 |
| 6 | modo fora de `0..2` | 3 |
| 3 | parâmetro fora de `[-16,16]` | 4 |
| 4 | épocas/rodadas fora da faixa | 5 |
| 5 | inconsistência interna (overflow/estado parcial) | 6 |

A validação ocorre antes de qualquer escrita: em erro 1, 2, 6, 3 e 4 o estado
não é alterado. Em erro 5 o estado pode ficar parcial e o relatório deve
declarar isso. A precedência efetiva é `1, 2, 6, 3, 4, 5`.

### 8.2 Formato do relatório

ASCII, LF, um LF final, sem `real`, `NaN`, `Infinity`, `-0` ou `e+`:

```
ATEN V1
ESTADO <NAO_TREINADO|UNIFORME|RECENCIA|TREINADO>
TREINO <n> <rodadas> <loss0> <lossN> <alteracoes> <convergiu>
PESO a <d> <v>
PESO beta <j> <v>
AT <i> <j> <s> <u> <permil> <permitido>
RESUMO <estado> <conjunto> <n> <acertos> <bp> <perda>
EX <estado> <conjunto> <i> <id0> <id1> <id2> <alvo> <pred> <ok>
CONF <estado> <conjunto> <alvo> <pred> <contagem>
DELTA_BP <estado> <conjunto> <bp_a> <bp_b> <delta>
CHECK <estado> <CAUSAL|PADDING|NORMALIZACAO|MUTACAO> OK|FALHA
LIMITES <caso> <codigo>
CHECKSUM <valor>
FIM
```

Cada relatório começa em `ATEN V1` e termina em `FIM`; um mesmo caso pode
emitir dois relatórios completos (ex.: `UNIFORME` e `TREINADO`) desde que cada
um tenha o par completo. `TREINO` traz 6 campos após a palavra-chave: `n`,
rodadas executadas, perda inicial `L`, perda final `L`, total de alterações de
atenção e `convergiu` (0/1). `perda` em `RESUMO` é `L` bruto, não permilagem.

## 9. Protocolo experimental

### 9.1 Estados avaliados

| Estado | Atenção | Leitura | Papel |
| --- | --- | --- | --- |
| `M8` | inexistente (contexto concatenado) | `w16/b16` congelados | referência histórica (M9) |
| `NAO_TREINADO` | canônica | canônica | piso inferior |
| `UNIFORME` | `a=beta=0` fixos | treinada | isola o efeito de ponderar |
| `RECENCIA` | pesos fixos `(1,2,4)` | treinada | baseline de posição sem aprendizado |
| `TREINADO` | `a,beta` aprendidos | treinada | M10 |

Todos os estados treinados usam os mesmos 10 exemplos e a mesma inicialização
canônica de `w,b`; apenas a atenção difere.

### 9.2 Métricas

- Acurácia top-1 e `BP` por conjunto (A, B, B_VISTO, B_INEDITO, C,
  C_SEM_PARE, D), como na M9.
- Perda escalada e `MILES` por conjunto.
- Margem média e matriz de confusão resumida.
- Sensibilidade à ordem: permutar os 3 tokens e contar mudanças de predição
  (comparável ao 106/192 da M9).
- Sensibilidade ao padding: mesma sequência com `n = 1,2,3`; comparar `c`,
  pesos e predição.
- Causalidade: alterar tokens `j > i` e exigir saída idêntica.
- Distinguibilidade de posição: `beta[j]` aprendidos e variação dos pesos ao
  trocar a ordem.

### 9.3 Critério pré-registrado

M10 só declara **evidência de que a atenção ajuda** se todas valerem:

1. `BP_C(M10) >= 4500` (o que força, no mínimo, 15/32), pois o maior baseline
   em C é 2500 e o critério da M9 exige 20 pp;
2. `Delta = BP_C(M10) - max(BP_C(M8)=1250, BP_C(memorizacao)=2500,
   BP_C(majoritario)=2500, BP_C(nao_treinado)=938) >= 2000`;
3. C usado integralmente (32 predições, sem filtro);
4. validade: causalidade, padding, normalização, não mutação, determinismo e
   regressão M1-M9 verdes;
5. atenção não degenerada: ao menos um contexto de C com pesos não uniformes
   e alteração de um token anterior muda ao menos um peso em algum caso.

Se qualquer condição falhar, o veredito é `SEM_EVIDENCIA`. Se houver
vazamento, mutação, não determinismo ou regressão, é `INVALIDO`.

### 9.4 Comparações reportadas

- `M10 - M8` em C, A e B (delta de `BP`).
- `M10 - UNIFORME` (efeito de aprender pesos).
- `M10 - RECENCIA` (efeito de aprender versus posição fixa).
- `M10 - baselines M9` (memorização, majoritário, não treinado).
- Custo: parâmetros, operações por predição e tempo de treino.

Nenhum desses números ajusta limiar, dados ou inicialização depois de vistos.

## 10. Matriz de testes

| ID | Caso | Tipo | Verifica |
| --- | --- | --- | --- |
| T1 | `at_limites` | extremo | códigos 1-6, precedência, estado parcial |
| T2 | `at_mascara` | positivo | `j > i` com peso 0 e `s` ignorado |
| T3 | `at_padding` | positivo | `n = 1,2,3` sem PAD-ID; `c` e `p` corretos |
| T4 | `at_pesos` | positivo | soma das permilagens, fallback uniforme |
| T5 | `at_exemplo` | positivo | exemplo de §4 reproduzido byte a byte |
| T6 | `at_nao_treinado` | positivo | estado canônico e métricas iniciais |
| T7 | `at_uniforme` | positivo | atenção uniforme + leitura treinada |
| T8 | `at_recencia` | positivo | pesos fixos + leitura treinada |
| T9 | `at_treinado` | positivo | perda cai, converge, métricas A/B/C/D |
| T10 | `at_ordem` | positivo | permutação de tokens muda/no muda |
| T11 | `at_determinismo_a/b` | positivo | bytes idênticos |
| T12 | `at_causal_futuro` | negativo | token futuro alterado não muda saída |
| T13 | `at_overflow` | extremo | pior caso em `[-16,16]` sem estouro |
| T14 | `at_layout` | negativo | relatório malformado retorna 6 |

Cada caso é um `.por` gerado por `scripts/build-attention-tests.ps1`, com
`.expected` produzido por O1 (nunca pela saída real). O runner compara bytes.
T1-T14 são 14 verificações; T11 consome dois arquivos
(`at_determinismo_a/b`), gerando 15 `.por` e 15 `.expected` no total.

## 11. Oráculos independentes

| Oráculo | Implementação | Escopo | Independência |
| --- | --- | --- | --- |
| O1 | PowerShell com `int` 32 bits | forward, treino, perda, pesos, métricas | reimplementa as equações sem importar o `.por` |
| O2 | PowerShell com `BigInteger` | somas de perda, permilagens, limites | aritmética diferente, sem overflow |
| O3 | literais manuais | exemplo de §4 e 2 casos curtos | calculado sem O1/O2 |
| O4 | `src/atencao.por` | execução real | quarta derivação |

O builder pode usar O1 para `.expected`, mas o verificador recalcula com O1,
O2 e O3 e compara com O4. Um erro compartilhado entre builder e verificador
só seria pego por O2/O3.

## 12. Verificador de integridade (planejado)

| ID | Verificação |
| --- | --- |
| V1 | hashes M1-M9 e `test.ps1` (402 linhas, BOM, sem CR), pins e escopo |
| V2 | corpus M8 e holdout M9 intactos (SHA-256) |
| V3 | contagens de A/B/C/D e 10 exemplos de treino |
| V4 | causalidade: tokens futuros não alteram saída |
| V5 | padding: `n=1,2,3` sem PAD-ID e com `c` correto |
| V6 | pesos normalizados e zero fora da máscara |
| V7 | exemplo numérico de §4 igual em O1/O2/O3/.por |
| V8 | métricas de C iguais em O1/O2 e `.por` |
| V9 | perda de treino cai, converge e é determinística |
| V10 | não mutação do estado durante inferência |
| V11 | determinismo A/B, gramática ASCII/LF, sem `real` |
| V12 | regressão: suíte 116/116, M7 16/16, M8 18/18, M9 13/13 |
| V13 | limites, erros e casos extremos |

Nenhum check pode ser aprovado por redução de cobertura, remoção de caso ou
mudança de resultado esperado.

## 13. Compatibilidade com M1-M9

O padrão de escopo das V1 de M7/M8/M9 usa allowlists literais de
`git status --short` e pins `git hash-object`. Arquivos novos de M10 quebram
V1 exatamente como aconteceu na M9. O plano (§7) inclui uma etapa de
compatibilidade autorizada explicitamente, limitada a:

- `scripts/verify-context-bytes.ps1`: acrescentar 7 caminhos M10 e
  `" M scripts/verify-corpus-bytes.ps1"`, `" M scripts/verify-evaluation-bytes.ps1"`
  à `$allowedStatus`;
- `scripts/verify-corpus-bytes.ps1`: mesmos caminhos e atualizar o pin de M7;
- `scripts/verify-evaluation-bytes.ps1`: acrescentar os caminhos M10 à lista
  `$allowed` e atualizar o pin de M7.

Nenhuma verificação funcional, hash de módulo, contagem ou expectativa muda.

## 14. Critérios de aceitação (AC1-AC12)

| ID | Critério |
| --- | --- |
| AC1 | Somente os arquivos autorizados de M10 foram criados/alterados. |
| AC2 | `scripts/test.ps1` intocado: 402 linhas, BOM, 116/116, exit 0. |
| AC3 | Runner M10 passa todos os casos, exit 0, bytes iguais a O1. |
| AC4 | Causalidade: nenhum token futuro influencia a saída. |
| AC5 | Padding: `n=1,2,3` sem PAD-ID e com contexto correto. |
| AC6 | Pesos observáveis, normalizados e zero fora da máscara. |
| AC7 | Treino: perda estritamente menor que a inicial e convergência declarada. |
| AC8 | Métricas de C iguais em O1, O2, O3 e `.por`. |
| AC9 | Determinismo byte a byte; ASCII/LF; sem `real`. |
| AC10 | Sem regressão: M7 16/16, M8 18/18, M9 13/13, suíte 116/116. |
| AC11 | Veredito de §9.3 emitido com números reais, inclusive negativo. |
| AC12 | Nenhum commit, push, tag ou branch sem autorização. |

## 15. Riscos e limitações

| Risco | Impacto | Mitigação |
| --- | --- | --- |
| Atenção uniforme por platô da busca | alto | reportar; não forçar pesos; comparar com X2/X3 |
| Overfitting nos 10 exemplos | alto | holdout como benchmark histórico; sem tuning em C |
| 7 parâmetros não representam Q/K/V | médio | declarar limitação; não chamar de Transformer |
| ReLU zera todos os escores | médio | fallback uniforme determinístico e testado |
| Descida coordenada presa em mínimo local | médio | reportar perda por rodada e limite de rodadas |
| Overflow em somas intermediárias | alto | prova de §5 e teste T13 |
| Allowlists M7-M9 quebrarem | alto | etapa de compatibilidade explícita (§13) |
| Interpretar melhora em A como generalização | alto | A é memorização; critério usa C |
| Reutilizar C como teste independente | alto | rotulado como benchmark histórico |
| Custo do treino em Portugol | médio | 231 avaliações/varredura, 6 rodadas, medir em E0 |

## 16. O que a missão prova e não prova

**Prova:** que uma ponderação causal de contexto, com pesos derivados de
parâmetros ajustados por uma regra explícita, pode ser implementada em
Portuguol inteiro, é determinística, tem limites numéricos demonstráveis e
pode ser comparada de forma reproduzível com M8 e com baselines fixos.

**Não prova:** que atenção melhora generalização, que o mecanismo equivale a
Q/K/V ou softmax, que 10 exemplos bastam para aprender atenção útil, nem que
o resultado em C se transferiria para outro corpus ou vocabulário.

## 17. Resultado da execução (2026-10-31)

### 17.1 Verificação

- `scripts/test-attention.ps1`: **14/14** verificações, exit 0.
- `scripts/verify-attention-bytes.ps1`: **13/13** (V1-V13), exit 0.
- `scripts/test.ps1`: **116/116**, exit 0.
- M7 **16/16**, M8 **18/18**, M9 **13/13**, exit 0.
- `test.ps1` permaneceu com 402 linhas e blob `e10771b7...`.
- Corpus M8 e holdout M9 com SHA-256 inalterados.

### 17.2 Treino no corpus real

```
TREINO 10 1 810505 529441 0 1
PESO a 0 0 / a 1 0 / a 2 0 / a 3 0
PESO beta 0 0 / beta 1 0 / beta 2 0
```

A perda caiu de `810505` para `529441`, mas **nenhum** parâmetro de atenção
mudou: a atenção uniforme é ótimo local da grade. A varredura custou uma
rodada e convergiu sem alterações. `TREINADO` é, na prática, `UNIFORME`.

Controles que confirmam que a busca funciona quando há sinal: no dataset
sintético balanceado, `TREINO 10 2 756722 517626 1 1`, `beta[2]=1`, BP 6000
contra 5000 da atenção uniforme.

### 17.3 Métricas em C (benchmark histórico, não teste independente)

| Estado | Acertos/32 | BP | Perda |
| --- | --- | --- | --- |
| Não treinado | 0 | 0 | 2361358 |
| Uniforme | 8 | 2500 | 2581936 |
| Recência | 4 | 1250 | 3108867 |
| Treinado (aprendido) | 7 | 2188 | 2463608 |
| Histórico M8 | - | 1250 | - |
| Memorização/majoritário | - | 2500 | - |

`DELTA_BP TREINADO C 2188 1250 938` contra o histórico M8, mas `-312` contra
o maior baseline (uniforme 2500). A vantagem exigida era `>= 2000` BP e
`BP_C >= 4500`; ambos falham. A atenção treinada no corpus não é degenerada
(7 alterações de leitura vieram do ajuste afim, 0 de atenção), mas **não há
evidência** de que a atenção aprendida melhore generalização.

### 17.4 Veredito

**`SEM_EVIDENCIA`.** O mecanismo está implementado, testado e determinístico;
o experimento é válido e negativo. Não se declara aprendizado de atenção útil
no corpus M8, nem se ajusta arquitetura, dados ou limiar para obter outro
resultado.
