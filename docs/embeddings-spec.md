# Especificação — Matriz de embeddings para mini-LLM (M3)

- **Status:** implementado e verificado (E0–E7, 2026-10-25); evidências na §12.
- **Versão:** `v0.1.1` (ajustes de E0 e do oráculo independente).
- **Versão:** `v0.1.1` — ajustes após a sonda E0: `const` só aceita literal; `-0.0` não é
  normalizado pelo runtime e não pode aparecer na saída; a grade `1/16` vale apenas para a
  inicialização canônica, não para valores gravados por `emb_definir`. Nenhuma regra de
  arquitetura mudou. Substitui a v0.1.0.
- **Depende de:** M1 (`docs/tokenizer-spec.md` v0.2.1), que fixa o vocabulário de 25 IDs.
- **Escopo:** manter uma matriz de embeddings determinística, consultável e atualizável por
  célula, com validação explícita de índices e saída textual verificável.
- **Fora de escopo:** treinamento, backpropagation, atenção, camadas, softmax, geração de
  texto, leitura de arquivos, números aleatórios, normalização de vetores, operações
  vetoriais (soma, produto escalar, norma) e qualquer biblioteca externa.

## 1. Contrato

| Item | Definição |
| --- | --- |
| Entrada lógica | um par `(id, dimensão)`, com `id` inteiro e `dimensão` inteiro. |
| Saída lógica | um valor `real` armazenado em `w[id * 4 + dimensão]`. |
| Estado | 100 valores `real` (25 linhas × 4 colunas), indexados por `id * 4 + d`. |
| Inicialização | determinística, por fórmula fechada, sem aleatoriedade (§4). |
| IDs válidos | `0..24`, incluindo `UNK = 0`. |
| Dimensões válidas | `0..3`. |
| IDs inválidos | `id < 0` ou `id > 24` → `ERRO=ID_INVALIDO`. |
| Dimensões inválidas | `d < 0` ou `d > 3` → `ERRO=DIMENSAO_INVALIDA`. |
| Precedência | se `id` e `d` forem inválidos, o erro reportado é `ID_INVALIDO`. |
| Saída observável | linhas textuais definidas em §8, terminadas por `\n`, sem saída parcial. |
| Aleatoriedade | proibida em qualquer ponto do módulo. |
| Dependências | nenhuma biblioteca do Portugol Studio. |

O módulo é um **fragmento** (como `src/tokenizador.por`): não declara `programa` nem
`inicio`; é concatenado a um driver de teste. Incluí-lo não produz saída.

## 2. Vocabulário e dimensão

O vocabulário é herdado da M1 e **não é redefinido** aqui:

| ID | Papel |
| --- | --- |
| `0` | `UNK` — token desconhecido. **É um ID válido e possui linha própria.** |
| `1..24` | as 24 palavras fixas da tabela da M1. |
| `25..` | inexistentes nesta versão; não podem ser mapeados nem reutilizados. |

**Dimensão escolhida: `D = 4`.**

Justificativa:

- 25 × 4 = **100 pesos**: pequeno o bastante para inspeção manual e execução rápida no
  interpretador de console, grande o bastante para que cada linha seja distinta.
- Permite expor o vetor inteiro em uma única linha de saída, sem truncamento.
- Todos os valores cabem na grade `k/16`, com `k ∈ [-16, 15]`, que é **exatamente
  representável** em binário (potência de dois no denominador). Isso elimina dúvidas de
  arredondamento na comparação e na serialização.
- A dimensão é um parâmetro de projeto, não uma constante mágica: crescer para 8 ou 16
  depois é uma mudança localizada (constantes e tabela de referência), sem alterar a API.
- Valores em `[-1.0, 0.9375]`, todos diferentes de zero em pelo menos uma coordenada,
  evitando uma matriz degenerada.

## 3. Estrutura de armazenamento

Armazenamento **plano** (vetor unidimensional) de `real`:

```
real w[100]
w[id * 4 + d]   // id em 0..24, d em 0..3
```

Justificativa:

- O interpretador já executou vetores unidimensionais de inteiros na M1; a matriz
  bidimensional é documentada nos exemplos instalados, mas ainda **não foi comprovada**
  neste harness (E0/P1, P2).
- Um único índice linear simplifica a checagem de limites: `0 <= id*4+d <= 99` decorre de
  `id` e `d` válidos, sem duas verificações independentes de linha e coluna.
- O layout é o mesmo que uma futura matriz `real[25][4]`; a conversão é apenas de indexação.
- A matriz inteira é passada por referência entre funções, sem cópia lógica.

Invariantes:

- **I1** — o estado tem exatamente 100 posições; nenhuma posição é reservada ou ignorada.
- **I2** — `w[id*4+d]` é a única representação do peso `(id, d)`; não há cópia paralela.
- **I3** — toda leitura/escrita pública ocorre após validação de `id` e `d` (§5, §6).
- **I4** — nenhuma posição é alterada por inicialização, consulta, impressão ou erro.
- **I5** — apenas `emb_definir` altera o estado depois da inicialização.
- **I6** — reexecutar `inicializar_embeddings` restaura o estado canônico a partir de
  qualquer estado anterior.
- **I7** — a grade `k/16` é propriedade exclusiva da inicialização; `emb_definir` pode
  gravar qualquer `real`, inclusive fora de `[-1, 1]`.

## 4. Inicialização determinística

Para `id ∈ [0, 24]` e `d ∈ [0, 3]`:

```
q(id, d) = ((id * 7 + d * 3) % 32) - 16      // inteiro em [-16, 15]
w(id, d) = q(id, d) / 16.0                   // real, múltiplo exato de 1/16
```

Propriedades verificáveis:

- `q` é inteiro; `%` opera apenas sobre inteiros não negativos nesta fórmula
  (`id*7 + d*3 >= 0`), portanto não há dependência de semântica de módulo negativo.
- `/ 16.0` é divisão real; usar `16` (inteiro) truncaria o resultado e é proibido.
- Todo valor é múltiplo exato de `1/16` e está em `[-1.0, 0.9375]`.
- **Linhas distintas:** se duas linhas `a` e `b` fossem iguais, então
  `7*(a-b) ≡ 0 (mod 32)`; como `mdc(7,32)=1`, isso exige `a ≡ b (mod 32)`. Com
  `a,b ∈ [0,24]`, a única possibilidade é `a = b`. Logo as 25 linhas são distintas.
- Não há dependência de relógio, ambiente, locale, ordem de chamadas ou estado anterior.

### 4.1 Tabela de referência (25 × 4)

Valores canônicos após `inicializar_embeddings`. Esta tabela é a única fonte de verdade
para os `.expected` e para o verificador independente.

| id | d0 | d1 | d2 | d3 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | -1.0 | -0.8125 | -0.625 | -0.4375 |
| 1 | -0.5625 | -0.375 | -0.1875 | 0.0 |
| 2 | -0.125 | 0.0625 | 0.25 | 0.4375 |
| 3 | 0.3125 | 0.5 | 0.6875 | 0.875 |
| 4 | 0.75 | 0.9375 | -0.875 | -0.6875 |
| 5 | -0.8125 | -0.625 | -0.4375 | -0.25 |
| 6 | -0.375 | -0.1875 | 0.0 | 0.1875 |
| 7 | 0.0625 | 0.25 | 0.4375 | 0.625 |
| 8 | 0.5 | 0.6875 | 0.875 | -0.9375 |
| 9 | 0.9375 | -0.875 | -0.6875 | -0.5 |
| 10 | -0.625 | -0.4375 | -0.25 | -0.0625 |
| 11 | -0.1875 | 0.0 | 0.1875 | 0.375 |
| 12 | 0.25 | 0.4375 | 0.625 | 0.8125 |
| 13 | 0.6875 | 0.875 | -0.9375 | -0.75 |
| 14 | -0.875 | -0.6875 | -0.5 | -0.3125 |
| 15 | -0.4375 | -0.25 | -0.0625 | 0.125 |
| 16 | 0.0 | 0.1875 | 0.375 | 0.5625 |
| 17 | 0.4375 | 0.625 | 0.8125 | -1.0 |
| 18 | 0.875 | -0.9375 | -0.75 | -0.5625 |
| 19 | -0.6875 | -0.5 | -0.3125 | -0.125 |
| 20 | -0.25 | -0.0625 | 0.125 | 0.3125 |
| 21 | 0.1875 | 0.375 | 0.5625 | 0.75 |
| 22 | 0.625 | 0.8125 | -1.0 | -0.8125 |
| 23 | -0.9375 | -0.75 | -0.5625 | -0.375 |
| 24 | -0.5 | -0.3125 | -0.125 | 0.0625 |

Fatos derivados, usados em testes:

- mínimo global = `-1.0` (ids 0/d0, 17/d3, 22/d2);
- máximo global = `0.9375` (ids 4/d1, 9/d0);
- 25 linhas distintas; 100 valores; zero ocorre em (1,d3), (6,d2), (11,d1), (16,d0).

## 5. API do fragmento

Constantes lógicas (implementadas como `const` com literal inteiro, conforme E0/P9b; o
runtime rejeita `const` inicializada por expressão):

```
TAM_VOCAB = 25
DIM       = 4
TOTAL     = 100
```

| Função | Assinatura | Comportamento |
| --- | --- | --- |
| inicialização | `funcao inicializar_embeddings(real w[])` | grava a tabela §4.1 nas 100 posições; não lê estado anterior. |
| validação de ID | `funcao logico emb_id_valido(inteiro id)` | `verdadeiro` sse `0 <= id <= 24`. |
| validação de dimensão | `funcao logico emb_dim_valida(inteiro d)` | `verdadeiro` sse `0 <= d <= 3`. |
| consulta | `funcao real emb_obter(real w[], inteiro id, inteiro d)` | devolve `w[id*4+d]`. **Pré-condição:** `emb_id_valido(id)` e `emb_dim_valida(d)`. |
| escrita | `funcao emb_definir(real w[], inteiro id, inteiro d, real valor)` | atribui `w[id*4+d] = valor`. **Pré-condição:** `emb_id_valido(id)` e `emb_dim_valida(d)`. Não valida nem limita `valor`. |
| info | `funcao emb_imprimir_info()` | emite `INFO=25 4 100`. |
| vetor | `funcao emb_imprimir_vetor(real w[], inteiro id)` | valida `id`; se inválido, emite `ERRO=ID_INVALIDO` e retorna; senão emite uma linha `VETOR=...`. |
| peso | `funcao emb_imprimir_peso(real w[], inteiro id, inteiro d)` | valida `id` e depois `d`; emite `ERRO=...` ou uma linha `PESO=...`. |
| resumo | `funcao emb_resumo(real w[])` | varre as 100 posições e emite menor, maior e número de linhas distintas. |

Regras:

- As funções `emb_imprimir_*` e `emb_resumo` são **totais** para qualquer `id`/`d`
  inteiro: nunca acessam o vetor antes de validar.
- `emb_obter` e `emb_definir` são internas: exigem índices já validados. Chamá-las com
  índice inválido é violação de pré-condição, não um caso de teste. Toda entrada externa
  passa por `emb_id_valido`/`emb_dim_valida` ou pelas funções de impressão.
- `emb_definir` aceita qualquer `real`, inclusive fora de `[-1, 1]` e fora da grade
  `1/16`. Não há *clamp*. Limitar valores é responsabilidade de quem treina, não do
  armazenamento.
- Nenhuma função imprime nada além do especificado; nenhuma imprime durante a
  inicialização.
- Nenhuma função usa `aleatorio`, tempo, entrada do usuário ou biblioteca.

### 5.1 Cálculo do resumo

`emb_resumo` calcula:

- `menor` e `maior`: varredura linear de `w[0..99]`, inicializada com `w[0]`;
- `distintos`: para cada `id` de `0..24`, compara a linha com todas as linhas anteriores,
  coordenada a coordenada, usando igualdade exata de `real`; conta a linha apenas se for
  diferente de todas as anteriores.

Custo máximo: 300 comparações de linhas × 4 coordenadas = 1.200 comparações; irrelevante.
A igualdade exata é legítima para o estado canônico, cujos valores são múltiplos de `1/16`.
O resumo só é testado nesse estado; as mutações usam `0.5` e `1.7` e não passam por
comparação de igualdade. O E0/P4 confirma `==` entre reais iguais.

## 6. Erros

| Código | Condição |
| --- | --- |
| `ID_INVALIDO` | `id < 0` ou `id > 24`. |
| `DIMENSAO_INVALIDA` | `0 <= id <= 24` e (`d < 0` ou `d > 3`). |

Regras de erro:

- **E1** — a validação ocorre antes de qualquer acesso ao vetor.
- **E2** — a validação ocorre antes de qualquer `escreva`: a linha de erro é a única saída
  da chamada (sem `VETOR=`/`PESO=` parcial).
- **E3** — um erro não altera o estado: as 100 posições permanecem como estavam.
- **E4** — um erro não encerra o programa; chamadas seguintes funcionam normalmente.
- **E5** — não há *clamp*, *wrap*, truncamento para `0` ou acesso ao índice 0.
- **E6** — a precedência é sempre ID antes de dimensão.

## 7. Caminho de atualização futura (treinamento)

O único caminho de escrita é `emb_definir`. Para uma futura rede neural:

```
novo = emb_obter(w, id, d) - taxa * gradiente
emb_definir(w, id, d, novo)
```

Consequências de projeto:

- o armazenamento plano de 100 reais é exatamente o vetor de parâmetros de uma camada de
  embedding `25 × 4`; um otimizador futuro percorre o mesmo índice `id*4+d`;
- nenhuma estrutura auxiliar precisa ser criada para atualizar pesos;
- `emb_definir` não valida faixa numérica, então o treinamento controla divergência;
- não há atualização em lote, média, *momentum* ou *weight decay* nesta missão.

## 8. Formato observável

### 8.1 Formato A (normativo, confirmado por E0/P7)

Uma linha por operação, separador Espaço (`0x20`), terminador `\n` (`0x0A`):

```
INFO=25 4 100
VETOR=<id> <v0> <v1> <v2> <v3>
PESO=<id> <d> <v>
RESUMO=25 100 <menor> <maior> <distintos>
ERRO=<CODIGO>
```

- `<id>`, `<d>`, `25`, `100` e `<distintos>` são inteiros decimais sem sinal, sem zeros à
  esquerda e sem separador de milhar.
- `<v>`, `<v0>..<v3>`, `<menor>`, `<maior>` seguem a gramática:

```
-?(0|[1-9][0-9]*)\.[0-9]{1,4}
```

- O separador decimal é ponto; vírgula é proibida. Notação exponencial é proibida.
  Sinal `+` é proibido. A string `-0.0` não pode aparecer na saída: a inicialização
  canônica produz `0.0`, e os casos de mutação usam valores positivos.
- O valor numérico deve ser **exatamente** igual ao racional esperado (múltiplo de
  `1/16`), e não uma aproximação.
- `VETOR` e `PESO` refletem o estado no momento da chamada, inclusive após
  `emb_definir`.
- `RESUMO` reflete as 100 posições atuais, não a tabela canônica.

### 8.2 Saída completa de uma execução

O driver imprime apenas as linhas das operações que executa, na ordem em que as executa.
Nenhuma linha em branco, nenhum cabeçalho, nenhum rodapé próprio. O epílogo do
interpretador (`Programa finalizado`, `Pressione ENTER...`) não faz parte do contrato e é
removido pelo runner, como na M1.

### 8.3 Formato C (reserva, somente se A falhar em E0)

Se o interpretador não serializar reais de forma estável e exata, os testes passam a
comparar **resultados de comparação** em vez de valores impressos:

```
<ROTULO>=OK      // todas as comparações do grupo passaram
<ROTULO>=FALHA   // ao menos uma comparação falhou
ERRO=<CODIGO>    // inalterado
```

`<ROTULO>` é fixo por caso (`INIT`, `UNK`, `ID1`, `ID24`, `PESOS`, `LAYOUT`, `RESUMO`,
`ATUALIZACAO`, `REINICIALIZACAO`, `DETERMINISMO`, `ERRO_ESTADO`). Cada driver compara
`emb_obter` com literais `real` exatos da tabela §4.1. O verificador independente recalcula
a fórmula e valida os literais embutidos no driver. Nesse cenário a spec é revisada e o
plano registra a evidência que motivou a troca. **Não aplicável nesta execução:** P7
confirmou o formato A.

### 8.4 Condição de congelamento

O formato só é considerado congelado depois que E0/P7 registrar os bytes exatos de
`VETOR=0`, `PESO=0 0`, `PESO=4 1` e `RESUMO`. Se os bytes observados violarem §8.1 de
forma não corrigível, aplica-se §8.3. Nenhum `.expected` é escrito antes disso.

**Resultado:** P7 confirmou integralmente §8.1 (100 valores e `RESUMO` conferidos), com
ponto decimal, sem vírgula, sem expoente e com `0.0` para zero calculado. Formato A
congelado em 2026-10-25. A única ressalva é `-0.0`, que o runtime imprime literalmente,
mas que não é produzido pela inicialização nem pelos casos de mutação; por isso o
contrato proíbe `-0.0` na saída em vez de prometer normalização.

## 9. Critérios de aceitação

- **AC1** — `src/embeddings.por` é um fragmento: não contém `programa` nem `inicio`.
- **AC2** — o fragmento não inclui bibliotecas e não produz saída ao ser incluído.
- **AC3** — o estado tem exatamente 25 × 4 = 100 valores `real`.
- **AC4** — após a inicialização, as 100 posições coincidem com a tabela §4.1.
- **AC5** — após a inicialização canônica, todo valor está em `[-1.0, 0.9375]` e é
  múltiplo exato de `1/16`. A grade **não** se aplica a valores gravados por
  `emb_definir`.
- **AC6** — as 25 linhas são distintas duas a duas.
- **AC7** — `UNK = 0` é um ID válido, com linha própria (`-1.0 -0.8125 -0.625 -0.4375`).
- **AC8** — IDs `0..24` são aceitos; `-1` e `25` produzem `ERRO=ID_INVALIDO`.
- **AC9** — dimensões `0..3` são aceitas; `-1` e `4` produzem
  `ERRO=DIMENSAO_INVALIDA`.
- **AC10** — com ambos inválidos, o erro é `ID_INVALIDO`.
- **AC11** — consulta e impressão devolvem exatamente o valor armazenado, sem
  arredondamento adicional.
- **AC12** — `emb_definir` altera **apenas** a célula indicada; as outras 99 permanecem
  idênticas.
- **AC12b** — `emb_definir` aceita qualquer `real`, inclusive fora de `[-1, 1]` e fora da
  grade `1/16` (o caso `emb_atualizacao` grava `1.7`), sem *clamp* e sem rejeição.
- **AC13** — reexecutar a inicialização restaura a tabela canônica, inclusive após
  escrita.
- **AC14** — o índice plano é `id*4+d`; o driver comprova a equivalência com a consulta
  em 16 pares `(id, d)`.
- **AC15** — `RESUMO=25 100 -1.0 0.9375 25` após a inicialização.
- **AC16** — erro não produz saída parcial, não altera o estado e não encerra o programa.
- **AC17** — duas execuções independentes do mesmo driver produzem saídas idênticas byte
  a byte.
- **AC18** — a fonte é ASCII puro (0x20–0x7E, TAB, CR, LF), sem BOM.
- **AC19** — nenhuma dependência externa, nenhum número aleatório, nenhum acesso a tempo.
- **AC20** — a suíte anterior (M0 + M1) permanece intacta: 21/21 verificações de bytes da
  M1 e 25/25 testes (5 da M0 + 20 da M1).
- **AC21** — a suíte completa (M0 + M1 + M3) termina com 0 falhas e inclui todos os casos
  da §7 do plano (`docs/embeddings-plan.md`).
- **AC22** — o verificador independente recalcula a fórmula em aritmética exata e
  aprova todos os valores, sem confiar nos `.expected` gerados pelo próprio módulo.

## 10. Pressupostos verificados na E0

Resultados das sondas executadas em 2026-10-25 (`temp/e0-emb/`, descartável):

| Pressuposto | Sonda | Resultado |
| --- | --- | --- |
| vetor local `real[100]`, leitura/escrita indexada | P1 | PASS — `-1.0`, `0.0`, `-0.8125`. |
| `real[]` por referência | P2 | PASS — escrita na função visível no chamador. |
| retorno `real`, `logico`, função sem retorno | P3 | PASS. |
| literais reais e `==` exato | P4 | PASS; `-0.0` é impresso como `-0.0` (não normalizado). |
| `%` e precedência | P5 | PASS — `((24*7+3*3)%32)-16 = 1`; `-7 % 32 = -7` (não usado). |
| `/ 16.0` exato × `/ 16` truncado | P6 | PASS — `1.0625` × `1.0`; aviso de conversão no segundo caso. |
| serialização §8.1 | P7 | PASS — 100 valores e `RESUMO` idênticos à tabela. |
| `escreva` misto | P8 | PASS. |
| `const` global visível e como tamanho de vetor | P9b | PASS apenas com literal inteiro; expressão em `const` é rejeitada (P9). |
| índice fora dos limites | P10a/P10b | aborta com erro de execução (exit 0 do processo); validação é obrigatória. |
| laços aninhados, `!=`, `nao` | P12 | PASS — 25 linhas distintas. |
| 25 linhas de saída, LF e epílogo | P13 | PASS — corpo só com LF; epílogo idêntico à M1. |
| cast `inteiro(real)` | P14/P14b | sintaxe de cast rejeitada; atribuição real→inteiro trunca com aviso (não usada). |

Consequências registradas: constantes usam literais; `q / 16.0` é obrigatório; a grade
`1/16` é só da inicialização; `-0.0` é proibido na saída; nenhum formato alternativo foi
necessário.
