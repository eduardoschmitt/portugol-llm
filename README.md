# Portugol LLM

Projeto experimental para estudar e implementar uma mini-LLM em Portugol.

## Objetivo

Construir incrementalmente componentes de um modelo de linguagem, com testes reproduzíveis e documentação das limitações reais do ambiente.

## Ambiente previsto

- Windows 11
- Portugol Studio (a instalar e validar)
- PowerShell
- Git
- WSL2 opcional

## Estado

**M0 — Preparação do ambiente (pendente).** Nenhuma capacidade de execução ou treinamento foi validada.

## Estrutura

- `src/`: implementação em Portugol.
- `tests/`: testes.
- `scripts/`: automação.
- `docs/`: especificações e decisões.
- `temp/`: arquivos descartáveis do agente, ignorados pelo Git.

## Próximos passos

1. Instalar Portugol Studio a partir de fonte oficial.
2. Identificar a versão e verificar execução por terminal.
3. Criar e automatizar um programa mínimo.
4. Somente depois, especificar o tokenizador e o modelo.

## Regras

Consulte `AGENTS.md`. Não declarar funcionalidades prontas sem execução e evidências.
