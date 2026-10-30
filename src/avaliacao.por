// ---------------------------------------------------------------------------
// Modulo de avaliacao de generalizacao (M9).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-evaluation-tests.ps1 concatena src/tokenizador.por,
// src/corpus.por, src/contexto.por e este fragmento a um driver.
//
// Contrato: estritamente somente leitura sobre w16/b16. Nenhuma funcao deste
// arquivo treina, extrai janelas ou executa a rede. O treino ocorre apenas no
// driver, uma vez, sobre os 10 pares congelados.
// Fonte ASCII puro. Sem real, tempo, aleatoriedade, arquivo ou locale.
// ---------------------------------------------------------------------------

const inteiro AVAL_MAX = 64
const inteiro AVAL_LOTE = 6
const inteiro AVAL_ESCALA = 131072
const inteiro AVAL_S_MAX_LOTE = 1926758400
const inteiro AVAL_VOCAB = 25
const inteiro AVAL_CONF = 625
const inteiro AVAL_SAIDA = 16

const inteiro AVAL_ERR_N = 21
const inteiro AVAL_ERR_ID = 22
const inteiro AVAL_ERR_PARAMS = 23
const inteiro AVAL_ERR_CATEGORIA = 24
const inteiro AVAL_ERR_S = 25
const inteiro AVAL_ERR_BUFFER = 26

// Divisao inteira com piso. Pre-condicao: num >= 0, den > 0.
// Retorna -1 para dominio invalido, sem mascarar erro com quociente.
funcao inteiro aval_div_piso(inteiro num, inteiro den)
{
    se (den <= 0 ou num < 0)
    {
        retorne 0 - 1
    }
    retorne num / den
}

// m_b = floor(1000*S_b/(131072*n_b)), sem materializar 1000*S_b.
// Pre-condicao: 0 <= s <= AVAL_S_MAX_LOTE e 1 <= n <= AVAL_LOTE.
funcao inteiro aval_milesimos(inteiro s, inteiro n)
{
    se (n < 1 ou n > AVAL_LOTE ou s < 0 ou s > AVAL_S_MAX_LOTE)
    {
        retorne 0 - 1
    }
    inteiro den = AVAL_ESCALA * n
    inteiro q = s / den
    inteiro r = s % den
    retorne 1000 * q + (1000 * r) / den
}

// Checksum linear do estado completo. |checksum| <= 727600.
funcao inteiro aval_checksum(inteiro w16[], inteiro b16[])
{
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < 300)
    {
        soma = soma + (i + 1) * w16[i]
        i = i + 1
    }
    i = 0
    enquanto (i < 25)
    {
        soma = soma + (i + 1) * b16[i]
        i = i + 1
    }
    retorne soma
}

// IDs em 0..24. n em 1..AVAL_MAX. 0 (UNK) e valido aqui; o builder rejeita
// 0 nos conjuntos de avaliacao.
funcao logico aval_ids_validos(inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (n < 1 ou n > AVAL_MAX)
    {
        retorne falso
    }
    inteiro i = 0
    enquanto (i < n * 3)
    {
        se (entradas[i] < 0 ou entradas[i] > 24)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < n)
    {
        se (alvos[i] < 0 ou alvos[i] > 24)
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

// Copia tam exemplos a partir de base. Retorna 0 ou AVAL_ERR_BUFFER.
funcao inteiro aval_copiar_lote(inteiro entradas[], inteiro alvos[],
                                inteiro base, inteiro tam,
                                inteiro lote_entradas[], inteiro lote_alvos[])
{
    se (base < 0 ou tam < 0 ou tam > AVAL_LOTE)
    {
        retorne AVAL_ERR_BUFFER
    }
    inteiro j = 0
    enquanto (j < tam)
    {
        lote_entradas[j * 3] = entradas[(base + j) * 3]
        lote_entradas[j * 3 + 1] = entradas[(base + j) * 3 + 1]
        lote_entradas[j * 3 + 2] = entradas[(base + j) * 3 + 2]
        lote_alvos[j] = alvos[base + j]
        j = j + 1
    }
    retorne 0
}

// BP = r(10000*acertos, n). n em 1..AVAL_MAX.
funcao inteiro aval_bp(inteiro acertos, inteiro n)
{
    se (n < 1 ou n > AVAL_MAX ou acertos < 0 ou acertos > n)
    {
        retorne 0 - 1
    }
    retorne ctx_div_arredondada(10000 * acertos, n)
}

// Media ponderada dos milesimos dos lotes. Pre-condicao: saida preenchida.
funcao inteiro aval_media_milesimos(inteiro saida[], inteiro n)
{
    se (n < 1 ou n > AVAL_MAX)
    {
        retorne 0 - 1
    }
    inteiro lotes = saida[1]
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < lotes)
    {
        inteiro tam = n - i * AVAL_LOTE
        se (tam > AVAL_LOTE)
        {
            tam = AVAL_LOTE
        }
        inteiro m = aval_milesimos(saida[2 + i], tam)
        se (m < 0)
        {
            retorne 0 - 1
        }
        soma = soma + m * tam
        i = i + 1
    }
    retorne soma / n
}

// Avalia em lotes de ate 6. Layout de saida[]:
//   [0] acertos (ctx_acertos), [1] n_lotes, [2..12] S_b, [13] acertos
//   recalculados por argmax, [14..15] reservados.
// Preenche conf[alvo*25 + pred]. Nao altera w16/b16.
funcao inteiro aval_avaliar(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[], inteiro n,
                            inteiro conf[], inteiro saida[])
{
    se (n < 1 ou n > AVAL_MAX)
    {
        retorne AVAL_ERR_N
    }
    se (nao aval_ids_validos(entradas, alvos, n))
    {
        retorne AVAL_ERR_ID
    }
    se (nao ctx_params_validos(w16, b16))
    {
        retorne AVAL_ERR_PARAMS
    }

    inteiro acertos = 0
    inteiro lotes = 0
    inteiro base = 0
    inteiro lote_e[18]
    inteiro lote_t[6]
    enquanto (base < n)
    {
        inteiro tam = n - base
        se (tam > AVAL_LOTE)
        {
            tam = AVAL_LOTE
        }
        inteiro cc = aval_copiar_lote(entradas, alvos, base, tam, lote_e, lote_t)
        se (cc != 0)
        {
            retorne cc
        }
        acertos = acertos + ctx_acertos(w16, b16, lote_e, lote_t, tam)
        inteiro s = ctx_perda_escalada(w16, b16, lote_e, lote_t, tam)
        se (s < 0 ou s > AVAL_S_MAX_LOTE)
        {
            retorne AVAL_ERR_S
        }
        saida[2 + lotes] = s
        lotes = lotes + 1
        base = base + AVAL_LOTE
    }

    inteiro acertos_loop = 0
    inteiro i = 0
    enquanto (i < n)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        inteiro pred = ctx_argmax(w16, b16, c16)
        se (pred == alvos[i])
        {
            acertos_loop = acertos_loop + 1
        }
        conf[alvos[i] * AVAL_VOCAB + pred] = conf[alvos[i] * AVAL_VOCAB + pred] + 1
        i = i + 1
    }

    saida[0] = acertos
    saida[1] = lotes
    saida[13] = acertos_loop
    retorne 0
}

// ZP - ZT para um exemplo. Somente leitura.
funcao inteiro aval_margem(inteiro w16[], inteiro b16[],
                           inteiro entradas[], inteiro i,
                           inteiro alvo, inteiro pred)
{
    inteiro c16[12]
    ctx_contexto_de_exemplo(entradas, i, c16)
    retorne ctx_z256(w16, b16, c16, pred) - ctx_z256(w16, b16, c16, alvo)
}

// Imprime W16/B16 ou W16_FIM/B16_FIM. fim=0 inicio, fim=1 fim.
funcao aval_imprimir_estado(inteiro w16[], inteiro b16[], inteiro fim)
{
    inteiro y = 0
    enquanto (y < 25)
    {
        se (fim == 0)
        {
            escreva("W16 ", y)
        }
        senao
        {
            escreva("W16_FIM ", y)
        }
        inteiro p = 0
        enquanto (p < 12)
        {
            escreva(" ", w16[y * 12 + p])
            p = p + 1
        }
        escreva("\n")
        y = y + 1
    }
    se (fim == 0)
    {
        escreva("B16")
    }
    senao
    {
        escreva("B16_FIM")
    }
    y = 0
    enquanto (y < 25)
    {
        escreva(" ", b16[y])
        y = y + 1
    }
    escreva("\n")
}

// mutacao_ok: 1 OK, 0 FALHA, -1 NA. acertos_ok: 1 OK, 0 FALHA.
funcao aval_imprimir_check(cadeia estado, inteiro mutacao_ok, inteiro acertos_ok)
{
    escreva("CHECK ", estado, " MUTACAO ")
    se (mutacao_ok == 1)
    {
        escreva("OK\n")
    }
    senao se (mutacao_ok == 0)
    {
        escreva("FALHA\n")
    }
    senao
    {
        escreva("NA\n")
    }
    escreva("CHECK ", estado, " ACERTOS ")
    se (acertos_ok == 1)
    {
        escreva("OK\n")
    }
    senao
    {
        escreva("FALHA\n")
    }
}

funcao aval_imprimir_resumo(cadeia estado, cadeia conjunto,
                            inteiro n, inteiro acertos, inteiro milesimos)
{
    escreva("RESUMO ", estado, " ", conjunto, " ", n, " ", acertos,
            " ", aval_bp(acertos, n), " ", milesimos, "\n")
}

funcao aval_imprimir_perda(cadeia estado, cadeia conjunto,
                           inteiro saida[], inteiro n)
{
    inteiro lotes = saida[1]
    inteiro i = 0
    enquanto (i < lotes)
    {
        inteiro tam = n - i * AVAL_LOTE
        se (tam > AVAL_LOTE)
        {
            tam = AVAL_LOTE
        }
        escreva("PERDA ", estado, " ", conjunto, " ", i + 1, " ", tam,
                " ", saida[2 + i], "\n")
        i = i + 1
    }
}

funcao aval_imprimir_conf(cadeia estado, cadeia conjunto,
                          inteiro conf[], inteiro n)
{
    inteiro alvo = 0
    enquanto (alvo < AVAL_VOCAB)
    {
        inteiro pred = 0
        enquanto (pred < AVAL_VOCAB)
        {
            inteiro q = conf[alvo * AVAL_VOCAB + pred]
            se (q > 0)
            {
                escreva("CONF ", estado, " ", conjunto, " ", alvo, " ",
                        pred, " ", q, "\n")
            }
            pred = pred + 1
        }
        alvo = alvo + 1
    }
}

// Uma linha EX. tipo: -1 nenhum, 0 INEDITO, 1 VISTO.
funcao aval_imprimir_ex(cadeia estado, cadeia conjunto, inteiro indice,
                        inteiro pos, inteiro entradas[], inteiro i,
                        inteiro alvo, inteiro pred, inteiro ok,
                        inteiro zp, inteiro zt, inteiro mz,
                        inteiro alvo_treino, inteiro tipo)
{
    escreva("EX ", estado, " ", conjunto, " ", indice, " ", pos, " ",
            entradas[i * 3], " ", entradas[i * 3 + 1], " ",
            entradas[i * 3 + 2], " ", alvo, " ", pred, " ", ok, " ",
            zp, " ", zt, " ", mz, " ", alvo_treino, " ")
    se (tipo == 1)
    {
        escreva("VISTO")
    }
    senao se (tipo == 0)
    {
        escreva("INEDITO")
    }
    senao
    {
        escreva("-")
    }
    escreva(" ")
    ctx_escrever_palavra(alvo)
    escreva(" ")
    ctx_escrever_palavra(pred)
    escreva("\n")
}

// Relatorio de um conjunto parametrizado (A, C ou D).
// layout: 0 pares (pos=0), 1 sequencias (pos=i%4).
// imprimir_ex: 1 imprime EX, 0 apenas resumo/perda/conf.
// derivar_sem_pare: 1 imprime tambem o RESUMO C_SEM_PARE (usar em C).
funcao inteiro aval_relatorio(cadeia estado, cadeia conjunto,
                              inteiro w16[], inteiro b16[],
                              inteiro entradas[], inteiro alvos[], inteiro n,
                              inteiro tipo[], inteiro alvo_treino[],
                              inteiro layout, inteiro imprimir_ex,
                              inteiro derivar_sem_pare)
{
    se (layout < 0 ou layout > 2)
    {
        retorne AVAL_ERR_CATEGORIA
    }
    inteiro ck0 = aval_checksum(w16, b16)
    inteiro conf[625]
    inteiro i = 0
    enquanto (i < AVAL_CONF)
    {
        conf[i] = 0
        i = i + 1
    }
    inteiro saida[16]
    i = 0
    enquanto (i < AVAL_SAIDA)
    {
        saida[i] = 0
        i = i + 1
    }

    inteiro codigo = aval_avaliar(w16, b16, entradas, alvos, n, conf, saida)
    se (codigo != 0)
    {
        retorne codigo
    }

    inteiro ck1 = aval_checksum(w16, b16)
    inteiro mut = 0
    se (ck0 == ck1)
    {
        mut = 1
    }
    inteiro acertos_ok = 0
    se (saida[0] == saida[13])
    {
        acertos_ok = 1
    }
    aval_imprimir_check(estado, mut, acertos_ok)

    aval_imprimir_resumo(estado, conjunto, n, saida[0],
                         aval_media_milesimos(saida, n))
    aval_imprimir_perda(estado, conjunto, saida, n)

    inteiro sem_pare_n = 0
    inteiro sem_pare_acertos = 0
    i = 0
    enquanto (i < n)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        inteiro pred = ctx_argmax(w16, b16, c16)
        inteiro ok = 0
        se (pred == alvos[i])
        {
            ok = 1
        }
        se (alvos[i] != 24)
        {
            sem_pare_n = sem_pare_n + 1
            sem_pare_acertos = sem_pare_acertos + ok
        }
        se (imprimir_ex == 1)
        {
            inteiro indice = i + 1
            inteiro pos = 0
            se (layout == 1)
            {
                indice = i / 4 + 1
                pos = i % 4
            }
            inteiro zp = ctx_z256(w16, b16, c16, pred)
            inteiro zt = ctx_z256(w16, b16, c16, alvos[i])
            aval_imprimir_ex(estado, conjunto, indice, pos, entradas, i,
                             alvos[i], pred, ok, zp, zt, zp - zt,
                             alvo_treino[i], tipo[i])
        }
        i = i + 1
    }

    aval_imprimir_conf(estado, conjunto, conf, n)

    se (derivar_sem_pare == 1)
    {
        aval_imprimir_resumo(estado, "C_SEM_PARE", sem_pare_n,
                             sem_pare_acertos, 0 - 1)
    }
    retorne 0
}

// Relatorio do conjunto B (20 predicoes mistas). Imprime RESUMO B,
// B_VISTO e B_INEDITO; PERDA/EX/CONF apenas para B.
funcao inteiro aval_relatorio_b(cadeia estado, inteiro w16[], inteiro b16[],
                                inteiro entradas[], inteiro alvos[],
                                inteiro tipo[], inteiro imprimir_ex)
{
    inteiro ck0 = aval_checksum(w16, b16)
    inteiro conf[625]
    inteiro i = 0
    enquanto (i < AVAL_CONF)
    {
        conf[i] = 0
        i = i + 1
    }
    inteiro saida[16]
    i = 0
    enquanto (i < AVAL_SAIDA)
    {
        saida[i] = 0
        i = i + 1
    }

    inteiro codigo = aval_avaliar(w16, b16, entradas, alvos, 20, conf, saida)
    se (codigo != 0)
    {
        retorne codigo
    }

    inteiro ck1 = aval_checksum(w16, b16)
    inteiro mut = 0
    se (ck0 == ck1)
    {
        mut = 1
    }
    inteiro acertos_ok = 0
    se (saida[0] == saida[13])
    {
        acertos_ok = 1
    }
    aval_imprimir_check(estado, mut, acertos_ok)

    aval_imprimir_resumo(estado, "B", 20, saida[0],
                         aval_media_milesimos(saida, 20))

    inteiro vistos = 0
    inteiro ineditos = 0
    i = 0
    enquanto (i < 20)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        inteiro pred = ctx_argmax(w16, b16, c16)
        se (pred == alvos[i])
        {
            se (tipo[i] == 1)
            {
                vistos = vistos + 1
            }
            senao
            {
                ineditos = ineditos + 1
            }
        }
        i = i + 1
    }
    aval_imprimir_resumo(estado, "B_VISTO", 10, vistos, 0 - 1)
    aval_imprimir_resumo(estado, "B_INEDITO", 10, ineditos, 0 - 1)

    aval_imprimir_perda(estado, "B", saida, 20)

    i = 0
    enquanto (i < 20)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        inteiro pred = ctx_argmax(w16, b16, c16)
        inteiro ok = 0
        se (pred == alvos[i])
        {
            ok = 1
        }
        se (imprimir_ex == 1)
        {
            inteiro zp = ctx_z256(w16, b16, c16, pred)
            inteiro zt = ctx_z256(w16, b16, c16, alvos[i])
            aval_imprimir_ex(estado, "B", i / 4 + 1, i % 4, entradas, i,
                             alvos[i], pred, ok, zp, zt, zp - zt,
                             0 - 1, tipo[i])
        }
        i = i + 1
    }
    aval_imprimir_conf(estado, "B", conf, 20)
    retorne 0
}

// Lookup de memorizacao: se o contexto e visto, prediz o alvo de treino;
// senao prediz 24. Retorna 0 ou codigo.
funcao inteiro aval_baseline_lookup(inteiro train_e[], inteiro train_t[],
                                    inteiro n_treino,
                                    inteiro entradas[], inteiro alvos[],
                                    inteiro n, inteiro preds[])
{
    se (n < 1 ou n > AVAL_MAX ou n_treino < 1 ou n_treino > 30)
    {
        retorne AVAL_ERR_N
    }
    se (nao aval_ids_validos(entradas, alvos, n) ou
        nao aval_ids_validos(train_e, train_t, n_treino))
    {
        retorne AVAL_ERR_ID
    }
    inteiro i = 0
    enquanto (i < n)
    {
        inteiro pred = 24
        logico achou = falso
        inteiro j = 0
        enquanto (j < n_treino e nao achou)
        {
            se (train_e[j * 3] == entradas[i * 3] e
                train_e[j * 3 + 1] == entradas[i * 3 + 1] e
                train_e[j * 3 + 2] == entradas[i * 3 + 2])
            {
                pred = train_t[j]
                achou = verdadeiro
            }
            j = j + 1
        }
        preds[i] = pred
        i = i + 1
    }
    retorne 0
}

funcao aval_preencher_constante(inteiro preds[], inteiro n, inteiro valor)
{
    inteiro i = 0
    enquanto (i < n)
    {
        preds[i] = valor
        i = i + 1
    }
}

funcao inteiro aval_contar_acertos(inteiro preds[], inteiro alvos[], inteiro n)
{
    inteiro total = 0
    inteiro i = 0
    enquanto (i < n)
    {
        se (preds[i] == alvos[i])
        {
            total = total + 1
        }
        i = i + 1
    }
    retorne total
}

// Acertos de um subconjunto de B: classe 1 VISTO, 0 INEDITO.
funcao inteiro aval_contar_acertos_tipo(inteiro preds[], inteiro alvos[],
                                        inteiro tipo[], inteiro n, inteiro classe)
{
    inteiro total = 0
    inteiro i = 0
    enquanto (i < n)
    {
        se (tipo[i] == classe e preds[i] == alvos[i])
        {
            total = total + 1
        }
        i = i + 1
    }
    retorne total
}

// Predicoes top-1 de um estado parametrizado. Somente leitura.
funcao inteiro aval_predizer(inteiro w16[], inteiro b16[],
                             inteiro entradas[], inteiro n, inteiro preds[])
{
    se (n < 1 ou n > AVAL_MAX)
    {
        retorne 0 - 1
    }
    inteiro i = 0
    enquanto (i < n)
    {
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        preds[i] = ctx_argmax(w16, b16, c16)
        i = i + 1
    }
    retorne 0
}

// Acertos de um estado parametrizado em lotes de ate 6. Somente leitura.
funcao inteiro aval_acertos_lotes(inteiro w16[], inteiro b16[],
                                  inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (n < 1 ou n > AVAL_MAX)
    {
        retorne 0 - 1
    }
    se (nao aval_ids_validos(entradas, alvos, n))
    {
        retorne 0 - 1
    }
    inteiro total = 0
    inteiro base = 0
    inteiro lote_e[18]
    inteiro lote_t[6]
    enquanto (base < n)
    {
        inteiro tam = n - base
        se (tam > AVAL_LOTE)
        {
            tam = AVAL_LOTE
        }
        inteiro cc = aval_copiar_lote(entradas, alvos, base, tam, lote_e, lote_t)
        se (cc != 0)
        {
            retorne 0 - 1
        }
        total = total + ctx_acertos(w16, b16, lote_e, lote_t, tam)
        base = base + AVAL_LOTE
    }
    retorne total
}

// Relatorio de um baseline discreto (sem w16/b16). mutacao = NA.
// layout/derivar_sem_pare tem o mesmo significado de aval_relatorio.
funcao aval_relatorio_baseline(cadeia estado, cadeia conjunto,
                               inteiro entradas[], inteiro preds[],
                               inteiro alvos[], inteiro n,
                               inteiro tipo[], inteiro alvo_treino[],
                               inteiro layout, inteiro imprimir_ex,
                               inteiro derivar_sem_pare)
{
    inteiro conf[625]
    inteiro i = 0
    enquanto (i < AVAL_CONF)
    {
        conf[i] = 0
        i = i + 1
    }

    inteiro acertos = 0
    inteiro sem_pare_n = 0
    inteiro sem_pare_acertos = 0
    i = 0
    enquanto (i < n)
    {
        se (preds[i] == alvos[i])
        {
            acertos = acertos + 1
        }
        se (alvos[i] != 24)
        {
            sem_pare_n = sem_pare_n + 1
            se (preds[i] == alvos[i])
            {
                sem_pare_acertos = sem_pare_acertos + 1
            }
        }
        conf[alvos[i] * AVAL_VOCAB + preds[i]] =
            conf[alvos[i] * AVAL_VOCAB + preds[i]] + 1
        i = i + 1
    }

    aval_imprimir_check(estado, 0 - 1, 1)
    aval_imprimir_resumo(estado, conjunto, n, acertos, 0 - 1)

    i = 0
    enquanto (i < n)
    {
        se (imprimir_ex == 1)
        {
            inteiro ok = 0
            se (preds[i] == alvos[i])
            {
                ok = 1
            }
            inteiro indice = i + 1
            inteiro pos = 0
            se (layout == 1)
            {
                indice = i / 4 + 1
                pos = i % 4
            }
            aval_imprimir_ex(estado, conjunto, indice, pos, entradas, i,
                             alvos[i], preds[i], ok, 0, 0, 0,
                             alvo_treino[i], tipo[i])
        }
        i = i + 1
    }

    aval_imprimir_conf(estado, conjunto, conf, n)

    se (derivar_sem_pare == 1)
    {
        aval_imprimir_resumo(estado, "C_SEM_PARE", sem_pare_n,
                             sem_pare_acertos, 0 - 1)
    }
}

// Relatorio B para baseline discreto. Predicoes em preds[0..19].
funcao aval_relatorio_baseline_b(cadeia estado,
                                 inteiro entradas[], inteiro preds[],
                                 inteiro alvos[], inteiro tipo[],
                                 inteiro imprimir_ex)
{
    inteiro conf[625]
    inteiro i = 0
    enquanto (i < AVAL_CONF)
    {
        conf[i] = 0
        i = i + 1
    }

    inteiro acertos = 0
    inteiro vistos = 0
    inteiro ineditos = 0
    i = 0
    enquanto (i < 20)
    {
        se (preds[i] == alvos[i])
        {
            acertos = acertos + 1
            se (tipo[i] == 1)
            {
                vistos = vistos + 1
            }
            senao
            {
                ineditos = ineditos + 1
            }
        }
        conf[alvos[i] * AVAL_VOCAB + preds[i]] =
            conf[alvos[i] * AVAL_VOCAB + preds[i]] + 1
        i = i + 1
    }

    aval_imprimir_check(estado, 0 - 1, 1)
    aval_imprimir_resumo(estado, "B", 20, acertos, 0 - 1)
    aval_imprimir_resumo(estado, "B_VISTO", 10, vistos, 0 - 1)
    aval_imprimir_resumo(estado, "B_INEDITO", 10, ineditos, 0 - 1)

    i = 0
    enquanto (i < 20)
    {
        se (imprimir_ex == 1)
        {
            inteiro ok = 0
            se (preds[i] == alvos[i])
            {
                ok = 1
            }
            aval_imprimir_ex(estado, "B", i / 4 + 1, i % 4, entradas, i,
                             alvos[i], preds[i], ok, 0, 0, 0,
                             0 - 1, tipo[i])
        }
        i = i + 1
    }

    aval_imprimir_conf(estado, "B", conf, 20)
}

funcao aval_imprimir_delta(cadeia conjunto, inteiro bp_estado, inteiro bp_base)
{
    escreva("DELTA_BP ", conjunto, " ", bp_estado, " ", bp_base, " ",
            bp_estado - bp_base, "\n")
}

// Sensibilidade a permutacoes de contexto na inferencia. Imprime seis
// predicoes por contexto (identidade incluida) e um resumo. Verifica tambem
// que o estado nao mudou.
funcao inteiro aval_permutacoes(cadeia estado, inteiro w16[], inteiro b16[],
                                inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (n < 1 ou n > AVAL_MAX)
    {
        retorne AVAL_ERR_N
    }
    se (nao aval_ids_validos(entradas, alvos, n))
    {
        retorne AVAL_ERR_ID
    }
    inteiro ck0 = aval_checksum(w16, b16)
    inteiro alterados = 0
    inteiro mudancas_total = 0
    inteiro i = 0
    enquanto (i < n)
    {
        inteiro a = entradas[i * 3]
        inteiro b = entradas[i * 3 + 1]
        inteiro c = entradas[i * 3 + 2]
        inteiro p[3]
        inteiro c16[12]

        p[0] = a
        p[1] = b
        p[2] = c
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro original = ctx_argmax(w16, b16, c16)

        p[0] = a
        p[1] = b
        p[2] = c
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro m1 = ctx_argmax(w16, b16, c16)

        p[0] = a
        p[1] = c
        p[2] = b
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro m2 = ctx_argmax(w16, b16, c16)

        p[0] = b
        p[1] = a
        p[2] = c
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro m3 = ctx_argmax(w16, b16, c16)

        p[0] = b
        p[1] = c
        p[2] = a
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro m4 = ctx_argmax(w16, b16, c16)

        p[0] = c
        p[1] = a
        p[2] = b
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro m5 = ctx_argmax(w16, b16, c16)

        p[0] = c
        p[1] = b
        p[2] = a
        ctx_contexto_de_exemplo(p, 0, c16)
        inteiro m6 = ctx_argmax(w16, b16, c16)

        inteiro mud = 0
        se (m2 != original) { mud = mud + 1 }
        se (m3 != original) { mud = mud + 1 }
        se (m4 != original) { mud = mud + 1 }
        se (m5 != original) { mud = mud + 1 }
        se (m6 != original) { mud = mud + 1 }
        se (mud > 0)
        {
            alterados = alterados + 1
        }
        mudancas_total = mudancas_total + mud
        escreva("PERM ", i + 1, " ", a, " ", b, " ", c, " ", original,
                " ", m1, " ", m2, " ", m3, " ", m4, " ", m5, " ", m6,
                " ", mud, "\n")
        i = i + 1
    }
    escreva("PERM_RESUMO ", n, " ", alterados, " ", mudancas_total, "\n")
    inteiro ck1 = aval_checksum(w16, b16)
    inteiro mut = 0
    se (ck0 == ck1)
    {
        mut = 1
    }
    aval_imprimir_check(estado, mut, 1)
    retorne 0
}

// 1 se IDs validos, 0 caso contrario.
funcao inteiro aval_ids_num(inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (aval_ids_validos(entradas, alvos, n))
    {
        retorne 1
    }
    retorne 0
}

// Caso sintetico de limites. Imprime codigos observaveis, sem depender de
// excecao do interpretador. Somente leitura sobre w16/b16.
funcao aval_limites(inteiro w16[], inteiro b16[],
                    inteiro train_e[], inteiro train_t[])
{
    inteiro ok_e[4]
    ok_e[0] = 1
    ok_e[1] = 3
    ok_e[2] = 17
    ok_e[3] = 0
    inteiro ok_t[4]
    ok_t[0] = 22
    ok_t[1] = 0
    ok_t[2] = 0
    ok_t[3] = 0
    inteiro bad_e[4]
    bad_e[0] = 25
    bad_e[1] = 3
    bad_e[2] = 17
    bad_e[3] = 0
    inteiro neg_e[4]
    neg_e[0] = 0 - 1
    neg_e[1] = 3
    neg_e[2] = 17
    neg_e[3] = 0

    inteiro conf[625]
    inteiro saida[16]
    inteiro i = 0
    enquanto (i < 625)
    {
        conf[i] = 0
        i = i + 1
    }
    i = 0
    enquanto (i < 16)
    {
        saida[i] = 0
        i = i + 1
    }

    escreva("AVAL V1\n")
    escreva("LIMITES\n")
    escreva("IDS n=0 ", aval_ids_num(ok_e, ok_t, 0), "\n")
    escreva("IDS n=65 ", aval_ids_num(ok_e, ok_t, 65), "\n")
    escreva("IDS id=25 ", aval_ids_num(bad_e, ok_t, 1), "\n")
    escreva("IDS id=-1 ", aval_ids_num(neg_e, ok_t, 1), "\n")
    escreva("IDS validos ", aval_ids_num(ok_e, ok_t, 1), "\n")
    escreva("DIV 10 3 ", aval_div_piso(10, 3), "\n")
    escreva("DIV 0 5 ", aval_div_piso(0, 5), "\n")
    escreva("DIV 5 0 ", aval_div_piso(5, 0), "\n")
    escreva("DIV -1 3 ", aval_div_piso(0 - 1, 3), "\n")
    escreva("MILES 0 1 ", aval_milesimos(0, 1), "\n")
    escreva("MILES 1 1 ", aval_milesimos(1, 1), "\n")
    escreva("MILES 321126400 1 ", aval_milesimos(321126400, 1), "\n")
    escreva("MILES 1926758400 6 ", aval_milesimos(1926758400, 6), "\n")
    escreva("MILES 1 0 ", aval_milesimos(1, 0), "\n")
    escreva("CHECKSUM ", aval_checksum(w16, b16), "\n")

    escreva("AVALIAR n=0 ", aval_avaliar(w16, b16, train_e, train_t, 0, conf, saida), "\n")
    escreva("AVALIAR n=65 ", aval_avaliar(w16, b16, train_e, train_t, 65, conf, saida), "\n")
    escreva("AVALIAR id=25 ", aval_avaliar(w16, b16, bad_e, ok_t, 1, conf, saida), "\n")
    escreva("AVALIAR id=-1 ", aval_avaliar(w16, b16, neg_e, ok_t, 1, conf, saida), "\n")

    inteiro bad_w[300]
    i = 0
    enquanto (i < 300)
    {
        bad_w[i] = w16[i]
        i = i + 1
    }
    bad_w[0] = 17
    escreva("AVALIAR params ", aval_avaliar(bad_w, b16, train_e, train_t, 10, conf, saida), "\n")

    escreva("RELATORIO modo 3 ", aval_relatorio("LIMITES", "A", w16, b16,
            train_e, train_t, 10, ok_e, ok_t, 3, 0, 0), "\n")

    inteiro lote_e[18]
    inteiro lote_t[6]
    escreva("COPIAR tam=7 ", aval_copiar_lote(train_e, train_t, 0, 7, lote_e, lote_t), "\n")
    escreva("COPIAR tam=6 ", aval_copiar_lote(train_e, train_t, 0, 6, lote_e, lote_t), "\n")
    escreva("FIM\n")
}
