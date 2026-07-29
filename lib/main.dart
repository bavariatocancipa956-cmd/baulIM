import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'main_layout_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Map<String, dynamic>? _usuarioLogueado;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BAÚL DE ACCIONES - OL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
      ),
      home: _usuarioLogueado == null
          ? LoginScreen(
        onLoginSuccess: (usuario) {
          setState(() {
            _usuarioLogueado = usuario;
          });
        },
      )
          : MainLayoutScreen(
        usuario: _usuarioLogueado!,
        onCerrarSesion: () {
          setState(() {
            _usuarioLogueado = null;
          });
        },
      ),
    );
  }
}