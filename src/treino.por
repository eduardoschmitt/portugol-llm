// ---------------------------------------------------------------------------
// Fragmento do primeiro treinamento supervisionado (M5, spec v1.0.0).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-training-tests.ps1 concatena este fragmento a um driver.
// Fonte ASCII puro por contrato. Sem bibliotecas, tempo ou aleatoriedade.
//
// Estado: inteiro w16[100] (W[y][d] em y*4+d) e inteiro b16[25] (b[y]),
// ambos em unidades de 1/16. Nenhum real no caminho de treinamento.
// Embeddings congelados: treino_emb16 recalcula a formula da M3.
// ---------------------------------------------------------------------------

const inteiro TREINO_TAM_VOCAB = 25
const inteiro TREINO_DIM = 4
const inteiro TREINO_SAIDAS = 25
const inteiro TREINO_TOTAL_W = 100
const inteiro TREINO_TOTAL_B = 25
const inteiro TREINO_PARAMS = 125
const inteiro TREINO_MAX_EXEMPLOS = 16
const inteiro TREINO_MAX_EPOCAS = 256
const inteiro TREINO_GRADE = 16
const inteiro TREINO_ESCALA_PERDA = 524288
const inteiro TREINO_LIMITE = 48
const inteiro TREINO_EPOCAS = 5
const inteiro TREINO_TAXA_NUM = 1
const inteiro TREINO_TAXA_DEN = 4
const inteiro TREINO_DIV_W = 1024
const inteiro TREINO_DIV_B = 64

// Valor absoluto sem biblioteca. Pre-condicao: v > -2147483648.
funcao inteiro treino_abs(inteiro v)
{
    se (v < 0)
    {
        retorne 0 - v
    }
    retorne v
}

funcao logico treino_id_valido(inteiro id)
{
    se (id >= 0 e id < TREINO_TAM_VOCAB)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico treino_n_valido(inteiro n)
{
    se (n >= 1 e n <= TREINO_MAX_EXEMPLOS)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico treino_epocas_validas(inteiro epocas)
{
    se (epocas >= 1 e epocas <= TREINO_MAX_EPOCAS)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Verdadeiro se todos os 125 parametros respeitam |v| <= limite.
funcao logico treino_params_no_limite(inteiro w16[], inteiro b16[], inteiro limite)
{
    inteiro i = 0
    enquanto (i < TREINO_TOTAL_W)
    {
        se (treino_abs(w16[i]) > limite)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < TREINO_TOTAL_B)
    {
        se (treino_abs(b16[i]) > limite)
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

funcao logico treino_params_validos(inteiro w16[], inteiro b16[])
{
    retorne treino_params_no_limite(w16, b16, TREINO_LIMITE)
}

// Precedencia normativa (spec secao 11.2): n, epocas, ids, parametros.
funcao inteiro treino_validar(inteiro entradas[], inteiro alvos[],
                              inteiro n, inteiro epocas,
                              inteiro w16[], inteiro b16[])
{
    se (nao treino_n_valido(n))
    {
        retorne 1
    }

    se (nao treino_epocas_validas(epocas))
    {
        retorne 2
    }

    inteiro i = 0
    enquanto (i < n)
    {
        se (nao treino_id_valido(entradas[i]) ou nao treino_id_valido(alvos[i]))
        {
            retorne 3
        }
        i = i + 1
    }

    se (nao treino_params_validos(w16, b16))
    {
        retorne 4
    }

    retorne 0
}

// Grava os 125 parametros canonicos, sem ler o estado anterior.
// W16[y][d] = ((y*7 + d*5) % 25) - 12 ; b16[y] = ((y*7) % 9) - 4
funcao treino_inicializar(inteiro w16[], inteiro b16[])
{
    inteiro y = 0
    enquanto (y < TREINO_SAIDAS)
    {
        inteiro d = 0
        enquanto (d < TREINO_DIM)
        {
            w16[y * TREINO_DIM + d] = ((y * 7 + d * 5) % 25) - 12
            d = d + 1
        }
        b16[y] = ((y * 7) % 9) - 4
        y = y + 1
    }
}

// Compara o estado corrente com a formula canonica de inicializacao.
funcao logico treino_igual_a_inicial(inteiro w16[], inteiro b16[])
{
    inteiro y = 0
    enquanto (y < TREINO_SAIDAS)
    {
        inteiro d = 0
        enquanto (d < TREINO_DIM)
        {
            se (w16[y * TREINO_DIM + d] != ((y * 7 + d * 5) % 25) - 12)
            {
                retorne falso
            }
            d = d + 1
        }
        se (b16[y] != ((y * 7) % 9) - 4)
        {
            retorne falso
        }
        y = y + 1
    }
    retorne verdadeiro
}

// e16(id,d) = ((id*7 + d*3) % 32) - 16, formula congelada da M3.
funcao inteiro treino_emb16(inteiro id, inteiro dimensao)
{
    retorne ((id * 7 + dimensao * 3) % 32) - 16
}

// Z256(id,y) = sum_d W16[y][d]*e16(id,d) + 16*b16[y].
// Ordem normativa: d = 0..3 com acumulacao a partir de 0, vies por ultimo.
funcao inteiro treino_z256(inteiro w16[], inteiro b16[], inteiro entrada, inteiro y)
{
    inteiro soma = 0
    inteiro d = 0
    enquanto (d < TREINO_DIM)
    {
        soma = soma + w16[y * TREINO_DIM + d] * treino_emb16(entrada, d)
        d = d + 1
    }
    soma = soma + TREINO_GRADE * b16[y]
    retorne soma
}

// delta256(n,y) = Z256(entrada,y) - 256*[y == alvo].
funcao inteiro treino_delta256(inteiro w16[], inteiro b16[],
                               inteiro entrada, inteiro y, inteiro alvo)
{
    inteiro z = treino_z256(w16, b16, entrada, y)
    se (y == alvo)
    {
        retorne z - TREINO_GRADE * TREINO_GRADE
    }
    retorne z
}

// Argmax normativo: inicializa no y=0 e usa comparacao estrita (empate: menor y).
funcao inteiro treino_argmax(inteiro w16[], inteiro b16[], inteiro entrada)
{
    inteiro melhor = 0
    inteiro melhor_valor = treino_z256(w16, b16, entrada, 0)
    inteiro y = 1
    enquanto (y < TREINO_SAIDAS)
    {
        inteiro valor = treino_z256(w16, b16, entrada, y)
        se (valor > melhor_valor)
        {
            melhor_valor = valor
            melhor = y
        }
        y = y + 1
    }
    retorne melhor
}

// S = sum_{n,y} delta256(n,y)^2.
funcao inteiro treino_perda_escalada(inteiro w16[], inteiro b16[],
                                     inteiro entradas[], inteiro alvos[],
                                     inteiro n)
{
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < n)
    {
        inteiro y = 0
        enquanto (y < TREINO_SAIDAS)
        {
            inteiro delta = treino_delta256(w16, b16, entradas[i], y, alvos[i])
            soma = soma + delta * delta
            y = y + 1
        }
        i = i + 1
    }
    retorne soma
}

funcao inteiro treino_acertos(inteiro w16[], inteiro b16[],
                              inteiro entradas[], inteiro alvos[], inteiro n)
{
    inteiro total = 0
    inteiro i = 0
    enquanto (i < n)
    {
        se (treino_argmax(w16, b16, entradas[i]) == alvos[i])
        {
            total = total + 1
        }
        i = i + 1
    }
    retorne total
}

// PERDA, ACERTOS e PRED. Valida n e os ids antes de acessar os arrays.
funcao treino_imprimir_avaliacao(inteiro w16[], inteiro b16[],
                                 inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (nao treino_n_valido(n))
    {
        escreva("ERRO=EXEMPLOS_INVALIDOS\n")
        retorne
    }

    inteiro i = 0
    enquanto (i < n)
    {
        se (nao treino_id_valido(entradas[i]) ou nao treino_id_valido(alvos[i]))
        {
            escreva("ERRO=ID_INVALIDO\n")
            retorne
        }
        i = i + 1
    }

    escreva("PERDA=", treino_perda_escalada(w16, b16, entradas, alvos, n), "\n")
    escreva("ACERTOS=", treino_acertos(w16, b16, entradas, alvos, n), "\n")
    escreva("PRED=")
    i = 0
    enquanto (i < n)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        escreva(treino_argmax(w16, b16, entradas[i]))
        i = i + 1
    }
    escreva("\n")
}

// r(num,den) = sinal(num) * floor((|num| + den/2) / den).
// den e positivo e par (64 ou 1024). Meio para longe de zero.
funcao inteiro treino_div_arredondada(inteiro numerador, inteiro denominador)
{
    inteiro sinal = 1
    se (numerador < 0)
    {
        sinal = 0 - 1
    }
    inteiro absoluto = numerador * sinal
    retorne sinal * ((absoluto + denominador / 2) / denominador)
}

// SGD por exemplo, ordem fixa, eta = 1/4, quantizacao no novo valor.
// Valida antes de mutar. Em 1..4 nao muta nada; em 5 o estado e parcial.
funcao inteiro treino_executar(inteiro w16[], inteiro b16[],
                               inteiro entradas[], inteiro alvos[],
                               inteiro n, inteiro epocas,
                               inteiro historico[])
{
    inteiro codigo = treino_validar(entradas, alvos, n, epocas, w16, b16)
    se (codigo != 0)
    {
        retorne codigo
    }

    inteiro delta[25]
    historico[0] = treino_perda_escalada(w16, b16, entradas, alvos, n)

    inteiro ep = 1
    enquanto (ep <= epocas)
    {
        inteiro i = 0
        enquanto (i < n)
        {
            // Congela os 25 deltas do exemplo antes de qualquer escrita.
            inteiro y = 0
            enquanto (y < TREINO_SAIDAS)
            {
                delta[y] = treino_delta256(w16, b16, entradas[i], y, alvos[i])
                y = y + 1
            }

            y = 0
            enquanto (y < TREINO_SAIDAS)
            {
                inteiro d = 0
                enquanto (d < TREINO_DIM)
                {
                    inteiro novo = treino_div_arredondada(
                        TREINO_DIV_W * w16[y * TREINO_DIM + d]
                            - delta[y] * treino_emb16(entradas[i], d),
                        TREINO_DIV_W)
                    w16[y * TREINO_DIM + d] = novo
                    se (treino_abs(novo) > TREINO_LIMITE)
                    {
                        retorne 5
                    }
                    d = d + 1
                }

                inteiro novo_b = treino_div_arredondada(
                    TREINO_DIV_B * b16[y] - delta[y], TREINO_DIV_B)
                b16[y] = novo_b
                se (treino_abs(novo_b) > TREINO_LIMITE)
                {
                    retorne 5
                }
                y = y + 1
            }
            i = i + 1
        }

        historico[ep] = treino_perda_escalada(w16, b16, entradas, alvos, n)
        ep = ep + 1
    }

    retorne 0
}

funcao treino_imprimir_historico(inteiro historico[], inteiro epocas)
{
    se (nao treino_epocas_validas(epocas))
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

// G(y,d) = sum_n delta256(n,y) * e16(entradas[n], d)
funcao inteiro treino_gradiente_w(inteiro w16[], inteiro b16[],
                                  inteiro entradas[], inteiro alvos[],
                                  inteiro n, inteiro y, inteiro d)
{
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < n)
    {
        soma = soma + treino_delta256(w16, b16, entradas[i], y, alvos[i])
            * treino_emb16(entradas[i], d)
        i = i + 1
    }
    retorne soma
}

// G_b(y) = 16 * sum_n delta256(n,y)
funcao inteiro treino_gradiente_b(inteiro w16[], inteiro b16[],
                                  inteiro entradas[], inteiro alvos[],
                                  inteiro n, inteiro y)
{
    inteiro soma = 0
    inteiro i = 0
    enquanto (i < n)
    {
        soma = soma + treino_delta256(w16, b16, entradas[i], y, alvos[i])
        i = i + 1
    }
    retorne TREINO_GRADE * soma
}

// Diferenca central com h = 1 em cada parametro, restaurando o estado.
// saida[0] = quantos dos 125 satisfazem S(v+1) - S(v-1) = 4G.
// saida[1] = soma dos 125 G.
// Pre-condicao: |W16|, |b16| <= 47 (para +-1 nao violar I2).
funcao treino_calcular_gradiente(inteiro w16[], inteiro b16[],
                                 inteiro entradas[], inteiro alvos[],
                                 inteiro n, inteiro saida[])
{
    inteiro exatos = 0
    inteiro soma = 0

    inteiro y = 0
    enquanto (y < TREINO_SAIDAS)
    {
        inteiro d = 0
        enquanto (d < TREINO_DIM)
        {
            inteiro indice = y * TREINO_DIM + d
            inteiro g = treino_gradiente_w(w16, b16, entradas, alvos, n, y, d)
            inteiro original = w16[indice]
            w16[indice] = original + 1
            inteiro mais = treino_perda_escalada(w16, b16, entradas, alvos, n)
            w16[indice] = original - 1
            inteiro menos = treino_perda_escalada(w16, b16, entradas, alvos, n)
            w16[indice] = original
            se (mais - menos == 4 * g)
            {
                exatos = exatos + 1
            }
            soma = soma + g
            d = d + 1
        }

        inteiro g_b = treino_gradiente_b(w16, b16, entradas, alvos, n, y)
        inteiro original_b = b16[y]
        b16[y] = original_b + 1
        inteiro mais_b = treino_perda_escalada(w16, b16, entradas, alvos, n)
        b16[y] = original_b - 1
        inteiro menos_b = treino_perda_escalada(w16, b16, entradas, alvos, n)
        b16[y] = original_b
        se (mais_b - menos_b == 4 * g_b)
        {
            exatos = exatos + 1
        }
        soma = soma + g_b
        y = y + 1
    }

    saida[0] = exatos
    saida[1] = soma
}

// Valida n, ids e o limite 47 antes de qualquer linha (sem saida parcial).
funcao treino_imprimir_gradiente(inteiro w16[], inteiro b16[],
                                 inteiro entradas[], inteiro alvos[], inteiro n)
{
    se (nao treino_n_valido(n))
    {
        escreva("ERRO=EXEMPLOS_INVALIDOS\n")
        retorne
    }

    inteiro i = 0
    enquanto (i < n)
    {
        se (nao treino_id_valido(entradas[i]) ou nao treino_id_valido(alvos[i]))
        {
            escreva("ERRO=ID_INVALIDO\n")
            retorne
        }
        i = i + 1
    }

    se (nao treino_params_no_limite(w16, b16, 47))
    {
        escreva("ERRO=PARAMETROS_INVALIDOS\n")
        retorne
    }

    inteiro saida[2]
    treino_calcular_gradiente(w16, b16, entradas, alvos, n, saida)
    escreva("GRAD_EXATOS=", saida[0], "\n")
    escreva("GRAD_TOTAL=", TREINO_PARAMS, "\n")
    escreva("GRAD_SOMA=", saida[1], "\n")
}

// Converte o estado inteiro para a grade 1/16 em real (divisao exata).
// Usado apenas na composicao com a M4; o treinamento nao usa real.
funcao treino_materializar(inteiro w16[], inteiro b16[],
                           real pesos[], real vieses[])
{
    inteiro y = 0
    enquanto (y < TREINO_SAIDAS)
    {
        inteiro d = 0
        enquanto (d < TREINO_DIM)
        {
            pesos[y * TREINO_DIM + d] = w16[y * TREINO_DIM + d] / 16.0
            d = d + 1
        }
        vieses[y] = b16[y] / 16.0
        y = y + 1
    }
}

funcao treino_imprimir_config()
{
    escreva("INFO=TREINO ", TREINO_GRADE, " ", TREINO_GRADE * TREINO_GRADE,
        " ", TREINO_PARAMS, " ", TREINO_TOTAL_W, "\n")
    escreva("TAXA=", TREINO_TAXA_NUM, "/", TREINO_TAXA_DEN, "\n")
    escreva("GRADE=1/", TREINO_GRADE, "\n")
    escreva("EPOCAS=", TREINO_EPOCAS, "\n")
    escreva("ESCALA_PERDA=", TREINO_ESCALA_PERDA, "\n")
    escreva("LIMITE_PARAM=", TREINO_LIMITE, "\n")
    escreva("ORDEM=EXEMPLO\n")
}

// Uma unica linha. Ordem de validacao: n, depois ids.
funcao treino_imprimir_validacao(inteiro entradas[], inteiro alvos[],
                                 inteiro n, inteiro epocas,
                                 inteiro w16[], inteiro b16[])
{
    inteiro codigo = treino_validar(entradas, alvos, n, epocas, w16, b16)
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

// Uma unica linha PARAM16=y w0 w1 w2 w3 b.
funcao treino_imprimir_param16(inteiro w16[], inteiro b16[], inteiro y)
{
    se (nao treino_id_valido(y))
    {
        escreva("ERRO=SAIDA_INVALIDA\n")
        retorne
    }

    escreva("PARAM16=", y,
        " ", w16[y * TREINO_DIM + 0],
        " ", w16[y * TREINO_DIM + 1],
        " ", w16[y * TREINO_DIM + 2],
        " ", w16[y * TREINO_DIM + 3],
        " ", b16[y], "\n")
}

// 25 linhas PARAM16 seguidas de MAXIMO16=<max|W16|> <max|b16|>.
funcao treino_imprimir_estado(inteiro w16[], inteiro b16[])
{
    inteiro y = 0
    enquanto (y < TREINO_SAIDAS)
    {
        treino_imprimir_param16(w16, b16, y)
        y = y + 1
    }

    inteiro maximo_w = 0
    inteiro maximo_b = 0
    inteiro i = 0
    enquanto (i < TREINO_TOTAL_W)
    {
        se (treino_abs(w16[i]) > maximo_w)
        {
            maximo_w = treino_abs(w16[i])
        }
        i = i + 1
    }
    i = 0
    enquanto (i < TREINO_TOTAL_B)
    {
        se (treino_abs(b16[i]) > maximo_b)
        {
            maximo_b = treino_abs(b16[i])
        }
        i = i + 1
    }
    escreva("MAXIMO16=", maximo_w, " ", maximo_b, "\n")
}

// Conta parametros diferentes da formula canonica, sem baseline armazenado.
funcao treino_imprimir_alterados(inteiro w16[], inteiro b16[])
{
    inteiro alterados_w = 0
    inteiro alterados_b = 0
    inteiro y = 0
    enquanto (y < TREINO_SAIDAS)
    {
        inteiro d = 0
        enquanto (d < TREINO_DIM)
        {
            se (w16[y * TREINO_DIM + d] != ((y * 7 + d * 5) % 25) - 12)
            {
                alterados_w = alterados_w + 1
            }
            d = d + 1
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
