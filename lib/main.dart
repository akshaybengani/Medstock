import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'providers/app_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'theme/theme_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Reminders are local-only; a failure here must never block app start.
  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Medstock: notification init failed — $e');
  }

  runApp(const MedstockApp());
}

class MedstockApp extends StatelessWidget {
  const MedstockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      // Only the MaterialApp rebuilds when the theme changes.
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: K.appName,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeProvider.mode,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
