---
name: delphi-fix-encoding
description: Normaliza o encoding dos arquivos alterados e novos (nao rastreados) do repositorio git para UTF-8 com BOM, tocando SOMENTE nos que estao de fato quebrados (arquivos 100% ASCII e os que ja estao em UTF-8 com BOM ficam intactos, para nao sujar o diff), detectando a origem (ANSI/Windows-1252, UTF-8 sem BOM, UTF-16) para preservar acentos. Com -Path, analisa/converte arquivos ou diretorios especificos (ex.: uma unit) em vez do diff; com -WhatIf apenas verifica sem alterar. Use antes de dar commit em projetos Delphi quando ha problemas de encoding, caracteres acentuados quebrados, para padronizar os arquivos do diff, ou para verificar o encoding de uma unit especifica.
---

# Ajustar encoding do diff (Delphi) -> UTF-8 com BOM

Esta skill converte para **UTF-8 com BOM** todos os arquivos que entrariam no
proximo commit (alteracoes rastreadas vs HEAD + arquivos novos nao rastreados),
detectando a codificacao de origem para nao quebrar os acentos. Com `-Path`,
opera apenas sobre arquivos/diretorios especificos em vez do diff.

## Escolha do modo

- **Diff do git (padrao):** sem `-Path`, processa todos os arquivos alterados e
  novos do repositorio. Exige estar em um repo git.
- **Arquivos especificos (`-Path`):** o usuario indicou uma unit ou pasta
  especifica. Aceita varios caminhos, curingas (`Dao\*.pas`) e diretorios
  (varridos recursivamente). Nao exige git.
- **So verificar (sem alterar):** adicione `-WhatIf` em qualquer modo. A saida
  informa o encoding detectado de cada arquivo (`[origem: ...]`, `Ja em UTF-8
  com BOM`, mojibake etc.) sem gravar nada.
- **Normalizar tudo (`-BomEmAscii`):** por padrao arquivos 100% ASCII nao sao
  tocados. Use essa opcao apenas se o usuario pedir explicitamente para TODOS os
  arquivos ficarem com BOM, aceitando o diff maior.

## Passos

1. **Confirme o escopo.** Se o usuario citou arquivo(s) ou pasta especifica, use
   `-Path`; caso contrario, opere no diff (e confirme que esta em um repo git —
   se nao estiver, avise o usuario). Se o pedido for so "verificar/conferir o
   encoding", inclua `-WhatIf`.

2. **(Opcional) Pre-visualize.** Se o usuario quiser ver o que sera alterado antes,
   rode com `-WhatIf`:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-fix-encoding/Fix-DiffEncoding.ps1" -WhatIf
   ```

3. **Execute:**

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-fix-encoding/Fix-DiffEncoding.ps1"
   ```

   Para uma unit especifica (verificacao e conversao, respectivamente):

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-fix-encoding/Fix-DiffEncoding.ps1" -Path "UCadProduto.pas" -WhatIf
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/delphi-fix-encoding/Fix-DiffEncoding.ps1" -Path "UCadProduto.pas"
   ```

4. **Reporte o resultado** ao usuario com base na saida do script: quantos foram
   convertidos (e de qual encoding de origem), quantos ja estavam OK, quantos eram
   ASCII puro (sem nada a corrigir) e quais foram pulados por serem binarios. No
   modo `-WhatIf`, reporte o encoding detectado de cada arquivo sem alterar nada. **Nao** faca o commit automaticamente — a skill
   so ajusta o encoding; o commit fica a cargo do usuario.

## Como o script decide a codificacao de origem

- Comeca com BOM UTF-8 (`EF BB BF`) -> ja esta correto, **nao mexe**.
- **100% ASCII** (nenhum byte >= 0x80, ou seja, nenhum acento) -> **nao mexe**.
  Nesse caso ANSI e UTF-8 sao identicos byte a byte, nao ha encoding quebrado, e
  inserir o BOM so geraria ruido no diff. Forcavel com `-BomEmAscii`.
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

- O conteudo e preservado integralmente: **espacos, indentacao, linhas em branco e
  quebras de linha (CRLF) nao sao alterados** — so a codificacao muda. Apos gravar,
  o script rele o arquivo e confere que o texto decodificado bate exatamente com o
  original; se divergir, restaura os bytes originais e reporta erro.
- Somente arquivos com problema real de encoding entram no diff.
- Arquivos deletados/inexistentes no diff sao ignorados com seguranca.
- O escopo respeita o `.gitignore` (usa `git ls-files --others --exclude-standard`).
