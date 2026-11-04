// ---------------------------------------------------------------------------
// Modulo de atencao causal minima (M10, spec v1.0.0).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-attention-tests.ps1 concatena este fragmento a um driver.
//
// ATENCAO NAO E TRANSFORMER nem self-attention Q/K/V. Este modulo implementa
// uma unica agregacao causal de ate T=3 embeddings congelados (M3), com
// escores aditivos e pesos inteiros observaveis, seguida de uma camada afim
// 4 -> 25. Nao ha softmax, exponencial, camada residual, normalizacao de
// camada, feed-forward, multiplas cabecas nem projecoes treinaveis.
//
// Estado: inteiro a[4] (escore aditivo), beta[3] (vies posicional),
// w[100] (w[y*4+d]) e b[25], todos em unidades de 1/16, |v| <= 16.
// Fonte ASCII puro. Sem real, tempo, aleatoriedade, arquivo ou locale.
// ---------------------------------------------------------------------------

const inteiro AT_T = 3
const inteiro AT_D = 4
const inteiro AT_V = 25
const inteiro AT_TOTAL_W = 100
const inteiro AT_TOTAL_B = 25
const inteiro AT_LIMITE = 16
const inteiro AT_RODADAS = 6
const inteiro AT_EPOCAS = 4
const inteiro AT_MAX_EXEMPLOS = 10
const inteiro AT_MAX_AVAL = 32
const inteiro AT_GRADE = 16
const inteiro AT_UNIDADE = 256
const inteiro AT_DIV_W = 2048
const inteiro AT_DIV_B = 128
const inteiro AT_CONF = 625

// Modos de atencao. MODO_APRENDIDA usa a[4] e beta[3]; os demais sao
// baselines fixos e nunca sao chamados de atencao treinada.
const inteiro AT_MODO_APRENDIDA = 0
const inteiro AT_MODO_UNIFORME = 1
const inteiro AT_MODO_RECENCIA = 2

// Codigos de erro (precedencia 1, 2, 6, 3, 4, 5).
const inteiro AT_ERR_N = 1
const inteiro AT_ERR_ID = 2
const inteiro AT_ERR_PARAMS = 3
const inteiro AT_ERR_EPOCAS = 4
const inteiro AT_ERR_INTERNO = 5
const inteiro AT_ERR_MODO = 6

funcao inteiro at_abs(inteiro v)
{
    se (v < 0)
    {
        retorne 0 - v
    }
    retorne v
}

funcao logico at_id_valido(inteiro id)
{
    se (id >= 0 e id <= 24)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico at_n_valido(inteiro n)
{
    se (n >= 1 e n <= AT_T)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico at_modo_valido(inteiro modo)
{
    se (modo >= 0 e modo <= 2)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico at_seq_valida(inteiro ids[], inteiro n)
{
    se (nao at_n_valido(n))
    {
        retorne falso
    }
    inteiro i = 0
    enquanto (i < n)
    {
        se (nao at_id_valido(ids[i]))
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

// Verdadeiro se |a|, |beta|, |w|, |b| <= AT_LIMITE.
funcao logico at_params_validos(inteiro a[], inteiro beta[], inteiro w[], inteiro b[])
{
    inteiro i = 0
    enquanto (i < AT_D)
    {
        se (at_abs(a[i]) > AT_LIMITE)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < AT_T)
    {
        se (at_abs(beta[i]) > AT_LIMITE)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < AT_TOTAL_W)
    {
        se (at_abs(w[i]) > AT_LIMITE)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < AT_TOTAL_B)
    {
        se (at_abs(b[i]) > AT_LIMITE)
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

// r(num,den) = sinal(num) * floor((|num| + den/2) / den), den > 0.
// A divisao inteira do Portugol trunca em direcao a zero; o sinal e aplicado
// depois do piso, entao o resultado e o mesmo em O1/O2/O3 e no oraculo.
funcao inteiro at_div_arredondada(inteiro numerador, inteiro denominador)
{
    se (denominador <= 0)
    {
        retorne 0
    }
    inteiro sinal = 1
    inteiro n = numerador
    se (n < 0)
    {
        sinal = 0 - 1
        n = 0 - n
    }
    retorne sinal * ((n + denominador / 2) / denominador)
}

// e16(id,d) = ((id*7 + d*3) % 32) - 16, formula congelada da M3/M7.
funcao inteiro at_e16(inteiro id, inteiro dimensao)
{
    retorne ((id * 7 + dimensao * 3) % 32) - 16
}

// Mascara causal: a chave j so e visivel para a consulta i quando j <= i.
funcao logico at_escopo(inteiro i, inteiro j)
{
    se (j <= i)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Escore aditivo s(i,j). Fora da mascara o valor e zero e nao e usado.
funcao inteiro at_score(inteiro a[], inteiro beta[], inteiro ids[],
                        inteiro i, inteiro j)
{
    se (nao at_escopo(i, j))
    {
        retorne 0
    }
    inteiro soma = 0
    inteiro d = 0
    enquanto (d < AT_D)
    {
        soma = soma + a[d] * at_e16(ids[j], d)
        d = d + 1
    }
    retorne soma + beta[j]
}

// Peso nao normalizado u(i,j) por modo. Uniforme usa 1; recencia usa 2^j;
// aprendida usa ReLU do escore. Fora da mascara u = 0.
funcao inteiro at_peso(inteiro a[], inteiro beta[], inteiro ids[],
                       inteiro i, inteiro j, inteiro modo)
{
    se (nao at_escopo(i, j))
    {
        retorne 0
    }
    se (modo == AT_MODO_UNIFORME)
    {
        retorne 1
    }
    se (modo == AT_MODO_RECENCIA)
    {
        inteiro p = 1
        inteiro k = 0
        enquanto (k < j)
        {
            p = p * 2
            k = k + 1
        }
        retorne p
    }
    inteiro s = at_score(a, beta, ids, i, j)
    se (s < 0)
    {
        retorne 0
    }
    retorne s
}

// Preenche u[0..i] e permil[0..i]; retorna U (soma dos u). Sem validacao.
funcao inteiro at_pesos_interno(inteiro a[], inteiro beta[], inteiro ids[],
                                inteiro i, inteiro modo,
                                inteiro u[], inteiro permil[])
{
    inteiro U = 0
    inteiro j = 0
    enquanto (j <= i)
    {
        u[j] = at_peso(a, beta, ids, i, j, modo)
        U = U + u[j]
        j = j + 1
    }
    j = 0
    enquanto (j <= i)
    {
        se (U > 0)
        {
            permil[j] = at_div_arredondada(1000 * u[j], U)
        }
        senao
        {
            permil[j] = at_div_arredondada(1000, i + 1)
        }
        j = j + 1
    }
    retorne U
}

// Contexto c[4] da consulta i, sem validacao. Retorna U.
funcao inteiro at_ctx_interno(inteiro a[], inteiro beta[], inteiro ids[],
                              inteiro i, inteiro modo, inteiro c[])
{
    inteiro u[3]
    inteiro permil[3]
    inteiro U = at_pesos_interno(a, beta, ids, i, modo, u, permil)
    inteiro d = 0
    enquanto (d < AT_D)
    {
        se (U > 0)
        {
            inteiro num = 0
            inteiro j = 0
            enquanto (j <= i)
            {
                num = num + u[j] * at_e16(ids[j], d)
                j = j + 1
            }
            c[d] = at_div_arredondada(num, U)
        }
        senao
        {
            // Fallback uniforme: media simples dos embeddings visiveis.
            inteiro soma = 0
            inteiro j2 = 0
            enquanto (j2 <= i)
            {
                soma = soma + at_e16(ids[j2], d)
                j2 = j2 + 1
            }
            c[d] = at_div_arredondada(soma, i + 1)
        }
        d = d + 1
    }
    retorne U
}

// Contexto da ultima posicao visivel: consulta i = n - 1.
funcao inteiro at_contexto_final(inteiro a[], inteiro beta[], inteiro ids[],
                                 inteiro n, inteiro modo, inteiro c[])
{
    retorne at_ctx_interno(a, beta, ids, n - 1, modo, c)
}

funcao inteiro at_pesos(inteiro a[], inteiro beta[], inteiro ids[],
                        inteiro n, inteiro i, inteiro modo,
                        inteiro u[], inteiro permil[])
{
    se (nao at_n_valido(n))
    {
        retorne 0 - AT_ERR_N
    }
    se (nao at_seq_valida(ids, n))
    {
        retorne 0 - AT_ERR_ID
    }
    se (nao at_modo_valido(modo))
    {
        retorne 0 - AT_ERR_MODO
    }
    se (i < 0 ou i >= n)
    {
        retorne 0 - AT_ERR_N
    }
    retorne at_pesos_interno(a, beta, ids, i, modo, u, permil)
}

funcao inteiro at_contexto(inteiro a[], inteiro beta[], inteiro ids[],
                           inteiro n, inteiro i, inteiro modo, inteiro c[])
{
    se (nao at_n_valido(n))
    {
        retorne AT_ERR_N
    }
    se (nao at_seq_valida(ids, n))
    {
        retorne AT_ERR_ID
    }
    se (nao at_modo_valido(modo))
    {
        retorne AT_ERR_MODO
    }
    se (i < 0 ou i >= n)
    {
        retorne AT_ERR_N
    }
    at_ctx_interno(a, beta, ids, i, modo, c)
    retorne 0
}

// Z256(c,y) = sum_d w[y*4+d]*c[d] + 16*b[y].
funcao inteiro at_z256(inteiro w[], inteiro b[], inteiro c[], inteiro y)
{
    inteiro soma = 0
    inteiro d = 0
    enquanto (d < AT_D)
    {
        soma = soma + w[y * AT_D + d] * c[d]
        d = d + 1
    }
    retorne soma + AT_GRADE * b[y]
}

funcao inteiro at_delta256(inteiro w[], inteiro b[], inteiro c[],
                           inteiro y, inteiro alvo)
{
    inteiro z = at_z256(w, b, c, y)
    se (y == alvo)
    {
        retorne z - AT_UNIDADE
    }
    retorne z
}

// Argmax normativo: inicializa em 0 e usa comparacao estrita (empate: menor y).
funcao inteiro at_argmax(inteiro w[], inteiro b[], inteiro c[])
{
    inteiro melhor = 0
    inteiro melhor_valor = at_z256(w, b, c, 0)
    inteiro y = 1
    enquanto (y < AT_V)
    {
        inteiro valor = at_z256(w, b, c, y)
        se (valor > melhor_valor)
        {
            melhor_valor = valor
            melhor = y
        }
        y = y + 1
    }
    retorne melhor
}

funcao inteiro at_perda_interna(inteiro w[], inteiro b[], inteiro a[],
                                inteiro beta[], inteiro entradas[],
                                inteiro alvos[], inteiro n, inteiro modo)
{
    inteiro c[4]
    inteiro soma = 0
    inteiro ex = 0
    enquanto (ex < n)
    {
        inteiro ids[3]
        ids[0] = entradas[ex * 3]
        ids[1] = entradas[ex * 3 + 1]
        ids[2] = entradas[ex * 3 + 2]
        at_ctx_interno(a, beta, ids, 2, modo, c)
        inteiro y = 0
        enquanto (y < AT_V)
        {
            inteiro delta = at_delta256(w, b, c, y, alvos[ex])
            soma = soma + delta * delta
            y = y + 1
        }
        ex = ex + 1
    }
    retorne soma
}

funcao inteiro at_validar(inteiro a[], inteiro beta[], inteiro w[], inteiro b[],
                          inteiro entradas[], inteiro alvos[], inteiro n,
                          inteiro modo, inteiro epocas)
{
    se (n < 1 ou n > AT_MAX_EXEMPLOS)
    {
        retorne AT_ERR_N
    }
    inteiro i = 0
    enquanto (i < n * 3)
    {
        se (nao at_id_valido(entradas[i]))
        {
            retorne AT_ERR_ID
        }
        i = i + 1
    }
    i = 0
    enquanto (i < n)
    {
        se (nao at_id_valido(alvos[i]))
        {
            retorne AT_ERR_ID
        }
        i = i + 1
    }
    se (nao at_modo_valido(modo))
    {
        retorne AT_ERR_MODO
    }
    se (nao at_params_validos(a, beta, w, b))
    {
        retorne AT_ERR_PARAMS
    }
    se (epocas < 1 ou epocas > AT_RODADAS)
    {
        retorne AT_ERR_EPOCAS
    }
    retorne 0
}

// Perda L = sum_e sum_y delta256(c_e,y)^2. saida[0] recebe L.
funcao inteiro at_perda(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                        inteiro entradas[], inteiro alvos[], inteiro n,
                        inteiro modo, inteiro saida[])
{
    inteiro codigo = at_validar(a, beta, w, b, entradas, alvos, n, modo, 1)
    se (codigo != 0)
    {
        retorne codigo
    }
    saida[0] = at_perda_interna(w, b, a, beta, entradas, alvos, n, modo)
    retorne 0
}

// Uma epoca da regra delta da M7 sobre a leitura 4 -> 25, exemplo a exemplo
// em ordem fixa. deltas congelados antes de qualquer escrita. Retorna 0 ou 5.
funcao inteiro at_treinar_afim(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                               inteiro entradas[], inteiro alvos[], inteiro n,
                               inteiro modo, inteiro epocas)
{
    inteiro codigo = at_validar(a, beta, w, b, entradas, alvos, n, modo, epocas)
    se (codigo != 0)
    {
        retorne codigo
    }
    inteiro c[4]
    inteiro delta[25]
    inteiro ep = 1
    enquanto (ep <= epocas)
    {
        inteiro ex = 0
        enquanto (ex < n)
        {
            inteiro ids[3]
            ids[0] = entradas[ex * 3]
            ids[1] = entradas[ex * 3 + 1]
            ids[2] = entradas[ex * 3 + 2]
            at_ctx_interno(a, beta, ids, 2, modo, c)

            inteiro y = 0
            enquanto (y < AT_V)
            {
                delta[y] = at_delta256(w, b, c, y, alvos[ex])
                y = y + 1
            }

            y = 0
            enquanto (y < AT_V)
            {
                inteiro d = 0
                enquanto (d < AT_D)
                {
                    inteiro novo = at_div_arredondada(
                        AT_DIV_W * w[y * AT_D + d] - delta[y] * c[d], AT_DIV_W)
                    w[y * AT_D + d] = novo
                    se (at_abs(novo) > AT_LIMITE)
                    {
                        retorne AT_ERR_INTERNO
                    }
                    d = d + 1
                }
                inteiro novo_b = at_div_arredondada(AT_DIV_B * b[y] - delta[y], AT_DIV_B)
                b[y] = novo_b
                se (at_abs(novo_b) > AT_LIMITE)
                {
                    retorne AT_ERR_INTERNO
                }
                y = y + 1
            }
            ex = ex + 1
        }
        ep = ep + 1
    }
    retorne 0
}

// Desempate canonico da busca coordenada: menor |v|, depois menor v.
funcao logico at_desempate(inteiro v, inteiro melhor)
{
    se (at_abs(v) < at_abs(melhor))
    {
        retorne verdadeiro
    }
    se (at_abs(v) == at_abs(melhor) e v < melhor)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Inicializacao canonica apenas da leitura 4 -> 25 (sem tocar em a/beta).
funcao at_init_leitura(inteiro w[], inteiro b[])
{
    inteiro y = 0
    enquanto (y < AT_V)
    {
        inteiro k = 0
        enquanto (k < AT_D)
        {
            w[y * AT_D + k] = ((y * 7 + k * 3) % 9) - 4
            k = k + 1
        }
        b[y] = 0
        y = y + 1
    }
}

// Reajuste deterministico da leitura para uma configuracao de atencao:
// reinicia w,b pela formula canonica e aplica AT_EPOCAS epocas da regra delta.
// Torna a perda uma funcao deterministica de (a,beta), sem depender do caminho.
funcao inteiro at_ajustar_leitura(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                                  inteiro entradas[], inteiro alvos[], inteiro n,
                                  inteiro modo)
{
    at_init_leitura(w, b)
    retorne at_treinar_afim(w, b, a, beta, entradas, alvos, n, modo, AT_EPOCAS)
}

// Uma varredura coordenada completa sobre a[0..3], beta[0..2], em ordem fixa.
// Para cada candidato, w,b sao reajustados do zero com a mesma regra delta;
// a perda avaliada e a do modelo treinado, nao a de pesos congelados. Aceita
// um valor somente se a perda for estritamente menor. Retorna o numero de
// parametros alterados (0..7) ou -AT_ERR_INTERNO.
funcao inteiro at_varredura(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                            inteiro entradas[], inteiro alvos[], inteiro n,
                            inteiro modo)
{
    se (modo != AT_MODO_APRENDIDA)
    {
        retorne 0
    }
    inteiro alteracoes = 0
    inteiro codigo = at_ajustar_leitura(w, b, a, beta, entradas, alvos, n, modo)
    se (codigo != 0)
    {
        retorne 0 - codigo
    }
    inteiro base = at_perda_interna(w, b, a, beta, entradas, alvos, n, modo)
    inteiro idx = 0
    enquanto (idx < 7)
    {
        inteiro atual = 0
        se (idx < 4)
        {
            atual = a[idx]
        }
        senao
        {
            atual = beta[idx - 4]
        }

        inteiro melhor_v = atual
        inteiro melhor_l = base
        inteiro v = 0 - AT_LIMITE
        enquanto (v <= AT_LIMITE)
        {
            se (idx < 4)
            {
                a[idx] = v
            }
            senao
            {
                beta[idx - 4] = v
            }
            codigo = at_ajustar_leitura(w, b, a, beta, entradas, alvos, n, modo)
            se (codigo != 0)
            {
                retorne 0 - codigo
            }
            inteiro l = at_perda_interna(w, b, a, beta, entradas, alvos, n, modo)
            se (l < melhor_l)
            {
                melhor_l = l
                melhor_v = v
            }
            senao se (l == melhor_l e at_desempate(v, melhor_v))
            {
                melhor_v = v
            }
            v = v + 1
        }

        se (idx < 4)
        {
            a[idx] = atual
        }
        senao
        {
            beta[idx - 4] = atual
        }
        codigo = at_ajustar_leitura(w, b, a, beta, entradas, alvos, n, modo)
        se (codigo != 0)
        {
            retorne 0 - codigo
        }

        se (melhor_l < base)
        {
            se (idx < 4)
            {
                a[idx] = melhor_v
            }
            senao
            {
                beta[idx - 4] = melhor_v
            }
            codigo = at_ajustar_leitura(w, b, a, beta, entradas, alvos, n, modo)
            se (codigo != 0)
            {
                retorne 0 - codigo
            }
            base = melhor_l
            alteracoes = alteracoes + 1
        }
        idx = idx + 1
    }
    retorne alteracoes
}

// Treino alternado. hist[0..rodadas] = perda no inicio de cada rodada
// (hist[0] = L inicial) e info[0] = rodadas executadas, info[1] = alteracoes
// de atencao, info[2] = 1 se convergiu (varredura sem alteracao) ou 0.
funcao inteiro at_treinar(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                          inteiro entradas[], inteiro alvos[], inteiro n,
                          inteiro modo, inteiro hist[], inteiro info[])
{
    inteiro codigo = at_validar(a, beta, w, b, entradas, alvos, n, modo, AT_EPOCAS)
    se (codigo != 0)
    {
        retorne codigo
    }

    inteiro w0[100]
    inteiro b0[25]
    inteiro a0[4]
    inteiro beta0[3]

    hist[0] = at_perda_interna(w, b, a, beta, entradas, alvos, n, modo)
    info[0] = 0
    info[1] = 0
    info[2] = 0

    inteiro rodada = 1
    logico parar = falso
    enquanto (rodada <= AT_RODADAS e nao parar)
    {
        inteiro i = 0
        enquanto (i < AT_TOTAL_W)
        {
            w0[i] = w[i]
            i = i + 1
        }
        i = 0
        enquanto (i < AT_TOTAL_B)
        {
            b0[i] = b[i]
            i = i + 1
        }
        i = 0
        enquanto (i < AT_D)
        {
            a0[i] = a[i]
            i = i + 1
        }
        i = 0
        enquanto (i < AT_T)
        {
            beta0[i] = beta[i]
            i = i + 1
        }

        inteiro inicial = hist[rodada - 1]
        codigo = at_treinar_afim(w, b, a, beta, entradas, alvos, n, modo, AT_EPOCAS)
        se (codigo != 0)
        {
            retorne codigo
        }

        inteiro mudou = at_varredura(w, b, a, beta, entradas, alvos, n, modo)
        se (mudou < 0)
        {
            retorne 0 - mudou
        }

        inteiro atual = at_perda_interna(w, b, a, beta, entradas, alvos, n, modo)
        se (atual > inicial)
        {
            i = 0
            enquanto (i < AT_TOTAL_W)
            {
                w[i] = w0[i]
                i = i + 1
            }
            i = 0
            enquanto (i < AT_TOTAL_B)
            {
                b[i] = b0[i]
                i = i + 1
            }
            i = 0
            enquanto (i < AT_D)
            {
                a[i] = a0[i]
                i = i + 1
            }
            i = 0
            enquanto (i < AT_T)
            {
                beta[i] = beta0[i]
                i = i + 1
            }
            hist[rodada] = inicial
            parar = verdadeiro
        }
        senao
        {
            hist[rodada] = atual
            info[0] = rodada
            info[1] = info[1] + mudou
            se (modo == AT_MODO_APRENDIDA e mudou == 0)
            {
                info[2] = 1
                parar = verdadeiro
            }
            rodada = rodada + 1
        }
    }
    retorne 0
}

// Inicializacao canonica: atencao uniforme (a = beta = 0) e leitura em
// [-4,4]. Nao le o estado anterior.
funcao at_inicializar(inteiro a[], inteiro beta[], inteiro w[], inteiro b[])
{
    inteiro d = 0
    enquanto (d < AT_D)
    {
        a[d] = 0
        d = d + 1
    }
    inteiro j = 0
    enquanto (j < AT_T)
    {
        beta[j] = 0
        j = j + 1
    }
    inteiro y = 0
    enquanto (y < AT_V)
    {
        inteiro k = 0
        enquanto (k < AT_D)
        {
            w[y * AT_D + k] = ((y * 7 + k * 3) % 9) - 4
            k = k + 1
        }
        b[y] = 0
        y = y + 1
    }
}

funcao inteiro at_acertos(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                          inteiro entradas[], inteiro alvos[], inteiro n,
                          inteiro modo)
{
    se (n < 1 ou n > AT_MAX_AVAL)
    {
        retorne 0 - AT_ERR_N
    }
    inteiro c[4]
    inteiro total = 0
    inteiro ex = 0
    enquanto (ex < n)
    {
        inteiro ids[3]
        ids[0] = entradas[ex * 3]
        ids[1] = entradas[ex * 3 + 1]
        ids[2] = entradas[ex * 3 + 2]
        at_ctx_interno(a, beta, ids, 2, modo, c)
        se (at_argmax(w, b, c) == alvos[ex])
        {
            total = total + 1
        }
        ex = ex + 1
    }
    retorne total
}

// Conta acertos de exemplos cujo tipo[] == filtro (-1 = todos).
funcao inteiro at_acertos_tipo(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                               inteiro entradas[], inteiro alvos[], inteiro tipo[],
                               inteiro n, inteiro modo, inteiro filtro)
{
    inteiro c[4]
    inteiro total = 0
    inteiro ex = 0
    enquanto (ex < n)
    {
        se (filtro < 0 ou tipo[ex] == filtro)
        {
            inteiro ids[3]
            ids[0] = entradas[ex * 3]
            ids[1] = entradas[ex * 3 + 1]
            ids[2] = entradas[ex * 3 + 2]
            at_ctx_interno(a, beta, ids, 2, modo, c)
            se (at_argmax(w, b, c) == alvos[ex])
            {
                total = total + 1
            }
        }
        ex = ex + 1
    }
    retorne total
}

funcao inteiro at_bp(inteiro acertos, inteiro n)
{
    se (n < 1 ou n > AT_MAX_AVAL ou acertos < 0 ou acertos > n)
    {
        retorne 0 - 1
    }
    retorne at_div_arredondada(10000 * acertos, n)
}

// Margem = Z(alvo) - max_{y != alvo} Z(y).
funcao inteiro at_margem(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                         inteiro ids[], inteiro n, inteiro modo, inteiro alvo)
{
    inteiro c[4]
    at_ctx_interno(a, beta, ids, n - 1, modo, c)
    inteiro melhor = 0
    logico tem = falso
    inteiro y = 0
    enquanto (y < AT_V)
    {
        se (y != alvo)
        {
            inteiro valor = at_z256(w, b, c, y)
            se (nao tem ou valor > melhor)
            {
                melhor = valor
                tem = verdadeiro
            }
        }
        y = y + 1
    }
    retorne at_z256(w, b, c, alvo) - melhor
}

// Media arredondada da margem sobre os exemplos (todos os tipos).
funcao inteiro at_margem_media(inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                               inteiro entradas[], inteiro alvos[], inteiro n,
                               inteiro modo)
{
    inteiro soma = 0
    inteiro ex = 0
    enquanto (ex < n)
    {
        inteiro ids[3]
        ids[0] = entradas[ex * 3]
        ids[1] = entradas[ex * 3 + 1]
        ids[2] = entradas[ex * 3 + 2]
        soma = soma + at_margem(w, b, a, beta, ids, 3, modo, alvos[ex])
        ex = ex + 1
    }
    retorne at_div_arredondada(soma, n)
}

// Checksum linear do estado completo. |checksum| <= 86256.
funcao inteiro at_checksum(inteiro a[], inteiro beta[], inteiro w[], inteiro b[])
{
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < AT_D)
    {
        soma = soma + (i + 1) * a[i]
        i = i + 1
    }
    i = 0
    enquanto (i < AT_T)
    {
        soma = soma + (i + 1) * beta[i]
        i = i + 1
    }
    i = 0
    enquanto (i < AT_TOTAL_W)
    {
        soma = soma + (i + 1) * w[i]
        i = i + 1
    }
    i = 0
    enquanto (i < AT_TOTAL_B)
    {
        soma = soma + (i + 1) * b[i]
        i = i + 1
    }
    retorne soma
}

// ---------------- Impressao (ASCII, LF, sem real) ----------------

funcao at_imprimir_estado(inteiro a[], inteiro beta[], inteiro w[], inteiro b[])
{
    inteiro d = 0
    enquanto (d < AT_D)
    {
        escreva("PESO a ", d, " ", a[d], "\n")
        d = d + 1
    }
    inteiro j = 0
    enquanto (j < AT_T)
    {
        escreva("PESO beta ", j, " ", beta[j], "\n")
        j = j + 1
    }
}

funcao at_imprimir_pesos(inteiro a[], inteiro beta[], inteiro ids[],
                         inteiro n, inteiro i, inteiro modo)
{
    inteiro u[3]
    inteiro permil[3]
    inteiro j = 0
    enquanto (j < AT_T)
    {
        u[j] = 0
        permil[j] = 0
        j = j + 1
    }
    at_pesos_interno(a, beta, ids, i, modo, u, permil)
    j = 0
    enquanto (j < AT_T)
    {
        inteiro s = 0
        inteiro permitido = 0
        se (j <= i e j < n)
        {
            s = at_score(a, beta, ids, i, j)
            permitido = 1
        }
        escreva("AT ", i, " ", j, " ", s, " ", u[j], " ", permil[j], " ", permitido, "\n")
        j = j + 1
    }
}

funcao at_imprimir_ex(cadeia estado, cadeia conjunto,
                      inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                      inteiro entradas[], inteiro alvos[], inteiro tipo[],
                      inteiro n, inteiro modo, inteiro filtro)
{
    inteiro c[4]
    inteiro ex = 0
    enquanto (ex < n)
    {
        se (filtro < 0 ou tipo[ex] == filtro)
        {
            inteiro ids[3]
            ids[0] = entradas[ex * 3]
            ids[1] = entradas[ex * 3 + 1]
            ids[2] = entradas[ex * 3 + 2]
            at_ctx_interno(a, beta, ids, 2, modo, c)
            inteiro pred = at_argmax(w, b, c)
            escreva("EX ", estado, " ", conjunto, " ", ex, " ", ids[0], " ",
                    ids[1], " ", ids[2], " ", alvos[ex], " ", pred, " ")
            se (pred == alvos[ex])
            {
                escreva("1\n")
            }
            senao
            {
                escreva("0\n")
            }
        }
        ex = ex + 1
    }
}

funcao at_imprimir_conf(cadeia estado, cadeia conjunto,
                        inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                        inteiro entradas[], inteiro alvos[], inteiro tipo[],
                        inteiro n, inteiro modo, inteiro filtro)
{
    inteiro conf[625]
    inteiro i = 0
    enquanto (i < AT_CONF)
    {
        conf[i] = 0
        i = i + 1
    }
    inteiro c[4]
    inteiro ex = 0
    enquanto (ex < n)
    {
        se (filtro < 0 ou tipo[ex] == filtro)
        {
            inteiro ids[3]
            ids[0] = entradas[ex * 3]
            ids[1] = entradas[ex * 3 + 1]
            ids[2] = entradas[ex * 3 + 2]
            at_ctx_interno(a, beta, ids, 2, modo, c)
            inteiro pred = at_argmax(w, b, c)
            conf[alvos[ex] * AT_V + pred] = conf[alvos[ex] * AT_V + pred] + 1
        }
        ex = ex + 1
    }
    inteiro alvo = 0
    enquanto (alvo < AT_V)
    {
        inteiro pred = 0
        enquanto (pred < AT_V)
        {
            se (conf[alvo * AT_V + pred] > 0)
            {
                escreva("CONF ", estado, " ", conjunto, " ", alvo, " ",
                        pred, " ", conf[alvo * AT_V + pred], "\n")
            }
            pred = pred + 1
        }
        alvo = alvo + 1
    }
}

funcao inteiro at_relatorio(cadeia estado, cadeia conjunto,
                            inteiro w[], inteiro b[], inteiro a[], inteiro beta[],
                            inteiro entradas[], inteiro alvos[], inteiro tipo[],
                            inteiro n, inteiro modo, inteiro filtro)
{
    inteiro c[4]
    inteiro conta = 0
    inteiro acertos = 0
    inteiro perda = 0
    inteiro ex = 0
    enquanto (ex < n)
    {
        se (filtro < 0 ou tipo[ex] == filtro)
        {
            inteiro ids[3]
            ids[0] = entradas[ex * 3]
            ids[1] = entradas[ex * 3 + 1]
            ids[2] = entradas[ex * 3 + 2]
            at_ctx_interno(a, beta, ids, 2, modo, c)
            se (at_argmax(w, b, c) == alvos[ex])
            {
                acertos = acertos + 1
            }
            inteiro y = 0
            enquanto (y < AT_V)
            {
                inteiro delta = at_delta256(w, b, c, y, alvos[ex])
                perda = perda + delta * delta
                y = y + 1
            }
            conta = conta + 1
        }
        ex = ex + 1
    }
    escreva("RESUMO ", estado, " ", conjunto, " ", conta, " ",
            acertos, " ", at_bp(acertos, conta), " ", perda, "\n")
    at_imprimir_ex(estado, conjunto, w, b, a, beta, entradas, alvos, tipo, n, modo, filtro)
    at_imprimir_conf(estado, conjunto, w, b, a, beta, entradas, alvos, tipo, n, modo, filtro)
    retorne 0
}

// ---------------- Limites e casos extremos ----------------

funcao inteiro at_limites()
{
    escreva("LIMITES MAXS ", 4 * AT_LIMITE * AT_LIMITE + AT_LIMITE, "\n")
    escreva("LIMITES MAXU ", AT_T * (4 * AT_LIMITE * AT_LIMITE + AT_LIMITE), "\n")
    escreva("LIMITES MAXNUM ", AT_T * (4 * AT_LIMITE * AT_LIMITE + AT_LIMITE) * AT_LIMITE, "\n")
    escreva("LIMITES MAXZ ", 4 * AT_LIMITE * AT_LIMITE + AT_GRADE * AT_LIMITE, "\n")
    escreva("LIMITES MAXDELTA ", 4 * AT_LIMITE * AT_LIMITE + AT_GRADE * AT_LIMITE + AT_UNIDADE, "\n")
    escreva("LIMITES MAXPERDA ",
            25 * AT_MAX_EXEMPLOS *
            (4 * AT_LIMITE * AT_LIMITE + AT_GRADE * AT_LIMITE + AT_UNIDADE) *
            (4 * AT_LIMITE * AT_LIMITE + AT_GRADE * AT_LIMITE + AT_UNIDADE), "\n")

    inteiro a[4]
    inteiro beta[3]
    inteiro w[100]
    inteiro b[25]
    inteiro i = 0
    enquanto (i < 4)
    {
        a[i] = AT_LIMITE
        i = i + 1
    }
    i = 0
    enquanto (i < 3)
    {
        beta[i] = AT_LIMITE
        i = i + 1
    }
    i = 0
    enquanto (i < 100)
    {
        w[i] = AT_LIMITE
        i = i + 1
    }
    i = 0
    enquanto (i < 25)
    {
        b[i] = AT_LIMITE
        i = i + 1
    }
    inteiro ids[3]
    ids[0] = 24
    ids[1] = 24
    ids[2] = 24
    inteiro c[4]
    inteiro U = at_ctx_interno(a, beta, ids, 2, AT_MODO_APRENDIDA, c)
    escreva("LIMITES EXTREMO ", U, " ", c[0], " ", c[1], " ", c[2], " ", c[3], " ",
            at_z256(w, b, c, 0), " ", at_checksum(a, beta, w, b), "\n")

    inteiro u[3]
    inteiro permil[3]
    inteiro n0[3]
    n0[0] = 1
    n0[1] = 2
    n0[2] = 5
    escreva("LIMITES N0 ", 0 - at_pesos(a, beta, n0, 0, 0, 0, u, permil), "\n")
    escreva("LIMITES N4 ", 0 - at_pesos(a, beta, n0, 4, 0, 0, u, permil), "\n")
    inteiro idruim[3]
    idruim[0] = 1
    idruim[1] = 25
    idruim[2] = 2
    escreva("LIMITES ID ", 0 - at_pesos(a, beta, idruim, 3, 0, 0, u, permil), "\n")
    inteiro aruim[4]
    aruim[0] = 17
    aruim[1] = 0
    aruim[2] = 0
    aruim[3] = 0
    escreva("LIMITES PARAM ", at_validar(aruim, beta, w, b, n0, n0, 1, 0, 4), "\n")
    escreva("LIMITES EPOCAS ", at_validar(a, beta, w, b, n0, n0, 1, 0, 0), "\n")
    escreva("LIMITES MODO ", at_validar(a, beta, w, b, n0, n0, 1, 3, 4), "\n")
    retorne 0
}
