import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'src/settings.dart';
import 'src/ui/shell.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 libmpv
  MediaKit.ensureInitialized();
  // 设置必须在建界面之前读好：缩略图/波形开关决定打开文件后要不要起分析进程
  final settings = await AppSettings.load();
  runApp(JianJinApp(settings: settings));
}

class JianJinApp extends StatelessWidget {
  const JianJinApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    // 用 WidgetsApp 而非 MaterialApp：整个应用不引入 Material 控件库
    return WidgetsApp(
      title: '剪金',
      color: AppColors.bg,
      debugShowCheckedModeBanner: false,
      // 参数名刻意用 routeSettings，避免遮蔽上面的 settings 字段
      pageRouteBuilder: <T>(RouteSettings routeSettings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: routeSettings,
          pageBuilder: (context, _, __) => builder(context),
        );
      },
      home: DefaultTextStyle(
        style: AppText.base,
        child: AppShell(settings: settings),
      ),
    );
  }
}
