# Plano de execução - Avaliação de generalização (M9)

- **Status:** planejamento apenas. Nenhum arquivo de código, corpus, script ou
  teste foi criado ou alterado. Nenhum modelo foi executado sobre o holdout.
  Nenhum commit ou push será feito nesta fase.
- **Especificação:** `docs/evaluation-spec.md` v0.1.0.
- **Objetivo:** medir, de forma reproduzível, se o estado congelado da M8 acerta
  contextos de 3 tokens que nunca viu, separando isso de memorização dos 10
  exemplos de treino.
- **Entrega desta fase:** exclusivamente `docs/evaluation-spec.md` e
  `docs/evaluation-plan.md`.
- **Parada:** após estes dois documentos, aguardar aprovação. Não iniciar E0.

## 1. Pré-voo medido

Verificado por comando antes de escrever este plano:

| Item | Estado medido | Evidência |
| --- | --- | --- |
| Branch | `main` | `git branch --show-current` |
| `HEAD` | `6f6ec0ea3016579844c5467165892df79c35d951` | `git rev-parse HEAD` |
| `origin/main` | mesmo commit; 0 ahead / 0 behind | `git rev-list --left-right --count HEAD...origin/main` |
| Árvore de trabalho | limpa antes dos docs; depois, apenas os dois docs novos | `git status --short` |
| Suíte de partida | **116/116**, `Failed: 0`, exit `0` | `temp/m8-verify-suite.log` (não reexecutada) |
| Verificador M8 | **18/18**, `Failures: 0`, exit `0`, 1.105 s | `temp/m8-verify-corpus-bytes-final.log` |
| Verificador M7 | **16/16**, `Failures: 0`, exit `0`, 635 s | `temp/m8-verify-context-bytes.log` |
| Autoteste | **0/1**, exit `1` intencional | `temp/m8-verify-selftest.log` |
| Corpus | 165 bytes, SHA-256 `d6eb8a78...b6113` | `corpus/m8-corpus-v1.txt` |
| `src/contexto.por` | blob `9da552861c58d145a1d1c52442e0c27a4c42ce2e` | `git hash-object` |
| `src/corpus.por` | blob `53e3c624a0f0455721aafb608c965a392cc9261d` | `git hash-object` |
| `scripts/test.ps1` | blob `e10771b7b89f7ff3132025f57e63a70683600d75` | `git hash-object` |

Leituras feitas nesta fase: `AGENTS.md`; `docs/tokenizer-spec.md` (vocabulário
e IDs); `docs/context-spec.md` §1.2, §3.2-3.3, §6.4, §10.5, §11;
`docs/corpus-spec.md` §7-9; `docs/corpus-plan.md`; `src/contexto.por`
(assinaturas e funções puras); `src/corpus.por` (lotes, perda, treino);
`scripts/test.ps1` (blocos aditivos M7/M8); `scripts/verify-context-bytes.ps1`
(V1/V16); `scripts/verify-corpus-bytes.ps1` (V1/V18); `scripts/build-corpus-tests.ps1`
(padrão de concatenação e oráculo); `scripts/verify-corpus-bytes.ps1`
(normalização de saída e epílogo).

Nenhuma suíte foi executada nesta fase. Os resultados acima são os logs
oficiais da missão anterior, preservados em `temp/`.

## 2. Auditoria estrutural do holdout (sem modelo)

Esta auditoria usou apenas os literais de `docs/evaluation-spec.md` §4 e o
Apêndice A. Nenhum peso foi carregado, nenhum `ctx_argmax` foi chamado.

| Verificação | Resultado |
| --- | --- |
| Serialização canônica | 50 linhas, 724 bytes, 0 CR, 1 LF final |
| SHA-256 | `e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10` |
| Contextos de C | 32 predições, 32 contextos distintos |
| Vazamento em C | 0 contextos de C nos 10 contextos de treino |
| Sufixo de 2 tokens em C | 0 contextos de C compartilham sufixo de 2 tokens com o treino |
| B | 10 pares vistos + 10 contextos inéditos |
| B_VISTO x A | mesmos 10 pares, em ordem diferente |
| D | 10/10 contextos vistos, 10/10 pares ausentes, `t' != t`, `1 <= t' <= 24` |
| IDs | todos em `1..24`; nenhum `0` (UNK) nos conjuntos de avaliação |
| Majoritário 24 | A 5/10; B 5/20; C 8/32; D 1/10 |
| Memorização | A 10/10; B 10/20; C 8/32; D 0/10 |

Esses números são pré-registrados. O baseline não treinado será medido em E0 e
congelado; não é presumido.

## 3. Decisão de arquitetura: runner separado, sem tocar na suíte de 116

### 3.1 Opção A (recomendada): runner e verificador próprios

Criar `scripts/test-evaluation.ps1` e `scripts/verify-evaluation-bytes.ps1`, com
casos em `temp/evaluation-tests/`, sem alterar `scripts/test.ps1` nem os
verificadores M1-M8.

Vantagens:

- preserva literalmente os 116 testes e os hashes congelados da M7/M8;
- não exige re-pin de `test.ps1` nem mudança em V1/V18 de verificadores
  protegidos;
- mantém o escopo da missão pequeno e auditável;
- o verificador novo pode pinar os hashes de M1-M8 e provar que nada antigo
  mudou.

Desvantagens:

- os casos novos não aparecem no `scripts/test.ps1` histórico; é preciso
  executar o runner novo separadamente;
- dois pontos de entrada de teste no projeto.

### 3.2 Opção B (não recomendada): integrar em `scripts/test.ps1`

Adicionar um bloco M9 ao runner faria a suíte passar de 116 para ~126 casos.
Isso quebraria, de forma objetiva:

- **M8 V1** (`scripts/verify-corpus-bytes.ps1`): exige `test.ps1` com exatamente
  402 linhas e reconstrói o hash removendo apenas o bloco M8; o bloco M9
  permaneceria na reconstrução. Além disso, a allowlist de `git status` não
  conhece os artefatos M9.
- **M8 V18**: exige `Passed: 116` e `Total: 116` literais; 126 falharia.

Seria necessário aplicar o mesmo tipo de patch já autorizado na M7:
`-lt`/`>=` no lugar de igualdade, reconstrução que remove todos os blocos
aditivos até `if ($SelfTest)`, allowlist nova e parser numérico no V18. É
tecnicamente possível, mas amplia o escopo para dois verificadores protegidos e
repete o problema estrutural que consumiu a missão anterior.

**Decisão:** Opção A. A Opção B fica registrada como fallback somente se o
usuário exigir explicitamente a integração na suíte de 116; nesse caso, a
autorização precisa cobrir `scripts/test.ps1`, `scripts/verify-context-bytes.ps1`
e `scripts/verify-corpus-bytes.ps1`.

### 3.3 Consequência para a regressão

A regressão M1-M8 continua sendo provada por:

1. `scripts/test.ps1` 116/116 (o verificador novo executa uma vez em E6/E7);
2. `scripts/verify-corpus-bytes.ps1` 18/18 (executado uma vez em E7; ele já
   executa a suíte, o autoteste e os verificadores M1-M7 por contrato próprio);
3. hashes congelados de M1-M8 verificados pelo novo verificador.

A suíte roda duas vezes no total (uma no verificador novo, outra dentro do V18
da M8), mas o verificador completo da M8 roda uma única vez. Não há necessidade
de rodar M8 duas vezes; o custo de 1.105 s é pago uma vez.

## 4. Etapas E0-E7

| Etapa | Objetivo | Artefatos | Gate | Fallback |
| --- | --- | --- | --- | --- |
| E0 | sondar APIs, custo e limites | `temp/eval-probe.log` | G0 | reduzir casos; manter lotes de 6 |
| E1 | congelar dados e hash | `scripts/eval-datasets.ps1`, `docs/evaluation-spec.md` | G1 | corrigir literal antes de qualquer modelo |
| E2 | módulo somente leitura | `src/avaliacao.por` | G2 | dividir em funções menores |
| E3 | casos base | `build-evaluation-tests.ps1`, `eval_nao_treinado`, `eval_treinado` | G3 | congelar estado via O1 |
| E4 | baselines e controles | `eval_baselines`, `eval_controle_*`, `eval_ordem_permutacoes` | G4 | reduzir X7 a amostra de 8 contextos |
| E5 | relatório e bytes | `eval_determinismo_a/b`, `.expected` | G5 | encurtar `EX` se o buffer do interpretador limitar |
| E6 | verificador independente | `verify-evaluation-bytes.ps1`, `test-evaluation.ps1` | G6 | separar V1-V13 em dois scripts |
| E7 | execução oficial | logs, §12 deste plano, status da spec | G7 | nenhum: resultado é o medido |

### E0 - Sondas técnicas (sem arquivos versionados)

Objetivo: confirmar que as APIs existentes suportam a avaliação e medir custo.

1. **P1 - perda por lote:** chamar `ctx_perda_escalada` com `n=6` no estado não
   treinado e no canônico; confirmar `0 <= S <= 1.926.758.400`.
2. **P2 - acertos:** chamar `ctx_acertos` com `n=6` seis vezes para cobrir 32
   predições; conferir a soma.
3. **P3 - treino:** medir `ctx_inicializar` + `corp_treinar` com os 10 exemplos
   e `E=4`; conferir o histórico `8404936 1341188 651091 509249 436118` e o
   estado de 325 valores.
4. **P4 - não mutação:** imprimir o estado completo antes/depois de
   `ctx_argmax`, `ctx_acertos`, `ctx_perda_escalada` e `ctx_z256`; comparar.
5. **P5 - palavras:** chamar `ctx_escrever_palavra` para `0..24`; confirmar
   `UNK` e as 24 palavras.
6. **P6 - custo:** medir o tempo de um relatório completo de C e o tamanho em
   bytes; estimar o total dos 9 casos.
7. **P7 - normalização:** confirmar o `0x0C` inicial e o epílogo exato do
   interpretador em uma execução de avaliação.

Gate **G0**: todos os pontos acima confirmados; `S` dentro da faixa; nenhuma
mutação; custo total estimado abaixo de 5 minutos para o runner novo.

Fallback: se `ctx_acertos` ou `ctx_perda_escalada` não aceitarem `n=6` em
alguma combinação, reduzir para `n=1..6` e registrar; se o relatório completo
for grande demais, imprimir `EX` só para C e resumos para A/B/D.

### E1 - Congelar dados

Criar `scripts/eval-datasets.ps1` com os literais do Apêndice A da spec e uma
função que devolve a serialização canônica. O script deve:

- validar 50 linhas, 724 bytes, LF, sem CR, sem BOM;
- calcular o SHA-256 e comparar com `e8aa354e...`;
- recalcular as janelas do corpus e comparar com `TRAIN`;
- validar L2-L8 da spec;
- falhar com código != 0 se qualquer regra violar.

Gate **G1**: hash idêntico, 0 vazamentos, contagens 10/10/5/8/10 e B 10+10.

Fallback: se o hash não bater, corrigir o literal antes de qualquer execução do
modelo; não “atualizar” o hash para acomodar um literal alterado sem registrar
`EVAL-V2`.

### E2 - Módulo `src/avaliacao.por`

Implementar as funções de §7.2 da spec, sem chamar funções mutantes. Testes
mínimos em `temp/eval-probe`:

- `aval_div_piso` e `aval_milesimos` contra O1/O2 em valores de borda
  (`S=0`, `S=1`, `S=321.126.400` com `n=1`, `S=1.926.758.400` com `n=6`);
- `aval_checksum` estável;
- `aval_ids_validos` rejeitando `n=0`, `n=65`, ID 25 e ID -1;
- `aval_avaliar` com 1, 6, 7 e 32 exemplos, conferindo a divisão em lotes;
- relatório de um conjunto sintético de 2 exemplos contra O3.

Gate **G2**: compila, não muta, métricas iguais a O1/O2, códigos de erro
corretos.

Fallback: se o interpretador não aceitar arrays de 64 posições ou parâmetros
`cadeia` no relatório, reduzir para 32 posições e gerar um caso por conjunto.

### E3 - Casos base

Criar `scripts/eval-oracle.ps1` (O1/O2) e `scripts/build-evaluation-tests.ps1`.
Gerar:

- `eval_nao_treinado`: estado inicial, A/B/C/D, relatório completo;
- `eval_treinado`: estado canônico, A/B/C/D, relatório completo, confusão.

O builder calcula `.expected` com O1. O runner executa o `.por`, normaliza a
saída e compara bytes.

Gate **G3**: A = 10/10; estado canônico igual ao da M8 (histórico e hash);
C medido; O1 = O2 = `.por` em `S_b`, `BP` e `m_b`.

Fallback: se o estado canônico divergir, parar e investigar M8 antes de
continuar; não ajustar a avaliação para “fazer passar”.

### E4 - Baselines e controles

Casos:

- `eval_baselines`: lookup e majoritário, sem `w16`/`b16`;
- `eval_controle_rotulo`: treino com `pi(t) = (t % 24) + 1`, avaliar A e C;
- `eval_controle_ordem`: treino com os 10 exemplos invertidos, avaliar A e C;
- `eval_ordem_permutacoes`: estado canônico, 6 permutações de cada contexto de
  C, contar mudanças de argmax;
- `eval_limites`: funções auxiliares e erros.

Gate **G4**: baselines exatos; controle negativo com A >= 8/10 e C < 15/32;
controle de ordem sem erro; permutações relatadas.

Fallback: se o controle negativo passar de 15/32, o experimento é inválido;
parar e investigar vazamento antes de qualquer conclusão. Se O1 não reproduzir
o controle, corrigir O1, não o resultado.

### E5 - Relatório e contrato de bytes

Implementar a gramática de §7.5, gerar `.expected`, comparar bytes, rodar
`eval_determinismo_a` e `_b` em processos separados.

Gate **G5**: A = B byte a byte; ASCII; LF; um LF final; sem CR, BOM, `real`,
`NaN` ou `-0`; soma dos `ok` igual a `acertos`.

Fallback: se o interpretador inserir espaços ou quebras extras, documentar a
normalização exata (além do `0x0C` e do epílogo) e aplicá-la no runner; não
alterar o `.expected` para “casar” com uma saída variável.

### E6 - Verificador independente

Criar `scripts/verify-evaluation-bytes.ps1` com as verificações V1-V13:

| ID | Verificação |
| --- | --- |
| V1 | hashes congelados de M1-M8; `test.ps1` 116 intacto; escopo do `git status` |
| V2 | serialização 724 bytes / 50 linhas / SHA `e8aa354e...` |
| V3 | contagens e composição de A/B/C/D |
| V4 | 0 vazamentos; B 10+10; D 10/10; C 32/32 |
| V5 | IDs em `1..24`; nenhum `0`; nenhuma sequência do corpus |
| V6 | estado canônico reproduzido por O1; hash do estado |
| V7 | métricas do não treinado iguais a O1/O2 |
| V8 | métricas do canônico iguais a O1/O2 (A, B, C, D, perda, margem, confusão) |
| V9 | baselines exatos |
| V10 | não mutação (estado completo antes/depois) |
| V11 | determinismo A/B; gramática; ASCII/LF |
| V12 | suíte 116/116; autoteste 0/1 |
| V13 | casos extremos e códigos de erro |

Gate **G6**: todas as verificações passam, exit 0; nenhum arquivo M1-M8
alterado.

Fallback: se V1 for caro por executar a suíte, separar V12 em um passo opcional
e registrar o log da suíte já existente.

### E7 - Execução oficial

Executar, em sequência, sem paralelismo:

1. `scripts/verify-evaluation-bytes.ps1` (runner novo + oráculos + suíte 116 +
   M1-M8 hashes);
2. `scripts/verify-corpus-bytes.ps1` uma única vez (regressão M1-M8 oficial,
   18/18 esperado).

Registrar tempos, exit codes, logs e o veredito de §6.4 da spec. Atualizar
`docs/evaluation-plan.md` §12 com a tabela de evidências e
`docs/evaluation-spec.md` apenas no status/resultado.

Gate **G7**: AC1-AC12 da spec satisfeitos; veredito emitido com os números
reais, inclusive se for `SEM_EVIDENCIA`.

## 5. Gates e fallbacks consolidados

| Gate | Critério | Se falhar |
| --- | --- | --- |
| G0 | APIs, faixa, não mutação, custo | reduzir lotes/casos; registrar |
| G1 | hash e 0 vazamentos | corrigir literal; nova versão se necessário |
| G2 | módulo puro e métricas | dividir funções; não tocar M7/M8 |
| G3 | estado canônico e A=10/10 | parar e investigar M8 |
| G4 | baselines e controles | investigar vazamento; invalidar se necessário |
| G5 | bytes determinísticos | documentar normalização; não relaxar `.expected` |
| G6 | verificador completo | separar verificações caras |
| G7 | AC1-AC12 | não publicar veredito; relatar bloqueio |

Nenhum gate pode ser “passado” alterando o holdout, o limiar, o baseline ou o
resultado esperado. A única correção permitida é corrigir um bug de
implementação e reexecutar.

## 6. Custo de execução

| Execução | Custo medido/estimado | Quando |
| --- | --- | --- |
| Sondas E0 | segundos a poucos minutos | uma vez |
| Runner de avaliação (9 casos) | estimado < 5 min; medir em E0 | E3-E6, repetido |
| Suíte 116 | já medida; uma execução no verificador novo e outra dentro do V18 da M8 | duas vezes no total |
| M7 16/16 | 635 s (medido na missão anterior) | não executar separadamente; o V18 da M8 o executa |
| M8 18/18 | 1.105 s (medido) | uma vez em E7 |

Não executar M8 e M7 em paralelo. Não executar o verificador M8 em cada etapa;
ele é o gate final. O runner novo é barato e pode ser repetido durante E2-E6.

## 7. Arquivos e autorização

### 7.1 Esta fase (autorizado)

- `docs/evaluation-spec.md` (novo)
- `docs/evaluation-plan.md` (novo)

### 7.2 Fase de implementação (será solicitada)

| Arquivo | Ação |
| --- | --- |
| `src/avaliacao.por` | novo |
| `scripts/eval-datasets.ps1` | novo |
| `scripts/eval-oracle.ps1` | novo |
| `scripts/build-evaluation-tests.ps1` | novo |
| `scripts/test-evaluation.ps1` | novo |
| `scripts/verify-evaluation-bytes.ps1` | novo |
| `docs/evaluation-spec.md` | status/resultado |
| `docs/evaluation-plan.md` | §12/evidências |
| `temp/evaluation-tests/*` | gerado, ignorado |

Nenhum desses arquivos será criado sem aprovação explícita.

### 7.3 Explicitamente fora de escopo

`src/contexto.por`, `src/corpus.por`, `corpus/`, `scripts/test.ps1`,
`scripts/verify-context-bytes.ps1`, `scripts/verify-corpus-bytes.ps1`,
`scripts/build-*.ps1` de M1-M8, `README.md`, `AGENTS.md`, `tests/`, commit,
push, tag e branch.

## 8. Ordem de execução dos testes

1. `eval_separacao` (PowerShell, sem `.por`) - barato, falha cedo.
2. `eval_limites` (`.por`) - valida helpers.
3. `eval_nao_treinado` (`.por`) - fixa o baseline inferior.
4. `eval_treinado` (`.por`) - resultado primário.
5. `eval_baselines` (`.por`) - confere os números pré-registrados.
6. `eval_controle_rotulo` (`.por`) - controle negativo.
7. `eval_controle_ordem` (`.por`) - sensibilidade à ordem.
8. `eval_ordem_permutacoes` (`.por`) - sensibilidade na inferência.
9. `eval_determinismo_a/b` (`.por`) - bytes.
10. `eval_regressao` (PowerShell) - suíte 116 + hashes.

Se `eval_separacao` falhar, nenhum caso `.por` deve rodar.

## 9. Tabela de evidências (medido em E7)

Medição oficial em 2026-10-30, árvore sem commit (`HEAD` inalterado).

| Item | Valor medido | Log |
| --- | --- | --- |
| Data/hora | 2026-10-30, horário local (UTC-03:00) | `temp/eval-run.log` |
| HEAD | `6f6ec0ea3016579844c5467165892df79c35d951` | `git rev-parse HEAD` |
| Hash do holdout | `e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10` (724 bytes, 50 linhas) | E1 / V2 |
| Estado canônico (SHA-256) | `efa3f1d397a7fa37aaa83fb1c664fc054f1844309a5a7220f4ef7c3de630bb6d` | E3 / V6 |
| A (canônico) | 10/10, `BP=10000`, perda 332 | E3 / V8 |
| B_VISTO / B_INEDITO | 10/10 (`BP=10000`) / 0/10 (`BP=0`); B total 10/20 (`BP=5000`, perda 1183) | E3 / V8 |
| C (canônico) | 4/32, `BP=1250`, perda 1530 | E3 / V8 |
| C_SEM_PARE | 1/24, `BP=417` | E3 / V8 |
| D (canônico) | 0/10, `BP=0`, perda 1028; aderência às predições de A 10/10 | E3 / V8 |
| Não treinado em C | 3/32, `BP=938`, perda 3555 | E3 / V7 |
| Memorização em C | 8/32, `BP=2500` (pré-registrado e confirmado) | E4 / V9 |
| Majoritário em C | 8/32, `BP=2500` (pré-registrado e confirmado) | E4 / V9 |
| Rótulo permutado em C | 2/32, `BP=625`; A 9/10 (controle satisfeito) | E4 / V8 |
| Ordem inversa em C | 3/32, `BP=938`; A 8/10 | E4 / V8 |
| Permutações de contexto | 32/32 contextos mudam ao menos uma vez; 106 mudanças em 192 predições | E4 / V8 |
| Determinismo A/B | idênticos byte a byte, SHA-256 `f36fb8398e488d3243e8f23d26ffb99b3678054357538c6cb5cc338596475091` | E5 / V11 |
| Suíte 116/116 | 116 passou, 0 falhou, exit 0; autoteste 0/1, exit 1 (esperado) | E6/E7 / V12 |
| M7 (`verify-context-bytes.ps1`) | 16/16, exit 0, 462 s (allowlist corrigida) | E7 / `temp/m8-verify-verify-context-bytes.ps1.log` |
| M8 (`verify-corpus-bytes.ps1`) | 18/18, exit 0, 1169 s (allowlist e pin corrigidos) | E7 / `temp/m8-verify-corpus-bytes.log` |
| M9 (`verify-evaluation-bytes.ps1`) | 13/13, exit 0, 303 s | `temp/eval-verify.log` |
| Runner M9 (`test-evaluation.ps1`) | 11/11, exit 0, 24 s | `temp/eval-run.log` |
| Veredito (§6.4) | `SEM_EVIDENCIA` com `QUALIFICACAO=FRACA` | E7 |
| Veredito técnico | `PRONTA`: AC1-AC12 verificados após a correção de escopo | E7 |

## 10. Riscos e mitigações

| Risco | Impacto | Mitigação |
| --- | --- | --- |
| Integrar em `test.ps1` quebra M8 V1/V18 | alto | Opção A; não editar `test.ps1` |
| Holdout pós-hoc | médio | hash antes de qualquer modelo; relatar todos os conjuntos |
| C difícil demais (sem sufixo de 2 tokens) | médio | declarar a limitação; não ajustar o teste |
| 32 predições | médio | leitura descritiva; sem teste de hipótese |
| Overflow de `S` | alto | lotes de 6; O2 com `BigInteger` |
| `milesimos` com divisão longa errada | médio | O2 + O3 + bordas |
| Mutação acidental por `ctx_executar` | alto | módulo sem chamadas mutantes; estado antes/depois |
| Interpretador com epílogo/form feed | baixo | normalização exata já usada na M8 |
| `.por` sem checagem de limites de array | alto | constantes fixas + validadores |
| Controle negativo passar | alto | invalidar e investigar vazamento |
| Resultado negativo ser “corrigido” | alto | pré-registro; §6.4; relatar como `SEM_EVIDENCIA` |
| Custo do M8 (18 min) | baixo | executar uma vez em E7 |

## 11. Critérios de conclusão da fase de planejamento (histórico)

Aplicáveis à fase de planejamento (concluída antes de E0):

- `docs/evaluation-spec.md` e `docs/evaluation-plan.md` existem.
- UTF-8 sem BOM, LF, um LF final, 0 CR.
- `git status --short` mostra apenas esses dois arquivos não rastreados.
- Nenhum código, corpus, script, teste, README ou AGENTS.md alterado.
- Nenhum commit, push, tag ou branch.
- Nenhum modelo executado sobre o holdout.

Na fase de implementação (E0-E7), `git status --short` passou a mostrar os 8
arquivos novos listados em `docs/evaluation-spec.md` §11, e o holdout foi usado
apenas na avaliação oficial, com o hash de §4.9 verificado antes e depois.

## 12. Resultado da implementação (E7)

Execução oficial em 2026-10-30, sem commit. Todos os números abaixo foram
medidos por `scripts/test-evaluation.ps1` e auditados por
`scripts/verify-evaluation-bytes.ps1`; `.expected` vem do oráculo O1, nunca da
saída real.

### 12.1 Estado e dados

- Estado canônico de M8 reproduzido: `TREINO 10`, hash do bloco `W16`/`B16`
  `efa3f1d397a7fa37aaa83fb1c664fc054f1844309a5a7220f4ef7c3de630bb6d`.
- Holdout intocado: 50 linhas, 724 bytes, SHA-256
  `e8aa354ecfad407e745d2be7babe5682c937519e3eec7f238b59a2dab85a5f10`, 0
  vazamentos (nenhuma sequência de B/C é linha do corpus).
- Contagens mantidas: A=10, B=10+10, C=32, C_SEM_PARE=24, D=10.
- Nenhuma mutação: estado completo idêntico antes/depois nos 5 casos
  parametrizados; `CHECK ... MUTACAO OK` em todos.

### 12.2 Resultado canônico (X1)

| Conjunto | N | Acertos | `BP` | Perda |
| --- | --- | --- | --- | --- |
| A (visto) | 10 | 10 | 10000 | 332 |
| B (total) | 20 | 10 | 5000 | 1183 |
| B_VISTO | 10 | 10 | 10000 | - |
| B_INEDITO | 10 | 0 | 0 | - |
| C (primário) | 32 | 4 | 1250 | 1530 |
| C_SEM_PARE | 24 | 1 | 417 | - |
| D (alvo trocado) | 10 | 0 | 0 | 1028 |

D tem aderência 10/10 às predições de A: com A=10/10, trocar o alvo não muda a
predição, como previsto.

### 12.3 Comparações contra baselines

| Comparação | `BP` | Delta |
| --- | --- | --- |
| C canônico vs memorização (8/32 = 2500) | 1250 vs 2500 | -1250 |
| C canônico vs não treinado (3/32 = 938) | 1250 vs 938 | +312 |
| C canônico vs majoritário (8/32 = 2500) | 1250 vs 2500 | -1250 |

O critério primário exige `BP_C - max(BP_M, BP_U) >= 2000` e `A_C >= 15`. O
delta é -1250 e `A_C = 4`, então **§6.2 não é satisfeito**.

### 12.4 Baselines pré-registrados

| Baseline | A | B | B_VISTO | B_INEDITO | C | C_SEM_PARE | D |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Memorização | 10/10 | 10/20 | 10/10 | 0/10 | 8/32 | 0/24 | 0/10 |
| Majoritário | 5/10 | 5/20 | 5/10 | 0/10 | 8/32 | 0/24 | 1/10 |

Os valores coincidem exatamente com os pré-registrados.

### 12.5 Controles

| Controle | A | C | Esperado | Situação |
| --- | --- | --- | --- | --- |
| Rótulo permutado (X4) | 9/10 | 2/32 | A >= 8/10 e C < 15/32 | satisfeito |
| Ordem inversa (X5) | 8/10 | 3/32 | A >= 8/10; C sem limiar | satisfeito |
| Permutações de contexto (X7) | - | 32/32 contextos mudam; 106 mudanças em 192 | sem limiar | registrado |

O controle negativo não passou: o modelo não transfere rótulos arbitrários para
C, o que é consistente com a ausência de generalização e descarta vazamento
grosseiro de rótulo.

### 12.6 Determinismo e regressão

- `eval_determinismo_a` e `eval_determinismo_b`: bytes idênticos, SHA-256
  `f36fb8398e488d3243e8f23d26ffb99b3678054357538c6cb5cc338596475091`.
- Relatório ASCII/LF, sem `real`; stderr vazio.
- `scripts/test.ps1`: 116 passou, 0 falhou, exit 0; autoteste 0/1, exit 1
  (esperado), sem edição do arquivo.
- `verify-context-bytes.ps1` (M7): 16/16, exit 0, 462 s.
- `verify-corpus-bytes.ps1` (M8): 18/18, exit 0, 1169 s.
- `verify-evaluation-bytes.ps1` (M9): 13/13, exit 0, 303 s; runner M9 11/11,
  exit 0, 24 s. Hashes congelados, pin do verificador M7 e suíte intactos.
- A correção de compatibilidade que permitiu 16/16 e 18/18 está descrita em
  §14; ela toca apenas regras de escopo e o pin criptográfico do M7.

### 12.7 Veredito

**`SEM_EVIDENCIA`** (`QUALIFICACAO=FRACA`; `A_C_SEM_PARE = 1/24`).

O experimento é válido: holdout intacto, sem vazamento, sem mutação,
determinístico, controles dentro do esperado e regressão verde. Ainda assim, o
modelo memoriza A (10/10) e B_VISTO (10/10), mas acerta apenas 4/32 em C, abaixo
do baseline de memorização (8/32) e muito abaixo do limiar de 15/32. O 1/24 em
`C_SEM_PARE` mostra que o acerto não vem de contexto inédito não terminal. Não
há evidência de generalização para contextos disjuntos com o estado congelado da
M8; nenhum dado, limiar ou baseline foi alterado para mudar esse resultado.

### 12.8 Veredito técnico da entrega

**`PRONTA`**: E0-E7 executados e AC1-AC12 verificados com evidência. Os 9 casos
`.por` batem byte a byte com O1; M7 16/16, M8 18/18, M9 13/13, runner M9 11/11,
suíte 116/116, todos exit 0. A causa da falha anterior era apenas a allowlist de
`git status` de M7/M8, corrigida em §14 sem alterar nenhuma verificação
funcional, hash de módulo ou resultado esperado. O resultado científico negativo
(`SEM_EVIDENCIA`) é o resultado do experimento, não falha de implementação.

## 13. Pedido de aprovação

O planejamento está completo. A próxima ação autorizada deve ser apenas a
implementação de E0-E7 com os arquivos de §7.2, ou uma correção deste plano.
Sem aprovação explícita, o trabalho para aqui.

## 14. Correção de compatibilidade das allowlists (M7/M8)

### 14.1 Causa

As verificações V1 de `scripts/verify-context-bytes.ps1` (M7) e
`scripts/verify-corpus-bytes.ps1` (M8) congelam a lista literal de linhas
aceitas de `git status --short`. Essa lista foi escrita para o estado de trabalho
das missões M7/M8 e, por isso, rejeitava os 8 arquivos novos do M9 como "fora do
escopo", mesmo eles sendo autorizados. Não havia falha de hash, de bytes, de
aritmética ou de comportamento: apenas escopo.

### 14.2 Patch aplicado

Ampliação de escopo autorizada exclusivamente para os dois verificadores:

- `scripts/verify-context-bytes.ps1`: acrescentados 8 caminhos M9 e a linha
  `" M scripts/verify-corpus-bytes.ps1"` à allowlist de V1. Nenhuma outra regra
  alterada.
- `scripts/verify-corpus-bytes.ps1`: mesmos 9 caminhos na allowlist de V1 e pin
  de `scripts/verify-context-bytes.ps1` atualizado de
  `463fe02275926f9942f9b61c506b0ad26450f78c` para
  `200b911fd3e15d43df28b1ca1942dc318359bbd7`.
- `scripts/verify-evaluation-bytes.ps1` (arquivo M9 já autorizado): pin do
  verificador M7 atualizado para o mesmo hash e os 2 verificadores acrescentados
  à lista de caminhos permitidos de V1.

Não foram alterados `scripts/test.ps1`, módulos M1-M8, corpus, README,
`AGENTS.md`, verificações matemáticas, hashes de módulos, contagens ou
resultados esperados. As allowlists continuam literais, sem curingas.

### 14.3 Prova de que o patch é mínimo

Reconstruindo cada verificador a partir do estado atual, removendo exatamente as
9 linhas de escopo acrescentadas e revertendo o pin, o blob SHA-1 volta ao valor
pré-patch:

| Arquivo | Blob reconstruído | Blob pré-patch |
| --- | --- | --- |
| `verify-context-bytes.ps1` | `463fe02275926f9942f9b61c506b0ad26450f78c` | `463fe02275926f9942f9b61c506b0ad26450f78c` |
| `verify-corpus-bytes.ps1` | `c3ed149c0f51bb89c3dc27cf82efd3ec4fe82fe7` | `c3ed149c0f51bb89c3dc27cf82efd3ec4fe82fe7` |

### 14.4 Testes direcionados (antes da regressão)

- Sintaxe PowerShell dos 3 verificadores: OK.
- Allowlist M7 e M8: 17 entradas cada, 0 linhas reais fora da lista, 0 curingas.
- Rejeição preservada: `?? hack.ps1`, ` M src/contexto.por` e `?? README.md`
  continuam fora da lista.
- Pins: 15 (M7), 18 (M8) e 18 (M9) hashes conferidos, 0 divergências.
- Allowlist M9 por caminho: 10 entradas (8 M9 + 2 verificadores), 0 fora.

### 14.5 Resultados oficiais após a correção

| Etapa | Resultado | Exit | Tempo |
| --- | --- | --- | --- |
| `verify-context-bytes.ps1` | 16/16 | 0 | 462 s |
| `verify-corpus-bytes.ps1` | 18/18 | 0 | 1169 s |
| `verify-evaluation-bytes.ps1` | 13/13 | 0 | 303 s |
| `test-evaluation.ps1` | 11/11 | 0 | 24 s |

Holdout (724 bytes, 50 linhas, `e8aa354e...`), corpus M8
(`d6eb8a78...`), estado canônico (`efa3f1d3...`), determinismo A/B
(`f36fb839...`) e o resultado `SEM_EVIDENCIA`/`FRACA` permanecem idênticos.

### 14.6 Escopo final

10 arquivos: os 8 do M9 (`src/avaliacao.por`, `scripts/eval-datasets.ps1`,
`scripts/eval-oracle.ps1`, `scripts/build-evaluation-tests.ps1`,
`scripts/test-evaluation.ps1`, `scripts/verify-evaluation-bytes.ps1`,
`docs/evaluation-spec.md`, `docs/evaluation-plan.md`) e os 2 verificadores
autorizados (`scripts/verify-context-bytes.ps1`, `scripts/verify-corpus-bytes.ps1`).
Nenhum commit, push, tag ou branch.
