import 'package:flutter/material.dart';
import 'api_service.dart';

class LoginScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usuarioCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _cargando = false;
  bool _ocultarPassword = true;

  Future<void> _iniciarSesion() async {
    final usuarioTxt = _usuarioCtrl.text.trim();
    final passwordTxt = _passwordCtrl.text.trim();

    if (usuarioTxt.isEmpty || passwordTxt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ingrese usuario y contraseña.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      // 🎯 Conexión a la tabla 'rutina_ol.rutina_usuario'
      final usuariosBD = await ApiService.consultar('rutina_ol', 'rutina_usuario');

      final usuarioEncontrado = usuariosBD.firstWhere(
            (u) {
          if (u is! Map) return false;
          String userBD = u['usuario']?.toString().trim().toLowerCase() ?? '';
          String passBD = u['contrasena']?.toString().trim() ?? u['contraseña']?.toString().trim() ?? '';

          return userBD == usuarioTxt.toLowerCase() && passBD == passwordTxt;
        },
        orElse: () => null,
      );

      if (usuarioEncontrado != null) {
        widget.onLoginSuccess(Map<String, dynamic>.from(usuarioEncontrado));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Usuario o contraseña incorrectos.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al conectar con el servidor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // 🔑 MODAL PARA CAMBIAR CONTRASEÑA
  void _abrirModalCambiarPassword() {
    final TextEditingController userCambioCtrl = TextEditingController(text: _usuarioCtrl.text.trim());
    final TextEditingController passActualCtrl = TextEditingController();
    final TextEditingController passNuevaCtrl = TextEditingController();
    final TextEditingController passConfirmCtrl = TextEditingController();

    bool guardando = false;
    bool ocultarP1 = true;
    bool ocultarP2 = true;
    bool ocultarP3 = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.key_rounded, color: Color(0xFF0D47A1), size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Cambiar Contraseña',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Campo Usuario / Cédula
                      const Text('Usuario / Cédula *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: userCambioCtrl,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Ej. 1078349495',
                          prefixIcon: const Icon(Icons.person_outline, size: 16, color: Color(0xFF0D47A1)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Contraseña Actual
                      const Text('Contraseña Actual *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: passActualCtrl,
                        obscureText: ocultarP1,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_clock_outlined, size: 16, color: Color(0xFF0D47A1)),
                          suffixIcon: IconButton(
                            icon: Icon(ocultarP1 ? Icons.visibility_off : Icons.visibility, size: 16, color: Colors.grey),
                            onPressed: () => setModalState(() => ocultarP1 = !ocultarP1),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Nueva Contraseña
                      const Text('Nueva Contraseña *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: passNuevaCtrl,
                        obscureText: ocultarP2,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Nueva clave',
                          prefixIcon: const Icon(Icons.lock_outline, size: 16, color: Color(0xFF0D47A1)),
                          suffixIcon: IconButton(
                            icon: Icon(ocultarP2 ? Icons.visibility_off : Icons.visibility, size: 16, color: Colors.grey),
                            onPressed: () => setModalState(() => ocultarP2 = !ocultarP2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Confirmar Nueva Contraseña
                      const Text('Confirmar Nueva Contraseña *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: passConfirmCtrl,
                        obscureText: ocultarP3,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Repita la nueva clave',
                          prefixIcon: const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF0D47A1)),
                          suffixIcon: IconButton(
                            icon: Icon(ocultarP3 ? Icons.visibility_off : Icons.visibility, size: 16, color: Colors.grey),
                            onPressed: () => setModalState(() => ocultarP3 = !ocultarP3),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Botones de acción
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: guardando ? null : () => Navigator.pop(dialogContext),
                            child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: guardando
                                ? null
                                : () async {
                              final userTxt = userCambioCtrl.text.trim();
                              final pAct = passActualCtrl.text.trim();
                              final pNueva = passNuevaCtrl.text.trim();
                              final pConf = passConfirmCtrl.text.trim();

                              if (userTxt.isEmpty || pAct.isEmpty || pNueva.isEmpty || pConf.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('⚠️ Llene todos los campos.'), backgroundColor: Colors.orange),
                                );
                                return;
                              }

                              if (pNueva != pConf) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('⚠️ Las nuevas contraseñas no coinciden.'), backgroundColor: Colors.orange),
                                );
                                return;
                              }

                              setModalState(() => guardando = true);

                              try {
                                final usuariosBD = await ApiService.consultar('rutina_ol', 'rutina_usuario');

                                final uEncontrado = usuariosBD.firstWhere(
                                      (u) {
                                    if (u is! Map) return false;
                                    String userBD = u['usuario']?.toString().trim().toLowerCase() ?? '';
                                    String passBD = u['contrasena']?.toString().trim() ?? u['contraseña']?.toString().trim() ?? '';
                                    return userBD == userTxt.toLowerCase() && passBD == pAct;
                                  },
                                  orElse: () => null,
                                );

                                if (uEncontrado == null) {
                                  setModalState(() => guardando = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('❌ Usuario o contraseña actual incorrectos.'), backgroundColor: Colors.red),
                                  );
                                  return;
                                }

                                final idUsuario = uEncontrado['id']?.toString();

                                await ApiService.actualizar('rutina_ol', 'rutina_usuario', 'id', idUsuario, {
                                  'contrasena': pNueva,
                                });

                                if (mounted) {
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('✅ Contraseña actualizada con éxito.'), backgroundColor: Colors.green),
                                  );
                                  _usuarioCtrl.text = userTxt;
                                  _passwordCtrl.text = pNueva;
                                }
                              } catch (e) {
                                setModalState(() => guardando = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('❌ Error al actualizar: $e'), backgroundColor: Colors.red),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D47A1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: guardando
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Actualizar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F2FD),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_person_rounded,
                    size: 48,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ACCIONES OL',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0D47A1),
                    letterSpacing: 1,
                  ),
                ),
                const Text(
                  'Gestión Logística y Supply Chain',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 28),

                // CAMPO USUARIO / CÉDULA
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Usuario / Cédula', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _usuarioCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_outline, size: 18, color: Color(0xFF0D47A1)),
                        hintText: 'Ej. 1078349495',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // CAMPO CONTRASEÑA
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Contraseña', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _ocultarPassword,
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _iniciarSesion(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF0D47A1)),
                        suffixIcon: IconButton(
                          icon: Icon(_ocultarPassword ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.grey),
                          onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                        ),
                        hintText: '••••••••',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 🔑 BOTÓN CAMBIAR CONTRASEÑA
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: _abrirModalCambiarPassword,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Text(
                        '🔑 ¿Deseas cambiar tu contraseña?',
                        style: TextStyle(fontSize: 11, color: Color(0xFF0D47A1), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // BOTÓN INICIAR SESIÓN
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _cargando ? null : _iniciarSesion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _cargando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('INICIAR SESIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}