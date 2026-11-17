<#
.SYNOPSIS
    mpv.net 构建依赖一键安装脚本

.DESCRIPTION
    为本项目的构建准备环境。项目目标框架：
      - net10.0              (MpvNet / libmpvnet)
      - net10.0-windows7.0   (MpvNet.Windows / NGettext.Wpf)

    需要的构建依赖只有两类：
      1) .NET 10 SDK —— 自带 MSBuild 与 NuGet，命令行构建 WPF/WinForms
         无需安装 Visual Studio；
      2) NuGet 包 —— CommunityToolkit.Mvvm、NGettext、Microsoft.Xaml.Behaviors.Wpf，
         由 dotnet restore 自动联网下载，无需单独安装。

    本脚本只做两件事：
      1) 检测 .NET 10 SDK；缺失时用官方 dotnet-install.ps1 静默安装到用户目录
         （无需管理员权限、不弹 UAC、不改动系统 PATH）；
      2) 将安装目录临时加入当前进程 PATH。

    注意：本脚本【不执行】dotnet restore / build / publish，不会在 MyCode
    项目目录写入任何文件，也不产生任何编译输出。NuGet 包在真正构建时
    由 dotnet build 自动下载到用户目录的全局缓存（%USERPROFILE%\.nuget\packages）。

    运行时依赖（libmpv-2.dll、MediaInfo.dll、mpvnet.com）仅在打包发布/运行
    阶段需要，不属于构建依赖，不在本脚本范围。可参考：
    .github/__workflows__ currently flawed/build.yml 中的下载步骤。

.EXAMPLE
    双击 install-build-deps.bat
    或： powershell -ExecutionPolicy Bypass -File install-build-deps.ps1
#>

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'

function Log {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host "[mpv.net] $Message" -ForegroundColor $Color
}

function Find-Sdk10 {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $dotnet) { return $null }
    $sdks = & dotnet --list-sdks 2>$null
    $hit = $sdks | Where-Object { $_ -match '^10\.' } | Select-Object -First 1
    return $hit
}

Write-Host '==============================================' -ForegroundColor DarkCyan
Write-Host ' mpv.net 构建依赖一键安装' -ForegroundColor DarkCyan
Write-Host '==============================================' -ForegroundColor DarkCyan

# --- 1. SDK 检测与安装 ---
$env:Path = "$InstallDir;$env:Path"   # 优先使用用户级安装目录

$sdk = Find-Sdk10
if ($null -eq $sdk) {
    Log '未检测到 .NET 10 SDK，开始通过官方脚本安装...' 'Yellow'
    $installer = Join-Path $env:TEMP 'dotnet-install-mpvnet.ps1'
    try {
        Log '下载 dotnet-install.ps1 ...'
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer -UseBasicParsing
        Log "安装 .NET 10 SDK 到：$InstallDir"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Channel 10.0 -InstallDir $InstallDir
        if ($LASTEXITCODE -ne 0 -and $null -eq (Find-Sdk10)) {
            throw 'dotnet-install 返回错误，且未检测到 SDK。'
        }
    } catch {
        Log "自动安装失败：$($_.Exception.Message)" 'Red'
        Log '请手动安装 .NET 10 SDK：https://dotnet.microsoft.com/download/dotnet/10.0' 'Yellow'
        throw
    }
    $sdk = Find-Sdk10
}

if ($null -eq $sdk) {
    throw '安装后仍未检测到 .NET 10 SDK，请重启终端后重试，或手动安装。'
}
Log "已检测到 SDK：$sdk" 'Green'

# --- 2. 完成说明（不触碰项目目录）---
# NuGet 包的下载发生在真正 dotnet build 时，缓存默认在 %USERPROFILE%\.nuget\packages
# （用户目录，不在 MyCode）。本脚本不运行 restore，因此不会在 src\*\obj\ 下
# 生成 project.assets.json 等任何中间文件，对项目目录零写入。
$nugetCache = Join-Path $env:USERPROFILE '.nuget\packages'
Log "NuGet 缓存位置（构建时自动下载到这里，不在 MyCode）：$nugetCache" 'DarkGray'

Write-Host ''
Log '构建环境安装完成！' 'Green'
Log '本脚本未在项目目录写入任何文件，也未构建/还原。' 'Green'
Log '构建时 NuGet 包会自动下载；源码 obj/bin 产物由构建命令产生。' 'Yellow'
