---
name: delphi-fix-encoding
description: Normaliza o encoding de TODOS os arquivos alterados e novos (nao rastreados) do repositorio git para UTF-8 com BOM, detectando a origem (ANSI/Windows-1252, UTF-8 sem BOM, UTF-16) para preservar acentos. Use antes de dar commit em projetos Delphi quando ha problemas de encoding, caracteres acentuados quebrados, ou para padronizar os arquivos do diff.
---

# Ajustar encoding do diff (Delphi) -> UTF-8 com BOM

Esta skill converte para **UTF-8 com BOM** todos os arquivos que entrariam no
proximo commit (alteracoes rastreadas vs HEAD + arquivos novos nao rastreados),
detectando a codificacao de origem para nao quebrar os acentos.

## Passos

1. **Confirme o repositorio.** A skill opera sobre o repositorio git do diretorio
   de trabalho atual. Se nao estiver em um repo git, avise o usuario.

2. **(Opcional) Pre-visualize.** Se o usuario quiser ver o que sera alterado antes,
   rode com `-WhatIf`:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-fix-encoding/Fix-DiffEncoding.ps1" -WhatIf
   ```

3. **Execute a conversao:**

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-fix-encoding/Fix-DiffEncoding.ps1"
   ```

4. **Reporte o resultado** ao usuario com base na saida do script: quantos foram
   convertidos (e de qual encoding de origem), quantos ja estavam OK e quais foram
   pulados por serem binarios. **Nao** faca o commit automaticamente — a skill so
   ajusta o encoding; o commit fica a cargo do usuario.

## Como o script decide a codificacao de origem

- Comeca com BOM UTF-8 (`EF BB BF`) -> ja esta correto, **nao mexe**.
- Comeca com BOM UTF-16 (LE/BE) -> decodifica como UTF-16.
- Decodifica como **UTF-8 estrito**; se passar, era UTF-8 sem BOM -> so adiciona o BOM.
- Se o UTF-8 estrito falhar -> decide com seguranca:
  - **Nenhuma** sequencia UTF-8 valida no arquivo -> assume **ANSI (Windows-1252)**
    (padrao PT-BR do Delphi antigo) e converte.
  - Tem sequencias UTF-8 validas **E** bytes invalidos (arquivo corrompido/misto) ->
    **NAO converte** (converter como 1252 geraria mojibake nas partes ja-UTF-8) e
    marca o arquivo para **revisao manual**.
- **Binarios sao pulados** — detectados por extensao conhecida (`.pdf`, `.res`, `.dcu`,
  imagens, zips, etc.), por byte nulo, ou por alta proporcao de bytes de controle.

## Aviso de mojibake (nao destrutivo)

Arquivos que ja sao UTF-8 valido sao varridos em busca de **mojibake** — acentos
quebrados tipo `Ã©`, `Ã³`, `Ã§` (UTF-8 que em algum momento foi salvo como Windows-1252,
problema comum do proprio Delphi/IDE). Esses arquivos **NAO sao alterados** (o conteudo
e UTF-8 valido, so com caracteres errados); a skill apenas **avisa** para revisao manual,
pois corrigir mojibake automaticamente nao e seguro.

## Observacoes

- O conteudo e as quebras de linha (CRLF) sao preservados — so a codificacao muda.
- Arquivos deletados/inexistentes no diff sao ignorados com seguranca.
- O escopo respeita o `.gitignore` (usa `git ls-files --others --exclude-standard`).
