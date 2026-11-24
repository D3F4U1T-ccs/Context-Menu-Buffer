@echo off
rem ============================================================================
rem  FOLDER TOOL - комбайн для папок через ПКМ (PowerShell + ffmpeg)
rem  Запуск: FolderTool.bat "путь\к\папке"
rem  Сохранять в UTF-8 без BOM. Весь код находится ниже, после метки PSCODE.
rem  Для конвертации и сжатия нужны ffmpeg и ffprobe в PATH.
rem ============================================================================
chcp 65001 >nul
title Folder Tool

setlocal DisableDelayedExpansion
if "%~1"=="" goto NOARG
if not exist "%~1\" goto NOFOLDER
set "FT_SELF=%~f0"
set "FT_DIR=%~f1"
where powershell >nul 2>&1 || goto NOPS
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:FT_SELF,[Text.Encoding]::UTF8); Invoke-Expression $t.Substring($t.LastIndexOf('#'+'PSCODE'))"
exit /b %errorlevel%

:NOARG
echo(
echo   Не передана папка. Запускай через ПКМ по папке
echo   или перетащи папку на этот .bat
echo(
pause
exit /b 1

:NOFOLDER
echo(
echo   Папка не найдена.
echo(
pause
exit /b 1

:NOPS
echo(
echo   Не найден PowerShell. В Windows 10 и 11 он встроен.
echo(
pause
exit /b 1

#PSCODE
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

$global:Root = [string]$env:FT_DIR
if ($global:Root.Length -gt 3) { $global:Root = $global:Root.TrimEnd('\') }
$global:Recurse = $false
$global:Spec = $null
$global:Stats = $null
$global:StatsDirty = $true
$global:RenFail = 0

$global:VideoExt = @('mp4','mkv','avi','mov','webm','m4v','wmv','flv','ts','m2ts','mts','mpg','mpeg','3gp')
$global:AudioExt = @('mp3','wav','flac','aac','m4a','ogg','opus','wma','aif','aiff','mka')
$global:ImageExt = @('jpg','jpeg','png','gif','bmp','webp','tif','tiff','heic','svg','ico')
$global:DocExt   = @('pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','odt','ods','csv','md')
$global:ArcExt   = @('zip','rar','7z','tar','gz','bz2','xz','iso')

# форматы для конвертации: Key - номер в меню
$global:ConvTargets = @(
    @{ Key = '1';  Ext = 'mp4';  Video = $true;  Opts = '-map 0:v:0 -map 0:a? -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart' },
    @{ Key = '2';  Ext = 'mkv';  Video = $true;  Opts = '-map 0:v:0 -map 0:a? -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k' },
    @{ Key = '3';  Ext = 'avi';  Video = $true;  Opts = '-map 0:v:0 -map 0:a? -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a libmp3lame -q:a 2' },
    @{ Key = '4';  Ext = 'mov';  Video = $true;  Opts = '-map 0:v:0 -map 0:a? -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart' },
    @{ Key = '5';  Ext = 'webm'; Video = $true;  Opts = '-map 0:v:0 -map 0:a? -c:v libvpx-vp9 -crf 28 -b:v 0 -row-mt 1 -deadline good -cpu-used 4 -c:a libopus -b:a 160k' },
    @{ Key = '6';  Ext = 'mp3';  Video = $false; Opts = '-vn -c:a libmp3lame -q:a 2' },
    @{ Key = '7';  Ext = 'wav';  Video = $false; Opts = '-vn -c:a pcm_s16le' },
    @{ Key = '8';  Ext = 'flac'; Video = $false; Opts = '-vn -c:a flac -compression_level 8' },
    @{ Key = '9';  Ext = 'm4a';  Video = $false; Opts = '-vn -c:a aac -b:a 256k' },
    @{ Key = '10'; Ext = 'ogg';  Video = $false; Opts = '-vn -c:a libvorbis -q:a 6' },
    @{ Key = '11'; Ext = 'opus'; Video = $false; Opts = '-vn -c:a libopus -b:a 160k' }
)

# ============================================================================
#  Мелкие помощники
# ============================================================================
function Ask([string]$prompt) {
    Write-Host -NoNewline $prompt
    $s = $Host.UI.ReadLine()
    if ($null -eq $s) { return '' }
    return $s
}

function AskT([string]$prompt) { return (Ask $prompt).Trim() }

function Is-Back([string]$s)     { return (@('0', 'b', 'и') -contains $s.Trim().ToLowerInvariant()) }
function Is-BackText([string]$s) { return (@('b', 'и') -contains $s.Trim().ToLowerInvariant()) }

function Pause-Enter([string]$text) {
    if (-not $text) { $text = '  Нажми Enter, чтобы вернуться...' }
    Write-Host ''
    [void](Ask $text)
}

function Say-Msg([string]$text) {
    Write-Host ''
    Write-Host ('  ' + $text)
    Pause-Enter ''
}

function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
    $a = $n % 100
    $b = $n % 10
    if ($a -ge 11 -and $a -le 14) { return $many }
    if ($b -eq 1) { return $one }
    if ($b -ge 2 -and $b -le 4) { return $few }
    return $many
}

function Fmt-Time([double]$sec) {
    if ([double]::IsNaN($sec) -or [double]::IsInfinity($sec) -or $sec -lt 0) { return '--:--:--' }
    $r = [long][math]::Round($sec)
    return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($r / 3600), [math]::Floor(($r % 3600) / 60), ($r % 60))
}

function Fmt-Size([long]$b) {
    if ($b -ge 1GB)  { return ('{0:N1} ГБ' -f ($b / 1GB)) }
    if ($b -ge 10MB) { return ('{0:N0} МБ' -f ($b / 1MB)) }
    if ($b -ge 1MB)  { return ('{0:N1} МБ' -f ($b / 1MB)) }
    return ('{0:N0} КБ' -f ($b / 1KB))
}

function Q([string]$s) { return '"' + $s + '"' }

# ключ для "человеческой" сортировки: file2 раньше file10
function Nat-Key([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($part in [regex]::Split($s.ToLowerInvariant(), '(\d+)')) {
        if ($part -match '^\d+$') { [void]$sb.Append($part.PadLeft(12, '0')) } else { [void]$sb.Append($part) }
    }
    return $sb.ToString()
}

# убирает из названия пометки копий: (2), - Copy, - копия, copy of
function Norm-Name([string]$base) {
    $n = $base.Trim()
    $n = [regex]::Replace($n, '\s*-\s*(copy|копия)(\s*\(\d+\))?$', '', 'IgnoreCase')
    $n = [regex]::Replace($n, '\s*\(\d+\)$', '')
    $n = [regex]::Replace($n, '^(copy of|копия)\s+', '', 'IgnoreCase')
    $n = [regex]::Replace($n, '[\s_]+copy(\s*\d+)?$', '', 'IgnoreCase')
    return $n.Trim().ToLowerInvariant()
}

function Unique-Path([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $p }
    $dir  = [IO.Path]::GetDirectoryName($p)
    $name = [IO.Path]::GetFileNameWithoutExtension($p)
    $ext  = [IO.Path]::GetExtension($p)
    $n = 2
    while ($true) {
        $c = Join-Path $dir ($name + '_' + $n + $ext)
        if (-not (Test-Path -LiteralPath $c)) { return $c }
        $n++
    }
}

function Test-Cancel {
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Escape') { return $true }
            if ($k.Key -eq 'C' -and (($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0)) { return $true }
        }
    } catch { }
    return $false
}

function Test-Tools {
    $a = Get-Command ffmpeg -ErrorAction SilentlyContinue
    $b = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($a -and $b) { return $true }
    Say-Msg 'Не найден ffmpeg или ffprobe. Скачай ffmpeg и добавь папку bin в переменную PATH.'
    return $false
}

function Invoke-Capture([string]$exe, [string]$argLine) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return $out
}

# длительность, наличие звука и видео, размер кадра
function Probe([string]$path) {
    $r = @{ Dur = 0.0; HasAudio = $false; HasVideo = $false; W = 0; H = 0 }
    try {
        $o = Invoke-Capture 'ffprobe' ('-v error -show_entries format=duration:stream=codec_type,width,height -of json ' + (Q $path))
        $j = $o | ConvertFrom-Json
        if ($j.format -and $j.format.duration) { $r.Dur = [double]::Parse([string]$j.format.duration, $inv) }
        foreach ($s in @($j.streams)) {
            if ($s.codec_type -eq 'audio') { $r.HasAudio = $true }
            if ($s.codec_type -eq 'video' -and -not $r.HasVideo) {
                $r.HasVideo = $true
                $r.W = [int]$s.width
                $r.H = [int]$s.height
            }
        }
    } catch { }
    return $r
}

# ============================================================================
#  Чтение папки и шапка
# ============================================================================
function Get-Entries([bool]$recurse) {
    $res = New-Object System.Collections.ArrayList
    $raw = @()
    try {
        if ($recurse) { $raw = @(Get-ChildItem -LiteralPath $global:Root -Recurse -ErrorAction SilentlyContinue) }
        else          { $raw = @(Get-ChildItem -LiteralPath $global:Root -ErrorAction SilentlyContinue) }
    } catch { $raw = @() }
    $skip1 = $global:Root.TrimEnd('\') + '\output\'
    $skip2 = $global:Root.TrimEnd('\') + '\Duplicates\'
    foreach ($e in $raw) {
        $full = $e.FullName
        if ($full.StartsWith($skip1, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($full.StartsWith($skip2, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $isDir = [bool]$e.PSIsContainer
        $ext = ''
        $base = $e.Name
        $dir = ''
        $size = [long]0
        if ($isDir) {
            $dir = $e.Parent.FullName
        } else {
            $dir = $e.DirectoryName
            $size = [long]$e.Length
            $ext = $e.Extension
            if ($ext.Length -gt 0) { $base = $e.Name.Substring(0, $e.Name.Length - $ext.Length) }
        }
        $obj = New-Object PSObject -Property @{
            Path = $full; Dir = $dir; Name = $e.Name; Base = $base; Ext = $ext
            IsDir = $isDir; Size = $size; Time = $e.LastWriteTime
            Include = $true; New = ''; Res = ''
        }
        [void]$res.Add($obj)
    }
    return $res.ToArray()
}

function Get-Items($scope) {
    $all = @(Get-Entries $global:Recurse)
    $sel = New-Object System.Collections.ArrayList
    foreach ($e in $all) {
        if ($e.IsDir) {
            if ($scope.Target -eq 'files') { continue }
        } else {
            if ($scope.Target -eq 'dirs') { continue }
            if ($null -ne $scope.Exts) {
                $x = $e.Ext.TrimStart('.').ToLowerInvariant()
                if (@($scope.Exts) -notcontains $x) { continue }
            }
        }
        [void]$sel.Add($e)
    }
    return @($sel | Sort-Object @{ Expression = { $_.Dir.ToLowerInvariant() } }, @{ Expression = { Nat-Key $_.Name } })
}

function Get-Stats {
    if ($null -ne $global:Stats -and -not $global:StatsDirty) { return $global:Stats }
    $all = @(Get-Entries $global:Recurse)
    $cnt = @{ v = 0; a = 0; i = 0; d = 0; z = 0; l = 0; o = 0; dir = 0 }
    $extCount = @{}
    $size = [long]0
    foreach ($e in $all) {
        if ($e.IsDir) { $cnt['dir']++; continue }
        $size += [long]$e.Size
        $x = $e.Ext.TrimStart('.').ToLowerInvariant()
        if ($x -eq 'lnk') { $cnt['l']++ }
        elseif ($global:VideoExt -contains $x) { $cnt['v']++ }
        elseif ($global:AudioExt -contains $x) { $cnt['a']++ }
        elseif ($global:ImageExt -contains $x) { $cnt['i']++ }
        elseif ($global:DocExt -contains $x)   { $cnt['d']++ }
        elseif ($global:ArcExt -contains $x)   { $cnt['z']++ }
        else { $cnt['o']++ }
        $k = $x
        if ($k -eq '') { $k = '(без расширения)' }
        if ($extCount.ContainsKey($k)) { $extCount[$k]++ } else { $extCount[$k] = 1 }
    }
    $parts = @()
    if ($cnt['v'] -gt 0) { $parts += ('{0} видео' -f $cnt['v']) }
    if ($cnt['a'] -gt 0) { $parts += ('{0} аудио' -f $cnt['a']) }
    if ($cnt['i'] -gt 0) { $parts += ('{0} {1}' -f $cnt['i'], (Plural $cnt['i'] 'изображение' 'изображения' 'изображений')) }
    if ($cnt['d'] -gt 0) { $parts += ('{0} {1}' -f $cnt['d'], (Plural $cnt['d'] 'документ' 'документа' 'документов')) }
    if ($cnt['z'] -gt 0) { $parts += ('{0} {1}' -f $cnt['z'], (Plural $cnt['z'] 'архив' 'архива' 'архивов')) }
    if ($cnt['l'] -gt 0) { $parts += ('{0} {1}' -f $cnt['l'], (Plural $cnt['l'] 'ярлык' 'ярлыка' 'ярлыков')) }
    if ($cnt['o'] -gt 0) { $parts += ('{0} {1}' -f $cnt['o'], (Plural $cnt['o'] 'другой файл' 'других файла' 'других файлов')) }
    if ($cnt['dir'] -gt 0) { $parts += ('{0} {1}' -f $cnt['dir'], (Plural $cnt['dir'] 'папка' 'папки' 'папок')) }
    $catText = 'пусто'
    if ($parts.Count -gt 0) { $catText = ($parts -join ',  ') }

    $top = @($extCount.GetEnumerator() | Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } | Select-Object -First 8)
    $et = @()
    foreach ($t in $top) { $et += ('{0} {1}' -f $t.Value, $t.Key) }
    $extText = '-'
    if ($et.Count -gt 0) { $extText = ($et -join ',  ') }
    if ($extCount.Count -gt 8) { $extText += '  ...' }

    $nFiles = $all.Count - $cnt['dir']
    $global:Stats = @{ Cats = $catText; Exts = $extText; Size = (Fmt-Size $size); Files = $nFiles }
    $global:StatsDirty = $false
    return $global:Stats
}

function Draw-Header {
    Clear-Host
    $leaf = [IO.Path]::GetFileName($global:Root.TrimEnd('\'))
    if ($leaf -eq '') { $leaf = $global:Root }
    $st = Get-Stats
    $sub = 'нет'
    if ($global:Recurse) { $sub = 'да' }
    Write-Host ('=' * 60)
    Write-Host '  FOLDER TOOL'
    Write-Host ('=' * 60)
    Write-Host ('  Папка:     ' + $leaf)
    Write-Host ('  Путь:      ' + $global:Root)
    Write-Host ('  Внутри:    ' + $st.Cats)
    Write-Host ('  Форматы:   ' + $st.Exts)
    Write-Host ('  Размер:    ' + $st.Size + '      Файлов: ' + $st.Files + '      Подпапки: ' + $sub)
    Write-Host ('-' * 60)
    Write-Host ''
}

# ============================================================================
#  Списки, предпросмотр, исключение файлов
# ============================================================================
function Parse-Nums([string]$s, [int]$max) {
    $out = New-Object System.Collections.ArrayList
    foreach ($tok in ($s -split '[,;\s]+')) {
        if ($tok -eq '') { continue }
        if ($tok.Length -gt 9) { continue }
        if ($tok -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]
            $b = [int]$Matches[2]
            if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
            for ($k = $a; $k -le $b; $k++) {
                if ($k -ge 1 -and $k -le $max -and -not $out.Contains($k)) { [void]$out.Add($k) }
            }
        } elseif ($tok -match '^\d+$') {
            $k = [int]$tok
            if ($k -ge 1 -and $k -le $max -and -not $out.Contains($k)) { [void]$out.Add($k) }
        }
    }
    return $out.ToArray()
}

function Show-Paged([string[]]$lines) {
    $page = [Math]::Max(10, [Console]::WindowHeight - 17)
    $i = 0
    while ($i -lt $lines.Count) {
        $end = [Math]::Min($i + $page, $lines.Count)
        for ($j = $i; $j -lt $end; $j++) { Write-Host $lines[$j] }
        $i = $end
        if ($i -lt $lines.Count) {
            $c = Ask ('  --- показано {0} из {1}.  Enter - дальше, q - пропустить ---' -f $i, $lines.Count)
            if (@('q', 'й') -contains $c.Trim().ToLowerInvariant()) { break }
        }
    }
}

function Toggle-Items($items) {
    $s = Ask '  Номера, которые не трогать, например 5, 19, 44 или 10-15. Повторный ввод возвращает файл. b - назад: '
    if (Is-BackText $s) { return }
    $nums = @(Parse-Nums $s $items.Count)
    foreach ($n in $nums) { $items[$n - 1].Include = -not $items[$n - 1].Include }
}

# имена по шаблону: [number], [number:3], [name], [prefix]текст
function Expand-Tpl([string]$tpl, [string]$orig, [int]$num) {
    $s = $tpl
    while ($true) {
        $m = [regex]::Match($s, '\[number(?::(\d+))?\]', 'IgnoreCase')
        if (-not $m.Success) { break }
        $w = 0
        if ($m.Groups[1].Success -and $m.Groups[1].Value.Length -le 2) { $w = [int]$m.Groups[1].Value }
        $txt = ([string]$num).PadLeft($w, '0')
        $s = $s.Substring(0, $m.Index) + $txt + $s.Substring($m.Index + $m.Length)
    }
    $s = [regex]::Replace($s, '\[name\]', $orig.Replace('$', '$$'), 'IgnoreCase')
    return $s
}

# считает новые имена для всех, кого не исключили
function Build-Names($items) {
    $spec = $global:Spec
    foreach ($it in $items) { $it.New = $it.Name }
    if ($null -eq $spec) { return }
    if ($spec.Type -eq 'pattern') {
        $counters = @{}
        foreach ($it in $items) {
            if (-not $it.Include) { continue }
            $key = $it.Dir.ToLowerInvariant() + '|' + [string]$it.IsDir
            if (-not $counters.ContainsKey($key)) { $counters[$key] = [int]$spec.Start }
            $n = $counters[$key]
            $counters[$key] = $n + 1
            $nb = Expand-Tpl $spec.Tpl $it.Base $n
            $it.New = $nb + $it.Ext
        }
    } elseif ($spec.Type -eq 'replace') {
        foreach ($it in $items) {
            if (-not $it.Include) { continue }
            $nb = [regex]::Replace($it.Base, [regex]::Escape($spec.Find), $spec.With.Replace('$', '$$'), 'IgnoreCase')
            $it.New = $nb + $it.Ext
        }
    }
}

# показывает список с номерами; true = продолжить, false = отмена
function Review-Items($items, [bool]$showNew, [string]$title) {
    while ($true) {
        if ($showNew) { Build-Names $items }
        Draw-Header
        Write-Host ('  ' + $title)
        Write-Host ''
        $lines = New-Object System.Collections.ArrayList
        $w = ([string]$items.Count).Length
        $inc = 0
        $chg = 0
        for ($i = 0; $i -lt $items.Count; $i++) {
            $it = $items[$i]
            $num = ([string]($i + 1)).PadLeft($w)
            if (-not $it.Include) {
                [void]$lines.Add(('  {0}  [не трогать]  {1}' -f $num, $it.Name))
            } elseif ($showNew) {
                $inc++
                if ($it.New -ceq $it.Name) {
                    [void]$lines.Add(('  {0}  {1}   (без изменений)' -f $num, $it.Name))
                } else {
                    $chg++
                    [void]$lines.Add(('  {0}  {1}  ->  {2}' -f $num, $it.Name, $it.New))
                }
            } else {
                $inc++
                $chg++
                [void]$lines.Add(('  {0}  {1}' -f $num, $it.Name))
            }
        }
        Show-Paged $lines.ToArray()
        Write-Host ''
        Write-Host ('  Будет затронуто: {0}      Не трогаю: {1}' -f $chg, ($items.Count - $inc))
        Write-Host ''
        Write-Host '  Enter - продолжить      x - исключить из списка      0 - отмена'
        $c = (AskT '  Выбор: ').ToLowerInvariant()
        if ($c -eq '') { return $true }
        if ($c -eq '0' -or $c -eq 'b' -or $c -eq 'и') { return $false }
        if ($c -eq 'x' -or $c -eq 'ч') { Toggle-Items $items }
    }
}

# ============================================================================
#  Вопросы: что менять и как назвать
# ============================================================================
function Ask-ExtList {
    while ($true) {
        $s = Ask '  Расширения через запятую, например mp4, mkv, jpg   (b - назад): '
        if (Is-BackText $s) { return }
        $list = @()
        foreach ($t in ($s -split '[,;\s]+')) {
            $x = $t.Trim().TrimStart('.').ToLowerInvariant()
            if ($x -ne '') { $list += $x }
        }
        if ($list.Count -gt 0) { return $list }
        Write-Host '  Не понял, впиши хотя бы одно расширение.'
    }
}

function Ask-Exts {
    while ($true) {
        Draw-Header
        Write-Host '  Какие файлы?'
        Write-Host ''
        Write-Host '  1  Все файлы'
        Write-Host '  2  Только указанные расширения'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return @{ Back = $true; Exts = $null } }
        if ($c -eq '1') { return @{ Back = $false; Exts = $null } }
        if ($c -eq '2') {
            $ex = @(Ask-ExtList)
            if ($ex.Count -gt 0) { return @{ Back = $false; Exts = $ex } }
        }
    }
}

function Ask-Scope([string]$title) {
    while ($true) {
        Draw-Header
        Write-Host ('  ' + $title)
        Write-Host ''
        Write-Host '  1  Только файлы'
        Write-Host '  2  Только папки'
        Write-Host '  3  Файлы и папки'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return $null }
        $target = ''
        if ($c -eq '1') { $target = 'files' }
        elseif ($c -eq '2') { $target = 'dirs' }
        elseif ($c -eq '3') { $target = 'both' }
        else { continue }
        if ($target -eq 'dirs') { return @{ Target = $target; Exts = $null } }
        $r = Ask-Exts
        if ($r.Back) { continue }
        return @{ Target = $target; Exts = $r.Exts }
    }
}

function Ask-Pattern {
    while ($true) {
        Draw-Header
        Write-Host '  НОВОЕ НАЗВАНИЕ'
        Write-Host ''
        Write-Host '  Как оно должно выглядеть? Примеры:'
        Write-Host '    [prefix]привет      добавить  привет  в начало названия'
        Write-Host '    [number]            1, 2, 3 ...'
        Write-Host '    привет[number]      привет1, привет2 ...'
        Write-Host '    привет [number]     привет 1, привет 2 ...'
        Write-Host '    [number:3]          001, 002, 003 ...  (цифра - сколько знаков)'
        Write-Host '    [name]_готово       старое название + _готово'
        Write-Host '  Расширение у файлов сохраняется само.'
        Write-Host ''
        $raw = Ask '  Шаблон, b - назад: '
        if (Is-BackText $raw) { return $null }
        if ($raw -eq '') { continue }
        $tpl = $raw
        if ($tpl.StartsWith('[prefix]', [StringComparison]::OrdinalIgnoreCase)) { $tpl = $tpl.Substring(8) + '[name]' }
        $hasNum = [regex]::IsMatch($tpl, '\[number(:\d+)?\]', 'IgnoreCase')
        $hasName = ($tpl.IndexOf('[name]', [StringComparison]::OrdinalIgnoreCase) -ge 0)
        if (-not $hasNum -and -not $hasName) {
            Say-Msg 'В шаблоне нет [number] или [prefix]. У всех файлов получилось бы одно и то же имя.'
            continue
        }
        $sample = Expand-Tpl $tpl 'x' 1
        if ($sample.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Say-Msg 'В названии нельзя использовать символы: \ / : * ? " < > |'
            continue
        }
        $start = 1
        if ($hasNum) {
            $s = (Ask '  С какого номера начать, Enter = 1: ').Trim()
            if ($s -match '^\d{1,6}$') { $start = [int]$s }
        }
        return @{ Tpl = $tpl; Start = $start }
    }
}

# ============================================================================
#  Переименование: применение, откат
# ============================================================================
function Apply-Group($pairs) {
    $stage = New-Object System.Collections.ArrayList
    $done = New-Object System.Collections.ArrayList
    foreach ($p in $pairs) {
        $tmp = Join-Path $p.Dir ('~mt_' + [guid]::NewGuid().ToString('N'))
        try {
            if ($p.IsDir) { [IO.Directory]::Move($p.Path, $tmp) } else { [IO.File]::Move($p.Path, $tmp) }
            [void]$stage.Add(@{ Tmp = $tmp; Orig = $p.Path; Final = (Join-Path $p.Dir $p.NewName); IsDir = $p.IsDir })
        } catch {
            $global:RenFail++
        }
    }
    foreach ($s in $stage) {
        try {
            if ($s.IsDir) { [IO.Directory]::Move($s.Tmp, $s.Final) } else { [IO.File]::Move($s.Tmp, $s.Final) }
            [void]$done.Add(@{ From = $s.Orig; To = $s.Final; IsDir = $s.IsDir })
        } catch {
            try {
                if ($s.IsDir) { [IO.Directory]::Move($s.Tmp, $s.Orig) } else { [IO.File]::Move($s.Tmp, $s.Orig) }
            } catch { }
            $global:RenFail++
        }
    }
    return $done.ToArray()
}

function Do-Rollback($allGroups) {
    $n = 0
    for ($gi = $allGroups.Count - 1; $gi -ge 0; $gi--) {
        $g = $allGroups[$gi]
        $pairs = New-Object System.Collections.ArrayList
        foreach ($d in $g) {
            $dir = [IO.Path]::GetDirectoryName($d.To)
            [void]$pairs.Add((New-Object PSObject -Property @{ Path = $d.To; Dir = $dir; NewName = [IO.Path]::GetFileName($d.From); IsDir = $d.IsDir }))
        }
        $back = @(Apply-Group $pairs)
        $n += $back.Count
    }
    Say-Msg ('Отменено. Названий возвращено: ' + $n)
}

function Run-Rename($items) {
    $todo = @($items | Where-Object { $_.Include -and -not ($_.New -ceq $_.Name) })
    if ($todo.Count -eq 0) {
        Say-Msg 'Нечего менять: все названия остались прежними.'
        return
    }
    # проверки до начала, чтобы ничего не сломать на полпути
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $errs = New-Object System.Collections.ArrayList
    $seen = @{}
    $oldSet = @{}
    foreach ($t in $todo) { $oldSet[$t.Path.ToLowerInvariant()] = $true }
    foreach ($t in $todo) {
        if ($t.New.IndexOfAny($invalid) -ge 0) { [void]$errs.Add('недопустимые символы: ' + $t.New); continue }
        if ($t.New.Length -le $t.Ext.Length) { [void]$errs.Add('пустое имя для: ' + $t.Name); continue }
        if ($t.IsDir -and ($t.New.EndsWith(' ') -or $t.New.EndsWith('.'))) { [void]$errs.Add('имя папки не может кончаться пробелом или точкой: ' + $t.New); continue }
        $np = (Join-Path $t.Dir $t.New).ToLowerInvariant()
        if ($seen.ContainsKey($np)) { [void]$errs.Add('получится два одинаковых имени: ' + $t.New) } else { $seen[$np] = $true }
        if ((Test-Path -LiteralPath (Join-Path $t.Dir $t.New)) -and -not $oldSet.ContainsKey($np)) {
            [void]$errs.Add('такое имя уже занято: ' + $t.New)
        }
    }
    if ($errs.Count -gt 0) {
        Draw-Header
        Write-Host '  ПЕРЕИМЕНОВАНИЕ ОСТАНОВЛЕНО, ничего не изменено. Конфликты:'
        Write-Host ''
        $shown = 0
        foreach ($e in $errs) {
            if ($shown -ge 12) { break }
            Write-Host ('   - ' + $e)
            $shown++
        }
        if ($errs.Count -gt 12) { Write-Host ('   ... и еще ' + ($errs.Count - 12)) }
        Pause-Enter ''
        return
    }
    # сначала файлы, потом папки от самых глубоких к верхним
    $files = @($todo | Where-Object { -not $_.IsDir })
    $dirs = @($todo | Where-Object { $_.IsDir })
    $groups = New-Object System.Collections.ArrayList
    if ($files.Count -gt 0) { [void]$groups.Add($files) }
    $depths = @($dirs | ForEach-Object { $_.Path.Split('\').Count } | Sort-Object -Unique -Descending)
    foreach ($d in $depths) {
        $g = @($dirs | Where-Object { $_.Path.Split('\').Count -eq $d })
        [void]$groups.Add($g)
    }
    $allGroups = New-Object System.Collections.ArrayList
    $okCount = 0
    $global:RenFail = 0
    foreach ($g in $groups) {
        $pairs = New-Object System.Collections.ArrayList
        foreach ($it in $g) {
            [void]$pairs.Add((New-Object PSObject -Property @{ Path = $it.Path; Dir = $it.Dir; NewName = $it.New; IsDir = $it.IsDir }))
        }
        $done = @(Apply-Group $pairs)
        if ($done.Count -gt 0) {
            [void]$allGroups.Add($done)
            $okCount += $done.Count
        }
    }
    $global:StatsDirty = $true
    Draw-Header
    Write-Host ('  ГОТОВО. Переименовано: ' + $okCount)
    if ($global:RenFail -gt 0) { Write-Host ('  Не удалось: ' + $global:RenFail) }
    Write-Host ''
    Write-Host '  Enter - в меню      u - отменить это переименование'
    $c = (AskT '  Выбор: ').ToLowerInvariant()
    if (($c -eq 'u' -or $c -eq 'г') -and $allGroups.Count -gt 0) { Do-Rollback $allGroups }
}

# ============================================================================
#  Меню: Имя (переименование и замена)
# ============================================================================
function Menu-Rename {
    $scope = Ask-Scope 'ПЕРЕИМЕНОВАНИЕ - что менять?'
    if ($null -eq $scope) { return }
    $items = @(Get-Items $scope)
    if ($items.Count -eq 0) { Say-Msg 'Подходящих файлов или папок нет.'; return }
    $pat = Ask-Pattern
    if ($null -eq $pat) { return }
    $global:Spec = @{ Type = 'pattern'; Tpl = $pat.Tpl; Start = $pat.Start }
    $ok = Review-Items $items $true 'ПРЕДПРОСМОТР - что получится'
    $global:Spec = $null
    if ($ok) {
        $global:Spec = @{ Type = 'pattern'; Tpl = $pat.Tpl; Start = $pat.Start }
        Build-Names $items
        $global:Spec = $null
        Run-Rename $items
    }
}

function Replace-Flow([string]$mode) {
    $scope = Ask-Scope 'ЗАМЕНА - где искать?'
    if ($null -eq $scope) { return }
    $all = @(Get-Items $scope)
    if ($all.Count -eq 0) { Say-Msg 'Подходящих файлов или папок нет.'; return }
    while ($true) {
        Draw-Header
        Write-Host '  ЗАМЕНА'
        Write-Host ''
        $find = Ask '  Что искать в названиях, b - назад: '
        if (Is-BackText $find) { return }
        if ($find -eq '') { continue }
        $hits = @($all | Where-Object { $_.Base.IndexOf($find, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($hits.Count -eq 0) { Say-Msg ('Ничего не найдено по запросу «' + $find + '».'); continue }
        foreach ($h in $hits) { $h.Include = $true }
        $global:Spec = $null
        $ok = Review-Items $hits $false ('НАЙДЕНО: ' + $hits.Count + '      запрос: «' + $find + '»')
        if (-not $ok) { continue }
        $spec = $null
        if ($mode -eq 'word') {
            $with = Ask '  На что заменить, пусто = просто убрать слово, b - назад: '
            if (Is-BackText $with) { continue }
            $spec = @{ Type = 'replace'; Find = $find; With = $with }
        } else {
            $pat = Ask-Pattern
            if ($null -eq $pat) { continue }
            $spec = @{ Type = 'pattern'; Tpl = $pat.Tpl; Start = $pat.Start }
        }
        $global:Spec = $spec
        $ok2 = Review-Items $hits $true 'ПРЕДПРОСМОТР - что получится'
        if ($ok2) {
            Build-Names $hits
            $global:Spec = $null
            Run-Rename $hits
            return
        }
        $global:Spec = $null
    }
}

function Menu-Replace {
    while ($true) {
        Draw-Header
        Write-Host '  ЗАМЕНА'
        Write-Host ''
        Write-Host '  1  Заменить слово в названиях       yummy -> Pizza'
        Write-Host '  2  Заменить название целиком        если в названии есть слово'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        if ($c -eq '1') { Replace-Flow 'word'; return }
        if ($c -eq '2') { Replace-Flow 'name'; return }
    }
}

function Menu-Name {
    while ($true) {
        Draw-Header
        Write-Host '  ИМЯ'
        Write-Host ''
        Write-Host '  1  Переименование'
        Write-Host '  2  Замена'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        if ($c -eq '1') { Menu-Rename; return }
        if ($c -eq '2') { Menu-Replace; return }
    }
}

# ============================================================================
#  ffmpeg: конвертация и сжатие
# ============================================================================
function Why([string]$e) {
    if ($e -match "Unknown encoder '([^']+)'")   { return 'в этой сборке ffmpeg нет кодека ' + $Matches[1] }
    if ($e -match 'does not contain any stream') { return 'в файле нет нужных дорожек' }
    if ($e -match 'Permission denied')           { return 'нет доступа на запись' }
    if ($e -match 'No space left')               { return 'на диске не хватает места' }
    if ($e -match 'Invalid data found|moov atom not found|Error opening input') { return 'не удалось прочитать файл, возможно он поврежден' }
    if ($e -match 'Invalid argument')            { return 'ffmpeg не принял параметры для этого файла' }
    return ''
}

function Get-VideoSet([string]$ext, [int]$crf, [bool]$fixExt) {
    $vext = 'mp4'
    foreach ($e in @('mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v')) { if ($ext -eq $e) { $vext = $e } }
    if ($fixExt) { $vext = $ext }
    if ($vext -eq 'webm') {
        $venc = '-c:v libvpx-vp9 -crf ' + $crf + ' -b:v 0 -row-mt 1 -deadline good -cpu-used 4'
        $vaenc = '-c:a libopus -b:a 160k'
    } else {
        $venc = '-c:v libx264 -crf ' + $crf + ' -preset medium -pix_fmt yuv420p'
        $vaenc = '-c:a aac -b:a 192k'
    }
    if ($vext -eq 'avi') { $vaenc = '-c:a libmp3lame -q:a 2' }
    $akeep = '-c:a copy'
    if ($vext -ne $ext) { $akeep = $vaenc }
    return @{ Ext = $vext; Venc = $venc; Vaenc = $vaenc; Akeep = $akeep }
}

function Get-AudioSet([string]$ext, [int]$abr, [bool]$lossyOnly) {
    $list = @('mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wav')
    if ($lossyOnly) { $list = @('mp3', 'm4a', 'aac', 'ogg', 'opus') }
    $aext = 'mp3'
    foreach ($e in $list) { if ($ext -eq $e) { $aext = $e } }
    $b = [string]$abr + 'k'
    $enc = ''
    if ($aext -eq 'mp3') {
        if ($abr -gt 0) { $enc = '-c:a libmp3lame -b:a ' + $b } else { $enc = '-c:a libmp3lame -q:a 2' }
    } elseif ($aext -eq 'm4a' -or $aext -eq 'aac') {
        if ($abr -gt 0) { $enc = '-c:a aac -b:a ' + $b } else { $enc = '-c:a aac -b:a 256k' }
    } elseif ($aext -eq 'ogg') {
        if ($abr -gt 0) { $enc = '-c:a libvorbis -b:a ' + $b } else { $enc = '-c:a libvorbis -q:a 6' }
    } elseif ($aext -eq 'opus') {
        if ($abr -gt 0) { $enc = '-c:a libopus -b:a ' + $b } else { $enc = '-c:a libopus -b:a 160k' }
    } elseif ($aext -eq 'flac') {
        $enc = '-c:a flac -compression_level 8'
    } else {
        $enc = '-c:a pcm_s16le'
    }
    return @{ Ext = $aext; Enc = $enc }
}

# рисует блок из 4 строк на одном и том же месте
function Draw-Progress($ui, [double]$cur) {
    $width = [Math]::Max(40, [Console]::WindowWidth - 2)
    $doneN = $ui.Ok + $ui.Fail
    $left = $ui.Count - $doneN
    $p = 0.0
    if ($ui.TotalDur -gt 0) { $p = ($ui.DoneDur + [Math]::Min([Math]::Max($cur, 0.0), $ui.CurW)) / $ui.TotalDur }
    if ($p -gt 1) { $p = 1.0 }
    if ($p -lt 0) { $p = 0.0 }
    $n = [int][Math]::Floor($p * 24)
    $bar = ('#' * $n) + ('-' * (24 - $n))
    $el = $ui.Sw.Elapsed.TotalSeconds
    $eta = 'считаю...'
    if ($p -ge 0.02 -and $el -ge 2) { $eta = Fmt-Time ($el * (1 - $p) / $p) }
    $name = [string]$ui.Name
    $maxn = $width - 4
    if ($name.Length -gt $maxn) { $name = $name.Substring(0, $maxn - 3) + '...' }
    $l1 = ('  Файл {0} из {1}      обработано: {2}      осталось: {3}      ошибок: {4}' -f $ui.Index, $ui.Count, $doneN, $left, $ui.Fail)
    $l2 = '  ' + $name
    $l3 = ('  [{0}] {1,3}%   осталось ~{2}' -f $bar, [int][Math]::Floor($p * 100), $eta)
    $l4 = '  Esc или Ctrl+C - отмена'
    try { [Console]::SetCursorPosition(0, $ui.Top) } catch { }
    Write-Host $l1.PadRight($width)
    Write-Host $l2.PadRight($width)
    Write-Host $l3.PadRight($width)
    Write-Host -NoNewline $l4.PadRight($width)
}

function Invoke-Ffmpeg([string]$argLine, $ui) {
    $res = @{ Code = 1; Err = ''; Cancelled = $false }
    $prog = Join-Path $env:TEMP ('foldertool_' + $PID + '.prg')
    if (Test-Path -LiteralPath $prog) { Remove-Item -LiteralPath $prog -Force -ErrorAction SilentlyContinue }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'ffmpeg'
    $psi.Arguments = '-hide_banner -loglevel error -nostdin -n -nostats -progress "' + $prog + '" ' + $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = $null
    $reader = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        $cur = 0.0
        while (-not $proc.HasExited) {
            if (Test-Cancel) { $res.Cancelled = $true; break }
            if ($null -eq $reader -and (Test-Path -LiteralPath $prog)) {
                $fs = New-Object System.IO.FileStream($prog, 'Open', 'Read', 'ReadWrite,Delete')
                $reader = New-Object System.IO.StreamReader($fs)
            }
            if ($null -ne $reader) {
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ($line.StartsWith('out_time=')) {
                        $tt = $line.Substring(9).Trim()
                        $parts = $tt.Split(':')
                        if ($parts.Count -eq 3) {
                            try { $cur = [double]::Parse($parts[0], $inv) * 3600 + [double]::Parse($parts[1], $inv) * 60 + [double]::Parse($parts[2], $inv) } catch { }
                        }
                    }
                }
            }
            Draw-Progress $ui $cur
            Start-Sleep -Milliseconds 400
        }
        if ($res.Cancelled) {
            try { $proc.Kill() } catch { }
            $proc.WaitForExit()
        } else {
            $proc.WaitForExit()
            $res.Code = $proc.ExitCode
            $res.Err = $errTask.Result
        }
    } catch {
        $res.Err = $_.Exception.Message
        $res.Code = 1
        try { if ($null -ne $proc -and -not $proc.HasExited) { $proc.Kill() } } catch { }
    } finally {
        if ($null -ne $reader) { try { $reader.Close() } catch { } }
        Remove-Item -LiteralPath $prog -Force -ErrorAction SilentlyContinue
    }
    return $res
}

function Select-Media([string]$title) {
    while ($true) {
        Draw-Header
        Write-Host ('  ' + $title + ' - какие файлы?')
        Write-Host ''
        Write-Host '  1  Все видео'
        Write-Host '  2  Все аудио'
        Write-Host '  3  Видео и аудио'
        Write-Host '  4  Только указанные расширения'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        $exts = $null
        if ($c -eq '1') { $exts = @($global:VideoExt) }
        elseif ($c -eq '2') { $exts = @($global:AudioExt) }
        elseif ($c -eq '3') { $exts = @($global:VideoExt) + @($global:AudioExt) }
        elseif ($c -eq '4') {
            $ex = @(Ask-ExtList)
            if ($ex.Count -eq 0) { continue }
            $exts = $ex
        } else { continue }
        $files = @(Get-Entries $global:Recurse | Where-Object { -not $_.IsDir } | Where-Object { $exts -contains $_.Ext.TrimStart('.').ToLowerInvariant() })
        if ($files.Count -eq 0) { Say-Msg 'Подходящих файлов в папке нет.'; continue }
        return $files
    }
}

# куда сохранять результат: replace, folder, suffix
function Ask-Output([string]$suffix) {
    while ($true) {
        Draw-Header
        Write-Host '  Заменить оригинальные файлы?'
        Write-Host ''
        Write-Host '  1  Да - результат встанет на место оригинала, оригинал будет удален'
        Write-Host '  2  Нет'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return $null }
        if ($c -eq '1') {
            Write-Host ''
            Write-Host '  ВНИМАНИЕ: каждый оригинал удаляется сразу после успешной обработки.'
            $a = (AskT '  Напиши  да  чтобы продолжить, иначе назад: ').ToLowerInvariant()
            if (@('да', 'д', 'y', 'yes') -contains $a) { return @{ Mode = 'replace' } }
            continue
        }
        if ($c -eq '2') {
            while ($true) {
                Draw-Header
                Write-Host '  Куда сохранить результат?'
                Write-Host ''
                Write-Host '  1  В папку output - она создастся сама'
                Write-Host ('  2  В ту же папку, добавив в конец названия  ' + $suffix)
                Write-Host ''
                Write-Host '  0  Назад'
                Write-Host ''
                $d = AskT '  Выбор: '
                if (Is-Back $d) { break }
                if ($d -eq '1') { return @{ Mode = 'folder' } }
                if ($d -eq '2') { return @{ Mode = 'suffix' } }
            }
        }
    }
}

# анализ файлов: длительность, звук, тип
function Build-Queue($files) {
    $q = New-Object System.Collections.ArrayList
    $n = $files.Count
    $i = 0
    $cancelled = $false
    [Console]::TreatControlCAsInput = $true
    try {
        Write-Host ''
        foreach ($f in $files) {
            $i++
            if (Test-Cancel) { $cancelled = $true; break }
            $txt = ('  Анализирую файлы: {0} из {1}      Esc - отмена' -f $i, $n)
            Write-Host -NoNewline ("`r" + $txt.PadRight(60))
            $ext = $f.Ext.TrimStart('.').ToLowerInvariant()
            $p = Probe $f.Path
            $kind = 'video'
            if ($global:AudioExt -contains $ext) { $kind = 'audio' }
            elseif ($global:VideoExt -contains $ext) { $kind = 'video' }
            elseif (-not $p.HasVideo -and $p.HasAudio) { $kind = 'audio' }
            elseif (-not $p.HasVideo -and -not $p.HasAudio) { $kind = 'none' }
            $o = New-Object PSObject -Property @{
                Path = $f.Path; Dir = $f.Dir; Name = $f.Name; Base = $f.Base; Ext = $ext; Size = $f.Size
                Kind = $kind; Dur = [double]$p.Dur; HasAudio = [bool]$p.HasAudio
                Args = ''; OutExt = ''; Skip = ''; W = 0.0
            }
            [void]$q.Add($o)
        }
    } finally {
        [Console]::TreatControlCAsInput = $false
    }
    return @{ Cancelled = $cancelled; Items = $q.ToArray() }
}

function Prep-Convert($items, $t) {
    foreach ($q in $items) {
        if ($q.Kind -eq 'none') { $q.Skip = 'не медиафайл'; continue }
        if ($q.Ext -eq $t.Ext) { $q.Skip = 'уже в формате ' + $t.Ext; continue }
        if ($q.Kind -eq 'audio' -and $t.Video) { $q.Skip = 'аудио нельзя в видеоформат'; continue }
        if ($q.Kind -eq 'video' -and -not $t.Video -and -not $q.HasAudio) { $q.Skip = 'в файле нет звука'; continue }
        $q.Args = $t.Opts
        $q.OutExt = $t.Ext
    }
}

function Prep-Compress($items, $spec) {
    foreach ($q in $items) {
        if ($q.Kind -eq 'none') { $q.Skip = 'не медиафайл'; continue }
        if ($q.Kind -eq 'video') {
            if ($spec.Lossless) {
                $q.OutExt = 'mkv'
                $q.Args = '-map 0:v:0 -map 0:a? -c:v libx264 -crf 0 -preset medium -c:a copy'
            } else {
                $vs = Get-VideoSet $q.Ext $spec.Crf $false
                $q.OutExt = $vs.Ext
                $q.Args = '-map 0:v:0 -map 0:a? ' + $vs.Venc + ' ' + $vs.Akeep
            }
        } else {
            if ($spec.Lossless) {
                $q.OutExt = 'flac'
                $q.Args = '-vn -c:a flac -compression_level 8'
            } else {
                $as = Get-AudioSet $q.Ext $spec.Abr $true
                $q.OutExt = $as.Ext
                $q.Args = '-vn ' + $as.Enc
            }
        }
    }
}

function Confirm-Queue($queue, [string]$mode, [string]$suffix) {
    Draw-Header
    $todo = @($queue | Where-Object { $_.Skip -eq '' })
    $skip = @($queue | Where-Object { $_.Skip -ne '' })
    Write-Host ('  К обработке: {0} {1}' -f $todo.Count, (Plural $todo.Count 'файл' 'файла' 'файлов'))
    if ($skip.Count -gt 0) {
        Write-Host ('  Будет пропущено: ' + $skip.Count)
        $reasons = @($skip | Group-Object Skip | Sort-Object Count -Descending)
        foreach ($r in $reasons) { Write-Host ('     {0} - {1}' -f $r.Count, $r.Name) }
    }
    $where = ''
    if ($mode -eq 'replace') { $where = 'ОРИГИНАЛЫ БУДУТ ЗАМЕНЕНЫ - после успешной обработки старый файл удаляется' }
    elseif ($mode -eq 'folder') { $where = 'результат пойдет в папку output' }
    else { $where = 'рядом с оригиналом, к названию добавится ' + $suffix }
    Write-Host ('  Куда: ' + $where)
    if ($todo.Count -eq 0) { Pause-Enter ''; return $false }
    Write-Host ''
    $c = AskT '  Enter - начать, 0 - отмена: '
    return (-not (Is-Back $c))
}

function Run-Queue($queue, [string]$mode, [string]$suffix, [string]$title) {
    $todo = @($queue | Where-Object { $_.Skip -eq '' })
    $skipped = @($queue | Where-Object { $_.Skip -ne '' })
    $known = @($todo | Where-Object { $_.Dur -gt 0 })
    $avg = 30.0
    if ($known.Count -gt 0) { $avg = [double](($known | Measure-Object -Property Dur -Average).Average) }
    $total = 0.0
    foreach ($q in $todo) {
        $w = [double]$q.Dur
        if ($w -le 0) { $w = $avg }
        $q.W = $w
        $total += $w
    }
    Draw-Header
    Write-Host ('  ' + $title)
    Write-Host ''
    for ($i = 0; $i -lt 6; $i++) { Write-Host '' }
    $top = [Console]::CursorTop - 6
    if ($top -lt 0) { $top = 0 }
    $ui = @{ Index = 0; Count = $todo.Count; Ok = 0; Fail = 0; DoneDur = 0.0; TotalDur = $total; CurW = 0.0; Sw = [System.Diagnostics.Stopwatch]::StartNew(); Top = $top; Name = '' }
    $fails = New-Object System.Collections.ArrayList
    $cancelled = $false
    $sumOld = [long]0
    $sumNew = [long]0
    $root = $global:Root
    [Console]::TreatControlCAsInput = $true
    try {
        foreach ($q in $todo) {
            $ui.Index = $ui.Index + 1
            $ui.Name = $q.Name
            $ui.CurW = $q.W
            Draw-Progress $ui 0.0
            $outName = $q.Base + '.' + $q.OutExt
            $final = ''
            $work = ''
            if ($mode -eq 'replace') {
                $work = Join-Path $q.Dir ('~mt_' + [guid]::NewGuid().ToString('N') + '.' + $q.OutExt)
            } elseif ($mode -eq 'folder') {
                $rel = ''
                if ($q.Dir.Length -gt $root.Length) { $rel = $q.Dir.Substring($root.Length).TrimStart('\') }
                $destDir = Join-Path $root 'output'
                if ($rel -ne '') { $destDir = Join-Path $destDir $rel }
                [void][IO.Directory]::CreateDirectory($destDir)
                $final = Unique-Path (Join-Path $destDir $outName)
                $work = $final
            } else {
                $final = Unique-Path (Join-Path $q.Dir ($q.Base + $suffix + '.' + $q.OutExt))
                $work = $final
            }
            $r = Invoke-Ffmpeg ('-i ' + (Q $q.Path) + ' ' + $q.Args + ' ' + (Q $work)) $ui
            if ($r.Cancelled) {
                $cancelled = $true
                if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue }
                break
            }
            $okfile = $false
            if ($r.Code -eq 0 -and (Test-Path -LiteralPath $work)) {
                if ((Get-Item -LiteralPath $work).Length -gt 0) { $okfile = $true }
            }
            $keepWork = $false
            if ($okfile -and $mode -eq 'replace') {
                $removed = $false
                try {
                    Remove-Item -LiteralPath $q.Path -Force
                    $removed = $true
                } catch {
                    $okfile = $false
                    $r.Err = 'не удалось удалить оригинал'
                }
                if ($removed) {
                    try {
                        $final = Unique-Path (Join-Path $q.Dir $outName)
                        [IO.File]::Move($work, $final)
                    } catch {
                        $okfile = $false
                        $keepWork = $true
                        $r.Err = 'оригинал удален, но результат остался под именем ' + [IO.Path]::GetFileName($work)
                    }
                }
            }
            if ($okfile) {
                $ui.Ok = $ui.Ok + 1
                $sumOld += [long]$q.Size
                $sumNew += [long](Get-Item -LiteralPath $final).Length
            } else {
                $ui.Fail = $ui.Fail + 1
                if (-not $keepWork -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue }
                $why = Why $r.Err
                if ($why -eq '' -and $r.Err -ne '') {
                    $lines = @($r.Err -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
                    if ($lines.Count -gt 0) { $why = $lines[$lines.Count - 1].Trim() }
                }
                if ($why -eq '') { $why = 'неизвестная ошибка' }
                [void]$fails.Add(@{ Name = $q.Name; Why = $why })
            }
            $ui.DoneDur = $ui.DoneDur + $q.W
            Draw-Progress $ui 0.0
        }
    } finally {
        [Console]::TreatControlCAsInput = $false
    }
    $global:StatsDirty = $true
    Draw-Header
    $elapsed = Fmt-Time $ui.Sw.Elapsed.TotalSeconds
    if ($cancelled) { Write-Host ('  ОТМЕНЕНО через ' + $elapsed + '. Незаконченный файл удален.') }
    else { Write-Host ('  ГОТОВО за ' + $elapsed) }
    Write-Host ''
    Write-Host ('  Успешно: {0}      Пропущено: {1}      Ошибок: {2}' -f $ui.Ok, $skipped.Count, $ui.Fail)
    if ($ui.Ok -gt 0) { Write-Host ('  Размер: {0} -> {1}' -f (Fmt-Size $sumOld), (Fmt-Size $sumNew)) }
    if ($fails.Count -gt 0) {
        Write-Host ''
        Write-Host '  Не получилось:'
        $shown = 0
        foreach ($f in $fails) {
            if ($shown -ge 10) { break }
            Write-Host ('   - ' + $f.Name + ' : ' + $f.Why)
            $shown++
        }
        if ($fails.Count -gt 10) { Write-Host ('   ... и еще ' + ($fails.Count - 10)) }
    }
    if ($skipped.Count -gt 0) {
        Write-Host ''
        Write-Host '  Пропущено:'
        $shown = 0
        foreach ($s in $skipped) {
            if ($shown -ge 8) { break }
            Write-Host ('   - ' + $s.Name + ' : ' + $s.Skip)
            $shown++
        }
        if ($skipped.Count -gt 8) { Write-Host ('   ... и еще ' + ($skipped.Count - 8)) }
    }
    Pause-Enter ''
}

function Ask-Int([string]$prompt, [int]$min, [int]$max) {
    while ($true) {
        $s = (Ask $prompt).Trim()
        if (Is-BackText $s) { return $null }
        if ($s -match '^\d{1,6}$') {
            $v = [int]$s
            if ($v -ge $min -and $v -le $max) { return $v }
        }
        Write-Host '  Неверное значение, попробуй еще раз.'
    }
}

function Menu-Convert {
    if (-not (Test-Tools)) { return }
    $files = @(Select-Media 'КОНВЕРТАЦИЯ')
    if ($files.Count -eq 0) { return }
    $t = $null
    while ($null -eq $t) {
        Draw-Header
        Write-Host '  КОНВЕРТАЦИЯ - в какой формат?'
        Write-Host ''
        Write-Host '  Видео:   1 mp4    2 mkv    3 avi    4 mov    5 webm'
        Write-Host '  Аудио:   6 mp3    7 wav    8 flac    9 m4a    10 ogg    11 opus'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        foreach ($x in $global:ConvTargets) { if ($x.Key -eq $c) { $t = $x } }
    }
    $out = Ask-Output '_converted'
    if ($null -eq $out) { return }
    $b = Build-Queue $files
    if ($b.Cancelled) { Say-Msg 'Отменено.'; return }
    $items = @($b.Items)
    Prep-Convert $items $t
    if (-not (Confirm-Queue $items $out.Mode '_converted')) { return }
    Run-Queue $items $out.Mode '_converted' ('КОНВЕРТАЦИЯ в ' + $t.Ext)
}

function Menu-Compress {
    if (-not (Test-Tools)) { return }
    $files = @(Select-Media 'СЖАТИЕ')
    if ($files.Count -eq 0) { return }
    $hasAud = (@($files | Where-Object { $global:AudioExt -contains $_.Ext.TrimStart('.').ToLowerInvariant() }).Count -gt 0)
    $hasVid = (@($files | Where-Object { $global:AudioExt -notcontains $_.Ext.TrimStart('.').ToLowerInvariant() }).Count -gt 0)
    $spec = $null
    while ($null -eq $spec) {
        Draw-Header
        Write-Host '  СЖАТИЕ - насколько сильно?'
        Write-Host ''
        Write-Host '  1  Lossless - без потерь, файлы могут стать БОЛЬШЕ'
        Write-Host '  2  Почти без потерь     видео CRF 18     аудио 256 кбит/с'
        Write-Host '  3  Легкое               видео CRF 23     аудио 192 кбит/с'
        Write-Host '  4  Среднее              видео CRF 28     аудио 128 кбит/с'
        Write-Host '  5  Сильное              видео CRF 32     аудио 64 кбит/с'
        Write-Host '  6  Свое качество'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        if ($c -eq '1') { $spec = @{ Lossless = $true; Crf = 0; Abr = 0 } }
        elseif ($c -eq '2') { $spec = @{ Lossless = $false; Crf = 18; Abr = 256 } }
        elseif ($c -eq '3') { $spec = @{ Lossless = $false; Crf = 23; Abr = 192 } }
        elseif ($c -eq '4') { $spec = @{ Lossless = $false; Crf = 28; Abr = 128 } }
        elseif ($c -eq '5') { $spec = @{ Lossless = $false; Crf = 32; Abr = 64 } }
        elseif ($c -eq '6') {
            $crf = 23
            $abr = 128
            $back = $false
            if ($hasVid) {
                $crf = Ask-Int '  CRF для видео от 0 до 51, меньше = лучше качество, 23 норма, b - назад: ' 0 51
                if ($null -eq $crf) { $back = $true }
            }
            if (-not $back -and $hasAud) {
                $abr = Ask-Int '  Битрейт для аудио в кбит/с, от 32 до 320, например 128, b - назад: ' 32 320
                if ($null -eq $abr) { $back = $true }
            }
            if (-not $back) { $spec = @{ Lossless = $false; Crf = [int]$crf; Abr = [int]$abr } }
        }
    }
    $out = Ask-Output '_compressed'
    if ($null -eq $out) { return }
    $b = Build-Queue $files
    if ($b.Cancelled) { Say-Msg 'Отменено.'; return }
    $items = @($b.Items)
    Prep-Compress $items $spec
    if (-not (Confirm-Queue $items $out.Mode '_compressed')) { return }
    Run-Queue $items $out.Mode '_compressed' 'СЖАТИЕ'
}

# ============================================================================
#  Поиск дублей
# ============================================================================
function Menu-Dupes {
    $c = ''
    while ($true) {
        Draw-Header
        Write-Host '  ПОИСК ДУБЛЕЙ'
        Write-Host ''
        Write-Host '  1  По названию, размеру и разрешению'
        Write-Host '     Файл  имя (2).mp4  считается копией файла  имя.mp4'
        Write-Host '  2  По содержимому - точные копии под любыми именами'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        if ($c -eq '1' -or $c -eq '2') { break }
    }
    $files = @(Get-Entries $global:Recurse | Where-Object { -not $_.IsDir -and $_.Size -gt 0 })
    if ($files.Count -lt 2) { Say-Msg 'Файлов слишком мало для поиска дублей.'; return }
    $haveProbe = $false
    if ($c -eq '1') {
        $a = Get-Command ffprobe -ErrorAction SilentlyContinue
        if ($a) { $haveProbe = $true }
    }
    $groups = New-Object System.Collections.ArrayList
    $cancel = $false
    Write-Host ''
    [Console]::TreatControlCAsInput = $true
    try {
        $buckets = @{}
        foreach ($f in $files) {
            if ($c -eq '1') { $k = (Norm-Name $f.Base) + '|' + $f.Ext.ToLowerInvariant() + '|' + $f.Size }
            else { $k = [string]$f.Size }
            if (-not $buckets.ContainsKey($k)) { $buckets[$k] = New-Object System.Collections.ArrayList }
            [void]$buckets[$k].Add($f)
        }
        $cand = @($buckets.Values | Where-Object { $_.Count -gt 1 })
        $i = 0
        foreach ($b in $cand) {
            $i++
            if (Test-Cancel) { $cancel = $true; break }
            $txt = ('  Сверяю: {0} из {1}      Esc - отмена' -f $i, $cand.Count)
            Write-Host -NoNewline ("`r" + $txt.PadRight(60))
            $sub = @{}
            foreach ($f in $b) {
                if ($c -eq '1') {
                    $rk = ''
                    $isVid = ($global:VideoExt -contains $f.Ext.TrimStart('.').ToLowerInvariant())
                    if ($isVid -and $haveProbe) {
                        $pr = Probe $f.Path
                        $rk = ('{0}x{1}' -f $pr.W, $pr.H)
                    }
                    $f.Res = $rk
                } else {
                    try { $f.Res = (Get-FileHash -LiteralPath $f.Path -Algorithm SHA256).Hash } catch { $f.Res = 'err_' + $f.Path }
                }
                if (-not $sub.ContainsKey($f.Res)) { $sub[$f.Res] = New-Object System.Collections.ArrayList }
                [void]$sub[$f.Res].Add($f)
            }
            foreach ($s in $sub.Values) {
                if ($s.Count -lt 2) { continue }
                $sorted = @($s | Sort-Object @{ Expression = { if ((Norm-Name $_.Base) -eq $_.Base.Trim().ToLowerInvariant()) { 0 } else { 1 } } }, @{ Expression = { $_.Time } }, @{ Expression = { $_.Path.Length } })
                $g = New-Object PSObject -Property @{ Files = $sorted; Include = $true; Res = $s[0].Res }
                [void]$groups.Add($g)
            }
        }
    } finally {
        [Console]::TreatControlCAsInput = $false
    }
    if ($cancel) { Say-Msg 'Поиск отменен.'; return }
    if ($groups.Count -eq 0) { Say-Msg 'Дублей не найдено.'; return }
    $rootLen = $global:Root.TrimEnd('\').Length + 1
    while ($true) {
        Draw-Header
        Write-Host ('  НАЙДЕНО ГРУПП ДУБЛЕЙ: ' + $groups.Count)
        Write-Host ''
        $lines = New-Object System.Collections.ArrayList
        $dupCount = 0
        $dupSize = [long]0
        $w = ([string]$groups.Count).Length
        for ($gi = 0; $gi -lt $groups.Count; $gi++) {
            $g = $groups[$gi]
            $num = ([string]($gi + 1)).PadLeft($w)
            $mark = ''
            if (-not $g.Include) { $mark = '   [не трогать]' }
            $res = ''
            if ($g.Res -match '^\d+x\d+$' -and $c -eq '1') { $res = ',  ' + $g.Res }
            [void]$lines.Add(('  Группа {0}:  {1} {2} по {3}{4}{5}' -f $num, $g.Files.Count, (Plural $g.Files.Count 'файл' 'файла' 'файлов'), (Fmt-Size $g.Files[0].Size), $res, $mark))
            for ($k = 0; $k -lt $g.Files.Count; $k++) {
                $f = $g.Files[$k]
                $rel = $f.Path
                if ($rel.Length -gt $rootLen) { $rel = $rel.Substring($rootLen) }
                if ($k -eq 0) { [void]$lines.Add('       [оставить]  ' + $rel) }
                else {
                    [void]$lines.Add('       [дубль]     ' + $rel)
                    if ($g.Include) { $dupCount++; $dupSize += [long]$f.Size }
                }
            }
        }
        Show-Paged $lines.ToArray()
        Write-Host ''
        Write-Host ('  Дублей к удалению: {0}      Освободится: {1}' -f $dupCount, (Fmt-Size $dupSize))
        Write-Host ''
        Write-Host '  Enter - продолжить      x - не трогать некоторые группы      0 - назад'
        $a = (AskT '  Выбор: ').ToLowerInvariant()
        if ($a -eq '0' -or $a -eq 'b' -or $a -eq 'и') { return }
        if ($a -eq 'x' -or $a -eq 'ч') {
            $s = Ask '  Номера групп, которые не трогать, например 3, 7 или 2-5. Повторный ввод возвращает группу. b - назад: '
            if (-not (Is-BackText $s)) {
                $nums = @(Parse-Nums $s $groups.Count)
                foreach ($n in $nums) { $groups[$n - 1].Include = -not $groups[$n - 1].Include }
            }
            continue
        }
        if ($a -ne '') { continue }
        if ($dupCount -eq 0) { Say-Msg 'Нечего удалять: все группы исключены.'; return }
        Draw-Header
        Write-Host ('  Что сделать с {0} дублями?' -f $dupCount)
        Write-Host ''
        Write-Host '  1  Удалить в корзину'
        Write-Host '  2  Переместить в папку Duplicates'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $m = AskT '  Выбор: '
        if ($m -ne '1' -and $m -ne '2') { continue }
        $ok = 0
        $bad = 0
        $freed = [long]0
        if ($m -eq '1') { Add-Type -AssemblyName Microsoft.VisualBasic }
        $dupDir = Join-Path $global:Root 'Duplicates'
        foreach ($g in $groups) {
            if (-not $g.Include) { continue }
            for ($k = 1; $k -lt $g.Files.Count; $k++) {
                $f = $g.Files[$k]
                try {
                    if ($m -eq '1') {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    } else {
                        [void][IO.Directory]::CreateDirectory($dupDir)
                        $dest = Unique-Path (Join-Path $dupDir $f.Name)
                        [IO.File]::Move($f.Path, $dest)
                    }
                    $ok++
                    $freed += [long]$f.Size
                } catch { $bad++ }
            }
        }
        $global:StatsDirty = $true
        $msg = ('Готово. Обработано дублей: {0}, освобождено: {1}.' -f $ok, (Fmt-Size $freed))
        if ($bad -gt 0) { $msg += ('  Не удалось: ' + $bad) }
        Say-Msg $msg
        return
    }
}

# ============================================================================
#  Сортировка по типам
# ============================================================================
function Menu-Sort {
    $mode = ''
    while ($true) {
        Draw-Header
        Write-Host '  СОРТИРОВКА ПО ТИПАМ'
        Write-Host '  Раскладывает файлы, лежащие прямо в этой папке, по папкам.'
        Write-Host ''
        Write-Host '  1  Стандартная: Видео, Аудио, Изображения, Документы, Архивы'
        Write-Host '  2  Только мои правила'
        Write-Host '  3  Стандартная + мои правила, мои главнее'
        Write-Host ''
        Write-Host '  0  Назад'
        Write-Host ''
        $c = AskT '  Выбор: '
        if (Is-Back $c) { return }
        if ($c -eq '1' -or $c -eq '2' -or $c -eq '3') { $mode = $c; break }
    }
    $map = @{}
    if ($mode -ne '2') {
        foreach ($x in $global:VideoExt) { $map[$x] = 'Видео' }
        foreach ($x in $global:AudioExt) { $map[$x] = 'Аудио' }
        foreach ($x in $global:ImageExt) { $map[$x] = 'Изображения' }
        foreach ($x in $global:DocExt)   { $map[$x] = 'Документы' }
        foreach ($x in $global:ArcExt)   { $map[$x] = 'Архивы' }
    }
    if ($mode -ne '1') {
        Draw-Header
        Write-Host '  МОИ ПРАВИЛА'
        Write-Host ''
        Write-Host '  Пиши по одному правилу: расширения = папка. Примеры:'
        Write-Host '    mp4, mkv = Фильмы'
        Write-Host '    jpg png -> Фото'
        Write-Host '  Пустая строка - закончить.  b - назад.'
        Write-Host ''
        $rules = 0
        while ($true) {
            $l = Ask '  Правило: '
            if (Is-BackText $l) { return }
            if ($l.Trim() -eq '') { break }
            $m = [regex]::Match($l, '^(.*?)\s*(?:=|->)\s*(.+)$')
            if (-not $m.Success) { Write-Host '  Не понял. Нужно так:  mp4, mkv = Фильмы'; continue }
            $fold = $m.Groups[2].Value.Trim()
            if ($fold.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $fold -eq '') { Write-Host '  В названии папки недопустимые символы.'; continue }
            $n = 0
            foreach ($t in ($m.Groups[1].Value -split '[,;\s]+')) {
                $x = $t.Trim().TrimStart('.').ToLowerInvariant()
                if ($x -ne '') { $map[$x] = $fold; $n++ }
            }
            if ($n -eq 0) { Write-Host '  Не нашел расширений слева от знака равно.'; continue }
            $rules++
            Write-Host ('  Принято. Правил: ' + $rules)
        }
        if ($mode -eq '2' -and $rules -eq 0) { Say-Msg 'Правил нет, сортировать нечего.'; return }
    }
    $other = 'keep'
    Write-Host ''
    Write-Host '  Файлы, для которых нет правила:'
    Write-Host '  1  Оставить на месте'
    Write-Host '  2  Переложить в папку Прочее'
    $o = AskT '  Выбор, Enter = 1: '
    if ($o -eq '2') { $other = 'folder' }
    $files = @(Get-Entries $false | Where-Object { -not $_.IsDir })
    $plan = New-Object System.Collections.ArrayList
    foreach ($f in $files) {
        $x = $f.Ext.TrimStart('.').ToLowerInvariant()
        $folder = $null
        if ($x -ne '' -and $map.ContainsKey($x)) { $folder = $map[$x] }
        elseif ($other -eq 'folder') { $folder = 'Прочее' }
        if ($null -eq $folder) { continue }
        [void]$plan.Add((New-Object PSObject -Property @{ File = $f; Folder = $folder }))
    }
    if ($plan.Count -eq 0) { Say-Msg 'Нет файлов, которые попали бы под правила.'; return }
    Draw-Header
    Write-Host '  ПРЕДПРОСМОТР СОРТИРОВКИ'
    Write-Host ''
    $byFolder = @($plan | Group-Object Folder | Sort-Object Name)
    foreach ($g in $byFolder) {
        Write-Host ('  {0}  -  {1} {2}' -f $g.Name.PadRight(18), $g.Count, (Plural $g.Count 'файл' 'файла' 'файлов'))
    }
    Write-Host ''
    Write-Host ('  Всего будет перемещено: ' + $plan.Count)
    Write-Host ''
    $a = AskT '  Enter - переместить, 0 - отмена: '
    if (Is-Back $a) { return }
    $ok = 0
    $bad = 0
    foreach ($p in $plan) {
        try {
            $dir = Join-Path $global:Root $p.Folder
            [void][IO.Directory]::CreateDirectory($dir)
            $dest = Unique-Path (Join-Path $dir $p.File.Name)
            [IO.File]::Move($p.File.Path, $dest)
            $ok++
        } catch { $bad++ }
    }
    $global:StatsDirty = $true
    $msg = 'Готово. Перемещено файлов: ' + $ok
    if ($bad -gt 0) { $msg += ('   Не удалось: ' + $bad) }
    Say-Msg $msg
}

# ============================================================================
#  Удалить пустые папки
# ============================================================================
function Menu-Empty {
    Draw-Header
    Write-Host '  УДАЛЕНИЕ ПУСТЫХ ПАПОК'
    Write-Host ''
    $dirs = @(Get-ChildItem -LiteralPath $global:Root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
    $empty = New-Object System.Collections.ArrayList
    $emptySet = @{}
    foreach ($d in $dirs) {
        $kids = @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)
        $real = 0
        foreach ($k in $kids) {
            if (-not $k.PSIsContainer) { $real++ }
            elseif (-not $emptySet.ContainsKey($k.FullName)) { $real++ }
        }
        if ($real -eq 0) {
            $emptySet[$d.FullName] = $true
            [void]$empty.Add($d.FullName)
        }
    }
    if ($empty.Count -eq 0) { Say-Msg 'Пустых папок нет.'; return }
    $rootLen = $global:Root.TrimEnd('\').Length + 1
    $lines = New-Object System.Collections.ArrayList
    foreach ($p in $empty) {
        $rel = $p
        if ($rel.Length -gt $rootLen) { $rel = $rel.Substring($rootLen) }
        [void]$lines.Add('   - ' + $rel)
    }
    Write-Host ('  Найдено пустых папок: ' + $empty.Count)
    Write-Host ''
    Show-Paged $lines.ToArray()
    Write-Host ''
    $a = AskT '  Enter - удалить, 0 - отмена: '
    if (Is-Back $a) { return }
    $ok = 0
    $bad = 0
    foreach ($p in $empty) {
        try { [IO.Directory]::Delete($p); $ok++ } catch { $bad++ }
    }
    $global:StatsDirty = $true
    $msg = 'Готово. Удалено папок: ' + $ok
    if ($bad -gt 0) { $msg += ('   Не удалось: ' + $bad) }
    Say-Msg $msg
}

# ============================================================================
#  ГЛАВНОЕ МЕНЮ
# ============================================================================
$running = $true
while ($running) {
    try { [Console]::TreatControlCAsInput = $false } catch { }
    $global:StatsDirty = $true
    Draw-Header
    $sub = 'нет'
    if ($global:Recurse) { $sub = 'да' }
    Write-Host '  1  Имя - переименование и замена'
    Write-Host '  2  Конвертировать все файлы'
    Write-Host '  3  Сжать все файлы'
    Write-Host '  4  Поиск дублей'
    Write-Host '  5  Сортировка по типам'
    Write-Host '  6  Удалить пустые папки'
    Write-Host ('  S  Подпапки: ' + $sub + '     - нажми S, чтобы переключить')
    Write-Host '  0  Выход'
    Write-Host ''
    $c = (AskT '  Выбор: ').ToLowerInvariant()
    try {
        if ($c -eq '0') { $running = $false }
        elseif ($c -eq '1') { Menu-Name }
        elseif ($c -eq '2') { Menu-Convert }
        elseif ($c -eq '3') { Menu-Compress }
        elseif ($c -eq '4') { Menu-Dupes }
        elseif ($c -eq '5') { Menu-Sort }
        elseif ($c -eq '6') { Menu-Empty }
        elseif ($c -eq 's' -or $c -eq 'ы') { $global:Recurse = -not $global:Recurse }
    } catch {
        try { [Console]::TreatControlCAsInput = $false } catch { }
        Say-Msg ('Ошибка: ' + $_.Exception.Message)
    }
}
exit 0
