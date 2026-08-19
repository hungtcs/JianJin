# 打包的是 flutter build linux 的预编译产物，不在 rpmbuild 里编译源码
# （Flutter SDK 不在 Fedora 仓库中，无法作为 BuildRequires）。
%global debug_package %{nil}
%global __brp_strip %{nil}
%global __brp_strip_static_archive %{nil}
%global __brp_check_rpaths %{nil}
%define _build_id_links none

# 私有 lib 目录里的 .so 不应对外提供 Provides，否则会污染系统依赖解析
%global __provides_exclude_from ^%{_libdir}/jianjin/.*$
# 同理，它们之间的相互依赖也不该变成对系统包的 Requires
%global __requires_exclude_from ^%{_libdir}/jianjin/.*$

Name:           jianjin
Version:        %{version}
Release:        1%{?dist}
Summary:        Quickly pick useful segments from a video and export them losslessly
Summary(zh_CN): 快速挑选视频中有用的片段并无损导出

License:        MIT
URL:            https://github.com/hungtcs/JianJin
Source0:        %{name}-%{version}.tar.gz

ExclusiveArch:  x86_64 aarch64

BuildRequires:  desktop-file-utils

# 播放依赖 libmpv。这里按 soname 而非包名声明：Fedora 主仓与 RPM Fusion
# 都可能提供它（mpv-libs），按包名写会在其中一种情况下解析失败。
Requires:       libmpv.so.2()(64bit)
# 切割与分析依赖 ffmpeg 可执行文件。按路径声明可同时被 ffmpeg 与
# ffmpeg-free 满足，不强制用户启用 RPM Fusion。
Requires:       /usr/bin/ffmpeg
Requires:       gtk3
Requires:       glib2
Requires:       gdk-pixbuf2

%description
JianJin (剪金) is a tool for triaging video: scan fast, mark the useful
segments with the keyboard, and export them with ffmpeg stream copy so
there is no re-encoding and no quality loss.

Playback is backed by libmpv, so it plays whatever ffmpeg can decode.

%description -l zh_CN
剪金用于从视频中快速挑选出有用的片段。为「比实时更快地扫描」而设计，
键盘打点，用 ffmpeg 流复制无损导出。播放基于 libmpv，ffmpeg 能解的都能播。

%prep
%setup -q

%install
rm -rf %{buildroot}

# 应用本体（含 Flutter 引擎与插件 .so）放进私有 libdir
install -d %{buildroot}%{_libdir}/%{name}
cp -a bundle/. %{buildroot}%{_libdir}/%{name}/
chmod 0755 %{buildroot}%{_libdir}/%{name}/%{name}

# 可执行文件靠 /proc/self/exe 定位同级的 lib/ 与 data/，
# 符号链接会被解析到真实路径，所以这样是安全的
install -d %{buildroot}%{_bindir}
ln -sf %{_libdir}/%{name}/%{name} %{buildroot}%{_bindir}/%{name}

install -Dm0644 %{name}.desktop %{buildroot}%{_datadir}/applications/%{name}.desktop
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

for size in 16 24 32 48 64 128 256 512; do
  install -Dm0644 icons/${size}x${size}/%{name}.png \
    %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/%{name}.png
done

%files
%{_libdir}/%{name}/
%{_bindir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Wed Aug 19 2026 hungtcs <tayoji.io@gmail.com> - 0.1.0-1
- 首个版本
