import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/network/dio_client.dart';
import 'core/network/network_status.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/tab_refresh_bus.dart';
import 'providers/theme_provider.dart';
import 'services/push_notification_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort -- no-ops until Firebase is configured for this app (see
  // push_notification_service.dart), never blocks/breaks app startup.
  await PushNotificationService.instance.init();

  // Initialize the local notification channel before any OrdersScreen poll
  // can fire. Android 13+ permission is requested here rather than racing
  // against MainShell's first frame.
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();

  final authProvider = AuthProvider();
  final themeProvider = ThemeProvider();
  await themeProvider.load();

  DioClient.instance.onUnauthorized = authProvider.forceLogout;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => CatalogProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => TabRefreshBus()),
        ChangeNotifierProvider.value(value: NetworkStatus.instance),
      ],
      child: const _AppBootstrapper(),
    ),
  );
}

class _AppBootstrapper extends StatefulWidget {
  const _AppBootstrapper();

  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper>
    with WidgetsBindingObserver {
  late final AuthProvider _authProvider;

  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _authProvider = context.read<AuthProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authProvider.restoreSession();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded =
        _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground =
        state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground) {
      _authProvider.checkSessionOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const FastNFreshApp();
  }
}