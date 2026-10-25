// ---------------------------------------------------------------------------
// Fragmento do tokenizador minimo (M1, spec v0.2.1).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-tests.ps1 concatena este fragmento a um driver em temp/tests/.
// Fonte ASCII puro por contrato (A10): qualquer acento aqui e acidente.
// ---------------------------------------------------------------------------
inclua biblioteca Texto --> tx

// Unica definicao de separador: espaco, TAB, CR ou LF (spec secao 2).
// TAB/CR/LF chegam por parametro, obtidos com tx.obter_caracter (A8/D8).
funcao logico eh_separador(caracter c, caracter tab, caracter cr, caracter lf)
{
    se (c == ' ' ou c == tab ou c == cr ou c == lf)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Compara o campo [ini, fim] com a palavra sem criar substring nem
// transformar o texto: primeiro o comprimento, depois caractere a caractere,
// com retorno imediato na primeira diferenca (D7, secao 3.1).
funcao logico mesmo_conteudo(cadeia texto, inteiro ini, inteiro fim, cadeia palavra)
{
    inteiro k = 0
    inteiro n_palavra = tx.numero_caracteres(palavra)

    se ((fim - ini + 1) != n_palavra)
    {
        retorne falso
    }

    enquanto (k < n_palavra)
    {
        se (tx.obter_caracter(texto, ini + k) != tx.obter_caracter(palavra, k))
        {
            retorne falso
        }
        k = k + 1
    }

    retorne verdadeiro
}

// Tabela fixa da secao 3.3, na ordem dos IDs 1..24 (D11).
// Fallback 0 = UNK. Nenhuma palavra mapeia para 0; nenhum ID em 25..63.
funcao inteiro id_do_campo(cadeia texto, inteiro ini, inteiro fim)
{
    se (mesmo_conteudo(texto, ini, fim, "programa"))   { retorne 1 }
    se (mesmo_conteudo(texto, ini, fim, "funcao"))     { retorne 2 }
    se (mesmo_conteudo(texto, ini, fim, "inicio"))     { retorne 3 }
    se (mesmo_conteudo(texto, ini, fim, "inteiro"))    { retorne 4 }
    se (mesmo_conteudo(texto, ini, fim, "real"))       { retorne 5 }
    se (mesmo_conteudo(texto, ini, fim, "logico"))     { retorne 6 }
    se (mesmo_conteudo(texto, ini, fim, "cadeia"))     { retorne 7 }
    se (mesmo_conteudo(texto, ini, fim, "vazio"))      { retorne 8 }
    se (mesmo_conteudo(texto, ini, fim, "se"))         { retorne 9 }
    se (mesmo_conteudo(texto, ini, fim, "senao"))      { retorne 10 }
    se (mesmo_conteudo(texto, ini, fim, "enquanto"))   { retorne 11 }
    se (mesmo_conteudo(texto, ini, fim, "faca"))       { retorne 12 }
    se (mesmo_conteudo(texto, ini, fim, "para"))       { retorne 13 }
    se (mesmo_conteudo(texto, ini, fim, "ate"))        { retorne 14 }
    se (mesmo_conteudo(texto, ini, fim, "passo"))      { retorne 15 }
    se (mesmo_conteudo(texto, ini, fim, "retorne"))    { retorne 16 }
    se (mesmo_conteudo(texto, ini, fim, "escreva"))    { retorne 17 }
    se (mesmo_conteudo(texto, ini, fim, "leia"))       { retorne 18 }
    se (mesmo_conteudo(texto, ini, fim, "e"))          { retorne 19 }
    se (mesmo_conteudo(texto, ini, fim, "ou"))         { retorne 20 }
    se (mesmo_conteudo(texto, ini, fim, "nao"))        { retorne 21 }
    se (mesmo_conteudo(texto, ini, fim, "verdadeiro")) { retorne 22 }
    se (mesmo_conteudo(texto, ini, fim, "falso"))      { retorne 23 }
    se (mesmo_conteudo(texto, ini, fim, "pare"))       { retorne 24 }
    retorne 0
}

// Saida: uma unica linha "IDS=..." ou "ERRO=..." seguida de LF.
// Ordem normativa (D9): comprimento antes de qualquer varredura ou escrita.
funcao tokenizar(cadeia texto)
{
    inteiro n = tx.numero_caracteres(texto)
    caracter tab = tx.obter_caracter("\t", 0)
    caracter cr = tx.obter_caracter("\r", 0)
    caracter lf = tx.obter_caracter("\n", 0)
    inteiro ids[1024]
    inteiro total = 0
    inteiro ini = 0
    inteiro fim = 0
    logico em_campo = falso
    inteiro i = 0
    inteiro j = 0

    se (n > 16384)
    {
        escreva("ERRO=ENTRADA_LONGA\n")
        retorne
    }

    // Varredura por indices; nenhuma substring e criada.
    enquanto (i < n)
    {
        se (eh_separador(tx.obter_caracter(texto, i), tab, cr, lf))
        {
            se (em_campo)
            {
                fim = i - 1
                // Limite de tokens (D14): o 1.025o campo dispara antes de gravar.
                // Como total <= 1023 na gravacao, ids[1024] nunca e acessado.
                se (total == 1024)
                {
                    escreva("ERRO=TOKENS_DEMAIS\n")
                    retorne
                }
                ids[total] = id_do_campo(texto, ini, fim)
                total = total + 1
                em_campo = falso
            }
        }
        senao
        {
            se (em_campo == falso)
            {
                ini = i
                em_campo = verdadeiro
            }
        }
        i = i + 1
    }

    se (em_campo)
    {
        fim = n - 1
        // Mesma guarda do 1.025o campo, agora para o campo que termina no fim.
        se (total == 1024)
        {
            escreva("ERRO=TOKENS_DEMAIS\n")
            retorne
        }
        ids[total] = id_do_campo(texto, ini, fim)
        total = total + 1
    }

    escreva("IDS=")
    enquanto (j < total)
    {
        se (j > 0)
        {
            escreva(" ")
        }
        escreva(ids[j])
        j = j + 1
    }
    escreva("\n")
}
