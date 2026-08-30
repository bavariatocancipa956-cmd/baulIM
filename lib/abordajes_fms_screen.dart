import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // Agregado para leer el logo
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api_service.dart';

class AbordajesFmsScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;
  final Map<String, dynamic>? usuario;

  const AbordajesFmsScreen({super.key, this.onToggleSidebar, this.usuario});

  @override
  State<AbordajesFmsScreen> createState() => _AbordajesFmsScreenState();
}

class _AbordajesFmsScreenState extends State<AbordajesFmsScreen> {
  final ScrollController _tablaScrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _cargando = true;
  String? _mensajeError;
  String? _idGenerandoPdf;

  List<Map<String, dynamic>> _todosLosAbordajes = [];
  List<Map<String, dynamic>> _abordajesFiltrados = [];

  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaOpms = ['Todos'];
  List<String> _listaAreasLogistica = [];

  String _busquedaTexto = '';
  String _supervisorSel = 'Todos';
  String _opmSel = 'Todos';
  String _estadoSel = 'Todos';

  final List<String> _listaEstados = ['Todos', 'PENDIENTE', 'REALIZADO'];

  int _registrosPorPagina = 10;
  int _paginaActual = 1;

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    super.dispose();
  }

  Future<Uint8List> _comprimirBytesMax15KB(Uint8List originalBytes, {int maxKB = 15, int startWidth = 800}) async {
    int maxBytes = maxKB * 1024;
    if (originalBytes.lengthInBytes <= maxBytes) return originalBytes;

    Uint8List bytes = originalBytes;
    int targetWidth = startWidth;

    while (bytes.lengthInBytes > maxBytes && targetWidth >= 60) {
      try {
        ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
        ui.FrameInfo frame = await codec.getNextFrame();
        ui.Image image = frame.image;
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData != null) {
          Uint8List newBytes = byteData.buffer.asUint8List();
          bytes = newBytes;
          if (newBytes.lengthInBytes <= maxBytes) return newBytes;
        }
      } catch (e) {
        break;
      }
      targetWidth -= 150;
    }
    return bytes;
  }

  Future<void> _cargarDatosBD() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      Set<String> areasSet = {};

      try {
        final areasRaw = await ApiService.consultar('fms', 'areas_logistica');
        if (areasRaw is List) {
          for (var a in areasRaw) {
            if (a is Map && a.isNotEmpty) {
              String nombreArea = '';
              if (a.containsKey('modulo')) {
                nombreArea = a['modulo']?.toString() ?? '';
              } else if (a.containsKey('MODULO')) {
                nombreArea = a['MODULO']?.toString() ?? '';
              } else if (a.values.isNotEmpty) {
                nombreArea = a.values.first?.toString() ?? '';
              }
              nombreArea = nombreArea.trim();
              if (nombreArea.isNotEmpty && nombreArea.toLowerCase() != 'null') {
                areasSet.add(nombreArea.toUpperCase());
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error leyendo areas_logistica (Silenciado): $e');
      }

      final datosRaw = await ApiService.consultar('fms', 'fms_reporte');
      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> superSet = {'Todos'};
      final Set<String> opmSet = {'Todos'};

      if (datosRaw is List) {
        for (var fila in datosRaw) {
          if (fila is Map) {
            final Map<String, dynamic> mapa = {};
            fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);

            String estadoAbordaje = (mapa['abordaje']?.toString() ?? '').trim().toUpperCase();
            if (estadoAbordaje == 'PENDIENTE' || estadoAbordaje == 'REALIZADO') {
              datosProcesados.add(mapa);

              String sup = (mapa['supervisor']?.toString() ?? '').trim().toUpperCase();
              if (sup.isNotEmpty && sup != 'NULL') superSet.add(sup);

              String opmNombre = (mapa['nombre']?.toString() ?? mapa['operador']?.toString() ?? '').trim().toUpperCase();
              if (opmNombre.isNotEmpty && opmNombre != 'NULL' && opmNombre != '-') opmSet.add(opmNombre);

              String lugarGuardado = (mapa['lugar_ocurrencia']?.toString() ?? '').trim().toUpperCase();
              if (lugarGuardado.isNotEmpty && lugarGuardado != 'NULL') {
                areasSet.add(lugarGuardado);
              }
            }
          }
        }
      }

      datosProcesados.sort((a, b) {
        String estA = (a['abordaje']?.toString() ?? '').trim().toUpperCase();
        String estB = (b['abordaje']?.toString() ?? '').trim().toUpperCase();
        if (estA == 'PENDIENTE' && estB != 'PENDIENTE') return -1;
        if (estA != 'PENDIENTE' && estB == 'PENDIENTE') return 1;
        return 0;
      });

      List<String> supList = superSet.toList()..sort();
      supList.remove('Todos');

      List<String> opmList = opmSet.toList()..sort();
      opmList.remove('Todos');

      setState(() {
        _listaAreasLogistica = areasSet.toList()..sort();
        _todosLosAbordajes = datosProcesados;
        _listaSupervisores = ['Todos', ...supList];
        _listaOpms = ['Todos', ...opmList];
        _aplicarFiltros();
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _mensajeError = 'Error conectando al servidor: $e';
        _cargando = false;
      });
    }
  }

  String _determinarEstado(Map<String, dynamic> row) {
    String abordaje = (row['abordaje']?.toString() ?? '').trim().toUpperCase();
    if (abordaje == 'REALIZADO') return 'REALIZADO';
    return 'PENDIENTE';
  }

  void _aplicarFiltros() {
    setState(() {
      _abordajesFiltrados = _todosLosAbordajes.where((row) {
        String estadoFila = _determinarEstado(row);
        if (_estadoSel != 'Todos' && estadoFila != _estadoSel) return false;

        String supervisorFila = (row['supervisor']?.toString() ?? '').trim().toUpperCase();
        if (_supervisorSel != 'Todos' && supervisorFila != _supervisorSel) return false;

        String opmFila = (row['nombre']?.toString() ?? row['operador']?.toString() ?? '').trim().toUpperCase();
        if (_opmSel != 'Todos' && opmFila != _opmSel) return false;

        if (_busquedaTexto.isNotEmpty) {
          String txt = _busquedaTexto.toLowerCase();
          String maquina = (row['maquina']?.toString() ?? '').toLowerCase();
          String evento = (row['evento']?.toString() ?? '').toLowerCase();
          String opmName = opmFila.toLowerCase();
          String opmOrigen = (row['origen_opm']?.toString() ?? '').toLowerCase();

          if (!maquina.contains(txt) && !evento.contains(txt) && !opmName.contains(txt) && !opmOrigen.contains(txt)) return false;
        }
        return true;
      }).toList();

      _paginaActual = 1;
    });
  }

  void _limpiarFiltros() {
    setState(() {
      _busquedaTexto = '';
      _supervisorSel = 'Todos';
      _opmSel = 'Todos';
      _estadoSel = 'Todos';
      _aplicarFiltros();
    });
  }

  // 📄 --- GENERADOR DE PDF --- 📄
  Future<pw.ImageProvider?> _obtenerImagenPdf(String? url) async {
    if (url == null || url.trim().isEmpty || url == 'null') return null;
    try {
      if (url.startsWith('data:image')) {
        final base64str = url.split(',').last;
        final bytes = base64Decode(base64str);
        return pw.MemoryImage(bytes);
      } else {
        return await networkImage(url);
      }
    } catch (e) {
      debugPrint('Error cargando imagen para PDF (CORS/Timeout): $e');
      return null;
    }
  }

  Future<void> _generarYDescargarPDF(Map<String, dynamic> row) async {
    final String idRegistro = row['id']?.toString() ?? '';
    setState(() { _idGenerandoPdf = idRegistro; });

    try {
      final doc = pw.Document();

      // Cargar Evidencia
      pw.ImageProvider? imgEvidencia;
      try {
        imgEvidencia = await _obtenerImagenPdf(row['foto_abordaje']?.toString()).timeout(const Duration(seconds: 5));
      } catch (_) {}

      // Cargar Firma
      pw.ImageProvider? imgFirma;
      try {
        imgFirma = await _obtenerImagenPdf(row['firma_opm']?.toString()).timeout(const Duration(seconds: 5));
      } catch (_) {}

      // Cargar Logo desde Assets
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (e) {
        debugPrint('No se encontró el logo local: $e');
      }

      String fechaOcurrencia = _formatearFechaCorta(row['fecha']?.toString());
      String fechaAbordaje = _formatearFechaHora(row['fecha_hora_abordaje']?.toString());
      String turno = row['turno']?.toString() ?? '-';
      String supervisor = row['supervisor']?.toString() ?? '-';
      String evento = row['evento']?.toString() ?? '-';
      String maquina = row['maquina']?.toString() ?? '-';
      String lugar = row['lugar_ocurrencia']?.toString() ?? '-';
      String area = row['area']?.toString() ?? '-';

      String opm = row['nombre']?.toString() ?? row['operador']?.toString() ?? '-';
      String origenOpm = row['origen_opm']?.toString() ?? '-';

      String accionPrev = row['accion_preventiva']?.toString() ?? '-';
      String descripcion = row['descripcion_evento']?.toString() ?? '-';
      String accionCorr = row['accion_correctiva']?.toString() ?? '-';

      final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10);
      const regularStyle = pw.TextStyle(fontSize: 10);

      pw.Widget celdaT(String texto) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(texto, style: boldStyle));
      pw.Widget celdaV(String texto) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(texto, style: regularStyle));

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              // 1. ENCABEZADO CORPORATIVO
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.2),
                    1: const pw.FlexColumnWidth(3.5),
                    2: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    pw.TableRow(
                        children: [
                          // CELDA DEL LOGO
                          pw.Container(
                            height: 60,
                            padding: const pw.EdgeInsets.all(5),
                            alignment: pw.Alignment.center,
                            child: imgLogo != null
                                ? pw.Image(imgLogo, fit: pw.BoxFit.contain)
                                : pw.SizedBox(),
                          ),
                          pw.Container(
                            alignment: pw.Alignment.center,
                            height: 60,
                            child: pw.Text('ABORDAJE DE OPERADORES DE MONTACARGAS (FMS)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
                          ),
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                              children: [
                                pw.Container(padding: const pw.EdgeInsets.all(4), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide())), child: pw.Text('Código: CO-EL-SST-FT-48', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700))),
                                pw.Container(padding: const pw.EdgeInsets.all(4), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide())), child: pw.Text('Versión: 03', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700))),
                                pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('Fecha: 25/03/2025', style: const pw.TextStyle(fontSize: 7, color: PdfColors.blue))),
                              ]
                          )
                        ]
                    )
                  ]
              ),
              pw.SizedBox(height: 20),

              // 2. TABLA GENERAL DE DATOS
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(1.3),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(children: [celdaT('Fecha ocurrencia:'), celdaV(fechaOcurrencia), celdaT('Fecha abordaje:'), celdaV(fechaAbordaje)]),
                  pw.TableRow(children: [celdaT('Turno:'), celdaV(turno), celdaT('Opm:'), celdaV(opm)]),
                  pw.TableRow(children: [celdaT('Supervisor:'), celdaV(supervisor), celdaT('Origen opm:'), celdaV(origenOpm)]),
                  pw.TableRow(children: [celdaT('Evento:'), celdaV(evento), celdaT('Máquina:'), celdaV(maquina)]),
                  pw.TableRow(children: [celdaT('Lugar:'), celdaV(lugar), celdaT('Area:'), celdaV(area)]),
                ],
              ),
              pw.SizedBox(height: 20),

              // 3. ACCIÓN PREVENTIVA
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: { 0: const pw.FlexColumnWidth(1.3), 1: const pw.FlexColumnWidth(5.3) },
                  children: [
                    pw.TableRow(children: [
                      pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.centerLeft, child: pw.Text('Acción preventiva', style: boldStyle)),
                      pw.Container(padding: const pw.EdgeInsets.all(6), constraints: const pw.BoxConstraints(minHeight: 40), alignment: pw.Alignment.topLeft, child: pw.Text(accionPrev, style: regularStyle))
                    ])
                  ]
              ),
              pw.SizedBox(height: 20),

              // 4. DESCRIPCIÓN
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  children: [
                    pw.TableRow(children: [
                      pw.Container(
                          constraints: const pw.BoxConstraints(minHeight: 80),
                          padding: const pw.EdgeInsets.all(6),
                          alignment: pw.Alignment.topLeft,
                          child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('Descripcion:', style: boldStyle),
                                pw.SizedBox(height: 6),
                                pw.Text(descripcion, style: regularStyle),
                              ]
                          )
                      )
                    ])
                  ]
              ),
              pw.SizedBox(height: 20),

              // 5. ACCIÓN CORRECTIVA
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: { 0: const pw.FlexColumnWidth(1.3), 1: const pw.FlexColumnWidth(5.3) },
                  children: [
                    pw.TableRow(children: [
                      pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.centerLeft, child: pw.Text('Acción correctiva:', style: boldStyle)),
                      pw.Container(padding: const pw.EdgeInsets.all(6), constraints: const pw.BoxConstraints(minHeight: 40), alignment: pw.Alignment.topLeft, child: pw.Text(accionCorr, style: regularStyle))
                    ])
                  ]
              ),
              pw.SizedBox(height: 20),

              // 6. EVIDENCIA FOTOGRÁFICA
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  children: [
                    pw.TableRow(children: [
                      pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          alignment: pw.Alignment.center,
                          child: pw.Text('EVIDENCIA ABORDAJE', style: boldStyle)
                      )
                    ]),
                    pw.TableRow(children: [
                      pw.Container(
                          height: 250,
                          padding: const pw.EdgeInsets.all(10),
                          alignment: pw.Alignment.center,
                          child: imgEvidencia != null
                              ? pw.Image(imgEvidencia, fit: pw.BoxFit.contain)
                              : pw.Text('Sin evidencia fotográfica reportada.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey))
                      )
                    ])
                  ]
              ),
              pw.SizedBox(height: 20),

              // 7. FIRMA
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: { 0: const pw.FlexColumnWidth(1.3), 1: const pw.FlexColumnWidth(5.3) },
                  children: [
                    pw.TableRow(children: [
                      pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.centerLeft, child: pw.Text('Firma opm:', style: boldStyle)),
                      pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          height: 80,
                          alignment: pw.Alignment.centerLeft,
                          child: imgFirma != null
                              ? pw.Image(imgFirma, fit: pw.BoxFit.contain)
                              : pw.Text('Sin firma reportada.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey))
                      )
                    ])
                  ]
              ),
            ];
          },
        ),
      );

      final bytesPdf = await doc.save();

      // Formatear nombres para archivo
      String fechaFormateadaArchivo = fechaAbordaje.replaceAll(RegExp(r'[/: ]'), '_');
      String opmFormateadoArchivo = opm.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

      await Printing.sharePdf(
        bytes: bytesPdf,
        filename: 'Abordaje_${fechaFormateadaArchivo}_$opmFormateadoArchivo.pdf',
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generando PDF: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() { _idGenerandoPdf = null; });
    }
  }

  // 📝 MODAL PARA GESTIONAR LA INVESTIGACIÓN DEL EVENTO
  void _abrirModalGestionarAbordaje(Map<String, dynamic> row) {
    final String idRegistro = row['id']?.toString() ?? '';
    final String estado = _determinarEstado(row);
    final bool esSoloLectura = estado == 'REALIZADO';

    final TextEditingController descripcionCtrl = TextEditingController(text: row['descripcion_evento']?.toString() ?? '');
    final TextEditingController lugarCtrl = TextEditingController(text: row['lugar_ocurrencia']?.toString() ?? '');
    final TextEditingController accionPrevCtrl = TextEditingController(text: row['accion_preventiva']?.toString() ?? '');
    final TextEditingController accionCorrCtrl = TextEditingController(text: row['accion_correctiva']?.toString() ?? '');

    DateTime fechaHoraSeleccionada = DateTime.now();
    if (row['fecha_hora_abordaje'] != null && row['fecha_hora_abordaje'].toString().isNotEmpty) {
      fechaHoraSeleccionada = DateTime.tryParse(row['fecha_hora_abordaje'].toString()) ?? DateTime.now();
    }

    Uint8List? fotoEvidenciaBytes;
    String? fotoEvidenciaNombre;

    List<Offset?> puntosFirma = [];
    final GlobalKey firmaKey = GlobalKey();
    bool tieneFirmaPrevia = row['firma_opm'] != null && row['firma_opm'].toString().trim().isNotEmpty && row['firma_opm'] != 'null';
    bool tieneFotoPrevia = row['foto_abordaje'] != null && row['foto_abordaje'].toString().trim().isNotEmpty && row['foto_abordaje'] != 'null';

    bool guardandoModal = false;

    Future<void> capturarFotoAbordaje(StateSetter setModalState) async {
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 50, maxWidth: 800, maxHeight: 800);
        if (pickedFile != null) {
          final bytesOriginales = await pickedFile.readAsBytes();
          final bytesComprimidos = await _comprimirBytesMax15KB(bytesOriginales, maxKB: 100, startWidth: 800);
          setModalState(() {
            fotoEvidenciaBytes = bytesComprimidos;
            fotoEvidenciaNombre = pickedFile.name;
          });
        }
      } catch (e) {
        debugPrint('Error tomando foto: $e');
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            bool isMobileModal = MediaQuery.of(ctx).size.width < 650;
            String opmNombre = row['nombre']?.toString() ?? row['operador']?.toString() ?? '-';
            String origenOpm = row['origen_opm']?.toString() ?? '-';

            return Dialog(
              insetPadding: EdgeInsets.all(isMobileModal ? 10 : 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: isMobileModal ? double.infinity : 680,
                padding: EdgeInsets.all(isMobileModal ? 16 : 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: const Color(0xFF0D47A1).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Icon(esSoloLectura ? Icons.remove_red_eye_rounded : Icons.manage_search_rounded, color: const Color(0xFF0D47A1), size: isMobileModal ? 18 : 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Investigación y Abordaje', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  Text(esSoloLectura ? 'Reporte Gestionado (Solo Lectura)' : 'Complete los detalles del reporte', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueGrey.shade100)),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 6),
                                const Text('Datos Originales', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                const Spacer(),
                                _dataCellEstado(estado),
                              ],
                            ),
                            const Divider(),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                SizedBox(width: 120, child: _buildDatoEstatico('Fecha Evento:', _formatearFechaCorta(row['fecha']?.toString()))),
                                SizedBox(width: 80, child: _buildDatoEstatico('Turno:', row['turno']?.toString() ?? '-')),
                                SizedBox(width: 100, child: _buildDatoEstatico('Máquina:', row['maquina']?.toString() ?? '-')),
                                SizedBox(width: 120, child: _buildDatoEstatico('Área:', row['area']?.toString() ?? '-')),
                                SizedBox(width: 200, child: _buildDatoEstatico('Evento:', row['evento']?.toString() ?? '-')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildDatoEstatico('Supervisor en Turno:', row['supervisor']?.toString() ?? '-')),
                                Expanded(child: _buildDatoEstatico('Operador (OPM):', '$opmNombre ($origenOpm)')),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      const Text('Formulario de Abordaje', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                      const SizedBox(height: 12),

                      if (isMobileModal) ...[
                        _buildSelectorCampoModal(
                          label: 'Lugar Exacto de Ocurrencia *',
                          hint: 'Seleccionar módulo/lugar...',
                          controller: lugarCtrl,
                          readOnly: esSoloLectura,
                          onTap: esSoloLectura ? () {} : () => _abrirBuscadorGenericoFormulario(dialogContext: dialogContext, titulo: 'Lugar Exacto', opciones: _listaAreasLogistica, controller: lugarCtrl, setModalState: setModalState),
                        ),
                        const SizedBox(height: 12),
                        _buildCampoFechaHora(fechaHoraSeleccionada),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: _buildSelectorCampoModal(
                              label: 'Lugar Exacto de Ocurrencia *',
                              hint: 'Seleccionar módulo/lugar...',
                              controller: lugarCtrl,
                              readOnly: esSoloLectura,
                              onTap: esSoloLectura ? () {} : () => _abrirBuscadorGenericoFormulario(dialogContext: dialogContext, titulo: 'Lugar Exacto', opciones: _listaAreasLogistica, controller: lugarCtrl, setModalState: setModalState),
                            )),
                            const SizedBox(width: 12),
                            Expanded(child: _buildCampoFechaHora(fechaHoraSeleccionada)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),

                      _buildInputForm('Descripción detallada del Evento *', descripcionCtrl, hint: 'Describa cómo y por qué sucedió...', maxLines: 3, readOnly: esSoloLectura),
                      const SizedBox(height: 12),
                      _buildInputForm('Acción Preventiva Establecida *', accionPrevCtrl, hint: '¿Qué se hará para prevenir?', maxLines: 2, readOnly: esSoloLectura),
                      const SizedBox(height: 12),
                      _buildInputForm('Acción Correctiva Ejecutada *', accionCorrCtrl, hint: '¿Qué se hizo para corregir?', maxLines: 2, readOnly: esSoloLectura),
                      const SizedBox(height: 20),

                      if (isMobileModal) ...[
                        _buildCajaFotoAbordaje(fotoEvidenciaBytes, fotoEvidenciaNombre, row['foto_abordaje'], () => capturarFotoAbordaje(setModalState), setModalState, esSoloLectura, tieneFotoPrevia),
                        const SizedBox(height: 16),
                        _buildCajaFirma(puntosFirma, tieneFirmaPrevia, row['firma_opm'], firmaKey, setModalState, esSoloLectura),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildCajaFotoAbordaje(fotoEvidenciaBytes, fotoEvidenciaNombre, row['foto_abordaje'], () => capturarFotoAbordaje(setModalState), setModalState, esSoloLectura, tieneFotoPrevia)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildCajaFirma(puntosFirma, tieneFirmaPrevia, row['firma_opm'], firmaKey, setModalState, esSoloLectura)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (esSoloLectura) ...[
                            ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              child: const Text('Cerrar Ventana', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            )
                          ] else ...[
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: guardandoModal
                                  ? null
                                  : () async {
                                if (lugarCtrl.text.trim().isEmpty || descripcionCtrl.text.trim().isEmpty || accionPrevCtrl.text.trim().isEmpty || accionCorrCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Complete todos los campos de texto (*)'), backgroundColor: Colors.orange));
                                  return;
                                }
                                if (!tieneFotoPrevia && fotoEvidenciaBytes == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ La foto de evidencia es obligatoria (*)'), backgroundColor: Colors.orange));
                                  return;
                                }
                                if (!tieneFirmaPrevia && puntosFirma.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ La Firma del OPM es obligatoria (*)'), backgroundColor: Colors.orange));
                                  return;
                                }

                                setModalState(() => guardandoModal = true);

                                try {
                                  String? urlFotoAbordaje;
                                  String? urlFirma;

                                  if (fotoEvidenciaBytes != null && fotoEvidenciaNombre != null) {
                                    try { urlFotoAbordaje = await ApiService.subirFoto('foto_abordaje', fotoEvidenciaBytes!, fotoEvidenciaNombre!); } catch (e) { debugPrint("Error foto: $e"); }
                                  }

                                  if (puntosFirma.isNotEmpty) {
                                    try {
                                      RenderRepaintBoundary boundary = firmaKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                                      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
                                      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                                      if (byteData != null) {
                                        Uint8List bytes = byteData.buffer.asUint8List();
                                        Uint8List compressed = await _comprimirBytesMax15KB(bytes, maxKB: 14, startWidth: 400);
                                        urlFirma = await ApiService.subirFoto('firma_opm', compressed, 'firma_${DateTime.now().millisecondsSinceEpoch}.png');
                                      }
                                    } catch (e) {
                                      debugPrint("Error subiendo firma: $e");
                                    }
                                  }

                                  final Map<String, dynamic> updateData = {
                                    'abordaje': 'REALIZADO',
                                    'fecha_hora_abordaje': fechaHoraSeleccionada.toIso8601String(),
                                    'lugar_ocurrencia': lugarCtrl.text.trim(),
                                    'descripcion_evento': descripcionCtrl.text.trim(),
                                    'accion_preventiva': accionPrevCtrl.text.trim(),
                                    'accion_correctiva': accionCorrCtrl.text.trim(),
                                  };

                                  if (urlFotoAbordaje != null) updateData['foto_abordaje'] = urlFotoAbordaje;
                                  if (urlFirma != null) updateData['firma_opm'] = urlFirma;

                                  await ApiService.actualizar('fms', 'fms_reporte', 'id', idRegistro, updateData);

                                  if (mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Abordaje guardado exitosamente'), backgroundColor: Colors.green));
                                    _cargarDatosBD();
                                  }
                                } catch (e) {
                                  setModalState(() => guardandoModal = false);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error actualizando datos: $e'), backgroundColor: Colors.red));
                                }
                              },
                              icon: guardandoModal ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline, size: 16),
                              label: Text(guardandoModal ? 'Guardando...' : 'Guardar Investigación', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E88E5), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            ),
                          ]
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

  // --- WIDGETS AUXILIARES PARA EL MODAL ---

  Widget _buildDatoEstatico(String titulo, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(valor, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildCampoFechaHora(DateTime fechaHoraSeleccionada) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fecha y Hora Abordaje (Automática)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.grey.shade100),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${fechaHoraSeleccionada.day.toString().padLeft(2,'0')}/${fechaHoraSeleccionada.month.toString().padLeft(2,'0')}/${fechaHoraSeleccionada.year} ${fechaHoraSeleccionada.hour.toString().padLeft(2,'0')}:${fechaHoraSeleccionada.minute.toString().padLeft(2,'0')}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
              const Icon(Icons.lock_clock, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCajaFotoAbordaje(Uint8List? bytes, String? nombre, dynamic urlPrevia, VoidCallback capturarFoto, StateSetter setModalState, bool esSoloLectura, bool tienePrevia) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.add_a_photo_outlined, size: 16, color: Colors.black54), SizedBox(width: 6), Text('Evidencia (Solo Foto) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87))]),
          const SizedBox(height: 10),
          if (bytes != null) ...[
            Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(bytes, height: 120, width: double.infinity, fit: BoxFit.cover)), Positioned(top: -5, right: -5, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setModalState(() { bytes = null; nombre = null; })))])
          ] else if (tienePrevia) ...[
            Row(children: [const Icon(Icons.check_circle, color: Colors.green, size: 16), const SizedBox(width: 6), const Text('Evidencia cargada', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: () => _mostrarPreviewImagen(urlPrevia.toString(), 'Evidencia'), style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('Ver', style: TextStyle(fontSize: 11, color: Color(0xFF0D47A1))))]),
            if (!esSoloLectura) ...[
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: capturarFoto, icon: const Icon(Icons.camera_alt, size: 16, color: Colors.black54), label: const Text('Tomar Nueva Foto', style: TextStyle(fontSize: 11, color: Colors.black87)))),
            ]
          ] else ...[
            if (esSoloLectura)
              const Text('Sin evidencia fotográfica', style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic))
            else
              SizedBox(width: double.infinity, height: 60, child: OutlinedButton.icon(onPressed: capturarFoto, icon: const Icon(Icons.camera_alt, size: 24, color: Colors.blueGrey), label: const Text('Tomar Foto de Evidencia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.blueGrey.shade300, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.white))),
          ]
        ],
      ),
    );
  }

  Widget _buildCajaFirma(List<Offset?> puntosFirma, bool tieneFirmaPrevia, dynamic urlPrevia, GlobalKey firmaKey, StateSetter setModalState, bool esSoloLectura) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), border: Border.all(color: Colors.green.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [Icon(Icons.draw_rounded, size: 18, color: Colors.green), SizedBox(width: 6), Text('Firma Digital OPM *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87))]),
              if (!esSoloLectura && (!tieneFirmaPrevia || puntosFirma.isNotEmpty))
                TextButton(onPressed: () => setModalState(() => puntosFirma.clear()), style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('Limpiar', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)))
            ],
          ),
          const SizedBox(height: 10),

          if (tieneFirmaPrevia && puntosFirma.isEmpty) ...[
            Row(children: [const Icon(Icons.check_circle, color: Colors.green, size: 16), const SizedBox(width: 6), const Text('Firma registrada', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: () => _mostrarPreviewImagen(urlPrevia.toString(), 'Firma OPM'), style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('Ver', style: TextStyle(fontSize: 11, color: Color(0xFF0D47A1))))]),
            if (!esSoloLectura) ...[
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => setModalState(() => tieneFirmaPrevia = false), icon: const Icon(Icons.draw, size: 16, color: Colors.black54), label: const Text('Rehacer Firma', style: TextStyle(fontSize: 11, color: Colors.black87)))),
            ]
          ] else ...[
            if (esSoloLectura)
              const Text('Sin firma registrada', style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic))
            else
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(border: Border.all(color: Colors.green.shade400, style: BorderStyle.solid, width: 2), borderRadius: BorderRadius.circular(6), color: Colors.white),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: RepaintBoundary(
                    key: firmaKey,
                    child: Container(
                      color: Colors.white,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          RenderBox box = firmaKey.currentContext!.findRenderObject() as RenderBox;
                          Offset localPos = box.globalToLocal(details.globalPosition);
                          setModalState(() => puntosFirma.add(localPos));
                        },
                        onPanEnd: (details) => setModalState(() => puntosFirma.add(null)),
                        child: CustomPaint(painter: _FirmaPainter(puntosFirma), size: Size.infinite),
                      ),
                    ),
                  ),
                ),
              ),
          ]
        ],
      ),
    );
  }

  void _abrirBuscadorGenericoFormulario({
    required BuildContext dialogContext,
    required String titulo,
    required List<String> opciones,
    required TextEditingController controller,
    required StateSetter setModalState,
  }) {
    showModalBottomSheet(
      context: dialogContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String filtro = "";
        return StatefulBuilder(
          builder: (context, setBuscadorState) {
            final listaFiltrada = opciones.where((n) => n.toLowerCase().contains(filtro.toLowerCase())).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: 16, left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Seleccionar $titulo', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Escriba para buscar o agregar...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF0D47A1)),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (val) => setBuscadorState(() => filtro = val),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                      child: (listaFiltrada.isEmpty && filtro.trim().isEmpty)
                          ? const Padding(padding: EdgeInsets.all(20.0), child: Text('Lista vacía.\nEscriba el lugar arriba para agregarlo manualmente.', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center))
                          : ListView.separated(
                        shrinkWrap: true,
                        itemCount: listaFiltrada.length + (filtro.trim().isNotEmpty ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (filtro.trim().isNotEmpty && index == listaFiltrada.length) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.add_circle_outline, color: Color(0xFF0D47A1), size: 18),
                              title: Text('Usar "${filtro.trim().toUpperCase()}"', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                              onTap: () {
                                setModalState(() => controller.text = filtro.trim().toUpperCase());
                                Navigator.pop(ctx);
                              },
                            );
                          }
                          final opcion = listaFiltrada[index];
                          return ListTile(dense: true, title: Text(opcion, style: const TextStyle(fontSize: 13)), onTap: () { setModalState(() => controller.text = opcion); Navigator.pop(ctx); });
                        },
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

  Widget _buildSelectorCampoModal({required String label, required String hint, required TextEditingController controller, required VoidCallback onTap, bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: readOnly ? Colors.grey.shade100 : Colors.white),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(controller.text.isEmpty ? hint : controller.text, style: TextStyle(fontSize: 12, color: controller.text.isEmpty ? Colors.black38 : (readOnly ? Colors.black54 : Colors.black87), fontWeight: controller.text.isEmpty ? FontWeight.normal : FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (!readOnly) const Icon(Icons.search_rounded, size: 16, color: Color(0xFF0D47A1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputForm(String label, TextEditingController controller, {String? hint, int maxLines = 1, bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          style: TextStyle(fontSize: 13, color: readOnly ? Colors.black54 : Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: readOnly,
            fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: readOnly ? Colors.grey.shade300 : const Color(0xFF0D47A1), width: 1.5)),
          ),
        ),
      ],
    );
  }

  // --- VISTA PRINCIPAL (FILTROS Y TABLA) ---

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(backgroundColor: Color(0xFFF4F6F9), body: Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))));

    int totalPaginas = max(1, (_abordajesFiltrados.length / _registrosPorPagina).ceil());
    int inicio = (_paginaActual - 1) * _registrosPorPagina;
    int fin = min(inicio + _registrosPorPagina, _abordajesFiltrados.length);
    List<Map<String, dynamic>> paginaActualLista = _abordajesFiltrados.isEmpty ? [] : _abordajesFiltrados.sublist(inicio, fin);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mensajeError != null) _buildBannerError(),
            _buildEncabezado(),
            const SizedBox(height: 20),
            _buildBarraFiltros(),
            const SizedBox(height: 20),
            _buildContenedorTabla(paginaActualLista, inicio, fin, totalPaginas),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (widget.onToggleSidebar != null) IconButton(icon: const Icon(Icons.menu, color: Color(0xFF0D47A1)), onPressed: widget.onToggleSidebar),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BANDEJA DE ABORDAJES - FMS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: 0.5)),
                Text('Investigación y control de reportes de flota', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _cargarDatosBD,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Actualizar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ],
    );
  }

  Widget _buildBarraFiltros() {
    bool hayFiltrosActivos = _supervisorSel != 'Todos' || _opmSel != 'Todos' || _estadoSel != 'Todos' || _busquedaTexto.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF0D47A1)),
                  SizedBox(width: 8),
                  Text('Filtros y Búsqueda', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
              if (hayFiltrosActivos)
                InkWell(
                  onTap: _limpiarFiltros,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('🧹 Limpiar Filtros', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Supervisor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _abrirModalBuscadorFiltro('Supervisor', _listaSupervisores, _supervisorSel, (val) => setState(() { _supervisorSel = val; _aplicarFiltros(); })),
                    child: Container(
                      width: 180,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(_supervisorSel, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                          const Icon(Icons.search, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Operador (OPM)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _abrirModalBuscadorFiltro('Operador', _listaOpms, _opmSel, (val) => setState(() { _opmSel = val; _aplicarFiltros(); })),
                    child: Container(
                      width: 180,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(_opmSel, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                          const Icon(Icons.search, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estado', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Container(
                    width: 130,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _listaEstados.contains(_estadoSel) ? _estadoSel : _listaEstados.first,
                        isDense: true,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                        items: _listaEstados.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setState(() { _estadoSel = v!; _aplicarFiltros(); }),
                      ),
                    ),
                  ),
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Buscar (Máquina, Evento, OPM)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 200,
                    height: 33,
                    child: TextField(
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Escriba aquí...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (v) {
                        _busquedaTexto = v;
                        _aplicarFiltros();
                      },
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_late_rounded, size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Text('Reportes Filtrados: ${_abordajesFiltrados.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    ],
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContenedorTabla(List<Map<String, dynamic>> paginaLista, int inicio, int fin, int totalPaginas) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Row(
              children: [
                const Text('Mostrar ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _registrosPorPagina,
                      isDense: true,
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                      items: [10, 25, 50, 100].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                      onChanged: (v) => setState(() { _registrosPorPagina = v!; _paginaActual = 1; }),
                    ),
                  ),
                ),
                const Text(' registros', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Scrollbar(
              controller: _tablaScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: _tablaScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
                  child: Table(
                    border: TableBorder.all(color: Colors.grey.shade200, width: 1),
                    columnWidths: const {
                      0: FixedColumnWidth(90),  // Fecha
                      1: FixedColumnWidth(110), // Máquina
                      2: FixedColumnWidth(120), // Área
                      3: FixedColumnWidth(180), // Evento
                      4: FixedColumnWidth(150), // Supervisor
                      5: FixedColumnWidth(150), // OPM
                      6: FixedColumnWidth(110), // Estado
                      7: FixedColumnWidth(160), // Acción (Botón)
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
                        children: [
                          _headerCell('Fecha Evento'),
                          _headerCell('Máquina'),
                          _headerCell('Área'),
                          _headerCell('Evento Reportado'),
                          _headerCell('Supervisor'),
                          _headerCell('Operador (OPM)'),
                          _headerCell('Estado', centrar: true),
                          _headerCell('Gestión', centrar: true),
                        ],
                      ),
                      ...paginaLista.map((row) {
                        String fecha = _formatearFechaCorta(row['fecha']?.toString());
                        String maquina = row['maquina']?.toString() ?? '-';
                        String area = row['area']?.toString() ?? '-';
                        String evento = row['evento']?.toString() ?? '-';
                        String supervisor = row['supervisor']?.toString() ?? '-';
                        String opmNombre = row['nombre']?.toString() ?? row['operador']?.toString() ?? '-';
                        String estado = _determinarEstado(row);

                        return TableRow(
                          decoration: const BoxDecoration(color: Colors.white),
                          children: [
                            _dataCell(fecha),
                            _dataCell(maquina, isBold: true),
                            _dataCell(area),
                            _dataCell(evento),
                            _dataCell(supervisor),
                            _dataCell(opmNombre),
                            _dataCellEstado(estado),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirModalGestionarAbordaje(row),
                                    icon: Icon(estado == 'PENDIENTE' ? Icons.edit_document : Icons.remove_red_eye_rounded, size: 14),
                                    label: Text(estado == 'PENDIENTE' ? 'Investigar' : 'Detalle', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: estado == 'PENDIENTE' ? const Color(0xFFFFC107) : Colors.green.shade50,
                                      foregroundColor: estado == 'PENDIENTE' ? Colors.black87 : Colors.green.shade800,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                      minimumSize: const Size(0, 28),
                                    ),
                                  ),
                                  if (estado == 'REALIZADO') ...[
                                    const SizedBox(width: 6),
                                    _idGenerandoPdf == row['id'].toString()
                                        ? const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent)),
                                    )
                                        : IconButton(
                                      onPressed: () => _generarYDescargarPDF(row),
                                      icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 18),
                                      tooltip: 'Descargar PDF',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mostrando ${paginaLista.isEmpty ? 0 : inicio + 1} a $fin de ${_abordajesFiltrados.length} reportes', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Row(
                  children: [
                    InkWell(onTap: _paginaActual > 1 ? () => setState(() => _paginaActual--) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: const Text('Anterior', style: TextStyle(fontSize: 11, color: Colors.blue)))),
                    const SizedBox(width: 4),
                    ...List.generate(min(totalPaginas, 9), (index) {
                      int pageNum = index + 1;
                      bool esActiva = pageNum == _paginaActual;
                      return InkWell(onTap: () => setState(() => _paginaActual = pageNum), child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: esActiva ? const Color(0xFF1976D2) : Colors.white, border: Border.all(color: esActiva ? const Color(0xFF1976D2) : Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: Text('$pageNum', style: TextStyle(fontSize: 11, color: esActiva ? Colors.white : Colors.blue))));
                    }),
                    const SizedBox(width: 4),
                    InkWell(onTap: _paginaActual < totalPaginas ? () => setState(() => _paginaActual++) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: const Text('Siguiente', style: TextStyle(fontSize: 11, color: Colors.blue)))),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- HELPERS TABLA ---
  void _abrirModalBuscadorFiltro(String titulo, List<String> opciones, String seleccionActual, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String filtro = "";
        return StatefulBuilder(
          builder: (context, setBuscadorState) {
            final listaFiltrada = opciones.where((n) => n.toLowerCase().contains(filtro.toLowerCase())).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: 16, left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Filtrar por $titulo', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Buscar $titulo...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF0D47A1)),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (val) => setBuscadorState(() => filtro = val),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: listaFiltrada.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final opcion = listaFiltrada[index];
                          final bool esSeleccionado = opcion == seleccionActual;
                          return ListTile(
                            dense: true,
                            title: Text(opcion, style: TextStyle(fontSize: 12, fontWeight: esSeleccionado ? FontWeight.bold : FontWeight.normal, color: esSeleccionado ? const Color(0xFF0D47A1) : Colors.black87)),
                            trailing: esSeleccionado ? const Icon(Icons.check_circle, color: Color(0xFF0D47A1), size: 18) : null,
                            onTap: () { onSelect(opcion); Navigator.pop(ctx); },
                          );
                        },
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

  Widget _headerCell(String text, {bool centrar = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87), textAlign: centrar ? TextAlign.center : TextAlign.left),
    );
  }

  Widget _dataCell(String text, {bool centrar = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, height: 1.3), textAlign: centrar ? TextAlign.center : TextAlign.left),
    );
  }

  Widget _dataCellEstado(String estado) {
    bool esPendiente = estado == 'PENDIENTE';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: esPendiente ? Colors.orange.shade100 : Colors.green.shade100, borderRadius: BorderRadius.circular(4), border: Border.all(color: esPendiente ? Colors.orange.shade300 : Colors.green.shade300)),
          child: Text(estado, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: esPendiente ? Colors.orange.shade900 : Colors.green.shade800)),
        ),
      ),
    );
  }

  String _formatearFechaCorta(String? fechaRaw) {
    if (fechaRaw == null || fechaRaw.isEmpty || fechaRaw == '-') return '-';
    try {
      String soloFecha = fechaRaw.split('T')[0];
      List<String> p = soloFecha.split('-');
      if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
    } catch (_) {}
    return fechaRaw;
  }

  String _formatearFechaHora(String? fechaRaw) {
    if (fechaRaw == null || fechaRaw.isEmpty || fechaRaw == 'null') return '-';
    try {
      DateTime dt = DateTime.parse(fechaRaw);
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return fechaRaw;
    }
  }

  void _mostrarPreviewImagen(String url, String titulo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(title: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white, automaticallyImplyLeading: false, elevation: 0, actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              Expanded(child: Padding(padding: const EdgeInsets.all(16.0), child: _buildImagenContenido(url))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagenContenido(String url) {
    if (url.startsWith('data:image')) {
      try { return Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain); } catch (e) { return const Center(child: Text('❌ Error al decodificar imagen.')); }
    } else {
      return Image.network(url, fit: BoxFit.contain, loadingBuilder: (ctx, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))), errorBuilder: (ctx, error, trace) => const Center(child: Text('❌ Error de carga.')));
    }
  }

  Widget _buildBannerError() {
    return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade700)), child: Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 18), const SizedBox(width: 8), Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold))), InkWell(onTap: _cargarDatosBD, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.amber.shade900, borderRadius: BorderRadius.circular(4)), child: const Text('REINTENTAR', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))]));
  }
}

// ==========================================
// CLASE PARA EL LIENZO DE FIRMA (CANVAS)
// ==========================================
class _FirmaPainter extends CustomPainter {
  final List<Offset?> puntos;
  _FirmaPainter(this.puntos);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < puntos.length - 1; i++) {
      if (puntos[i] != null && puntos[i + 1] != null) {
        canvas.drawLine(puntos[i]!, puntos[i + 1]!, paint);
      } else if (puntos[i] != null && puntos[i + 1] == null) {
        canvas.drawPoints(ui.PointMode.points, [puntos[i]!], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}