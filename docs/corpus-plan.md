# Plano de execução — Treinamento a partir de corpus textual (M8)

- **Status:** planejamento apenas. Nenhum arquivo de código, corpus, script ou
  teste foi criado ou alterado. Nenhum commit ou push será feito nesta fase.
- **Especificação:** `docs/corpus-spec.md` v0.1.0.
- **Missões anteriores:** M1 (`docs/tokenizer-spec.md` v0.2.1), M3
  (`docs/embeddings-spec.md` v0.1.1), M4 (`docs/network-spec.md` v1.0.0), M5
  (`docs/training-spec.md` v1.0.0), M6 (`docs/generation-spec.md` v1.0.0), M7
  (`docs/context-spec.md` v1.0.0).
- **Fora de escopo:** ampliar o vocabulário, alterar `src/contexto.por`,
  embeddings treináveis, softmax, amostragem, atenção, Transformer, leitura de
  arquivo em tempo de execução pelo `.por`, generalização em texto natural,
  commit, push, tag e operação remota.
- **Entrega futura:** `corpus/m8-corpus-v1.txt`, `src/corpus.por`,
  `scripts/build-corpus-tests.ps1`, `scripts/verify-corpus-bytes.ps1` e o bloco
  aditivo de `scripts/test.ps1`, além dos dois documentos desta fase.

## 1. Estado de partida e pré-voo

Verificado por comando nesta missão, antes de escrever este plano:

| Item | Estado medido |
| --- | --- |
| Branch | `main` |
| `HEAD` | `54ed948d91c1ff19c14a23f98011c70ed0bce24a` |
| `origin/main` | mesmo commit; 0 ahead / 0 behind |
| Árvore de trabalho | limpa antes dos docs; depois, apenas `docs/corpus-spec.md` e `docs/corpus-plan.md` não rastreados |
| Suíte de partida | `scripts/test.ps1` = **100 PASS / 0 FAIL**, exit `0` (`temp/m8-baseline-suite.log`) |
| Composição da suíte | 5 literais + 20 M1 + 19 M3 + 14 M4 + 12 M5 + 14 M6 + 16 M7 = 100 |
| M1 bytes | 21/21, exit `0` (`temp/m8-verify-bytes.log`) |
| M3 bytes | 19/19, exit `0` (`temp/m8-verify-embedding-bytes.log`) |
| M4 bytes | 22/22, exit `0` (`temp/m8-verify-network-bytes.log`) |
| M5 bytes | 23/23, exit `0` (`temp/m8-verify-training-bytes.log`) |
| M6 bytes | 13/13, exit `0` (`temp/m8-verify-generation-bytes.log`) |
| M7 bytes | 16/16, exit `0` (`temp/m8-verify-context-bytes.log`) |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |
| Custo por caso | ~1,3–1,5 s; suíte de 100 casos ~250 s, incluindo builders |

O baseline foi medido nesta missão. Nenhum valor foi inferido de memória.

### 1.1 Arquivos congelados

Hashes `git hash-object` em `HEAD`, que **não podem** mudar na implementação:

```
src/tokenizador.por                    6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f
src/embeddings.por                     6f06aa820d163d3c1636383803b86105bf54cd85
src/rede.por                           fa9367a79bd2aefc373d30a94cfca2b7c86d9958
src/treino.por                         f5121423dd0aac6469b59b24b13d8a85b2c0d64d
src/gerador.por                        532e60cc52cef03fbd60c2a9d2b530472c73ded1
src/contexto.por                       9da552861c58d145a1d1c52442e0c27a4c42ce2e
scripts/build-tests.ps1                1cfb01202586a83c4d7ec08ff738a8e90fb19044
scripts/verify-bytes.ps1               851afbbad494778f019bf2ce70e82b0b575ab443
scripts/build-embedding-tests.ps1      94d1a3819b76b4d614f4422bf00b0cd2c008daaf
scripts/verify-embedding-bytes.ps1     4f3aa68e499a9dc3289d22ebae5b8d1c18086651
scripts/build-network-tests.ps1        998e91b2896e9ec40bc1814990a0a53ae740fb3e
scripts/verify-network-bytes.ps1       1f46800852fed34d840206ca97bc84badd109b31
scripts/build-training-tests.ps1       c587e161e19d353af23f0cb9d055119b288c2675
scripts/verify-training-bytes.ps1      f59fee82d337e13f619360e63d6e928aef8e0f6b
scripts/build-generation-tests.ps1     e712064d631e6fbf2711943ec65da6812223427f
scripts/verify-generation-bytes.ps1    e1807a8d6469ecaba0d2ad724c9e58b6a2689b3a
scripts/build-context-tests.ps1        e9dd6d1ba2b54eb4caade4391a3da12cb555f29d
scripts/verify-context-bytes.ps1       6ea2bf3b79b275d1cc33a69876615bbcc0cfc260
```

`scripts/test.ps1` em `HEAD` tem hash
`b5f2f03255de984807f3d4d1c4d46d33d238958c`, **BOM UTF-8**, **LF**, 14.713
bytes e último byte `0x7D` (`}`). Ele muda por desenho: apenas um bloco aditivo
de 16 casos, dentro de `if (-not $SelfTest)`. O BOM, o LF e o restante do
arquivo devem permanecer idênticos; o diff é conferido em E7.

## 2. Sondas e etapas E0–E7

### E0 — Sondas técnicas e congelamento do contrato

**Objetivo:** provar que a linguagem e a composição suportam o desenho antes de
escrever qualquer linha de produção.

Sondas obrigatórias, em `temp/m8-e0/` (descartável, ignorado pelo Git):

1. `cadeia linhas[6]` e passagem de arrays de `cadeia` para função.
2. Visibilidade de `tx` e de `id_do_campo` em um fragmento concatenado depois de
   `src/tokenizador.por`.
3. `corp_tokenizar` mínimo sobre as 5 linhas canônicas, comparado com a saída de
   `tokenizar` da M1.
4. `ctx_executar` com `n=6`, `epocas=1`, e comparação com uma passagem global
   equivalente de 6 exemplos.
5. `ctx_perda_escalada` em lotes 6+4 sobre os 10 exemplos canônicos,
   comparada com `S0=8.404.936`.
6. `ctx_gerar` com prefixo de 3 tokens, `maximo=64`, e parada em `pare`.
7. Escrita e leitura de literais com `\t`, `\r` e `\n` para os testes de
   formato.
8. Tempo de uma execução de 10 exemplos × 4 épocas, para registrar custo.

**Gate G0:** todas as sondas produzem a saída esperada e o contrato de
`docs/corpus-spec.md` congela em `v0.1.0`. Nenhum gate dispara.

**Fallbacks:**

- Se `cadeia linhas[6]` não for suportado: representar o corpus como uma única
  `cadeia` com LF e dividir em tempo de execução. O contrato de bytes e a ordem
  permanecem; o builder passa a injetar uma única literal.
- Se `id_do_campo` não estiver visível: duplicar a tabela de 24 palavras em
  `src/corpus.por` e manter `corp_composicao` comparando as 5 sequências com a
  M1. A duplicação é registrada como exceção aprovada.
- Se a ordem de lotes não for equivalente: **parar**. Não alterar
  `src/contexto.por` nem a prova da M7 sem aprovação.
- Se `\t`/`\r` não puderem ser representados em literal: testar apenas espaço
  duplo, espaço inicial/final e comprimento; a verificação de CR/BOM/TAB fica
  no verificador de bytes.

### E1 — Corpus, bytes e tokenização

**Objetivo:** criar o corpus v1 e o tokenizador estrito.

Atividades:

1. Criar `corpus/m8-corpus-v1.txt` com exatamente os 165 bytes de §3.1 da spec.
2. Implementar `corp_tokenizar` com formato estrito, `id_do_campo` e os códigos
   2..7.
3. Criar `scripts/verify-corpus-bytes.ps1` com as 18 verificações de bytes,
   hash, linhas, tokens, vocabulário, arquivos congelados e escopo.
4. Adicionar os casos `corp_integridade`, `corp_tokenizacao`, `corp_unk` e
   `corp_invalido` ao builder.

**Gate G1:** bytes, SHA-256, 5 linhas, 25 tokens; 5 sequências de IDs canônicas;
UNK rejeitado com linha/token; formatos inválidos com códigos e precedência
corretos; nenhum buffer alterado em erro.

**Fallback:** qualquer divergência de byte é correção do corpus, nunca do
esperado. Se a tokenização não puder reutilizar `id_do_campo`, aplicar o
fallback de E0.

### E2 — Extração, fronteiras, dedup e capacidade

**Objetivo:** transformar IDs em exemplos supervisionados sem atravessar linhas.

Atividades:

1. Implementar `corp_extrair` com staging local e cópia só no sucesso.
2. Implementar as comparações de duplicidade e conflito.
3. Adicionar `corp_janelas`, `corp_fronteiras`, `corp_duplicados` e
   `corp_capacidade`.

**Gate G2:** 10 exemplos de §5.2 na ordem canônica; nenhuma janela entre linhas;
`Σ(L−3)`; códigos 9/10; N=30 com 5 lotes de 6; 7 linhas e 9 tokens rejeitados.

**Fallback:** se `N=30` não couber com segurança, reduzir
`CORP_MAX_EXEMPLOS` para 12 e registrar a mudança; o corpus canônico (N=10) não
é afetado. Não reduzir abaixo de 10.

### E3 — Lotes, perda total e treino

**Objetivo:** treinar com `N > 6` sem duplicar o laço da M7.

Atividades:

1. Implementar `corp_perda_total` com lotes e guarda de `2.000.000.000`.
2. Implementar `corp_treinar` com buffers de 18/6 e `ctx_executar(..., 1, ...)`.
3. Adicionar `corp_lotes`, comparando N=6 direto com `ctx_executar` e N=10 6+4
   com o oráculo.
4. Testar os códigos 11..16 e a pureza em erro de validação.

**Gate G3:** `S0=8.404.936`; `S4=436.118`; lotes 6+4; N=6 idêntico ao direto;
nenhuma mutação em 11..14; 15/16 mapeados.

**Fallback:** se a equivalência falhar, **parar** e revisar a ordem ou a cópia
dos buffers. Não alterar `src/contexto.por` sem aprovação.

### E4 — Treino canônico e aprendizagem mensurável

**Objetivo:** medir a trajetória canônica e confirmar `10/10`.

Atividades:

1. Adicionar `corp_treino`.
2. Conferir `HISTORICO`, `PERDA`, `ACERTOS`, `PRED`, `MARGENS`,
   `ALTERADOS_W`, `ALTERADOS_B`, `MAXIMO16`.
3. Conferir a tabela `PARAM16` de §12.2.

**Gate G4:** histórico `8.404.936 1.341.188 651.091 509.249 436.118`;
`10/10`; margens `11 350 17 119 4 102 161 115 125 224`; 253/22; `9/6`; tabela
final idêntica.

**Fallback:** qualquer divergência **para** a implementação. Não ajustar
esperado, corpus ou `E` para fazer passar. A única correção permitida é a
implementação de acordo com a spec.

### E5 — Ordem, ablações, mudança de parâmetros e stress numérico

**Objetivo:** demonstrar sensibilidade à ordem e ausência de generalização
trivial.

Atividades:

1. Adicionar `corp_ordem` com a ordem inversa.
2. Medir as ablações “só último token” e “só antigos” no driver.
3. Medir a sonda fora do corpus (1/10).
4. Rodar o corpus canônico com `epocas=32` e conferir `max |W|`, `max |b|` e a
   ausência de estouro.
5. Rodar uma sonda de estouro controlada em `temp/` se o stress não disparar
   15; se disparar, registrar época/lote e o estado parcial.

**Gate G5:** ordem inversa com histórico
`8.404.936 1.941.318 727.037 491.309 377.464`, `8/10`, 213 diferenças;
ablações 5/10 e 8/10; sonda fora do corpus 1/10; `E=32` com `max |W|=12`,
`max |b|=10`, sem violar `|v| ≤ 16`.

**Fallback:** se a ordem inversa não for mensurável, usar uma permutação
pré-registrada (rotação de uma posição) e documentar. Não escolher a permutação
depois de ver o resultado.

### E6 — Geração, determinismo, composição e pureza

**Objetivo:** fechar o pipeline e provar que ele é determinístico e não invasivo.

Atividades:

1. Adicionar `corp_geracao` com os 5 prefixos canônicos, `PARE`, `MAXIMO` e
   `TEXTO`.
2. Adicionar `corp_determinismo_a` e `corp_determinismo_b`.
3. Adicionar `corp_composicao` com M1/M3/M7 e `corp_pureza`.
4. Conferir que `src/corpus.por` não escreve em `w16`/`b16` fora de
   `corp_treinar`.

**Gate G6:** 5 saídas canônicas; A = B byte a byte; `M1_IDS=OK`, `M3_OK=100`,
`M7_OK=10/10`; `PARAMS_INTACTOS=OK`, `IDS_INTACTOS=OK`,
`SAIDA_INTACTA=OK`.

**Fallback:** qualquer divergência de geração **para** a implementação ou para
o corpus; não alterar a saída esperada.

### E7 — Regressão completa, bytes e auditoria

**Objetivo:** provar que a M8 não quebrou M1–M7 e que o escopo foi respeitado.

Comandos:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-embedding-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-network-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-training-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-generation-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-context-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-corpus-bytes.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

**Gate G7:** suíte `116/116`, exit `0`; verificadores `21/21`, `19/19`, `22/22`,
`23/23`, `13/13`, `16/16`, `18/18`, todos exit `0`; autoteste `0/1` intencional,
exit `1`; somente arquivos autorizados; hashes congelados intactos.

**Fallback:** nenhum. Qualquer falha bloqueia a missão.

## 3. Etapas de implementação

A implementação só começa após aprovação explícita desta fase. A ordem é:

1. **E1.1** Criar `corpus/m8-corpus-v1.txt`; rodar o verificador de bytes
   (ainda não existe; conferir manualmente com `Get-FileHash` e contagem).
2. **E1.2** Criar `src/corpus.por` com `corp_tokenizar` e as constantes.
   Compilar com um driver mínimo em `temp/m8-e1/`.
3. **E1.3** Implementar `corp_extrair`; testar as 10 janelas e as fronteiras.
4. **E1.4** Implementar `corp_perda_total` e `corp_treinar`; testar 6+4.
5. **E1.5** Criar `scripts/build-corpus-tests.ps1` com o oráculo inteiro em
   PowerShell e os 16 drivers/expected.
6. **E1.6** Criar `scripts/verify-corpus-bytes.ps1`.
7. **E1.7** Adicionar o bloco aditivo de 16 casos em `scripts/test.ps1`.
8. **E1.8** Rodar a matriz E4–E7 e registrar as evidências em `temp/`.

Cada etapa termina com um teste executável. Não acumular várias etapas sem
verificação.

## 4. Arquivos autorizados

### 4.1 Nesta fase (planejamento)

| Arquivo | Ação |
| --- | --- |
| `docs/corpus-spec.md` | criar |
| `docs/corpus-plan.md` | criar |

Nenhum outro arquivo pode ser criado ou modificado. `README.md`, `AGENTS.md`,
`src/`, `scripts/`, `tests/` e o corpus permanecem intocados.

### 4.2 Na implementação futura (após aprovação)

| Arquivo | Ação | Finalidade |
| --- | --- | --- |
| `corpus/m8-corpus-v1.txt` | criar | corpus fixo de 165 bytes |
| `src/corpus.por` | criar | tokenização estrita, extração, lotes, treino |
| `scripts/build-corpus-tests.ps1` | criar | oráculo e 16 casos |
| `scripts/verify-corpus-bytes.ps1` | criar | 18 verificações de bytes/escopo |
| `scripts/test.ps1` | modificar | bloco aditivo de 16 casos |
| `docs/corpus-spec.md` | manter | contrato congelado |
| `docs/corpus-plan.md` | manter | evidências E0–E7 |

### 4.3 Explicitamente intocados

`src/tokenizador.por`, `src/embeddings.por`, `src/rede.por`, `src/treino.por`,
`src/gerador.por`, `src/contexto.por`, `docs/tokenizer-spec.md`,
`docs/embeddings-spec.md`, `docs/network-spec.md`, `docs/training-spec.md`,
`docs/generation-spec.md`, `docs/context-spec.md`, `docs/context-plan.md`,
`scripts/build-*.ps1` de M1–M7, `scripts/verify-*.ps1` de M1–M7, `README.md`,
`AGENTS.md` e `tests/`.

**Exceção autorizada:** na missão de correção, `scripts/verify-context-bytes.ps1`
foi alterado exclusivamente em V1/V16 (patch em §12.2). Os demais caminhos desta
lista permanecem intocados.

## 5. Matriz de testes

| Caso | Tipo | Cobertura | Oráculo | Chave esperada |
| --- | --- | --- | --- | --- |
| `corp_integridade` | `.por` | corpus canônico | literais da spec | 5 linhas, 25 tokens, 10 exemplos |
| `corp_tokenizacao` | `.por` | tokenização | M1 + IDs de §4.2 | 5 `IDS` canônicas |
| `corp_janelas` | `.por` | janelas K=3 | §5.2 | 10 `EXEMPLO`, `N=10` |
| `corp_fronteiras` | `.por` | fronteiras | contagem `Σ(L−3)` | nenhuma janela entre linhas |
| `corp_unk` | `.por` | UNK | §4.3 | código 3, linha/token, `IDS_INTACTOS=OK` |
| `corp_invalido` | `.por` | vazio/inválido | §11.2/§11.3 | códigos 1,2,4,5,6,7,8 |
| `corp_duplicados` | `.por` | dedup/conflito | §5.4 | códigos 9 e 10 |
| `corp_capacidade` | `.por` | N=30 | fixture de 6×8 | 30 exemplos, 5 lotes, `S0=19563100` |
| `corp_lotes` | `.por` | equivalência | M7 + §9.2 | N=6 direto; N=10 6+4 |
| `corp_treino` | `.por` | treino | §12.1/§12.2 | histórico, 10/10, margens |
| `corp_ordem` | `.por` | ordem inversa | §12.4 | histórico, 8/10, 213 |
| `corp_geracao` | `.por` | geração | §10/§12.5 | 5 prefixos, `PARE`, `MAXIMO` |
| `corp_determinismo_a` | `.por` | execução A | §12 | saída A |
| `corp_determinismo_b` | `.por` | execução B | §12 | B = A |
| `corp_composicao` | `.por` | M1/M3/M7 | M7 §11.2 | `M1_IDS=OK`, `M3_OK=100`, `M7_OK=10/10` |
| `corp_pureza` | `.por` | pureza | §11.3 | `PARAMS_INTACTOS=OK` etc. |
| `verify-corpus-bytes` | PowerShell | bytes/escopo | independente | `Checks: 18`, `Failures: 0` |

Total: **16 casos `.por`** + **1 verificador**. Suíte final: **116/116**.

### 5.1 Regressão

- Os 100 casos anteriores permanecem com os mesmos `.expected`.
- Os verificadores M1–M7 permanecem com os mesmos totais.
- O bloco aditivo de `scripts/test.ps1` não altera a ordem, o filtro ou o
  `Normalize-Output` dos casos anteriores.
- `scripts/test.ps1 -SelfTest` continua `0 PASS / 1 FAIL` intencional.

## 6. Contratos de bytes

### 6.1 Corpus

| Propriedade | Valor |
| --- | --- |
| Caminho | `corpus/m8-corpus-v1.txt` |
| Bytes | 165 |
| SHA-256 | `d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113` |
| Codificação | ASCII `0x20..0x7E` + LF |
| CR | proibido |
| BOM | proibido |
| LF final | exatamente um |
| Linhas | 5, cada uma com 5 tokens |
| Tokens | 25; nenhum UNK |

### 6.2 Documentos

`docs/corpus-spec.md` e `docs/corpus-plan.md`: UTF-8 sem BOM, LF, exatamente um
LF final. Nenhum CR.

### 6.3 Fonte e scripts

- `src/corpus.por`: ASCII puro, LF, um LF final, sem BOM.
- `scripts/build-corpus-tests.ps1` e `scripts/verify-corpus-bytes.ps1`: UTF-8
  sem BOM, LF; seguir o estilo dos scripts M7.
- `scripts/test.ps1`: preservar o BOM UTF-8, LF, o último byte `0x7D` e o
  restante do arquivo; apenas o bloco aditivo de 16 casos.
- `.por` gerados: ASCII, LF, um LF final.
- `.expected` gerados: UTF-8 sem BOM, LF, **sem** LF final (convenção M7).

### 6.4 Hashes de conferência

O verificador de corpus confere:

```
SHA-256  d6eb8a788aa6c19c602f55faf8dd6aea7de6fe3e218d6aecb99cb507ab9b6113
BYTES    165
LINHAS   5
TOKENS   25
```

E confere que os hashes de §1.1 permanecem iguais, exceto `scripts/test.ps1`,
que muda por desenho.

## 7. Gates e fallbacks consolidados

| Gate | Critério de passagem | Fallback |
| --- | --- | --- |
| G0 | sondas de linguagem/composição | representar corpus como `cadeia` única; duplicar tabela M1; **parar** se lotes não forem equivalentes |
| G1 | corpus 165 bytes/hash; tokenização canônica | corrigir o corpus, nunca o esperado |
| G2 | 10 janelas; fronteiras; dedup; N=30 | reduzir `CORP_MAX_EXEMPLOS` para 12, se necessário |
| G3 | lotes 6+4; `S0`/`S4` canônicos | **parar** e revisar ordem/cópia; não alterar M7 |
| G4 | histórico, 10/10, margens, 253/22, 9/6 | **parar**; corrigir a implementação, não o esperado |
| G5 | ordem inversa, ablações, stress | permutação pré-registrada; documentar |
| G6 | geração, determinismo, composição, pureza | **parar**; corrigir a implementação |
| G7 | 116/116 + verificadores + bytes | **parar**; bloquear a missão |

## 8. Critérios de aceitação

| AC | Comando/verificação | Resultado exigido |
| ---: | --- | --- |
| AC1 | pré-voo | `main`, `HEAD 54ed948…`, árvore limpa, 100/100 |
| AC2 | `git status --short` + bytes dos docs | nesta fase, somente os dois docs; na implementação, somente os arquivos de §4.2 deste plano; UTF-8 sem BOM, LF, um LF final |
| AC3 | `scripts/test.ps1` | `Passed: 116`, `Failed: 0`, exit `0` |
| AC4 | verificadores M1–M7 | 21/21, 19/19, 22/22, 23/23, 13/13, 16/16, exit `0` |
| AC5 | autoteste | `0 PASS / 1 FAIL`, exit `1` |
| AC6 | `scripts/verify-corpus-bytes.ps1` | `Checks: 18`, `Failures: 0`, exit `0` |
| AC7 | corpus | 165 bytes, hash, 5×5 |
| AC8 | tokenização | 5 sequências canônicas; UNK rejeitado |
| AC9 | extração | 10 exemplos; nenhuma fronteira; dedup |
| AC10 | treino | histórico, 10/10, margens |
| AC11 | parâmetros | tabela de §12.2, 253/22, `MAXIMO16=9 6` |
| AC12 | ordem | histórico inverso, 8/10, 213 diferenças |
| AC13 | geração | 5 prefixos, `PARE`/`MAXIMO` |
| AC14 | determinismo | A = B byte a byte |
| AC15 | vocabulário | 25 IDs; nenhum token novo |
| AC16 | escopo | nenhum arquivo não autorizado alterado |
| AC17 | commit/push | não executados nesta fase |

## 9. Riscos e decisões abertas

| Risco | Probabilidade | Mitigação |
| --- | --- | --- |
| `cadeia[]` não suportado | baixa | sonda E0; fallback de `cadeia` única com LF |
| `id_do_campo` não visível | baixa | concatenar tokenizador primeiro; fallback de tabela duplicada |
| Margem mínima 4/256 frágil | média | valores determinísticos; teste exato; nenhuma alegação de robustez |
| Acurácia cai em E=5 | certa | E=4 escolhido por critério objetivo; E=5 documentado |
| N=30 e faixa de `S` | baixa | lotes de 6 + guarda de 2e9; `S0=19.563.100` na fixture |
| Estouro em stress | média | código 15/16; estado parcial documentado; reinicializar |
| Ordem inversa com `S` menor | certa | demonstra que perda agregada não basta; não é falha |
| Builder e implementação divergirem | média | oráculo independente + literais de conferência; falhar, não regenerar |
| `scripts/test.ps1` com BOM | certa | preservar BOM/LF; diff aditivo conferido em E7 |
| Vocabulário expandido por engano | baixa | verificação de 25 IDs; nenhum token novo |

## 10. Registro de evidências

Preenchida durante a implementação, em `temp/` (descartável, ignorado pelo Git).
Os valores abaixo foram medidos em 2026-10-27, nesta árvore de trabalho.

| Etapa | Comando/artefato | Resultado | Status |
| --- | --- | --- | --- |
| Pré-voo | `scripts/test.ps1` → `temp/m8-baseline-suite.log` | 100/100, exit `0` | **medido** |
| Pré-voo | `verify-*.ps1` → `temp/m8-verify-*.log` | 21/19/22/23/13/16, exit `0` | **medido** |
| E0 | `temp/m8-e0/probe_a.por`, `probe_b.por` | composição, 10 exemplos, `S0=8404936`, lote 6 = global, 10/10, geração | **medido** |
| E1 | `corpus/m8-corpus-v1.txt` + `corp_integridade`/`corp_tokenizacao`/`corp_unk`/`corp_invalido` | 165 bytes, hash, 5 IDs canônicas, erros 1..8 | **medido** |
| E2 | `corp_janelas`/`corp_fronteiras`/`corp_duplicados`/`corp_capacidade` | 10 janelas, 0 fronteiras, código 9/10, N=30 | **medido** |
| E3 | `corp_lotes` | `H6_DIRETO=H6_LOTES`, `H10` canônico, `S0/S4` | **medido** |
| E4 | `corp_treino` | `8404936 1341188 651091 509249 436118`, 10/10, margens, 253/22, `9 6` | **medido** |
| E5 | `corp_ordem` + oráculo | inverso 8/10, 213 diferenças; ablações 5/10 e 8/10; sonda 1/10; `E=32` | **medido** |
| E6 | `corp_geracao`, `corp_determinismo_a/b`, `corp_composicao`, `corp_pureza` | 5 prefixos, A = B, `M1_IDS=OK`, `M3_OK=100`, `M7_OK=10`, `M8_OK=10` | **medido** |
| E7 | suíte 116/116; M1–M6 21/19/22/23/13; M7 16/16; M8 18/18 | `temp/m8-suite-116.log`, `temp/m8-verify-*.log` | **medido** |

## 11. Critérios de parada

Interromper sem descartar trabalho se qualquer condição ocorrer:

1. Baseline diferente de 100/100 ou qualquer verificador M1–M7 com regressão.
2. Corpus com bytes, hash, linhas, tokens ou encoding diferentes de §3.1.
3. Qualquer valor canônico de §12 divergir do oráculo.
4. Qualquer tentativa de ajustar o esperado, o corpus, `E` ou a ordem para
   “fazer passar”.
5. Vocabulário com mais de 25 IDs ou qualquer token novo.
6. Ordem de atualização dos lotes diferente da ordem global.
7. Estouro numérico não mapeado para 15/16, ou estado com `|v| > 16` após
   sucesso.
8. Arquivo não autorizado criado ou modificado.
9. `scripts/test.ps1` com BOM/LF alterado fora do bloco aditivo.
10. Qualquer teste novo falhando sem fallback aprovado.
11. Pedido de commit, push, tag ou operação remota nesta fase.
12. Qualquer alegação de generalização a partir dos 10 exemplos memorizados.

## 12. Próximo passo

A implementação da M8 está concluída e verificada. O gate **G7** chegou a
ficar bloqueado por uma incompatibilidade objetiva do verificador da M7, não
por divergência numérica; a correção foi autorizada e aplicada (§12.2).

### 12.1 Causa comprovada das falhas V1/V16 da M7

`scripts/verify-context-bytes.ps1` foi congelado antes da M8 e fixa dois
pressupostos globais do projeto:

- **V1** (linhas 954, 970–981 e 992–1004): exige `test.ps1` com exatamente 377
  linhas, reconstrói o hash pré-M7 removendo apenas o bloco aditivo da M7 e
  aceita somente a lista literal de seis caminhos da M7 em `git status --short`.
- **V16** (linhas 1499 e 1501): exige as strings `Passed: 100` e `Total: 100`.

Reconstruções medidas nesta árvore:

| Conteúdo | Linhas | Bytes | Hash |
| --- | ---: | ---: | --- |
| `test.ps1` atual | 402 | 15.766 | SHA-256 `faa8ae16…` |
| remoção do bloco M8 (pre-M8) | 377 | 14.713 | git `b5f2f032…` = HEAD |
| remoção dos blocos M7+M8 (pre-M7) | 353 | 13.658 | git `2a37138a…` = esperado pelo V1 |

O V1 remove apenas o bloco M7 de 24 linhas, mas o bloco M8 de 25 linhas
permanece; por isso o hash reconstruído não coincide e o `git status --short`
contém caminhos da M8, ambos fora da lista congelada. O V16 recebe `Passed:
116`/`Total: 116`. As duas falhas são estruturais (expectativas globais do
runner), não matemáticas: V2–V15 da M7 passam e nenhum valor canônico mudou. A
execução oficial que falhou antes do patch está preservada em
`temp/m8-verify-context-bytes.prefix.log` (`Checks: 16`, `Failures: 2`, exit
`1`).

### 12.2 Correção aplicada (ampliação de escopo autorizada)

A missão seguinte autorizou explicitamente a alteração **exclusiva** de
`scripts/verify-context-bytes.ps1`. O patch aplicado em V1/V16 foi:

1. **V1, contagem:** `-ne 377` → `-lt 377`.
2. **V1, reconstrução:** localiza `if ($SelfTest) {` e usa a linha `-2`
   (fechamento de `if (-not $SelfTest)`) como início da cauda; prefixo antes do
   bloco M7 + cauda devem reproduzir `2a37138a…` (353 linhas). O bloco M7
   continua coberto pela contagem de 24 linhas e pelos 4 needles.
3. **V1, escopo:** allowlist exata com os 8 caminhos autorizados (`M
   scripts/test.ps1`, `M scripts/verify-context-bytes.ps1` e os 6 artefatos da
   M8); qualquer outra linha é rejeitada.
4. **V16:** a função `Get-SuiteSummaryErrors` interpreta `Passed`, `Failed` e
   `Total` numericamente e exige `Failed = 0`, `Passed >= 100`, `Total >= 100`
   e `Total = Passed + Failed`; a execução real da suíte e do autoteste
   (exit `0`/`1`) continua obrigatória.

Consequência necessária em `scripts/verify-corpus-bytes.ps1` (artefato da M8):
o hash congelado de `verify-context-bytes.ps1` passou de `6ea2bf3b…` para o
conteúdo aprovado `463fe022…`, e a allowlist do `git status` passou a incluir
` M scripts/verify-context-bytes.ps1`. Não é mascaramento: o hash continua
pinando criptograficamente o verificador da M7, agora na versão aprovada.

Testes direcionados antes das suítes (`temp/m8-targeted-tests.log`, **30/30
PASS**, exit `0`): sintaxe dos dois scripts via parser; reconstrução real =
`2a37138a…`; bloco M7 com 24 linhas e 4 needles; adulteração fora do bloco
rejeitada; hash não cobre o interior do bloco (por isso os needles são
obrigatórios); escopo rejeitando `?? evil.ps1`, ` M src/contexto.por`,
`A novo.txt` e `?? docs/other.md`; parser V16 aceitando `116/0/116`,
`100/0/100` e `200/0/200` e rejeitando falha, resultado `< 100`, total
inconsistente e campos ausentes.

### 12.3 Resultados oficiais e situação

| Execução | Resultado | Exit | Tempo |
| --- | --- | --- | --- |
| `scripts/verify-context-bytes.ps1` | **16/16** | `0` | 635 s |
| `scripts/verify-corpus-bytes.ps1` | **18/18** | `0` | 1.105 s |

Dentro do V18: suíte **116/116**, `Failed: 0`; autoteste **0/1**, exit `1`
intencional; `verify-bytes` 21/21, `verify-embedding-bytes` 19/19,
`verify-network-bytes` 22/22, `verify-training-bytes` 23/23,
`verify-generation-bytes` 13/13 e `verify-context-bytes` 16/16, todos exit `0`.
O corpus permanece com 165 bytes e SHA-256 canônico; o V16 da M8 confirma
determinismo A = B; nenhum valor matemático foi alterado. As execuções que
falharam antes do patch estão preservadas em
`temp/m8-verify-context-bytes.prefix.log` (16 checks, 2 falhas) e
`temp/m8-verify-corpus-bytes.prefix.log` (18 checks, 1 falha).

**Veredito:** `PRONTA`. Não houve commit, tag, branch ou push; a M9 não foi
iniciada.
