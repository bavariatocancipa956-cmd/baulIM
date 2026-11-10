import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_service.dart';

// --- CLASE AUXILIAR PARA LA EDICIÓN DE ACCIONES ---
class AccionEditItem {
  String? tipoAccion;
  String? actividadSeleccionada;
  final TextEditingController actividadCtrl = TextEditingController();
  final TextEditingController descripcionCtrl = TextEditingController();
  final TextEditingController responsableCtrl = TextEditingController();
  DateTime? fechaCierre;
  String estado = 'Pendiente';

  void dispose() {
    actividadCtrl.dispose();
    descripcionCtrl.dispose();
    responsableCtrl.dispose();
  }
}

// Motor de compresión para nuevas imágenes subidas durante la edición
Uint8List comprimirImagenWorker(Uint8List bytes) {
  img.Image? decodedImage = img.decodeImage(bytes);
  if (decodedImage == null) return bytes;
  img.Image resized = decodedImage;
  if (decodedImage.width > 600) {
    resized = img.copyResize(decodedImage, width: 600);
  }
  int quality = 85;
  Uint8List result = img.encodeJpg(resized, quality: quality);
  while (result.length > 51200 && quality > 5) {
    quality -= 15;
    result = img.encodeJpg(resized, quality: quality);
  }
  return result;
}

class HistorialCincoWhyScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onToggleSidebar;

  const HistorialCincoWhyScreen({
    super.key,
    required this.usuario,
    required this.onToggleSidebar,
  });

  @override
  State<HistorialCincoWhyScreen> createState() =>
      _HistorialCincoWhyScreenState();
}

class _HistorialCincoWhyScreenState extends State<HistorialCincoWhyScreen> {
  // --- CONSTANTES DE DISEÑO EJECUTIVO ---
  final Color _colorBackground = const Color(0xFFF1F5F9);
  final Color _colorPrincipal = const Color(0xFFF36F21);
  final Color _colorEncabezados = const Color(0xFF1E293B);
  final Color _colorTextoOscuro = const Color(0xFF334155);

  final List<BoxShadow> _sombraCards = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  final ScrollController _tablaScrollController = ScrollController();
  bool _cargando = true;
  String? _mensajeError;
  String? _idGenerandoPdf;
  bool _generandoMultiplesPdf = false;

  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];
  final Set<String> _seleccionados = {};

  // --- FILTROS AMPLIADOS ---
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _filtroArea = 'Todas';
  String _filtroEstado = 'Todos';
  String _filtroPI = 'Todos';
  String _filtroSupervisor = 'Todos';
  String _filtroInterventor = 'Todos';

  List<String> _listaFiltroArea = ['Todas'];
  final List<String> _listaFiltroEstado = ['Todos', 'Pendiente', 'Concluido'];
  List<String> _listaFiltroPI = ['Todos'];
  List<String> _listaFiltroSupervisor = ['Todos'];
  List<String> _listaFiltroInterventor = ['Todos'];

  int _registrosPorPagina = 10;
  int _paginaActual = 1;

  final ImagePicker _picker = ImagePicker();

  static const Map<String, String> _criteriosAdherencia = {
    'cumple_flujo_resolucion': 'Flujo de resolución de problemas',
    'resolucion_primera_linea': 'Resolución con la primera línea',
    'secuencia_tiene_sentido': 'Secuencia lógica de la resolución',
    'porques_con_evidencia': 'Porqués respaldados con evidencia',
    'encontro_causa_raiz': 'Causa raíz encontrada',
    'proponen_acciones_eliminacion': 'Acciones para eliminar la causa raíz',
  };

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
      _seleccionados.clear();
    });

    try {
      final data = await ApiService.consultar('gestion', '5why');
      List<Map<String, dynamic>> datosProcesados = [];
      if (data != null && data is List) {
        datosProcesados = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      datosProcesados.sort((a, b) {
        DateTime dateA = DateTime.tryParse(a['fecha']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        DateTime dateB = DateTime.tryParse(b['fecha']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

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
    Set<String> areas = {'Todas'};
    Set<String> pis = {'Todos'};
    Set<String> supervisores = {'Todos'};
    Set<String> interventores = {'Todos'};

    for (var r in _registros) {
      String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
      String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();
      String sup = (r['supervisor']?.toString() ?? '').trim().toUpperCase();
      String inv = (r['interventor']?.toString() ?? '').trim().toUpperCase();

      if (ar.isNotEmpty && ar != 'NULL') areas.add(ar);
      if (pi.isNotEmpty && pi != 'NULL') pis.add(pi);
      if (sup.isNotEmpty && sup != 'NULL') supervisores.add(sup);
      if (inv.isNotEmpty && inv != 'NULL') interventores.add(inv);
    }

    _listaFiltroArea = areas.toList()..sort();
    _listaFiltroPI = pis.toList()..sort();
    _listaFiltroSupervisor = supervisores.toList()..sort();
    _listaFiltroInterventor = interventores.toList()..sort();
  }

  void _aplicarFiltros() {
    setState(() {
      _registrosFiltrados = _registros.where((r) {
        String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
        String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();
        String sup = (r['supervisor']?.toString() ?? '').trim().toUpperCase();
        String inv = (r['interventor']?.toString() ?? '').trim().toUpperCase();

        if (_filtroArea != 'Todas' && ar != _filtroArea) return false;
        if (_filtroPI != 'Todos' && pi != _filtroPI) return false;
        if (_filtroSupervisor != 'Todos' && sup != _filtroSupervisor)
          return false;
        if (_filtroInterventor != 'Todos' && inv != _filtroInterventor)
          return false;

        if (_filtroEstado != 'Todos') {
          bool coincideEstado = false;
          for (int i = 1; i <= 4; i++) {
            String est = (r['estado_accion$i']?.toString() ?? '')
                .trim()
                .toUpperCase();
            if (est == _filtroEstado.toUpperCase()) {
              coincideEstado = true;
              break;
            }
          }
          if (!coincideEstado) return false;
        }

        if (_fechaDesde != null || _fechaHasta != null) {
          try {
            final fStr = r['fecha']?.toString() ?? '';
            if (fStr.isNotEmpty && fStr != 'NULL') {
              final f = DateTime.parse(fStr);
              if (_fechaDesde != null && f.isBefore(_fechaDesde!)) return false;
              if (_fechaHasta != null && f.isAfter(_fechaHasta!.add(const Duration(days: 1)))) return false;
            }
          } catch(e) {}
        }

        return true;
      }).toList();

      _paginaActual = 1;
      _seleccionados.clear();
    });
  }

  void _limpiarFiltros() {
    setState(() {
      _fechaDesde = null;
      _fechaHasta = null;
      _filtroArea = 'Todas';
      _filtroEstado = 'Todos';
      _filtroPI = 'Todos';
      _filtroSupervisor = 'Todos';
      _filtroInterventor = 'Todos';
      _aplicarFiltros();
    });
  }

  void _toggleSeleccion(String id) {
    setState(() {
      if (_seleccionados.contains(id)) {
        _seleccionados.remove(id);
      } else {
        _seleccionados.add(id);
      }
    });
  }

  void _toggleSeleccionarTodos(List<Map<String, dynamic>> pagina) {
    setState(() {
      bool todosSeleccionados = pagina.every(
        (r) => _seleccionados.contains(r['id'].toString()),
      );
      if (todosSeleccionados) {
        for (var r in pagina) {
          _seleccionados.remove(r['id'].toString());
        }
      } else {
        for (var r in pagina) {
          _seleccionados.add(r['id'].toString());
        }
      }
    });
  }

  String _estadoEvaluacion(Map<String, dynamic> registro) {
    final estado = (registro['estado']?.toString() ?? '').trim().toUpperCase();
    final aprobacion =
        (registro['ultima_aprovacion']?.toString() ??
                registro['ultima aprovacion']?.toString() ??
                '')
            .trim()
            .toUpperCase();

    if (aprobacion == 'APROBADO' || aprobacion == 'APTO') return 'APTO';
    if (aprobacion == 'NO APROBADO' || aprobacion == 'NO APTO') {
      return 'NO APTO';
    }
    if (aprobacion == 'VOLVER A REVISAR' ||
        aprobacion == 'PENDIENTE POR REVISIÓN' ||
        aprobacion == 'PENDIENTE POR REVISION') {
      return 'PENDIENTE';
    }
    if (estado == 'APTO' || estado == 'NO APTO') return estado;
    return 'PENDIENTE';
  }

  double? _calificacionNumerica(Map<String, dynamic> registro) {
    final raw = registro['resultado']?.toString().trim();
    if (raw == null || raw.isEmpty || raw.toUpperCase() == 'NULL') return null;
    return double.tryParse(raw.replaceAll('%', '').replaceAll(',', '.'));
  }

  List<MapEntry<String, double>> _adherenciaPorCriterio(
    List<Map<String, dynamic>> revisados,
  ) {
    return _criteriosAdherencia.entries.map((criterio) {
      final respuestasSi = revisados
          .where(
            (registro) =>
                (registro[criterio.key]?.toString() ?? '')
                    .trim()
                    .toUpperCase() ==
                'SI',
          )
          .length;
      final porcentaje = revisados.isEmpty
          ? 0.0
          : respuestasSi / revisados.length * 100;
      return MapEntry(criterio.key, porcentaje);
    }).toList();
  }

  Widget _buildDashboardHistorial() {
    final registros = _registrosFiltrados;
    final aptos = registros
        .where((registro) => _estadoEvaluacion(registro) == 'APTO')
        .length;
    final noAptos = registros
        .where((registro) => _estadoEvaluacion(registro) == 'NO APTO')
        .length;
    final pendientes = registros
        .where((registro) => _estadoEvaluacion(registro) == 'PENDIENTE')
        .length;
    final revisados = registros
        .where((registro) => _estadoEvaluacion(registro) != 'PENDIENTE')
        .toList();
    final adherencia = _adherenciaPorCriterio(revisados);
    final adherenciaGlobal = adherencia.isEmpty
        ? 0.0
        : adherencia.fold<double>(0, (total, item) => total + item.value) /
              adherencia.length;



    final indicadores = [
      _buildTarjetaIndicador(
        titulo: 'TOTAL EVENTOS',
        valor: '${registros.length}',
        color: const Color(0xFF0D6EFD), // Blue
      ),
      _buildTarjetaIndicador(
        titulo: 'REVISADOS',
        valor: '${aptos + noAptos}',
        color: const Color(0xFF0DCAF0), // Cyan
      ),
      _buildTarjetaIndicador(
        titulo: 'APTOS',
        valor: '$aptos',
        color: const Color(0xFF198754), // Green
      ),
      _buildTarjetaIndicador(
        titulo: 'NO APTOS',
        valor: '$noAptos',
        color: const Color(0xFFDC3545), // Red
      ),
      _buildTarjetaIndicador(
        titulo: 'PENDIENTES',
        valor: '$pendientes',
        color: const Color(0xFFFD7E14), // Orange
      ),
      _buildTarjetaIndicador(
        titulo: 'ADHERENCIA GLOBAL',
        valor: '${adherenciaGlobal.toStringAsFixed(1)}%',
        color: const Color(0xFF6F42C1), // Purple
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final isWide = availableWidth >= 900;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: indicadores.map((e) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: e == indicadores.last ? 0 : 12),
                    child: e,
                  ),
                )).toList(),
              );
            } else {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: indicadores.map((e) => SizedBox(width: (availableWidth / 2) - 6, child: e)).toList(),
              );
            }
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (isWide) {
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildCardBase(
                          titulo: '5 Why por PI Afectado',
                          child: _buildTablaDistribucion(registros, campo: 'pi', encabezado: 'PI AFECTADO'),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildCardBase(
                          titulo: '5 Why por Área',
                          child: _buildTablaDistribucion(registros, campo: 'area', encabezado: 'ÁREA'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildCardBase(
                          titulo: '5 Why por Supervisor',
                          child: _buildTablaPorSupervisor(registros),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildCardBase(
                          titulo: 'Revisión por Interventor',
                          child: _buildTablaInterventores(registros),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Column(
              children: [
                _buildCardBase(
                  titulo: '5 Why por PI Afectado',
                  child: _buildTablaDistribucion(registros, campo: 'pi', encabezado: 'PI AFECTADO'),
                ),
                const SizedBox(height: 20),
                _buildCardBase(
                  titulo: '5 Why por Área',
                  child: _buildTablaDistribucion(registros, campo: 'area', encabezado: 'ÁREA'),
                ),
                const SizedBox(height: 20),
                _buildCardBase(
                  titulo: '5 Why por Supervisor',
                  child: _buildTablaPorSupervisor(registros),
                ),
                const SizedBox(height: 20),
                _buildCardBase(
                  titulo: 'Revisión por Interventor',
                  child: _buildTablaInterventores(registros),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTarjetaIndicador({
    required String titulo,
    required String valor,
    required Color color,
  }) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: _sombraCards,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTablaDistribucion(
    List<Map<String, dynamic>> registros, {
    required String campo,
    required String encabezado,
  }) {
    if (registros.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No hay registros para mostrar con los filtros actuales.',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      );
    }

    final resumen = <String, Map<String, dynamic>>{};
    for (final registro in registros) {
      var nombre = registro[campo]?.toString().trim() ?? '';
      if (nombre.isEmpty || nombre.toUpperCase() == 'NULL') {
        nombre = 'SIN DEFINIR';
      } else {
        nombre = nombre.toUpperCase();
        if (campo == 'area' && (nombre.startsWith('LINEA') || nombre.startsWith('LÍNEA'))) {
          nombre = 'LINEAS';
        }
      }

      final fila = resumen.putIfAbsent(
        nombre,
        () => {
          'total': 0,
          'realizadas': 0,
          'pendientes': 0,
        },
      );
      fila['total'] = (fila['total'] as int) + 1;

      final estado = _estadoEvaluacion(registro);
      if (estado != 'PENDIENTE') {
        fila['realizadas'] = (fila['realizadas'] as int) + 1;
      } else {
        fila['pendientes'] = (fila['pendientes'] as int) + 1;
      }
    }

    final filas = resumen.entries.toList()
      ..sort(
        (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
      );

    if (filas.length > 5) {
      filas.removeRange(5, filas.length);
    }

    final total = registros.length;
    final totalRealizadas = registros
        .where((registro) => _estadoEvaluacion(registro) != 'PENDIENTE')
        .length;
    final totalPendientes = registros
        .where((registro) => _estadoEvaluacion(registro) == 'PENDIENTE')
        .length;

    String calcularAvance(int realizadas, int total) {
      if (total == 0) return '0.0%';
      return '${(realizadas / total * 100).toStringAsFixed(1)}%';
    }

    final totalDatos = <String, dynamic>{
      'total': total,
      'realizadas': totalRealizadas,
      'pendientes': totalPendientes,
    };

    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text(encabezado, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('REALIZADAS', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('PENDIENTES', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('AVANCE', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        Container(
          height: 250,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.grey.shade200),
              right: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: filas.length + 1,
              itemBuilder: (context, index) {
                bool esTotal = index == filas.length;
                var datos = esTotal ? totalDatos : filas[index].value;
                String nombre = esTotal ? 'TOTAL GENERAL' : filas[index].key;

                final avanceStr = calcularAvance(datos['realizadas'] as int, datos['total'] as int);
                final estiloTotal = esTotal ? const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E293B), fontSize: 11) : const TextStyle(color: Color(0xFF334155), fontSize: 11);

                return Container(
                  color: esTotal ? const Color(0xFFEFF6FF) : (index.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(nombre, style: estiloTotal)),
                      Expanded(flex: 2, child: Text('${datos['total']}', textAlign: TextAlign.center, style: estiloTotal)),
                      Expanded(flex: 2, child: Text('${datos['realizadas']}', textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('${datos['pendientes']}', textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text(avanceStr, textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTablaInterventores(List<Map<String, dynamic>> registros) {
    return _buildTablaResumenPersonas(
      registros,
      campo: 'interventor',
      encabezado: 'INTERVENTOR',
      incluirAdherencia: false,
    );
  }

  Widget _buildTablaPorSupervisor(List<Map<String, dynamic>> registros) {
    return _buildTablaResumenPersonas(
      registros,
      campo: 'supervisor',
      encabezado: 'SUPERVISOR',
      incluirAdherencia: true,
    );
  }

  Map<String, Map<String, dynamic>> _agruparPorPersona(
    List<Map<String, dynamic>> registros,
    String campo,
  ) {
    final resumen = <String, Map<String, dynamic>>{};
    for (final registro in registros) {
      var nombre = registro[campo]?.toString().trim() ?? '';
      if (nombre.isEmpty || nombre.toUpperCase() == 'NULL') {
        nombre = 'SIN ${campo == 'supervisor' ? 'SUPERVISOR' : 'INTERVENTOR'}';
      } else {
        nombre = nombre.toUpperCase();
      }

      final fila = resumen.putIfAbsent(
        nombre,
        () => {
          'total': 0,
          'revisados': 0,
          'aptos': 0,
          'noAptos': 0,
          'pendientes': 0,
          'respuestasSi': 0,
          'sumaCalificacion': 0.0,
          'calificaciones': 0,
        },
      );
      fila['total'] = (fila['total'] as int) + 1;

      final estado = _estadoEvaluacion(registro);
      if (estado == 'APTO') {
        fila['aptos'] = (fila['aptos'] as int) + 1;
        fila['revisados'] = (fila['revisados'] as int) + 1;
      } else if (estado == 'NO APTO') {
        fila['noAptos'] = (fila['noAptos'] as int) + 1;
        fila['revisados'] = (fila['revisados'] as int) + 1;
      } else {
        fila['pendientes'] = (fila['pendientes'] as int) + 1;
      }

      if (estado != 'PENDIENTE') {
        for (final criterio in _criteriosAdherencia.keys) {
          if ((registro[criterio]?.toString() ?? '').trim().toUpperCase() ==
              'SI') {
            fila['respuestasSi'] = (fila['respuestasSi'] as int) + 1;
          }
        }
      }

      final score = _calificacionNumerica(registro);
      if (score != null) {
        fila['sumaCalificacion'] = (fila['sumaCalificacion'] as double) + score;
        fila['calificaciones'] = (fila['calificaciones'] as int) + 1;
      }
    }
    return resumen;
  }

  Widget _buildTablaResumenPersonas(
    List<Map<String, dynamic>> registros, {
    required String campo,
    required String encabezado,
    required bool incluirAdherencia,
  }) {
    if (registros.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No hay registros para mostrar con los filtros actuales.',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      );
    }

    final resumen = _agruparPorPersona(registros, campo);
    final filas = resumen.entries.toList()
      ..sort(
        (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
      );

    if (filas.length > 5) {
      filas.removeRange(5, filas.length);
    }

    final total = registros.length;
    final totalAptos = registros
        .where((registro) => _estadoEvaluacion(registro) == 'APTO')
        .length;
    final totalNoAptos = registros
        .where((registro) => _estadoEvaluacion(registro) == 'NO APTO')
        .length;
    final totalPendientes = registros
        .where((registro) => _estadoEvaluacion(registro) == 'PENDIENTE')
        .length;
    final totalRevisados = totalAptos + totalNoAptos;

    String porcentajeAdherencia(Map<String, dynamic> datos) {
      final denominador =
          (datos['revisados'] as int) * _criteriosAdherencia.length;
      if (denominador == 0) return '—';
      final porcentaje = (datos['respuestasSi'] as int) / denominador * 100;
      return '${porcentaje.toStringAsFixed(1)}%';
    }

    String promedioCalificacion(Map<String, dynamic> datos) {
      final cantidad = datos['calificaciones'] as int;
      if (cantidad == 0) return '—';
      final promedio = (datos['sumaCalificacion'] as double) / cantidad;
      return '${promedio.toStringAsFixed(1)}%';
    }

    final totalDatos = <String, dynamic>{
      'total': total,
      'revisados': totalRevisados,
      'aptos': totalAptos,
      'noAptos': totalNoAptos,
      'pendientes': totalPendientes,
      'respuestasSi': filas.fold<int>(
        0,
        (sum, fila) => sum + (fila.value['respuestasSi'] as int),
      ),
      'sumaCalificacion': filas.fold<double>(
        0,
        (sum, fila) => sum + (fila.value['sumaCalificacion'] as double),
      ),
      'calificaciones': filas.fold<int>(
        0,
        (sum, fila) => sum + (fila.value['calificaciones'] as int),
      ),
    };

    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text(encabezado, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(incluirAdherencia ? 'TOTAL 5 WHY' : 'REPORTES', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('REVISADOS', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('PENDIENTES', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('APTOS', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('NO APTOS', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text(incluirAdherencia ? 'ADHERENCIA' : 'CALIF. PROM.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        Container(
          height: 250,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.grey.shade200),
              right: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: filas.length + 1,
              itemBuilder: (context, index) {
                bool esTotal = index == filas.length;
                var datos = esTotal ? totalDatos : filas[index].value;
                String nombre = esTotal ? 'TOTAL GENERAL' : filas[index].key;

                final valorFinal = incluirAdherencia ? porcentajeAdherencia(datos) : promedioCalificacion(datos);
                final estiloTotal = esTotal ? const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E293B), fontSize: 11) : const TextStyle(color: Color(0xFF334155), fontSize: 11);

                return Container(
                  color: esTotal ? const Color(0xFFEFF6FF) : (index.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(nombre, style: estiloTotal)),
                      Expanded(flex: 2, child: Text('${datos['total']}', textAlign: TextAlign.center, style: estiloTotal)),
                      Expanded(flex: 2, child: Text('${datos['revisados']}', textAlign: TextAlign.center, style: estiloTotal)),
                      Expanded(flex: 2, child: Text('${datos['pendientes']}', textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('${datos['aptos']}', textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('${datos['noAptos']}', textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text(valorFinal, textAlign: TextAlign.center, style: esTotal ? estiloTotal : const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _descargarExcel() async {
    try {
      String csv =
          "ID;Fecha;Area;PI Afectado;Supervisor;Interventor;Participantes;"
          "Valor Disparador;Causa Raiz Encontrada;Descripcion Causa Raiz;"
          "Req. Investigacion Adicional;Estado Evaluacion;Observacion Evaluador;"
          "Estado Acciones;Resultado 2;Observacion 2;Ultima Aprobacion\n";

      String sanitize(String val) =>
          val.replaceAll('\n', ' ').replaceAll('\r', '').replaceAll(';', ',');

      for (var r in _registrosFiltrados) {
        String id = sanitize(r['id']?.toString() ?? '');
        String f = sanitize(r['fecha']?.toString().split('T')[0] ?? '');
        String a = sanitize(r['area']?.toString() ?? '');
        String p = sanitize(r['pi']?.toString() ?? '');
        String sup = sanitize(r['supervisor']?.toString() ?? '');
        String inv = sanitize(r['interventor']?.toString() ?? '');
        String part = sanitize(r['participantes']?.toString() ?? '');
        String disp = sanitize(
          r['valor_disparador_alcanzado']?.toString() ?? '',
        );
        String causa = sanitize(r['encontro_causa_raiz']?.toString() ?? '');
        String req = sanitize(
          r['requiere_investigacion_adicional']?.toString() ?? '',
        );
        String estEval = sanitize(r['estado']?.toString() ?? 'PENDIENTE');
        String obsEval = sanitize(r['observacion_evaluador']?.toString() ?? '');

        String causaRaizDesc = sanitize(
          r['causa_raiz']?.toString() ?? r['causa raiz']?.toString() ?? '',
        );
        String res2 = sanitize(r['resultado_2']?.toString() ?? '');
        String obs2 = sanitize(
          r['Observacion 2']?.toString() ??
              r['observacion_2']?.toString() ??
              '',
        );
        String ultAp = sanitize(
          r['ultima aprovacion']?.toString() ??
              r['ultima_aprovacion']?.toString() ??
              '',
        );

        int accionesCerradas = 0;
        int totalAcciones = 0;
        for (int i = 1; i <= 4; i++) {
          if ((r['accion_$i']?.toString() ?? '').isNotEmpty) {
            totalAcciones++;
            if ((r['estado_accion$i']?.toString() ?? '').toUpperCase() ==
                'CONCLUIDA') {
              accionesCerradas++;
            }
          }
        }
        String estadoAcc = "$accionesCerradas de $totalAcciones cerradas";
        csv +=
            "$id;$f;$a;$p;$sup;$inv;$part;$disp;$causa;$causaRaizDesc;"
            "$req;$estEval;$obsEval;$estadoAcc;$res2;$obs2;$ultAp\n";
      }

      List<int> bytes = [0xEF, 0xBB, 0xBF] + utf8.encode(csv);
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename:
            'Reporte_5Why_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel generado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _mostrarPreviewImagen(String dato, {required bool isBase64}) {
    String cleanData = dato;
    if (isBase64 && dato.contains('IMAGEN_ADJUNTA:')) {
      cleanData = dato.replaceAll('IMAGEN_ADJUNTA:', '').trim();
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Evidencia Fotográfica',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: isBase64
                        ? Image.memory(
                            base64Decode(cleanData),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Padding(
                              padding: EdgeInsets.all(30.0),
                              child: Text(
                                'Error al cargar imagen',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          )
                        : Image.network(
                            cleanData,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Padding(
                              padding: EdgeInsets.all(30.0),
                              child: Text(
                                'Enlace inválido',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirModalEdicion(Map<String, dynamic> row, bool soloLectura) {
    dynamic id = row['id'];

    String estadoActual = (row['estado']?.toString() ?? 'PENDIENTE')
        .toUpperCase();
    String calificacion = row['resultado']?.toString() ?? '0.0%';
    String obs1 =
        row['observacion_evaluador']?.toString() ?? 'Sin observaciones aún.';
    String resFinal =
        row['ultima aprovacion']?.toString() ??
        row['ultima_aprovacion']?.toString() ??
        'Pendiente';
    String obs2 =
        row['Observacion 2']?.toString() ??
        row['observacion_2']?.toString() ??
        'Sin observaciones de segunda revisión.';
    String estadoRevision = row['estado_revicion']?.toString() ?? '';

    DateTime fechaSelect =
        DateTime.tryParse(row['fecha']?.toString() ?? '') ?? DateTime.now();
    String turnoSelect = row['turno']?.toString() ?? 'T1';
    if (!['T1', 'T2', 'T3'].contains(turnoSelect)) turnoSelect = 'T1';

    TextEditingController areaCtrl = TextEditingController(
      text: row['area']?.toString(),
    );
    TextEditingController participantesCtrl = TextEditingController(
      text: row['participantes']?.toString(),
    );
    TextEditingController disparadorCtrl = TextEditingController(
      text: row['valor_disparador_alcanzado']?.toString(),
    );
    TextEditingController contencionCtrl = TextEditingController(
      text: row['contencion_problema']?.toString(),
    );
    TextEditingController causaRaizCtrl = TextEditingController(
      text:
          row['causa_raiz']?.toString() ?? row['causa raiz']?.toString() ?? '',
    );
    TextEditingController supervisorCtrl = TextEditingController(
      text: row['supervisor']?.toString(),
    );
    TextEditingController interventorCtrl = TextEditingController(
      text: row['interventor']?.toString(),
    );

    String? piSeleccionado = row['pi']?.toString();

    String reqInvestigacion =
        row['requiere_investigacion_adicional']?.toString().toUpperCase() ==
            'SI'
        ? 'SI'
        : 'NO';
    String encontroCausa =
        row['encontro_causa_raiz']?.toString().toUpperCase() == 'SI'
        ? 'SI'
        : 'NO';

    List<TextEditingController> pqCtrls = List.generate(
      5,
      (i) =>
          TextEditingController(text: row['porque_${i + 1}']?.toString() ?? ''),
    );
    List<TextEditingController> exCtrls = List.generate(
      5,
      (i) => TextEditingController(
        text: row['explique_porque_${i + 1}']?.toString() ?? '',
      ),
    );
    List<TextEditingController> evTextCtrls = [];

    List<String> evidenciasExistentesURL = List.generate(5, (_) => '');
    List<Uint8List?> nuevasEvidenciasBytes = List.filled(5, null);

    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      String textoPuro = rawEvidencia;
      String urlOBase64 = '';

      if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
        var parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
        textoPuro = parts[0].replaceAll('|', '').trim();
        urlOBase64 = 'IMAGEN_ADJUNTA:${parts[1].trim()}';
      } else if (rawEvidencia.contains('http')) {
        int httpIndex = rawEvidencia.indexOf('http');
        textoPuro = rawEvidencia
            .substring(0, httpIndex)
            .replaceAll('|', '')
            .trim();
        urlOBase64 = rawEvidencia.substring(httpIndex).trim();
      } else if (rawEvidencia.contains('data:image')) {
        int dataIndex = rawEvidencia.indexOf('data:image');
        textoPuro = rawEvidencia
            .substring(0, dataIndex)
            .replaceAll('|', '')
            .trim();
        urlOBase64 = rawEvidencia.substring(dataIndex).trim();
      }

      evTextCtrls.add(TextEditingController(text: textoPuro));
      evidenciasExistentesURL[i - 1] = urlOBase64;
    }

    List<AccionEditItem> accionesEditables = [];
    List<String> validActividades = [
      'DTO',
      'SLA',
      'Entrenamiento',
      'PIs',
      'Mapa de Procesos',
      'PM Plan',
      'Check List',
    ];

    for (int i = 1; i <= 4; i++) {
      String tipo = row['accion_$i']?.toString() ?? '';
      if (tipo.trim().isNotEmpty) {
        AccionEditItem accion = AccionEditItem();
        accion.tipoAccion = ['Preventiva', 'Correctiva'].contains(tipo)
            ? tipo
            : 'Correctiva';

        String actDb = row['actividad_$i']?.toString() ?? '';
        accion.actividadSeleccionada = validActividades.contains(actDb)
            ? actDb
            : null;

        accion.actividadCtrl.text = actDb;
        accion.descripcionCtrl.text = row['descripcion_$i']?.toString() ?? '';
        accion.responsableCtrl.text = row['responsable_$i']?.toString() ?? '';

        accion.estado = row['estado_accion$i']?.toString() ?? 'Pendiente';
        if (!['Pendiente', 'Concluida'].contains(accion.estado))
          accion.estado = 'Pendiente';

        String fechaC = row['fecha_cierre_$i']?.toString() ?? '';
        if (fechaC.isNotEmpty && fechaC != 'NULL') {
          accion.fechaCierre = DateTime.tryParse(fechaC);
        }
        accionesEditables.add(accion);
      }
    }
    if (accionesEditables.isEmpty) {
      accionesEditables.addAll([AccionEditItem(), AccionEditItem()]);
    }

    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            bool isMobile = MediaQuery.of(ctx).size.width < 700;

            Future<void> seleccionarNuevaImagen(int index) async {
              if (soloLectura) return;
              try {
                final XFile? image = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 15,
                  maxWidth: 400,
                  maxHeight: 400,
                );
                if (image != null) {
                  Uint8List bytes = await image.readAsBytes();
                  if (bytes.length > 51200)
                    bytes = await compute(comprimirImagenWorker, bytes);
                  if (bytes.length > 51200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Imagen demasiado compleja. Elija una más simple.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  setModalState(() => nuevasEvidenciasBytes[index] = bytes);
                }
              } catch (e) {
                debugPrint('Error imagen: $e');
              }
            }

            void agregarAccion() {
              if (soloLectura) return;
              if (accionesEditables.length < 4)
                setModalState(() => accionesEditables.add(AccionEditItem()));
            }

            void eliminarAccion(int index) {
              if (soloLectura) return;
              if (accionesEditables.length > 2) {
                setModalState(() {
                  accionesEditables[index].dispose();
                  accionesEditables.removeAt(index);
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Debe mantener al menos 2 acciones.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: const Color(0xFFF8FAFC),
              insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
              child: SizedBox(
                width: isMobile ? double.infinity : 900,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                soloLectura
                                    ? Icons.visibility
                                    : Icons.edit_note_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                soloLectura
                                    ? 'Detalle del Reporte'
                                    : 'Editar Reporte 5 Why',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: _sombraCards,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'RETROALIMENTACIÓN DEL REVISOR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _datoRowVisual(
                                          'Estado 1ra Rev:',
                                          estadoActual,
                                          isBold: true,
                                        ),
                                      ),
                                      Expanded(
                                        child: _datoRowVisual(
                                          'Calificación:',
                                          calificacion,
                                          isBold: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  _datoRowVisual('Observación 1:', obs1),
                                  const Divider(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _datoRowVisual(
                                          'Aprobación Final:',
                                          resFinal,
                                          isBold: true,
                                          color: const Color(0xFF00B4D8),
                                        ),
                                      ),
                                      Expanded(
                                        child: _datoRowVisual(
                                          'Estado Reenvío:',
                                          estadoRevision.isEmpty
                                              ? 'Ninguno'
                                              : estadoRevision,
                                          isBold: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  _datoRowVisual('Observación 2:', obs2),
                                  const Divider(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _datoRowVisual(
                                          'Supervisor:',
                                          row['supervisor']?.toString() ?? '-',
                                        ),
                                      ),
                                      Expanded(
                                        child: _datoRowVisual(
                                          'Interventor:',
                                          row['interventor']?.toString() ?? '-',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            if (soloLectura)
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Reporte aprobado (Solo lectura).',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            Text(
                              soloLectura
                                  ? 'FORMULARIO (SOLO LECTURA)'
                                  : 'FORMULARIO DE EDICIÓN',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 16),

                            _seccionSubtitulo(
                              '1. Información General',
                              Icons.feed_rounded,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Fecha',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: soloLectura
                                            ? null
                                            : () async {
                                                DateTime? p =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate: fechaSelect,
                                                      firstDate: DateTime(2020),
                                                      lastDate: DateTime(2101),
                                                    );
                                                if (p != null)
                                                  setModalState(
                                                    () => fechaSelect = p,
                                                  );
                                              },
                                        child: Container(
                                          height: 35,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.grey.shade300,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            color: soloLectura
                                                ? const Color(0xFFF8FAFC)
                                                : Colors.white,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                DateFormat(
                                                  'yyyy-MM-dd',
                                                ).format(fechaSelect),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: soloLectura
                                                      ? Colors.black54
                                                      : Colors.black87,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.calendar_today,
                                                size: 14,
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Turno',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 35,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          color: soloLectura
                                              ? const Color(0xFFF8FAFC)
                                              : Colors.white,
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: turnoSelect,
                                            isExpanded: true,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: soloLectura
                                                  ? Colors.black54
                                                  : Colors.black87,
                                            ),
                                            items: ['T1', 'T2', 'T3']
                                                .map(
                                                  (e) => DropdownMenuItem(
                                                    value: e,
                                                    child: Text(e),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: soloLectura
                                                ? null
                                                : (v) => setModalState(
                                                    () => turnoSelect = v!,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInputTextField(
                                    'Área / Proceso',
                                    areaCtrl,
                                    readOnly: soloLectura,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInputTextField(
                              'Participantes',
                              participantesCtrl,
                              readOnly: soloLectura,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInputTextField(
                                    'Supervisor',
                                    supervisorCtrl,
                                    readOnly: soloLectura,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildInputTextField(
                                    'Interventor',
                                    interventorCtrl,
                                    readOnly: soloLectura,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            _seccionSubtitulo(
                              '2. Disparador y Contención',
                              Icons.warning_rounded,
                            ),
                            _buildInputTextField(
                              'Valor del Disparador Alcanzado',
                              disparadorCtrl,
                              readOnly: soloLectura,
                            ),
                            const SizedBox(height: 12),
                            _buildInputTextField(
                              '¿Qué se hizo para contener el problema?',
                              contencionCtrl,
                              maxLines: 2,
                              readOnly: soloLectura,
                            ),

                            const SizedBox(height: 24),
                            _seccionSubtitulo(
                              '3. Análisis de Causa Raíz (5W)',
                              Icons.account_tree_rounded,
                            ),
                            ...List.generate(5, (index) {
                              bool tieneUrlAnterior =
                                  evidenciasExistentesURL[index].isNotEmpty;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1E293B),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(8),
                                          topRight: Radius.circular(8),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '¿Por qué ${index + 1}?',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        children: [
                                          _buildInputTextField(
                                            'Pregunta',
                                            pqCtrls[index],
                                            readOnly: soloLectura,
                                          ),
                                          const SizedBox(height: 8),
                                          _buildInputTextField(
                                            'Respuesta / Explicación',
                                            exCtrls[index],
                                            maxLines: 2,
                                            readOnly: soloLectura,
                                          ),
                                          const SizedBox(height: 8),
                                          _buildInputTextField(
                                            'Evidencia (Texto)',
                                            evTextCtrls[index],
                                            maxLines: 2,
                                            readOnly: soloLectura,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  nuevasEvidenciasBytes[index] !=
                                                          null
                                                      ? '✅ Nueva imagen lista'
                                                      : (tieneUrlAnterior
                                                            ? '🖼️ Imagen actual en servidor'
                                                            : 'Sin imagen fotográfica'),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        nuevasEvidenciasBytes[index] !=
                                                            null
                                                        ? Colors.green
                                                        : Colors.grey.shade600,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                              if (!soloLectura)
                                                ElevatedButton.icon(
                                                  onPressed: () =>
                                                      seleccionarNuevaImagen(
                                                        index,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.upload_file,
                                                    size: 14,
                                                  ),
                                                  label: const Text(
                                                    'Cambiar Foto',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            const Color(
                                                              0xFFF8FAFC,
                                                            ),
                                                        foregroundColor:
                                                            Colors.black87,
                                                        elevation: 0,
                                                        minimumSize: const Size(
                                                          0,
                                                          30,
                                                        ),
                                                      ),
                                                )
                                              else if (tieneUrlAnterior)
                                                TextButton.icon(
                                                  onPressed: () => _mostrarPreviewImagen(
                                                    evidenciasExistentesURL[index],
                                                    isBase64:
                                                        evidenciasExistentesURL[index]
                                                            .contains(
                                                              'IMAGEN_ADJUNTA:',
                                                            ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.visibility,
                                                    size: 14,
                                                  ),
                                                  label: const Text(
                                                    'Ver Foto',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            const SizedBox(height: 24),
                            _seccionSubtitulo(
                              'Conclusión',
                              Icons.search_rounded,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '¿Requiere inv. adicional?',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 35,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          color: soloLectura
                                              ? const Color(0xFFF8FAFC)
                                              : Colors.white,
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: reqInvestigacion,
                                            isExpanded: true,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: soloLectura
                                                  ? Colors.black54
                                                  : Colors.black87,
                                            ),
                                            items: ['SI', 'NO']
                                                .map(
                                                  (e) => DropdownMenuItem(
                                                    value: e,
                                                    child: Text(e),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: soloLectura
                                                ? null
                                                : (v) => setModalState(
                                                    () => reqInvestigacion = v!,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '¿Encontró Causa Raíz?',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 35,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          color: soloLectura
                                              ? const Color(0xFFF8FAFC)
                                              : Colors.white,
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: encontroCausa,
                                            isExpanded: true,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: soloLectura
                                                  ? Colors.black54
                                                  : Colors.black87,
                                            ),
                                            items: ['SI', 'NO']
                                                .map(
                                                  (e) => DropdownMenuItem(
                                                    value: e,
                                                    child: Text(e),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: soloLectura
                                                ? null
                                                : (v) => setModalState(
                                                    () => encontroCausa = v!,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInputTextField(
                              'Descripción Causa Raíz (Si aplica)',
                              causaRaizCtrl,
                              maxLines: 2,
                              readOnly: soloLectura,
                            ),

                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _seccionSubtitulo(
                                  '4. Acciones a tomar',
                                  Icons.assignment_turned_in_rounded,
                                ),
                                if (!soloLectura &&
                                    accionesEditables.length < 4)
                                  TextButton.icon(
                                    onPressed: agregarAccion,
                                    icon: const Icon(
                                      Icons.add_circle,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'Agregar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFFF8FAFC),
                                    ),
                                  ),
                              ],
                            ),
                            ...List.generate(accionesEditables.length, (index) {
                              final acc = accionesEditables[index];
                              bool esPreventiva =
                                  acc.tipoAccion == 'Preventiva';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Acción #${index + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E293B),
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (!soloLectura &&
                                            accionesEditables.length > 2)
                                          InkWell(
                                            onTap: () => eliminarAccion(index),
                                            child: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 16,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const Divider(),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Tipo',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                height: 35,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  color: soloLectura
                                                      ? const Color(0xFFF8FAFC)
                                                      : Colors.white,
                                                ),
                                                child: DropdownButtonHideUnderline(
                                                  child: DropdownButton<String>(
                                                    value: acc.tipoAccion,
                                                    isExpanded: true,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: soloLectura
                                                          ? Colors.black54
                                                          : Colors.black87,
                                                    ),
                                                    items:
                                                        [
                                                              'Preventiva',
                                                              'Correctiva',
                                                            ]
                                                            .map(
                                                              (e) =>
                                                                  DropdownMenuItem(
                                                                    value: e,
                                                                    child: Text(
                                                                      e,
                                                                    ),
                                                                  ),
                                                            )
                                                            .toList(),
                                                    onChanged: soloLectura
                                                        ? null
                                                        : (val) {
                                                            setModalState(() {
                                                              acc.tipoAccion =
                                                                  val;
                                                              if (val ==
                                                                  'Correctiva')
                                                                acc.actividadSeleccionada =
                                                                    null;
                                                            });
                                                          },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Actividad',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              esPreventiva
                                                  ? Container(
                                                      height: 35,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: Colors
                                                              .grey
                                                              .shade300,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        color: soloLectura
                                                            ? const Color(
                                                                0xFFF8FAFC,
                                                              )
                                                            : Colors.white,
                                                      ),
                                                      child: DropdownButtonHideUnderline(
                                                        child: DropdownButton<String>(
                                                          value: acc
                                                              .actividadSeleccionada,
                                                          isExpanded: true,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: soloLectura
                                                                ? Colors.black54
                                                                : Colors
                                                                      .black87,
                                                          ),
                                                          hint: const Text(
                                                            'Elegir',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                            ),
                                                          ),
                                                          items:
                                                              [
                                                                    'DTO',
                                                                    'SLA',
                                                                    'Entrenamiento',
                                                                    'PIs',
                                                                    'Mapa de Procesos',
                                                                    'PM Plan',
                                                                    'Check List',
                                                                  ]
                                                                  .map(
                                                                    (
                                                                      e,
                                                                    ) => DropdownMenuItem(
                                                                      value: e,
                                                                      child:
                                                                          Text(
                                                                            e,
                                                                          ),
                                                                    ),
                                                                  )
                                                                  .toList(),
                                                          onChanged: soloLectura
                                                              ? null
                                                              : (
                                                                  val,
                                                                ) => setModalState(
                                                                  () =>
                                                                      acc.actividadSeleccionada =
                                                                          val,
                                                                ),
                                                        ),
                                                      ),
                                                    )
                                                  : _buildInputTextField(
                                                      '',
                                                      acc.actividadCtrl,
                                                      maxLines: 1,
                                                      readOnly: soloLectura,
                                                    ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _buildInputTextField(
                                      'Descripción',
                                      acc.descripcionCtrl,
                                      maxLines: 2,
                                      readOnly: soloLectura,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _buildInputTextField(
                                            'Responsable',
                                            acc.responsableCtrl,
                                            readOnly: soloLectura,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Fecha Cierre',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              InkWell(
                                                onTap: soloLectura
                                                    ? null
                                                    : () async {
                                                        DateTime?
                                                        p = await showDatePicker(
                                                          context: context,
                                                          initialDate:
                                                              acc.fechaCierre ??
                                                              DateTime.now(),
                                                          firstDate: DateTime(
                                                            2020,
                                                          ),
                                                          lastDate: DateTime(
                                                            2101,
                                                          ),
                                                        );
                                                        if (p != null)
                                                          setModalState(
                                                            () =>
                                                                acc.fechaCierre =
                                                                    p,
                                                          );
                                                      },
                                                child: Container(
                                                  height: 35,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color:
                                                          Colors.grey.shade300,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    color: soloLectura
                                                        ? const Color(
                                                            0xFFF8FAFC,
                                                          )
                                                        : Colors.white,
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        acc.fechaCierre != null
                                                            ? DateFormat(
                                                                'yyyy-MM-dd',
                                                              ).format(
                                                                acc.fechaCierre!,
                                                              )
                                                            : 'DD-MM-YYYY',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              acc.fechaCierre !=
                                                                  null
                                                              ? Colors.black87
                                                              : Colors.grey,
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons.calendar_today,
                                                        size: 14,
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
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Estado',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                height: 35,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  color: soloLectura
                                                      ? const Color(0xFFF8FAFC)
                                                      : Colors.white,
                                                ),
                                                child: DropdownButtonHideUnderline(
                                                  child: DropdownButton<String>(
                                                    value: acc.estado,
                                                    isExpanded: true,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: soloLectura
                                                          ? Colors.black54
                                                          : Colors.black87,
                                                    ),
                                                    items:
                                                        [
                                                              'Pendiente',
                                                              'Concluida',
                                                            ]
                                                            .map(
                                                              (e) =>
                                                                  DropdownMenuItem(
                                                                    value: e,
                                                                    child: Text(
                                                                      e,
                                                                    ),
                                                                  ),
                                                            )
                                                            .toList(),
                                                    onChanged: soloLectura
                                                        ? null
                                                        : (val) {
                                                            setModalState(() {
                                                              acc.estado = val!;
                                                            });
                                                          },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: soloLectura
                            ? [
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E293B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Cerrar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ]
                            : [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: guardando
                                      ? null
                                      : () async {
                                          if (areaCtrl.text.trim().isEmpty ||
                                              disparadorCtrl.text
                                                  .trim()
                                                  .isEmpty) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Por favor, complete Área y Disparador.',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }

                                          for (
                                            int i = 0;
                                            i < accionesEditables.length;
                                            i++
                                          ) {
                                            var a = accionesEditables[i];
                                            if (a.tipoAccion == null ||
                                                a.descripcionCtrl.text
                                                    .trim()
                                                    .isEmpty ||
                                                a.responsableCtrl.text
                                                    .trim()
                                                    .isEmpty ||
                                                a.fechaCierre == null) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Complete todos los campos de la Acción #${i + 1}',
                                                  ),
                                                  backgroundColor:
                                                      Colors.orange,
                                                ),
                                              );
                                              return;
                                            }
                                            if (a.tipoAccion == 'Preventiva' &&
                                                a.actividadSeleccionada ==
                                                    null) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Seleccione una actividad para la Acción #${i + 1}',
                                                  ),
                                                  backgroundColor:
                                                      Colors.orange,
                                                ),
                                              );
                                              return;
                                            }
                                          }

                                          setModalState(() => guardando = true);

                                          for (int i = 0; i < 5; i++) {
                                            if (nuevasEvidenciasBytes[i] !=
                                                null) {
                                              String? urlSubida =
                                                  await ApiService.subirImagen(
                                                    nuevasEvidenciasBytes[i]!,
                                                  );
                                              if (urlSubida != null) {
                                                evidenciasExistentesURL[i] =
                                                    urlSubida;
                                              } else {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Error al subir imagen.',
                                                    ),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                                setModalState(
                                                  () => guardando = false,
                                                );
                                                return;
                                              }
                                            }
                                          }

                                          String getEvidenciaFinal(int index) {
                                            String texto = evTextCtrls[index]
                                                .text
                                                .trim();
                                            String url =
                                                evidenciasExistentesURL[index];
                                            if (url.isNotEmpty &&
                                                texto.isNotEmpty)
                                              return '$texto | $url';
                                            if (url.isNotEmpty) return url;
                                            return texto;
                                          }

                                          final payload = {
                                            'fecha': DateFormat(
                                              'yyyy-MM-dd',
                                            ).format(fechaSelect),
                                            'turno': turnoSelect,
                                            'area': areaCtrl.text.trim(),
                                            'pi': piSeleccionado ?? '',
                                            'participantes': participantesCtrl
                                                .text
                                                .trim(),
                                            'supervisor': supervisorCtrl.text
                                                .trim(),
                                            'interventor': interventorCtrl.text
                                                .trim(),
                                            'valor_disparador_alcanzado':
                                                disparadorCtrl.text.trim(),
                                            'contencion_problema':
                                                contencionCtrl.text.trim(),
                                            'requiere_investigacion_adicional':
                                                reqInvestigacion,
                                            'encontro_causa_raiz':
                                                encontroCausa,
                                            'causa raiz': causaRaizCtrl.text
                                                .trim(),

                                            'porque_1': pqCtrls[0].text.trim(),
                                            'explique_porque_1': exCtrls[0].text
                                                .trim(),
                                            'evidencia_porque_1':
                                                getEvidenciaFinal(0),
                                            'porque_2': pqCtrls[1].text.trim(),
                                            'explique_porque_2': exCtrls[1].text
                                                .trim(),
                                            'evidencia_porque_2':
                                                getEvidenciaFinal(1),
                                            'porque_3': pqCtrls[2].text.trim(),
                                            'explique_porque_3': exCtrls[2].text
                                                .trim(),
                                            'evidencia_porque_3':
                                                getEvidenciaFinal(2),
                                            'porque_4': pqCtrls[3].text.trim(),
                                            'explique_porque_4': exCtrls[3].text
                                                .trim(),
                                            'evidencia_porque_4':
                                                getEvidenciaFinal(3),
                                            'porque_5': pqCtrls[4].text.trim(),
                                            'explique_porque_5': exCtrls[4].text
                                                .trim(),
                                            'evidencia_porque_5':
                                                getEvidenciaFinal(4),

                                            'accion_1':
                                                accionesEditables.isNotEmpty
                                                ? accionesEditables[0]
                                                      .tipoAccion
                                                : '',
                                            'actividad_1':
                                                accionesEditables.isNotEmpty &&
                                                    accionesEditables[0]
                                                            .tipoAccion ==
                                                        'Preventiva'
                                                ? (accionesEditables[0]
                                                          .actividadSeleccionada ??
                                                      '')
                                                : '',
                                            'descripcion_1':
                                                accionesEditables.isNotEmpty
                                                ? accionesEditables[0]
                                                      .descripcionCtrl
                                                      .text
                                                : '',
                                            'responsable_1':
                                                accionesEditables.isNotEmpty
                                                ? accionesEditables[0]
                                                      .responsableCtrl
                                                      .text
                                                : '',
                                            'fecha_cierre_1':
                                                (accionesEditables.isNotEmpty &&
                                                    accionesEditables[0]
                                                            .fechaCierre !=
                                                        null)
                                                ? DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(
                                                    accionesEditables[0]
                                                        .fechaCierre!,
                                                  )
                                                : null,
                                            'estado_accion1':
                                                accionesEditables.isNotEmpty
                                                ? accionesEditables[0].estado
                                                : '',

                                            'accion_2':
                                                accionesEditables.length > 1
                                                ? accionesEditables[1]
                                                      .tipoAccion
                                                : '',
                                            'actividad_2':
                                                accionesEditables.length > 1 &&
                                                    accionesEditables[1]
                                                            .tipoAccion ==
                                                        'Preventiva'
                                                ? (accionesEditables[1]
                                                          .actividadSeleccionada ??
                                                      '')
                                                : '',
                                            'descripcion_2':
                                                accionesEditables.length > 1
                                                ? accionesEditables[1]
                                                      .descripcionCtrl
                                                      .text
                                                : '',
                                            'responsable_2':
                                                accionesEditables.length > 1
                                                ? accionesEditables[1]
                                                      .responsableCtrl
                                                      .text
                                                : '',
                                            'fecha_cierre_2':
                                                (accionesEditables.length > 1 &&
                                                    accionesEditables[1]
                                                            .fechaCierre !=
                                                        null)
                                                ? DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(
                                                    accionesEditables[1]
                                                        .fechaCierre!,
                                                  )
                                                : null,
                                            'estado_accion2':
                                                accionesEditables.length > 1
                                                ? accionesEditables[1].estado
                                                : '',

                                            'accion_3':
                                                accionesEditables.length > 2
                                                ? accionesEditables[2]
                                                      .tipoAccion
                                                : '',
                                            'actividad_3':
                                                accionesEditables.length > 2 &&
                                                    accionesEditables[2]
                                                            .tipoAccion ==
                                                        'Preventiva'
                                                ? (accionesEditables[2]
                                                          .actividadSeleccionada ??
                                                      '')
                                                : '',
                                            'descripcion_3':
                                                accionesEditables.length > 2
                                                ? accionesEditables[2]
                                                      .descripcionCtrl
                                                      .text
                                                : '',
                                            'responsable_3':
                                                accionesEditables.length > 2
                                                ? accionesEditables[2]
                                                      .responsableCtrl
                                                      .text
                                                : '',
                                            'fecha_cierre_3':
                                                (accionesEditables.length > 2 &&
                                                    accionesEditables[2]
                                                            .fechaCierre !=
                                                        null)
                                                ? DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(
                                                    accionesEditables[2]
                                                        .fechaCierre!,
                                                  )
                                                : null,
                                            'estado_accion3':
                                                accionesEditables.length > 2
                                                ? accionesEditables[2].estado
                                                : '',

                                            'accion_4':
                                                accionesEditables.length > 3
                                                ? accionesEditables[3]
                                                      .tipoAccion
                                                : '',
                                            'actividad_4':
                                                accionesEditables.length > 3 &&
                                                    accionesEditables[3]
                                                            .tipoAccion ==
                                                        'Preventiva'
                                                ? (accionesEditables[3]
                                                          .actividadSeleccionada ??
                                                      '')
                                                : '',
                                            'descripcion_4':
                                                accionesEditables.length > 3
                                                ? accionesEditables[3]
                                                      .descripcionCtrl
                                                      .text
                                                : '',
                                            'responsable_4':
                                                accionesEditables.length > 3
                                                ? accionesEditables[3]
                                                      .responsableCtrl
                                                      .text
                                                : '',
                                            'fecha_cierre_4':
                                                (accionesEditables.length > 3 &&
                                                    accionesEditables[3]
                                                            .fechaCierre !=
                                                        null)
                                                ? DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(
                                                    accionesEditables[3]
                                                        .fechaCierre!,
                                                  )
                                                : null,
                                            'estado_accion4':
                                                accionesEditables.length > 3
                                                ? accionesEditables[3].estado
                                                : '',

                                            'estado_revicion':
                                                'PENDIENTE REVISION',
                                            'estado': 'PENDIENTE',
                                          };

                                          try {
                                            await ApiService.actualizar(
                                              'gestion',
                                              '5why',
                                              'id',
                                              id,
                                              payload,
                                            );
                                            if (mounted) {
                                              Navigator.pop(ctx);
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Reporte actualizado y enviado a revisión',
                                                  ),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                              _cargarDatos();
                                            }
                                          } catch (e) {
                                            setModalState(
                                              () => guardando = false,
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error al guardar: $e',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        },
                                  icon: guardando
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    guardando
                                        ? 'Enviando...'
                                        : 'Guardar y Enviar a Revisión',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF36F21),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
        ],
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          style: TextStyle(
            fontSize: 11,
            color: readOnly ? Colors.black54 : Colors.black87,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: readOnly
                    ? Colors.grey.shade300
                    : const Color(0xFFF36F21),
              ),
            ),
            fillColor: readOnly ? const Color(0xFFF8FAFC) : Colors.white,
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _seccionSubtitulo(String titulo, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFF36F21), size: 16),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _datoRowVisual(
    String etiqueta,
    String valor, {
    bool isBold = false,
    Color color = Colors.black87,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<int, pw.ImageProvider>> _preDecodificarImagenesParaPDF(
    Map<String, dynamic> row,
  ) async {
    Map<int, pw.ImageProvider> imagenesListas = {};
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      try {
        if (rawEvidencia.contains('http://') ||
            rawEvidencia.contains('https://')) {
          int httpIndex = rawEvidencia.indexOf('http');
          String imageUrl = rawEvidencia.substring(httpIndex).trim();
          imagenesListas[i] = await networkImage(imageUrl);
        } else if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
          final parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
          if (parts.length > 1) {
            String base64String = parts[1];
            int commaIndex = base64String.indexOf('base64,');
            if (commaIndex != -1)
              base64String = base64String.substring(commaIndex + 7);
            if (base64String.length > 1000000) continue;
            base64String = base64String.replaceAll(RegExp(r'\s+'), '');
            await Future.delayed(const Duration(milliseconds: 10));
            final imgBytes = base64Decode(base64String);
            imagenesListas[i] = pw.MemoryImage(imgBytes, dpi: 72);
          }
        } else if (rawEvidencia.contains('data:image')) {
          int dataIndex = rawEvidencia.indexOf('data:image');
          String base64String = rawEvidencia.substring(dataIndex);
          int commaIndex = base64String.indexOf('base64,');
          if (commaIndex != -1)
            base64String = base64String.substring(commaIndex + 7);
          if (base64String.length > 1000000) continue;
          base64String = base64String.replaceAll(RegExp(r'\s+'), '');
          await Future.delayed(const Duration(milliseconds: 10));
          final imgBytes = base64Decode(base64String);
          imagenesListas[i] = pw.MemoryImage(imgBytes, dpi: 72);
        }
      } catch (e) {
        debugPrint('Error procesando imagen PDF $i: $e');
      }
    }
    return imagenesListas;
  }

  List<pw.Widget> _construirPaginasPdf(
    Map<String, dynamic> row,
    pw.ImageProvider? imgLogo,
    Map<int, pw.ImageProvider> imagenesDecodificadas,
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
        textoEvidencia = rawEvidencia
            .split('IMAGEN_ADJUNTA:')[0]
            .replaceAll('|', '')
            .trim();
      } else if (rawEvidencia.contains('http')) {
        textoEvidencia = rawEvidencia
            .substring(0, rawEvidencia.indexOf('http'))
            .replaceAll('|', '')
            .trim();
      } else if (rawEvidencia.contains('data:image')) {
        textoEvidencia = rawEvidencia
            .substring(0, rawEvidencia.indexOf('data:image'))
            .replaceAll('|', '')
            .trim();
      }

      if (imagenesDecodificadas.containsKey(i)) {
        evidenciasWidgets.add(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (textoEvidencia.isNotEmpty)
                pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
              if (textoEvidencia.isNotEmpty) pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Image(
                  imagenesDecodificadas[i]!,
                  height: 60,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ],
          ),
        );
      } else {
        if (rawEvidencia.contains('IMAGEN_ADJUNTA:') ||
            rawEvidencia.contains('http') ||
            rawEvidencia.contains('data:image')) {
          evidenciasWidgets.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (textoEvidencia.isNotEmpty)
                  pw.Text(
                    textoEvidencia,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '[Imagen omitida o muy pesada]',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.red800,
                  ),
                ),
              ],
            ),
          );
        } else {
          evidenciasWidgets.add(
            pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
          );
        }
      }
    }

    String fecha = row['fecha']?.toString().split('T')[0] ?? '-';
    String turno = row['turno']?.toString() ?? '-';
    String area = row['area']?.toString() ?? '-';
    String pi = row['pi']?.toString() ?? '-';
    String supervisor = row['supervisor']?.toString() ?? '-';
    String interventor = row['interventor']?.toString() ?? '-';
    String participantes = row['participantes']?.toString() ?? '-';
    String disparador = row['valor_disparador_alcanzado']?.toString() ?? '-';
    String contencion = row['contencion_problema']?.toString() ?? '-';
    String necesitaInv =
        (row['requiere_investigacion_adicional']?.toString() ?? 'NO')
            .toUpperCase();
    String causaRaizFormulario =
        (row['encontro_causa_raiz']?.toString() ?? 'NO').toUpperCase();
    String descripcionCausaRaiz =
        row['causa_raiz']?.toString() ?? row['causa raiz']?.toString() ?? '-';

    String q1 = row['cumple_flujo_resolucion']?.toString() ?? '';
    if (q1 == 'PD') q1 = '';
    String q2 = row['resolucion_primera_linea']?.toString() ?? '';
    if (q2 == 'PD') q2 = '';
    String q3 = row['secuencia_tiene_sentido']?.toString() ?? '';
    if (q3 == 'PD') q3 = '';
    String q4 = row['porques_con_evidencia']?.toString() ?? '';
    if (q4 == 'PD') q4 = '';
    String q5 =
        row['encontro_causa_raiz_eval']?.toString() ??
        row['encontro_causa_raiz']?.toString() ??
        '';
    if (q5 == 'PD') q5 = '';
    String q6 = row['proponen_acciones_eliminacion']?.toString() ?? '';
    if (q6 == 'PD') q6 = '';

    String estadoEval = row['estado']?.toString().toUpperCase() ?? 'PENDIENTE';

    String displayEstadoEval = estadoEval == 'PENDIENTE' ? '' : estadoEval;
    String calificacion = estadoEval == 'PENDIENTE'
        ? ''
        : (row['resultado']?.toString() ?? '');
    String obsEval = estadoEval == 'PENDIENTE'
        ? ''
        : (row['observacion_evaluador']?.toString() ?? '');

    String resultado2 =
        row['resultado_2']?.toString() ??
        (estadoEval == 'APTO' ? 'No aplica' : '');
    if (resultado2 == 'Pendiente por revisión') resultado2 = '';

    String ultimaAprovacion =
        row['ultima_aprovacion']?.toString() ??
        row['ultima aprovacion']?.toString() ??
        (estadoEval == 'APTO' ? 'No aplica' : '');
    if (ultimaAprovacion == 'Pendiente por revisión') ultimaAprovacion = '';

    String obs2 =
        row['Observacion 2']?.toString() ??
        row['observacion_2']?.toString() ??
        '';
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
                child: imgLogo != null
                    ? pw.Image(imgLogo, fit: pw.BoxFit.contain)
                    : pw.SizedBox(),
              ),
              pw.Container(
                color: greyBg,
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Análisis 5 porqués',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'ABInBev',
                  style: pw.TextStyle(
                    color: PdfColors.red800,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
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
          pw.TableRow(
            children: [
              celdaLabel('Supervisor:'),
              celdaValor(supervisor),
              celdaLabel('Interventor:'),
              celdaValor(interventor),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(5),
        },
        children: [
          pw.TableRow(
            children: [celdaLabel('Participantes:'), celdaValor(participantes)],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text('Información del disparador:', style: boldStyle),
              ),
            ],
          ),
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(disparador, style: regularStyle),
              ),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '¿Qué se hizo para contener el problema y lograr reanudar el proceso?',
                  style: boldStyle,
                ),
              ),
            ],
          ),
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(contencion, style: regularStyle),
              ),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text('5W', style: boldStyle),
              ),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(4),
          1: const pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text('Responda los 5 porqués', style: boldStyle),
              ),
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text('Evidencias', style: boldStyle),
              ),
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
                pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${index + 1}', style: regularStyle),
                ),
                pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('¿Por qué?', style: regularStyle),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.black,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: pw.Text(
                        pq.isEmpty ? ' ' : pq,
                        style: boldStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        ex.isEmpty ? ' ' : ex,
                        style: regularStyle,
                      ),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.center,
                  child: evidenciasWidgets[index],
                ),
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
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text('Cierre del ciclo:', style: boldStyle),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '¿Se necesita realizar una\ninvestigación adicional?',
                  style: boldStyle,
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Container(
                color: necesitaInv == 'SI' ? PdfColors.red : PdfColors.green,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  necesitaInv,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Causa raíz encontrada',
                  style: boldStyle,
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Container(
                color: causaRaizFormulario == 'SI'
                    ? PdfColors.green
                    : PdfColors.red,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  causaRaizFormulario,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(5),
        },
        children: [
          pw.TableRow(
            children: [
              celdaLabel('Descripción Causa Raíz:'),
              celdaValor(descripcionCausaRaiz),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                color: greyBg,
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text('ACCIONES', style: boldStyle),
              ),
            ],
          ),
        ],
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.2),
          1: const pw.FlexColumnWidth(1.5),
          2: const pw.FlexColumnWidth(3),
          3: const pw.FlexColumnWidth(1.5),
          4: const pw.FlexColumnWidth(1.2),
          5: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: greyBg),
            children: [
              celdaLabel('Tipo de accion'),
              celdaLabel('Aplicar a / Actividad'),
              celdaLabel('Accion / Descripción'),
              celdaLabel('Responsable'),
              celdaLabel('Fecha cierre'),
              celdaLabel('Estado'),
            ],
          ),
          ...List.generate(4, (index) {
            String tipo = row['accion_${index + 1}']?.toString() ?? '';
            String act = row['actividad_${index + 1}']?.toString() ?? '';
            String desc = row['descripcion_${index + 1}']?.toString() ?? '';
            String resp = row['responsable_${index + 1}']?.toString() ?? '';
            String fCie =
                row['fecha_cierre_${index + 1}']?.toString().split('T')[0] ??
                '';
            String est = row['estado_accion${index + 1}']?.toString() ?? '';

            if (tipo.isEmpty && desc.isEmpty) return pw.TableRow(children: []);
            bool isPreventiva = tipo.toUpperCase() == 'PREVENTIVA';
            bool isConcluida = est.toUpperCase() == 'CONCLUIDA';

            return pw.TableRow(
              children: [
                celdaLabel(tipo, align: pw.TextAlign.center),
                pw.Container(
                  color: isPreventiva ? darkGreyBg : PdfColors.white,
                  padding: const pw.EdgeInsets.all(5),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    act.isEmpty ? 'N/A' : act,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: isPreventiva
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ),
                celdaValor(desc),
                celdaValor(resp),
                celdaValor(fCie),
                celdaLabel(
                  est.isNotEmpty ? est : 'Pendiente',
                  align: pw.TextAlign.center,
                  colorTexto: isConcluida
                      ? PdfColors.green800
                      : PdfColors.orange800,
                ),
              ],
            );
          }),
        ],
      ),
      if (estadoEval == 'APTO' ||
          estadoEval == 'NO APTO' ||
          estadoEval == 'PENDIENTE') ...[
        pw.SizedBox(height: 15),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  color: greyBg,
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'EVALUACIÓN DE CALIDAD Y REVISIÓN',
                    style: boldStyle,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                celdaValor(
                  '1. ¿Se cumple con el flujo de resolución de problemas (participación adecuada)?',
                ),
                celdaLabel(q1, align: pw.TextAlign.center),
              ],
            ),
            pw.TableRow(
              children: [
                celdaValor(
                  '2. ¿La resolución se llevó a cabo con la primera línea (operadores y técnicos)?',
                ),
                celdaLabel(q2, align: pw.TextAlign.center),
              ],
            ),
            pw.TableRow(
              children: [
                celdaValor(
                  '3. ¿La secuencia de la resolución de problema tiene sentido?',
                ),
                celdaLabel(q3, align: pw.TextAlign.center),
              ],
            ),
            pw.TableRow(
              children: [
                celdaValor('4. ¿Todos los porqués cuentan con evidencia?'),
                celdaLabel(q4, align: pw.TextAlign.center),
              ],
            ),
            pw.TableRow(
              children: [
                celdaValor('5. ¿Se encontró causa raíz?'),
                celdaLabel(q5, align: pw.TextAlign.center),
              ],
            ),
            pw.TableRow(
              children: [
                celdaValor(
                  '6. ¿Se proponen acciones de eliminación de la causa raíz?',
                ),
                celdaLabel(q6, align: pw.TextAlign.center),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                celdaLabel('Calificación Obtenida:'),
                celdaLabel(
                  calificacion,
                  colorTexto: estadoEval == 'APTO'
                      ? PdfColors.green800
                      : (estadoEval == 'NO APTO'
                            ? PdfColors.red800
                            : PdfColors.black),
                ),
                celdaLabel('Estado Final:'),
                celdaLabel(
                  displayEstadoEval,
                  colorTexto: estadoEval == 'APTO'
                      ? PdfColors.green800
                      : (estadoEval == 'NO APTO'
                            ? PdfColors.red800
                            : PdfColors.black),
                ),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              children: [
                celdaLabel('Resultado 2:'),
                celdaLabel(resultado2, colorTexto: PdfColors.blue800),
                celdaLabel('Última Aprobación:'),
                celdaLabel(ultimaAprovacion, colorTexto: PdfColors.blue800),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  color: greyBg,
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Observación Evaluador (1ra Revisión):',
                    style: boldStyle,
                  ),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(obsEval, style: regularStyle),
                ),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  color: greyBg,
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Observación 2 (2da Revisión):',
                    style: boldStyle,
                  ),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(obs2, style: regularStyle),
                ),
              ],
            ),
          ],
        ),
      ],
    ];
  }

  Future<void> _generarYDescargarPDF(Map<String, dynamic> row) async {
    setState(() {
      _idGenerandoPdf = row['id'].toString();
    });
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      Map<int, pw.ImageProvider> imagenesListas =
          await _preDecodificarImagenesParaPDF(row);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) =>
              _construirPaginasPdf(row, imgLogo, imagenesListas),
        ),
      );

      final bytesPdf = await doc.save();
      String areaNom = (row['area']?.toString() ?? 'General').replaceAll(
        ' ',
        '_',
      );
      String fecha = row['fecha']?.toString().split('T')[0] ?? '-';

      await Printing.sharePdf(
        bytes: bytesPdf,
        filename: '5Why_${fecha}_$areaNom.pdf',
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _idGenerandoPdf = null;
        });
    }
  }

  Future<void> _descargarMultiplesPDFs() async {
    if (_seleccionados.isEmpty) return;
    setState(() {
      _generandoMultiplesPdf = true;
    });
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      List<Map<String, dynamic>> registrosSeleccionados = _registrosFiltrados
          .where((r) => _seleccionados.contains(r['id'].toString()))
          .toList();

      for (var row in registrosSeleccionados) {
        Map<int, pw.ImageProvider> imagenesListas =
            await _preDecodificarImagenesParaPDF(row);
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            build: (pw.Context context) =>
                _construirPaginasPdf(row, imgLogo, imagenesListas),
          ),
        );
      }

      final bytesPdf = await doc.save();
      await Printing.sharePdf(
        bytes: bytesPdf,
        filename:
            'Reporte_Masivo_5Why_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDFs múltiples: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _generandoMultiplesPdf = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: _colorBackground,
        body: Center(child: CircularProgressIndicator(color: _colorPrincipal)),
      );
    }

    return Scaffold(
      backgroundColor: _colorBackground,
      appBar: AppBar(
        backgroundColor: _colorEncabezados,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onToggleSidebar,
        ),
        title: const Text(
          'Historial y Analítica 5 Why',
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
          ? _buildBannerError()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBarraFiltros(),
                  const SizedBox(height: 20),
                  _buildDashboardHistorial(),
                  const SizedBox(height: 20),
                  _buildTablaDetalleCompleto(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade600),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber.shade900,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _mensajeError!,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _cargarDatos,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text(
              'REINTENTAR',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : (items.isNotEmpty ? items[0] : null),
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
              style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDatePicker(String label, DateTime? date, ValueChanged<DateTime?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2101),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            height: 38,
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
                  date != null ? DateFormat('yyyy-MM-dd').format(date) : 'Seleccionar',
                  style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
                const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarraFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: _sombraCards,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w < 800) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: [
                SizedBox(width: 160, child: _buildFilterDatePicker('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d))),
                SizedBox(width: 160, child: _buildFilterDatePicker('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d))),
                SizedBox(width: 160, child: _buildFilterDropdown('ÁREA', _filtroArea, _listaFiltroArea, (val) => setState(() => _filtroArea = val!))),
                SizedBox(width: 160, child: _buildFilterDropdown('PI AFECTADO', _filtroPI, _listaFiltroPI, (val) => setState(() => _filtroPI = val!))),
                SizedBox(width: 160, child: _buildFilterDropdown('SUPERVISOR', _filtroSupervisor, _listaFiltroSupervisor, (val) => setState(() => _filtroSupervisor = val!))),
                SizedBox(width: 160, child: _buildFilterDropdown('INTERVENTOR', _filtroInterventor, _listaFiltroInterventor, (val) => setState(() => _filtroInterventor = val!))),
                SizedBox(width: 160, child: _buildFilterDropdown('ESTADO (ACCIONES)', _filtroEstado, _listaFiltroEstado, (val) => setState(() => _filtroEstado = val!))),
                Container(
                  height: 54,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _aplicarFiltros,
                        icon: const Icon(Icons.filter_alt, size: 16),
                        label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D6EFD),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _descargarExcel,
                        icon: const Icon(Icons.table_view_rounded, size: 16),
                        label: const Text('EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF198754),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _limpiarFiltros,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF212529),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          padding: const EdgeInsets.all(16),
                          minimumSize: const Size(48, 48),
                          elevation: 0,
                        ),
                        child: const Icon(Icons.cleaning_services_rounded, size: 16),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildFilterDatePicker('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDatePicker('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDropdown('ÁREA', _filtroArea, _listaFiltroArea, (val) => setState(() => _filtroArea = val!))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDropdown('PI AFECTADO', _filtroPI, _listaFiltroPI, (val) => setState(() => _filtroPI = val!))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDropdown('SUPERVISOR', _filtroSupervisor, _listaFiltroSupervisor, (val) => setState(() => _filtroSupervisor = val!))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _buildFilterDropdown('INTERVENTOR', _filtroInterventor, _listaFiltroInterventor, (val) => setState(() => _filtroInterventor = val!))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDropdown('ESTADO (ACCIONES)', _filtroEstado, _listaFiltroEstado, (val) => setState(() => _filtroEstado = val!))),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: const SizedBox()),
                  ElevatedButton.icon(
                    onPressed: _aplicarFiltros,
                    icon: const Icon(Icons.filter_alt, size: 16),
                    label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D6EFD),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _descargarExcel,
                    icon: const Icon(Icons.table_view_rounded, size: 16),
                    label: const Text('EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF198754),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _limpiarFiltros,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF212529),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.all(18),
                      minimumSize: const Size(52, 52),
                      elevation: 0,
                    ),
                    child: const Icon(Icons.cleaning_services_rounded, size: 16),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardBase({
    required String titulo,
    Widget? actionRight,
    required Widget child,
    String? badgeText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: _sombraCards,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (badgeText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC3545),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (actionRight != null) actionRight,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildTablaDetalleCompleto() {
    int inicio = (_paginaActual - 1) * _registrosPorPagina;
    int fin = min(inicio + _registrosPorPagina, _registrosFiltrados.length);
    List<Map<String, dynamic>> paginaLista = _registrosFiltrados.isEmpty
        ? []
        : _registrosFiltrados.sublist(inicio, fin);
    int totalPaginas = max(
      1,
      (_registrosFiltrados.length / _registrosPorPagina).ceil(),
    );
    bool todosSeleccionados =
        paginaLista.isNotEmpty &&
        paginaLista.every((r) => _seleccionados.contains(r['id'].toString()));

    List<Map<String, dynamic>> columnas = [
      {'key': 'sel', 'label': '', 'w': 40.0},
      {'key': 'fecha', 'label': 'FECHA', 'w': 80.0},
      {'key': 'area', 'label': 'ÁREA', 'w': 100.0},
      {'key': 'pi', 'label': 'PI AFECTADO', 'w': 130.0},
      {'key': 'disp', 'label': 'DISPARADOR', 'w': 220.0},
      {'key': 'part', 'label': 'PARTICIPANTES', 'w': 160.0},
      {'key': 'estado', 'label': 'ESTADO', 'w': 100.0},
      {'key': 'obs1', 'label': 'OBSERVACIÓN 1', 'w': 180.0},
      {'key': 'obs2', 'label': 'OBSERVACIÓN 2', 'w': 180.0},
      {'key': 'res', 'label': 'RES. FINAL', 'w': 100.0},
      {'key': 'gest', 'label': 'GESTIÓN', 'w': 160.0},
    ];

    double totalWidth = columnas.fold<double>(
      0.0,
      (p, c) => p + (c['w'] as double),
    );

    return _buildCardBase(
      titulo: 'Reporte Detallado 5 Why',
      badgeText: '${_registrosFiltrados.length} Registros',
      actionRight: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_seleccionados.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _generandoMultiplesPdf
                  ? null
                  : _descargarMultiplesPDFs,
              icon: _generandoMultiplesPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 14),
              label: Text(
                'DESCARGAR SELECC. (${_seleccionados.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _colorPrincipal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _descargarExcel,
            icon: const Icon(Icons.table_view_rounded, size: 14),
            label: const Text(
              'EXCEL',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Mostrar ',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _registrosPorPagina,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    items: [10, 25, 50, 100]
                        .map(
                          (e) => DropdownMenuItem(value: e, child: Text('$e')),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _registrosPorPagina = v!;
                      _paginaActual = 1;
                    }),
                  ),
                ),
              ),
              const Text(
                ' registros',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Scrollbar(
                controller: _tablaScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8,
                radius: const Radius.circular(8),
                child: SingleChildScrollView(
                  controller: _tablaScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: totalWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: _colorEncabezados,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          ),
                          child: Row(
                            children: columnas.map((c) {
                              if (c['key'] == 'sel') {
                                return Container(
                                  width: c['w'] as double,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Theme(
                                    data: ThemeData(
                                      unselectedWidgetColor: Colors.white70,
                                    ),
                                    child: Checkbox(
                                      value: todosSeleccionados,
                                      onChanged: paginaLista.isEmpty
                                          ? null
                                          : (v) => _toggleSeleccionarTodos(
                                              paginaLista,
                                            ),
                                      activeColor: _colorPrincipal,
                                      checkColor: Colors.white,
                                    ),
                                  ),
                                );
                              }
                              return _headerCell(
                                c['label'] as String,
                                width: c['w'] as double,
                              );
                            }).toList(),
                          ),
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: paginaLista.length,
                          itemBuilder: (context, i) {
                            var r = paginaLista[i];
                            String idRow = r['id'].toString();

                            String rawF = r['fecha']?.toString() ?? '';
                            String fecha = rawF.isNotEmpty
                                ? rawF.split('T')[0].split(' ')[0]
                                : 'N/A';

                            String estadoOriginal =
                                (r['estado']?.toString() ?? 'PENDIENTE')
                                    .toUpperCase();
                            String ultAp =
                                (r['ultima aprovacion']?.toString() ??
                                        r['ultima_aprovacion']?.toString() ??
                                        '')
                                    .toUpperCase();
                            String obs1 =
                                r['observacion_evaluador']?.toString() ?? '-';
                            if (obs1.trim().isEmpty || obs1 == 'NULL')
                              obs1 = '-';
                            String obs2 =
                                r['Observacion 2']?.toString() ??
                                r['observacion_2']?.toString() ??
                                '-';
                            if (obs2.trim().isEmpty || obs2 == 'NULL')
                              obs2 = '-';

                            String estadoMostrar = estadoOriginal;
                            if (estadoOriginal != 'PENDIENTE' &&
                                ultAp.isNotEmpty &&
                                ultAp != 'NULL' &&
                                ultAp != 'NO APLICA' &&
                                ultAp != 'PENDIENTE POR REVISIÓN') {
                              estadoMostrar = ultAp;
                            }

                            bool bloqueado =
                                (estadoMostrar == 'APTO' ||
                                estadoMostrar == 'APROBADO');

                            Color colorEst = Colors.orange.shade800;
                            if (estadoMostrar == 'APTO' ||
                                estadoMostrar == 'APROBADO')
                              colorEst = Colors.green;
                            else if (estadoMostrar == 'NO APTO' ||
                                estadoMostrar == 'NO APROBADO')
                              colorEst = Colors.red;

                            String resFinal =
                                r['ultima aprovacion']?.toString() ??
                                r['ultima_aprovacion']?.toString() ??
                                '-';
                            if (resFinal.trim().isEmpty || resFinal == 'NULL')
                              resFinal = '-';

                            Color colorResFinal = Colors.black87;
                            if (resFinal == 'APROBADO' || resFinal == 'APTO')
                              colorResFinal = Colors.green;
                            if (resFinal == 'NO APROBADO' ||
                                resFinal == 'NO APTO')
                              colorResFinal = Colors.red;
                            if (resFinal == 'VOLVER A REVISAR')
                              colorResFinal = Colors.orange.shade800;

                            Color rowColor = i % 2 == 0
                                ? Colors.white
                                : const Color(0xFFF8FAFC);

                            return Container(
                              decoration: BoxDecoration(
                                color: rowColor,
                                border: const Border(
                                  bottom: BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: columnas[0]['w'] as double,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Checkbox(
                                      value: _seleccionados.contains(idRow),
                                      onChanged: (v) => _toggleSeleccion(idRow),
                                      activeColor: _colorPrincipal,
                                    ),
                                  ),
                                  _buildFixedCell(
                                    columnas[1]['w'] as double,
                                    fecha,
                                  ),
                                  _buildFixedCell(
                                    columnas[2]['w'] as double,
                                    r['area']?.toString() ?? 'N/A',
                                  ),
                                  _buildFixedCell(
                                    columnas[3]['w'] as double,
                                    r['pi']?.toString() ?? 'N/A',
                                    isBold: true,
                                    color: _colorPrincipal,
                                  ),
                                  _buildFixedCell(
                                    columnas[4]['w'] as double,
                                    r['valor_disparador_alcanzado']
                                            ?.toString() ??
                                        'N/A',
                                  ),
                                  _buildFixedCell(
                                    columnas[5]['w'] as double,
                                    r['participantes']?.toString() ?? 'N/A',
                                  ),
                                  Container(
                                    width: columnas[6]['w'] as double,
                                    padding: const EdgeInsets.all(8.0),
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorEst.withValues(alpha: 0.1),
                                        border: Border.all(color: colorEst),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        estadoMostrar,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: colorEst,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildFixedCell(
                                    columnas[7]['w'] as double,
                                    obs1,
                                    color: Colors.black54,
                                  ),
                                  _buildFixedCell(
                                    columnas[8]['w'] as double,
                                    obs2,
                                    color: Colors.black54,
                                  ),
                                  Container(
                                    width: columnas[9]['w'] as double,
                                    padding: const EdgeInsets.all(8.0),
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorResFinal != Colors.black87
                                            ? colorResFinal.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.grey.shade100,
                                        border: Border.all(
                                          color: colorResFinal != Colors.black87
                                              ? colorResFinal
                                              : Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        resFinal,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: colorResFinal != Colors.black87
                                              ? colorResFinal
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: columnas[10]['w'] as double,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () => _evaluarConIA(r),
                                          icon: const Icon(Icons.smart_toy, size: 12),
                                          label: const Text(
                                            'Auditor IA',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF4F46E5), // Indigo
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 0,
                                            ),
                                            minimumSize: const Size(0, 30),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _abrirModalEdicion(r, bloqueado),
                                          icon: Icon(
                                            bloqueado
                                                ? Icons.visibility
                                                : Icons.edit,
                                            size: 12,
                                          ),
                                          label: Text(
                                            bloqueado ? 'Detalle' : 'Editar',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: bloqueado
                                                ? Colors.grey.shade300
                                                : _colorPrincipal,
                                            foregroundColor: bloqueado
                                                ? Colors.black87
                                                : Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 0,
                                            ),
                                            minimumSize: const Size(0, 30),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                        _idGenerandoPdf == idRow
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.redAccent,
                                                    ),
                                              )
                                            : IconButton(
                                                icon: const Icon(
                                                  Icons.picture_as_pdf_rounded,
                                                  color: Colors.redAccent,
                                                  size: 18,
                                                ),
                                                tooltip: 'Descargar PDF',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () =>
                                                    _generarYDescargarPDF(r),
                                              ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mostrando ${paginaLista.isEmpty ? 0 : inicio + 1} a $fin de ${_registrosFiltrados.length} reportes',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Row(
                  children: [
                    InkWell(
                      onTap: _paginaActual > 1
                          ? () => setState(() => _paginaActual--)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white,
                        ),
                        child: const Text(
                          'Anterior',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ' $_paginaActual / $totalPaginas ',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _paginaActual < totalPaginas
                          ? () => setState(() => _paginaActual++)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white,
                        ),
                        child: const Text(
                          'Siguiente',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  Widget _buildFixedCell(
    double width,
    String text, {
    bool isBold = false,
    Color color = const Color(0xFF1E293B),
    TextAlign align = TextAlign.left,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color,
        ),
        textAlign: align,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _evaluarConIA(Map<String, dynamic> registro) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Auditor IA analizando el reporte...'),
          ],
        ),
      ),
    );

    try {
      final apiKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
      final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

      // Preparamos los datos que le mandaremos en la conversación
      String mensajeUsuario = '''
Por favor evalúa el siguiente reporte "5 Porqués":

Datos del reporte:
- Área: ${registro['area'] ?? 'No registrada'}
- Problema/Disparador: ${registro['valor_disparador_alcanzado'] ?? 'No registrado'}
- Participantes: ${registro['participantes'] ?? 'No registrados'}
- Contención del problema: ${registro['contencion_problema'] ?? 'No registrada'}

Respuestas a los 5 Porqués:
1. ${registro['porque_1'] ?? 'No registrado'}
2. ${registro['porque_2'] ?? 'No registrado'}
3. ${registro['porque_3'] ?? 'No registrado'}
4. ${registro['porque_4'] ?? 'No registrado'}
5. ${registro['porque_5'] ?? 'No registrado'}

Acciones propuestas (Tipos y descripciones):
1. ${registro['accion_1'] ?? 'Ninguna'}: ${registro['descripcion_1'] ?? ''}
2. ${registro['accion_2'] ?? 'Ninguna'}: ${registro['descripcion_2'] ?? ''}
3. ${registro['accion_3'] ?? 'Ninguna'}: ${registro['descripcion_3'] ?? ''}
4. ${registro['accion_4'] ?? 'Ninguna'}: ${registro['descripcion_4'] ?? ''}
5. ${registro['accion_5'] ?? 'Ninguna'}: ${registro['descripcion_5'] ?? ''}
''';

      // 2. Hacer la solicitud HTTP directa a OpenRouter (usando Gemma 4 31B IT)
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://plantatocancipa.site', // OpenRouter lo recomienda
          'X-Title': 'Auditor 5 Why', // OpenRouter lo recomienda
        },
        body: jsonEncode({
          "model": "google/gemma-4-31b-it",
          "messages": [
            {
              "role": "system",
              "content": "Eres un auditor industrial experto en la metodología de resolución de problemas '5 Porqués' (5 Whys). Tu objetivo es evaluar la calidad de los reportes. Eres estricto, profesional y técnico. Siempre debes responder usando esta estructura EXACTA:\n\n1. **Calificación**: (Ej: 80/100)\n2. **Puntos Fuertes**: Lo que se hizo bien en este reporte específico (basado en los datos leídos).\n3. **Áreas de Mejora**: Qué falló en la secuencia lógica, si las respuestas tienen sentido, o si se llegó a una verdadera causa raíz en el porqué 5.\n4. **Retroalimentación General**: Un breve consejo para el analista."
            },
            {
              "role": "user",
              "content": mensajeUsuario
            }
          ],
          "temperature": 0.2,
        }),
      );

      if (context.mounted) Navigator.of(context).pop(); // Cerrar dialog de carga

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final textoRespuesta = data['choices'][0]['message']['content'];

        if (context.mounted) _mostrarDialogoResultadoIA(textoRespuesta);
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Asegurar cierre del loader
        _mostrarDialogoResultadoIA('Ocurrió un error al contactar a la IA: \$e');
      }
    }
  }

  void _mostrarDialogoResultadoIA(String resultado) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.smart_toy, color: Colors.blueAccent),
            SizedBox(width: 10),
            Expanded(child: Text('Evaluación del Auditor IA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.5,
          child: SingleChildScrollView(
            child: SelectableText(resultado),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
