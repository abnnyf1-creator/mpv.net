
; mpv.net 安装器脚本（Inno Setup 6）
; 基于官方脚本修改：捆绑安装 Icaros 缩略图组件
; Icaros v3.3.6 (https://github.com/Xanashi/Icaros) 让 Windows 资源管理器
; 能为 4:2:2 10bit H.264 视频（如索尼相机 XAVC S HD 422 素材）显示画面缩略图
;
; 编译方法见同目录 README-编译说明.txt

#define MyAppName "mpv.net"
#define MyAppExeName "mpvnet.exe"
; 取构建流程组装好的 dist 便携版（含 mpvnet.exe + libmpv-2.dll + MediaInfo.dll + mpvnet.com）
; 注意：需先运行构建（build.cmd），产出 dist\mpv.net-vX.X.X-portable-x64 后再编译本安装器
#define MyAppSourceDir "..\..\..\dist\mpv.net-v7.1.2.0-portable-x64"
#define MyAppVersion GetFileVersion("..\..\..\dist\mpv.net-v7.1.2.0-portable-x64\mpvnet.exe")

; Icaros 捆绑配置
#define IcarosInstaller "Icaros_v3.3.6.exe"
#define IcarosVersion "3.3.6"

; .NET Desktop Runtime 捆绑配置（mpv.net 单文件版运行必需）
; 目标机器已装 10.x 时自动跳过安装
#define RuntimeInstaller "windowsdesktop-runtime-10.0.15-win-x64.exe"

[Setup]
AppId={{9AA2B100-BEF3-44D0-B819-D8FC3C4D557D}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Frank Skare (stax76)
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
DefaultDirName={autopf}\{#MyAppName}
OutputBaseFilename=mpv.net-v{#MyAppVersion}-setup-x64
OutputDir=Output
DefaultGroupName={#MyAppName}
SetupIconFile=..\..\MpvNet.Windows\mpv-icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
; 只定义一种语言 → 安装器全程中文，且不弹语言选择框
; （若编译时报错找不到该文件，需在 Inno Setup 安装时勾选语言包，见 README）
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
; 附加组件页：默认勾选安装 Icaros
; Check: IsAdmin() —— 若用户在安装器里选择了"仅为我安装"（非提升权限），
; Icaros 需要系统级安装，此时自动隐藏该选项
Name: "icaros"; \
    Description: "安装 Icaros 缩略图组件 v{#IcarosVersion}（推荐：让 4:2:2 10bit 视频（如索尼相机素材）在资源管理器显示画面缩略图）"; \
    GroupDescription: "附加组件："; \
    Check: IsAdmin()

; .NET Desktop Runtime：目标机器没有 10.x 时才显示并勾选
Name: "dotnetruntime"; \
    Description: "安装 .NET Desktop Runtime 10.0（mpv.net 运行必需；已装会自动跳过）"; \
    GroupDescription: "附加组件："; \
    Check: DotNetDesktopMissing() and IsAdmin()

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Files]
Source: "{#MyAppSourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,win-x64,win-arm64"; Flags: ignoreversion recursesubdirs createallsubdirs;
; Icaros 安装器捆绑到临时目录，安装完成后自动删除，不留在目标机器上
Source: "{#IcarosInstaller}"; DestDir: "{tmp}"; Flags: deleteafterinstall; Tasks: icaros
; .NET Desktop Runtime 同样捆绑到临时目录，装完即删
Source: "{#RuntimeInstaller}"; DestDir: "{tmp}"; Flags: deleteafterinstall; Tasks: dotnetruntime
; 默认配置模板（装到程序目录，安装完成后按需写入用户配置目录）
Source: "default-mpv.conf"; DestDir: "{app}"; Flags: ignoreversion
Source: "default-mpvnet.conf"; DestDir: "{app}"; Flags: ignoreversion
; ModernZ 控制栏三件套（装到程序目录，安装完成后按需部署到用户配置目录）
; 本机没装 ModernZ 会导致 osc=no 后没有任何控制栏，所以必须随安装器分发
Source: "ModernZ\modernz.lua"; DestDir: "{app}\ModernZ"; Flags: ignoreversion
Source: "ModernZ\modernz-icons.ttf"; DestDir: "{app}\ModernZ"; Flags: ignoreversion
Source: "ModernZ\modernz.conf"; DestDir: "{app}\ModernZ"; Flags: ignoreversion

[Run]
; Icaros 3.3.6 实为 Inno Setup 打包（不是 NSIS），/S 无效！
; 必须用 Inno 静默参数：全程无界面，不弹语言选择框，不弹 UAC
; （因为 mpv.net 安装器本身已以管理员权限运行）
Filename: "{tmp}\{#IcarosInstaller}"; Parameters: "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART"; Tasks: icaros; Flags: waituntilterminated
; .NET Desktop Runtime 官方静默参数：/install /quiet /norestart
Filename: "{tmp}\{#RuntimeInstaller}"; Parameters: "/install /quiet /norestart"; Tasks: dotnetruntime; Flags: waituntilterminated

[Code]
var
  RefreshResultCode: Integer;

// 检测目标机器是否已安装 .NET Desktop Runtime 10.x
// 方法：查 %ProgramFiles%\dotnet\shared\Microsoft.WindowsDesktop.App 下的版本目录
function DotNetDesktopMissing(): Boolean;
var
  SearchRec: TFindRec;
  DesktopDir: string;
begin
  Result := True;
  DesktopDir := ExpandConstant('{pf}\dotnet\shared\Microsoft.WindowsDesktop.App');
  if FindFirst(DesktopDir + '\*', SearchRec) then
  begin
    repeat
      if (SearchRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') then
          if Pos('10.', SearchRec.Name) = 1 then
            Result := False;
    until not FindNext(SearchRec);
    FindClose(SearchRec);
  end;
end;

// Icaros 3.3.6 的 COM 类标识（缩略图提供程序 / 属性处理程序）
// 注意：Inno 的 Pascal 脚本不支持过程内 const 段和嵌套过程，常量必须放全局
const
  ClsidThumb = '{c5aec3ec-e812-4677-a9a7-4fee1f9aa000}';
  ClsidProp  = '{0C08E3BB-D10B-4CC9-B1B3-701F5BE9D6EC}';

// 手工补全 Icaros COM 注册
// 背景：Icaros 3.3.6 的安装器依赖 DLL 自注册写入 InprocServer32，
// 但 /VERYSILENT 静默安装时该步骤不生效 —— 只留下空壳 CLSID 键，
// Explorer/COM 代理无从加载 DLL，缩略图整体失效（甚至引发 DllHost 崩溃）。
// 这里按自注册的等效内容直接写注册表（64 位与 32 位两个视图）。
procedure RegisterIcarosDlls();
var
  Base64, Base32, Dll64, Dll32, Clsid: string;
  Name: string;
begin
  if not FileExists(ExpandConstant('{pf}\Icaros\64-bit\IcarosThumbnailProvider.dll')) then
    exit;
  Base64 := 'SOFTWARE\Classes\CLSID';
  Base32 := 'SOFTWARE\WOW6432Node\Classes\CLSID';
  Dll64 := ExpandConstant('{pf}\Icaros\64-bit\');
  Dll32 := ExpandConstant('{pf32}\Icaros\32-bit\');

  // 第 1 个类：缩略图提供程序
  Name := 'Icaros Thumbnail Provider';
  Clsid := ClsidThumb;
  RegWriteStringValue(HKLM, Base64 + '\' + Clsid, '', Name);
  RegWriteStringValue(HKLM, Base64 + '\' + Clsid + '\InprocServer32', '', Dll64 + 'IcarosThumbnailProvider.dll');
  RegWriteStringValue(HKLM, Base64 + '\' + Clsid + '\InprocServer32', 'ThreadingModel', 'Apartment');
  RegWriteStringValue(HKLM, Base32 + '\' + Clsid, '', Name);
  RegWriteStringValue(HKLM, Base32 + '\' + Clsid + '\InprocServer32', '', Dll32 + 'IcarosThumbnailProvider.dll');
  RegWriteStringValue(HKLM, Base32 + '\' + Clsid + '\InprocServer32', 'ThreadingModel', 'Apartment');

  // 第 2 个类：属性处理程序
  Name := 'Icaros Property Handler';
  Clsid := ClsidProp;
  RegWriteStringValue(HKLM, Base64 + '\' + Clsid, '', Name);
  RegWriteStringValue(HKLM, Base64 + '\' + Clsid + '\InprocServer32', '', Dll64 + 'IcarosPropertyHandler.dll');
  RegWriteStringValue(HKLM, Base64 + '\' + Clsid + '\InprocServer32', 'ThreadingModel', 'Apartment');
  RegWriteStringValue(HKLM, Base32 + '\' + Clsid, '', Name);
  RegWriteStringValue(HKLM, Base32 + '\' + Clsid + '\InprocServer32', '', Dll32 + 'IcarosPropertyHandler.dll');
  RegWriteStringValue(HKLM, Base32 + '\' + Clsid + '\InprocServer32', 'ThreadingModel', 'Apartment');
end;

// 让 Icaros 接管 .mp4 的缩略图
// 背景：Icaros 3.3.6 默认激活 .mkv/.webm/.flv 等类型，但 .mp4 的缩略图处理
// 程序被 Windows 旧版 {9DBD2C50-...}（只支持 4:2:0）占着，Icaros 不会自动
// 接管 → 索尼 4:2:2 10bit 素材（XAVC S HD）仍无缩略图。
// 这里镜像 IcarosConfig 接管 .mkv 时的写法：备份旧处理程序 → 改指向 → 置激活位。
procedure ActivateIcarosForMp4();
var
  ShellExKey, OldHandler, CurList: string;
begin
  // 仅当 Icaros 实际安装成功后才执行
  if not FileExists(ExpandConstant('{pf}\Icaros\64-bit\IcarosThumbnailProvider.dll')) and
     not FileExists(ExpandConstant('{pf32}\Icaros\64-bit\IcarosThumbnailProvider.dll')) then
    exit;

  // 备份 .mp4 原缩略图处理程序（Icaros 卸载时按 ThumbBackup 恢复）
  ShellExKey := 'SOFTWARE\Classes\.mp4\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}';
  if RegQueryStringValue(HKLM, ShellExKey, '', OldHandler) and
     (OldHandler <> '') and (UpperCase(OldHandler) <> ClsidThumb) then
  begin
    RegWriteStringValue(HKLM, 'SOFTWARE\Icaros\ThumbBackup', 'IThumb.mp4', OldHandler);
    RegWriteStringValue(HKLM, 'SOFTWARE\Icaros\ThumbBackup', 'IExtract.mp4', OldHandler);
  end;

  // 缩略图/图像提取处理程序 → Icaros
  RegWriteStringValue(HKLM, ShellExKey, '', ClsidThumb);
  RegWriteStringValue(HKLM, 'SOFTWARE\Classes\.mp4\ShellEx\{BB2E617C-0920-11d1-9A0B-00C04FC2D6C1}',
                      '', ClsidThumb);
  // Icaros 激活表：.mp4 置 1
  RegWriteDWordValue(HKLM, 'SOFTWARE\Icaros\Properties', '.mp4', 1);

  // Icaros 总开关"Thumbnail Extensions"里没有 .mp4 —— Icaros 运行时读这份
  // 分号分隔的清单决定是否处理，缺了就整个不生效
  if RegQueryStringValue(HKLM, 'SOFTWARE\Icaros', 'Thumbnail Extensions', CurList) then
    if Pos(';.mp4;', ';' + LowerCase(CurList) + ';') = 0 then
      RegWriteStringValue(HKLM, 'SOFTWARE\Icaros', 'Thumbnail Extensions',
                          CurList + ';.mp4');

  // 注册进 Explorer"已批准扩展"列表
  RegWriteStringValue(HKLM,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved',
    ClsidThumb, 'Icaros Thumbnail Provider');
  RegWriteStringValue(HKLM,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved',
    '{0C08E3BB-D10B-4CC9-B1B3-701F5BE9D6EC}', 'Icaros Property Handler');
end;

// 安装完成后刷新 Windows 图标缓存，让视频缩略图立即生效
procedure CurStepChanged(CurStep: TSetupStep);
var
  UserConfDir, UserConfFile, UserAppConfFile, ModernZSrc: string;
begin
  if CurStep = ssPostInstall then
  begin
    RegisterIcarosDlls();
    ActivateIcarosForMp4();

    UserConfDir := ExpandConstant('{userappdata}\mpv.net');
    UserConfFile := UserConfDir + '\mpv.conf';

    if not DirExists(UserConfDir) then
      ForceDirectories(UserConfDir);

    // 默认播放配置：仅全新安装（无 mpv.conf）时写入，老用户配置一律不覆盖
    if not FileExists(UserConfFile) then
      FileCopy(ExpandConstant('{app}\default-mpv.conf'), UserConfFile, False);

    // mpv.net 配置：开启 auto-load-folder 同目录连播（仅全新安装时写入）
    UserAppConfFile := UserConfDir + '\mpvnet.conf';
    if not FileExists(UserAppConfFile) then
      FileCopy(ExpandConstant('{app}\default-mpvnet.conf'), UserAppConfFile, False);

    // ModernZ 控制栏始终部署（已存在的文件不覆盖，保护用户自定义）：
    // 默认配置 osc=no 关掉了内置控制栏，若没有 ModernZ 脚本接管，
    // 新机器（尤其 Win10）就完全没有控制栏，表现为"呼不出来"。
    // 即使老用户已有自己的 mpv.conf，只要里面是 osc=no 就需要这份脚本。
    ModernZSrc := ExpandConstant('{app}\ModernZ');
    if not DirExists(UserConfDir + '\scripts') then
      ForceDirectories(UserConfDir + '\scripts');
    if not DirExists(UserConfDir + '\fonts') then
      ForceDirectories(UserConfDir + '\fonts');
    if not DirExists(UserConfDir + '\script-opts') then
      ForceDirectories(UserConfDir + '\script-opts');
    if not FileExists(UserConfDir + '\scripts\modernz.lua') then
      FileCopy(ModernZSrc + '\modernz.lua', UserConfDir + '\scripts\modernz.lua', False);
    if not FileExists(UserConfDir + '\fonts\modernz-icons.ttf') then
      FileCopy(ModernZSrc + '\modernz-icons.ttf', UserConfDir + '\fonts\modernz-icons.ttf', False);
    if not FileExists(UserConfDir + '\script-opts\modernz.conf') then
      FileCopy(ModernZSrc + '\modernz.conf', UserConfDir + '\script-opts\modernz.conf', False);

    // Win10/11 用 -show 参数；失败则尝试老系统的 -ClearIconCache
    if not Exec(ExpandConstant('{sys}\ie4uinit.exe'), '-show',
                '', SW_HIDE, ewWaitUntilTerminated, RefreshResultCode) then
      Exec(ExpandConstant('{sys}\ie4uinit.exe'), '-ClearIconCache',
           '', SW_HIDE, ewWaitUntilTerminated, RefreshResultCode);
  end;
end;

// 卸载 mpv.net 时询问是否连同卸载 Icaros（不强制——
// 用户可能希望保留系统缩略图功能）
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  UninstallResultCode: Integer;
  IcarosUninstaller: string;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Icaros 3.3.6 为 Inno Setup 打包，卸载器是 unins000.exe
    // 64 位装 Program Files\Icaros，32 位装 Program Files (x86)\Icaros
    IcarosUninstaller := ExpandConstant('{pf}\Icaros\unins000.exe');
    if not FileExists(IcarosUninstaller) then
      IcarosUninstaller := ExpandConstant('{pf32}\Icaros\unins000.exe');
    // 兜底：旧版 NSIS 安装器的卸载器名为 un.exe
    if not FileExists(IcarosUninstaller) then
      IcarosUninstaller := ExpandConstant('{pf}\Icaros\un.exe');
    if not FileExists(IcarosUninstaller) then
      IcarosUninstaller := ExpandConstant('{pf32}\Icaros\un.exe');

    if FileExists(IcarosUninstaller) then
    begin
      if MsgBox('是否同时卸载 Icaros 缩略图组件？' #13#10
                '（卸载后 4:2:2 10bit 视频（如索尼素材）将不再显示缩略图）',
                mbConfirmation, MB_YESNO) = IDYES then
        Exec(IcarosUninstaller, '', '', SW_SHOW, ewWaitUntilTerminated, UninstallResultCode);
    end;
  end;
end;
