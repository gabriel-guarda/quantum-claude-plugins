# quantum-claude-plugins

Marketplace de plugins do Claude Code da equipe Quantum.

## Plugins disponiveis

### delphi-tools

Skills para o fluxo de desenvolvimento Delphi:

- **delphi-fix-encoding** — normaliza o encoding dos arquivos alterados/novos do
  repositorio git para UTF-8 com BOM, detectando a origem (ANSI/Windows-1252,
  UTF-8 sem BOM, UTF-16) para preservar os acentos. Use antes de commitar.
- **delphi-remove-comments** — remove os comentarios (`//` e `{ }`) e linhas em
  branco ADICIONADOS no diff de fontes Delphi (.pas/.dpr/.dpk/.inc), preservando
  diretivas `{$...}`, comentarios `(* *)` e conteudo dentro de strings. Roda em
  preview por padrao; so altera com `-Apply`.

## Como instalar

### A partir do GitHub (apos publicar este repositorio)

```
/plugin marketplace add <org-ou-usuario>/quantum-claude-plugins
/plugin install delphi-tools@quantum-tools
```

### A partir de uma pasta local ou da rede

```
/plugin marketplace add D:\Projetos\quantum-claude-plugins
/plugin install delphi-tools@quantum-tools
```

(funciona tambem com um caminho de rede compartilhado, ex. `\\servidor\compartilhamento\quantum-claude-plugins`)

## Como usar

Depois de instalado, as skills sao invocadas com o namespace do plugin:

```
/delphi-tools:delphi-fix-encoding
/delphi-tools:delphi-remove-comments
```

O Claude tambem aciona as skills automaticamente quando o pedido combina com a
descricao delas (ex.: "arruma o encoding dos arquivos antes do commit").

## Atualizacao

Quando o marketplace receber novas versoes:

```
/plugin marketplace update quantum-tools
```
