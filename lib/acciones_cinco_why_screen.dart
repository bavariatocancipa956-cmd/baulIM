import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:convert';
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
  final String tipoAccion;
  final String descripcion;
  final String responsable;
  final String fechaCierre;
  final String estado;
  final String? urlEvidencia;

  AccionVisual({
    required this.id5Why,
    required this.numeroAccion,
    required this.fecha,
    required this.area,
    required this.pi,
    required this.tipoAccion,
    required this.descripcion,
    required this.responsable,
    required this.fechaCierre,
    required this.estado,
    this.urlEvidencia,
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

  // Valores seleccionados en filtros
  String? _filtroFecha;
  String _filtroEstado = 'Todos';
  String _filtroArea = 'Todas';
  String _filtroPi = 'Todos';

  // Anchos de columnas para la tabla custom
  final double wFecha = 100;
  final double wArea = 120;
  final double wPi = 140;
  final double wPdf = 60;
  final double wTipo = 130;
  final double wAccion = 320;
  final double wResponsable = 160;
  final double wFechaCierre = 110;
  final double wEstado = 100;
  final double wEvidencia = 120; // Nueva columna

  final BorderSide _bordeTabla = BorderSide(
    color: Colors.grey.shade300,
    width: 1,
  );

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

      for (var row in data) {
        int id = row['id'];
        String fechaFormat = _formatearFecha(row['fecha']);
        String pi = row['pi']?.toString().trim() ?? 'N/A';
        String area = row['area']?.toString().trim() ?? 'N/A';

        if (area != 'N/A') areasUnicas.add(area);
        if (pi != 'N/A') pisUnicos.add(pi);

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
                tipoAccion: tipoAccion,
                descripcion: row['descripcion_$i'] ?? 'Sin descripción',
                responsable: (row['responsable_$i'] ?? 'SIN ASIGNAR')
                    .toString()
                    .toUpperCase(),
                fechaCierre: _formatearFecha(row['fecha_cierre_$i']),
                estado: row['estado_accion$i'] ?? 'Pendiente',
                urlEvidencia: row['evidencia_accion_$i']?.toString(),
              ),
            );
          }
        }
      }

      _listaAreas = areasUnicas.toList()..sort();
      _listaPis = pisUnicos.toList()..sort();
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

      return coincideFecha && coincideEstado && coincideArea && coincidePi;
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

    return Row(
      children: [
        Expanded(child: _buildKPI('TOTAL ACCIONES', total.toString(), Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _buildKPI('CONCLUIDAS', concluidas.toString(), Colors.green)),
        const SizedBox(width: 12),
        Expanded(child: _buildKPI('PENDIENTES', pendientes.toString(), Colors.orange)),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTablaResumen('Acciones por Área', _agruparPorArea())),
              const SizedBox(width: 20),
              Expanded(child: _buildTablaResumen('Acciones por PI', _agruparPorPI())),
            ],
          );
        }
        return Column(
          children: [
            _buildTablaResumen('Acciones por Área', _agruparPorArea()),
            const SizedBox(height: 20),
            _buildTablaResumen('Acciones por PI', _agruparPorPI()),
          ],
        );
      },
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

  Map<String, Map<String, int>> _agruparPorPI() {
    Map<String, Map<String, int>> map = {};
    for (var a in _accionesFiltradas) {
      String pi = a.pi.toUpperCase();
      map.putIfAbsent(pi, () => {'total': 0, 'concluidas': 0});
      map[pi]!['total'] = map[pi]!['total']! + 1;
      if (a.estado.toLowerCase() == 'concluida') {
        map[pi]!['concluidas'] = map[pi]!['concluidas']! + 1;
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                const Row(
                  children: [
                    Expanded(flex: 3, child: Text('CATEGORÍA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54))),
                    Expanded(child: Text('TOTAL', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54))),
                    Expanded(child: Text('CONCLUIDAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54))),
                    Expanded(child: Text('% AVANCE', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54))),
                  ],
                ),
                const Divider(),
                ...filas.map((e) {
                  double pct = e.value['total']! == 0 ? 0 : (e.value['concluidas']! / e.value['total']!) * 100;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                        Expanded(child: Text(e.value['total'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                        Expanded(child: Text(e.value['concluidas'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.green))),
                        Expanded(child: Text('${pct.toStringAsFixed(1)}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                }),
              ],
            ),
          )
        ],
      ),
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
          const SizedBox(width: 12),
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
          const SizedBox(width: 12),
          Expanded(
            child: _buildFiltroDropdown('PI', _filtroPi, _listaPis, (v) {
              setState(() => _filtroPi = v!);
              _aplicarFiltros();
            }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildFiltroDropdown('Área', _filtroArea, _listaAreas, (v) {
              setState(() => _filtroArea = v!);
              _aplicarFiltros();
            }),
          ),
          const SizedBox(width: 12),
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
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 38,
          child: DropdownButtonFormField<String>(
            initialValue: opciones.contains(valor) ? valor : opciones.first,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
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
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
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

    double totalWidth = wFecha + wArea + wPi + wPdf + wTipo + wAccion + wResponsable + wFechaCierre + wEstado + wEvidencia;

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
                  children: _accionesAgrupadas.entries.map(
                    (entry) => _buildFilaAgrupada(entry.value),
                  ).toList(),
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
        _buildCeldaCabecera('PDF', wPdf),
        _buildCeldaCabecera('TIPO DE ACCIÓN', wTipo),
        _buildCeldaCabecera('ACCIÓN', wAccion, align: Alignment.centerLeft),
        _buildCeldaCabecera('RESPONSABLE', wResponsable),
        _buildCeldaCabecera('FECHA CIERRE', wFechaCierre),
        _buildCeldaCabecera('ESTADO', wEstado),
        _buildCeldaCabecera('EVIDENCIA', wEvidencia),
      ],
    );
  }

  Widget _buildFilaAgrupada(List<AccionVisual> grupo) {
    AccionVisual primera = grupo.first;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCeldaAgrupada(
            Text(
              primera.fecha,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
            wFecha,
          ),
          _buildCeldaAgrupada(
            Text(
              primera.area,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
            wArea,
          ),
          _buildCeldaAgrupada(
            Text(
              primera.pi,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.bold),
            ),
            wPi,
          ),
          _buildCeldaAgrupada(
            const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFEF4444),
              size: 20,
            ),
            wPdf,
          ),
          SizedBox(
            width: wTipo + wAccion + wResponsable + wFechaCierre + wEstado + wEvidencia,
            child: Column(
              children: grupo.asMap().entries.map((entry) {
                return _buildFilaAccion(entry.value, isLast: entry.key == grupo.length - 1);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilaAccion(AccionVisual accion, {required bool isLast}) {
    bool completado = accion.estado.toLowerCase() == 'concluida';

    return Row(
      children: [
        _buildCeldaCuerpo(
          Text(
            accion.tipoAccion,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
          ),
          wTipo,
          isLast: isLast,
        ),
        _buildCeldaCuerpo(
          Text(
            accion.descripcion,
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          wAccion,
          align: Alignment.centerLeft,
          isLast: isLast,
        ),
        _buildCeldaCuerpo(
          Text(
            accion.responsable,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
          ),
          wResponsable,
          isLast: isLast,
        ),
        _buildCeldaCuerpo(
          Text(
            accion.fechaCierre,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
          ),
          wFechaCierre,
          isLast: isLast,
        ),
        _buildCeldaCuerpo(
          _buildBadgeEstado(accion.estado.toUpperCase(), completado),
          wEstado,
          isLast: isLast,
        ),
        _buildCeldaCuerpo(
          _buildEvidenciaWidget(accion),
          wEvidencia,
          isLast: isLast,
        ),
      ],
    );
  }

  Widget _buildCeldaCabecera(
    String texto,
    double width, {
    Alignment align = Alignment.center,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9), // Un gris azulado claro profesional
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 2),
          right: BorderSide(color: Color(0xFFE2E8F0), width: 1), // Borde derecho para Excel feel
        ), 
      ),
      alignment: align,
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF334155), 
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCeldaAgrupada(
    Widget hijo,
    double width,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1), 
          right: BorderSide(color: Color(0xFFE2E8F0), width: 1), // Separador vertical de grupos
        ), 
      ),
      alignment: Alignment.center,
      child: hijo,
    );
  }

  Widget _buildCeldaCuerpo(
    Widget hijo,
    double width, {
    Alignment align = Alignment.center,
    required bool isLast,
  }) {
    BorderSide borderBottom = isLast 
        ? const BorderSide(color: Color(0xFFE2E8F0), width: 1) 
        : const BorderSide(color: Color(0xFFF8FAFC), width: 1); 

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: borderBottom,
          right: const BorderSide(color: Color(0xFFF1F5F9), width: 1), // Separador vertical tenue
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
      return Row(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(width: 4),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
