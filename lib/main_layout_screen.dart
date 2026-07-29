import 'package:flutter/material.dart';
import 'dashboard_ol_screen.dart';
import 'acciones_ol_screen.dart';

class MainLayoutScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onCerrarSesion;

  const MainLayoutScreen({
    super.key,
    required this.usuario,
    required this.onCerrarSesion,
  });

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _selectedIndex = 0;
  bool _sidebarAbierto = true;

  String get _nombreUsuario {
    final n = widget.usuario['nombre'] ?? widget.usuario['Nombre'] ?? widget.usuario['usuario'];
    return (n ?? 'OPERADOR').toString().trim().toUpperCase();
  }

  String get _cedulaUsuario {
    final c = widget.usuario['usuario'] ?? widget.usuario['id'];
    return (c ?? '').toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    // Vistas principales
    final List<Widget> paginas = [
      DashboardOlScreen(
        usuario: widget.usuario,
        onToggleSidebar: () => setState(() => _sidebarAbierto = !_sidebarAbierto),
      ),
      AccionesOlScreen(
        usuario: widget.usuario,
        onToggleSidebar: () => setState(() => _sidebarAbierto = !_sidebarAbierto),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Row(
        children: [
          // 🚪 MENÚ LATERAL (SIDEBAR)
          if (_sidebarAbierto) _buildSidebar(),

          // 📄 CONTENIDO DE LA PANTALLA SELECCIONADA
          Expanded(
            child: paginas[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF0A2540), // Azul oscuro profesional
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(2, 0),
          )
        ],
      ),
      child: Column(
        children: [
          // LOGO / ENCABEZADO SIDEBAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOGÍSTICA OL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Planta Tocancipá',
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ÍTEMS DE NAVEGACIÓN
          _buildSidebarItem(
            index: 0,
            icon: Icons.dashboard_rounded,
            label: 'Dashboard',
          ),
          _buildSidebarItem(
            index: 1,
            icon: Icons.table_chart_rounded,
            label: 'Baúl de Acciones',
          ),

          const Spacer(),

          const Divider(color: Colors.white12, height: 1),

          // PERFIL DE USUARIO LOGUEADO
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF1976D2),
                  child: Text(
                    _nombreUsuario.isNotEmpty ? _nombreUsuario[0] : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nombreUsuario,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'ID: $_cedulaUsuario',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // BOTÓN CERRAR SESIÓN
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
            child: InkWell(
              onTap: widget.onCerrarSesion,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.redAccent, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Cerrar Sesión',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool esSeleccionado = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: esSeleccionado ? const Color(0xFF0D47A1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: esSeleccionado ? Colors.white : Colors.white60,
                size: 20,
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: esSeleccionado ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: esSeleccionado ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}