---
name: delphi-remove-comments
description: Remove os comentarios ADICIONADOS no diff (vs commit) de arquivos-fonte Delphi (.pas/.dpr/.dpk/.inc) — estilos // e { } — e tambem as LINHAS EM BRANCO adicionadas (em arquivos rastreados). Preserva diretivas {$...}, comentarios (* *) e // ou { dentro de strings. Use para limpar comentarios e espacamento que a IA (ou voce) inseriu antes de dar commit. Roda em PREVIEW por padrao; so altera com -Apply.
---

# Remover comentarios adicionados (Delphi)

Esta skill apaga os comentarios que aparecem nas **linhas adicionadas** do diff
(arquivos rastreados modificados vs HEAD + arquivos novos nao rastreados), nos
fontes Delphi. Nao toca em comentarios antigos que ja estavam no arquivo.

- **Remove:** `// ...` (inclusive trailing no fim de uma linha de codigo) e `{ ... }`
  (uma ou varias linhas).
- **Remove tambem linhas EM BRANCO adicionadas** — mas **so em arquivos rastreados**
  (modificados). Em arquivo **novo** as linhas em branco sao preservadas (para nao
  destruir a formatacao do arquivo inteiro); comentarios continuam sendo removidos.
- **Preserva sempre:** diretivas de compilacao `{$...}`, comentarios `(* ... *)`, e
  qualquer `//` ou `{` que esteja **dentro de uma string** `'...'`.
- **Encoding e quebras de linha (CRLF)** sao preservados.

## Passos

1. **Confirme o repositorio.** Opera sobre o repositorio git do diretorio atual.
   Se nao for um repo git, avise o usuario.

2. **Rode o PREVIEW** (nao altera nada) e mostre ao usuario a lista de comentarios
   que seriam removidos:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-remove-comments/Remove-AddedComments.ps1"
   ```

3. **Confirme com o usuario** se a lista esta correta. Como isso altera codigo,
   nao aplique sem o usuario ver o preview (a menos que ele ja tenha pedido direto).

4. **Aplique** com `-Apply`:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-remove-comments/Remove-AddedComments.ps1" -Apply
   ```

5. **Reporte o resultado** (quantos comentarios, quantos arquivos, quantas linhas
   apagadas) e sugira `git diff` para revisao. **Nao** faca commit automaticamente.

## Como decide o que e "adicionado"

- **Arquivo rastreado modificado:** usa `git diff -U0 vs HEAD` para achar as linhas
  adicionadas; so remove comentario cujas linhas estao nesse conjunto. Um comentario
  de bloco `{ }` multilinha so e removido se **todas** as suas linhas forem adicionadas.
- **Arquivo novo nao rastreado:** todas as linhas contam como adicionadas.

## Comportamento de remocao

- Linha que vira **so espaco** depois de remover o comentario e' **apagada**.
- Linha de **codigo + comentario no fim** mantem o codigo (sem o comentario).
- **Linha em branco adicionada** (em arquivo rastreado) e' **apagada**.
- A indentacao do codigo e mantida; sobra de espaco no fim e' aparada.

## Parametros

- `-Apply` : aplica no disco (sem ele, e' apenas preview).
- `-Extensions` : extensoes processadas (default `.pas .dpr .dpk .inc`).

## Observacoes / limites

- Estilos removidos sao `//` e `{ }` (definido no topo do script, em `$RemoveSlash`
  e `$RemoveBrace`). `(* *)` e' propositalmente preservado.
- Diretivas `{$...}` nunca sao removidas.
- Assume que comentarios de bloco `{ }` nao aninham (padrao do Delphi: o primeiro
  `}` fecha o bloco).
