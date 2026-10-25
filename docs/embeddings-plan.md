# Plano de execução — Embeddings (M3)

- **Status:** implementado e verificado (E0–E7, 2026-10-25); nenhum commit ou push.
- **Especificação:** `docs/embeddings-spec.md` v0.1.1.
- **Missão anterior:** M2 (`docs/tokenizer-spec.md` v0.2.1, `docs/tokenizer-plan.md`).
- **Execução:** prevista para ocorrer de forma autônoma, etapa por etapa, sem aprovação
  intermediária (§11).

## 1. Estado de partida

Verificado antes de escrever este plano:

| Item | Estado |
| --- | --- |
| `HEAD` | `20bb357` (`chore(agents): organize agent instructions and memory`) |
| Branch | `main`, sincronizado com `origin/main` |
| Árvore de trabalho | limpa no início; apenas os dois documentos desta missão estavam não rastreados |
| M0 | 5 casos explícitos em `tests/` |
| M1 | 20 casos gerados + 21 verificações de bytes |
| Suíte atual | `test.ps1` = 25/25; `verify-bytes.ps1` = 21/21 |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |

Comandos de referência:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

## 2. Restrições descobertas no runner atual

Estas restrições determinam a integração e não são negociáveis sem alterar a M1:

1. **`build-tests.ps1` apaga `temp/tests` inteiro** (`Remove-Item -Recurse`) antes de gerar.
   Portanto, casos de embeddings não podem ser gravados nesse diretório por outro script:
   seriam apagados ou apagariam os da M1, conforme a ordem.
2. **`verify-bytes.ps1` valida *todos* os `*.expected` de `temp/tests`** contra a gramática
   `IDS=...`/`ERRO=...` da M1. Colocar casos de embeddings em `temp/tests` faria o
   verificador da M1 falhar (21/21 → falha), mesmo com o código da M1 intacto.
3. **`test.ps1` descobre casos gerados apenas em `temp/tests`** e compara o texto
   normalizado completo; `-SelfTest` ignora os gerados.
4. **`Normalize-Output` remove o *form feed* e o epílogo** e faz `Trim()`. Os `.expected`
   não devem ter `\n` final.
5. **`test.ps1` usa UTF-8 com BOM e finais de linha LF (sem CR)**; qualquer edição deve
   preservar ambos.

Consequências obrigatórias:

- os casos de M3 vão para **`temp/embedding-tests/`** (diretório separado, ignorado pelo
  Git);
- `verify-bytes.ps1` e `build-tests.ps1` **não são modificados**;
- `test.ps1` recebe **apenas um bloco aditivo** que gera e anexa os casos de embeddings;
- o verificador da M1 continua com 21/21 e a suíte da M1 continua com 20 casos.

## 3. Decisões técnicas

| # | Decisão | Justificativa | Alternativas rejeitadas |
| --- | --- | --- | --- |
| D1 | Dimensão `D = 4` | 100 pesos, todos verificáveis à mão; cada linha cabe em uma linha de saída; grade `k/16` exata; expansão futura localizada. | `D = 2` (linhas pobres, colisões prováveis com a fórmula); `D = 8/16` (saída longa, sem ganho didático agora). |
| D2 | Tipo `real` | É o tipo numérico contínuo da linguagem, necessário para treinar depois; múltiplos de `1/16` são exatos em binário. | `inteiro` com escala fixa (exigiria conversão em toda leitura/escrita); `cadeia` (não é numérico). |
| D3 | Vetor plano `real w[100]`, índice `id*4+d` | Vetor 1D já foi executado na M1; matriz 2D é documentada, mas não comprovada neste harness; um único índice simplifica limites. | `real w[25][4]` (não comprovado; duas dimensões a validar); 25 vetores separados (não generaliza para atualização). |
| D4 | Inicialização por fórmula fechada `q=((id*7+d*3)%32)-16`, `w=q/16.0` | Determinística, sem semente, sem dependência de ambiente; 25 linhas distintas provadas por `mdc(7,32)=1`; valores exatos. | Aleatória (proibida por requisito); constante literal de 100 valores (redundante com a fórmula e mais fácil de errar). |
| D5 | Sem *clamp* em `emb_definir` | O armazenamento não deve esconder divergência de treinamento; validação de faixa pertence ao otimizador futuro. | Limitar a `[-1,1]` (mascararia *exploding gradients*). |
| D6 | Fragmento sem bibliotecas, sem estado global | Mesmo padrão da M1; permite concatenar com o tokenizador; estado explícito no driver; testável isoladamente. | Array global mutável (esconde fluxo de dados e dificulta dois modelos no mesmo programa). |
| D7 | Validação em `emb_imprimir_*`; acessores com pré-condição | As funções observáveis são totais para qualquer inteiro; leitura/escrita interna fica sem *branch* redundante. | Validar em toda chamada (duplica código e não melhora o contrato observável). |
| D8 | Erros `ID_INVALIDO` e `DIMENSAO_INVALIDA`, com ID primeiro | Códigos fechados, testáveis, sem depender da mensagem do runtime; precedência única. | Deixar o interpretador abortar (viola AC16); retornar `0` (confunde com peso válido). |
| D9 | Casos em `temp/embedding-tests/` | Evita quebrar `verify-bytes.ps1` e o gerador da M1 (§2). | Reutilizar `temp/tests` (quebra 21/21). |
| D10 | `test.ps1` recebe um bloco aditivo | Menor alteração possível; mantém uma única suíte e um único resumo. | Runner separado (duplica descoberta, normalização e contagem). |
| D11 | Verificador próprio com oráculo independente | Recalcula a fórmula em aritmética exata, sem confiar nos `.expected` gerados pelo módulo. | Confiar só na comparação de strings (congelaria um eventual erro). |
| D12 | Fonte ASCII puro | Mesmo contrato da M1 (A10); rótulos (`INFO=`, `VETOR=`, `ERRO=`) são ASCII. | UTF-8 com acentos (adiciona variável de codificação sem benefício). |
| D13 | Constantes `25/4/100` como `const` com literal inteiro | Uma única fonte de verdade no fragmento; E0/P9b comprovou `const` visível e como tamanho de vetor, mas rejeitou inicialização por expressão. | Literais repetidos (propensão a divergência); expressão em `const` (erro de sintaxe). |

**Ajuste obrigatório B (aplicado):** a grade `k/16` e a faixa `[-1, 0.9375]` descrevem
apenas a inicialização canônica. `emb_definir` não valida nem limita o valor; o caso
`emb_atualizacao` grava `0.5` e `1.7` (o segundo fora da grade e de `[-1, 1]`) e exige que
o valor seja armazenado e impresso sem alteração. O verificador aplica a mesma distinção:
somente o estado canônico é conferido contra a grade; as mutações são simuladas com os
valores exatos do driver.

### 3.1 Interface com o tokenizador

- Não há acoplamento de código: `src/embeddings.por` não chama nem importa o tokenizador.
- O contrato compartilhado é o **espaço de IDs** da M1: `0 = UNK`, `1..24` palavras fixas.
- `UNK` **não** é descartado: tem linha própria, como qualquer outro ID.
- O pipeline futuro é `tokenizar(texto) -> IDs -> w[id*4+d]`; a M3 apenas garante que
  qualquer ID emitido pela M1 (sempre `0..24`) é aceito.
- E0/P11 verifica, de forma informativa, que os dois fragmentos podem ser concatenados no
  mesmo driver (o tokenizador inclui `Texto`; embeddings não inclui nada).

## 4. Arquivos previstos

| Ação | Arquivo | Observação |
| --- | --- | --- |
| criar | `src/embeddings.por` | fragmento; ASCII; sem `programa`/`inicio`. |
| criar | `scripts/build-embedding-tests.ps1` | gera `temp/embedding-tests/*.por` e `*.expected` em UTF-8 sem BOM. |
| criar | `scripts/verify-embedding-bytes.ps1` | formato bruto + oráculo independente. |
| modificar | `scripts/test.ps1` | **somente** bloco aditivo de geração/descoberta; preservar BOM e LF. |
| criar | `docs/embeddings-spec.md` | contrato (esta missão). |
| criar | `docs/embeddings-plan.md` | este plano + evidências. |
| criar (descartável) | `temp/e0-emb/**` | sondas E0, ignoradas pelo Git. |
| criar (gerado) | `temp/embedding-tests/**` | casos gerados, ignorados pelo Git. |

Proibido alterar: `src/tokenizador.por`, `scripts/build-tests.ps1`, `scripts/verify-bytes.ps1`,
`tests/*`, `README.md`, `AGENTS.md`.

## 5. Etapa E0 — Sondas e congelamento do contrato (CONCLUÍDA em 2026-10-25)

Diretório: `temp/e0-emb/`. Harness `run-probes.ps1` no padrão da M1: `ProcessStartInfo`,
`UseShellExecute=false`, stdin com `" "` + quebra de linha, leitura de
`StandardOutput.BaseStream`/`StandardError.BaseStream` para preservar bytes crus;
`<sonda>.out.bin`, `.err.bin`, `.out.txt`, `.err.txt`. Cada sonda é um `.por` independente.
O diretório é descartável e não entra no Git.

| Sonda | O que mede | Decide |
| --- | --- | --- |
| P1 | `real w[100]` local; laço; leitura/escrita indexada; `w[0]` e `w[99]`. | D3 viável |
| P2 | `real[]` como parâmetro: escrita em `w[i]` dentro da função visível no chamador; leitura após escrita. | G1 |
| P2b | (reserva) array global declarado no bloco `programa`, visível a funções, sem parâmetro. | alternativa de G1 |
| P3 | Função que retorna `real`; função que retorna `logico`; função sem tipo de retorno. | assinaturas |
| P4 | Literais `-1.0`, `0.0625`, `0.9375`; atribuição; igualdade `==` entre reais iguais; `-0.0`. | AC11, igualdade do resumo |
| P5 | `%` com operandos não negativos; precedência com parênteses; `((24*7+3*3)%32)-16 == 1`. | fórmula |
| P6 | `inteiro / 16.0` → real exato; `inteiro / 16` → truncado (comprova a proibição). | D4 |
| P7 | Serialização de todos os 100 valores canônicos; bytes exatos de `VETOR=0`, `PESO=0 0`, `PESO=4 1`, `PESO=16 0`, `RESUMO`. | G2 / formato A × C |
| P8 | `escreva` com múltiplos argumentos misturando `cadeia`, `inteiro` e `real`; `\n`. | saída |
| P9 | `const inteiro` no escopo do `programa`, visível a funções; `const` dentro de função. | G3 |
| P9b | Repetição de P9 com literais inteiros (sem expressão) e uso de `const` como tamanho de vetor. | G3 |
| P10 | Leitura de `w[100]` e escrita em `w[-1]` (em programa separado): aborta, ignora ou corrompe? | justifica validação |
| P11 | Tokenizador + embeddings concatenados no mesmo driver; tokenizar e imprimir vetor de um ID. | informativo |
| P12 | Laços aninhados 25×25 com comparação de reais e contador; `!=`; `nao`. | resumo |
| P13 | Driver com 25 linhas de saída: cada linha termina em LF, sem CR, epílogo único. | verificador |
| P14 | Cast `inteiro(real)` e conversão implícita real→inteiro (truncamento). | reserva |
| P15 | Serialização de valores de mutação `1.7`, `1.75`, `0.5`, `-2.25`. | G2 / caso de atualização |

### 5.1 Portões de decisão

| Portão | Condição | Ação se falhar |
| --- | --- | --- |
| **G1** | P2 comprova passagem por referência | usar array global (P2b) + funções sem parâmetro de vetor; registrar desvio na spec (`v0.1.1`) antes de E1. |
| **G2** | P7 produz reais exatos conforme §8.1 (ponto, sem vírgula/expoente, ≤ 4 casas, `-1.0`/`0.0`/`0.9375` corretos) | adotar formato C (spec §8.3), congelar rótulos `OK/FALHA`; nenhuma outra mudança de arquitetura. |
| **G3** | P9 aceita `const` visível a funções | usar `const` locais por função ou literais nomeados por comentário; registrar. |
| **G4** | P5/P6 exatos | se a divisão real não for exata, manter `q` inteiro no armazenamento e converter só na borda (formato C com inteiros); spec `v0.1.1`. |
| **G5** | P10 aborta ou ignora, mas nunca escreve silenciosamente em outra posição | se houver *clamp*/escrita silenciosa, reforçar a ordem de validação e adicionar caso extra de fronteira. |
| **G6** | P13 epílogo idêntico ao da M1 | se divergir, o verificador usa busca de `\n\nPrograma finalizado` em vez de offset fixo. |

**Critério de conclusão da E0:** todos os portões resolvidos, formato escolhido (A ou C),
tabela de referência confirmada valor a valor e evidência registrada em §12. Se G1 e G3
falharem simultaneamente, **parar** e reportar (o desenho de API precisa de revisão).

## 6. Etapas E1–E7

Cada etapa é executada por completo antes da seguinte: implementar → gerar casos → rodar
suíte → corrigir → registrar evidência. Nenhuma etapa "passa" com falha pendente.

### E1 — Núcleo de leitura e integração mínima (CONCLUÍDA em 2026-10-25)

**Depende de:** E0 concluída.
**Arquivos:** `src/embeddings.por`, `scripts/build-embedding-tests.ps1`, `scripts/test.ps1`.

Alterações:

- criar as constantes (`TAM_VOCAB`, `DIM`, `TOTAL`) conforme G3;
- `emb_id_valido`, `emb_dim_valida`, `emb_obter`, `inicializar_embeddings`,
  `emb_imprimir_info`, `emb_imprimir_vetor`;
- `build-embedding-tests.ps1` no molde do builder da M1: limpa apenas
  `temp/embedding-tests`, concatena o fragmento ao driver, valida UTF-8 sem BOM, escreve
  `.por`/`.expected` e recusa nomes duplicados;
- `test.ps1`: após o bloco da M1 e ainda dentro de `if (-not $SelfTest)`, chamar o novo
  builder e anexar os `*.expected` de `temp/embedding-tests` a `$testCases`. Não alterar o
  bloco da M1, o autoteste nem o resumo.

Casos: `emb_info`, `emb_unk`, `emb_id_1`, `emb_id_24`, `emb_amostra_vetores`,
`emb_determinismo_a`, `emb_determinismo_b` (7).

Testes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-embedding-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

**Conclusão:** 7 novos casos passam; suíte total 32/32 (5 M0 + 20 M1 + 7 M3); 21/21 bytes
da M1 preservados; nenhuma saída extra nas linhas.

### E2 — Consulta pontual, validadores e layout (CONCLUÍDA em 2026-10-25)

**Depende de:** E1.
**Arquivos:** `src/embeddings.por`, `scripts/build-embedding-tests.ps1`,
`scripts/verify-embedding-bytes.ps1`.

Alterações: `emb_imprimir_peso`; casos de validadores e de layout; verificador v1 com
gramática de linha, epílogo e oráculo independente para os casos existentes.

Casos: `emb_peso`, `emb_validadores`, `emb_layout` (3 → 10).

**Conclusão:** 35/35 na suíte; verificador aprova 10 casos; M1 21/21.

### E3 — Erros e estado após erro (CONCLUÍDA em 2026-10-25)

**Depende de:** E2.
**Arquivos:** `src/embeddings.por`, `scripts/build-embedding-tests.ps1`,
`scripts/verify-embedding-bytes.ps1`.

Alterações: validação e ordem ID→dimensão em `emb_imprimir_vetor`/`emb_imprimir_peso`;
nenhum `escreva` antes da validação.

Casos: `emb_id_invalido_neg`, `emb_id_invalido_25`, `emb_dim_invalida_neg`,
`emb_dim_invalida_4`, `emb_ambos_invalidos`, `emb_apos_erro` (6 → 16).

**Conclusão:** 41/41; nenhuma saída parcial; verificador confirma que `ERRO=` é a única
linha da chamada e que o estado segue canônico no caso `emb_apos_erro`.

### E4 — Escrita e reinicialização (CONCLUÍDA em 2026-10-25)

**Depende de:** E3.
**Arquivos:** `src/embeddings.por`, `scripts/build-embedding-tests.ps1`.

Alterações: `emb_definir`; casos de mutação.

Casos: `emb_atualizacao`, `emb_reinicializacao` (2 → 18).

**Conclusão:** 43/43; célula alterada reflete `0.5`; vizinhas e demais 99 posições
inalteradas; reinicialização restaura a tabela.

### E5 — Resumo e matriz completa (CONCLUÍDA em 2026-10-25)

**Depende de:** E4.
**Arquivos:** `src/embeddings.por`, `scripts/build-embedding-tests.ps1`,
`scripts/verify-embedding-bytes.ps1`.

Alterações: `emb_resumo` (menor, maior, distintos); verificador completo para os 19 casos,
com modelo de estado por nome de caso.

Casos: `emb_resumo` (1 → 19).

**Conclusão:** 44/44 na suíte; verificador aprova 19/19; M1 21/21; resumo canônico
`RESUMO=25 100 -1.0 0.9375 25`.

### E6 — Endurecimento e regressão (CONCLUÍDA em 2026-10-25)

**Depende de:** E5.
**Arquivos:** os mesmos, apenas correções.

Verificações obrigatórias:

1. `build-tests.ps1` + `verify-bytes.ps1` → 21/21 (M1 intocada).
2. `test.ps1` → 44/44 com 0 falhas.
3. `test.ps1 -SelfTest` → 1 falha intencional, exit 1.
4. `build-embedding-tests.ps1` duas vezes seguidas → mesmos bytes (determinismo do
   builder).
5. `build-tests.ps1` depois do builder de embeddings → M1 continua 20 casos e o builder de
   embeddings não foi apagado (diretórios independentes).
6. Nenhum `*.expected` em `temp/tests` fora do padrão da M1.
7. Fonte ASCII, UTF-8 sem BOM, sem CR dentro das linhas de carga.
8. Contagem de casos do `test.ps1` confere com 5 + 20 + 19.
9. Repetir `test.ps1` e conferir saídas idênticas (AC17).

**Conclusão:** todos os itens acima com evidência registrada; nenhum arquivo proibido
modificado (`git status` só mostra os arquivos previstos em §4).

### E7 — Fechamento documental (CONCLUÍDA em 2026-10-25)

**Depende de:** E6.
**Arquivos:** `docs/embeddings-plan.md` (evidências), `docs/embeddings-spec.md` (somente se
E0 alterou o contrato).

Alterações: preencher §12 com comandos, contagens, exit codes e tempos reais; registrar
qual formato (A ou C) foi congelado; listar desvios de G1–G6, se houver; atualizar o
`Status` da spec para "implementado e verificado" somente se todos os ACs tiverem
evidência.

**Conclusão:** `git diff --check` limpo; árvore contém apenas arquivos previstos; relatório
final apresentado. **Não criar commit e não executar push** (não autorizado para esta
missão). Parar.

## 7. Matriz de testes

Todos os valores abaixo assumem formato A congelado (E0/G2). Se G2 falhar, o formato C
preserva os mesmos grupos de verificação, com rótulos `OK/FALHA`.

| # | Caso | Ação do driver | Saída esperada (texto completo) | Oráculo | Etapa |
| ---: | --- | --- | --- | --- | --- |
| 1 | `emb_info` | `inicializar; emb_imprimir_info()` | `INFO=25 4 100` | constantes | E1 |
| 2 | `emb_unk` | init; `emb_imprimir_vetor(w, 0)` | `VETOR=0 -1.0 -0.8125 -0.625 -0.4375` | tabela §4.1 | E1 |
| 3 | `emb_id_1` | init; vetor `1` | `VETOR=1 -0.5625 -0.375 -0.1875 0.0` | tabela | E1 |
| 4 | `emb_id_24` | init; vetor `24` | `VETOR=24 -0.5 -0.3125 -0.125 0.0625` | tabela | E1 |
| 5 | `emb_amostra_vetores` | init; vetores `4`, `9`, `17` | 3 linhas: `0.75 0.9375 -0.875 -0.6875`; `0.9375 -0.875 -0.6875 -0.5`; `0.4375 0.625 0.8125 -1.0` | tabela | E1 |
| 6 | `emb_determinismo_a` | init; vetores `0..24` em ordem | 25 linhas `VETOR=` | tabela | E1 |
| 7 | `emb_determinismo_b` | idêntico a A | idêntico a A | tabela | E1 |
| 8 | `emb_peso` | init; pesos `(0,0) (4,1) (9,0) (16,0) (24,3) (11,1) (3,2)` | `PESO=0 0 -1.0`; `PESO=4 1 0.9375`; `PESO=9 0 0.9375`; `PESO=16 0 0.0`; `PESO=24 3 0.0625`; `PESO=11 1 0.0`; `PESO=3 2 0.6875` | tabela | E2 |
| 9 | `emb_validadores` | ids `-1,0,24,25`; dims `-1,0,3,4` | `VALIDO=0`, `VALIDO=1`, `VALIDO=1`, `VALIDO=0`, `VALIDO=0`, `VALIDO=1`, `VALIDO=1`, `VALIDO=0` | limites | E2 |
| 10 | `emb_layout` | init; 16 comparações `w[id*4+d] == emb_obter(...)` para `id∈{0,9,17,24}` e `d=0..3` | `LAYOUT=OK` | layout | E2 |
| 11 | `emb_id_invalido_neg` | init; vetor `-1` | `ERRO=ID_INVALIDO` | limites | E3 |
| 12 | `emb_id_invalido_25` | init; vetor `25` | `ERRO=ID_INVALIDO` | limites | E3 |
| 13 | `emb_dim_invalida_neg` | init; peso `(0,-1)` | `ERRO=DIMENSAO_INVALIDA` | limites | E3 |
| 14 | `emb_dim_invalida_4` | init; peso `(0,4)` | `ERRO=DIMENSAO_INVALIDA` | limites | E3 |
| 15 | `emb_ambos_invalidos` | init; peso `(-1,4)` | `ERRO=ID_INVALIDO` | precedência | E3 |
| 16 | `emb_apos_erro` | init; vetor `25`; vetor `0` | `ERRO=ID_INVALIDO` + `VETOR=0 -1.0 -0.8125 -0.625 -0.4375` | tabela | E3 |
| 17 | `emb_atualizacao` | init; definir `(5,2)=0.5` e `(5,3)=1.7`; vetores `5` e `6` | `VETOR=5 -0.8125 -0.625 0.5 1.7` + `VETOR=6 -0.375 -0.1875 0.0 0.1875` | tabela + mutação | E4 |
| 18 | `emb_reinicializacao` | init; definir `(5,2)=1.7`; init; vetor `5` | `VETOR=5 -0.8125 -0.625 -0.4375 -0.25` | tabela | E4 |
| 19 | `emb_resumo` | init; `emb_resumo(w)` | `RESUMO=25 100 -1.0 0.9375 25` | varredura | E5 |

Regras:

- `.expected` contém exatamente o texto acima, sem `\n` final; cada linha emitida termina
  em `\n`.
- Nenhum caso depende de aleatoriedade, tempo, entrada do usuário ou arredondamento.
- `emb_determinismo_a`/`_b` são gerados pelo mesmo driver, mas executados como processos
  independentes; a comparação byte a byte é feita pelos `.expected` idênticos.
- Se G2 levar ao formato C, os grupos são: `INIT`, `UNK`, `ID1`, `ID24`, `AMOSTRA`,
  `DETERMINISMO` (A/B), `PESOS`, `VALIDACAO`, `LAYOUT`, `ERROS`, `ATUALIZACAO`,
  `REINICIALIZACAO`, `RESUMO`, `ERRO_ESTADO`; os 19 arquivos de caso continuam os mesmos.

### 7.1 Contagem de testes

| Origem | Casos |
| --- | ---: |
| M0 (`tests/`) | 5 |
| M1 (gerados em `temp/tests`) | 20 |
| M3 (gerados em `temp/embedding-tests`) | 19 |
| **Total** | **44** |

## 8. Integração com o runner

Alteração exata em `scripts/test.ps1`, dentro de `if (-not $SelfTest)`, imediatamente depois
do bloco existente que anexa os casos da M1:

```powershell
    $embeddingBuilder = Join-Path $PSScriptRoot "build-embedding-tests.ps1"
    try {
        & $embeddingBuilder
    } catch {
        Write-Host "ERROR: embedding test builder failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $embeddingRoot = "temp/embedding-tests"
    $embeddingCases = @(Get-ChildItem -Path $embeddingRoot -Filter "*.expected" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($expectedFile in $embeddingCases) {
        $caseName = [IO.Path]::GetFileNameWithoutExtension($expectedFile.Name)
        $testCases += @{
            Name = $caseName
            File = "$embeddingRoot/$caseName.por"
            ExpectedOutput = [IO.File]::ReadAllText($expectedFile.FullName)
        }
    }
```

Cuidados:

- preservar o BOM UTF-8 e os finais de linha LF (sem CR) do arquivo;
- não alterar `Normalize-Output`, a lista explícita da M0, o autoteste nem o resumo;
- nomes de caso têm prefixo `emb_` (sem colisão com os 20 da M1);
- se o builder de embeddings não existir, o runner deve falhar de forma explícita (nunca
  ignorar silenciosamente).

`verify-embedding-bytes.ps1` é independente e **não** é chamado por `test.ps1` (assim como
`verify-bytes.ps1` também não é). O verificador:

1. exige os 19 nomes esperados, sem faltas nem extras;
2. roda cada `.por` e lê os bytes crus;
3. valida `0x0C` inicial, carga ASCII imprimível, LF no fim de cada linha, nenhum CR na
   carga e epílogo exato;
4. valida a gramática de cada linha (`INFO`, `VETOR`, `PESO`, `RESUMO`, `VALIDO`,
   `LAYOUT`, `ERRO`);
5. recalcula a tabela em PowerShell com aritmética inteira e `[decimal]`, sem `double`;
6. aplica o modelo de estado por caso (`emb_atualizacao`: `(5,2)=0.5` e
   `(5,3)=1.7`; `emb_reinicializacao`: canônico; demais: canônico);
7. compara cada número parseado como `[decimal]` com `InvariantCulture` e exige
   `valor * 16` inteiro entre `-16` e `15`, exatamente igual ao oráculo;
8. verifica que a fonte é ASCII puro e que o fragmento não contém `programa`/`inicio`.

## 9. Critérios de aceitação da missão

Além dos ACs da spec (§9), a missão só é considerada concluída quando:

- **MA1** — `build-tests.ps1` e `verify-bytes.ps1` da M1 permanecem intocados e passam
  21/21.
- **MA2** — `test.ps1` passa 44/44 com exit 0.
- **MA3** — `test.ps1 -SelfTest` continua detectando a falha intencional (exit 1).
- **MA4** — `verify-embedding-bytes.ps1` passa 19/19 (ou o número exato de casos da §7) e
  usa oráculo independente.
- **MA5** — nenhum arquivo proibido foi modificado; `git status --short` lista apenas os
  arquivos da §4.
- **MA6** — duas execuções consecutivas produzem os mesmos bytes (determinismo).
- **MA7** — as evidências reais estão registradas em §12, sem valores inventados.

## 10. Riscos e limitações

| Risco | Prob. | Impacto | Mitigação |
| --- | --- | --- | --- |
| Serialização de `real` com vírgula, expoente ou casas fixas | média | `.expected` inválidos | E0/P7 antes de qualquer `.expected`; fallback formato C (G2). |
| Arrays passados por valor | baixa | setter/init inócuos | E0/P2; fallback array global (G1). |
| `const` global não aceito | média | erro de sintaxe no fragmento | E0/P9; fallback `const` local ou literais (G3). |
| `/ 16` inteiro truncando | média | tabela errada (0 em tudo) | E0/P6 + revisão obrigatória de que existe `16.0`; caso de teste pega. |
| `%` com precedência inesperada | média | fórmula deslocada | parênteses explícitos + E0/P5 + tabela verificada. |
| Igualdade de reais no resumo | baixa | distintos errado | valores são múltiplos exatos de `1/16`; E0/P4; AC6/AC15. |
| Índice fora dos limites aborta o processo | média | caso de erro derruba a suíte | validação antes do acesso (E3); E0/P10 documenta o comportamento. |
| `escreva` parcial antes do erro | baixa | saída fora do contrato | validar antes de imprimir; caso `emb_apos_erro` e verificador. |
| Colisão de nomes/diretórios com a M1 | baixa | 21/21 quebra | diretório separado + prefixo `emb_` + §2. |
| Edição do `test.ps1` alterar BOM/LF | média | diff ruidoso ou falha do runner | editar preservando bytes; conferir BOM e ausência de CR em E6. |
| Interpretador lento (≈1,3 s/caso) | alta | suíte ~60 s | 19 casos curtos; execução sequencial aceitável; sem otimização prematura. |
| Crescer `D` depois exigir retrabalho | baixa | mudança localizada | constantes e tabela isoladas; API por `id,d` já generaliza. |

Limitações explícitas desta missão: não há treinamento, não há semântica aprendida, os
pesos são arbitrários e determinísticos, não há normalização nem operações vetoriais, e a
qualidade dos embeddings não é avaliada (não há objetivo de tarefa).

## 11. Execução autônoma

### 11.1 Laço por etapa

Para cada etapa de E0 a E7, nesta ordem:

1. **Ler** a etapa e confirmar dependências (a anterior está concluída com evidência).
2. **Implementar** somente os arquivos previstos na etapa.
3. **Gerar** os casos com o builder correspondente.
4. **Executar** a suíte completa (`test.ps1`) e, a partir de E2, também o verificador.
5. **Comparar** com os critérios da etapa; se falhar, diagnosticar a causa raiz e corrigir.
6. **Repetir** os passos 3–5 até passar, com no máximo **3 ciclos de correção** por etapa.
7. **Registrar** evidência em §12 (comando, exit code, linha de resumo, tempo, data).
8. **Avançar** automaticamente para a próxima etapa.

Regras de correção:

- corrigir a implementação, nunca afrouxar o teste ou o oráculo;
- nunca gerar `.expected` a partir de uma execução suspeita antes de conferir o oráculo
  independente;
- se um caso falhar por formato, resolver na E0/G2 ou em ajuste único do builder, não caso
  a caso;
- se a suíte da M1 falhar, **parar imediatamente** (regressão inaceitável).

### 11.2 Quando interromper

Parar e reportar, sem tentar contornar, se:

- um portão G1–G6 não puder ser resolvido com as alternativas previstas;
- a suíte da M1 deixar de passar 21/21 ou 20/20 casos;
- for necessário alterar arquivo fora da §4 (por exemplo `verify-bytes.ps1`,
  `build-tests.ps1`, `tests/*`, `README.md`);
- houver ambiguidade material no contrato (por exemplo, formato de saída impossível de
  representar sem mudar a spec);
- houver risco de perda de dados (sobrescrever arquivos não rastreados, apagar `temp/`
  além dos diretórios gerados, reescrever histórico Git);
- o interpretador desaparecer ou mudar de comportamento de forma que invalide E0.

Em interrupção: registrar a etapa, o comando, a saída relevante e a hipótese; **não**
inventar resultado; classificar como PARCIAL ou BLOQUEADO.

### 11.3 Limites de ação

- criar/editar apenas: `src/embeddings.por`, `scripts/build-embedding-tests.ps1`,
  `scripts/verify-embedding-bytes.ps1`, bloco aditivo em `scripts/test.ps1`, os dois docs
  desta missão e `temp/**`;
- não instalar nada, não acessar rede, não adicionar dependências;
- não criar commit, tag, branch ou push nesta missão;
- não iniciar M4 (rede neural, treinamento, atenção, geração);
- não apagar `temp/tests` manualmente nem os backups locais ignorados.

### 11.4 Definição de pronto

A missão termina **PRONTA** somente se MA1–MA7 estiverem comprovados com saída real. Caso
contrário, o relatório final usa **PARCIAL** (etapas concluídas + pendências) ou
**BLOQUEADO** (impedimento), sempre com evidência.

## 12. Registro de evidências

Execução real em 2026-10-25, Windows 11 / PowerShell 5.1, interpretador
`C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat`. Sondas em `temp/e0-emb/`
(descartável, fora do Git).

### 12.1 E0 — sondas (todas executadas)

| Sonda | Resultado observado | Portão | Veredito |
| --- | --- | --- | --- |
| P1 | `real w[100]` local; `w[0]=-1.0`, `w[16]=0.0`, `w[99]=-0.8125`. | D3 | PASS |
| P2 | Escrita em `v[0]`/`v[7]` dentro da função visível no chamador; leitura `-1.0`. | G1 | PASS |
| P3 | Retorno `real` (0.9375), `logico` (verdadeiro/falso) e função sem retorno. | assinaturas | PASS |
| P4 | Literais negativos e `==` exatos; `-0.0` é impresso como `-0.0`. | AC11 | PASS com ressalva |
| P5 | `((24*7+3*3)%32)-16 = 1`; `-7 % 32 = -7` (não usado na fórmula). | G4 | PASS |
| P6 | `17 / 16.0 = 1.0625`; `17 / 16 = 1.0` com aviso de conversão. | G4 | PASS |
| P7 | 100 linhas `VETOR=` idênticas à tabela; `PESO` e `RESUMO=25 100 -1.0 0.9375 25`. | G2 | PASS |
| P8 | `escreva` com `cadeia`, `real`, `inteiro` e `logico`; `-0.0` literal. | saída | PASS |
| P9 | `const inteiro TOTAL = TAM * DIM` rejeitada: "deve ser inicializada com um valor". | G3 | FAIL |
| P9b | `const` com literais, visível a funções e como tamanho de vetor (`real w[TOTAL]`). | G3 | PASS |
| P10a/P10b | Índice 100 e índice -1 abortam com erro de execução (stderr; exit 0 do processo). | G5 | PASS (aborta) |
| P11b | `src/tokenizador.por` + `src/embeddings.por` no mesmo driver: `IDS=1 0`, `VETOR=0 ...`, `INFO=25 4 100`. | informativo | PASS |
| P12 | Laços 25×25 com `!=` e `nao`: `DISTINTOS=25`. | resumo | PASS |
| P13 | 25 linhas; corpo só com LF, sem CR; epílogo CRLF idêntico à M1. | G6 | PASS |
| P14 | Cast `inteiro(expr)` rejeitado ("expressão esperada"). | reserva | FAIL (não usado) |
| P14b | Atribuição real→inteiro trunca (`0.9375*16 → 15`, `1.75 → 1`) com aviso. | reserva | PASS (não usado) |
| P15 | `1.7`, `1.75`, `0.5`, `-2.25` serializados como `1.7`, `1.75`, `0.5`, `-2.25`. | G2 | PASS |

**Formato congelado:** **A** (spec §8.1). Nenhuma saída dependente de locale, vírgula ou
expoente foi observada.

**Desvios registrados:**

- `const` exige literal inteiro (P9); constantes do módulo usam `25`, `4`, `100`.
- `-0.0` não é normalizado pelo runtime; o contrato proíbe `-0.0` na saída e a
  inicialização canônica produz `0.0`.
- Não existe cast `inteiro(expr)`; não foi necessário.
- Nenhum desvio de arquitetura: arrays por referência, vetor plano e formato A
  confirmados.

### 12.2 Etapas

| Etapa | Comando | Exit | Resultado | Data |
| --- | --- | ---: | --- | --- |
| E1 | `build-embedding-tests.ps1` + `test.ps1` | 0 | 7 casos; suíte 32/32; M1 21/21 | 2026-10-25 |
| E2 | `test.ps1` + `verify-embedding-bytes.ps1` | 0 | 10 casos; suíte 35/35; verificador 10/10 | 2026-10-25 |
| E3 | `test.ps1` + `verify-embedding-bytes.ps1` | 0 | 16 casos; suíte 41/41; verificador 16/16 | 2026-10-25 |
| E4 | `test.ps1` + `verify-embedding-bytes.ps1` | 0 | 18 casos; suíte 43/43; verificador 18/18 | 2026-10-25 |
| E5 | `test.ps1` + `verify-embedding-bytes.ps1` | 0 | 19 casos; suíte 44/44; verificador 19/19 | 2026-10-25 |
| E6 | M1 + 2×`test.ps1` + `-SelfTest` + hash do builder | 0 / 0 / 1 | M1 21/21; 44/44 e 44/44; autoteste 1 FAIL; 38/38 arquivos idênticos; diretórios 20 e 19 | 2026-10-25 |
| E7 | sequência final obrigatória | 0 / 1 | ver §12.3 | 2026-10-25 |

Sequência final (tempos reais):

| # | Comando | Exit | Tempo | Resultado |
| ---: | --- | ---: | ---: | --- |
| 1 | `build-tests.ps1` | 0 | 0,41 s | 20 casos |
| 2 | `build-embedding-tests.ps1` | 0 | 0,52 s | 19 casos |
| 3 | `verify-bytes.ps1` | 0 | 22,85 s | 21/21 |
| 4 | `verify-embedding-bytes.ps1` | 0 | 22,41 s | 19/19 |
| 5 | `test.ps1` (A) | 0 | 50,82 s | 44/44 |
| 6 | `test.ps1` (B) | 0 | 50,50 s | 44/44 |
| 7 | `test.ps1 -SelfTest` | 1 | 1,33 s | 1 FAIL intencional |

Determinismo: duas execuções de `test.ps1` produziram texto idêntico; duas gerações do
builder produziram os mesmos 38 hashes SHA-256 (19 `.por` + 19 `.expected`).

### 12.3 Fechamento

- Suíte M0+M1+M3: **44/44** (5 + 20 + 19), duas vezes, exit 0.
- Casos antigos preservados: **25/25** dentro dos 44.
- Bytes M1: **21/21**.
- Verificador M3: **19/19**, com oráculo independente.
- Autoteste: exit **1**, com 1 falha intencional.
- Arquivos criados: `src/embeddings.por`, `scripts/build-embedding-tests.ps1`,
  `scripts/verify-embedding-bytes.ps1`, `docs/embeddings-spec.md`,
  `docs/embeddings-plan.md`.
- Arquivo modificado: `scripts/test.ps1` (somente o bloco aditivo; BOM e LF preservados).
- Arquivos proibidos: inalterados (`src/tokenizador.por`, `scripts/build-tests.ps1`,
  `scripts/verify-bytes.ps1`, `tests/*`, `README.md`, `AGENTS.md`).
- Pendências: nenhuma.
