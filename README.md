# quantum-claude-plugins

Marketplace de plugins do Claude Code da equipe Quantum.

## Plugins disponiveis

### delphi-tools

Skills para o fluxo de desenvolvimento Delphi:

- **delphi-fix-encoding** — normaliza o encoding dos arquivos alterados/novos do
  repositorio git para UTF-8 com BOM, detectando a origem (ANSI/Windows-1252,
  UTF-8 sem BOM, UTF-16) para preservar os acentos. Toca **somente** nos arquivos
  que estao de fato quebrados, para o diff nao inchar. Use antes de commitar.
  Tambem verifica/converte arquivos ou pastas especificas via `-Path`.
- **delphi-remove-comments** — remove os comentarios (`//` e `{ }`) e linhas em
  branco ADICIONADOS no diff de fontes Delphi (.pas/.dpr/.dpk/.inc), preservando
  diretivas `{$...}`, comentarios `(* *)` e conteudo dentro de strings. Roda em
  preview por padrao; so altera com `-Apply`.

## Como instalar

### A partir do GitHub

```
/plugin marketplace add gabriel-guarda/quantum-claude-plugins
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

### delphi-fix-encoding

Tres modos de uso; basta pedir em portugues que o Claude escolhe o modo certo:

| Pedido (exemplo)                                   | O que acontece |
|----------------------------------------------------|----------------|
| "arruma o encoding dos arquivos antes do commit"   | converte todos os arquivos do diff do git (alterados + novos) para UTF-8 com BOM |
| "verifica o encoding da unit UCadProduto.pas"      | so VERIFICA o(s) arquivo(s) indicado(s) e reporta o encoding detectado, sem alterar nada (`-Path` + `-WhatIf`) |
| "converte a pasta Dao\ para UTF-8 com BOM"         | converte apenas os arquivos/pastas indicados (`-Path`), sem depender do diff nem de git |

Para rodar o script diretamente (fora do Claude):

```
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin>\skills\delphi-fix-encoding\Fix-DiffEncoding.ps1              # diff do git
powershell -NoProfile -ExecutionPolicy Bypass -File ...\Fix-DiffEncoding.ps1 -WhatIf                                      # diff, so verificar
powershell -NoProfile -ExecutionPolicy Bypass -File ...\Fix-DiffEncoding.ps1 -Path "UCadProduto.pas" -WhatIf              # unit especifica, so verificar
powershell -NoProfile -ExecutionPolicy Bypass -File ...\Fix-DiffEncoding.ps1 -Path "Dao\*.pas" "Controller\"              # curingas e pastas (recursivo)
powershell -NoProfile -ExecutionPolicy Bypass -File ...\Fix-DiffEncoding.ps1 -BomEmAscii                                   # forca BOM ate em arquivos sem acento
```

Detalhes do `-Path`: aceita varios caminhos (soltos ou separados por `,`/`;`),
curingas e diretorios (varridos recursivamente); nao exige repositorio git.

#### O que NAO e tocado

O objetivo e que o diff contenha apenas o que realmente estava com encoding
quebrado:

- Arquivos **ja em UTF-8 com BOM** nunca sao reescritos.
- Arquivos **100% ASCII** (nenhum acento) sao deixados intactos: nesse caso ANSI e
  UTF-8 sao identicos byte a byte, nao ha nada quebrado, e inserir o BOM so criaria
  ruido no diff. Passe `-BomEmAscii` se quiser forcar o BOM em todos.
- **Binarios** sao pulados (extensao conhecida, byte nulo ou muitos bytes de controle).
- **UTF-8 corrompido/misto** e **mojibake** sao apenas avisados para revisao manual,
  nunca convertidos automaticamente.

#### Preservacao do conteudo

So a codificacao muda. Espacos, indentacao, linhas em branco e quebras de linha
(CRLF) ficam intactos — `git diff -w` retorna o mesmo que o diff normal. Depois de
gravar, o script rele o arquivo e confere que o texto decodificado bate exatamente
com o original; se divergir, restaura os bytes originais e reporta erro. Na pratica
as unicas linhas que mudam sao as que contem acentos, mais o BOM na linha 1.

### delphi-remove-comments

Peca algo como "remove os comentarios que a IA adicionou no diff". Roda em
preview por padrao e mostra o que seria removido; a remocao de fato so
acontece com `-Apply` (o Claude pede confirmacao antes de aplicar).

## Atualizacao

Quando o marketplace receber novas versoes:

```
/plugin marketplace update quantum-tools
```
