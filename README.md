# Portugol LLM

Um laboratório educacional que constrói, passo a passo, uma rede neural minúscula
em **Portugol Studio**. O objetivo não é competir com modelos de linguagem
modernos: é mostrar, com código executável e testes reproduzíveis, como um texto
vira números, como esses números atravessam uma camada neural, como o modelo
aprende por regras explícitas e como medir honestamente o que ele consegue — e o
que ele não consegue — fazer.

O projeto foi desenvolvido em missões pequenas (M1 a M10). Cada missão de
implementação tem especificação, plano, testes de bytes e um verificador
independente. Os resultados negativos também estão documentados: a avaliação de
generalização (M9) e o experimento de atenção (M10) **não encontraram evidência
de melhoria**.

> **Importante:** este projeto **não** implementa um Transformer completo e
> **não** equivale a um LLM moderno. Não há softmax, retropropagação,
> embeddings treináveis, múltiplas cabeças de atenção nem GPU. O modelo é uma
> camada linear inteira sobre um vocabulário de 25 símbolos e um corpus
> sintético de 5 linhas.

## 1. O que é este projeto?

`portugol-llm` é um repositório de estudo. Ele implementa, em Portugol, um
pipeline mínimo de modelo de linguagem:

1. **Tokenização** — transforma palavras de um vocabulário fixo em IDs inteiros.
2. **Embeddings** — associa cada ID a um vetor de 4 números.
3. **Camada neural** — calcula 25 escores (logits) e escolhe o maior.
4. **Treinamento** — ajusta os parâmetros com uma regra delta determinística.
5. **Geração** — repete a predição para produzir uma sequência de tokens.
6. **Contexto** — usa os três tokens anteriores em vez de apenas um.
7. **Corpus** — extrai exemplos de um pequeno texto e treina a partir deles.
8. **Avaliação** — mede memorização e generalização contra baselines.
9. **Atenção** — testa uma ponderação causal mínima, como experimento.

Tudo roda no interpretador de linha de comando do Portugol Studio, no Windows,
e é verificado por scripts PowerShell. Não há dependências de Python, Node,
bibliotecas de machine learning ou serviços externos.

O que este projeto **é**:

- um material didático sobre representação, predição e treinamento;
- um exemplo de engenharia com testes de bytes, oráculos independentes e
  resultados declarados antes da execução;
- uma demonstração de como separar **memorização** de **generalização**.

O que este projeto **não é**:

- um ChatGPT ou qualquer modelo de linguagem moderno;
- um interpretador de Portugol ou um compilador;
- uma prova de que atenção melhora generalização;
- um produto pronto para uso.

## 2. Por que construir uma rede neural em Portugol?

Porque Portugol é a linguagem que muitos estudantes brasileiros usam para
aprender programação. Construir o modelo nela obriga a lidar com os detalhes
que bibliotecas escondem: índices, dimensões, arredondamento, limites de
inteiros, máscaras, testes de bytes e reprodutibilidade.

O projeto também é um exercício de honestidade científica. É fácil dizer que
"o modelo aprendeu" olhando apenas os exemplos de treino. Aqui, os exemplos de
treino medem **memorização**; a generalização é medida em contextos que o
modelo nunca viu, contra baselines registrados antes do experimento. Quando o
resultado é negativo, ele é publicado como negativo.

A stack é deliberadamente pequena:

- **Windows** (o projeto foi executado no Windows 11);
- **PowerShell 5.1** ou superior;
- **Portugol Studio** com o executável `portugol-console.bat`;
- **Git** apenas para clonar o repositório.

## 3. O que o projeto consegue fazer?

Com o corpus e o vocabulário atuais, o projeto consegue:

- tokenizar frases formadas pelas 24 palavras da tabela fixa;
- mostrar os IDs e os vetores de embedding de cada token;
- treinar uma camada linear para prever o próximo token;
- gerar uma sequência autoregressiva que, no corpus atual, termina em `pare`
  (ID 24);
- usar um contexto de até três tokens;
- extrair janelas de um corpus textual e treinar a partir delas;
- medir acertos em conjuntos vistos e inéditos;
- comparar o modelo com baselines de memorização e de classe majoritária;
- executar um experimento de atenção causal com pesos observáveis.

O que ele **não** consegue fazer:

- entender Portugol de verdade;
- gerar texto livre fora das 24 palavras;
- lidar com acentos, maiúsculas ou pontuação (o vocabulário é ASCII minúsculo);
- manter contexto maior que três tokens;
- aprender representações: os embeddings são fixos por fórmula;
- provar generalização: os resultados de M9 e M10 são negativos.

## 4. Como funciona, do texto até a geração

### 4.1 Tokenização

O vocabulário tem 25 IDs:

| ID | Palavra | ID | Palavra | ID | Palavra |
| ---: | --- | ---: | --- | ---: | --- |
| 0 | `UNK` (desconhecida) | 9 | `se` | 17 | `escreva` |
| 1 | `programa` | 10 | `senao` | 18 | `leia` |
| 2 | `funcao` | 11 | `enquanto` | 19 | `e` |
| 3 | `inicio` | 12 | `faca` | 20 | `ou` |
| 4 | `inteiro` | 13 | `para` | 21 | `nao` |
| 5 | `real` | 14 | `ate` | 22 | `verdadeiro` |
| 6 | `logico` | 15 | `passo` | 23 | `falso` |
| 7 | `cadeia` | 16 | `retorne` | 24 | `pare` |
| 8 | `vazio` | | | | |

O tokenizador separa por espaço, TAB, CR ou LF. Ele aceita no máximo 16.384
caracteres e 1.024 tokens. No tokenizador M1, qualquer palavra fora da tabela
vira `UNK` (0); a leitura do corpus M8 é mais estrita e rejeita palavras fora
da tabela. O texto é ASCII minúsculo: `Programa` e `programa` não são a mesma
palavra.

Exemplo real do corpus:

```text
programa inicio escreva verdadeiro pare
```

vira:

```text
IDS: 1 3 17 22 24
```

### 4.2 Embeddings

Cada ID possui uma linha de 4 números reais, formando uma matriz 25 × 4. Os
valores são fixos e determinísticos, não treinados:

```text
q(id, d) = ((id * 7 + d * 3) % 32) - 16
embedding(id, d) = q(id, d) / 16
```

Assim, cada valor é um múltiplo exato de `1/16`, entre `-1.0` e `0.9375`.
Embeddings fixos tornam o experimento pequeno e reproduzível, mas também
limitam o que o modelo pode aprender.

### 4.3 Camada neural

A camada é linear: recebe 4 números (um embedding) ou 12 números (três
embeddings concatenados) e produz 25 escores, um por token do vocabulário.

```text
Z(y) = soma_d W[y, d] * entrada[d] + viés[y]
```

O próximo token é o `argmax`: o índice `y` com o maior `Z(y)`. Não há softmax,
função de ativação, camada escondida nem amostragem aleatória. O resultado é
sempre o mesmo para a mesma entrada.

Os parâmetros são inteiros escalados: `W16` representa `W * 16` e `b16`
representa `b * 16`. A soma `Z256 = 256 * Z` é inteira. Essa escolha evita
diferenças de ponto flutuante entre execuções.

### 4.4 Treinamento supervisionado

O treinamento usa pares `(entrada, alvo)`. Para cada exemplo, o modelo calcula
a predição, mede o erro e ajusta os parâmetros com uma regra delta inteira:

```text
delta_y = Z256(y) - 256 * [y == alvo]
W16[y, d] <- r(1024 * W16[y, d] - delta_y * e16(entrada, d), 1024)
b16[y]    <- r(  64 * b16[y] - delta_y,                        64)
```

`r(...)` é a divisão inteira com arredondamento. A regra é uma descida de
gradiente escalada, sem retropropagação através de camadas. O modelo tem uma
única camada ajustável; os embeddings permanecem fixos.

Na missão M5, o modelo aprende quatro transições isoladas:

```text
9 -> 12     (se -> faca)
12 -> 13    (faca -> para)
13 -> 14    (para -> ate)
14 -> 24    (ate -> pare)
```

Isso é memorização de quatro pares, não compreensão de programas.

### 4.5 Geração autoregressiva

A geração começa com um ou mais tokens e repete:

1. monta o contexto;
2. calcula os 25 escores;
3. escolhe o maior;
4. acrescenta o token à sequência;
5. para quando o token é `pare` (24) ou quando atinge o limite.

Exemplo real, depois do treino no corpus:

```text
GERADO=9 22 12 17 24
N=5
PASSOS=2
PARADA=PARE
TEXTO=se verdadeiro faca escreva pare
```

O texto é uma **projeção** dos IDs de volta para palavras, não uma
detokenização inversa geral. O modelo não "escreve": ele escolhe o próximo ID
mais provável segundo seus parâmetros.

### 4.6 Contexto de três tokens

A missão M7 amplia a entrada: em vez de um único embedding, o modelo concatena
os embeddings dos três últimos tokens, produzindo 12 números. Para sequências
menores, as posições à esquerda que faltam são preenchidas com zeros em `c16`,
mas **sem ID de PAD**. Como nenhum embedding de token é o vetor todo zero, zero
representa ausência de token e não se confunde com `UNK` (0).

Com `K = 3`, o modelo consegue aprender transições como:

```text
[se, verdadeiro, faca] -> escreva
[verdadeiro, faca, escreva] -> pare
```

### 4.7 Corpus e janelas

O corpus versionado tem cinco linhas:

```text
programa inicio escreva verdadeiro pare
funcao inicio escreva falso pare
se verdadeiro faca escreva pare
se falso senao leia pare
enquanto verdadeiro faca leia pare
```

Cada linha tem cinco tokens. O extrator monta janelas de três tokens de
contexto mais um alvo, sem atravessar o fim da linha. As cinco linhas produzem
**10 exemplos**. O treino usa esses 10 exemplos e a mesma regra delta da M5.

### 4.8 Atenção causal (M10)

A missão M10 acrescenta uma atenção aditiva mínima, com uma cabeça e máscara
causal:

```text
s(i, j) = soma_d a[d] * embedding(id_j, d) + beta[j]   para j <= i
u(i, j) = max(0, s(i, j))
c(i)    = soma_j u(i, j) * embedding(id_j) / soma_j u(i, j)
```

Só há 7 parâmetros de atenção (`a[4]` e `beta[3]`), ajustados por busca
coordenada discreta. A leitura final continua sendo uma camada linear. Se todos
os escores forem zero, o modelo usa a média simples dos embeddings como
fallback uniforme.

Isso **não** é atenção Q/K/V, não é softmax e não é um Transformer. É um
mecanismo pequeno para estudar pesos observáveis. No corpus real, a busca de
atenção não alterou nenhum dos 7 parâmetros: os pesos continuaram uniformes e a
redução de perda veio do ajuste afim. O resultado está documentado em
`docs/attention-spec.md`.

## 5. Evolução do projeto: M1–M10

| Missão | Módulo | O que foi construído | Resultado |
| --- | --- | --- | --- |
| M0 | infraestrutura | runner PowerShell, testes de fumaça, tratamento das quirks do interpretador | 5 testes iniciais |
| M1 | `src/tokenizador.por` | vocabulário fixo de 25 IDs, tokenização ASCII | 20 casos gerados |
| M2 | documentação | especificação e plano do tokenizador | contrato v0.2.1 |
| M3 | `src/embeddings.por` | matriz 25 × 4 determinística | 19 casos |
| M4 | `src/rede.por` | camada linear 4 → 25, argmax | 14 casos |
| M5 | `src/treino.por` | regra delta inteira, 4 pares supervisionados | 12 casos |
| M6 | `src/gerador.por` | geração autoregressiva, parada em `pare` | 14 casos |
| M7 | `src/contexto.por` | contexto K = 3, padding sem PAD | 16 casos |
| M8 | `src/corpus.por` | corpus de 5 linhas, 10 janelas, treino | 16 casos |
| M9 | `src/avaliacao.por` | A/B/C/D, baselines, veredito de generalização | `SEM_EVIDENCIA` |
| M10 | `src/atencao.por` | atenção aditiva causal, 1 cabeça, 7 parâmetros | `SEM_EVIDENCIA` |

A suíte principal soma **116 testes**. As missões de implementação (M1 e M3 a
M10) também têm verificadores independentes que recalculam resultados com
oráculos separados, conferem hashes, codificação ASCII/LF e a não mutação de
estado.

### 5.1 O que está concluído

- tokenizador, embeddings, camada linear, treino, geração e contexto;
- corpus versionado e treino a partir do corpus;
- avaliação de generalização com conjuntos vistos e inéditos;
- experimento de atenção causal;
- testes de bytes, determinismo, limites e regressão.

### 5.2 O que é trabalho futuro

- retropropagação e camadas escondidas;
- embeddings treináveis;
- softmax e atenção Q/K/V;
- múltiplas cabeças e blocos residuais;
- contexto maior que três tokens;
- vocabulário e corpus maiores;
- detokenização inversa completa;
- execução em outras plataformas além do Windows.

## 6. Como instalar e executar

### 6.1 Pré-requisitos

1. **Windows** (testado no Windows 11).
2. **PowerShell 5.1** ou superior (já incluído no Windows).
3. **Portugol Studio** instalado, com o arquivo `portugol-console.bat`.
4. **Git** (opcional, para clonar o repositório).

O caminho padrão do interpretador neste projeto é:

```text
C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat
```

Se o seu Portugol Studio estiver em outro lugar, informe o caminho com
`-InterpreterPath` ou defina a variável de ambiente `PORTUGOL_CONSOLE`.

### 6.2 Clonar o repositório

```powershell
git clone https://github.com/eduardoschmitt/portugol-llm.git
cd portugol-llm
```

### 6.3 Executar a demonstração

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo.ps1
```

Se o interpretador não estiver no caminho padrão:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo.ps1 `
  -InterpreterPath "C:\Program Files\Portugol Studio\portugol-console.bat"
```

A demonstração:

- lê `corpus/m8-corpus-v1.txt`;
- tokeniza a primeira linha;
- extrai as 10 janelas K = 3;
- treina a camada linear por 8 épocas;
- mostra um contexto e sua predição;
- gera uma continuação autoregressiva.

O arquivo `.por` gerado fica em `temp/demo/demo.por`. Ele é recriado a cada
execução; nada em `temp/` é necessário para rodar a demonstração.

### 6.4 Executar os testes

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

Saída esperada no estado atual:

```text
Passed: 116
Failed: 0
Total:  116

All tests passed.
```

Se o interpretador estiver em outro caminho:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 `
  -InterpreterPath "C:\Program Files\Portugol Studio\portugol-console.bat"
```

O runner também possui um autoteste negativo, que confirma que ele detecta uma
saída errada:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

Resultado esperado: **0 PASS / 1 FAIL intencional / exit code 1**.

### 6.5 Executar a suíte da atenção (opcional)

A suíte M10 é separada da suíte principal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-attention-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-attention.ps1
```

Resultado esperado: **14/14**.

## 7. Exemplos reais de entrada e saída

Os exemplos abaixo foram produzidos por `scripts/demo.ps1` e pelos testes
versionados. Eles não são ilustrativos: são a saída real do interpretador.

### 7.1 Tokenização

Entrada:

```text
programa inicio escreva verdadeiro pare
```

Saída:

```text
LINHA: programa inicio escreva verdadeiro pare
IDS: 1 3 17 22 24
PALAVRAS: programa inicio escreva verdadeiro pare
```

### 7.2 Janelas K = 3 e treino

```text
EXEMPLOS=10 CODIGO=0
TREINO_CODIGO=0
HISTORICO=8404936 1341188 651091 509249 436118 415557 391087 394372 368571
ACERTOS_NO_TREINO=10/10
```

O histórico é a perda escalada por época. Ela cai de `8404936` para `368571`.
O `10/10` significa que o modelo acertou os **próprios exemplos de treino**.
Isso é memorização, não generalização.

### 7.3 Predição de um contexto

```text
CONTEXTO: se falso senao -> leia
ALVO: leia
```

### 7.4 Geração

```text
GERADO=9 22 12 17 24
N=5
PASSOS=2
PARADA=PARE
TEXTO=se verdadeiro faca escreva pare
```

### 7.5 Um teste isolado

A suíte também executa arquivos `.por` pequenos. Exemplo de teste de fumaça:

```text
[PASS] smoke
```

Os testes comparam a saída normalizada com um `.expected`. O interpretador
sempre retorna `exit code 0`, mesmo em erros; por isso o runner valida o
conteúdo, não apenas o código de saída.

## 8. Como executar os testes

Há duas camadas de verificação:

1. **Testes de comportamento** — `scripts/test.ps1`, com 116 casos. Cada caso
   é um programa `.por` com saída esperada.
2. **Verificadores independentes** — scripts `verify-*.ps1`, que recalculam
   valores com oráculos próprios, conferem hashes e detectam regressões.

Comandos principais:

```powershell
# suíte completa
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1

# autoteste negativo do runner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest

# casos da atenção (M10) + verificação independente
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-attention-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-attention-bytes.ps1
```

Os verificadores de missões anteriores ficam em `scripts/verify-*.ps1`. Cada um
lê os casos já gerados em `temp/` pelo `build-*.ps1` correspondente; rode o
gerador antes se a pasta ainda não existir. Eles são mais lentos porque
reexecutam casos e comparam bytes.

### 8.1 Como interpretar a saída

- `[PASS] nome` — o caso produziu a saída esperada.
- `[FAIL] nome` — houve diferença de bytes, erro de execução ou saída
  inesperada.
- `Passed`, `Failed`, `Total` — resumo da suíte.
- `All tests passed.` — todos os casos passaram.
- `exit code 0` — sucesso do script; o interpretador do Portugol não usa o
  exit code para sinalizar erros de runtime.

O interpretador imprime um caractere de controle no início e um epílogo com
`Programa finalizado` e `Pressione ENTER para continuar`. Os scripts removem
esses artefatos antes de comparar.

## 9. Resultados experimentais

### 9.1 O que foi medido

A avaliação M9 usa quatro conjuntos:

- **A** — 10 pares vistos no treino (memorização);
- **B** — 20 pares, sendo 10 vistos e 10 inéditos;
- **C** — 32 contextos inéditos, o conjunto primário de generalização;
- **D** — 10 contextos vistos com o alvo trocado (controle).

O critério de generalização foi registrado antes da execução: o modelo precisava
superar os baselines em C por uma margem mínima. Os baselines são memorização
(consulta direta) e classe majoritária (sempre `pare`).

### 9.2 Resultado da avaliação M9

| Conjunto | Acertos | BP | Leitura |
| --- | ---: | ---: | --- |
| A (visto) | 10/10 | 10000 | memorização perfeita |
| B (total) | 10/20 | 5000 | metade vista, metade inédita |
| B_VISTO | 10/10 | 10000 | memorização |
| B_INEDITO | 0/10 | 0 | nenhuma generalização |
| C (primário) | 4/32 | 1250 | abaixo dos baselines |
| C_SEM_PARE | 1/24 | 417 | quase nenhum acerto |
| D (controle) | 0/10 | 0 | consistente com A |

Comparações em C:

- modelo: `1250` BP;
- não treinado: `938` BP;
- memorização: `2500` BP;
- classe majoritária: `2500` BP.

O modelo superou o não treinado em apenas `+312` BP e ficou `-1250` BP abaixo
dos baselines de memorização e majoritário. O critério exigia uma vantagem de
`+2000` BP sobre o maior baseline e pelo menos 15 acertos em C (o modelo obteve
4). **Não houve evidência de generalização.** O veredito registrado é
`SEM_EVIDENCIA` com qualificação `FRACA`.

### 9.3 Resultado da atenção M10

A atenção causal foi treinada no mesmo corpus. No corpus real, a perda caiu,
mas **nenhum** dos 7 parâmetros de atenção mudou: a busca permaneceu no ponto
inicial (`a = beta = 0`), que corresponde à atenção uniforme. Em C, o estado
treinado obteve `7/32` (`2188` BP), contra `2500` BP da atenção uniforme. A
atenção não melhorou a generalização.

Em um conjunto sintético balanceado, a busca mudou `beta[2]` de `0` para `1` e
a perda caiu. Isso mostra que o mecanismo de busca funciona quando existe sinal,
mas não indica ganho no corpus real.

### 9.4 O que esses números significam

- **Aprendizado supervisionado** é o ajuste dos parâmetros para reduzir o erro
  nos exemplos fornecidos.
- **Memorização** é acertar esses mesmos exemplos. Não é generalização.
- **Generalização** é acertar contextos novos. As métricas em C mostram que o
  modelo atual não generaliza de forma convincente.

O projeto publica esses resultados como eles são. Não há ajuste de limiar,
escolha de subconjunto ou mudança de arquitetura para transformar um resultado
negativo em positivo.

## 10. Limitações atuais

- **Vocabulário minúsculo:** apenas 24 palavras e `UNK`.
- **Corpus sintético:** 5 linhas, 25 tokens, 10 exemplos de treino.
- **Modelo linear:** uma única camada; não há camadas escondidas.
- **Sem retropropagação:** a regra delta ajusta apenas a última camada.
- **Embeddings fixos:** não são aprendidos.
- **Contexto curto:** no máximo 3 tokens.
- **Sem softmax:** a saída é apenas `argmax` determinístico.
- **Atenção experimental:** 1 cabeça, aditiva, sem Q/K/V.
- **Texto ASCII:** sem acentos, maiúsculas ou pontuação.
- **Sem detokenização inversa:** o texto é uma projeção de IDs.
- **Somente Windows:** depende do `portugol-console.bat`.
- **Interpretador rígido:** o exit code não sinaliza erros de runtime.
- **Generalização não demonstrada:** M9 e M10 tiveram resultado negativo.

## 11. O que falta implementar

Trabalho futuro, em ordem de importância para o objetivo educacional:

1. **Publicação do repositório** — concluir a revisão do histórico e tornar o
   repositório público.
2. **Corpus maior e mais variado** — mais linhas, mais transições e um
   conjunto de teste realmente independente.
3. **Vocabulário maior** — incluir mais palavras, números, operadores e
   acentuação.
4. **Embeddings treináveis** — hoje a matriz é fixa por fórmula.
5. **Camadas escondidas e retropropagação** — o modelo atual é linear.
6. **Softmax e atenção Q/K/V** — a atenção atual é apenas aditiva.
7. **Múltiplas cabeças e blocos residuais** — necessários para aproximar a
   arquitetura de um Transformer.
8. **Contexto maior** — K = 3 é suficiente para o experimento, não para texto.
9. **Detokenização inversa** — reconstruir texto com formatação a partir dos
   IDs.
10. **Portabilidade** — executar em Linux/macOS com outro interpretador ou
    uma versão do console.
11. **Atualizar `AGENTS.md`** — o arquivo ainda descreve o escopo inicial do
    projeto e não reflete as missões M1–M10.

Nenhum desses itens está implementado. Eles estão listados para deixar claro
onde o projeto termina e onde começaria um trabalho novo.

## 12. Estrutura do repositório

Árvore resumida (cada missão também tem um `-plan.md` em `docs/`):

```text
portugol-llm/
├── AGENTS.md                  instruções internas de condução do projeto
├── LICENSE                    licença MIT
├── README.md                  este arquivo
├── corpus/
│   └── m8-corpus-v1.txt       corpus sintético versionado (5 linhas)
├── docs/
│   ├── tokenizer-spec.md      especificação e decisões da M1
│   ├── tokenizer-plan.md      plano de execução da M1
│   ├── embeddings-spec.md     M3: matriz 25 × 4
│   ├── network-spec.md        M4: camada linear 4 → 25
│   ├── training-spec.md       M5: treinamento supervisionado
│   ├── generation-spec.md     M6: geração autoregressiva
│   ├── context-spec.md        M7: contexto K = 3
│   ├── corpus-spec.md         M8: treino a partir do corpus
│   ├── evaluation-spec.md     M9: avaliação de generalização
│   └── attention-spec.md      M10: atenção causal mínima
├── scripts/
│   ├── test.ps1               runner principal (116 testes)
│   ├── demo.ps1               demonstração reproduzível
│   ├── test-evaluation.ps1    suíte da avaliação M9
│   ├── test-attention.ps1     suíte da atenção M10
│   ├── build-*.ps1            geradores de casos em temp/
│   ├── verify-*.ps1           verificadores independentes
│   └── eval-*.ps1             oráculos da avaliação
├── src/
│   ├── tokenizador.por        M1: texto → IDs
│   ├── embeddings.por         M3: IDs → vetores
│   ├── rede.por               M4: vetores → logits
│   ├── treino.por             M5: regra delta
│   ├── gerador.por            M6: geração
│   ├── contexto.por           M7: contexto K = 3
│   ├── corpus.por             M8: janelas do corpus
│   ├── avaliacao.por          M9: métricas e baselines
│   └── atencao.por            M10: atenção causal
├── tests/
│   ├── smoke.por              teste de fumaça
│   ├── falha.por              erro de runtime esperado
│   ├── syntax_error.por       erro de sintaxe esperado
│   └── unexpected.por         saída inesperada
└── temp/                      artefatos descartáveis (ignorado pelo Git)
```

Os arquivos em `temp/` são gerados pelos scripts. Eles não fazem parte da
biblioteca e não são necessários para entender o projeto.

`AGENTS.md` contém instruções internas usadas durante o desenvolvimento. Ele
não é um tutorial do modelo e pode estar desatualizado em relação ao código.

## 13. Licença

Este projeto é distribuído sob a **Licença MIT**.

Copyright (c) 2026 Eduardo Schmitt.

O texto completo está em [`LICENSE`](LICENSE). A licença permite usar, copiar,
modificar, fundir, publicar, distribuir, sublicenciar e vender o software, desde
que o aviso de copyright e a permissão sejam mantidos. O software é fornecido
"como está", sem garantias.

---

## Documentação detalhada

Cada missão tem uma especificação e um plano. Os documentos mais úteis para
entender as decisões são:

- [`docs/tokenizer-spec.md`](docs/tokenizer-spec.md) — vocabulário e regras de
  tokenização;
- [`docs/embeddings-spec.md`](docs/embeddings-spec.md) — fórmula dos embeddings;
- [`docs/network-spec.md`](docs/network-spec.md) — camada linear e `argmax`;
- [`docs/training-spec.md`](docs/training-spec.md) — regra delta e limites;
- [`docs/generation-spec.md`](docs/generation-spec.md) — geração e parada;
- [`docs/context-spec.md`](docs/context-spec.md) — contexto K = 3;
- [`docs/corpus-spec.md`](docs/corpus-spec.md) — corpus e janelas;
- [`docs/evaluation-spec.md`](docs/evaluation-spec.md) — conjuntos A/B/C/D e
  baselines;
- [`docs/attention-spec.md`](docs/attention-spec.md) — atenção causal e os
  resultados negativos.
