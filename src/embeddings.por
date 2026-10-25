// ---------------------------------------------------------------------------
// Fragmento da matriz de embeddings (M3, spec v0.1.1).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-embedding-tests.ps1 concatena este fragmento a um driver.
// Fonte ASCII puro por contrato (AC18).
//
// Estado: real w[100], indice id * 4 + dimensao, id em 0..24, dimensao em 0..3.
// Inicializacao deterministica (spec secao 4): w = (((id*7 + d*3) % 32) - 16) / 16.0
// ---------------------------------------------------------------------------

const inteiro EMB_TAM_VOCAB = 25
const inteiro EMB_DIM = 4
const inteiro EMB_TOTAL = 100

// Valida o ID de token. 0 (UNK) e valido; 25.. e inexistente.
funcao logico emb_id_valido(inteiro id)
{
    se (id >= 0 e id < EMB_TAM_VOCAB)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Valida a dimensao do vetor de embeddings.
funcao logico emb_dim_valida(inteiro dimensao)
{
    se (dimensao >= 0 e dimensao < EMB_DIM)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Grava a tabela canonica nas 100 posicoes, sem ler o estado anterior.
funcao inicializar_embeddings(real w[])
{
    inteiro id = 0
    enquanto (id < EMB_TAM_VOCAB)
    {
        inteiro dimensao = 0
        enquanto (dimensao < EMB_DIM)
        {
            inteiro q = ((id * 7 + dimensao * 3) % 32) - 16
            w[id * EMB_DIM + dimensao] = q / 16.0
            dimensao = dimensao + 1
        }
        id = id + 1
    }
}

// Consulta interna. Pre-condicao: id e dimensao validos.
funcao real emb_obter(real w[], inteiro id, inteiro dimensao)
{
    retorne w[id * EMB_DIM + dimensao]
}

funcao emb_imprimir_info()
{
    escreva("INFO=", EMB_TAM_VOCAB, " ", EMB_DIM, " ", EMB_TOTAL, "\n")
}

// Escrita interna. Pre-condicao: id e dimensao validos (o chamador valida).
// Aceita qualquer real, sem clamp e sem restricao a grade 1/16.
funcao emb_definir(real w[], inteiro id, inteiro dimensao, real valor)
{
    w[id * EMB_DIM + dimensao] = valor
}

// Impressao total: valida antes de acessar o vetor. Em caso de erro, a linha
// ERRO= e a unica saida da chamada.
funcao emb_imprimir_vetor(real w[], inteiro id)
{
    se (nao emb_id_valido(id))
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }

    escreva("VETOR=", id, " ",
        w[id * EMB_DIM + 0], " ",
        w[id * EMB_DIM + 1], " ",
        w[id * EMB_DIM + 2], " ",
        w[id * EMB_DIM + 3], "\n")
}

// Resumo do estado atual: menor, maior e numero de linhas distintas.
funcao emb_resumo(real w[])
{
    real menor = w[0]
    real maior = w[0]
    inteiro i = 1
    enquanto (i < EMB_TOTAL)
    {
        se (w[i] < menor)
        {
            menor = w[i]
        }
        se (w[i] > maior)
        {
            maior = w[i]
        }
        i = i + 1
    }

    inteiro distintos = 0
    inteiro a = 0
    enquanto (a < EMB_TAM_VOCAB)
    {
        logico nova = verdadeiro
        inteiro b = 0
        enquanto (b < a)
        {
            logico igual = verdadeiro
            inteiro dimensao = 0
            enquanto (dimensao < EMB_DIM)
            {
                se (w[a * EMB_DIM + dimensao] != w[b * EMB_DIM + dimensao])
                {
                    igual = falso
                }
                dimensao = dimensao + 1
            }
            se (igual)
            {
                nova = falso
            }
            b = b + 1
        }
        se (nova)
        {
            distintos = distintos + 1
        }
        a = a + 1
    }

    escreva("RESUMO=", EMB_TAM_VOCAB, " ", EMB_TOTAL, " ",
        menor, " ", maior, " ", distintos, "\n")
}

// Consulta pontual de um peso. Ordem de validacao: ID antes da dimensao.
funcao emb_imprimir_peso(real w[], inteiro id, inteiro dimensao)
{
    se (nao emb_id_valido(id))
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }

    se (nao emb_dim_valida(dimensao))
    {
        escreva("ERRO=DIMENSAO_INVALIDA\n")
        retorne
    }

    escreva("PESO=", id, " ", dimensao, " ",
        w[id * EMB_DIM + dimensao], "\n")
}
