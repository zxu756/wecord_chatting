import 'package:flutter/widgets.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runWeCordApp();
}
