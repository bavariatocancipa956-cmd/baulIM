import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math';

import 'api_service.dart';

class DashboardCincoWhyScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onToggleSidebar;

  const DashboardCincoWhyScreen({
    super.key,
    required this.usuario,
    required this.onToggleSidebar,
  });

  @override
  State<DashboardCincoWhyScreen> createState() =>
      _DashboardCincoWhyScreenState();
}

class _DashboardCincoWhyScreenState extends State<DashboardCincoWhyScreen> {
  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _filtroPI = 'Todos';
  String _filtroArea = 'Todas';

  List<String> _listaFiltroPI = ['Todos'];
  List<String> _listaFiltroArea = ['Todas'];

  int _totalReportes = 0;
  int _conCausaRaiz = 0;
  int _sinCausaRaiz = 0;
  Map<String, int> _conteoPI = {};
  Map<String, int> _conteoAreas = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });
    try {
      final data = await ApiService.consultar('gestion', '5why');
      List<Map<String, dynamic>> datosProcesados = [];
      if (data != null && data is List)
        datosProcesados = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

      _registros = datosProcesados;
      _extraerListasParaFiltros();
      _aplicarFiltros();

      setState(() => _cargando = false);
    } catch (e) {
      setState(() {
        _mensajeError = 'Error al cargar los datos: $e';
        _cargando = false;
      });
    }
  }

  void _extraerListasParaFiltros() {
    Set<String> pis = {'Todos'};
    Set<String> areas = {'Todas'};
    for (var r in _registros) {
      String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();
      String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
      if (pi.isNotEmpty && pi != 'NULL') pis.add(pi);
      if (ar.isNotEmpty && ar != 'NULL') areas.add(ar);
    }
    _listaFiltroPI = pis.toList()..sort();
    _listaFiltroArea = areas.toList()..sort();
  }

  void _aplicarFiltros() {
    setState(() {
      _registrosFiltrados = _registros.where((r) {
        if (_fechaDesde != null || _fechaHasta != null) {
          DateTime? dt = DateTime.tryParse(r['fecha']?.toString() ?? '');
          if (dt != null) {
            if (_fechaDesde != null && dt.isBefore(_fechaDesde!)) return false;
            if (_fechaHasta != null &&
                dt.isAfter(_fechaHasta!.add(const Duration(days: 1))))
              return false;
          }
        }
        String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
        String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();
        if (_filtroArea != 'Todas' && ar != _filtroArea) return false;
        if (_filtroPI != 'Todos' && pi != _filtroPI) return false;
        return true;
      }).toList();

      _calcularEstadisticas(_registrosFiltrados);
    });
  }

  void _calcularEstadisticas(List<Map<String, dynamic>> datos) {
    _totalReportes = datos.length;
    _conCausaRaiz = 0;
    _sinCausaRaiz = 0;
    Map<String, int> piTemp = {};
    Map<String, int> areasTemp = {};

    for (var fila in datos) {
      String pi = (fila['pi']?.toString() ?? 'Sin PI').toUpperCase();
      String area = (fila['area']?.toString() ?? 'Sin Área').toUpperCase();
      String causa = (fila['encontro_causa_raiz']?.toString() ?? '')
          .toUpperCase();

      if (pi.trim().isEmpty || pi == 'NULL') pi = 'SIN PI';
      if (area.trim().isEmpty || area == 'NULL') area = 'SIN ÁREA';
      if (causa == 'SI')
        _conCausaRaiz++;
      else
        _sinCausaRaiz++;

      piTemp[pi] = (piTemp[pi] ?? 0) + 1;
      areasTemp[area] = (areasTemp[area] ?? 0) + 1;
    }

    _conteoPI = Map.fromEntries(
      piTemp.entries.toList()..sort((e1, e2) => e2.value.compareTo(e1.value)),
    );
    _conteoAreas = Map.fromEntries(
      areasTemp.entries.toList()
        ..sort((e1, e2) => e2.value.compareTo(e1.value)),
    );
  }

  void _limpiarFiltros() {
    setState(() {
      _fechaDesde = null;
      _fechaHasta = null;
      _filtroPI = 'Todos';
      _filtroArea = 'Todas';
      _aplicarFiltros();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando)
      return const Scaffold(
        backgroundColor: Color(0xFFF1F5F9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0A2540)),
        ),
      );

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: widget.onToggleSidebar,
        ),
        title: const Text(
          'Dashboard Analítico 5 Why',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: _mensajeError != null
          ? Center(
              child: Text(
                _mensajeError!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBarraFiltros(),
                  const SizedBox(height: 24),
                  _buildDashboardTarjetas(),
                  const SizedBox(height: 24),
                  _buildTablasResumen(),
                ],
              ),
            ),
    );
  }

  Widget _buildBarraFiltros() {
    bool hayFiltrosActivos =
        _fechaDesde != null ||
        _fechaHasta != null ||
        _filtroPI != 'Todos' ||
        _filtroArea != 'Todas';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: Color(0xFF1976D2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Filtros del Dashboard',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              if (hayFiltrosActivos)
                InkWell(
                  onTap: _limpiarFiltros,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '🧹 Limpiar Filtros',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _buildFiltroFecha(
                'Fecha Desde',
                _fechaDesde,
                (fecha) => setState(() {
                  _fechaDesde = fecha;
                  _aplicarFiltros();
                }),
              ),
              _buildFiltroFecha(
                'Fecha Hasta',
                _fechaHasta,
                (fecha) => setState(() {
                  _fechaHasta = fecha;
                  _aplicarFiltros();
                }),
              ),
              _buildFiltroDropdown(
                'Área',
                _listaFiltroArea,
                _filtroArea,
                (val) => setState(() {
                  _filtroArea = val!;
                  _aplicarFiltros();
                }),
              ),
              _buildFiltroDropdown(
                'PI Afectado',
                _listaFiltroPI,
                _filtroPI,
                (val) => setState(() {
                  _filtroPI = val!;
                  _aplicarFiltros();
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroFecha(
    String label,
    DateTime? fechaActual,
    Function(DateTime?) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: fechaActual ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2101),
            );
            if (picked != null) onSelect(picked);
          },
          child: Container(
            width: 140,
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  fechaActual != null
                      ? DateFormat('yyyy-MM-dd').format(fechaActual)
                      : 'DD/MM/AAAA',
                  style: TextStyle(
                    fontSize: 12,
                    color: fechaActual != null ? Colors.black87 : Colors.grey,
                  ),
                ),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroDropdown(
    String label,
    List<String> opciones,
    String valor,
    Function(String?) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 160,
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: opciones.contains(valor) ? valor : opciones.first,
              isExpanded: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: opciones
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(e, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: onSelect,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTarjetas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        double w = constraints.maxWidth;
        int crossAxisCount = w > 800 ? 3 : (w > 500 ? 2 : 1);
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _kpiCard(
              'Total Análisis',
              '$_totalReportes',
              Icons.assignment_rounded,
              Colors.blue,
            ),
            _kpiCard(
              'Con Causa Raíz',
              '$_conCausaRaiz',
              Icons.check_circle_rounded,
              Colors.green,
            ),
            _kpiCard(
              'Sin Causa Raíz',
              '$_sinCausaRaiz',
              Icons.warning_rounded,
              Colors.orange,
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String titulo, String valor, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0A2540),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildTablasResumen() {
    bool isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      return Column(
        children: [
          _buildTablaTop('Análisis por Área (Top 10)', 'ÁREA', _conteoAreas),
          const SizedBox(height: 16),
          _buildTablaTop('Análisis por PI (Top 10)', 'PI AFECTADO', _conteoPI),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildTablaTop(
              'Análisis por Área (Top 10)',
              'ÁREA',
              _conteoAreas,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildTablaTop(
              'Análisis por PI (Top 10)',
              'PI AFECTADO',
              _conteoPI,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildTablaTop(
    String titulo,
    String headerCol1,
    Map<String, int> datos,
  ) {
    var top10 = datos.entries.take(10).toList();
    int totalTop = top10.fold(0, (sum, e) => sum + e.value);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
          ),
          Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: Colors.grey.shade100),
            ),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      headerCol1,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '%',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              ...top10.map((e) {
                double pct = _totalReportes == 0
                    ? 0
                    : (e.value / _totalReportes) * 100;
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${e.value}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFE2E8F0)),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'TOTALES MOSTRADOS',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '$totalTop',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _totalReportes == 0
                          ? '0%'
                          : '${((totalTop / _totalReportes) * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
