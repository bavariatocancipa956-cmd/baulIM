import 'package:flutter/material.dart';
import 'dashboard_ol_screen.dart';
import 'reportes_diarios_screen.dart';
import 'acciones_ol_screen.dart';
import 'abordajes_fms_screen.dart'; // <-- AQUÍ IMPORTAMOS LA NUEVA PANTALLA

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _sidebarFijoAbierto = true;

  String get _nombreUsuario {
    final n = widget.usuario['nombre'] ?? widget.usuario['Nombre'] ?? widget.usuario['usuario'];
    return (n ?? 'OPERADOR').toString().trim().toUpperCase();
  }

  String get _cedulaUsuario {
    final c = widget.usuario['usuario'] ?? widget.usuario['id'];
    return (c ?? '').toString().trim();
  }

  void _toggleSidebar(bool isMobile) {
    if (isMobile) {
      _scaffoldKey.currentState?.openDrawer();
    } else {
      setState(() => _sidebarFijoAbierto = !_sidebarFijoAbierto);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 850;

    // Vistas principales integradas (índices 0, 1, 2, 3)
    final List<Widget> paginas = [
      DashboardOlScreen(
        usuario: widget.usuario,
        onToggleSidebar: () => _toggleSidebar(isMobile),
      ),
      ReportesDiariosScreen(
        usuario: widget.usuario,
        onToggleSidebar: () => _toggleSidebar(isMobile),
      ),
      AccionesOlScreen(
        usuario: widget.usuario,
        onToggleSidebar: () => _toggleSidebar(isMobile),
      ),
      // <-- AQUÍ LLAMAMOS A LA PANTALLA REAL (ÍNDICE 3)
      AbordajesFmsScreen(
        usuario: widget.usuario,
        onToggleSidebar: () => _toggleSidebar(isMobile),
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: isMobile
          ? AppBar(
        backgroundColor: const Color(0xFF0A2540),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('LOGÍSTICA OL', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        elevation: 0,
      )
          : null,
      drawer: isMobile
          ? Drawer(
        width: 260,
        child: _buildSidebarContent(isMobile),
      )
          : null,
      body: Row(
        children: [
          if (!isMobile && _sidebarFijoAbierto)
            SizedBox(
              width: 250,
              child: _buildSidebarContent(isMobile),
            ),

          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: paginas,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A2540),
        boxShadow: [
          if (!isMobile)
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(2, 0),
            )
        ],
      ),
      child: Column(
        children: [
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.8),
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

          const SizedBox(height: 10),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      iconColor: Colors.white,
                      collapsedIconColor: Colors.white60,
                      leading: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 20),
                      title: const Text(
                        'ACCIONES OL',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
                      children: [
                        _buildSidebarItem(index: 0, icon: Icons.dashboard_rounded, label: 'Dashboard General', isMobile: isMobile),
                        _buildSidebarItem(index: 1, icon: Icons.grid_on_rounded, label: 'Matriz Diaria', isMobile: isMobile),
                        _buildSidebarItem(index: 2, icon: Icons.table_chart_rounded, label: 'Baúl de Acciones', isMobile: isMobile),
                      ],
                    ),
                  ),

                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      iconColor: Colors.white,
                      collapsedIconColor: Colors.white60,
                      leading: const Icon(Icons.security_rounded, color: Colors.white, size: 20),
                      title: const Text(
                        'GESTIÓN FMS',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
                      children: [
                        // ESTE ÍNDICE 3 AHORA ABRIRÁ LA PANTALLA REAL
                        _buildSidebarItem(index: 3, icon: Icons.assignment_ind_rounded, label: 'Abordajes', isMobile: isMobile),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

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

  Widget _buildSidebarItem({required int index, required IconData icon, required String label, required bool isMobile}) {
    final bool esSeleccionado = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() => _selectedIndex = index);
          if (isMobile) {
            Navigator.pop(context);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: esSeleccionado ? const Color(0xFF1976D2).withOpacity(0.8) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: esSeleccionado ? Colors.white : Colors.white60, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: esSeleccionado ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: esSeleccionado ? FontWeight.bold : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}