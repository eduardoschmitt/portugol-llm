// ---------------------------------------------------------------------------
// Fragmento da geracao autoregressiva determinista (M6, spec v1.0.0).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-generation-tests.ps1 concatena treino.por + este fragmento
// + um driver.
// Fonte ASCII puro por contrato. Sem bibliotecas, tempo ou aleatoriedade.
//
// Dependencia unica: treino_argmax e treino_params_validos da M5. Nenhum
// forward e duplicado aqui; nenhum vetor w16/b16 e escrito.
// ---------------------------------------------------------------------------

const inteiro GERADOR_TAM_VOCAB = 25
const inteiro GERADOR_DIM = 4
const inteiro GERADOR_SAIDAS = 25
const inteiro GERADOR_PARAMS = 125
const inteiro GERADOR_MAX_TOKENS = 64
const inteiro GERADOR_TOKEN_UNK = 0
const inteiro GERADOR_TOKEN_PARADA = 24

funcao logico gerador_token_valido(inteiro token)
{
    se (token >= 0 e token < GERADOR_TAM_VOCAB)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico gerador_limite_valido(inteiro maximo)
{
    se (maximo >= 1 e maximo <= GERADOR_MAX_TOKENS)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Proximo token por argmax deterministico da camada afim da M5.
// Pre-condicao: token em 0..24. Nao imprime e nao muta nada.
funcao inteiro gerador_proximo(inteiro w16[], inteiro b16[], inteiro token)
{
    retorne treino_argmax(w16, b16, token)
}

// Preenche saida[0..N-1] com a semente e os tokens seguintes; retorna N.
// O token inicial ocupa o indice 0. O laco verifica "pare" antes de calcular
// o proximo token, portanto semente 24 produz N=1 e PARE vence o limite.
funcao inteiro gerador_gerar(inteiro w16[], inteiro b16[],
                             inteiro semente, inteiro maximo,
                             inteiro saida[])
{
    saida[0] = semente
    inteiro total = 1
    enquanto (total < maximo)
    {
        se (saida[total - 1] == GERADOR_TOKEN_PARADA)
        {
            retorne total
        }
        inteiro proximo = gerador_proximo(w16, b16, saida[total - 1])
        saida[total] = proximo
        total = total + 1
    }
    retorne total
}

// Escreve apenas a palavra do ID, sem espaco e sem quebra de linha.
// Pre-condicao: 0 <= token <= 24.
funcao gerador_escrever_palavra(inteiro token)
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

// Imprime TEXTO= seguido das palavras de saida[0..total-1].
// Valida total e todos os IDs antes de escrever qualquer byte.
funcao gerador_imprimir_texto(inteiro saida[], inteiro total)
{
    se (total < 0 ou total > GERADOR_MAX_TOKENS)
    {
        escreva("ERRO=SEQUENCIA_INVALIDA\n")
        retorne
    }
    inteiro i = 0
    enquanto (i < total)
    {
        se (nao gerador_token_valido(saida[i]))
        {
            escreva("ERRO=SEQUENCIA_INVALIDA\n")
            retorne
        }
        i = i + 1
    }
    escreva("TEXTO=")
    i = 0
    enquanto (i < total)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        gerador_escrever_palavra(saida[i])
        i = i + 1
    }
    escreva("\n")
}

// Imprime PALAVRA=<id> <palavra>; ID invalido produz ERRO=ID_INVALIDO.
funcao gerador_imprimir_palavra(inteiro token)
{
    se (nao gerador_token_valido(token))
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }
    escreva("PALAVRA=", token, " ")
    gerador_escrever_palavra(token)
    escreva("\n")
}

// Bloco de 5 linhas. Valida semente, limite e os 125 parametros, nessa ordem,
// antes de escrever qualquer byte. O buffer e local: o chamador nao precisa
// fornecer saida[] e o estado w16/b16 nunca e escrito.
funcao gerador_imprimir_geracao(inteiro w16[], inteiro b16[],
                                inteiro semente, inteiro maximo)
{
    se (nao gerador_token_valido(semente))
    {
        escreva("ERRO=TOKEN_INVALIDO\n")
        retorne
    }
    se (nao gerador_limite_valido(maximo))
    {
        escreva("ERRO=LIMITE_INVALIDO\n")
        retorne
    }
    se (nao treino_params_validos(w16, b16))
    {
        escreva("ERRO=PARAMETROS_INVALIDOS\n")
        retorne
    }
    inteiro saida[64]
    inteiro total = gerador_gerar(w16, b16, semente, maximo, saida)
    escreva("GERADO=")
    inteiro i = 0
    enquanto (i < total)
    {
        se (i > 0)
        {
            escreva(" ")
        }
        escreva(saida[i])
        i = i + 1
    }
    escreva("\n")
    escreva("N=", total, "\n")
    escreva("PASSOS=", total - 1, "\n")
    se (saida[total - 1] == GERADOR_TOKEN_PARADA)
    {
        escreva("PARADA=PARE\n")
    }
    senao
    {
        escreva("PARADA=MAXIMO\n")
    }
    gerador_imprimir_texto(saida, total)
}

funcao gerador_imprimir_config()
{
    escreva("INFO=GERADOR ", GERADOR_TAM_VOCAB, " ", GERADOR_MAX_TOKENS,
            " ", GERADOR_DIM, " ", GERADOR_PARAMS, "\n")
    escreva("TOKEN_PARADA=", GERADOR_TOKEN_PARADA, "\n")
    escreva("TOKEN_UNK=", GERADOR_TOKEN_UNK, "\n")
    escreva("LIMITE_MAXIMO=", GERADOR_MAX_TOKENS, "\n")
}

// Impressao pura dos validadores: 0 ou 1, sem alterar argumentos.
funcao gerador_imprimir_validadores(inteiro token, inteiro maximo)
{
    inteiro token_ok = 0
    se (gerador_token_valido(token))
    {
        token_ok = 1
    }
    inteiro limite_ok = 0
    se (gerador_limite_valido(maximo))
    {
        limite_ok = 1
    }
    escreva("VALIDO=TOKEN ", token, " ", token_ok, "\n")
    escreva("VALIDO=LIMITE ", maximo, " ", limite_ok, "\n")
}
