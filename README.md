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

**M0 — Preparação do ambiente: CONCLUÍDO** (verificado em 2026-10-24).

### Evidências de execução

Validação realizada em 2026-10-24, no Windows PowerShell 5.1.

**Suíte padrão:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

Resultado: **5 PASS / 0 FAIL / EXIT_CODE=0**.

**Autoteste negativo:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -SelfTest
```

Resultado: **0 PASS / 1 FAIL intencional / EXIT_CODE=1**.

O autoteste confirma que o runner detecta saídas incorretas e retorna código de erro.

A suíte padrão valida execução correta, erro de runtime, erro de sintaxe, arquivo inexistente e interpretador indisponível.

### Limitações conhecidas do ambiente

- O interpretador `portugol-console.bat` sempre retorna `EXIT_CODE=0`, mesmo em erros de runtime. O runner valida por conteúdo de saída, não por exit code do processo.
- O interpretador emite stderr em CP1252 (ANSI da JVM). O runner detecta a página ANSI do sistema dinamicamente (`ANSICodePage`) para evitar artefatos em caracteres acentuados.
- O arquivo `scripts/test.ps1` requer **UTF-8 BOM** para ser lido corretamente pelo PowerShell 5.x sem artefatos em strings com acentos.

## Estrutura

- `src/`: implementação em Portugol.
- `tests/`: testes.
- `scripts/`: automação (`test.ps1` — runner de testes).
- `docs/`: especificações e decisões.
- `temp/`: arquivos descartáveis do agente, ignorados pelo Git.

## Próximos passos

1. ~~Instalar Portugol Studio e validar execução por terminal.~~ ✅
2. ~~Criar e automatizar programa mínimo com testes reproduzíveis.~~ ✅
3. Especificar M1: tokenizador mínimo em Portugol (só após M0 verificado).
4. Implementar e testar o tokenizador com o runner existente.

## Regras

Consulte `AGENTS.md`. Não declarar funcionalidades prontas sem execução e evidências.
