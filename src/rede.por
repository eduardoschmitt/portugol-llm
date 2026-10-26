// ---------------------------------------------------------------------------
// Fragmento da camada de saida linear (M4, spec v0.1.0).
// NAO e um programa executavel sozinho: nao declara "programa" nem "inicio".
// scripts/build-network-tests.ps1 concatena este fragmento a um driver.
// Fonte ASCII puro por contrato (AC3). Sem bibliotecas, tempo ou aleatoriedade.
//
// Estado: real pesos[100] (W[y][d] em y*4+d) e real vieses[25] (b[y]).
// Inicializacao deterministica (spec secao 4.1):
//   W[y][d] = (((y*7 + d*5) % 25) - 12) / 16.0
//   b[y]    = (((y*7) % 9) - 4) / 16.0
// ---------------------------------------------------------------------------

const inteiro REDE_TAM_VOCAB = 25
const inteiro REDE_ENTRADAS = 4
const inteiro REDE_SAIDAS = 25
const inteiro REDE_TOTAL = 100
const inteiro REDE_PARAMS = 125

// Validadores puros (spec secao 7.1). Nao acessam arrays.
funcao logico rede_id_valido(inteiro id)
{
    se (id >= 0 e id < REDE_TAM_VOCAB)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico rede_saida_valida(inteiro y)
{
    se (y >= 0 e y < REDE_SAIDAS)
    {
        retorne verdadeiro
    }
    retorne falso
}

funcao logico rede_dim_valida(inteiro dimensao)
{
    se (dimensao >= 0 e dimensao < REDE_ENTRADAS)
    {
        retorne verdadeiro
    }
    retorne falso
}

// Grava os 125 parametros canonicos, sem ler o estado anterior (idempotente).
funcao inicializar_rede(real pesos[], real vieses[])
{
    inteiro y = 0
    enquanto (y < REDE_SAIDAS)
    {
        inteiro d = 0
        enquanto (d < REDE_ENTRADAS)
        {
            pesos[y * REDE_ENTRADAS + d] = (((y * 7 + d * 5) % 25) - 12) / 16.0
            d = d + 1
        }
        vieses[y] = (((y * 7) % 9) - 4) / 16.0
        y = y + 1
    }
}

// Calculo puro (spec secao 5.1) na ordem normativa da secao 5.2:
// quatro produtos da esquerda para a direita, comecando em 0.0, e o vies por
// ultimo. Nao valida indices e nao muta os vetores.
funcao real rede_logit(real pesos[], real vieses[], real emb[], inteiro id, inteiro y)
{
    real soma = 0.0
    inteiro dimensao = 0
    enquanto (dimensao < REDE_ENTRADAS)
    {
        soma = soma + pesos[y * REDE_ENTRADAS + dimensao] * emb[id * REDE_ENTRADAS + dimensao]
        dimensao = dimensao + 1
    }
    soma = soma + vieses[y]
    retorne soma
}

// Argmax normativo (spec secao 5.5): inicializa com o logit 0, varre 1..24
// com comparacao estrita; empate fica com o menor y.
funcao inteiro rede_argmax(real pesos[], real vieses[], real emb[], inteiro id)
{
    inteiro melhor = 0
    real melhor_valor = rede_logit(pesos, vieses, emb, id, 0)
    inteiro y = 1
    enquanto (y < REDE_SAIDAS)
    {
        real valor = rede_logit(pesos, vieses, emb, id, y)
        se (valor > melhor_valor)
        {
            melhor_valor = valor
            melhor = y
        }
        y = y + 1
    }
    retorne melhor
}

// Impressao total: valida o ID antes de acessar arrays.
funcao rede_imprimir_argmax(real pesos[], real vieses[], real emb[], inteiro id)
{
    se (nao rede_id_valido(id))
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }

    escreva("ARGMAX=", id, " ", rede_argmax(pesos, vieses, emb, id), "\n")
}

// Impressao total do vetor de 25 logits. Valida o ID antes de acessar arrays.
funcao rede_imprimir_logits(real pesos[], real vieses[], real emb[], inteiro id)
{
    se (nao rede_id_valido(id))
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }

    escreva("LOGITS=", id)
    inteiro y = 0
    enquanto (y < REDE_SAIDAS)
    {
        escreva(" ", rede_logit(pesos, vieses, emb, id, y))
        y = y + 1
    }
    escreva("\n")
}

// Ordem de validacao: ID antes da saida.
funcao rede_imprimir_logit(real pesos[], real vieses[], real emb[], inteiro id, inteiro y)
{
    se (nao rede_id_valido(id))
    {
        escreva("ERRO=ID_INVALIDO\n")
        retorne
    }

    se (nao rede_saida_valida(y))
    {
        escreva("ERRO=SAIDA_INVALIDA\n")
        retorne
    }

    escreva("LOGIT=", id, " ", y, " ",
        rede_logit(pesos, vieses, emb, id, y), "\n")
}

// Mutacao explicita (spec secao 7.5). Pre-condicao: indices validos.
// Grava qualquer real, sem clamp, sem arredondamento e sem normalizacao.
funcao rede_definir_peso(real pesos[], inteiro y, inteiro dimensao, real valor)
{
    pesos[y * REDE_ENTRADAS + dimensao] = valor
}

funcao rede_definir_bias(real vieses[], inteiro y, real valor)
{
    vieses[y] = valor
}

funcao inteiro rede_bit(logico valor)
{
    se (valor)
    {
        retorne 1
    }
    retorne 0
}

funcao rede_imprimir_info()
{
    escreva("INFO=", REDE_TAM_VOCAB, " ", REDE_ENTRADAS, " ", REDE_PARAMS, "\n")
}

// I1 e I2 da spec secao 3.3, conferidas em tempo de execucao.
funcao rede_imprimir_layout()
{
    se (REDE_SAIDAS * REDE_ENTRADAS == REDE_TOTAL e REDE_TOTAL + REDE_SAIDAS == REDE_PARAMS)
    {
        escreva("LAYOUT=OK\n")
    }
    senao
    {
        escreva("LAYOUT=ERRO\n")
    }
}

// Impressao total: valida antes de acessar o vetor.
funcao rede_imprimir_peso(real pesos[], inteiro y, inteiro dimensao)
{
    se (nao rede_saida_valida(y))
    {
        escreva("ERRO=SAIDA_INVALIDA\n")
        retorne
    }

    se (nao rede_dim_valida(dimensao))
    {
        escreva("ERRO=DIMENSAO_INVALIDA\n")
        retorne
    }

    escreva("PARAM=", y, " ", dimensao, " ",
        pesos[y * REDE_ENTRADAS + dimensao], "\n")
}

funcao rede_imprimir_bias(real vieses[], inteiro y)
{
    se (nao rede_saida_valida(y))
    {
        escreva("ERRO=SAIDA_INVALIDA\n")
        retorne
    }

    escreva("BIAS=", y, " ", vieses[y], "\n")
}

funcao rede_imprimir_validadores(inteiro id, inteiro y, inteiro dimensao)
{
    escreva("VALIDO=ID ", rede_bit(rede_id_valido(id)), "\n")
    escreva("VALIDO=SAIDA ", rede_bit(rede_saida_valida(y)), "\n")
    escreva("VALIDO=DIM ", rede_bit(rede_dim_valida(dimensao)), "\n")
}
