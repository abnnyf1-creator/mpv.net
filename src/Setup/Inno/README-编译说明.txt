mpv.net 安装器编译说明（含 Icaros 捆绑）
==========================================

一、目录内容
-----------
inno-setup.iss    安装器脚本（基于官方脚本修改，捆绑 Icaros）
Icaros_v3.3.6.exe Icaros 官方安装器（从 GitHub Xanashi/Icaros v3.3.6 下载）
                  SHA256: 22e4d58e1c92aa48e11738d29c43fb6cdd80bdbce835f7029a46e91aa04fe8fd

二、为什么捆绑 Icaros
---------------------
Windows 自带的视频缩略图解码器只支持 4:2:0 8bit H.264。
索尼相机（如 A7M4 的 XAVC S HD 422）拍的是 4:2:2 10bit H.264，
Windows 抽不出画面帧，资源管理器只显示通用图标。
Icaros 基于 ffmpeg 解码，能让这类素材正常显示缩略图。
本安装器把 Icaros 一起装上，装完索尼素材立即有缩略图。

三、编译方式（两种）
--------------------------------------------
【方式 A：全自动（推荐）】
直接跑项目根目录的 build.cmd——第 [6/6] 步会自动探测 Inno Setup 6
并编译安装器，setup.exe 自动放进 dist\，随回传逻辑一起回共享。
没装 Inno Setup 时会自动下载 innosetup-6.7.4.exe 并静默装到
%LOCALAPPDATA%\Programs\Inno Setup 6（免管理员、不改系统），然后继续编译；
下载失败才跳过，不影响便携 zip 产出。

【方式 B：手动】
1. 装好 Inno Setup 6 后，双击打开 inno-setup.iss
2. 菜单 Build → Compile（Ctrl+F9）
3. 产物输出在：src/Setup/Inno/Output/mpv.net-v<版本>-setup-x64.exe

前置条件（两种方式相同）：
- 先构建出 dist/mpv.net-v<版本>-portable-x64/（安装器从这里取文件）
- Inno Setup 安装时要包含中文语言包（默认就有）：
  编译时需要 <InnoSetup目录>\Languages\ChineseSimplified.isl，
  缺了的话重跑 Inno Setup 安装程序勾选语言包即可
- src/Setup/Inno/ 下要有三个捆绑文件（本目录已备齐）：
  · Icaros_v3.3.6.exe（12.8MB，缩略图组件）
  · windowsdesktop-runtime-10.0.15-win-x64.exe（60MB，.NET Desktop Runtime）
  · inno-setup.iss

四、安装器行为
--------------
- 安装器界面为简体中文（只定义一种语言，不弹语言选择框）
- 默认勾选安装 Icaros v3.3.6（附加组件页可取消勾选）
- 目标机器没有 .NET Desktop Runtime 10.x 时，附加组件页多出
  "安装 .NET Desktop Runtime"（默认勾选、静默安装）；已装自动隐藏
- Icaros 实为 Inno Setup 打包，用 /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
  静默安装（全程无界面）；Runtime 用 /install /quiet /norestart，均无额外 UAC
- 安装完成后自动刷新 Windows 图标缓存
- 若用户选择"仅为我安装"（非管理员），两个系统级组件自动隐藏
- 卸载 mpv.net 时会询问是否连 Icaros 一起卸载（可拒绝保留）；
  .NET Runtime 和 Icaros 的卸载也可在"设置-应用"单独进行
- 捆绑的安装器本体装完即删，不在目标机器留残留

五、安装器体积
--------------
dist 便携版约 128 MB（大头是 libmpv-2.dll 111.7 MB）
+ Icaros 12.8 MB
lzma2 压缩后最终 setup.exe 约 55-70 MB。

六、注意事项
------------
- 如果想换成 Icaros 4.0.0 Alpha（含 RAW/PDF/SVG 缩略图等新功能）：
  从 https://github.com/Xanashi/Icaros/releases 下载对应 exe，
  替换本目录文件并同步修改 .iss 顶部的 IcarosInstaller/IcarosVersion 两个 #define。
- Icaros v3.3.6 是最新稳定版；v4.0.0a1 虽是 latest 但为 Alpha，故捆绑稳定版。
