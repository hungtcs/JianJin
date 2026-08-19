/// 应用元信息。
///
/// 版本号**不在这里**：它由 pubspec.yaml 定义、经 Flutter 注入各平台 bundle，
/// 运行时用 package_info_plus 读取。硬编码一份常量迟早会忘记同步。
class AppInfo {
  const AppInfo._();

  static const name = '剪金';
  static const latinName = 'JianJin';
  static const tagline = '快速挑选视频中有用的片段，无损导出';
  static const repository = 'https://github.com/hungtcs/JianJin';
}
