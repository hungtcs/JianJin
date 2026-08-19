import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'src/ui/shell.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 libmpv
  MediaKit.ensureInitialized();
  runApp(const JianJinApp());
}

class JianJinApp extends StatelessWidget {
  const JianJinApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 用 WidgetsApp 而非 MaterialApp：整个应用不引入 Material 控件库
    return WidgetsApp(
      title: '剪金',
      color: AppColors.bg,
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, __) => builder(context),
        );
      },
      home: const DefaultTextStyle(
        style: AppText.base,
        child: AppShell(),
      ),
    );
  }
}
