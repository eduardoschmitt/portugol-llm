// ---------------------------------------------------------------------------
// Fragmento do contexto de multiplos tokens (M7, spec v1.0.0).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-context-tests.ps1 concatena este fragmento a um driver.
// Fonte ASCII puro por contrato. Sem bibliotecas, tempo ou aleatoriedade.
//
// Estado: inteiro w16[300] (W[y][k][d] em y*12 + k*4 + d) e inteiro b16[25]
// (b[y]), ambos em unidades de 1/16. Contexto c16[12] = concatenacao de K=3
// embeddings, do mais antigo (k=0) para o mais recente (k=2), com
// preenchimento zero a esquerda. Nenhum real no caminho quente.
//
// Uma camada afim 12 -> 25, 325 parametros, sem camada oculta, ativacao,
// normalizacao ou softmax. Embeddings congelados: ctx_e16 recalcula a
// formula da M3. Nenhuma funcao de M1-M6 e chamada por este fragmento.
// ---------------------------------------------------------------------------

const inteiro CTX_K = 3
const inteiro CTX_TAM_VOCAB = 25
const inteiro CTX_DIM = 4
const inteiro CTX_ENTRADAS = 12
const inteiro CTX_TOTAL_W = 300
const inteiro CTX_TOTAL_B = 25
const inteiro CTX_PARAMS = 325
const inteiro CTX_MAX_EXEMPLOS = 6
const inteiro CTX_MAX_EPOCAS = 32
const inteiro CTX_GRADE = 16
const inteiro CTX_ESCALA_PERDA = 131072
const inteiro CTX_LIMITE = 16
const inteiro CTX_TAXA_NUM = 1
const inteiro CTX_TAXA_DEN = 8
const inteiro CTX_DIV_W = 2048
const inteiro CTX_DIV_B = 128
const inteiro CTX_EPOCAS = 7
const inteiro CTX_TOKENS_MAX = 64

// Valor absoluto sem biblioteca. Pre-condicao: v > -2147483648.
funcao inteiro ctx_abs(inteiro v)
{
    se (v < 0)
    {
        retorne 0 - v
    }
    retorne v
}

// Valida o ID de token. 0 (UNK) e valido; 25.. e inexistente.
funcao logico ctx_id_valido(inteiro id)
{
    se (id >= 0 e id < CTX_TAM_VOCAB)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico ctx_n_valido(inteiro n)
{
    se (n >= 1 e n <= CTX_MAX_EXEMPLOS)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico ctx_epocas_validas(inteiro epocas)
{
    se (epocas >= 1 e epocas <= CTX_MAX_EPOCAS)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico ctx_maximo_valido(inteiro maximo)
{
    se (maximo >= 1 e maximo <= CTX_TOKENS_MAX)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Verdadeiro se todos os 325 parametros respeitam |v| <= limite.
funcao logico ctx_params_no_limite(inteiro w16[], inteiro b16[], inteiro limite)
{
    inteiro i = 0
    enquanto (i < CTX_TOTAL_W)
    {
        se (ctx_abs(w16[i]) > limite)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < CTX_TOTAL_B)
    {
        se (ctx_abs(b16[i]) > limite)
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

funcao logico ctx_params_validos(inteiro w16[], inteiro b16[])
{
    retorne ctx_params_no_limite(w16, b16, CTX_LIMITE)
}

// Prefixo de geracao: 1..3 IDs em 0..24; pare (24) so na ultima posicao.
funcao logico ctx_prefixo_valido(inteiro prefixo[], inteiro n_prefixo)
{
    se (n_prefixo < 1 ou n_prefixo > CTX_K)
    {
        retorne falso
    }

    inteiro i = 0
    enquanto (i < n_prefixo)
    {
        se (nao ctx_id_valido(prefixo[i]))
        {
            retorne falso
        }
        i = i + 1
    }

    i = 0
    enquanto (i < n_prefixo - 1)
    {
        se (prefixo[i] == 24)
        {
            retorne falso
        }
        i = i + 1
    }

    retorne verdadeiro
}

// e16(id,d) = ((id*7 + d*3) % 32) - 16, formula congelada da M3.
funcao inteiro ctx_e16(inteiro id, inteiro dimensao)
{
    retorne ((id * 7 + dimensao * 3) % 32) - 16
}

// Monta c16 a partir dos ultimos K tokens de historico[0..n-1].
// Pre-condicao: 1 <= n <= 64. Preenchimento zero a esquerda, sem ler
// posicoes negativas e sem confundir PAD com UNK.
funcao ctx_montar_contexto(inteiro historico[], inteiro n, inteiro c16[])
{
    inteiro k = 0
    enquanto (k < CTX_K)
    {
        inteiro d = 0
        enquanto (d < CTX_DIM)
        {
            c16[k * CTX_DIM + d] = 0
            d = d + 1
        }
        k = k + 1
    }

    k = 0
    enquanto (k < CTX_K)
    {
        inteiro posicao = n - CTX_K + k
        se (posicao >= 0)
        {
            inteiro d = 0
            enquanto (d < CTX_DIM)
            {
                c16[k * CTX_DIM + d] = ctx_e16(historico[posicao], d)
                d = d + 1
            }
        }
        k = k + 1
    }
}

// Contexto de um exemplo completo de 3 tokens: entradas[n*3 .. n*3+2].
// Pre-condicao: 0 <= n < 6 e IDs validos.
funcao ctx_contexto_de_exemplo(inteiro entradas[], inteiro n, inteiro c16[])
{
    inteiro k = 0
    enquanto (k < CTX_K)
    {
        inteiro d = 0
        enquanto (d < CTX_DIM)
        {
            c16[k * CTX_DIM + d] = ctx_e16(entradas[n * CTX_K + k], d)
            d = d + 1
        }
        k = k + 1
    }
}

// Z256(c,y) = sum_p W16[y][p]*c16[p] + 16*b16[y].
// Ordem normativa: p = 0..11 com acumulacao a partir de 0, vies por ultimo.
funcao inteiro ctx_z256(inteiro w16[], inteiro b16[], inteiro c16[], inteiro y)
{
    inteiro soma = 0
    inteiro p = 0
    enquanto (p < CTX_ENTRADAS)
    {
        soma = soma + w16[y * CTX_ENTRADAS + p] * c16[p]
        p = p + 1
    }
    soma = soma + CTX_GRADE * b16[y]
    retorne soma
}

// delta256(c,y,alvo) = Z256(c,y) - 256*[y == alvo].
funcao inteiro ctx_delta256(inteiro w16[], inteiro b16[], inteiro c16[],
                            inteiro y, inteiro alvo)
{
    inteiro z = ctx_z256(w16, b16, c16, y)
    se (y == alvo)
    {
        retorne z - CTX_GRADE * CTX_GRADE
    }
    retorne z
}

// Argmax normativo: inicializa no y=0 e usa comparacao estrita (empate: menor y).
funcao inteiro ctx_argmax(inteiro w16[], inteiro b16[], inteiro c16[])
{
    inteiro melhor = 0
    inteiro melhor_valor = ctx_z256(w16, b16, c16, 0)
    inteiro y = 1
    enquanto (y < CTX_TAM_VOCAB)
    {
        inteiro valor = ctx_z256(w16, b16, c16, y)
        se (valor > melhor_valor)
        {
            melhor_valor = valor
            melhor = y
        }
        y = y + 1
    }
    retorne melhor
}

// S = sum_{n,y} delta256(c_n,y)^2.
funcao inteiro ctx_perda_escalada(inteiro w16[], inteiro b16[],
                                  inteiro entradas[], inteiro alvos[], inteiro n)
{
    inteiro c16[12]
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < n)
    {
        ctx_contexto_de_exemplo(entradas, i, c16)
        inteiro y = 0
        enquanto (y < CTX_TAM_VOCAB)
        {
            inteiro delta = ctx_delta256(w16, b16, c16, y, alvos[i])
            soma = soma + delta * delta
            y = y + 1
        }
        i = i + 1
    }
    retorne soma
}

funcao inteiro ctx_acertos(inteiro w16[], inteiro b16[],
                           inteiro entradas[], inteiro alvos[], inteiro n)
{
    inteiro c16[12]
    inteiro total = 0
    inteiro i = 0
    enquanto (i < n)
    {
        ctx_contexto_de_exemplo(entradas, i, c16)
        se (ctx_argmax(w16, b16, c16) == alvos[i])
        {
            total = total + 1
        }
        i = i + 1
    }
    retorne total
}

// r(num,den) = sinal(num) * floor((|num| + den/2) / den).
// den e positivo e par (128 ou 2048). Meio para longe de zero.
funcao inteiro ctx_div_arredondada(inteiro numerador, inteiro denominador)
{
    inteiro sinal = 1
    se (numerador < 0)
    {
        sinal = 0 - 1
    }
    inteiro absoluto = numerador * sinal
    retorne sinal * ((absoluto + denominador / 2) / denominador)
}

// Precedencia normativa (spec secao 10.3): n, epocas, ids, parametros.
funcao inteiro ctx_validar(inteiro entradas[], inteiro alvos[],
                           inteiro n, inteiro epocas,
                           inteiro w16[], inteiro b16[])
{
    se (nao ctx_n_valido(n))
    {
        retorne 1
    }

    se (nao ctx_epocas_validas(epocas))
    {
        retorne 2
    }

    inteiro i = 0
    enquanto (i < n)
    {
        se (nao ctx_id_valido(entradas[i]) ou nao ctx_id_valido(alvos[i]))
        {
            retorne 3
        }
        i = i + 1
    }

    se (nao ctx_params_validos(w16, b16))
    {
        retorne 4
    }

    retorne 0
}

// Precedencia normativa de geracao (spec secao 10.3): prefixo, maximo, parametros.
funcao inteiro ctx_validar_geracao(inteiro w16[], inteiro b16[],
                                   inteiro prefixo[], inteiro n_prefixo,
                                   inteiro maximo)
{
    se (nao ctx_prefixo_valido(prefixo, n_prefixo))
    {
        retorne 1
    }

    se (nao ctx_maximo_valido(maximo) ou maximo < n_prefixo)
    {
        retorne 2
    }

    se (nao ctx_params_validos(w16, b16))
    {
        retorne 3
    }

    retorne 0
}

// Grava os 325 parametros canonicos, sem ler o estado anterior.
// Fatias k=0,1 zeradas; fatia k=2 igual a M5; b16 igual a M5.
funcao ctx_inicializar(inteiro w16[], inteiro b16[])
{
    inteiro y = 0
    enquanto (y < CTX_TAM_VOCAB)
    {
        inteiro k = 0
        enquanto (k < CTX_K)
        {
            inteiro d = 0
            enquanto (d < CTX_DIM)
            {
                se (k < CTX_K - 1)
                {
                    w16[y * CTX_ENTRADAS + k * CTX_DIM + d] = 0
                }
                senao
                {
                    w16[y * CTX_ENTRADAS + k * CTX_DIM + d] =
                        ((y * 7 + d * 5) % 25) - 12
                }
                d = d + 1
            }
            k = k + 1
        }
        b16[y] = ((y * 7) % 9) - 4
        y = y + 1
    }
}

// SGD por exemplo, ordem fixa n=0..5, eta = 1/8, quantizacao no novo valor.
// Valida antes de mutar. Em 1..4 nao muta nada; em 5 o estado e parcial.
funcao inteiro ctx_executar(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[],
                            inteiro n, inteiro epocas,
                            inteiro historico[])
{
    inteiro codigo = ctx_validar(entradas, alvos, n, epocas, w16, b16)
    se (codigo != 0)
    {
        retorne codigo
    }

    inteiro c16[12]
    inteiro delta[25]
    historico[0] = ctx_perda_escalada(w16, b16, entradas, alvos, n)

    inteiro ep = 1
    enquanto (ep <= epocas)
    {
        inteiro i = 0
        enquanto (i < n)
        {
            ctx_contexto_de_exemplo(entradas, i, c16)

            // Congela os 25 deltas do exemplo antes de qualquer escrita.
            inteiro y = 0
            enquanto (y < CTX_TAM_VOCAB)
            {
                delta[y] = ctx_delta256(w16, b16, c16, y, alvos[i])
                y = y + 1
            }

            y = 0
            enquanto (y < CTX_TAM_VOCAB)
            {
                inteiro p = 0
                enquanto (p < CTX_ENTRADAS)
                {
                    inteiro novo = ctx_div_arredondada(
                        CTX_DIV_W * w16[y * CTX_ENTRADAS + p]
                            - delta[y] * c16[p],
                        CTX_DIV_W)
                    w16[y * CTX_ENTRADAS + p] = novo
                    se (ctx_abs(novo) > CTX_LIMITE)
                    {
                        retorne 5
                    }
                    p = p + 1
                }

                inteiro novo_b = ctx_div_arredondada(
                    CTX_DIV_B * b16[y] - delta[y], CTX_DIV_B)
                b16[y] = novo_b
                se (ctx_abs(novo_b) > CTX_LIMITE)
                {
                    retorne 5
                }
                y = y + 1
            }
            i = i + 1
        }

        historico[ep] = ctx_perda_escalada(w16, b16, entradas, alvos, n)
        ep = ep + 1
    }

    retorne 0
}

// Gera a partir de prefixo[0..n_prefixo-1]; retorna N.
// Em erro de validacao retorna -codigo (1..3) sem escrever em saida[].
// pare (24) tem precedencia sobre o limite; UNK (0) nao e parada.
funcao inteiro ctx_gerar(inteiro w16[], inteiro b16[],
                         inteiro prefixo[], inteiro n_prefixo,
                         inteiro maximo, inteiro saida[])
{
    inteiro codigo = ctx_validar_geracao(w16, b16, prefixo, n_prefixo, maximo)
    se (codigo != 0)
    {
        retorne 0 - codigo
    }

    inteiro i = 0
    enquanto (i < n_prefixo)
    {
        saida[i] = prefixo[i]
        i = i + 1
    }

    inteiro total = n_prefixo
    se (saida[total - 1] == 24)
    {
        retorne total
    }

    inteiro c16[12]
    enquanto (total < maximo)
    {
        ctx_montar_contexto(saida, total, c16)
        inteiro proximo = ctx_argmax(w16, b16, c16)
        saida[total] = proximo
        total = total + 1
        se (proximo == 24)
        {
            retorne total
        }
    }

    retorne total
}

// Escreve apenas a palavra do ID, sem espaco e sem quebra de linha.
// Pre-condicao: 0 <= token <= 24.
funcao ctx_escrever_palavra(inteiro token)
{
    se (token == 0)
    {
        escreva("UNK")
        retorne
    }
    senao se (token == 1)
    {
        escreva("programa")
        retorne
    }
    senao se (token == 2)
    {
        escreva("funcao")
        retorne
    }
    senao se (token == 3)
    {
        escreva("inicio")
        retorne
    }
    senao se (token == 4)
    {
        escreva("inteiro")
        retorne
    }
    senao se (token == 5)
    {
        escreva("real")
        retorne
    }
    senao se (token == 6)
    {
        escreva("logico")
        retorne
    }
    senao se (token == 7)
    {
        escreva("cadeia")
        retorne
    }
    senao se (token == 8)
    {
        escreva("vazio")
        retorne
    }
    senao se (token == 9)
    {
        escreva("se")
        retorne
    }
    senao se (token == 10)
    {
        escreva("senao")
        retorne
    }
    senao se (token == 11)
    {
        escreva("enquanto")
        retorne
    }
    senao se (token == 12)
    {
        escreva("faca")
        retorne
    }
    senao se (token == 13)
    {
        escreva("para")
        retorne
    }
    senao se (token == 14)
    {
        escreva("ate")
        retorne
    }
    senao se (token == 15)
    {
        escreva("passo")
        retorne
    }
    senao se (token == 16)
    {
        escreva("retorne")
        retorne
    }
    senao se (token == 17)
    {
        escreva("escreva")
        retorne
    }
    senao se (token == 18)
    {
        escreva("leia")
        retorne
    }
    senao se (token == 19)
    {
        escreva("e")
        retorne
    }
    senao se (token == 20)
    {
        escreva("ou")
        retorne
    }
    senao se (token == 21)
    {
        escreva("nao")
        retorne
    }
    senao se (token == 22)
    {
        escreva("verdadeiro")
        retorne
    }
    senao se (token == 23)
    {
        escreva("falso")
        retorne
    }
    senao se (token == 24)
    {
        escreva("pare")
        retorne
    }
}

funcao ctx_imprimir_config()
{
    escreva("INFO=CTX ", CTX_K, " ", CTX_ENTRADAS, " ", CTX_PARAMS,
            " ", CTX_TOTAL_W, "\n")
    escreva("TAXA=", CTX_TAXA_NUM, "/", CTX_TAXA_DEN, "\n")
    escreva("GRADE=1/", CTX_GRADE, "\n")
    escreva("EPOCAS=", CTX_EPOCAS, "\n")
    escreva("ESCALA_PERDA=", CTX_ESCALA_PERDA, "\n")
    escreva("LIMITE_PARAM=", CTX_LIMITE, "\n")
    escreva("ORDEM=EXEMPLO\n")
}

// Uma unica linha. Codigos 0..4 na ordem de precedencia.
funcao ctx_imprimir_validacao(inteiro entradas[], inteiro alvos[],
                              inteiro n, inteiro epocas,
                              inteiro w16[], inteiro b16[])
{
    inteiro codigo = ctx_validar(entradas, alvos, n, epocas, w16, b16)
    se (codigo == 0)
    {
        escreva("VALIDO=OK\n")
        retorne
    }
    se (codigo == 1)
    {
        escreva("ERRO=EXEMPLOS_INVALIDOS\n")
        retorne
    }
    se (codigo == 2)
    {
        escreva("ERRO=EPOCAS_INVALIDAS\n")
        retorne
    }
    se (codigo == 3)
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }
    escreva("ERRO=PARAMETROS_INVALIDOS\n")
}

// PERDA, ACERTOS e PRED. Valida n e os ids antes de acessar os arrays.
funcao ctx_imprimir_avaliacao(inteiro w16[], inteiro b16[],
                              inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (nao ctx_n_valido(n))
    {
        escreva("ERRO=EXEMPLOS_INVALIDOS\n")
        retorne
    }

    inteiro i = 0
    enquanto (i < n)
    {
        se (nao ctx_id_valido(entradas[i]) ou nao ctx_id_valido(alvos[i]))
        {
            escreva("ERRO=ID_INVALIDO\n")
            retorne
        }
        i = i + 1
    }

    escreva("PERDA=", ctx_perda_escalada(w16, b16, entradas, alvos, n), "\n")
    escreva("ACERTOS=", ctx_acertos(w16, b16, entradas, alvos, n), "\n")
    escreva("PRED=")
    i = 0
    enquanto (i < n)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        inteiro c16[12]
        ctx_contexto_de_exemplo(entradas, i, c16)
        escreva(ctx_argmax(w16, b16, c16))
        i = i + 1
    }
    escreva("\n")
}

// HISTORICO= com epocas+1 valores inteiros.
funcao ctx_imprimir_historico(inteiro historico[], inteiro epocas)
{
    se (nao ctx_epocas_validas(epocas))
    {
        escreva("ERRO=EPOCAS_INVALIDAS\n")
        retorne
    }

    escreva("HISTORICO=")
    inteiro indice = 0
    enquanto (indice <= epocas)
    {
        se (indice > 0)
        {
            escreva(" ")
        }
        escreva(historico[indice])
        indice = indice + 1
    }
    escreva("\n")
}

// Uma unica linha PARAM16=y w0..w11 b.
funcao ctx_imprimir_param16(inteiro w16[], inteiro b16[], inteiro y)
{
    se (nao ctx_id_valido(y))
    {
        escreva("ERRO=SAIDA_INVALIDA\n")
        retorne
    }

    escreva("PARAM16=", y,
        " ", w16[y * CTX_ENTRADAS + 0],
        " ", w16[y * CTX_ENTRADAS + 1],
        " ", w16[y * CTX_ENTRADAS + 2],
        " ", w16[y * CTX_ENTRADAS + 3],
        " ", w16[y * CTX_ENTRADAS + 4],
        " ", w16[y * CTX_ENTRADAS + 5],
        " ", w16[y * CTX_ENTRADAS + 6],
        " ", w16[y * CTX_ENTRADAS + 7],
        " ", w16[y * CTX_ENTRADAS + 8],
        " ", w16[y * CTX_ENTRADAS + 9],
        " ", w16[y * CTX_ENTRADAS + 10],
        " ", w16[y * CTX_ENTRADAS + 11],
        " ", b16[y], "\n")
}

// 25 linhas PARAM16 seguidas de MAXIMO16=<max|W16|> <max|b16|>.
funcao ctx_imprimir_estado(inteiro w16[], inteiro b16[])
{
    inteiro y = 0
    enquanto (y < CTX_TAM_VOCAB)
    {
        ctx_imprimir_param16(w16, b16, y)
        y = y + 1
    }

    inteiro maximo_w = 0
    inteiro maximo_b = 0
    inteiro i = 0
    enquanto (i < CTX_TOTAL_W)
    {
        se (ctx_abs(w16[i]) > maximo_w)
        {
            maximo_w = ctx_abs(w16[i])
        }
        i = i + 1
    }
    i = 0
    enquanto (i < CTX_TOTAL_B)
    {
        se (ctx_abs(b16[i]) > maximo_b)
        {
            maximo_b = ctx_abs(b16[i])
        }
        i = i + 1
    }
    escreva("MAXIMO16=", maximo_w, " ", maximo_b, "\n")
}

// Conta parametros diferentes da formula canonica de ctx_inicializar,
// sem baseline armazenado. Fatias 0/1 esperadas zero; fatia 2 da M5.
funcao ctx_imprimir_alterados(inteiro w16[], inteiro b16[])
{
    inteiro alterados_w = 0
    inteiro alterados_b = 0
    inteiro y = 0
    enquanto (y < CTX_TAM_VOCAB)
    {
        inteiro k = 0
        enquanto (k < CTX_K)
        {
            inteiro d = 0
            enquanto (d < CTX_DIM)
            {
                inteiro esperado = 0
                se (k == CTX_K - 1)
                {
                    esperado = ((y * 7 + d * 5) % 25) - 12
                }
                se (w16[y * CTX_ENTRADAS + k * CTX_DIM + d] != esperado)
                {
                    alterados_w = alterados_w + 1
                }
                d = d + 1
            }
            k = k + 1
        }
        se (b16[y] != ((y * 7) % 9) - 4)
        {
            alterados_b = alterados_b + 1
        }
        y = y + 1
    }
    escreva("ALTERADOS_W=", alterados_w, "\n")
    escreva("ALTERADOS_B=", alterados_b, "\n")
}

// CTX16=<n> <12 inteiros>. Valida n e os ids antes de escrever qualquer byte.
funcao ctx_imprimir_contexto(inteiro historico[], inteiro n)
{
    se (n < 1 ou n > CTX_TOKENS_MAX)
    {
        escreva("ERRO=HISTORICO_INVALIDO\n")
        retorne
    }

    inteiro i = 0
    enquanto (i < n)
    {
        se (nao ctx_id_valido(historico[i]))
        {
            escreva("ERRO=HISTORICO_INVALIDO\n")
            retorne
        }
        i = i + 1
    }

    inteiro c16[12]
    ctx_montar_contexto(historico, n, c16)
    escreva("CTX16=", n)
    inteiro p = 0
    enquanto (p < CTX_ENTRADAS)
    {
        escreva(" ", c16[p])
        p = p + 1
    }
    escreva("\n")
}

// Bloco de 5 linhas. parada: 1 = PARE, 0 = MAXIMO.
// Valida n_saida, n_prefixo e os ids antes de escrever qualquer byte.
funcao ctx_imprimir_geracao(inteiro saida[], inteiro n_saida,
                            inteiro n_prefixo, inteiro parada)
{
    se (n_saida < 1 ou n_saida > CTX_TOKENS_MAX)
    {
        escreva("ERRO=SEQUENCIA_INVALIDA\n")
        retorne
    }
    se (n_prefixo < 1 ou n_prefixo > CTX_K ou n_prefixo > n_saida)
    {
        escreva("ERRO=SEQUENCIA_INVALIDA\n")
        retorne
    }

    inteiro i = 0
    enquanto (i < n_saida)
    {
        se (nao ctx_id_valido(saida[i]))
        {
            escreva("ERRO=SEQUENCIA_INVALIDA\n")
            retorne
        }
        i = i + 1
    }

    escreva("GERADO=")
    i = 0
    enquanto (i < n_saida)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        escreva(saida[i])
        i = i + 1
    }
    escreva("\n")
    escreva("N=", n_saida, "\n")
    escreva("PASSOS=", n_saida - n_prefixo, "\n")
    se (parada == 1)
    {
        escreva("PARADA=PARE\n")
    }
    senao
    {
        escreva("PARADA=MAXIMO\n")
    }
    escreva("TEXTO=")
    i = 0
    enquanto (i < n_saida)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        ctx_escrever_palavra(saida[i])
        i = i + 1
    }
    escreva("\n")
}
