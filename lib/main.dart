import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/auth/data/datasources/biometric_datasource.dart';
import 'features/auth/domain/usecases/authenticate_user.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/pages/login_page.dart';

void main() {
  runApp(const FitnessApp());
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Inyección de dependencias manual (por ahora)
    final biometricDataSource = BiometricDataSourceImpl();
    final authenticateUser = AuthenticateUser(biometricDataSource);

    return MaterialApp(
      title: 'Fitness Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Aplicamos la tipografía Nunito globalmente según SKILL.md
        fontFamily: 'Nunito',
      ),
      home: BlocProvider(
        create: (_) => AuthBloc(authenticateUser),
        child: LoginPage(
          onAuthSuccess: () {
            print('Autenticación exitosa - ¡Módulo 1 Completado!');
          },
        ),
      ),
    );
  }
}
