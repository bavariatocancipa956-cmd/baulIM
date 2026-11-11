import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart'; // Gráficas
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api_service.dart';

// ==========================================
// MODELO DE DATOS
// ==========================================
class AccionVisual {
  final int id5Why;
  final int numeroAccion;
  final String fecha;
  final String area;
  final String pi;
  final String supervisor;
  final String interventor;
  final String tipoAccion;
  final String descripcion;
  final String responsable;
  final String fechaCierre;
  final String estado;
  final String? urlEvidencia;
  final Map<String, dynamic> rowData;

  AccionVisual({
    required this.id5Why,
    required this.numeroAccion,
    required this.fecha,
    required this.area,
    required this.pi,
    required this.supervisor,
    required this.interventor,
    required this.tipoAccion,
    required this.descripcion,
    required this.responsable,
    required this.fechaCierre,
    required this.estado,
    this.urlEvidencia,
    required this.rowData,
  });
}

class AccionesCincoWhyScreen extends StatefulWidget {
  final VoidCallback onToggleSidebar;

  const AccionesCincoWhyScreen({super.key, required this.onToggleSidebar});

  @override
  State<AccionesCincoWhyScreen> createState() => _AccionesCincoWhyScreenState();
}

class _AccionesCincoWhyScreenState extends State<AccionesCincoWhyScreen> {
  bool _cargando = true;
  List<AccionVisual> _todasLasAcciones = [];
  List<AccionVisual> _accionesFiltradas = [];

  // Listas para Filtros Dinámicos
  List<String> _listaAreas = ['Todas'];
  List<String> _listaPis = ['Todos'];
  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaInterventores = ['Todos'];

  // Valores seleccionados en filtros
  String? _filtroFecha;
  String _filtroEstado = 'Todos';
  String _filtroArea = 'Todas';
  String _filtroPi = 'Todos';
  String _filtroSupervisor = 'Todos';
  String _filtroInterventor = 'Todos';

  // Anchos de columnas para la tabla custom (ajustados para caber)
  final double wFecha = 80;
  final double wArea = 100;
  final double wPi = 120;
  final double wSupervisor = 120;
  final double wInterventor = 120;
  final double wTipo = 100;
  final double wAccion = 250;
  final double wResponsable = 120;
  final double wFechaCierre = 90;
  final double wEstado = 90;
  final double wEvidencia = 90;
  final double wPdf = 70; // Aumentado ligeramente para evitar el overflow del botón PDF

  bool _generandoPdf = false;

  @override
  void initState() {
    super.initState();
    _cargarAcciones();
  }

  String _formatearFecha(dynamic fechaRaw) {
    if (fechaRaw == null || fechaRaw.toString().isEmpty) return 'N/A';
    try {
      DateTime dt = DateTime.parse(fechaRaw.toString());
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (e) {
      return fechaRaw.toString();
    }
  }

  Future<void> _cargarAcciones() async {
    setState(() => _cargando = true);
    try {
      final List<dynamic> data = await ApiService.consultar('gestion', '5why');
      List<AccionVisual> extraidas = [];
      Set<String> areasUnicas = {'Todas'};
      Set<String> pisUnicos = {'Todos'};
      Set<String> supUnicos = {'Todos'};
      Set<String> intUnicos = {'Todos'};

      for (var row in data) {
        int id = row['id'];
        String fechaFormat = _formatearFecha(row['fecha']);
        String pi = row['pi']?.toString().trim() ?? 'N/A';
        String area = row['area']?.toString().trim() ?? 'N/A';
        String sup = row['supervisor']?.toString().trim().toUpperCase() ?? 'N/A';
        String inter = row['interventor']?.toString().trim().toUpperCase() ?? 'N/A';

        if (area != 'N/A') areasUnicas.add(area);
        if (pi != 'N/A') pisUnicos.add(pi);
        if (sup.isNotEmpty && sup != 'N/A' && sup != 'NULL') supUnicos.add(sup);
        if (inter.isNotEmpty && inter != 'N/A' && inter != 'NULL') intUnicos.add(inter);

        for (int i = 1; i <= 4; i++) {
          String? tipoAccion = row['accion_$i'];
          if (tipoAccion != null && tipoAccion.toString().trim().isNotEmpty) {
            extraidas.add(
              AccionVisual(
                id5Why: id,
                numeroAccion: i,
                fecha: fechaFormat,
                area: area,
                pi: pi,
                supervisor: sup,
                interventor: inter,
                tipoAccion: tipoAccion,
                descripcion: row['descripcion_$i'] ?? 'Sin descripción',
                responsable: (row['responsable_$i'] ?? 'SIN ASIGNAR')
                    .toString()
                    .toUpperCase(),
                fechaCierre: _formatearFecha(row['fecha_cierre_$i']),
                estado: row['estado_accion$i'] ?? 'Pendiente',
                urlEvidencia: row['evidencia_accion_$i']?.toString(),
                rowData: row,
              ),
            );
          }
        }
      }

      _listaAreas = areasUnicas.toList()..sort();
      _listaPis = pisUnicos.toList()..sort();
      _listaSupervisores = supUnicos.toList()..sort();
      _listaInterventores = intUnicos.toList()..sort();
      _todasLasAcciones = extraidas;

      _aplicarFiltros();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _aplicarFiltros() {
    _accionesFiltradas = _todasLasAcciones.where((a) {
      bool coincideFecha = _filtroFecha == null || a.fecha == _filtroFecha;

      bool coincideEstado = true;
      if (_filtroEstado == 'Pendientes')
        coincideEstado = a.estado.toLowerCase() != 'concluida';
      if (_filtroEstado == 'Concluidas')
        coincideEstado = a.estado.toLowerCase() == 'concluida';

      bool coincideArea = _filtroArea == 'Todas' || a.area == _filtroArea;
      bool coincidePi = _filtroPi == 'Todos' || a.pi == _filtroPi;
      bool coincideSup = _filtroSupervisor == 'Todos' || a.supervisor == _filtroSupervisor;
      bool coincideInt = _filtroInterventor == 'Todos' || a.interventor == _filtroInterventor;

      return coincideFecha && coincideEstado && coincideArea && coincidePi && coincideSup && coincideInt;
    }).toList();

    setState(() {});
  }

  Future<void> _seleccionarFechaFiltro() async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (seleccion != null) {
      setState(() => _filtroFecha = DateFormat('dd/MM/yyyy').format(seleccion));
      _aplicarFiltros();
    }
  }

  void _limpiarFiltros() {
    setState(() {
      _filtroFecha = null;
      _filtroEstado = 'Todos';
      _filtroArea = 'Todas';
      _filtroPi = 'Todos';
      _filtroSupervisor = 'Todos';
      _filtroInterventor = 'Todos';
    });
    _aplicarFiltros();
  }

  String _agruparArea(String area) {
    String a = area.toLowerCase().trim();
    if (a.startsWith('linea') || a.startsWith('línea')) return 'LÍNEAS';
    return area.toUpperCase();
  }

  Map<int, List<AccionVisual>> get _accionesAgrupadas {
    Map<int, List<AccionVisual>> agrupadas = {};
    for (var accion in _accionesFiltradas) {
      agrupadas.putIfAbsent(accion.id5Why, () => []).add(accion);
    }
    return agrupadas;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: widget.onToggleSidebar,
        ),
        title: const Text(
          'Acciones del 5 Why',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarAcciones,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBarraFiltrosSuperior(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildTarjetasKPI(),
                      const SizedBox(height: 20),
                      _buildTablasResumen(),
                      const SizedBox(height: 20),
                      _buildContenedorTablaCustom(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ===============================================
  // TARJETAS KPI
  // ===============================================
  Widget _buildTarjetasKPI() {
    int total = _accionesFiltradas.length;
    int concluidas = _accionesFiltradas.where((a) => a.estado.toLowerCase() == 'concluida').length;
    int pendientes = total - concluidas;

    double avance = total == 0 ? 0 : (concluidas / total) * 100;

    return Row(
      children: [
        Expanded(child: _buildKPI('TOTAL ACCIONES', total.toString(), Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _buildKPI('CONCLUIDAS', concluidas.toString(), Colors.green)),
        const SizedBox(width: 12),
        Expanded(child: _buildKPI('PENDIENTES', pendientes.toString(), Colors.orange)),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('AVANCE GENERAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      Text('${avance.toStringAsFixed(1)}%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: total == 0 ? 0 : concluidas / total,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                        strokeWidth: 6,
                      ),
                      Center(
                        child: Text(
                          '${avance.toInt()}%',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKPI(String titulo, String valor, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade700)),
          const SizedBox(height: 8),
          Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  // ===============================================
  // TABLAS RESUMEN
  // ===============================================
  Widget _buildTablasResumen() {
    int total = _accionesFiltradas.length;
    int concluidas = _accionesFiltradas.where((a) => a.estado.toLowerCase() == 'concluida').length;
    int pendientes = total - concluidas;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _buildTablaResumen('Acciones por Área', _agruparPorArea()),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 1,
          child: _buildPieChartEstados(concluidas, pendientes, total),
        ),
      ],
    );
  }

  Map<String, Map<String, int>> _agruparPorArea() {
    Map<String, Map<String, int>> map = {};
    for (var a in _accionesFiltradas) {
      String area = _agruparArea(a.area);
      map.putIfAbsent(area, () => {'total': 0, 'concluidas': 0});
      map[area]!['total'] = map[area]!['total']! + 1;
      if (a.estado.toLowerCase() == 'concluida') {
        map[area]!['concluidas'] = map[area]!['concluidas']! + 1;
      }
    }
    return map;
  }

  Widget _buildTablaResumen(String titulo, Map<String, Map<String, int>> datos) {
    var filas = datos.entries.toList()..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text('ÁREA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                  Expanded(child: Text('TOTAL', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                  Expanded(child: Text('CONCLUIDAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                  Expanded(child: Text('% AVANCE', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                  Expanded(flex: 2, child: Text('BARRA', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...filas.expand((e) {
            double pct = e.value['total']! == 0 ? 0 : (e.value['concluidas']! / e.value['total']!) * 100;
            return [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(e.key, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500))),
                    Expanded(child: Text(e.value['total'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                    Expanded(child: Text(e.value['concluidas'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                    Expanded(child: Text('${pct.toStringAsFixed(1)}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)))),
                    Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: _buildProgressBar(pct))),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
            ];
          }).toList(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double pct) {
    return Container(
      height: 10,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: (pct / 100.0).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChartEstados(int concluidas, int pendientes, int total) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Distribución de Estados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: total == 0 
                ? const Center(child: Text('Sin datos'))
                : PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 60,
                      sections: [
                        if (concluidas > 0)
                          PieChartSectionData(
                            color: const Color(0xFF4CAF50),
                            value: concluidas.toDouble(),
                            title: '',
                            radius: 30,
                          ),
                        if (pendientes > 0)
                          PieChartSectionData(
                            color: const Color(0xFFFF9800),
                            value: pendientes.toDouble(),
                            title: '',
                            radius: 30,
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 32),
          _buildLeyendaPieChart(color: const Color(0xFF4CAF50), titulo: 'Concluidas', valor: concluidas, total: total),
          const SizedBox(height: 12),
          _buildLeyendaPieChart(color: const Color(0xFFFF9800), titulo: 'Pendientes', valor: pendientes, total: total),
        ],
      ),
    );
  }

  Widget _buildLeyendaPieChart({required Color color, required String titulo, required int valor, required int total}) {
    double pct = total == 0 ? 0 : (valor / total) * 100;
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text('$valor (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ],
    );
  }

  // ===============================================
  // BARRA DE FILTROS SUPERIOR
  // ===============================================
  Widget _buildBarraFiltrosSuperior() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fecha',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: _seleccionarFechaFiltro,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _filtroFecha ?? 'DD/MM/YYYY',
                          style: TextStyle(
                            fontSize: 13,
                            color: _filtroFecha == null
                                ? Colors.black38
                                : Colors.black87,
                          ),
                        ),
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildFiltroDropdown(
              'Estado',
              _filtroEstado,
              ['Todos', 'Pendientes', 'Concluidas'],
              (v) {
                setState(() => _filtroEstado = v!);
                _aplicarFiltros();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildFiltroDropdown('PI', _filtroPi, _listaPis, (v) {
              setState(() => _filtroPi = v!);
              _aplicarFiltros();
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildFiltroDropdown('Área', _filtroArea, _listaAreas, (v) {
              setState(() => _filtroArea = v!);
              _aplicarFiltros();
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildFiltroDropdown('Supervisor', _filtroSupervisor, _listaSupervisores, (v) {
              setState(() => _filtroSupervisor = v!);
              _aplicarFiltros();
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildFiltroDropdown('Interventor', _filtroInterventor, _listaInterventores, (v) {
              setState(() => _filtroInterventor = v!);
              _aplicarFiltros();
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: TextButton.icon(
              onPressed: _limpiarFiltros,
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                foregroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text(
                'Limpiar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroDropdown(
    String titulo,
    String valor,
    List<String> opciones,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 10, // Letra más pequeña para que quepa
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
          overflow: TextOverflow.ellipsis, // Evitar overflow
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 38,
          child: DropdownButtonFormField<String>(
            initialValue: opciones.contains(valor) ? valor : (opciones.isNotEmpty ? opciones.first : null),
            isExpanded: true, // Esto es importante para que el texto no desborde la caja
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, // Menos padding
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
            style: const TextStyle(fontSize: 11, color: Colors.black87), // Letra más pequeña
            items: opciones
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ===============================================
  // TABLA CUSTOM ESTILO EXCEL (Encabezados Fijos)
  // ===============================================
  Widget _buildContenedorTablaCustom() {
    return Container(
      height: 600, // Altura fija para permitir el scroll interno de la tabla
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: _buildTablaCustom(),
    );
  }

  Widget _buildTablaCustom() {
    if (_accionesFiltradas.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron acciones con los filtros aplicados',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    double totalWidth = wFecha + wArea + wPi + wSupervisor + wInterventor + wTipo + wAccion + wResponsable + wFechaCierre + wEstado + wEvidencia + wPdf;

    int gIdx = 0;
    List<Widget> rows = [];
    for (var entry in _accionesAgrupadas.entries) {
      List<AccionVisual> grupo = entry.value;
      for (int i = 0; i < grupo.length; i++) {
        bool isLastOfGroup = i == grupo.length - 1;
        rows.add(_buildFilaFlat(grupo[i], isLastOfGroup: isLastOfGroup, isEvenGroup: gIdx % 2 == 0));
      }
      gIdx++;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCabeceraTabla(),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCabeceraTabla() {
    return Row(
      children: [
        _buildCeldaCabecera('FECHA', wFecha),
        _buildCeldaCabecera('AREA', wArea),
        _buildCeldaCabecera('PI', wPi),
        _buildCeldaCabecera('SUPERVISOR', wSupervisor),
        _buildCeldaCabecera('INTERVENTOR', wInterventor),
        _buildCeldaCabecera('TIPO DE ACCIÓN', wTipo),
        _buildCeldaCabecera('ACCIÓN', wAccion, align: Alignment.centerLeft),
        _buildCeldaCabecera('RESPONSABLE', wResponsable),
        _buildCeldaCabecera('FECHA CIERRE', wFechaCierre),
        _buildCeldaCabecera('ESTADO', wEstado),
        _buildCeldaCabecera('EVIDENCIA', wEvidencia),
        _buildCeldaCabecera('PDF', wPdf),
      ],
    );
  }

  Widget _buildFilaFlat(AccionVisual accion, {required bool isLastOfGroup, required bool isEvenGroup}) {
    bool completado = accion.estado.toLowerCase() == 'concluida';
    Color rowColor = isEvenGroup ? Colors.white : const Color(0xFFF8FAFC); // Zebra striping por grupo de 5Why

    return Container(
      color: rowColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCeldaCuerpoFlat(Text(accion.fecha, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wFecha, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.area, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wArea, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.pi, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.bold)), wPi, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.supervisor, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wSupervisor, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.interventor, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wInterventor, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.tipoAccion, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wTipo, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.descripcion, style: const TextStyle(fontSize: 12, color: Color(0xFF334155)), maxLines: 4, overflow: TextOverflow.ellipsis), wAccion, align: Alignment.centerLeft, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.responsable, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wResponsable, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(Text(accion.fechaCierre, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))), wFechaCierre, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(_buildBadgeEstado(accion.estado.toUpperCase(), completado), wEstado, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(_buildEvidenciaWidget(accion), wEvidencia, isLastOfGroup: isLastOfGroup),
            _buildCeldaCuerpoFlat(
              _generandoPdf 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 20),
                  tooltip: 'Descargar PDF 5 Why',
                  onPressed: () => _generarYDescargarPDF(accion.rowData),
                ), 
              wPdf, 
              isLastOfGroup: isLastOfGroup
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCeldaCabecera(
    String texto,
    double width, {
    Alignment align = Alignment.center,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(
          right: BorderSide(color: Colors.white24, width: 1),
        ), 
      ),
      alignment: align,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              texto,
              textAlign: align == Alignment.center ? TextAlign.center : TextAlign.left,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white, 
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.unfold_more, size: 12, color: Colors.white70),
        ],
      ),
    );
  }

  Widget _buildCeldaCuerpoFlat(
    Widget hijo,
    double width, {
    Alignment align = Alignment.center,
    required bool isLastOfGroup,
  }) {
    // Cuadrícula gruesa inferior solo cuando es el final del grupo
    BorderSide borderBottom = isLastOfGroup 
        ? const BorderSide(color: Color(0xFFCBD5E1), width: 2) // Gris más oscuro, más grueso
        : const BorderSide(color: Color(0xFFE2E8F0), width: 1); // Gris claro

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: borderBottom,
          right: const BorderSide(color: Color(0xFFE2E8F0), width: 1), 
        ),
      ),
      alignment: align,
      child: hijo,
    );
  }

  Widget _buildBadgeEstado(String text, bool isSuccess) {
    Color colorFondo = isSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    Color colorTexto = isSuccess ? const Color(0xFF166534) : const Color(0xFF92400E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(20), // Botones redondeados tipo píldora
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colorTexto,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEvidenciaWidget(AccionVisual accion) {
    bool hasEvidencia = accion.urlEvidencia != null && accion.urlEvidencia!.isNotEmpty && accion.urlEvidencia != 'NULL';
    bool completado = accion.estado.toLowerCase() == 'concluida' || accion.estado.toLowerCase() == 'completada' || accion.estado.toLowerCase() == 'cerrado';

    if (hasEvidencia) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          InkWell(
            onTap: () => _mostrarPreviewImagen(accion.urlEvidencia!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF), // Azul muy claro
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF93C5FD)), // Borde azul claro
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_rounded, size: 14, color: Color(0xFF2563EB)), // Azul vibrante
                  SizedBox(width: 4),
                  Text('Ver', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.edit_square, color: Colors.black54, size: 16),
            tooltip: 'Cambiar evidencia',
            onPressed: () => _seleccionarYSubirEvidencia(accion, isEdit: true),
          ),
        ],
      );
    }

    if (!completado) {
      return ElevatedButton.icon(
        onPressed: () => _seleccionarYSubirEvidencia(accion, isEdit: false),
        icon: const Icon(Icons.upload_file_rounded, size: 14),
        label: const Text('Cargar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981), // Verde Esmeralda
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }

    return const Text('-', style: TextStyle(color: Colors.black54));
  }

  Future<void> _seleccionarYSubirEvidencia(AccionVisual accion, {bool isEdit = false}) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Cambiar Evidencia de Cierre' : 'Adjuntar Evidencia de Cierre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEdit)
              const Padding(
                padding: EdgeInsets.only(bottom: 12.0),
                child: Text('Al subir una nueva imagen, se reemplazará la evidencia anterior.', style: TextStyle(color: Colors.black54, fontSize: 13)),
              ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tomar Foto'),
              onTap: () {
                Navigator.pop(ctx);
                _procesarImagen(accion, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de Galería'),
              onTap: () {
                Navigator.pop(ctx);
                _procesarImagen(accion, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _procesarImagen(AccionVisual accion, ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: source);
      if (image == null) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Comprimiendo y subiendo (Máx 30KB)...')),
              ],
            ),
          ),
        );
      }

      Uint8List bytes = await image.readAsBytes();
      
      // Compresión
      Uint8List compressed = await compute(_compressImage30KB, bytes);

      // Subida
      String? url = await ApiService.subirImagen(compressed);
      
      if (mounted) Navigator.pop(context); // Cerrar loader
      
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al subir la imagen a la nube')));
        }
        return;
      }

      // Actualizar Base de datos
      String colEvidencia = 'evidencia_accion_${accion.numeroAccion}';
      String colEstado = 'estado_accion${accion.numeroAccion}';

      final success = await ApiService.actualizar('gestion', '5why', 'id', accion.id5Why, {
        colEvidencia: url,
        colEstado: 'CONCLUIDA',
      });

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evidencia actualizada y acción concluida exitosamente.')));
          _cargarAcciones();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al actualizar registro de acción.')));
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _mostrarPreviewImagen(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: url.startsWith('http') 
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, fit: BoxFit.contain)) 
                  : (url.startsWith('data:image') 
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain)) 
                      : const Center(child: Text('Formato no soportado', style: TextStyle(color: Colors.white)))),
            ),
            Container(
              margin: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================
  // GENERAR PDF DE ACCIONES DE 5 WHY
  // ===============================================
  Future<Map<String, pw.ImageProvider>> _preDecodificarImagenes(Map<String, dynamic> row) async {
    Map<String, pw.ImageProvider> imagenesListas = {};
    
    // Decodificar imágenes de los 5 Porqués
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      try {
        if (rawEvidencia.contains('http://') || rawEvidencia.contains('https://')) {
          int httpIndex = rawEvidencia.indexOf('http');
          String imageUrl = rawEvidencia.substring(httpIndex).trim();
          final resp = await http.get(Uri.parse(imageUrl));
          if (resp.statusCode == 200) imagenesListas['porque_$i'] = pw.MemoryImage(resp.bodyBytes);
        } else if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
          final parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
          if (parts.length > 1) {
            String base64String = parts[1];
            int commaIndex = base64String.indexOf('base64,');
            if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
            if (base64String.length <= 1000000) {
              base64String = base64String.replaceAll(RegExp(r'\s+'), '');
              imagenesListas['porque_$i'] = pw.MemoryImage(base64Decode(base64String), dpi: 72);
            }
          }
        } else if (rawEvidencia.contains('data:image')) {
          int dataIndex = rawEvidencia.indexOf('data:image');
          String base64String = rawEvidencia.substring(dataIndex);
          int commaIndex = base64String.indexOf('base64,');
          if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
          if (base64String.length <= 1000000) {
            base64String = base64String.replaceAll(RegExp(r'\s+'), '');
            imagenesListas['porque_$i'] = pw.MemoryImage(base64Decode(base64String), dpi: 72);
          }
        }
      } catch (e) {
        debugPrint('Error procesando imagen PDF porqué $i: $e');
      }
    }

    // Decodificar imágenes de las Acciones
    for (int i = 1; i <= 4; i++) {
      String rawEvidencia = row['evidencia_accion_$i']?.toString() ?? '';
      try {
        if (rawEvidencia.contains('http://') || rawEvidencia.contains('https://')) {
          int httpIndex = rawEvidencia.indexOf('http');
          String imageUrl = rawEvidencia.substring(httpIndex).trim();
          final resp = await http.get(Uri.parse(imageUrl));
          if (resp.statusCode == 200) imagenesListas['accion_$i'] = pw.MemoryImage(resp.bodyBytes);
        } else if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
          final parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
          if (parts.length > 1) {
            String base64String = parts[1];
            int commaIndex = base64String.indexOf('base64,');
            if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
            if (base64String.length <= 1000000) {
              base64String = base64String.replaceAll(RegExp(r'\s+'), '');
              imagenesListas['accion_$i'] = pw.MemoryImage(base64Decode(base64String), dpi: 72);
            }
          }
        } else if (rawEvidencia.contains('data:image')) {
          int dataIndex = rawEvidencia.indexOf('data:image');
          String base64String = rawEvidencia.substring(dataIndex);
          int commaIndex = base64String.indexOf('base64,');
          if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
          if (base64String.length <= 1000000) {
            base64String = base64String.replaceAll(RegExp(r'\s+'), '');
            imagenesListas['accion_$i'] = pw.MemoryImage(base64Decode(base64String), dpi: 72);
          }
        }
      } catch (e) {
        debugPrint('Error procesando imagen PDF acción $i: $e');
      }
    }

    return imagenesListas;
  }

  List<pw.Widget> _construirPaginasPdf(
    Map<String, dynamic> row,
    pw.ImageProvider? imgLogo,
    Map<String, pw.ImageProvider> imagenesDecodificadas,
  ) {
    final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const regularStyle = pw.TextStyle(fontSize: 9);
    final greyBg = PdfColors.grey300;
    final darkGreyBg = PdfColors.grey400;

    pw.Widget celdaLabel(
      String texto, {
      pw.TextAlign align = pw.TextAlign.center,
      PdfColor colorTexto = PdfColors.black,
    }) => pw.Container(
      padding: const pw.EdgeInsets.all(5),
      alignment: align == pw.TextAlign.center
          ? pw.Alignment.center
          : pw.Alignment.centerLeft,
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
          color: colorTexto,
        ),
        textAlign: align,
      ),
    );
    pw.Widget celdaValor(String texto) => pw.Container(
      padding: const pw.EdgeInsets.all(5),
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(texto, style: regularStyle),
    );

    List<pw.Widget> evidenciasWidgets = [];
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      String textoEvidencia = rawEvidencia;

      if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
        textoEvidencia = rawEvidencia.split('IMAGEN_ADJUNTA:')[0].replaceAll('|', '').trim();
      } else if (rawEvidencia.contains('http')) {
        textoEvidencia = rawEvidencia.substring(0, rawEvidencia.indexOf('http')).replaceAll('|', '').trim();
      } else if (rawEvidencia.contains('data:image')) {
        textoEvidencia = rawEvidencia.substring(0, rawEvidencia.indexOf('data:image')).replaceAll('|', '').trim();
      }

      if (imagenesDecodificadas.containsKey('porque_$i')) {
        evidenciasWidgets.add(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
              if (textoEvidencia.isNotEmpty) pw.SizedBox(height: 4),
              pw.Center(child: pw.Image(imagenesDecodificadas['porque_$i']!, height: 60, fit: pw.BoxFit.contain)),
            ],
          ),
        );
      } else {
        if (rawEvidencia.contains('IMAGEN_ADJUNTA:') || rawEvidencia.contains('http') || rawEvidencia.contains('data:image')) {
          evidenciasWidgets.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 4),
                pw.Text('[Imagen omitida o muy pesada]', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800)),
              ],
            ),
          );
        } else {
          evidenciasWidgets.add(pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)));
        }
      }
    }

    String fecha = row['fecha']?.toString().split('T')[0] ?? '-';
    String turno = row['turno']?.toString() ?? '-';
    String area = row['area']?.toString() ?? '-';
    String pi = row['pi']?.toString() ?? '-';
    String participantes = row['participantes']?.toString() ?? '-';
    String disparador = row['valor_disparador_alcanzado']?.toString() ?? '-';
    String contencion = row['contencion_problema']?.toString() ?? '-';
    String necesitaInv = (row['requiere_investigacion_adicional']?.toString() ?? 'NO').toUpperCase();
    String causaRaizFormulario = (row['encontro_causa_raiz']?.toString() ?? 'NO').toUpperCase();
    String descripcionCausaRaiz = row['causa_raiz']?.toString() ?? row['causa raiz']?.toString() ?? '-';

    String q1 = row['cumple_flujo_resolucion']?.toString() ?? '';
    if (q1 == 'PD') q1 = '';
    String q2 = row['resolucion_primera_linea']?.toString() ?? '';
    if (q2 == 'PD') q2 = '';
    String q3 = row['secuencia_tiene_sentido']?.toString() ?? '';
    if (q3 == 'PD') q3 = '';
    String q4 = row['porques_con_evidencia']?.toString() ?? '';
    if (q4 == 'PD') q4 = '';
    String q5 = row['encontro_causa_raiz_eval']?.toString() ?? row['encontro_causa_raiz']?.toString() ?? '';
    if (q5 == 'PD') q5 = '';
    String q6 = row['proponen_acciones_eliminacion']?.toString() ?? '';
    if (q6 == 'PD') q6 = '';

    String estadoEval = row['estado']?.toString().toUpperCase() ?? 'PENDIENTE';
    String displayEstadoEval = estadoEval == 'PENDIENTE' ? '' : estadoEval;
    String calificacion = estadoEval == 'PENDIENTE' ? '' : (row['resultado']?.toString() ?? '');
    String obsEval = estadoEval == 'PENDIENTE' ? '' : (row['observacion_evaluador']?.toString() ?? '');
    String resultado2 = row['resultado_2']?.toString() ?? (estadoEval == 'APTO' ? 'No aplica' : '');
    if (resultado2 == 'Pendiente por revisión') resultado2 = '';
    String ultimaAprovacion = row['ultima_aprovacion']?.toString() ?? row['ultima aprovacion']?.toString() ?? (estadoEval == 'APTO' ? 'No aplica' : '');
    if (ultimaAprovacion == 'Pendiente por revisión') ultimaAprovacion = '';
    String obs2 = row['Observacion 2']?.toString() ?? row['observacion_2']?.toString() ?? '';
    if (obs2 == '-') obs2 = '';

    return [
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.2),
          1: const pw.FlexColumnWidth(3.5),
          2: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                height: 40,
                padding: const pw.EdgeInsets.all(5),
                alignment: pw.Alignment.center,
                child: imgLogo != null ? pw.Image(imgLogo, fit: pw.BoxFit.contain) : pw.SizedBox(),
              ),
              pw.Container(
                color: greyBg,
                alignment: pw.Alignment.center,
                child: pw.Text('Análisis 5 porqués', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              ),
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text('ABInBev', style: pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(2.5),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            children: [
              celdaLabel('Fecha:'),
              celdaValor(fecha),
              celdaLabel('Turno:'),
              celdaValor(turno),
            ],
          ),
          pw.TableRow(
            children: [
              celdaLabel('Área:'),
              celdaValor(area),
              celdaLabel('PI:'),
              celdaValor(pi),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(5)},
        children: [pw.TableRow(children: [celdaLabel('Participantes:'), celdaValor(participantes)])],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Información del disparador:', style: boldStyle))]),
          pw.TableRow(children: [pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(disparador, style: regularStyle))]),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('¿Qué se hizo para contener el problema y lograr reanudar el proceso?', style: boldStyle))]),
          pw.TableRow(children: [pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(contencion, style: regularStyle))]),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('5W', style: boldStyle))])],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(2)},
        children: [
          pw.TableRow(
            children: [
              pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Responda los 5 porqués', style: boldStyle)),
              pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Evidencias', style: boldStyle)),
            ],
          ),
        ],
      ),
      ...List.generate(5, (index) {
        String pq = row['porque_${index + 1}']?.toString() ?? '';
        String ex = row['explique_porque_${index + 1}']?.toString() ?? '';
        return pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: {
            0: const pw.FixedColumnWidth(25),
            1: const pw.FixedColumnWidth(65),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              children: [
                pw.Container(alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(4), child: pw.Text('${index + 1}', style: regularStyle)),
                pw.Container(alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(4), child: pw.Text('¿Por qué?', style: regularStyle)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))),
                      child: pw.Text(pq.isEmpty ? ' ' : pq, style: boldStyle, textAlign: pw.TextAlign.center),
                    ),
                    pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(ex.isEmpty ? ' ' : ex, style: regularStyle)),
                  ],
                ),
                pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: evidenciasWidgets[index]),
              ],
            ),
          ],
        );
      }),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(3),
          4: const pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            children: [
              pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Cierre del ciclo:', style: boldStyle)),
              pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('¿Se necesita realizar una\ninvestigación adicional?', style: boldStyle, textAlign: pw.TextAlign.center)),
              pw.Container(color: necesitaInv == 'SI' ? PdfColors.red : PdfColors.green, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text(necesitaInv, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11))),
              pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Causa raíz encontrada', style: boldStyle, textAlign: pw.TextAlign.center)),
              pw.Container(color: causaRaizFormulario == 'SI' ? PdfColors.green : PdfColors.red, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text(causaRaizFormulario, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11))),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(5)},
        children: [pw.TableRow(children: [celdaLabel('Descripción Causa Raíz:'), celdaValor(descripcionCausaRaiz)])],
      ),
      pw.SizedBox(height: 5),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(
            children: [
              pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('ACCIONES', style: boldStyle)),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(2.5),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1),
          6: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: greyBg),
            children: [
              celdaLabel('Tipo'),
              celdaLabel('Aplicar a'),
              celdaLabel('Accion / Descripción'),
              celdaLabel('Responsable'),
              celdaLabel('Fecha cierre'),
              celdaLabel('Estado'),
              celdaLabel('Evidencia'),
            ],
          ),
          ...List.generate(4, (index) {
            String tipo = row['accion_${index + 1}']?.toString() ?? '';
            String act = row['actividad_${index + 1}']?.toString() ?? '';
            String desc = row['descripcion_${index + 1}']?.toString() ?? '';
            String resp = row['responsable_${index + 1}']?.toString() ?? '';
            String fCie = row['fecha_cierre_${index + 1}']?.toString().split('T')[0] ?? '';
            String est = row['estado_accion${index + 1}']?.toString() ?? '';
            String ev = row['evidencia_accion_${index + 1}']?.toString() ?? '';

            if (tipo.isEmpty && desc.isEmpty) return pw.TableRow(children: []);
            bool isPreventiva = tipo.toUpperCase() == 'PREVENTIVA';
            bool isConcluida = est.toUpperCase() == 'CONCLUIDA';

            pw.Widget widgetEvidencia = pw.Text('-', style: regularStyle, textAlign: pw.TextAlign.center);
            if (imagenesDecodificadas.containsKey('accion_${index + 1}')) {
              widgetEvidencia = pw.Center(child: pw.Image(imagenesDecodificadas['accion_${index + 1}']!, height: 40, fit: pw.BoxFit.contain));
            } else if (ev.contains('IMAGEN_ADJUNTA:') || ev.contains('http') || ev.contains('data:image')) {
              widgetEvidencia = pw.Text('[Evidencia omitida]', style: pw.TextStyle(fontSize: 7, color: PdfColors.red800), textAlign: pw.TextAlign.center);
            }

            return pw.TableRow(
              children: [
                celdaLabel(tipo, align: pw.TextAlign.center),
                pw.Container(
                  color: isPreventiva ? darkGreyBg : PdfColors.white,
                  padding: const pw.EdgeInsets.all(5),
                  alignment: pw.Alignment.center,
                  child: pw.Text(act.isEmpty ? 'N/A' : act, style: pw.TextStyle(fontSize: 9, fontWeight: isPreventiva ? pw.FontWeight.bold : pw.FontWeight.normal)),
                ),
                celdaValor(desc),
                celdaValor(resp),
                celdaValor(fCie),
                celdaLabel(est.isNotEmpty ? est : 'Pendiente', align: pw.TextAlign.center, colorTexto: isConcluida ? PdfColors.green800 : PdfColors.orange800),
                pw.Container(padding: const pw.EdgeInsets.all(5), alignment: pw.Alignment.center, child: widgetEvidencia),
              ],
            );
          }),
        ],
      ),
      if (estadoEval == 'APTO' || estadoEval == 'NO APTO' || estadoEval == 'PENDIENTE') ...[
        pw.SizedBox(height: 15),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          children: [
            pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('EVALUACIÓN DE CALIDAD Y REVISIÓN', style: boldStyle))]),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: {0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1)},
          children: [
            pw.TableRow(children: [celdaValor('1. ¿Se cumple con el flujo de resolución de problemas (participación adecuada)?'), celdaLabel(q1, align: pw.TextAlign.center)]),
            pw.TableRow(children: [celdaValor('2. ¿La resolución se llevó a cabo con la primera línea (operadores y técnicos)?'), celdaLabel(q2, align: pw.TextAlign.center)]),
            pw.TableRow(children: [celdaValor('3. ¿La secuencia de la resolución de problema tiene sentido?'), celdaLabel(q3, align: pw.TextAlign.center)]),
            pw.TableRow(children: [celdaValor('4. ¿Todos los porqués cuentan con evidencia?'), celdaLabel(q4, align: pw.TextAlign.center)]),
            pw.TableRow(children: [celdaValor('5. ¿Se encontró causa raíz?'), celdaLabel(q5, align: pw.TextAlign.center)]),
            pw.TableRow(children: [celdaValor('6. ¿Se proponen acciones de eliminación de la causa raíz?'), celdaLabel(q6, align: pw.TextAlign.center)]),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1)},
          children: [
            pw.TableRow(
              children: [
                celdaLabel('Calificación Obtenida:'),
                celdaLabel(calificacion, colorTexto: estadoEval == 'APTO' ? PdfColors.green800 : (estadoEval == 'NO APTO' ? PdfColors.red800 : PdfColors.black)),
                celdaLabel('Estado Final:'),
                celdaLabel(displayEstadoEval, colorTexto: estadoEval == 'APTO' ? PdfColors.green800 : (estadoEval == 'NO APTO' ? PdfColors.red800 : PdfColors.black)),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          children: [
            pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Observación Evaluador (1ra Revisión):', style: boldStyle))]),
            pw.TableRow(children: [pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obsEval, style: regularStyle))]),
          ],
        ),
        if (resultado2.isNotEmpty && resultado2 != 'No aplica') ...[
          pw.SizedBox(height: 15),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            children: [pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('SEGUNDA REVISIÓN (DEFINITIVA)', style: boldStyle))])],
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: {0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1)},
            children: [
              pw.TableRow(children: [celdaValor('1. ¿Se cumple con el flujo de resolución de problemas (participación adecuada)?'), celdaLabel(row['cumple_flujo_resolucion_2']?.toString() ?? '-', align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('2. ¿La resolución se llevó a cabo con la primera línea (operadores y técnicos)?'), celdaLabel(row['resolucion_primera_linea_2']?.toString() ?? '-', align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('3. ¿La secuencia de la resolución de problema tiene sentido?'), celdaLabel(row['secuencia_tiene_sentido_2']?.toString() ?? '-', align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('4. ¿Todos los porqués cuentan con evidencia?'), celdaLabel(row['porques_con_evidencia_2']?.toString() ?? '-', align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('5. ¿Se encontró causa raíz?'), celdaLabel(row['encontro_causa_raiz_2']?.toString() ?? '-', align: pw.TextAlign.center)]),
            ],
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.5)},
            children: [
              pw.TableRow(
                children: [
                  celdaLabel('Resultado 2:'),
                  celdaLabel(resultado2, colorTexto: PdfColors.blue800),
                  celdaLabel('Última Aprobación:'),
                  celdaLabel(ultimaAprovacion, colorTexto: ultimaAprovacion == 'APROBADO' || ultimaAprovacion == 'APTO' ? PdfColors.green800 : (ultimaAprovacion == 'NO APROBADO' || ultimaAprovacion == 'NO APTO' ? PdfColors.red800 : PdfColors.orange800)),
                ],
              ),
            ],
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            children: [
              pw.TableRow(children: [pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Observación 2 (2da Revisión):', style: boldStyle))]),
              pw.TableRow(children: [pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obs2, style: regularStyle))]),
            ],
          ),
        ],
      ],
    ];
  }

  Future<void> _generarYDescargarPDF(Map<String, dynamic> row) async {
    setState(() => _generandoPdf = true);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      Map<String, pw.ImageProvider> imagenesListas = await _preDecodificarImagenes(row);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) => _construirPaginasPdf(row, imgLogo, imagenesListas),
        ),
      );

      final bytesPdf = await doc.save();
      String areaNom = (row['area']?.toString() ?? 'General').replaceAll(' ', '_');
      String fecha = row['fecha']?.toString().split('T')[0] ?? '-';

      await Printing.sharePdf(
        bytes: bytesPdf,
        filename: 'Reporte_5Why_${fecha}_$areaNom.pdf',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e')));
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }
}

// Función global top-level para el compute de compresión a <= 30KB
Uint8List _compressImage30KB(Uint8List bytes) {
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  
  img.Image resized = decoded;
  if (decoded.width > 800) {
    resized = img.copyResize(decoded, width: 800);
  }
  
  int quality = 85;
  Uint8List result = img.encodeJpg(resized, quality: quality);
  
  // 30KB = 30720 bytes aprox. Bajar la calidad paulatinamente.
  while (result.length > 30720 && quality > 10) {
    quality -= 15;
    result = img.encodeJpg(resized, quality: quality);
  }
  return result;
}
