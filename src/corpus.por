// ---------------------------------------------------------------------------
// Fragmento do treinamento a partir de corpus textual (M8, spec v0.1.0).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-corpus-tests.ps1 concatena src/tokenizador.por ANTES deste
// fragmento (o alias tx e id_do_campo sao herdados da M1) e src/contexto.por
// depois. Fonte ASCII puro. Sem bibliotecas, tempo ou aleatoriedade.
//
// Responsabilidades exclusivas da M8:
//   1. tokenizacao estrita de uma linha do corpus (formato + id_do_campo);
//   2. extracao de janelas K=3 dentro de cada linha, sem cruzar fronteiras;
//   3. perda total em lotes de ate 6 e treino por lotes que reutiliza
//      ctx_executar (M7) com epocas=1.
// Nenhuma formula de embedding, forward, perda, atualizacao ou geracao e
// reimplementada aqui.
// ---------------------------------------------------------------------------

const inteiro CORP_MAX_LINHAS = 6
const inteiro CORP_MIN_TOKENS = 4
const inteiro CORP_MAX_TOKENS = 8
const inteiro CORP_MAX_EXEMPLOS = 30
const inteiro CORP_K = 3
const inteiro CORP_LOTE = 6
const inteiro CORP_MAX_EPOCAS = 32
const inteiro CORP_LIMITE_PERDA = 2000000000

// Valor absoluto local (ctx_abs existe, mas a M8 nao depende de simbolos
// internos da M7 para validar parametros).
funcao inteiro corp_abs(inteiro v)
{
    se (v < 0)
    {
        retorne 0 - v
    }
    retorne v
}

// Verdadeiro se 0 <= id <= 24 (vocabulario fixo da M1).
funcao logico corp_id_valido(inteiro id)
{
    se (id >= 0 e id < 25)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Verdadeiro se todos os 325 parametros respeitam |v| <= 16.
funcao logico corp_params_validos(inteiro w16[], inteiro b16[])
{
    inteiro i = 0
    enquanto (i < 300)
    {
        se (corp_abs(w16[i]) > 16)
        {
            retorne falso
        }
        i = i + 1
    }
    i = 0
    enquanto (i < 25)
    {
        se (corp_abs(b16[i]) > 16)
        {
            retorne falso
        }
        i = i + 1
    }
    retorne verdadeiro
}

// Tokeniza uma linha do corpus. Retorna a contagem (4..8) ou -codigo.
// Em erro, ids[] permanece intacto e diagnostico[0] recebe a posicao 1-based
// do token culpado (0 quando nao se aplica). diagnostico[1] e sempre 0.
//
// Precedencia: 2 (formato) -> 3 (palavra desconhecida) -> 6 (curta) ->
// 7 (longa) -> 4 (sem pare) -> 5 (pare invalido).
funcao inteiro corp_tokenizar(cadeia linha, inteiro ids[], inteiro diagnostico[])
{
    diagnostico[0] = 0
    diagnostico[1] = 0

    inteiro n = tx.numero_caracteres(linha)
    se (n == 0)
    {
        retorne 0 - 2
    }

    caracter tab = tx.obter_caracter("\t", 0)
    caracter cr = tx.obter_caracter("\r", 0)
    caracter lf = tx.obter_caracter("\n", 0)

    inteiro inicios[16]
    inteiro fins[16]
    inteiro campos = 0
    inteiro ini = 0
    inteiro i = 0
    enquanto (i < n)
    {
        caracter c = tx.obter_caracter(linha, i)
        se (c == ' ')
        {
            se (i == 0 ou i == n - 1)
            {
                retorne 0 - 2
            }
            se (tx.obter_caracter(linha, i - 1) == ' ')
            {
                retorne 0 - 2
            }
            se (campos < 16)
            {
                inicios[campos] = ini
                fins[campos] = i - 1
            }
            campos = campos + 1
            ini = i + 1
        }
        senao se (c == tab ou c == cr ou c == lf)
        {
            retorne 0 - 2
        }
        i = i + 1
    }
    se (campos < 16)
    {
        inicios[campos] = ini
        fins[campos] = n - 1
    }
    campos = campos + 1

    inteiro buffer[16]
    i = 0
    enquanto (i < campos e i < 16)
    {
        inteiro id = id_do_campo(linha, inicios[i], fins[i])
        se (id == 0)
        {
            diagnostico[0] = i + 1
            retorne 0 - 3
        }
        buffer[i] = id
        i = i + 1
    }

    se (campos < CORP_MIN_TOKENS)
    {
        diagnostico[0] = campos
        retorne 0 - 6
    }
    se (campos > CORP_MAX_TOKENS)
    {
        diagnostico[0] = campos
        retorne 0 - 7
    }
    se (buffer[campos - 1] != 24)
    {
        retorne 0 - 4
    }
    i = 0
    enquanto (i < campos - 1)
    {
        se (buffer[i] == 24)
        {
            diagnostico[0] = i + 1
            retorne 0 - 5
        }
        i = i + 1
    }

    i = 0
    enquanto (i < campos)
    {
        ids[i] = buffer[i]
        i = i + 1
    }
    retorne campos
}

// Compara a janela candidata (3 IDs) com a ja gravada no indice j.
funcao logico corp_mesmo_contexto(inteiro cand_entradas[], inteiro j,
                                  inteiro a, inteiro b, inteiro c)
{
    se (cand_entradas[j * 3] != a)
    {
        retorne falso
    }
    se (cand_entradas[j * 3 + 1] != b)
    {
        retorne falso
    }
    se (cand_entradas[j * 3 + 2] != c)
    {
        retorne falso
    }
    retorne verdadeiro
}

// Extrai todos os exemplos do corpus. Retorna 0 ou codigo.
// Em erro, entradas[], alvos[] e n_exemplos[] permanecem intactos.
// diagnostico[0] = linha 1-based; diagnostico[1] = token 1-based.
funcao inteiro corp_extrair(cadeia linhas[], inteiro n_linhas,
                            inteiro entradas[], inteiro alvos[],
                            inteiro n_exemplos[], inteiro diagnostico[])
{
    diagnostico[0] = 0
    diagnostico[1] = 0

    se (n_linhas == 0)
    {
        retorne 1
    }
    se (n_linhas > CORP_MAX_LINHAS)
    {
        retorne 8
    }

    inteiro cand_entradas[90]
    inteiro cand_alvos[30]
    inteiro total = 0
    inteiro linha = 0
    enquanto (linha < n_linhas)
    {
        inteiro ids[8]
        inteiro diag[2]
        inteiro n_tokens = corp_tokenizar(linhas[linha], ids, diag)
        se (n_tokens < 0)
        {
            diagnostico[0] = linha + 1
            diagnostico[1] = diag[0]
            retorne 0 - n_tokens
        }

        inteiro i = CORP_K
        enquanto (i < n_tokens)
        {
            inteiro a = ids[i - 3]
            inteiro b = ids[i - 2]
            inteiro c = ids[i - 1]
            inteiro alvo = ids[i]

            inteiro j = 0
            enquanto (j < total)
            {
                se (corp_mesmo_contexto(cand_entradas, j, a, b, c))
                {
                    diagnostico[0] = linha + 1
                    diagnostico[1] = i + 1
                    se (cand_alvos[j] == alvo)
                    {
                        retorne 9
                    }
                    retorne 10
                }
                j = j + 1
            }

            cand_entradas[total * 3] = a
            cand_entradas[total * 3 + 1] = b
            cand_entradas[total * 3 + 2] = c
            cand_alvos[total] = alvo
            total = total + 1
            i = i + 1
        }
        linha = linha + 1
    }

    inteiro k = 0
    enquanto (k < total * 3)
    {
        entradas[k] = cand_entradas[k]
        k = k + 1
    }
    k = 0
    enquanto (k < total)
    {
        alvos[k] = cand_alvos[k]
        k = k + 1
    }
    n_exemplos[0] = total
    retorne 0
}

// Copia ate 6 exemplos a partir de base para os buffers de lote.
funcao corp_copiar_lote(inteiro entradas[], inteiro alvos[],
                        inteiro base, inteiro tam,
                        inteiro lote_entradas[], inteiro lote_alvos[])
{
    inteiro j = 0
    enquanto (j < tam)
    {
        lote_entradas[j * 3] = entradas[(base + j) * 3]
        lote_entradas[j * 3 + 1] = entradas[(base + j) * 3 + 1]
        lote_entradas[j * 3 + 2] = entradas[(base + j) * 3 + 2]
        lote_alvos[j] = alvos[base + j]
        j = j + 1
    }
}

// S total em lotes de ate 6. Retorna 0 (saida[0]=S) ou codigo.
// A soma e identica a S global porque a perda e aditiva por exemplo.
funcao inteiro corp_perda_total(inteiro w16[], inteiro b16[],
                                inteiro entradas[], inteiro alvos[],
                                inteiro n, inteiro saida[])
{
    se (n < 1 ou n > CORP_MAX_EXEMPLOS)
    {
        retorne 12
    }
    inteiro i = 0
    enquanto (i < n)
    {
        se (nao corp_id_valido(entradas[i * 3]) ou
            nao corp_id_valido(entradas[i * 3 + 1]) ou
            nao corp_id_valido(entradas[i * 3 + 2]) ou
            nao corp_id_valido(alvos[i]))
        {
            retorne 13
        }
        i = i + 1
    }
    se (nao corp_params_validos(w16, b16))
    {
        retorne 14
    }

    inteiro lote_entradas[18]
    inteiro lote_alvos[6]
    inteiro total = 0
    inteiro base = 0
    enquanto (base < n)
    {
        inteiro tam = n - base
        se (tam > CORP_LOTE)
        {
            tam = CORP_LOTE
        }
        corp_copiar_lote(entradas, alvos, base, tam,
                         lote_entradas, lote_alvos)
        inteiro parcial = ctx_perda_escalada(w16, b16, lote_entradas,
                                             lote_alvos, tam)
        se (total > CORP_LIMITE_PERDA - parcial)
        {
            retorne 16
        }
        total = total + parcial
        base = base + CORP_LOTE
    }
    saida[0] = total
    retorne 0
}

// Mapeia os codigos de ctx_executar para os codigos da M8.
funcao inteiro corp_mapa_codigo(inteiro codigo)
{
    se (codigo == 1)
    {
        retorne 12
    }
    se (codigo == 2)
    {
        retorne 11
    }
    se (codigo == 3)
    {
        retorne 13
    }
    se (codigo == 4)
    {
        retorne 14
    }
    retorne 15
}

// Treina com os exemplos na ordem do array, em lotes de ate 6.
// Reutiliza ctx_executar com epocas=1; o laco de epocas e da M8.
// Precedencia: 12 -> 11 -> 13 -> 14 -> 15/16.
funcao inteiro corp_treinar(inteiro w16[], inteiro b16[],
                            inteiro entradas[], inteiro alvos[],
                            inteiro n, inteiro epocas,
                            inteiro historico[])
{
    se (n < 1 ou n > CORP_MAX_EXEMPLOS)
    {
        retorne 12
    }
    se (epocas < 1 ou epocas > CORP_MAX_EPOCAS)
    {
        retorne 11
    }
    inteiro i = 0
    enquanto (i < n)
    {
        se (nao corp_id_valido(entradas[i * 3]) ou
            nao corp_id_valido(entradas[i * 3 + 1]) ou
            nao corp_id_valido(entradas[i * 3 + 2]) ou
            nao corp_id_valido(alvos[i]))
        {
            retorne 13
        }
        i = i + 1
    }
    se (nao corp_params_validos(w16, b16))
    {
        retorne 14
    }

    inteiro perda[2]
    inteiro codigo = corp_perda_total(w16, b16, entradas, alvos, n, perda)
    se (codigo != 0)
    {
        retorne codigo
    }
    historico[0] = perda[0]

    inteiro lote_entradas[18]
    inteiro lote_alvos[6]
    inteiro hist_lote[2]
    inteiro ep = 1
    enquanto (ep <= epocas)
    {
        inteiro base = 0
        enquanto (base < n)
        {
            inteiro tam = n - base
            se (tam > CORP_LOTE)
            {
                tam = CORP_LOTE
            }
            corp_copiar_lote(entradas, alvos, base, tam,
                             lote_entradas, lote_alvos)
            codigo = ctx_executar(w16, b16, lote_entradas, lote_alvos,
                                  tam, 1, hist_lote)
            se (codigo != 0)
            {
                retorne corp_mapa_codigo(codigo)
            }
            base = base + CORP_LOTE
        }

        codigo = corp_perda_total(w16, b16, entradas, alvos, n, perda)
        se (codigo != 0)
        {
            retorne codigo
        }
        historico[ep] = perda[0]
        ep = ep + 1
    }

    retorne 0
}
