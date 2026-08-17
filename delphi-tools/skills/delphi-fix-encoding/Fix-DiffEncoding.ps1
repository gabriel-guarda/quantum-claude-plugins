<#
.SYNOPSIS
    Converte para UTF-8 com BOM todos os arquivos alterados e novos (untracked)
    do repositorio git atual, detectando a codificacao de origem para preservar
    os acentos (ANSI/Windows-1252, UTF-8 sem BOM, UTF-16).

.DESCRIPTION
    Coleta os arquivos que entrariam no proximo commit:
      - alteracoes rastreadas vs HEAD (staged + working tree)
      - arquivos novos nao rastreados (respeitando .gitignore)
    Para cada arquivo de texto, detecta a codificacao atual, le o conteudo e
    regrava como UTF-8 com BOM. Seguranca:
      - Arquivos binarios (extensao conhecida, byte nulo ou muitos bytes de
        controle) sao pulados.
      - Arquivos ja em UTF-8 com BOM nao sao tocados.
      - O fallback para Windows-1252 so e aplicado quando o arquivo NAO tem
        nenhuma sequencia UTF-8 valida (ANSI puro). Se houver sequencias UTF-8
        validas E bytes invalidos (arquivo corrompido/misto), o arquivo NAO e
        alterado e e marcado para revisao manual -> evita gerar mojibake.
      - Arquivos em UTF-8 valido sao varridos em busca de mojibake (acentos
        quebrados tipo C3-xx) e apenas AVISADOS, nunca alterados.

.PARAMETER WhatIf
    Apenas mostra o que seria convertido, sem gravar nada.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File Fix-DiffEncoding.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File Fix-DiffEncoding.ps1 -WhatIf
#>
[CmdletBinding()]
param(
    [switch]$WhatIf
)

# --- Verifica repositorio git --------------------------------------------------
$null = git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: diretorio atual nao e um repositorio git (ou git nao encontrado)." -ForegroundColor Red
    exit 1
}

$root = (git rev-parse --show-toplevel).Trim()

# --- Coleta arquivos candidatos ------------------------------------------------
$files = New-Object 'System.Collections.Generic.HashSet[string]'

git rev-parse --verify HEAD *> $null
$hasHead = ($LASTEXITCODE -eq 0)

if ($hasHead) {
    git -c core.quotepath=false diff --name-only HEAD |
        ForEach-Object { if ($_ -and $_.Trim()) { [void]$files.Add($_.Trim()) } }
} else {
    # repositorio sem nenhum commit ainda: usa o que esta no index
    git -c core.quotepath=false diff --cached --name-only |
        ForEach-Object { if ($_ -and $_.Trim()) { [void]$files.Add($_.Trim()) } }
}

# arquivos novos nao rastreados (respeita .gitignore)
git -c core.quotepath=false ls-files --others --exclude-standard |
    ForEach-Object { if ($_ -and $_.Trim()) { [void]$files.Add($_.Trim()) } }

if ($files.Count -eq 0) {
    Write-Host "Nenhum arquivo alterado ou novo encontrado no diff." -ForegroundColor Yellow
    exit 0
}

# --- Encodings -----------------------------------------------------------------
$utf8Bom    = New-Object System.Text.UTF8Encoding($true)         # com BOM
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true) # sem BOM, lanca em bytes invalidos
$win1252    = [System.Text.Encoding]::GetEncoding(1252)

# --- Deteccao de binario -------------------------------------------------------
$binExt = @(
    '.pdf','.dcu','.dcp','.bpl','.res','.exe','.dll','.ocx','.obj','.lib','.a','.so',
    '.png','.jpg','.jpeg','.gif','.bmp','.ico','.cur','.wmf','.emf','.tif','.tiff',
    '.zip','.rar','.7z','.gz','.tar','.jar','.class',
    '.docx','.xlsx','.pptx','.doc','.xls','.ppt','.mdb','.fdb','.gdb','.db','.dat','.bin'
)

function Test-IsBinary {
    param([byte[]]$Bytes, [string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($binExt -contains $ext) { return $true }
    if ($Bytes.Length -eq 0)    { return $false }

    $scan = [Math]::Min($Bytes.Length, 65536)
    $control = 0
    for ($i = 0; $i -lt $scan; $i++) {
        $b = $Bytes[$i]
        if ($b -eq 0) { return $true }   # byte nulo => binario
        # bytes de controle, exceto TAB(9), LF(10), FF(12), CR(13)
        if (($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 12 -and $b -ne 13) -or $b -eq 127) {
            $control++
        }
    }
    return (($control / $scan) -gt 0.10)   # >10% de controle => provavelmente binario
}

# Conta sequencias UTF-8 multibyte validas vs bytes altos invalidos.
# Distingue ANSI puro (0 validas) de UTF-8 corrompido/misto (>0 validas).
function Get-Utf8MultibyteStats {
    param([byte[]]$Bytes)
    $n = $Bytes.Length; $i = 0; $valid = 0; $invalid = 0
    while ($i -lt $n) {
        $b = $Bytes[$i]
        if ($b -lt 0x80) { $i++; continue }                                  # ASCII
        elseif ($b -ge 0xC2 -and $b -le 0xDF) {                              # lead de 2 bytes
            if ($i+1 -lt $n -and $Bytes[$i+1] -ge 0x80 -and $Bytes[$i+1] -le 0xBF) { $valid++; $i += 2 } else { $invalid++; $i++ }
        }
        elseif ($b -ge 0xE0 -and $b -le 0xEF) {                              # lead de 3 bytes
            if ($i+2 -lt $n -and $Bytes[$i+1] -ge 0x80 -and $Bytes[$i+1] -le 0xBF -and $Bytes[$i+2] -ge 0x80 -and $Bytes[$i+2] -le 0xBF) { $valid++; $i += 3 } else { $invalid++; $i++ }
        }
        elseif ($b -ge 0xF0 -and $b -le 0xF4) {                              # lead de 4 bytes
            if ($i+3 -lt $n -and $Bytes[$i+1] -ge 0x80 -and $Bytes[$i+1] -le 0xBF -and $Bytes[$i+2] -ge 0x80 -and $Bytes[$i+2] -le 0xBF -and $Bytes[$i+3] -ge 0x80 -and $Bytes[$i+3] -le 0xBF) { $valid++; $i += 4 } else { $invalid++; $i++ }
        }
        else { $invalid++; $i++ }                                            # 0x80-0xBF solto, 0xC0/0xC1, 0xF5-0xFF
    }
    return [pscustomobject]@{ ValidMultibyte = $valid; InvalidBytes = $invalid }
}

# Detecta padroes tipicos de mojibake PT-BR (UTF-8 que ja foi lido como Windows-1252):
# U+00C3/U+00C2/U+00E2 seguidos de um byte de continuacao U+0080-U+00BF.
$mojibakeRegex = [regex]"[ÂÃâ][-¿]"
function Get-MojibakeCount {
    param([string]$Text)
    return $mojibakeRegex.Matches($Text).Count
}

$converted     = @()
$alreadyOk     = 0
$skippedBinary = @()
$ambiguous     = @()
$mojibake      = @()
$missing       = 0
$errors        = @()

foreach ($rel in $files) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing++; continue }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -eq 0) { $alreadyOk++; continue }

        # Deteccao de binario (extensao conhecida, byte nulo ou muitos bytes de controle)
        if (Test-IsBinary -Bytes $bytes -Path $path) { $skippedBinary += $rel; continue }

        # Ja esta em UTF-8 com BOM? -> nao reescreve, mas verifica mojibake.
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $alreadyOk++
            $mj = Get-MojibakeCount ([System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3))
            if ($mj -gt 0) { $mojibake += [pscustomobject]@{ Arquivo = $rel; Ocorrencias = $mj } }
            continue
        }

        $text = $null
        $sourceEnc = $null
        $checkMojibake = $false

        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
            $sourceEnc = 'UTF-16 LE'
        }
        elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
            $sourceEnc = 'UTF-16 BE'
        }
        else {
            try {
                $text = $utf8Strict.GetString($bytes)   # decodifica em UTF-8 estrito
                $sourceEnc = 'UTF-8 (sem BOM)'
                $checkMojibake = $true                  # ja era UTF-8: pode conter mojibake
            } catch {
                # UTF-8 estrito falhou: decidir entre ANSI puro e UTF-8 corrompido/misto.
                $stats = Get-Utf8MultibyteStats $bytes
                if ($stats.ValidMultibyte -eq 0) {
                    $text = $win1252.GetString($bytes)  # ANSI/Windows-1252 puro -> conversao segura
                    $sourceEnc = 'ANSI (Windows-1252)'
                } else {
                    # Tem sequencias UTF-8 validas E bytes invalidos: converter como 1252
                    # geraria mojibake nas partes ja-UTF-8. NAO converte; pede revisao manual.
                    $ambiguous += [pscustomobject]@{ Arquivo = $rel; Validas = $stats.ValidMultibyte; Invalidos = $stats.InvalidBytes }
                    continue
                }
            }
        }

        if ($checkMojibake) {
            $mj = Get-MojibakeCount $text
            if ($mj -gt 0) { $mojibake += [pscustomobject]@{ Arquivo = $rel; Ocorrencias = $mj } }
        }

        if (-not $WhatIf) {
            [System.IO.File]::WriteAllText($path, $text, $utf8Bom)
        }
        $converted += [pscustomobject]@{ Arquivo = $rel; Origem = $sourceEnc }
    }
    catch {
        $errors += [pscustomobject]@{ Arquivo = $rel; Erro = $_.Exception.Message }
    }
}

# --- Relatorio -----------------------------------------------------------------
$acao = if ($WhatIf) { "SERIAM convertidos (modo -WhatIf, nada gravado)" } else { "Convertidos para UTF-8 com BOM" }

Write-Host ""
Write-Host "=== Fix-DiffEncoding ===" -ForegroundColor Cyan
Write-Host ("Repositorio : {0}" -f $root)
Write-Host ("Candidatos  : {0}" -f $files.Count)
Write-Host ""

if ($converted.Count -gt 0) {
    Write-Host ("{0}: {1}" -f $acao, $converted.Count) -ForegroundColor Green
    $converted | ForEach-Object { Write-Host ("  - {0}  [origem: {1}]" -f $_.Arquivo, $_.Origem) }
} else {
    Write-Host "Nenhum arquivo precisou de conversao." -ForegroundColor Green
}

if ($alreadyOk -gt 0)            { Write-Host ("Ja em UTF-8 com BOM : {0}" -f $alreadyOk) }

if ($skippedBinary.Count -gt 0)  {
    Write-Host ("Pulados (binarios)  : {0}" -f $skippedBinary.Count) -ForegroundColor Yellow
    $skippedBinary | ForEach-Object { Write-Host ("  - {0}" -f $_) }
}

if ($ambiguous.Count -gt 0) {
    Write-Host ("Pulados (UTF-8 corrompido/misto - revisar manual): {0}" -f $ambiguous.Count) -ForegroundColor Yellow
    $ambiguous | ForEach-Object { Write-Host ("  - {0}  (seq UTF-8 validas: {1}, bytes invalidos: {2})" -f $_.Arquivo, $_.Validas, $_.Invalidos) -ForegroundColor Yellow }
}

if ($mojibake.Count -gt 0) {
    Write-Host ""
    Write-Host ("AVISO: possivel MOJIBAKE (acentos quebrados) em UTF-8 valido - NAO alterado, revisar: {0}" -f $mojibake.Count) -ForegroundColor Magenta
    $mojibake | ForEach-Object { Write-Host ("  - {0}  ({1} ocorrencia(s))" -f $_.Arquivo, $_.Ocorrencias) -ForegroundColor Magenta }
}

if ($missing -gt 0)              { Write-Host ("Ignorados (removidos/inexistentes): {0}" -f $missing) }

if ($errors.Count -gt 0) {
    Write-Host ("ERROS: {0}" -f $errors.Count) -ForegroundColor Red
    $errors | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.Arquivo, $_.Erro) -ForegroundColor Red }
    exit 1
}

exit 0
