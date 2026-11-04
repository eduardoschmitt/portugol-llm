# Plano de execução - Mecanismo de atenção causal mínimo (M10)

- **Status:** planejamento concluído; **nenhuma implementação iniciada**.
  Aguarda aprovação explícita.
- **Especificação:** `docs/attention-spec.md` v0.1.0 (congelada neste plano).
- **Missões anteriores:** M1-M9, com `HEAD` em
  `97086501bb0ed9e1ab806f946eb1778ab6b297fa`.
- **Entrega desta fase:** exclusivamente `docs/attention-spec.md` e
  `docs/attention-plan.md`. Nenhum código, script, corpus ou teste.
- **Fora de escopo:** Transformer completo, multi-head, softmax, `real` no
  caminho quente, alteração funcional de M1-M9, dados novos, commit, push, tag
  e branch.

## 1. Estado de partida e pré-voo

Medido por comando antes de escrever este plano:

| Item | Estado |
| --- | --- |
| Branch | `main` |
| `HEAD` | `97086501bb0ed9e1ab806f946eb1778ab6b297fa` |
| `origin/main` | mesmo commit |
| Árvore de trabalho | limpa antes dos docs; depois, apenas os dois docs novos |
| Suíte principal | **116/116**, exit 0 (`temp/eval-verify-suite.log`, `temp/m8-verify-suite.log`) |
| Runner M9 | **11/11**, exit 0 (reconfirmado nesta missão, `temp/eval-run.log`) |
| M7 | 16/16, exit 0 (evidência oficial de 2026-10-30) |
| M8 | 18/18, exit 0 (evidência oficial de 2026-10-30) |
| M9 | 13/13, exit 0 (evidência oficial de 2026-10-30) |
| Interpretador | `C:\ProgramData\UNIVALI\Portugol Studio\portugol-console.bat` |
| Corpus M8 | 165 bytes, SHA-256 `d6eb8a78...` |
| Holdout M9 | 724 bytes, 50 linhas, SHA-256 `e8aa354e...` |

A regressão completa **não** foi reexecutada nesta fase; os números acima vêm
dos logs oficiais da missão anterior, como autorizado.

### 1.1 Arquivos congelados (não podem mudar em conteúdo)

Hashes `git hash-object` em `HEAD`:

```
src/tokenizador.por                    6c7616562dd7ee4c0511f080afdb7fdc1b66bc8f
src/embeddings.por                     6f06aa820d163d3c1636383803b86105bf54cd85
src/rede.por                           fa9367a79bd2aefc373d30a94cfca2b7c86d9958
src/treino.por                         f5121423dd0aac6469b59b24b13d8a85b2c0d64d
src/gerador.por                        532e60cc52cef03fbd60c2a9d2b530472c73ded1
src/contexto.por                       9da552861c58d145a1d1c52442e0c27a4c42ce2e
src/corpus.por                         53e3c624a0f0455721aafb608c965a392cc9261d
src/avaliacao.por                      73233f06855215a2fca0b08fcd5af24fb5a47601
scripts/test.ps1                       e10771b7b89f7ff3132025f57e63a70683600d75
scripts/verify-context-bytes.ps1       200b911fd3e15d43df28b1ca1942dc318359bbd7
scripts/verify-corpus-bytes.ps1        9c5dc26e9ec78cc9fd9f4aaf283979c89a881cfd
scripts/verify-evaluation-bytes.ps1    dc32229b1241ddfa50761836b0a00099b24e7a09
corpus/m8-corpus-v1.txt                9e36121efec984ff0063ebeb5c51715272e7b6d7
```

`scripts/test.ps1` permanece com 402 linhas, 15766 bytes, BOM UTF-8, último
byte `0x7D` e 116/116.

## 2. Resumo das decisões

| Decisão | Escolha | Alternativa rejeitada |
| --- | --- | --- |
| Tipo de atenção | aditiva, causal, cabeça única | Q/K/V com softmax |
| Normalização | ReLU + divisão inteira | softmax, aproximação por série |
| Valores | embedding congelado (identidade) | V projetado |
| Consulta | constante | consulta de conteúdo |
| Posição | viés `beta[3]` aprendido | codificação senoidal |
| Pesos fixos | apenas baselines X2/X3 | chamar pesos fixos de aprendizado |
| Treino da atenção | descida coordenada discreta (7 parâmetros) | retropropagação |
| Treino da leitura | regra delta da M7 | perceptron com margem |
| Dados | os 10 exemplos da M8 | corpus novo |
| Holdout | benchmark histórico | teste independente |
| Runner | separado (`test-attention.ps1`) | bloco em `test.ps1` |

Justificativa completa em `docs/attention-spec.md` §2-§3.

## 3. Etapas E0-E7

### E0 - Sondas técnicas

**Entregável:** log `temp/m10-probe.log` (descartável).

Verificar no interpretador: `inteiro` 32 bits, divisão inteira, `mod` de
negativos, arrays de tamanho 3 e 4, arredondamento de `r()`, custo de uma
varredura de 231 avaliações de perda.

**Gate G0:** o exemplo de `docs/attention-spec.md` §4 reproduzido em um `.por`
de sonda; custo de uma varredura medida e compatível com o orçamento (§6).

**Fallback:** se o custo da varredura for proibitivo, reduzir a grade de busca
para `-8..8` **antes** de ver qualquer métrica em C, registrando a decisão.

### E1 - Congelar dados e constantes

**Entregável:** `scripts/build-attention-tests.ps1` (parte de dados) e
auditoria `temp/m10-separacao.log`.

- Reutilizar `scripts/eval-datasets.ps1` por dot-sourcing para A/B/C/D.
- Extrair os 10 exemplos de treino do corpus M8 com a mesma regra da M8.
- Confirmar contagens (A=10, B=10+10, C=32, C_SEM_PARE=24, D=10),
  holdout 724/50/`e8aa354e...` e 0 vazamentos.

**Gate G1:** `SEPARACAO=OK`, contagens exatas, hash do holdout inalterado.

**Fallback:** nenhum. Falha em G1 bloqueia E2.

### E2 - Módulo `src/atencao.por`

**Entregável:** fragmento com a API de §8 da spec.

- `at_e16`, `at_score`, `at_pesos`, `at_contexto`, `at_z256`, `at_argmax`.
- `at_perda`, `at_treinar_afim`, `at_varredura`, `at_treinar`.
- `at_avaliar`, `at_margem`, `at_limites`, impressão.
- Sem chamadas a M1-M9; sem `real`; sem aleatoriedade.

**Gate G2:** compila concatenado a um driver; exemplo numérico de §4 idêntico
ao calculado à mão.

**Fallback:** se a varredura completa não couber no custo, usar
primeira-melhoria em vez de melhor-melhoria, registrando antes de avaliar C.

### E3 - Casos base

**Entregável:** T1-T6 e T12-T14 gerados com `.expected` de O1.

**Gate G3:** máscara, padding, normalização, limites e exemplo numérico
passam byte a byte.

**Fallback:** nenhum para causalidade/padding; são gates duros.

### E4 - Baselines e treino

**Entregável:** T7 (uniforme), T8 (recência), T9 (treinado), T10 (ordem).

**Gate G4:** treino reduz a perda estritamente (`L_final < L_0`), converge ou
para por limite, e o histórico é determinístico. Caso a atenção permaneça
uniforme, registrar como resultado negativo, sem forçar.

**Correção de consistência:** cada candidato da varredura reinicia `w,b` pela
inicialização canônica e refaz 4 épocas da regra delta, senão a perda de um
`w,b` já ajustado não pode melhorar apenas por trocar `(a,beta)`. A regra
completa está em `docs/attention-spec.md` §7.3.

**Fallback:** se a perda não cair, o veredito experimental será
`SEM_EVIDENCIA`; nenhum ajuste em C.

### E5 - Relatório e contrato de bytes

**Entregável:** gramática de §8.2, checksum, `T11` de determinismo.

**Gate G5:** dois casos idênticos byte a byte; ASCII/LF; sem `real`.

### E6 - Verificador independente

**Entregável:** `scripts/verify-attention-bytes.ps1` V1-V13 e
`scripts/attention-oracle.ps1` O1/O2, além de O3 manual.

**Gate G6:** V1-V13 verdes com `-SkipSuite`; V12 completa em E7.

### E7 - Execução oficial

Ordem sequencial, sem sobreposição:

1. `scripts/test-attention.ps1` -> 14/14, exit 0;
2. `scripts/verify-attention-bytes.ps1` -> 13/13, exit 0;
3. `scripts/test.ps1` -> 116/116, exit 0;
4. `scripts/verify-context-bytes.ps1` -> 16/16, exit 0;
5. `scripts/verify-corpus-bytes.ps1` -> 18/18, exit 0;
6. `scripts/verify-evaluation-bytes.ps1` -> 13/13, exit 0.

**Gate G7:** todos os números acima + holdout/corpus intactos + veredito de
§9.3 da spec.

**Fallback:** qualquer falha é reportada como falha; nenhum gate é aprovado
por mudança de expectativa.

### Evidências de execução (2026-10-31)

| Etapa | Evidência |
| --- | --- |
| E0 | `7/2=3`, `-7/2=-3`, `-7%3=-1`, `7%-3=1`, `r(-1090,2048)=-1`; exemplo `AT (2,0) s=608 u=608 p=527`, `CTX 1153 5 8 11 14`, `Z 38`, `DELTA -218`, `WN 2 1 0 3`, `BN 3`; limites `1040 3120 49920 1280 1536 589824000` |
| E1 | corpus M8 `9e36121e...`/SHA-256 `d6eb8a78...`; holdout 724 bytes/50 linhas/SHA-256 `e8aa354e...`; A=10, B=10+10, C=32, C_SEM_PARE=24, D=10; 0 vazamentos |
| E2/E3 | `src/atencao.por` ASCII, 132 parâmetros; exemplo de §4 e máscara/padding conferidos; 15 `.por` + 15 `.expected` em `temp/attention-tests/` |
| E4 | corpus real: `TREINO 10 1 810505 529441 0 1` (atenção uniforme, 0 alterações); sintético: `TREINO 10 2 756722 517626 1 1`, `beta[2]=1`, BP 6000 vs 5000 uniforme |
| E5 | `test-attention.ps1`: 14/14, T11 compara `at_determinismo_a/b` byte a byte e SHA-256 |
| E6 | `verify-attention-bytes.ps1 -SkipSuite`: V1-V13, 13/13; V12 completa em E7 |
| E7 | 14/14, 13/13, 116/116, M7 16/16, M8 18/18, M9 13/13; `test.ps1` 402 linhas e blob `e10771b7...` intactos |

Métricas de C (estado treinado): `RESUMO TREINADO C 32 7 2188 2463608`.
Baselines: uniforme `2500`, recência `1250`, histórico M8 `1250`,
memorização/majoritário `2500`. Vantagem sobre o maior baseline: `-312` BP.
Critérios `BP_C >= 4500` e vantagem `>= 2000`: **não atendidos**. Veredito
experimental: `SEM_EVIDENCIA`.

## 4. Gates, critérios e evidências

| Gate | Critério | Evidência |
| --- | --- | --- |
| G0 | exemplo e custo medidos | `temp/m10-probe.log` |
| G1 | dados e hash intactos | `temp/m10-separacao.log` |
| G2 | exemplo numérico exato | `.expected` de O1/O3 |
| G3 | máscara/padding/normalização | testes T2-T4 |
| G4 | perda cai e converge | histórico em T9 |
| G5 | determinismo e bytes | T11 e V11 |
| G6 | V1-V13 | `temp/m10-verify.log` |
| G7 | regressão e veredito | logs oficiais |

## 5. Plano de treinamento (resumo operacional)

Para cada estado treinado (`UNIFORME`, `RECENCIA`, `TREINADO`):

1. inicializar `w,b` pela fórmula canônica e a atenção pelo estado;
2. rodada `r = 1..6`:
   - reajustar `w,b`: inicialização canônica + 4 épocas da regra delta;
   - varredura coordenada de `a` e `beta` (231 reajustes de leitura);
   - reverter e parar se `L` não diminuir;
3. gravar `hist[0..6]` e `info = (rodadas, alterações, convergiu)`;
4. avaliar A/B/C/D e emitir relatório.

Custo por rodada: `231` avaliações × 10 exemplos × (3 escores + 25 logits) ≈
`1,5 × 10^5` multiplicações, seis rodadas ≈ `9 × 10^5`.

## 6. Estimativa de custo

Baseada nos tempos medidos na M9: runner 11 casos em 24 s; M9 verificador em
303 s; M8 em 1169 s; M7 em 462 s.

| Etapa | Estimativa |
| --- | --- |
| E0 sondas | 5-10 min |
| E1 dados | 2-4 min |
| E2 módulo | implementação, sem custo de execução |
| E3 casos base | 3-5 min |
| E4 treino e baselines | 5-10 min |
| E5 bytes | 2-3 min |
| E6 verificador | 10-15 min |
| E7 oficial | ~45 min (M8 + M9 + M7 + M10 + suíte) |
| **Total** | **70-90 min** |

Se a varredura for mais cara que o previsto, o gate G0 reduz a grade antes de
qualquer avaliação em C.

## 7. Compatibilidade de escopo (allowlists e pins)

O padrão V1 de M7/M8/M9 compara `git status` com listas literais. Os 7
caminhos novos de M10 quebrariam V1 exatamente como na M9. A implementação
deve incluir uma etapa autorizada, limitada a:

| Arquivo | Alteração permitida |
| --- | --- |
| `scripts/verify-context-bytes.ps1` | `$allowedStatus`: +7 caminhos M10, +`" M scripts/verify-corpus-bytes.ps1"`, +`" M scripts/verify-evaluation-bytes.ps1"` |
| `scripts/verify-corpus-bytes.ps1` | mesmos caminhos; pin de M7 atualizado para o novo blob |
| `scripts/verify-evaluation-bytes.ps1` | `$allowed`: +7 caminhos M10; pin de M7 atualizado |

Caminhos previstos:

```
?? src/atencao.por
?? scripts/attention-oracle.ps1
?? scripts/build-attention-tests.ps1
?? scripts/test-attention.ps1
?? scripts/verify-attention-bytes.ps1
?? docs/attention-spec.md
?? docs/attention-plan.md
```

Nenhuma verificação funcional, hash de módulo, contagem ou expectativa é
alterada. O patch é provado mínimo reconstruindo os blobs pré-patch, como em
M9 §14.3.

Se a autorização para tocar nesses três verificadores não for concedida, a
alternativa é aceitar V1 de M7/M8/M9 falhando por escopo e declarar o
resultado `PARCIAL`; o plano recomenda a autorização explícita.

## 8. Protocolo experimental (resumo)

- Treinar `UNIFORME`, `RECENCIA` e `TREINADO` nos mesmos 10 exemplos.
- Avaliar nos conjuntos M9, sem ajustar nada em C.
- Reportar A/B/C/D, C_SEM_PARE, perda, margem, confusão, ordem, padding e
  causalidade.
- Comparar com M8 (1250 em C) e baselines (2500, 2500, 938).
- Critério: `BP_C >= 4500` e `Delta >= 2000` sobre o maior baseline; caso
  contrário, `SEM_EVIDENCIA`.
- Declarar C como benchmark histórico, não teste independente.

## 9. Matriz de testes (resumo)

14 verificações `.por` (T1-T14; T11 usa dois arquivos A/B, total de 15 arquivos):
limites, máscara, padding, pesos, exemplo, não treinado,
uniforme, recência, treinado, ordem, determinismo A/B e causalidade futura.
Detalhes em `docs/attention-spec.md` §10. Cada `.expected` vem de O1; O2 e O3
auditam.

## 10. Critérios de aceitação (AC1-AC12)

Mapeamento direto para gates:

| AC | Critério | Gate |
| --- | --- | --- |
| AC1 | Somente arquivos autorizados | G7 |
| AC2 | `test.ps1` intocado, 116/116 | G7 |
| AC3 | Runner M10 14/14, exit 0 | G7 |
| AC4 | Causalidade comprovada | G3 |
| AC5 | Padding sem PAD-ID | G3 |
| AC6 | Pesos normalizados e observáveis | G3 |
| AC7 | Perda cai e converge | G4 |
| AC8 | O1/O2/O3/`.por` iguais em C | G6 |
| AC9 | Determinismo e ASCII/LF | G5 |
| AC10 | M7/M8/M9/suíte sem regressão | G7 |
| AC11 | Veredito emitido com números reais | G7 |
| AC12 | Sem commit/push/tag/branch | G7 |

## 11. Riscos específicos do plano

| Risco | Mitigação |
| --- | --- |
| Custo da varredura estourar | G0 mede antes; grade `-8..8` pré-registrada |
| Busca ficar em platô | reportar; comparar X2/X3; não forçar |
| Overfitting em 10 exemplos | holdout histórico; sem tuning |
| Allowlists quebrarem | §7, com autorização prévia |
| Interpretar A como generalização | critério usa apenas C |
| Treino não convergir | `SEM_EVIDENCIA`, sem ajuste |
| Oráculo divergir do `.por` | O2/O3 independentes e exemplo manual |

## 12. Arquivos previstos para a implementação (não autorizados agora)

| Arquivo | Ação |
| --- | --- |
| `src/atencao.por` | novo |
| `scripts/attention-oracle.ps1` | novo |
| `scripts/build-attention-tests.ps1` | novo |
| `scripts/test-attention.ps1` | novo |
| `scripts/verify-attention-bytes.ps1` | novo |
| `docs/attention-spec.md` | criado nesta fase; status/evidências em E7 |
| `docs/attention-plan.md` | criado nesta fase; evidências E0-E7 |
| `scripts/verify-context-bytes.ps1` | allowlist de escopo + pin (autorização §7) |
| `scripts/verify-corpus-bytes.ps1` | allowlist de escopo + pin (autorização §7) |
| `scripts/verify-evaluation-bytes.ps1` | allowlist de escopo + pin (autorização §7) |
| `temp/attention-tests/*` | gerado, ignorado pelo Git |

**Não autorizados:** `src/tokenizador.por`, `src/embeddings.por`,
`src/rede.por`, `src/treino.por`, `src/gerador.por`, `src/contexto.por`,
`src/corpus.por`, `src/avaliacao.por`, `corpus/`, `scripts/test.ps1`,
`README.md`, `AGENTS.md`, `tests/` e os demais verificadores.

## 13. Critérios de conclusão desta fase

- `docs/attention-spec.md` e `docs/attention-plan.md` existem.
- UTF-8 sem BOM, LF, um LF final, 0 CR.
- `git status --short` mostra apenas os dois documentos novos.
- Nenhum código, script, corpus, teste, verificador, README ou `AGENTS.md`
  alterado.
- Nenhum commit, push, tag ou branch.
- Nenhuma implementação iniciada.

## 14. Pedido de aprovação

Aprovar a implementação de E0-E7 com os arquivos de §12, incluindo a
autorização limitada de §7 para os três verificadores de escopo. Sem
aprovação explícita, o trabalho para aqui.
