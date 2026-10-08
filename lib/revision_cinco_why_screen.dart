import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math';
import 'api_service.dart';

class RevisionCincoWhyScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onToggleSidebar;

  const RevisionCincoWhyScreen({
    super.key,
    required this.usuario,
    required this.onToggleSidebar,
  });

  @override
  State<RevisionCincoWhyScreen> createState() => _RevisionCincoWhyScreenState();
}

class _RevisionCincoWhyScreenState extends State<RevisionCincoWhyScreen> {
  // --- CONSTANTES DE DISEÑO EJECUTIVO ---
  final Color _colorBackground = const Color(0xFFF1F5F9);
  final Color _colorPrincipal = const Color(0xFFF36F21);
  final Color _colorEncabezados = const Color(0xFF1E293B);
  final Color _colorTextoOscuro = const Color(0xFF334155);

  final List<BoxShadow> _sombraCards = [
    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
  ];

  final ScrollController _tablaScrollController = ScrollController();

  bool _cargando = true;
  String? _mensajeError;
  String? _idGenerandoPdf;
  bool _generandoMultiplesPdf = false;

  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];
  Set<String> _seleccionados = {};

  // Filtros
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _filtroPI = 'Todos';
  String _filtroArea = 'Todas';
  String _filtroEstado = 'TODOS';
  String _busquedaTexto = '';
  final TextEditingController _buscarCtrl = TextEditingController();

  List<String> _listaFiltroPI = ['Todos'];
  List<String> _listaFiltroArea = ['Todas'];

  // Contadores para Dashboard
  Map<String, int> _pendientesPorArea = {};
  Map<String, int> _pendientesPorPI = {};
  int _totalReportes = 0;
  int _totalPendientes = 0;
  int _totalRevisados = 0;
  int _totalAptos = 0;
  int _totalNoAptos = 0;
  double _porcentajeRevisados = 0.0;

  Map<String, double> _adherenciaPreguntas = {};

  // Paginación
  int _registrosPorPagina = 10;
  int _paginaActual = 1;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    _buscarCtrl.dispose();
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
        datosProcesados = data.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      datosProcesados.sort((a, b) {
        int idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        int idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return idB.compareTo(idA);
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
            if (_fechaHasta != null && dt.isAfter(_fechaHasta!.add(const Duration(days: 1)))) return false;
          }
        }

        String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
        String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();
        if (_filtroArea != 'Todas' && ar != _filtroArea) return false;
        if (_filtroPI != 'Todos' && pi != _filtroPI) return false;

        String estado = (r['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
        if (_filtroEstado != 'TODOS' && estado != _filtroEstado) return false;

        if (_busquedaTexto.isNotEmpty) {
          String search = _busquedaTexto.toLowerCase();
          bool match = false;
          if (ar.toLowerCase().contains(search)) match = true;
          if (pi.toLowerCase().contains(search)) match = true;
          if ((r['participantes']?.toString() ?? '').toLowerCase().contains(search)) match = true;
          if ((r['valor_disparador_alcanzado']?.toString() ?? '').toLowerCase().contains(search)) match = true;

          if (!match) return false;
        }

        return true;
      }).toList();

      _paginaActual = 1;
      _seleccionados.clear();
      _calcularEstadisticas();
    });
  }

  void _limpiarFiltros() {
    setState(() {
      _fechaDesde = null; _fechaHasta = null; _filtroPI = 'Todos'; _filtroArea = 'Todas';
      _filtroEstado = 'TODOS'; _busquedaTexto = ''; _buscarCtrl.clear();
      _aplicarFiltros();
    });
  }

  void _calcularEstadisticas() {
    _pendientesPorArea.clear();
    _pendientesPorPI.clear();
    _totalReportes = _registrosFiltrados.length;
    _totalPendientes = 0;
    _totalRevisados = 0;
    _totalAptos = 0;
    _totalNoAptos = 0;

    Map<String, int> siCounts = {
      'cumple_flujo_resolucion': 0, 'resolucion_primera_linea': 0,
      'secuencia_tiene_sentido': 0, 'porques_con_evidencia': 0,
      'encontro_causa_raiz': 0, 'proponen_acciones_eliminacion': 0,
    };
    int evaluadosCount = 0;

    for (var r in _registrosFiltrados) {
      String estado = (r['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
      if (estado == 'PENDIENTE') {
        _totalPendientes++;
        String area = (r['area']?.toString() ?? 'Sin Área').toUpperCase();
        String pi = (r['pi']?.toString() ?? 'Sin PI').toUpperCase();

        _pendientesPorArea[area] = (_pendientesPorArea[area] ?? 0) + 1;
        _pendientesPorPI[pi] = (_pendientesPorPI[pi] ?? 0) + 1;
      } else {
        _totalRevisados++;
        if (estado == 'APTO') _totalAptos++;
        if (estado == 'NO APTO') _totalNoAptos++;

        evaluadosCount++;
        if ((r['cumple_flujo_resolucion']?.toString() ?? '').toUpperCase() == 'SI') siCounts['cumple_flujo_resolucion'] = siCounts['cumple_flujo_resolucion']! + 1;
        if ((r['resolucion_primera_linea']?.toString() ?? '').toUpperCase() == 'SI') siCounts['resolucion_primera_linea'] = siCounts['resolucion_primera_linea']! + 1;
        if ((r['secuencia_tiene_sentido']?.toString() ?? '').toUpperCase() == 'SI') siCounts['secuencia_tiene_sentido'] = siCounts['secuencia_tiene_sentido']! + 1;
        if ((r['porques_con_evidencia']?.toString() ?? '').toUpperCase() == 'SI') siCounts['porques_con_evidencia'] = siCounts['porques_con_evidencia']! + 1;
        if ((r['encontro_causa_raiz']?.toString() ?? '').toUpperCase() == 'SI') siCounts['encontro_causa_raiz'] = siCounts['encontro_causa_raiz']! + 1;
        if ((r['proponen_acciones_eliminacion']?.toString() ?? '').toUpperCase() == 'SI') siCounts['proponen_acciones_eliminacion'] = siCounts['proponen_acciones_eliminacion']! + 1;
      }
    }

    _porcentajeRevisados = _totalReportes > 0 ? (_totalRevisados / _totalReportes) * 100 : 0.0;

    _adherenciaPreguntas.clear();
    siCounts.forEach((key, count) {
      _adherenciaPreguntas[key] = evaluadosCount > 0 ? (count / evaluadosCount) * 100 : 0.0;
    });

    _pendientesPorArea = Map.fromEntries(_pendientesPorArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    _pendientesPorPI = Map.fromEntries(_pendientesPorPI.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  void _toggleSeleccion(String id) {
    setState(() {
      if (_seleccionados.contains(id)) _seleccionados.remove(id);
      else _seleccionados.add(id);
    });
  }

  void _toggleSeleccionarTodos(List<Map<String, dynamic>> pagina) {
    setState(() {
      bool todosSeleccionados = pagina.every((r) => _seleccionados.contains(r['id'].toString()));
      if (todosSeleccionados) {
        for (var r in pagina) { _seleccionados.remove(r['id'].toString()); }
      } else {
        for (var r in pagina) { _seleccionados.add(r['id'].toString()); }
      }
    });
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12, color: Colors.black45),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: _colorPrincipal, width: 1.5)),
    filled: true, fillColor: Colors.white, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _datoRow(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(etiqueta, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 12, color: Colors.black87))),
        ],
      ),
    );
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(color: _colorEncabezados, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Evidencia Fotográfica', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(ctx).pop(), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: isBase64
                        ? Image.memory(base64Decode(cleanData), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(30.0), child: Text('Error al cargar imagen', style: TextStyle(color: Colors.red))))
                        : Image.network(cleanData, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(30.0), child: Text('Enlace inválido', style: TextStyle(color: Colors.red)))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // FUNCIONES RECUPERADAS (PDF Y EXCEL)
  // ==========================================
  Future<void> _descargarExcel() async {
    try {
      String csv = "ID;Fecha;Area;PI Afectado;Participantes;Valor Disparador;Causa Raiz Encontrada;Req. Investigacion Adicional;Estado Evaluacion;Observacion Evaluador;Estado Acciones;Resultado 2;Observacion 2;Ultima Aprobacion\n";
      String sanitize(String val) => val.replaceAll('\n', ' ').replaceAll('\r', '').replaceAll(';', ',');

      for (var r in _registrosFiltrados) {
        String id = sanitize(r['id']?.toString() ?? '');
        String f = sanitize(r['fecha']?.toString().split('T')[0] ?? '');
        String a = sanitize(r['area']?.toString() ?? '');
        String p = sanitize(r['pi']?.toString() ?? '');
        String part = sanitize(r['participantes']?.toString() ?? '');
        String disp = sanitize(r['valor_disparador_alcanzado']?.toString() ?? '');
        String causa = sanitize(r['encontro_causa_raiz']?.toString() ?? '');
        String req = sanitize(r['requiere_investigacion_adicional']?.toString() ?? '');
        String estEval = sanitize(r['estado']?.toString() ?? 'PENDIENTE');
        String obsEval = sanitize(r['observacion_evaluador']?.toString() ?? '');

        String res2 = sanitize(r['resultado_2']?.toString() ?? '');
        String obs2 = sanitize(r['Observacion 2']?.toString() ?? r['observacion_2']?.toString() ?? '');
        String ultAp = sanitize(r['ultima aprovacion']?.toString() ?? r['ultima_aprovacion']?.toString() ?? '');

        int accionesCerradas = 0; int totalAcciones = 0;
        for (int i = 1; i <= 4; i++) {
          if ((r['accion_$i']?.toString() ?? '').isNotEmpty) {
            totalAcciones++;
            if ((r['estado_accion$i']?.toString() ?? '').toUpperCase() == 'CONCLUIDA') accionesCerradas++;
          }
        }
        String estadoAcc = "$accionesCerradas de $totalAcciones cerradas";
        csv += "$id;$f;$a;$p;$part;$disp;$causa;$req;$estEval;$obsEval;$estadoAcc;$res2;$obs2;$ultAp\n";
      }

      List<int> bytes = [0xEF, 0xBB, 0xBF] + utf8.encode(csv);
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'Reporte_Revisiones_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel generado exitosamente'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar Excel: $e'), backgroundColor: Colors.red));
    }
  }

  Future<Map<int, pw.ImageProvider>> _preDecodificarImagenes(Map<String, dynamic> row) async {
    Map<int, pw.ImageProvider> imagenesListas = {};
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      try {
        if (rawEvidencia.contains('http://') || rawEvidencia.contains('https://')) {
          int httpIndex = rawEvidencia.indexOf('http');
          String imageUrl = rawEvidencia.substring(httpIndex).trim();
          imagenesListas[i] = await networkImage(imageUrl);
        } else if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
          final parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
          if (parts.length > 1) {
            String base64String = parts[1];
            int commaIndex = base64String.indexOf('base64,');
            if (commaIndex != -1) {
              base64String = base64String.substring(commaIndex + 7);
            }
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
          if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
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

  List<pw.Widget> _construirPaginasPdf(Map<String, dynamic> row, pw.ImageProvider? imgLogo, Map<int, pw.ImageProvider> imagenesDecodificadas) {
    final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const regularStyle = pw.TextStyle(fontSize: 9);
    final greyBg = PdfColors.grey300;

    pw.Widget celdaLabel(String texto, {pw.TextAlign align = pw.TextAlign.center, PdfColor colorTexto = PdfColors.black}) => pw.Container(
      padding: const pw.EdgeInsets.all(5), alignment: align == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(texto, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: colorTexto), textAlign: align),
    );
    pw.Widget celdaValor(String texto) => pw.Container(padding: const pw.EdgeInsets.all(5), alignment: pw.Alignment.centerLeft, child: pw.Text(texto, style: regularStyle));

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

      if (imagenesDecodificadas.containsKey(i)) {
        evidenciasWidgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
          if (textoEvidencia.isNotEmpty) pw.SizedBox(height: 4),
          pw.Center(child: pw.Image(imagenesDecodificadas[i]!, height: 60, fit: pw.BoxFit.contain)),
        ]));
      } else {
        if (rawEvidencia.contains('IMAGEN_ADJUNTA:') || rawEvidencia.contains('http') || rawEvidencia.contains('data:image')) {
          evidenciasWidgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 4),
            pw.Text('[Imagen omitida]', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800)),
          ]));
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

    String q1 = row['cumple_flujo_resolucion']?.toString() ?? 'PD';
    String q2 = row['resolucion_primera_linea']?.toString() ?? 'PD';
    String q3 = row['secuencia_tiene_sentido']?.toString() ?? 'PD';
    String q4 = row['porques_con_evidencia']?.toString() ?? 'PD';
    String q5 = row['encontro_causa_raiz']?.toString() ?? 'PD';
    String q6 = row['proponen_acciones_eliminacion']?.toString() ?? 'PD';

    String estadoEval = row['estado']?.toString().toUpperCase() ?? 'PENDIENTE';
    String calificacion = estadoEval == 'PENDIENTE' ? '0.0%' : (row['resultado']?.toString() ?? '0.0%');
    String obsEval = estadoEval == 'PENDIENTE' ? 'Pendiente' : (row['observacion_evaluador']?.toString() ?? '-');
    String resultado2 = row['resultado_2']?.toString() ?? (estadoEval == 'APTO' ? 'No aplica' : 'Pendiente');
    String ultimaAprovacion = row['ultima aprovacion']?.toString() ?? row['ultima_aprovacion']?.toString() ?? (estadoEval == 'APTO' ? 'No aplica' : 'Pendiente');
    String obs2 = row['Observacion 2']?.toString() ?? row['observacion_2']?.toString() ?? '-';

    return [
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1.2), 1: const pw.FlexColumnWidth(3.5), 2: const pw.FlexColumnWidth(1.2) },
          children: [
            pw.TableRow(
                children: [
                  pw.Container(height: 40, padding: const pw.EdgeInsets.all(5), alignment: pw.Alignment.center, child: imgLogo != null ? pw.Image(imgLogo, fit: pw.BoxFit.contain) : pw.SizedBox()),
                  pw.Container(color: greyBg, alignment: pw.Alignment.center, child: pw.Text('Revisión 5 porqués', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))),
                  pw.Container(alignment: pw.Alignment.center, child: pw.Text('ABInBev', style: pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold, fontSize: 14))),
                ]
            )
          ]
      ),
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(2.5), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.5) },
          children: [
            pw.TableRow(children: [ celdaLabel('Fecha:'), celdaValor(fecha), celdaLabel('Turno:'), celdaValor(turno) ]),
            pw.TableRow(children: [ celdaLabel('Área:'), celdaValor(area), celdaLabel('PI:'), celdaValor(pi) ]),
          ]
      ),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(5) }, children: [
        pw.TableRow(children: [ celdaLabel('Participantes:'), celdaValor(participantes) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Información del disparador:', style: boldStyle)) ]),
        pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(disparador, style: regularStyle)) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Contención:', style: boldStyle)) ]),
        pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(contencion, style: regularStyle)) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('5 Porqués', style: boldStyle)) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), columnWidths: { 0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(2) }, children: [
        pw.TableRow(children: [
          pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Responda los 5 porqués', style: boldStyle)),
          pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Evidencias', style: boldStyle))
        ]),
      ]),
      ...List.generate(5, (index) {
        String pq = row['porque_${index + 1}']?.toString() ?? '';
        String ex = row['explique_porque_${index + 1}']?.toString() ?? '';
        return pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FixedColumnWidth(25), 1: const pw.FixedColumnWidth(65), 2: const pw.FlexColumnWidth(3), 3: const pw.FlexColumnWidth(2) },
            children: [
              pw.TableRow(
                  children: [
                    pw.Container(alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(4), child: pw.Text('${index + 1}', style: regularStyle)),
                    pw.Container(alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(4), child: pw.Text('¿Por qué?', style: regularStyle)),
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Container(padding: const pw.EdgeInsets.all(4), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Text(pq.isEmpty ? ' ' : pq, style: boldStyle, textAlign: pw.TextAlign.center)),
                          pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(ex.isEmpty ? ' ' : ex, style: regularStyle)),
                        ]
                    ),
                    pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: evidenciasWidgets[index])
                  ]
              )
            ]
        );
      }),
      if (estadoEval == 'APTO' || estadoEval == 'NO APTO' || estadoEval == 'PENDIENTE') ...[
        pw.SizedBox(height: 15),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            children: [
              pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('EVALUACIÓN DE CALIDAD Y REVISIÓN', style: boldStyle)) ]),
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1) },
            children: [
              pw.TableRow(children: [celdaValor('1. Flujo de resolución adecuado'), celdaLabel(q1, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('2. Resolución con primera línea'), celdaLabel(q2, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('3. Secuencia tiene sentido'), celdaLabel(q3, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('4. Porqués con evidencia'), celdaLabel(q4, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('5. Encontró causa raíz'), celdaLabel(q5, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('6. Acciones de eliminación'), celdaLabel(q6, align: pw.TextAlign.center)]),
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1) },
            children: [
              pw.TableRow(children: [
                celdaLabel('Calificación:'),
                celdaLabel(calificacion, colorTexto: estadoEval == 'APTO' ? PdfColors.green800 : PdfColors.red800),
                celdaLabel('Estado:'),
                celdaLabel(estadoEval, colorTexto: estadoEval == 'APTO' ? PdfColors.green800 : PdfColors.red800),
              ])
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.5) },
            children: [
              pw.TableRow(children: [
                celdaLabel('Resultado 2:'),
                celdaLabel(resultado2, colorTexto: PdfColors.blue800),
                celdaLabel('Última Aprobación:'),
                celdaLabel(ultimaAprovacion, colorTexto: PdfColors.blue800),
              ])
            ]
        ),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
          pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Obs Evaluador 1:', style: boldStyle)) ]),
          pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obsEval, style: regularStyle)) ]),
        ]),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
          pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Obs Evaluador 2:', style: boldStyle)) ]),
          pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obs2, style: regularStyle)) ]),
        ]),
      ]
    ];
  }

  Future<void> _generarYDescargarPDF(Map<String, dynamic> row) async {
    setState(() { _idGenerandoPdf = row['id'].toString(); });
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      Map<int, pw.ImageProvider> imagenesListas = await _preDecodificarImagenes(row);

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) => _construirPaginasPdf(row, imgLogo, imagenesListas),
      ));

      final bytesPdf = await doc.save();
      String areaNom = (row['area']?.toString() ?? 'General').replaceAll(' ', '_');
      String fecha = row['fecha']?.toString().split('T')[0] ?? '-';

      await Printing.sharePdf(bytes: bytesPdf, filename: 'Revision_5Why_${fecha}_$areaNom.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _idGenerandoPdf = null; });
    }
  }

  Future<void> _descargarMultiplesPDFs() async {
    if (_seleccionados.isEmpty) return;
    setState(() { _generandoMultiplesPdf = true; });
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      List<Map<String, dynamic>> registrosSeleccionados = _registrosFiltrados.where((r) => _seleccionados.contains(r['id'].toString())).toList();

      for (var row in registrosSeleccionados) {
        Map<int, pw.ImageProvider> imagenesListas = await _preDecodificarImagenes(row);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) => _construirPaginasPdf(row, imgLogo, imagenesListas),
        ));
      }

      final bytesPdf = await doc.save();
      await Printing.sharePdf(bytes: bytesPdf, filename: 'Reporte_Masivo_Revisiones_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDFs múltiples: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _generandoMultiplesPdf = false; });
    }
  }

  void _abrirModalEvaluacion(Map<String, dynamic> row) {
    dynamic id = row['id'];
    String estadoActual = (row['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
    bool yaEvaluado = estadoActual != 'PENDIENTE';
    bool esApto = estadoActual == 'APTO';

    String? q1 = row['cumple_flujo_resolucion']?.toString();
    String? q2 = row['resolucion_primera_linea']?.toString();
    String? q3 = row['secuencia_tiene_sentido']?.toString();
    String? q4 = row['porques_con_evidencia']?.toString();
    String? q5 = row['encontro_causa_raiz']?.toString();
    String? q6 = row['proponen_acciones_eliminacion']?.toString();
    TextEditingController obsCtrl = TextEditingController(text: row['observacion_evaluador']?.toString() ?? '');

    String? res2Db = row['resultado_2']?.toString();
    if (res2Db == 'NULL') res2Db = '';
    TextEditingController res2Ctrl = TextEditingController(text: res2Db ?? '');

    String? obs2Db = row['Observacion 2']?.toString() ?? row['observacion_2']?.toString();
    if (obs2Db == 'NULL') obs2Db = '';
    TextEditingController obs2Ctrl = TextEditingController(text: obs2Db ?? '');

    String? ultApDb = row['ultima aprovacion']?.toString() ?? row['ultima_aprovacion']?.toString();
    if (ultApDb == 'NULL' || ultApDb == null || ultApDb.trim().isEmpty) ultApDb = null;
    String? ultimaAprobacion = ultApDb;

    bool guardando = false;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (dialogContext, setModalState) {

                List<String?> respuestas = [q1, q2, q3, q4, q5, q6];
                int respondidas = respuestas.where((r) => r != null && r.isNotEmpty && r != 'NULL').length;
                int siCount = respuestas.where((r) => r == 'SI').length;

                double porcentaje = 0;
                String estadoCalculado = 'PENDIENTE';
                Color colorEstado = Colors.orange;

                if (respondidas == 6) {
                  porcentaje = (siCount / 6) * 100;
                  if (porcentaje == 100.0) {
                    estadoCalculado = 'APTO';
                    colorEstado = Colors.green;
                  } else {
                    estadoCalculado = 'NO APTO';
                    colorEstado = Colors.red;
                  }
                }

                if (yaEvaluado) {
                  colorEstado = estadoActual == 'APTO' ? Colors.green : Colors.red;
                }

                bool isMobile = MediaQuery.of(ctx).size.width < 700;

                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: _colorBackground,
                  insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
                  child: SizedBox(
                    width: isMobile ? double.infinity : 900,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(color: _colorEncabezados, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.fact_check_rounded, color: Colors.white, size: 24),
                                  SizedBox(width: 10),
                                  Text('Revisión y Calidad 5 Why', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
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
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: _sombraCards),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('📄 DETALLES DEL REPORTE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1E293B))),
                                        const SizedBox(height: 16),

                                        _datoRow('Fecha Evento:', row['fecha']?.toString().split('T')[0] ?? '-'),
                                        _datoRow('Área / Proceso:', row['area']?.toString() ?? '-'),
                                        _datoRow('PI Afectado:', row['pi']?.toString() ?? '-'),
                                        _datoRow('Participantes:', row['participantes']?.toString() ?? '-'),
                                        _datoRow('Valor Disparador:', row['valor_disparador_alcanzado']?.toString() ?? '-'),
                                        _datoRow('Contención Inmediata:', row['contencion_problema']?.toString() ?? '-'),

                                        Builder(
                                            builder: (context) {
                                              String causaRaizDesc = row['causa_raiz']?.toString() ?? row['causa raiz']?.toString() ?? '';
                                              if (causaRaizDesc.trim().isNotEmpty && causaRaizDesc != 'NULL') {
                                                return _datoRow('Causa Raíz Descrita:', causaRaizDesc);
                                              }
                                              return const SizedBox();
                                            }
                                        ),

                                        const Divider(height: 30),
                                        const Text('Desarrollo de los 5 Porqués:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                                        const SizedBox(height: 12),
                                        ...List.generate(5, (index) {
                                          String pq = row['porque_${index + 1}']?.toString() ?? '';
                                          String ex = row['explique_porque_${index + 1}']?.toString() ?? '';
                                          String ev = row['evidencia_porque_${index + 1}']?.toString() ?? '';

                                          if (pq.isEmpty && ex.isEmpty) return const SizedBox();

                                          Widget evWidget = Text(ev.isEmpty ? 'Sin evidencia adjunta' : ev, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic));

                                          if (ev.contains('IMAGEN_ADJUNTA:')) {
                                            final parts = ev.split('IMAGEN_ADJUNTA:');
                                            final textEv = parts[0].replaceAll('|', '').trim();
                                            final b64 = parts[1].replaceAll('data:image/jpeg;base64,', '').replaceAll('data:image/png;base64,', '').trim();

                                            evWidget = Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (textEv.isNotEmpty) Text(textEv, style: const TextStyle(fontSize: 12)),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () => _mostrarPreviewImagen(b64, isBase64: true),
                                                  child: Container(
                                                    height: 80, width: 120,
                                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                                                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(base64Decode(b64), fit: BoxFit.cover, errorBuilder: (c,e,s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)))),
                                                  ),
                                                )
                                              ],
                                            );
                                          } else if (ev.contains('http')) {
                                            int httpIndex = ev.indexOf('http');
                                            String url = ev.substring(httpIndex).trim();
                                            String textEv = ev.substring(0, httpIndex).replaceAll('|', '').trim();

                                            evWidget = Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (textEv.isNotEmpty) Text(textEv, style: const TextStyle(fontSize: 12)),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () => _mostrarPreviewImagen(url, isBase64: false),
                                                  child: Container(
                                                    height: 80, width: 120,
                                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                                                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(url, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)))),
                                                  ),
                                                )
                                              ],
                                            );
                                          } else if (ev.contains('data:image')) {
                                            int dataIndex = ev.indexOf('data:image');
                                            String b64 = ev.substring(dataIndex).replaceAll('data:image/jpeg;base64,', '').replaceAll('data:image/png;base64,', '').trim();
                                            String textEv = ev.substring(0, dataIndex).replaceAll('|', '').trim();

                                            evWidget = Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (textEv.isNotEmpty) Text(textEv, style: const TextStyle(fontSize: 12)),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () => _mostrarPreviewImagen(b64, isBase64: true),
                                                  child: Container(
                                                    height: 80, width: 120,
                                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                                                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(base64Decode(b64), fit: BoxFit.cover, errorBuilder: (c,e,s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)))),
                                                  ),
                                                )
                                              ],
                                            );
                                          }

                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 12),
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('¿Por qué ${index + 1}?', style: TextStyle(fontWeight: FontWeight.bold, color: _colorPrincipal, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Text(pq, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                                const Divider(height: 20),
                                                const Text('Respuesta / Explicación:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B))),
                                                const SizedBox(height: 2),
                                                Text(ex, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                                const Divider(height: 20),
                                                const Text('Evidencia:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B))),
                                                const SizedBox(height: 4),
                                                evWidget,
                                              ],
                                            ),
                                          );
                                        }),

                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  // BLOQUE 1: CALIFICACIÓN DEL REVISOR
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: yaEvaluado ? Colors.grey.shade300 : _colorPrincipal, width: yaEvaluado ? 1.0 : 2.0), boxShadow: _sombraCards),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(yaEvaluado ? '🔒 EVALUACIÓN DE CALIDAD (Solo lectura)' : '✅ EVALUACIÓN DE CALIDAD', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: yaEvaluado ? Colors.grey.shade700 : _colorPrincipal)),
                                        const SizedBox(height: 8),
                                        const Text('Basado en la lectura del reporte superior, califique los siguientes criterios:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        const SizedBox(height: 20),
                                        _buildOpcionEvaluacion('1. ¿Se cumple con el flujo de resolución de problemas (participación adecuada)?', q1, (val) => setModalState(() => q1 = val), disabled: yaEvaluado),
                                        _buildOpcionEvaluacion('2. ¿La resolución se llevó a cabo con la primera línea (operadores y técnicos)?', q2, (val) => setModalState(() => q2 = val), disabled: yaEvaluado),
                                        _buildOpcionEvaluacion('3. ¿La secuencia de resolución tiene sentido lógico?', q3, (val) => setModalState(() => q3 = val), disabled: yaEvaluado),
                                        _buildOpcionEvaluacion('4. ¿Todos los porqués cuentan con evidencia?', q4, (val) => setModalState(() => q4 = val), disabled: yaEvaluado),
                                        _buildOpcionEvaluacion('5. ¿Se encontró la Causa Raíz real?', q5, (val) => setModalState(() => q5 = val), disabled: yaEvaluado),
                                        _buildOpcionEvaluacion('6. ¿Se proponen acciones efectivas para eliminar la causa?', q6, (val) => setModalState(() => q6 = val), disabled: yaEvaluado),

                                        const SizedBox(height: 16),
                                        const Divider(),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Calificación: ${yaEvaluado ? row['resultado'] : porcentaje.toStringAsFixed(1)}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colorEstado)),
                                            Row(
                                              children: [
                                                const Text('Estado: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(border: Border.all(color: colorEstado), borderRadius: BorderRadius.circular(6), color: colorEstado.withOpacity(0.1)),
                                                  child: Text(yaEvaluado ? estadoActual : estadoCalculado, style: TextStyle(color: colorEstado, fontWeight: FontWeight.w900, fontSize: 14)),
                                                )
                                              ],
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        TextFormField(
                                          controller: obsCtrl,
                                          maxLines: 2,
                                          readOnly: yaEvaluado,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: _inputDecor('Detalle por qué no es apto u otra observación...').copyWith(labelText: 'Observación del Evaluador', floatingLabelBehavior: FloatingLabelBehavior.always, fillColor: yaEvaluado ? Colors.grey.shade100 : Colors.white),
                                        )
                                      ],
                                    ),
                                  ),

                                  // BLOQUE 2: SEGUNDA REVISIÓN Y APROBACIÓN FINAL (SÓLO SI ES NO APTO)
                                  if (yaEvaluado && !esApto) ...[
                                    const SizedBox(height: 24),
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.blue.shade200, width: 1.5)
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('🔄 SEGUNDA REVISIÓN Y APROBACIÓN FINAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1976D2))),
                                          const SizedBox(height: 20),

                                          const Text('Última Aprobación:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                          const SizedBox(height: 6),
                                          DropdownButtonFormField<String>(
                                            value: ['APROBADO', 'NO APROBADO', 'VOLVER A REVISAR', 'No aplica'].contains(ultimaAprobacion) ? ultimaAprobacion : null,
                                            decoration: _inputDecor('Seleccione el estado final...'),
                                            items: ['APROBADO', 'NO APROBADO', 'VOLVER A REVISAR', 'No aplica'].map((e) {
                                              Color colorOpcion = Colors.black87;
                                              if (e == 'APROBADO') colorOpcion = Colors.green;
                                              if (e == 'NO APROBADO') colorOpcion = Colors.red;
                                              if (e == 'VOLVER A REVISAR') colorOpcion = Colors.orange.shade800;
                                              return DropdownMenuItem(value: e, child: Text(e, style: TextStyle(fontWeight: FontWeight.bold, color: colorOpcion)));
                                            }).toList(),
                                            onChanged: (val) => setModalState(() => ultimaAprobacion = val),
                                          ),
                                          const SizedBox(height: 16),

                                          const Text('Resultado 2 (Recalificación):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: res2Ctrl,
                                            style: const TextStyle(fontSize: 12),
                                            decoration: _inputDecor('Ej: 100%, 80%, No aplica...'),
                                          ),
                                          const SizedBox(height: 16),

                                          const Text('Observación 2:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: obs2Ctrl,
                                            maxLines: 2,
                                            style: const TextStyle(fontSize: 12),
                                            decoration: _inputDecor('Comentarios de la segunda revisión o conclusión final...'),
                                          ),
                                        ],
                                      ),
                                    )
                                  ],

                                ],
                              )
                          ),
                        ),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: (yaEvaluado && esApto)
                                ? [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: ElevatedButton.styleFrom(backgroundColor: _colorEncabezados, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), elevation: 0),
                                child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold)),
                              )
                            ]
                                : [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: guardando ? null : () async {

                                  if (!yaEvaluado) {
                                    if (respondidas < 6) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe responder todas las preguntas (SÍ/NO) para confirmar la primera revisión.'), backgroundColor: Colors.orange));
                                      return;
                                    }
                                    if (estadoCalculado == 'NO APTO' && obsCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Como el estado es NO APTO, debe colocar una observación.'), backgroundColor: Colors.red));
                                      return;
                                    }
                                  } else {
                                    if (ultimaAprobacion == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe seleccionar una opción en Última Aprobación.'), backgroundColor: Colors.orange));
                                      return;
                                    }
                                  }

                                  setModalState(() => guardando = true);

                                  final payload = {
                                    'cumple_flujo_resolucion': q1,
                                    'resolucion_primera_linea': q2,
                                    'secuencia_tiene_sentido': q3,
                                    'porques_con_evidencia': q4,
                                    'encontro_causa_raiz': q5,
                                    'proponen_acciones_eliminacion': q6,
                                    'resultado': yaEvaluado ? row['resultado'] : '${porcentaje.toStringAsFixed(1)}%',
                                    'estado': yaEvaluado ? estadoActual : estadoCalculado,
                                    'observacion_evaluador': yaEvaluado ? row['observacion_evaluador'] : (obsCtrl.text.trim().isEmpty && estadoCalculado == 'APTO' ? 'Cumple al 100%' : obsCtrl.text.trim()),

                                    'resultado_2': yaEvaluado ? res2Ctrl.text.trim() : (estadoCalculado == 'APTO' ? 'No aplica' : 'Pendiente por revisión'),
                                    'Observacion 2': yaEvaluado ? obs2Ctrl.text.trim() : '',
                                    'ultima aprovacion': yaEvaluado ? ultimaAprobacion : (estadoCalculado == 'APTO' ? 'No aplica' : 'Pendiente por revisión'),

                                    'estado_revicion': 'Revisado',
                                  };

                                  try {
                                    await ApiService.actualizar('gestion', '5why', 'id', id, payload);
                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisión actualizada correctamente'), backgroundColor: Colors.green));
                                      _cargarDatos();
                                    }
                                  } catch (e) {
                                    setModalState(() => guardando = false);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red));
                                  }
                                },
                                icon: guardando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 16),
                                label: Text(guardando ? 'Guardando...' : 'Confirmar Revisión', style: const TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: _colorPrincipal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), elevation: 0),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  Widget _buildOpcionEvaluacion(String pregunta, String? valorActual, Function(String) onSelect, {bool disabled = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(pregunta, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
          const SizedBox(width: 8),
          Row(
            children: ['SI', 'NO'].map((opcion) {
              bool isSelected = valorActual == opcion;
              Color activeColor = opcion == 'SI' ? Colors.green : Colors.redAccent;

              return GestureDetector(
                onTap: disabled ? null : () => onSelect(opcion),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor : (disabled ? Colors.grey.shade100 : Colors.white),
                    border: Border.all(color: isSelected ? activeColor : Colors.grey.shade300, width: isSelected ? 2 : 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(opcion, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade700)),
                ),
              );
            }).toList(),
          )
        ],
      ),
    );
  }

  // ==========================================
  // CONSTRUCCIÓN DEL LAYOUT VISUAL (MÉTODO BUILD)
  // ==========================================
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
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: widget.onToggleSidebar),
        title: const Text('Revisión 5 Why', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _cargarDatos)
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

            _buildDashboardTarjetas(),
            const SizedBox(height: 20),

            _buildNuevaSeccionAdherenciaGrafico(),
            const SizedBox(height: 20),

            _buildTablasResumen(),
            const SizedBox(height: 20),

            _buildTablaGestion(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity, margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade600)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w600))),
          ElevatedButton(
            onPressed: _cargarDatos,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade600, foregroundColor: Colors.white, elevation: 0),
            child: const Text('REINTENTAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildBarraFiltros() {
    bool hayFiltrosActivos = _fechaDesde != null || _fechaHasta != null || _filtroPI != 'Todos' || _filtroArea != 'Todas' || _filtroEstado != 'TODOS' || _busquedaTexto.isNotEmpty;

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
              Row(
                children: [
                  Icon(Icons.filter_alt_rounded, color: _colorPrincipal, size: 18),
                  const SizedBox(width: 8),
                  Text('Filtros y Búsqueda', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _colorTextoOscuro)),
                ],
              ),
              if (hayFiltrosActivos)
                InkWell(
                  onTap: _limpiarFiltros,
                  child: const Text('🧹 Limpiar Filtros', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _buildSelectorFecha('DESDE', _fechaDesde ?? DateTime.now(), (d) => setState(() => _fechaDesde = d)),
              _buildSelectorFecha('HASTA', _fechaHasta ?? DateTime.now(), (d) => setState(() => _fechaHasta = d)),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ÁREA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  Container(
                    height: 38, width: 140, padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filtroArea, isExpanded: true, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                        icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF94A3B8)),
                        items: _listaFiltroArea.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setState(() { _filtroArea = val!; _aplicarFiltros(); }),
                      ),
                    ),
                  )
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PI AFECTADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  Container(
                    height: 38, width: 140, padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filtroPI, isExpanded: true, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                        icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF94A3B8)),
                        items: _listaFiltroPI.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setState(() { _filtroPI = val!; _aplicarFiltros(); }),
                      ),
                    ),
                  )
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ESTADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  Container(
                    height: 38, width: 150, padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filtroEstado, isExpanded: true, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                        icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF94A3B8)),
                        items: ['TODOS', 'PENDIENTE', 'APTO', 'NO APTO', 'APROBADO', 'NO APROBADO', 'VOLVER A REVISAR'].map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setState(() { _filtroEstado = val!; _aplicarFiltros(); }),
                      ),
                    ),
                  )
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BUSCAR (EVENTO, DISP)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 200, height: 38,
                    child: TextField(
                      controller: _buscarCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Término de búsqueda...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (v) { _busquedaTexto = v; _aplicarFiltros(); },
                    ),
                  ),
                ],
              ),

              ElevatedButton.icon(
                onPressed: _aplicarFiltros,
                icon: const Icon(Icons.filter_alt_rounded, size: 16),
                label: const Text('FILTRAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorPrincipal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorFecha(String label, DateTime fecha, Function(DateTime) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) onSelect(p);
          },
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildDashboardTarjetas() {
    return Row(
      children: [
        Expanded(child: _buildKPICard('TOTAL REPORTES', '$_totalReportes', Icons.assignment_outlined, const Color(0xFF2196F3))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('PENDIENTES REVISIÓN', '$_totalPendientes', Icons.pending_actions_rounded, const Color(0xFFFF9800))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('AVANCE REVISIÓN', '${_porcentajeRevisados.toStringAsFixed(1)}%', Icons.pie_chart_outline_rounded, const Color(0xFF9C27B0))),
      ],
    );
  }

  Widget _buildKPICard(String titulo, String valor, IconData icono, Color colorIcono) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: _sombraCards,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorIcono.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, color: colorIcono, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(valor, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBase({required String titulo, Widget? actionRight, required Widget child}) {
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
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)))),
              if (actionRight != null) actionRight,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildNuevaSeccionAdherenciaGrafico() {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return Column(
        children: [
          _buildTablaAdherencia(),
          const SizedBox(height: 20),
          _buildGraficoCircularEstados(),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: _buildTablaAdherencia()),
          const SizedBox(width: 20),
          Expanded(flex: 1, child: _buildGraficoCircularEstados()),
        ],
      );
    }
  }

  Widget _buildTablaAdherencia() {
    Map<String, String> textosPreguntas = {
      'cumple_flujo_resolucion': 'Se cumple con el flujo de resolución de problemas',
      'resolucion_primera_linea': 'La resolución se llevó a cabo con la primera línea',
      'secuencia_tiene_sentido': 'La secuencia de la resolución tiene sentido',
      'porques_con_evidencia': 'Todos los porqués cuentan con evidencia',
      'encontro_causa_raiz': 'Se encontró causa raíz',
      'proponen_acciones_eliminacion': 'Se proponen acciones de eliminación',
    };

    return _buildCardBase(
      titulo: 'Adherencia por Calificación',
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(color: _colorEncabezados, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
              child: const Row(
                children: [
                  Expanded(flex: 4, child: Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('PREGUNTA / CRITERIO EVALUADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)))),
                  Expanded(flex: 1, child: Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('% ADHERENCIA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center))),
                  Expanded(flex: 1, child: Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('BARRA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center))),
                ],
              ),
            ),
            if (_adherenciaPreguntas.isEmpty || _totalRevisados == 0)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Colors.white),
                child: const Text('Aún no hay reportes revisados (Apto/No Apto) para calcular adherencia.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
              ),
            ...textosPreguntas.entries.toList().asMap().entries.map((entry) {
              int i = entry.key;
              var e = entry.value;
              double pct = _adherenciaPreguntas[e.key] ?? 0.0;
              Color colorBarra = pct >= 80 ? Colors.green : (pct >= 50 ? Colors.orange : Colors.red);
              Color rowColor = i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC);

              return Container(
                decoration: BoxDecoration(color: rowColor, border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text(e.value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))))),
                    Expanded(flex: 1, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorBarra), textAlign: TextAlign.center))),
                    Expanded(
                        flex: 1,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
                                FractionallySizedBox(widthFactor: pct / 100, child: Container(height: 12, decoration: BoxDecoration(color: colorBarra.withOpacity(0.8), borderRadius: BorderRadius.circular(4)))),
                              ],
                            )
                        )
                    ),
                  ],
                ),
              );
            }).toList()
          ],
        ),
      ),
    );
  }

  Widget _buildGraficoCircularEstados() {
    return _buildCardBase(
      titulo: 'Distribución de Estados',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          SizedBox(
            height: 150, width: 150,
            child: CustomPaint(
              painter: _PieChartPainter(aptos: _totalAptos, noAptos: _totalNoAptos, pendientes: _totalPendientes),
            ),
          ),
          const SizedBox(height: 30),
          _leyendaPie('Aptos', _totalAptos, Colors.green),
          const SizedBox(height: 8),
          _leyendaPie('No Aptos', _totalNoAptos, Colors.red),
          const SizedBox(height: 8),
          _leyendaPie('Pendientes', _totalPendientes, Colors.orange),
        ],
      ),
    );
  }

  Widget _leyendaPie(String label, int valor, Color color) {
    double pct = _totalReportes == 0 ? 0 : (valor / _totalReportes) * 100;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
        Text('$valor (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  Widget _buildTablasResumen() {
    bool isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      return Column(
        children: [
          _buildTablaTop10('Pendientes por Área (Top 10)', 'ÁREA', _pendientesPorArea, Colors.blue),
          const SizedBox(height: 20),
          _buildTablaTop10('Pendientes por PI (Top 10)', 'PI AFECTADO', _pendientesPorPI, Colors.teal),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTablaTop10('Pendientes por Área (Top 10)', 'ÁREA', _pendientesPorArea, Colors.blue)),
          const SizedBox(width: 20),
          Expanded(child: _buildTablaTop10('Pendientes por PI (Top 10)', 'PI AFECTADO', _pendientesPorPI, Colors.teal)),
        ],
      );
    }
  }

  Widget _buildTablaTop10(String titulo, String headerCol1, Map<String, int> datos, Color colorBarra) {
    var top10 = datos.entries.take(10).toList();
    int totalTop = top10.fold(0, (sum, e) => sum + e.value);

    return _buildCardBase(
        titulo: titulo,
        child: Container(
          height: 250,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(color: _colorEncabezados, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text(headerCol1, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)))),
                    const Expanded(flex: 1, child: Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('PENDIENTES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center))),
                    const Expanded(flex: 1, child: Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('PESO %', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center))),
                  ],
                ),
              ),
              if (top10.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Colors.white),
                  child: const Text('Sin pendientes', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: top10.length,
                  itemBuilder: (ctx, i) {
                    var e = top10[i];
                    double pct = _totalPendientes == 0 ? 0 : (e.value / _totalPendientes) * 100;
                    Color rowColor = i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC);
                    return Container(
                      decoration: BoxDecoration(color: rowColor, border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))))),
                          Expanded(flex: 1, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('${e.value}', style: const TextStyle(fontSize: 11, color: Colors.black87), textAlign: TextAlign.center))),
                          Expanded(
                              flex: 1,
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                  child: Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      Container(height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
                                      FractionallySizedBox(widthFactor: pct / 100, child: Container(height: 12, decoration: BoxDecoration(color: colorBarra.withOpacity(0.6), borderRadius: BorderRadius.circular(4)))),
                                      Center(child: Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87))),
                                    ],
                                  )
                              )
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (top10.isNotEmpty)
                Container(
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)), border: Border(top: BorderSide(color: Colors.orange.shade200))),
                  child: Row(
                    children: [
                      const Expanded(flex: 3, child: Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('TOTALES MOSTRADOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black87)))),
                      Expanded(flex: 1, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text('$totalTop', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black87), textAlign: TextAlign.center))),
                      Expanded(flex: 1, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), child: Text(_totalPendientes == 0 ? '0%' : '${((totalTop / _totalPendientes) * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black87), textAlign: TextAlign.center))),
                    ],
                  ),
                )
            ],
          ),
        )
    );
  }

  Widget _buildTablaGestion() {
    int inicio = (_paginaActual - 1) * _registrosPorPagina;
    int fin = min(inicio + _registrosPorPagina, _registrosFiltrados.length);
    List<Map<String, dynamic>> paginaLista = _registrosFiltrados.isEmpty ? [] : _registrosFiltrados.sublist(inicio, fin);
    int totalPaginas = max(1, (_registrosFiltrados.length / _registrosPorPagina).ceil());
    bool todosSeleccionados = paginaLista.isNotEmpty && paginaLista.every((r) => _seleccionados.contains(r['id'].toString()));

    List<Map<String, dynamic>> columnas = [
      {'key': 'sel', 'label': '', 'w': 40.0},
      {'key': 'fecha', 'label': 'FECHA EVENTO', 'w': 100.0},
      {'key': 'area', 'label': 'ÁREA', 'w': 120.0},
      {'key': 'pi', 'label': 'PI AFECTADO', 'w': 140.0},
      {'key': 'disp', 'label': 'DISPARADOR', 'w': 240.0},
      {'key': 'part', 'label': 'PARTICIPANTES', 'w': 160.0},
      {'key': 'estado', 'label': 'ESTADO', 'w': 120.0},
      {'key': 'obs1', 'label': 'OBSERVACIÓN 1', 'w': 200.0},
      {'key': 'obs2', 'label': 'OBSERVACIÓN 2', 'w': 200.0},
      {'key': 'res', 'label': 'RES. FINAL', 'w': 120.0},
      {'key': 'gest', 'label': 'GESTIÓN', 'w': 240.0},
    ];

    double totalWidth = columnas.fold<double>(0.0, (p, c) => p + (c['w'] as double));

    return _buildCardBase(
        titulo: 'Detalles y Gestión de Revisiones',
        actionRight: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_seleccionados.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _generandoMultiplesPdf ? null : _descargarMultiplesPDFs,
                  icon: _generandoMultiplesPdf
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded, size: 14),
                  label: Text('DESCARGAR SELECC. (${_seleccionados.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorPrincipal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _descargarExcel,
                icon: const Icon(Icons.table_view_rounded, size: 14),
                label: const Text('EXCEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Mostrar ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Container(
                  height: 30, padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _registrosPorPagina,
                      style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                      icon: const Icon(Icons.arrow_drop_down, size: 16),
                      items: [10, 25, 50, 100].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                      onChanged: (v) => setState(() { _registrosPorPagina = v!; _paginaActual = 1; }),
                    ),
                  ),
                ),
                const Text(' registros', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 14),

            Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
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
                            decoration: BoxDecoration(color: _colorEncabezados),
                            child: Row(
                              children: columnas.map((c) {
                                if (c['key'] == 'sel') {
                                  return Container(
                                    width: c['w'] as double,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Theme(
                                      data: ThemeData(unselectedWidgetColor: Colors.white70),
                                      child: Checkbox(
                                        value: todosSeleccionados,
                                        onChanged: paginaLista.isEmpty ? null : (v) => _toggleSeleccionarTodos(paginaLista),
                                        activeColor: _colorPrincipal,
                                        checkColor: Colors.white,
                                      ),
                                    ),
                                  );
                                }
                                return _headerCell(c['label'] as String, width: c['w'] as double);
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
                              String fecha = rawF.isNotEmpty ? rawF.split('T')[0].split(' ')[0] : 'N/A';

                              String estadoOriginal = (r['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
                              String ultAp = (r['ultima aprovacion']?.toString() ?? r['ultima_aprovacion']?.toString() ?? '').toUpperCase();
                              String obs1 = r['observacion_evaluador']?.toString() ?? '-';
                              if (obs1.trim().isEmpty || obs1 == 'NULL') obs1 = '-';
                              String obs2 = r['Observacion 2']?.toString() ?? r['observacion_2']?.toString() ?? '-';
                              if (obs2.trim().isEmpty || obs2 == 'NULL') obs2 = '-';

                              String estadoMostrar = estadoOriginal;
                              if (estadoOriginal != 'PENDIENTE' && ultAp.isNotEmpty && ultAp != 'NULL' && ultAp != 'NO APLICA' && ultAp != 'PENDIENTE POR REVISIÓN') {
                                estadoMostrar = ultAp;
                              }

                              bool bloqueado = (estadoMostrar == 'APTO' || estadoMostrar == 'APROBADO');

                              Color colorEst = Colors.orange.shade800;
                              if (estadoMostrar == 'APTO' || estadoMostrar == 'APROBADO') colorEst = Colors.green;
                              else if (estadoMostrar == 'NO APTO' || estadoMostrar == 'NO APROBADO') colorEst = Colors.red;

                              String resFinal = r['ultima aprovacion']?.toString() ?? r['ultima_aprovacion']?.toString() ?? '-';
                              if (resFinal.trim().isEmpty || resFinal == 'NULL') resFinal = '-';

                              Color colorResFinal = Colors.black87;
                              if (resFinal == 'APROBADO' || resFinal == 'APTO') colorResFinal = Colors.green;
                              if (resFinal == 'NO APROBADO' || resFinal == 'NO APTO') colorResFinal = Colors.red;
                              if (resFinal == 'VOLVER A REVISAR') colorResFinal = Colors.orange.shade800;

                              Color rowColor = i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC);

                              return Container(
                                decoration: BoxDecoration(color: rowColor, border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                                child: Row(
                                  children: [
                                    Container(
                                      width: columnas[0]['w'] as double,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Checkbox(
                                        value: _seleccionados.contains(idRow),
                                        onChanged: (v) => _toggleSeleccion(idRow),
                                        activeColor: _colorPrincipal,
                                      ),
                                    ),
                                    _buildFixedCell(columnas[1]['w'] as double, fecha),
                                    _buildFixedCell(columnas[2]['w'] as double, r['area']?.toString() ?? 'N/A'),
                                    _buildFixedCell(columnas[3]['w'] as double, r['pi']?.toString() ?? 'N/A', isBold: true, color: _colorPrincipal),
                                    _buildFixedCell(columnas[4]['w'] as double, r['valor_disparador_alcanzado']?.toString() ?? 'N/A'),
                                    _buildFixedCell(columnas[5]['w'] as double, r['participantes']?.toString() ?? 'N/A'),
                                    Container(
                                      width: columnas[6]['w'] as double,
                                      padding: const EdgeInsets.all(8.0),
                                      alignment: Alignment.center,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(color: colorEst.withOpacity(0.1), border: Border.all(color: colorEst), borderRadius: BorderRadius.circular(4)),
                                        child: Text(estadoMostrar, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colorEst)),
                                      ),
                                    ),
                                    _buildFixedCell(columnas[7]['w'] as double, obs1, color: Colors.black54),
                                    _buildFixedCell(columnas[8]['w'] as double, obs2, color: Colors.black54),
                                    Container(
                                      width: columnas[9]['w'] as double,
                                      padding: const EdgeInsets.all(8.0),
                                      alignment: Alignment.center,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(color: colorResFinal != Colors.black87 ? colorResFinal.withOpacity(0.1) : Colors.grey.shade100, border: Border.all(color: colorResFinal != Colors.black87 ? colorResFinal : Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                                        child: Text(resFinal, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colorResFinal != Colors.black87 ? colorResFinal : Colors.black87)),
                                      ),
                                    ),
                                    Container(
                                      width: columnas[10]['w'] as double,
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      child: Wrap(
                                        spacing: 6, runSpacing: 4,
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (estadoOriginal == 'PENDIENTE')
                                            ElevatedButton.icon(
                                              onPressed: () async {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🤖 La IA está evaluando el reporte... espere unos segundos.'), duration: Duration(seconds: 4)));
                                                try {
                                                  await ApiService.auditarConIA(idRow);
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Auditoría IA completada con éxito'), backgroundColor: Colors.green));
                                                    _cargarDatos();
                                                  }
                                                } catch (e) {
                                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error IA: $e'), backgroundColor: Colors.red));
                                                }
                                              },
                                              icon: const Icon(Icons.smart_toy_rounded, size: 14),
                                              label: const Text('Auditor IA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: const Size(0, 30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                                            ),
                                          ElevatedButton.icon(
                                            onPressed: () => _abrirModalEvaluacion(r),
                                            icon: Icon(bloqueado ? Icons.visibility : Icons.edit, size: 12),
                                            label: Text(bloqueado ? 'Detalle' : 'Revisar', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(backgroundColor: bloqueado ? Colors.grey.shade300 : _colorPrincipal, foregroundColor: bloqueado ? Colors.black87 : Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), minimumSize: const Size(0, 30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                                          ),
                                          _idGenerandoPdf == idRow
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                                              : IconButton(
                                            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 18),
                                            tooltip: 'Descargar PDF',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _generarYDescargarPDF(r),
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
                  Text('Mostrando ${paginaLista.isEmpty ? 0 : inicio + 1} a $fin de ${_registrosFiltrados.length} reportes', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Row(
                    children: [
                      InkWell(onTap: _paginaActual > 1 ? () => setState(() => _paginaActual--) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4), color: Colors.white), child: const Text('Anterior', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)))),
                      const SizedBox(width: 8),
                      Text(' $_paginaActual / $totalPaginas ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                      const SizedBox(width: 8),
                      InkWell(onTap: _paginaActual < totalPaginas ? () => setState(() => _paginaActual++) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4), color: Colors.white), child: const Text('Siguiente', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)))),
                    ],
                  )
                ],
              ),
            )
          ],
        )
    );
  }

  Widget _headerCell(String text, {required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.left),
    );
  }

  Widget _buildFixedCell(double width, String text, {bool isBold = false, Color color = const Color(0xFF1E293B), TextAlign align = TextAlign.left}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color), textAlign: align, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final int aptos;
  final int noAptos;
  final int pendientes;

  _PieChartPainter({required this.aptos, required this.noAptos, required this.pendientes});

  @override
  void paint(Canvas canvas, Size size) {
    double total = (aptos + noAptos + pendientes).toDouble();
    if (total == 0) return;

    double startAngle = -pi / 2;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..style = PaintingStyle.fill;

    if (aptos > 0) {
      double sweep = (aptos / total) * 2 * pi;
      paint.color = Colors.green;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }

    if (noAptos > 0) {
      double sweep = (noAptos / total) * 2 * pi;
      paint.color = Colors.red;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }

    if (pendientes > 0) {
      double sweep = (pendientes / total) * 2 * pi;
      paint.color = Colors.orange;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
    }

    final innerPaint = Paint()..style = PaintingStyle.fill..color = Colors.white;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 3.5, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}