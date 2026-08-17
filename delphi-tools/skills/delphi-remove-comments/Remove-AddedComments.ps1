<#
.SYNOPSIS
    Remove comentarios ADICIONADOS no diff (vs HEAD) de arquivos-fonte Delphi.
    Estilos removidos: comentario de linha //  e comentario de bloco { ... }.
    PRESERVA: diretivas de compilacao {$...}, comentarios (* ... *), e qualquer
    // ou { que esteja dentro de uma string Pascal '...'.

.DESCRIPTION
    Para arquivos rastreados modificados, so remove comentarios que aparecem nas
    LINHAS ADICIONADAS (git diff -U0 vs HEAD). Para arquivos novos nao rastreados,
    todas as linhas contam como adicionadas.

    Comportamento de remocao:
      - // ...            -> remove ate o fim da linha (inclui trailing em linha de codigo).
      - { ... }           -> remove o bloco (uma ou varias linhas), se TODAS as linhas
                            do bloco forem linhas adicionadas.
      - Linha que vira so espaco apos remover o comentario e' apagada.
      - Linha de codigo com comentario no fim mantem o codigo (sem o comentario).

    Encoding e quebras de linha sao preservados.

.PARAMETER Apply
    Aplica as remocoes no disco. SEM esse switch o script so mostra um PREVIEW.

.PARAMETER Extensions
    Extensoes de arquivo a processar. Default: .pas .dpr .dpk .inc

.EXAMPLE
    # preview (nao altera nada)
    powershell -NoProfile -ExecutionPolicy Bypass -File Remove-AddedComments.ps1
    # aplicar
    powershell -NoProfile -ExecutionPolicy Bypass -File Remove-AddedComments.ps1 -Apply
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string[]]$Extensions = @('.pas','.dpr','.dpk','.inc')
)

# Estilos a remover (conforme escolha do usuario):
$RemoveSlash = $true   # //
$RemoveBrace = $true   # { ... }   (diretivas {$...} sempre preservadas)

# --- Verifica repositorio git --------------------------------------------------
$null = git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: diretorio atual nao e um repositorio git (ou git nao encontrado)." -ForegroundColor Red
    exit 1
}
$root = (git rev-parse --show-toplevel).Trim()

git rev-parse --verify HEAD *> $null
$hasHead = ($LASTEXITCODE -eq 0)

# --- Coleta candidatos (so extensoes de fonte) ---------------------------------
$extLower = $Extensions | ForEach-Object { $_.ToLowerInvariant() }
function Test-WantedExt([string]$p) {
    return ($extLower -contains ([System.IO.Path]::GetExtension($p)).ToLowerInvariant())
}

$tracked   = New-Object 'System.Collections.Generic.HashSet[string]'
$untracked = New-Object 'System.Collections.Generic.HashSet[string]'

if ($hasHead) {
    git -c core.quotepath=false diff --name-only HEAD |
        ForEach-Object { if ($_ -and (Test-WantedExt $_)) { [void]$tracked.Add($_.Trim()) } }
}
git -c core.quotepath=false ls-files --others --exclude-standard |
    ForEach-Object { if ($_ -and (Test-WantedExt $_)) { [void]$untracked.Add($_.Trim()) } }

$allFiles = @($tracked) + @($untracked) | Sort-Object -Unique
if ($allFiles.Count -eq 0) {
    Write-Host "Nenhum arquivo-fonte Delphi alterado/novo no diff." -ForegroundColor Yellow
    exit 0
}

# --- Helpers -------------------------------------------------------------------

# Linhas adicionadas (1-based) de um arquivo rastreado, via git diff -U0.
function Get-AddedLines([string]$rel) {
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    $newLine = 0
    foreach ($dl in (git -c core.quotepath=false diff -U0 --no-color -- $rel)) {
        if ($dl -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') { $newLine = [int]$Matches[1]; continue }
        if ($dl.StartsWith('+++') -or $dl.StartsWith('---') -or $dl.StartsWith('\')) { continue }
        if ($dl.StartsWith('+')) { [void]$set.Add($newLine); $newLine++; continue }
        if ($dl.StartsWith('-')) { continue }
    }
    return $set
}

# Acha o fim de um token ('}' ou '*)') a partir de (sl,sc), varrendo varias linhas.
# Retorna Line (0-based) e Col (0-based, ultima posicao do token).
function Find-Close($lines, [int]$sl, [int]$sc, [string]$token) {
    $li = $sl; $from = $sc
    while ($li -lt $lines.Count) {
        $idx = $lines[$li].IndexOf($token, [Math]::Min($from, $lines[$li].Length))
        if ($idx -ge 0) { return [pscustomobject]@{ Line = $li; Col = ($idx + $token.Length - 1) } }
        $li++; $from = 0
    }
    $last = $lines.Count - 1
    return [pscustomobject]@{ Line = $last; Col = [Math]::Max(0, $lines[$last].Length - 1) }
}

# Lexer Pascal: retorna lista de spans de comentario { Kind; SL; SC; EL; EC }.
# Reconhece strings '...', // , { } , {$...} (directive=flag), (* *).
function Get-CommentSpans($lines) {
    $spans = New-Object System.Collections.ArrayList
    $li = 0
    while ($li -lt $lines.Count) {
        $line = $lines[$li]
        $L = $line.Length
        $ci = 0
        while ($ci -lt $L) {
            $ch = $line[$ci]

            if ($ch -eq "'") {                       # string literal (nao cruza linha)
                $ci++
                while ($ci -lt $L) {
                    if ($line[$ci] -eq "'") {
                        if (($ci + 1) -lt $L -and $line[$ci + 1] -eq "'") { $ci += 2; continue }
                        $ci++; break
                    }
                    $ci++
                }
                continue
            }

            if ($ch -eq '/' -and ($ci + 1) -lt $L -and $line[$ci + 1] -eq '/') {   # // ate fim da linha
                [void]$spans.Add([pscustomobject]@{ Kind = '//'; SL = $li; SC = $ci; EL = $li; EC = ($L - 1) })
                $ci = $L
                continue
            }

            if ($ch -eq '{') {                       # bloco { } ou diretiva {$...}
                $isDir = (($ci + 1) -lt $L -and $line[$ci + 1] -eq '$')
                $close = Find-Close $lines $li ($ci + 1) '}'
                if (-not $isDir) {
                    [void]$spans.Add([pscustomobject]@{ Kind = '{}'; SL = $li; SC = $ci; EL = $close.Line; EC = $close.Col })
                }
                $li = $close.Line; $line = $lines[$li]; $L = $line.Length; $ci = $close.Col + 1
                continue
            }

            if ($ch -eq '(' -and ($ci + 1) -lt $L -and $line[$ci + 1] -eq '*') {   # (* *) -> reconhece, NAO remove
                $close = Find-Close $lines $li ($ci + 2) '*)'
                $li = $close.Line; $line = $lines[$li]; $L = $line.Length; $ci = $close.Col + 1
                continue
            }

            $ci++
        }
        $li++
    }
    return $spans
}

# --- Processa cada arquivo -----------------------------------------------------
$totalRemovedComments = 0
$totalDroppedLines    = 0
$totalBlankLines      = 0
$filesChanged         = @()

foreach ($rel in $allFiles) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0) { continue }

    # encoding (preservar na escrita)
    $writeEnc = $null; $text = $null
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        $writeEnc = New-Object System.Text.UTF8Encoding($true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        $writeEnc = [System.Text.Encoding]::Unicode
    } else {
        try {
            $strict = New-Object System.Text.UTF8Encoding($false, $true)
            $text = $strict.GetString($bytes)
            $writeEnc = New-Object System.Text.UTF8Encoding($false)
        } catch {
            $text = ([System.Text.Encoding]::GetEncoding(1252)).GetString($bytes)
            $writeEnc = [System.Text.Encoding]::GetEncoding(1252)
        }
    }

    $eol = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } else { "`r" }
    $endsWithEol = ($text.Length -gt 0 -and ($text.EndsWith("`n") -or $text.EndsWith("`r")))
    $lines = [System.Collections.ArrayList]@($text -split "`r`n|`r|`n")
    if ($endsWithEol -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $lineArr = $lines.ToArray()

    # linhas adicionadas
    $isUntracked = $untracked.Contains($rel)
    if ($isUntracked) {
        $added = $null   # null = todas as linhas contam
    } else {
        $added = Get-AddedLines $rel
        if ($added.Count -eq 0) { continue }
    }
    function Test-Added([int]$lineNo) {
        if ($null -eq $added) { return $true }
        return $added.Contains($lineNo)
    }

    # spans removiveis
    $spans = Get-CommentSpans $lineArr
    $removable = @()
    foreach ($s in $spans) {
        if ($s.Kind -eq '//' -and -not $RemoveSlash) { continue }
        if ($s.Kind -eq '{}' -and -not $RemoveBrace) { continue }
        $allAdded = $true
        for ($n = ($s.SL + 1); $n -le ($s.EL + 1); $n++) { if (-not (Test-Added $n)) { $allAdded = $false; break } }
        if ($allAdded) { $removable += $s }
    }

    # linhas EM BRANCO adicionadas (so em arquivos rastreados; novos preservam formatacao)
    $addedBlankLines = New-Object 'System.Collections.Generic.HashSet[int]'
    if (-not $isUntracked) {
        for ($bi = 0; $bi -lt $lineArr.Count; $bi++) {
            if ($lineArr[$bi].Trim() -eq '' -and (Test-Added ($bi + 1))) { [void]$addedBlankLines.Add($bi) }
        }
    }

    if ($removable.Count -eq 0 -and $addedBlankLines.Count -eq 0) { continue }

    # marca caracteres removidos por linha
    $removeMask = @{}
    function Mark([int]$ln, [int]$a, [int]$b) {
        if (-not $removeMask.ContainsKey($ln)) { $removeMask[$ln] = New-Object 'bool[]' ($lineArr[$ln].Length) }
        $m = $removeMask[$ln]
        for ($k = $a; $k -le $b -and $k -lt $m.Length; $k++) { $m[$k] = $true }
    }
    foreach ($s in $removable) {
        if ($s.SL -eq $s.EL) {
            Mark $s.SL $s.SC $s.EC
        } else {
            Mark $s.SL $s.SC ($lineArr[$s.SL].Length - 1)
            for ($mid = $s.SL + 1; $mid -lt $s.EL; $mid++) { Mark $mid 0 ($lineArr[$mid].Length - 1) }
            Mark $s.EL 0 $s.EC
        }
    }

    # reconstroi linhas
    $newLines = New-Object System.Collections.ArrayList
    $droppedComments = 0
    $droppedBlanks   = 0
    for ($i = 0; $i -lt $lineArr.Count; $i++) {
        if ($addedBlankLines.Contains($i)) { $droppedBlanks++; continue }   # linha em branco adicionada -> apaga
        if (-not $removeMask.ContainsKey($i)) { [void]$newLines.Add($lineArr[$i]); continue }
        $orig = $lineArr[$i]
        $m = $removeMask[$i]
        $sb = New-Object System.Text.StringBuilder
        for ($k = 0; $k -lt $orig.Length; $k++) { if (-not $m[$k]) { [void]$sb.Append($orig[$k]) } }
        $newContent = $sb.ToString()
        if ($newContent.Trim() -eq '' -and $orig.Trim() -ne '') {
            $droppedComments++   # linha era so comentario -> apaga
        } else {
            [void]$newLines.Add($newContent.TrimEnd())
        }
    }

    $newText = [string]::Join($eol, $newLines.ToArray())
    if ($endsWithEol) { $newText += $eol }

    $blankNos = @($addedBlankLines) | ForEach-Object { $_ + 1 } | Sort-Object
    $filesChanged += [pscustomobject]@{
        Rel = $rel; Removable = $removable; DroppedComments = $droppedComments; DroppedBlanks = $droppedBlanks
        BlankNos = $blankNos; NewText = $newText; WriteEnc = $writeEnc; Path = $path; LineArr = $lineArr
    }
    $totalRemovedComments += $removable.Count
    $totalDroppedLines    += ($droppedComments + $droppedBlanks)
    $totalBlankLines      += $droppedBlanks
}

# --- Relatorio / aplicacao -----------------------------------------------------
Write-Host ""
Write-Host "=== Remove-AddedComments ===" -ForegroundColor Cyan
Write-Host ("Repositorio : {0}" -f $root)
$modo = if ($Apply) { "APLICAR" } else { "PREVIEW (nada gravado)" }
Write-Host ("Modo        : {0}" -f $modo)
Write-Host ""

if ($filesChanged.Count -eq 0) {
    Write-Host "Nenhum comentario nem linha em branco adicionada para remover." -ForegroundColor Green
    exit 0
}

foreach ($f in $filesChanged) {
    Write-Host ("{0}" -f $f.Rel) -ForegroundColor Cyan
    foreach ($s in ($f.Removable | Sort-Object SL, SC)) {
        $snippet = $f.LineArr[$s.SL].Substring([Math]::Min($s.SC, $f.LineArr[$s.SL].Length)).Trim()
        if ($snippet.Length -gt 80) { $snippet = $snippet.Substring(0, 77) + '...' }
        $loc = if ($s.SL -eq $s.EL) { "L$($s.SL + 1)" } else { "L$($s.SL + 1)-$($s.EL + 1)" }
        Write-Host ("  [{0}] {1}: {2}" -f $s.Kind, $loc, $snippet)
    }
    if ($f.DroppedBlanks -gt 0) {
        Write-Host ("  [branco] linhas em branco adicionadas removidas: {0}  (L: {1})" -f $f.DroppedBlanks, ($f.BlankNos -join ', '))
    }
    Write-Host ("  -> {0} comentario(s) | apagadas: {1} de comentario + {2} em branco = {3} linha(s)" -f $f.Removable.Count, $f.DroppedComments, $f.DroppedBlanks, ($f.DroppedComments + $f.DroppedBlanks)) -ForegroundColor DarkGray

    if ($Apply) {
        [System.IO.File]::WriteAllText($f.Path, $f.NewText, $f.WriteEnc)
    }
}

Write-Host ""
Write-Host ("TOTAL: {0} comentario(s) em {1} arquivo(s); {2} linha(s) apagada(s) (das quais {3} em branco adicionadas)." -f $totalRemovedComments, $filesChanged.Count, $totalDroppedLines, $totalBlankLines) -ForegroundColor Green
if ($Apply) {
    Write-Host "Aplicado. Revise com 'git diff' antes de commitar." -ForegroundColor Green
} else {
    Write-Host "Isto foi um PREVIEW. Rode de novo com -Apply para aplicar." -ForegroundColor Yellow
}
exit 0
