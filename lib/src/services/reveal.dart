import 'dart:io';

/// 在系统文件管理器中打开目录。导出完成后让用户一键抵达产物。
class Reveal {
  const Reveal._();

  /// 用系统默认浏览器打开链接
  static Future<bool> url(String url) async {
    try {
      if (Platform.isMacOS) {
        return (await Process.run('open', [url])).exitCode == 0;
      }
      if (Platform.isWindows) {
        // start 是 cmd 内建命令，必须经 cmd 执行；
        // 空字符串占位是 start 的标题参数，省略会把 URL 当标题吃掉
        await Process.run('cmd', ['/c', 'start', '', url]);
        return true;
      }
      return (await Process.run('xdg-open', [url])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> directory(String path) async {
    try {
      final ProcessResult r;
      if (Platform.isMacOS) {
        r = await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        r = await Process.run('explorer', [path]);
        // explorer 即使成功也常返回非 0，单独放行
        return true;
      } else {
        r = await Process.run('xdg-open', [path]);
      }
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
