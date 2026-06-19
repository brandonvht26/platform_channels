import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/auth/data/datasources/biometric_datasource.dart';
import 'features/auth/domain/usecases/authenticate_user.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/steps/presentation/widgets/step_counter_widget.dart';
import 'features/tracking/presentation/widgets/route_map_widget.dart';

// ============================================================================
// PALETA MARINO CARIBE — seed color
// ============================================================================
const _seedCeleste = Color(0xFF00B4DB);
const _surfaceDark = Color(0xFF006064);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FitnessApp());
}

// ============================================================================
// FitnessApp — raíz de la aplicación con tema global
// ============================================================================
class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Inyección de dependencias manual (transitoria)
    final biometricDataSource = BiometricDataSourceImpl();
    final authenticateUser = AuthenticateUser(biometricDataSource);

    return MaterialApp(
      title: 'Fitness Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedCeleste,
          brightness: Brightness.light,
        ),
        // El scaffold usa un fondo casi blanco con sutil tinte marino
        scaffoldBackgroundColor: const Color(0xFFF5FBFC),
      ),
      home: BlocProvider(
        create: (_) => AuthBloc(authenticateUser),
        child: const AuthWrapper(),
      ),
    );
  }
}

// ============================================================================
// AuthWrapper — controla si mostramos Login o HomePage
// ============================================================================
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isAuthenticated = false;

  void _onAuthSuccess() {
    setState(() => _isAuthenticated = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) return const HomePage();
    return LoginPage(onAuthSuccess: _onAuthSuccess);
  }
}

// ============================================================================
// HomePage — dashboard principal post-autenticación
// ============================================================================
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // ------------------------------------------------------------------
      // AppBar premium: fondo claro, sin borde morado, tipografía limpia
      // ------------------------------------------------------------------
      appBar: AppBar(
        title: const Text(
          'Fitness Tracker',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: _surfaceDark,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _surfaceDark,
        elevation: 0.5,
        shadowColor: _seedCeleste.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),

      // ------------------------------------------------------------------
      // Body: scroll vertical con los widgets de cada módulo
      // ------------------------------------------------------------------
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              colorScheme.primaryContainer.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            children: [
              // Módulo 2 — Contador de pasos (acelerómetro)
              StepCounterWidget(),
              SizedBox(height: 16),
              // Módulo 3 — Ruta GPS
              RouteMapWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
