import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/network/dio_client.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/connectivity_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final authProvider = AuthProvider();
  // Wire the Dio 401 interceptor to force a logout when the session becomes invalid.
  DioClient.instance.onUnauthorized = authProvider.forceLogout;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => CatalogProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: const _AppBootstrapper(),
    ),
  );
}

/// Kicks off session restoration ("remember session") once, then hands off
/// to the themed app widget.
class _AppBootstrapper extends StatefulWidget {
  const _AppBootstrapper();

  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) => const FastNFreshApp();
}
