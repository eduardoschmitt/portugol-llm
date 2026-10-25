# Especificação — Tokenizador mínimo para mini-LLM (M1)

- **Status:** especificação apenas. Nada foi implementado, executado ou medido.
- **Versão:** `v0.2.1` — correção factual em §4 (o maior campo é 16.384, não 15.361); nenhuma
  regra normativa alterada. Substitui a v0.2.0, que substituiu integralmente a v0.1.0.
- **Escopo:** converter texto em uma sequência de IDs inteiros de um vocabulário pequeno e fixo.
- **Fora de escopo:** lexer de Portugol, classes léxicas, parser, AST, avaliação, treino,
  embeddings, normalização Unicode, leitura de arquivos, entrada interativa.

## 1. Contrato

| Item | Definição |
| --- | --- |
| Entrada | um texto (sequência de caracteres). |
| Saída lógica | sequência ordenada de IDs inteiros. |
| Saída observável | uma única linha, exatamente `IDS=<id> <id> ...` ou `ERRO=<CÓDIGO>`, seguida de um `\n`. |
| Unidade | 1 token = 1 campo não vazio entre separadores. |
| Mapeamento | cada token vira **exatamente um** ID: o do vocabulário (§3) se houver igualdade exata; senão `0` (`UNK`). |
| ID reservado | `0` = `UNK`; nenhuma palavra usa `0`. |
| Faixa de IDs | `0..63` (tabela de tamanho fixo). `25..63` reservados. |

O tokenizador é determinístico e sem estado: mesma entrada produz sempre a mesma saída.

### 1.1 Fluxo normativo (ordem obrigatória)

1. Se o texto tiver mais de 16.384 caracteres → `ERRO=ENTRADA_LONGA` (§4).
2. Dividir o texto em campos usando apenas os separadores de §2.
3. Descartar campos vazios (consecutivos, à esquerda, à direita).
4. Se restarem mais de 1.024 campos → `ERRO=TOKENS_DEMAIS` (§4).
5. Para cada campo, na ordem: comparar exatamente com a tabela de §3; emitir o ID
   correspondente ou `0`.
6. Serializar conforme §5.

Não existe tokenização parcial: se §4 disparar, nenhum ID é emitido.

## 2. Separação

Separadores, e somente eles: espaço (U+0020), TAB (U+0009), CR (U+000D), LF (U+000A).

- Espaços consecutivos (de qualquer mistura dos quatro) são ignorados.
- Separadores no início e no fim não geram tokens.
- Entrada vazia ou só com separadores gera **zero tokens** e é **sucesso**.
- Nenhum outro caractere separa. Em particular, pontuação **não** separa (§3.2).

## 3. Vocabulário e comparação

### 3.1 Comparação exata

O campo é comparado **caractere a caractere** com as palavras da tabela, com igualdade
exata. Não há:

- conversão de caixa (`Se` ≠ `se`);
- remoção de acentos (`função` ≠ `funcao`);
- normalização Unicode (NFC/NFD) ou dobra de diacríticos;
- remoção de pontuação, aspas, prefixos ou sufixos;
- truncamento.

Consequência aceita: tudo o que não for uma das 24 palavras exatas vira `UNK`.

### 3.2 Pontuação

Pontuação não tem ID nesta versão e não é removida. Logo:

- `(` sozinho → `UNK`;
- `se,` → `UNK` (o campo é `se,`, não `se`);
- `inicio()` → `UNK`;
- `x=1` → `UNK`.

### 3.3 Tabela de palavras (fixa)

| ID | Palavra | ID | Palavra | ID | Palavra |
| ---: | --- | ---: | --- | ---: | --- |
| 1 | `programa` | 9 | `se` | 17 | `escreva` |
| 2 | `funcao` | 10 | `senao` | 18 | `leia` |
| 3 | `inicio` | 11 | `enquanto` | 19 | `e` |
| 4 | `inteiro` | 12 | `faca` | 20 | `ou` |
| 5 | `real` | 13 | `para` | 21 | `nao` |
| 6 | `logico` | 14 | `ate` | 22 | `verdadeiro` |
| 7 | `cadeia` | 15 | `passo` | 23 | `falso` |
| 8 | `vazio` | 16 | `retorne` | 24 | `pare` |

- `0` = `UNK` (fora da tabela acima, por definição).
- Total ocupado: `0..24`. Reserva: `25..63`, sem emissão nesta versão.
- Capacidade máxima da tabela: 64 entradas (uma por ID).

### 3.4 Estabilidade dos IDs

- IDs são imutáveis: nunca renumerar, nunca reutilizar.
- Crescimento apenas por acréscimo, em ordem, dentro de `25..63`, com incremento de versão.
- A v0.1.0 nunca foi implementada; por isso a renumeração para a v0.2.0 é permitida e os
  IDs congelam a partir desta versão.

## 4. Limites

| Limite | Valor | Ao exceder |
| --- | ---: | --- |
| Caracteres de entrada | 16.384 | `ERRO=ENTRADA_LONGA` |
| Tokens (campos não vazios) | 1.024 | `ERRO=TOKENS_DEMAIS` |

Regras:

- Os limites são valores de especificação, escolhidos para caber em estruturas de tamanho
  fixo. **Não** são capacidades medidas do Portugol Studio e não devem ser apresentados como
  tais.
- Não há limite próprio de comprimento por token. O maior campo possível tem 16.384
  caracteres (entrada sem nenhum separador, portanto um único token). O valor 15.361
  (16.384 − 1.023 separadores) é apenas o maior campo possível quando existem exatamente
  1.024 tokens.
- Se ambos os limites forem excedidos, vale `ENTRADA_LONGA` (é verificado primeiro).
- Texto só com separadores acima de 16.384 caracteres é `ENTRADA_LONGA`, mesmo gerando zero
  tokens.
- Não há truncamento silencioso em nenhum caso.
- Os limites valem por chamada; não há acumulação entre entradas.

## 5. Formato observável

Saída é sempre **uma única linha**, terminada por exatamente um `\n` (LF), sem linhas em
branco adicionais.

### 5.1 Sucesso

```
IDS=<id>[ <id>]*
```

- Prefixo literal `IDS=`.
- IDs em decimal ASCII, sem zeros à esquerda, na ordem de leitura.
- Separador: exatamente um espaço (U+0020) entre IDs.
- Sem espaço antes do primeiro ID, sem espaço após o último.
- Zero tokens: a linha é exatamente `IDS=` seguida de `\n` (5 bytes).
- `IDS=0` significa um token `UNK` e é diferente de `IDS=` (zero tokens).

### 5.2 Erro

```
ERRO=<CÓDIGO>
```

- Códigos possíveis e únicos: `ENTRADA_LONGA`, `TOKENS_DEMAIS`.
- Prefixo e código em ASCII maiúsculo, sem espaços, sem IDs.
- Uma linha, terminada por um `\n`.

### 5.3 Regras sem ambiguidade

- Sucesso nunca contém `ERRO=`; erro nunca contém `IDS=`.
- Exatamente uma das duas linhas, nunca as duas, nunca nenhuma.
- Em erro, nenhum ID parcial é emitido.
- Não há mensagens extras, avisos, cabeçalhos ou contadores na saída.
- O runner do M0 valida por conteúdo e remove `\n` final; a especificação exige o `\n`
  mesmo assim, para que a saída seja comparável byte a byte por outros meios.

## 6. Exemplos

`␣` = espaço, `⇥` = TAB, `↵` = LF, `␍` = CR, apenas para legibilidade.

| Entrada | Saída | Motivo |
| --- | --- | --- |
| `""` | `IDS=` | zero tokens |
| `"␣␣␣"` | `IDS=` | só separadores |
| `"se"` | `IDS=9` | palavra exata |
| `"Se"` | `IDS=0` | caixa diferente |
| `"SE"` | `IDS=0` | caixa diferente |
| `"senao"` | `IDS=10` | palavra exata |
| `"senão"` | `IDS=0` | acento, sem normalização |
| `"funcao"` | `IDS=2` | palavra exata |
| `"função"` | `IDS=0` | acento, sem normalização |
| `"nao"` | `IDS=21` | palavra exata |
| `"não"` | `IDS=0` | acento, sem normalização |
| `"programa␣␣␣inicio"` | `IDS=1 3` | consecutivos ignorados |
| `"␣␣inteiro␣"` | `IDS=4` | bordas ignoradas |
| `"se⇥faca"` | `IDS=9 12` | TAB separa |
| `"leia␍␍x"` | `IDS=18 0` | CR separa |
| `"se↵enquanto"` | `IDS=9 11` | LF separa |
| `"x␣=␣1"` | `IDS=0 0 0` | identificador, operador e número fora da tabela |
| `"resultado"` | `IDS=0` | fora da tabela |
| `"123"` | `IDS=0` | números não têm ID |
| `"se,"` | `IDS=0` | pontuação colada, sem remoção |
| `"(se)"` | `IDS=0` | pontuação colada |
| `"se,␣faca"` | `IDS=0 12` | só o campo afetado vira UNK |

Sequência completa:

```
Entrada:  programa { funcao inicio() { escreva("OI") } }
Saída:    IDS=1 0 2 0 0 0 0 0
```

Campos: `programa`=1, `{`=0, `funcao`=2, `inicio()`=0, `{`=0, `escreva("OI")`=0, `}`=0, `}`=0.

Erros:

```
Entrada:  (16.385 caracteres)
Saída:    ERRO=ENTRADA_LONGA

Entrada:  1.025 campos "se" separados por espaço
Saída:    ERRO=TOKENS_DEMAIS
```

## 7. Critérios de aceitação

Verificáveis por comparação de saída, sem inspeção manual. Nenhum foi executado ainda.

- **AC1** — Entrada vazia produz exatamente `IDS=` + `\n`.
- **AC2** — Entrada apenas com espaço/TAB/CR/LF produz exatamente `IDS=` + `\n`.
- **AC3** — Separadores consecutivos, à esquerda e à direita são ignorados:
  `"␣␣se⇥⇥faca␣"` → `IDS=9 12`.
- **AC4** — Somente espaço, TAB, CR e LF separam; qualquer outro caractere permanece no campo
  (ex.: `se␣faca` separa, `se,faca` não).
- **AC5** — Igualdade é sensível a caixa: `se`→`IDS=9`, `Se`→`IDS=0`, `SE`→`IDS=0`.
- **AC6** — Igualdade é sensível a acentos: `nao`→`IDS=21`, `não`→`IDS=0`,
  `funcao`→`IDS=2`, `função`→`IDS=0`.
- **AC7** — Cada uma das 24 palavras do §3.3 produz exatamente o ID tabelado.
- **AC8** — Qualquer campo fora da tabela produz `UNK` (0), incluindo identificadores,
  números e símbolos: `x`→0, `42`→0, `@`→0.
- **AC9** — Pontuação não é removida nem separada: `se,`→0, `(se)`→0, `se,␣faca`→`IDS=0 12`.
- **AC10** — Cardinalidade preservada: para qualquer entrada válida, a quantidade de IDs é
  igual à quantidade de campos não vazios, e `UNK` conta como token.
- **AC11** — `IDS=0` (um `UNK`) e `IDS=` (zero tokens) são saídas distintas.
- **AC12** — 1.024 tokens são aceitos; 1.025 produzem `ERRO=TOKENS_DEMAIS`, sem `IDS=`.
- **AC13** — 16.384 caracteres são aceitos; 16.385 produzem `ERRO=ENTRADA_LONGA`, sem `IDS=`.
- **AC14** — Com ambos os limites excedidos, a saída é `ERRO=ENTRADA_LONGA`.
- **AC15** — Formato exato: prefixo `IDS=`, um espaço simples entre IDs, sem espaço final,
  exatamente um `\n`, uma única linha.
- **AC16** — Erro: exatamente `ERRO=ENTRADA_LONGA` ou `ERRO=TOKENS_DEMAIS`, mais `\n`, sem
  `IDS=` e sem saída parcial.
- **AC17** — Determinismo: entradas repetidas produzem saídas idênticas, sem dependência de
  locale, ambiente ou histórico de chamadas.
- **AC18** — Sem truncamento: um campo muito longo é um único `UNK`, contado uma vez.
- **AC19** — Tabela fechada: IDs `0..24` são os únicos emitidos; `25..63` não são emitidos
  nesta versão e não podem ser reutilizados.
- **AC20** — Nenhuma transformação textual ocorre antes da comparação (sem caixa, acento,
  trim de pontuação ou normalização): a única alteração é a divisão em campos.

## 8. Pressupostos e itens a verificar

Premissas mínimas, todas a confirmar na fase de implementação:

- percorrer o texto e comparar trechos por igualdade;
- manter até 1.024 inteiros;
- emitir texto com `escreva`, incluindo múltiplos argumentos, forma já observada no M0.

Não assumido nesta versão (e não deve ser alegado sem teste):

- funções de normalização Unicode, caixa ou remoção de acentos;
- separação de strings pronta no runtime;
- arrays dinâmicos, dicionários ou alocação ilimitada;
- leitura de arquivos, `stdin` ou qualquer I/O além da escrita de saída;
- limites medidos do interpretador.

Se a implementação não puder medir caracteres como definido em §4, isso deve ser registrado
como pendência e resolvido sem alterar o contrato observável.

## 9. Limitações conhecidas

1. Vocabulário de 24 palavras: a maior parte de um programa real vira `UNK`.
2. Caixa e acentos não são normalizados: `Se`, `SE`, `função` e `não` são `UNK`.
3. Pontuação colada invalida o campo (`inicio()`, `escreva("OI")`, `x=1`).
4. Cadeias com espaços são divididas em vários campos.
5. Sem identificação de números, identificadores ou literais.
6. Sem informação de posição, linha ou comprimento na saída.

Candidatos a versões futuras, fora desta spec e sujeitos a aprovação:

- palavras adicionais em `25..63`;
- normalização opcional de caixa/acentos como versão explícita do vocabulário;
- separação de pontuação;
- ID por identificador normalizado;
- metadados de posição.

## 10. Referências internas

- `README.md` — estado do projeto e limitações do ambiente.
- `scripts/test.ps1` — runner que comparará a saída observável.
- `tests/smoke.por` — padrão de saída usado no M0.
