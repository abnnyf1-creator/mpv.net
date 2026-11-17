<#
.SYNOPSIS
    mpv.net 一键构建脚本（Windows，不需要 Visual Studio）。

.DESCRIPTION
    目标框架：net10.0 / net10.0-windows7.0 —— 只需要 .NET 10 SDK，SDK 自带 MSBuild 与 NuGet。

    五个步骤：
      [1/6] 检测 .NET 10 SDK；缺失时用官方 dotnet-install.ps1 装到用户目录（免管理员、不改系统 PATH）
      [2/6] 从 src\MpvNet.Windows\MpvNet.Windows.csproj 读 FileVersion 作为版本号
      [3/6] dotnet publish（Release / win-x64 / 单文件）
      [4/6] 组装 dist\mpv.net-v<版本>-portable-x64\，并按需补 libmpv-2.dll / MediaInfo.dll / mpvnet.com
      [5/6] 打包 zip
      [6/6] 用 Inno Setup 6 编译安装器（捆绑 Icaros 缩略图组件）；
            未安装 Inno Setup 时自动跳过，不影响前五步产物

    运行时依赖说明：libmpv-2.dll（mpv 播放内核）和 MediaInfo.dll 不在源码里，
    默认从 GitHub 上 mpv.net 官方便携包中抽取，缓存到
    %LOCALAPPDATA%\mpvnet-runtime\，第二次构建不再重复下载。
    没有这两个 DLL 时程序能启动但无法播放，所以默认会拉。

.PARAMETER NoRuntime
    不下载 libmpv-2.dll / MediaInfo.dll / mpvnet.com，只出 exe。
.PARAMETER RuntimeZip
    已有的官方便携包 zip 本地路径（比如从共享拷过来的），给了就不联网。
.PARAMETER Clean
    构建前清掉 bin / obj。
.PARAMETER Configuration
    默认 Release。
.PARAMETER NoBump
    兼容其他项目脚本的调用习惯；本项目版本号来自 csproj，不做递增，参数被忽略。
.PARAMETER InnoSetup
    显式指定 ISCC.exe 路径；不给则自动探测（Program Files / PATH）。

.EXAMPLE
    .\build.ps1
    .\build.ps1 -NoRuntime
    .\build.ps1 -Clean -Configuration Debug
#>
param(
    [switch]$NoRuntime,
    [switch]$Clean,
    [string]$RuntimeZip = '',
    [string]$Configuration = 'Release',
    [switch]$NoBump,
    [string]$InnoSetup = ''
)

$ErrorActionPreference = 'Stop'

function Step([string]$n, [string]$msg) { Write-Host ("[$n] $msg") -ForegroundColor Cyan }
function Note([string]$msg) { Write-Host ("      " + $msg) -ForegroundColor DarkGray }
function Ok([string]$msg)   { Write-Host ("      OK  " + $msg) -ForegroundColor Green }
function Warn([string]$msg) { Write-Host ("      !!  " + $msg) -ForegroundColor Yellow }

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $root
$proj = Join-Path $root 'src\MpvNet.Windows\MpvNet.Windows.csproj'
if (-not (Test-Path -LiteralPath $proj)) { throw "找不到项目文件：$proj" }

# 先判断是不是共享/网络路径：日志绝不允许写到共享盘
$isNetPath = ($root -match '^\\\\') -or ($root -match '^//')
$driveInfo = $null
try { $driveInfo = (Get-Item -LiteralPath $root).PSDrive } catch { }
if (-not $isNetPath -and $driveInfo -and $driveInfo.DisplayRoot -and $driveInfo.DisplayRoot -match '^\\\\') { $isNetPath = $true }

if ($isNetPath) {
    $logFile = Join-Path $env:LOCALAPPDATA 'mpvnet-build-last.log'
} else {
    $logFile = Join-Path $root '_build.log'
}

# 崩溃也要留痕：任何未捕获错误都写进日志，窗口不会“静默闪退”
try { Start-Transcript -Path $logFile -Append -Force | Out-Null } catch { }
trap {
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host ''
    Write-Host ("构建中断：" + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("       详细日志：" + $logFile) -ForegroundColor Yellow
    exit 1
}

# 保护：不允许在网络路径（UNC / 映射的网络盘）上直接构建，
# 否则 MSBuild 的 obj/bin/dist 会写进共享盘。
if ($isNetPath) {
    throw ("拒绝在共享路径上构建：" + $root + "`n请先同步到本地盘，再在本地副本里运行 build.ps1（或用 tools\logbuild.cmd / build-on-vm.cmd）。")
}

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host ' mpv.net 构建' -ForegroundColor DarkCyan
Write-Host (" 项目：" + $root) -ForegroundColor DarkCyan
Write-Host '============================================================' -ForegroundColor DarkCyan

# ---------- 1. .NET 10 SDK ----------
Step '1/6' '.NET 10 SDK'

function Test-Sdk10([string]$exe) {
    try {
        $sdks = & $exe --list-sdks 2>$null
        if ($sdks -and ($sdks -match '^10\.')) { return $true }
    } catch { }
    return $false
}

function Find-Dotnet10 {
    $cands = @()
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'),
        'C:\tools\dotnet\dotnet.exe',
        'C:\Program Files\dotnet\dotnet.exe'
    )) {
        if (Test-Path -LiteralPath $p) { $cands += $p }
    }
    foreach ($exe in $cands) {
        if (Test-Sdk10 $exe) { return $exe }
    }
    return $null
}

function Invoke-HttpDownload([string]$url, [string]$path, [int]$timeoutSec = 1800) {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $had = 0
    if (Test-Path -LiteralPath $path) { $had = [int64](Get-Item -LiteralPath $path).Length }
    $h = New-Object System.Net.Http.HttpClientHandler
    $h.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $h.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $c = New-Object System.Net.Http.HttpClient($h)
    $c.Timeout = [TimeSpan]::FromSeconds($timeoutSec)
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
    if ($had -gt 0) { $req.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue($had, $null) }
    $resp = $c.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
    $code = [int]$resp.StatusCode
    if ($code -eq 416 -and $had -gt 0) { return $had }
    if ($code -ne 200 -and $code -ne 206) { throw ('HTTP ' + $code) }
    $mode = [System.IO.FileMode]::Create
    if ($code -eq 206 -and $had -gt 0) { $mode = [System.IO.FileMode]::Append }
    $fs = New-Object System.IO.FileStream($path, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $stream = $resp.Content.ReadAsStreamAsync().Result
    $buf = New-Object byte[] 131072
    $written = 0
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $fs.Write($buf, 0, $n)
            $written += $n
            if (($written % 5242880) -lt 131072) { Note ('  进度 ' + [math]::Round(($had + $written) / 1MB, 1) + ' MB') }
        }
    } finally {
        try { $fs.Flush() } catch {}
        $fs.Dispose()
        $stream.Dispose()
        $c.Dispose()
    }
    return ($had + $written)
}

function Test-ZipIntact([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [IO.Compression.ZipFile]::OpenRead($path)
        $n = $z.Entries.Count
        $z.Dispose()
        return ($n -gt 0)
    } catch { return $false }
}

function Test-ZipHasRuntime([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [IO.Compression.ZipFile]::OpenRead($path)
        $hit = $false
        foreach ($e in $z.Entries) { if ($e.Name -eq 'libmpv-2.dll') { $hit = $true; break } }
        $z.Dispose()
        return $hit
    } catch { return $false }
}

function Get-MpvRuntimeZip([string]$targetDir, [string]$ver) {
    $assetName = 'mpv.net-v' + $ver + '-portable-x64.zip'
    $urls = New-Object 'System.Collections.Generic.List[string]'
    # 首选 GitHub API 解析最新资产；但 API 常被限流（403），失败就按项目版本号拼直链
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/mpvnet-player/mpv.net/releases/latest' -UseBasicParsing -TimeoutSec 30
        $hit = $rel.assets | Where-Object { $_.name -like '*portable-x64.zip' } | Select-Object -First 1
        if ($hit) {
            $assetName = $hit.name
            Note ("API 解析到资产：" + $assetName + "（" + [math]::Round($hit.size / 1MB, 1) + " MB）")
            $urls.Add($hit.browser_download_url)
        }
    } catch {
        Note 'API 不可用（多为匿名限流），改用项目版本号拼出下载直链'
    }
    if ($urls.Count -eq 0) {
        $urls.Add("https://github.com/mpvnet-player/mpv.net/releases/download/v$ver/$assetName")
        $urls.Add("https://github.com/mpvnet-player/mpv.net/releases/download/$ver/$assetName")
    }
    $target = Join-Path $targetDir $assetName
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    # GitHub 直连在国内常被重置，按顺序试直连和几个加速镜像，每轮都用 -C - 续传
    $bases = @('', 'https://ghproxy.net/', 'https://ghfast.top/')
    for ($pass = 1; $pass -le 6; $pass++) {
        $b = $bases[($pass - 1) % $bases.Count]
        foreach ($u0 in $urls) {
            $have = 0
            if (Test-Path -LiteralPath $target) { $have = [int64](Get-Item -LiteralPath $target).Length }
            if (Test-ZipHasRuntime $target) { return $target }
            $u = if ($b) { $b + $u0 } else { $u0 }
            Note ("  第 $pass 轮 / " + $(if ($b) { $b } else { 'GitHub 直连（走系统代理）' }) + "  已有 " + [math]::Round($have / 1MB, 1) + " MB")
            try {
                $sz = Invoke-HttpDownload $u $target 1800
                Note ("  本轮结束，已有 " + [math]::Round($sz / 1MB, 1) + " MB")
            } catch {
                Note ("  这个源出错：" + $_.Exception.Message)
            }
            if (Test-ZipHasRuntime $target) {
                $now = (Get-Item -LiteralPath $target).Length
                Ok ("运行时包已完整：" + [math]::Round($now / 1MB, 1) + " MB")
                return $target
            }
        }
    }
    return $null
}

$dotnet = Find-Dotnet10
if ($dotnet) {
    Ok ("已就绪：" + $dotnet)
} else {
    $installDir = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'
    Note ".NET 10 SDK 缺失，用官方脚本装到 $installDir（不需要管理员权限）"
    $installer = Join-Path $env:TEMP 'dotnet-install-mpvnet.ps1'
    if (-not (Test-Path -LiteralPath $installer)) {
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer -UseBasicParsing -TimeoutSec 120
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Channel 10.0 -InstallDir $installDir 6>$null
    $env:Path = $installDir + ';' + $env:Path
    $dotnet = Find-Dotnet10
    if (-not $dotnet) { throw '安装后仍未检测到 .NET 10 SDK，可手动装：https://dotnet.microsoft.com/download/dotnet/10.0' }
    Ok ("已安装：" + $dotnet)
}

# ---------- 2. 版本号 ----------
Step '2/6' '版本号'
$text = Get-Content -LiteralPath $proj -Raw -Encoding utf8
$m = [regex]::Match($text, '<FileVersion>([0-9]+(?:\.[0-9]+)*)</FileVersion>')
$ver = '0.0.0'
if ($m.Success) { $ver = $m.Groups[1].Value }
Ok ("FileVersion = $ver（来自 MpvNet.Windows.csproj）")

# ---------- 3. 编译 ----------
Step '3/6' 'dotnet publish'
if ($Clean) {
    foreach ($d in @('src\MpvNet.Windows\bin', 'src\MpvNet.Windows\obj', 'src\MpvNet\bin', 'src\MpvNet\obj', 'src\NGettext.Wpf\bin', 'src\NGettext.Wpf\obj')) {
        $full = Join-Path $root $d
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force; Note "已清理 $d" }
    }
}
Note ("配置 $Configuration / win-x64 / 单文件；首次会下载 NuGet 包")
& $dotnet publish $proj -c $Configuration -r win-x64 --self-contained false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish 失败（exit=$LASTEXITCODE）" }

$publishDir = Join-Path $root "src\MpvNet.Windows\bin\$Configuration\win-x64\publish"
if (-not (Test-Path -LiteralPath (Join-Path $publishDir 'mpvnet.exe'))) { throw "publish 输出里没有 mpvnet.exe：$publishDir" }
Ok ("输出：" + $publishDir)

# ---------- 4. 组装产物 ----------
Step '4/6' '组装 dist'
$outName = "mpv.net-v$ver-portable-x64"
$distRoot = Join-Path $root 'dist'
$outDir = Join-Path $distRoot $outName
if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Get-ChildItem -LiteralPath $publishDir -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $outDir -Recurse -Force }
Ok ("已拷入 publish 产物 -> $outName")

$runtimeFiles = @('libmpv-2.dll', 'MediaInfo.dll', 'mpvnet.com')
$found = @{}
$rtTmp = $null
foreach ($f in $runtimeFiles) {
    foreach ($cand in @(
        (Join-Path $root "src\MpvNet.Windows\bin\$Configuration\win-x64\$f"),
        (Join-Path $root "runtime\$f"),
        (Join-Path $root $f)
    )) {
        if (Test-Path -LiteralPath $cand) { $found[$f] = $cand; break }
    }
}

if ($found.Count -lt $runtimeFiles.Count -and -not $NoRuntime) {
    $cacheDir = Join-Path $env:LOCALAPPDATA 'mpvnet-runtime'
    if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

    $zip = $RuntimeZip
    if (-not $zip -and $env:MPVNET_RUNTIME_ZIP) { $zip = $env:MPVNET_RUNTIME_ZIP }
    # 本地已有的包优先（避免联网）：-RuntimeZip > 环境变量 > 项目旁 _deps / _runtime > 用户缓存
    foreach ($dir in @(
        (Join-Path $root '_runtime'),
        (Join-Path (Split-Path -Parent $root) '_deps'),
        (Join-Path $root '_deps'),
        $cacheDir
    )) {
        if ($zip) { break }
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $hit = Get-ChildItem -LiteralPath $dir -Filter 'mpv.net-*-portable-x64.zip' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) {
            if (Test-ZipHasRuntime $hit.FullName) {
                $zip = $hit.FullName
                Note ("使用本地包：" + $zip)
            } else {
                Note ("跳过不完整的包：" + $hit.FullName + "（" + [math]::Round($hit.Length / 1MB, 1) + " MB，会尝试续传）")
            }
        }
    }

    if (-not $zip -or -not (Test-Path -LiteralPath $zip)) {
        Note '本地没有官方便携包，由本机下载到用户缓存（断点续传 + 多镜像，失败只跳过运行时文件）'
        try {
            $zip = Get-MpvRuntimeZip $cacheDir $ver
        } catch {
            Note ("  获取失败：" + $_.Exception.Message)
            $zip = $null
        }
        if (-not $zip) {
            Warn '运行时文件没拿到，本次只出 exe；网络恢复后重跑会自动续传'
        }
    }
    if ($zip -and (Test-Path -LiteralPath $zip)) {
        $tmp = Join-Path $env:TEMP ('mpvnet_rt_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        Note ('解包 ' + (Split-Path -Leaf $zip))
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        try {
            # PS 5.1 的 Expand-Archive 解 100MB 级压缩包会中途抛错，这里直接用 .NET
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
        } catch {
            Note ('  .NET 整体解包出错：' + $_.Exception.Message + '，改为逐个条目解压')
            try {
                $arch = [IO.Compression.ZipFile]::OpenRead($zip)
                foreach ($e in $arch.Entries) {
                    if ($e.Length -eq 0) { continue }
                    $dest = Join-Path $tmp ($e.FullName -replace '/', '\')
                    $sub = Split-Path -Parent $dest
                    if (-not (Test-Path -LiteralPath $sub)) { New-Item -ItemType Directory -Path $sub -Force | Out-Null }
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                }
                $arch.Dispose()
            } catch {
                Warn ('解包失败（包可能不完整）：' + $_.Exception.Message)
            }
        }
        foreach ($f in $runtimeFiles) {
            if ($found.ContainsKey($f)) { continue }
            $hit = Get-ChildItem -LiteralPath $tmp -Recurse -Filter $f -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) {
                $found[$f] = $hit.FullName
                Note ('  取到 ' + $f + '  ' + [math]::Round($hit.Length / 1MB, 1) + ' MB')
            }
        }
        $rtTmp = $tmp
    }
}

foreach ($f in $runtimeFiles) {
    if ($found.ContainsKey($f) -and (Test-Path -LiteralPath $found[$f])) {
        Copy-Item -LiteralPath $found[$f] -Destination (Join-Path $outDir $f) -Force
        Ok ("运行时文件 $f")
    } else {
        Warn ("缺 $f（程序能启动但相关功能不可用）")
    }
}
if ($rtTmp -and (Test-Path -LiteralPath $rtTmp)) { Remove-Item -LiteralPath $rtTmp -Recurse -Force -ErrorAction SilentlyContinue }

# 界面翻译（gettext .mo，已预编译进仓库 lang/mo/，避免构建机需要 msgfmt）
# 放到 exe 目录 Locale/<语言>/LC_MESSAGES/mpvnet.mo，程序按系统语言自动加载
$localeSrc = Join-Path $root 'lang\mo'
if (Test-Path -LiteralPath $localeSrc) {
    Copy-Item -LiteralPath $localeSrc -Destination (Join-Path $outDir 'Locale') -Recurse -Force
    $moCount = (Get-ChildItem -LiteralPath (Join-Path $outDir 'Locale') -Filter 'mpvnet.mo' -Recurse -File).Count
    Ok ("界面翻译 Locale（$moCount 种语言，含简体中文）")
} else {
    Warn '缺 lang\mo\（界面翻译），菜单将显示英文'
}

# ---------- 5. 打包 ----------
Step '5/6' '打包 zip'
$zipPath = Join-Path $distRoot ($outName + '.zip')
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Ok ((Split-Path -Leaf $zipPath) + '  ' + [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1) + ' MB')

# ---------- 6. 编译安装器（可选，含 Icaros 捆绑） ----------
$setupPath = $null
$iscc = $InnoSetup
if (-not $iscc) {
    # 常见安装位置：Inno Setup 6 / 7 都认（目录通配 + 用户级安装 / scoop / chocolatey）
    $cands = @()
    foreach ($pf in @('C:\Program Files (x86)', 'C:\Program Files', (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        Get-ChildItem -Path $pf -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue |
            ForEach-Object { $cands += (Join-Path $_.FullName 'ISCC.exe') }
    }
    $cands += @(
        'C:\Program Files (x86)\Inno Setup\ISCC.exe',
        'C:\Program Files\Inno Setup\ISCC.exe',
        (Join-Path $env:USERPROFILE 'scoop\apps\innosetup\current\Inno Setup 6\ISCC.exe'),
        'C:\ProgramData\chocolatey\lib\innosetup\tools\Inno Setup 6\ISCC.exe'
    )
    # 注册表（Inno Setup 6/7 安装器都会写 Uninstall 键的 InstallLocation，自定义安装路径也能找到）
    foreach ($rk in (Get-ChildItem -Path @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            ) -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Inno Setup *' })) {
        try {
            $loc = (Get-ItemProperty -Path $rk.PSPath -ErrorAction Stop).InstallLocation
            if ($loc) { $cands += (Join-Path $loc.TrimEnd('\') 'ISCC.exe') }
        } catch { }
    }
    foreach ($cand in $cands) {
        if ($cand -and (Test-Path -LiteralPath $cand)) { $iscc = $cand; break }
    }
    if (-not $iscc) {
        $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
        if ($cmd) { $iscc = $cmd.Source }
    }
}

# 仍然找不到 → 自动下载 Inno Setup 6.7.4 并静默装到用户目录（免管理员、不改系统 PATH）
if (-not $iscc) {
    $isDir = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6'
    $iscc = Join-Path $isDir 'ISCC.exe'
    if (-not (Test-Path -LiteralPath $iscc)) {
        Note '未安装 Inno Setup，自动静默安装到用户目录（免管理员）：' + $isDir
        $cacheDir = Join-Path $env:LOCALAPPDATA 'mpvnet-build-tools'
        if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        $isExe = Join-Path $cacheDir 'innosetup-6.7.4.exe'
        $asset = 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_4/innosetup-6.7.4.exe'
        $dlOk = $false
        foreach ($u in @($asset, "https://ghproxy.net/$asset", "https://ghfast.top/$asset")) {
            try {
                Note ('  下载：' + $u)
                Invoke-HttpDownload $u $isExe 600 | Out-Null
                if ((Test-Path -LiteralPath $isExe) -and (Get-Item -LiteralPath $isExe).Length -gt 1MB) { $dlOk = $true; break }
            } catch {
                Note ('  该源失败：' + $_.Exception.Message)
            }
        }
        if (-not $dlOk) {
            $iscc = $null
            Warn 'Inno Setup 安装包下载失败，跳过安装器编译'
        } else {
            $p = Start-Process -FilePath $isExe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', ("/DIR=$isDir") -Wait -PassThru
            if ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $iscc)) {
                Ok ('Inno Setup 已安装：' + $isDir)
            } else {
                $iscc = $null
                Warn ('Inno Setup 静默安装失败（exit=' + $p.ExitCode + '），跳过安装器编译')
            }
        }
    }
}
$issFile = Join-Path $root 'src\Setup\Inno\inno-setup.iss'
if ($iscc -and (Test-Path -LiteralPath $iscc) -and (Test-Path -LiteralPath $issFile)) {
    Step '6/6' '编译安装器（Inno Setup，捆绑 Icaros 缩略图组件）'
    & $iscc $issFile
    if ($LASTEXITCODE -eq 0) {
        $outDirInno = Join-Path $root 'src\Setup\Inno\Output'
        $hit = Get-ChildItem -LiteralPath $outDirInno -Filter 'mpv.net-v*-setup-x64.exe' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) {
            $setupPath = Join-Path $distRoot $hit.Name
            Copy-Item -LiteralPath $hit.FullName -Destination $setupPath -Force
            Ok ((Split-Path -Leaf $setupPath) + '  ' + [math]::Round($hit.Length / 1MB, 1) + ' MB（已放入 dist）')
        } else {
            Warn 'ISCC 编译成功但没找到 setup 产物'
        }
    } else {
        Warn ('Inno Setup 编译失败（exit=' + $LASTEXITCODE + '），zip/portable 产物不受影响')
    }
} else {
    Write-Host ''
    Write-Host '[6/6] 编译安装器：跳过' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $issFile)) {
        Warn '缺少 src\Setup\Inno\inno-setup.iss'
    } else {
        Warn '未找到 Inno Setup（ISCC.exe）——不出 setup.exe，只出便携 zip'
        Note '已装却没找到？可能是装在非标准路径，可用参数显式指定：build.cmd -InnoSetup "D:\Inno6\ISCC.exe"'
        Note '没装的话：装 Inno Setup https://jrsoftware.org/isinfo.php 后重跑（6/7 版都支持）'
    }
}

Write-Host ''
Write-Host '构建完成' -ForegroundColor Green
Write-Host ("  目录：" + $outDir) -ForegroundColor Green
Write-Host ("  压缩包：" + $zipPath) -ForegroundColor Green
if ($setupPath) {
    Write-Host ("  安装器：" + $setupPath + "（安装时自动捆绑 Icaros，索尼 4:2:2 素材缩略图开箱即用）") -ForegroundColor Green
}
Write-Host '  运行：双击 dist 目录里的 mpvnet.exe（单文件版，需 .NET Desktop Runtime 10.0）' -ForegroundColor DarkGray
try { Stop-Transcript | Out-Null } catch { }
