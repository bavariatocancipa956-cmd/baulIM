import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'api_service.dart';

class ReporteRotura {
  final int id;
  final String codigoReporte;
  final String fechaEvento;
  final String supervisor;
  final String personal;
  final String zona;
  final String turno;
  final String cantidad;
  final String causal;
  final String atribuible;
  final String status;
  final String skuRoturaAplica;

  final String descripcionOriginal;
  final String categoria;
  final String conciliador;
  final String tipoMaterial2;
  final String ubicacion;
  final String evidenciaEvento;
  final String evidenciaCausante;
  final List<Map<String, dynamic>> itemsSku;

  final String descripcionHallazgo;
  final String accionPreventiva;
  final String accionCorrectiva;
  final String fotoAbordaje;
  final String firmaAbordaje;
  final String fechaHoraAbordaje;

  ReporteRotura({
    required this.id,
    required this.codigoReporte,
    required this.fechaEvento,
    required this.supervisor,
    required this.personal,
    required this.zona,
    required this.turno,
    required this.cantidad,
    required this.causal,
    required this.atribuible,
    required this.status,
    required this.skuRoturaAplica,
    required this.descripcionOriginal,
    required this.categoria,
    required this.conciliador,
    required this.tipoMaterial2,
    required this.ubicacion,
    required this.evidenciaEvento,
    required this.evidenciaCausante,
    required this.itemsSku,
    required this.descripcionHallazgo,
    required this.accionPreventiva,
    required this.accionCorrectiva,
    required this.fotoAbordaje,
    required this.firmaAbordaje,
    required this.fechaHoraAbordaje,
  });

  factory ReporteRotura.fromJson(Map<String, dynamic> json) {
    String rawDate = json['timestamp_registro']?.toString() ?? json['fecha_evento']?.toString() ?? '';
    if (rawDate.contains('T')) {
      rawDate = rawDate.replaceAll('T', ' ').substring(0, 16);
    }

    String skuVal = json['sku']?.toString() ?? 'N/A';
    String cantVal = json['cantidad']?.toString() ?? '0';
    String matVal = json['tipo_material_2']?.toString() ?? 'N/A';

    return ReporteRotura(
      id: json['id'] ?? 0,
      codigoReporte: json['codigo_reporte']?.toString().trim() ?? '',
      fechaEvento: rawDate,
      supervisor: json['supervisor']?.toString() ?? '',
      personal: json['personal']?.toString() ?? '',
      zona: json['zona']?.toString() ?? '',
      turno: json['turno']?.toString() ?? '',
      cantidad: cantVal,
      causal: json['causal']?.toString() ?? '',
      atribuible: json['atribuible']?.toString() ?? '',
      status: json['status']?.toString().trim().toUpperCase() ?? 'PENDIENTE',
      skuRoturaAplica: json['sku_rotura_aplica']?.toString().trim().toUpperCase() ?? '',
      descripcionOriginal: json['descripcion']?.toString() ?? '',
      categoria: json['categoria']?.toString() ?? '',
      conciliador: json['conciliador']?.toString() ?? '',
      tipoMaterial2: matVal,
      ubicacion: json['ubicacion']?.toString() ?? '',
      evidenciaEvento: json['evidencia_evento']?.toString() ?? '',
      evidenciaCausante: json['evidencia_causante']?.toString() ?? '',
      itemsSku: [{'sku': skuVal, 'cantidad': cantVal, 'tipoMaterial': matVal}],

      descripcionHallazgo: json['descripcion_hallazgo']?.toString() ?? '',
      accionPreventiva: json['acciones_preventiva']?.toString() ?? '',
      accionCorrectiva: json['acciones_correctiva']?.toString() ?? '',

      fotoAbordaje: json['foto_abordaje']?.toString() ?? '',
      firmaAbordaje: json['firma_abordaje']?.toString() ?? '',
      fechaHoraAbordaje: json['fecha_hora_abordaje']?.toString() ?? '',
    );
  }

  ReporteRotura copyWith({String? nuevaCantidad, List<Map<String, dynamic>>? nuevosItemsSku}) {
    return ReporteRotura(
      id: id,
      codigoReporte: codigoReporte,
      fechaEvento: fechaEvento,
      supervisor: supervisor,
      personal: personal,
      zona: zona,
      turno: turno,
      cantidad: nuevaCantidad ?? cantidad,
      causal: causal,
      atribuible: atribuible,
      status: status,
      skuRoturaAplica: skuRoturaAplica,
      descripcionOriginal: descripcionOriginal,
      categoria: categoria,
      conciliador: conciliador,
      tipoMaterial2: tipoMaterial2,
      ubicacion: ubicacion,
      evidenciaEvento: evidenciaEvento,
      evidenciaCausante: evidenciaCausante,
      itemsSku: nuevosItemsSku ?? itemsSku,
      descripcionHallazgo: descripcionHallazgo,
      accionPreventiva: accionPreventiva,
      accionCorrectiva: accionCorrectiva,
      fotoAbordaje: fotoAbordaje,
      firmaAbordaje: firmaAbordaje,
      fechaHoraAbordaje: fechaHoraAbordaje,
    );
  }
}

class AbordajesRoturaScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onToggleSidebar;

  const AbordajesRoturaScreen({
    Key? key,
    required this.usuario,
    required this.onToggleSidebar,
  }) : super(key: key);

  @override
  State<AbordajesRoturaScreen> createState() => _AbordajesRoturaScreenState();
}

class _AbordajesRoturaScreenState extends State<AbordajesRoturaScreen> {
  List<ReporteRotura> reportes = [];
  List<ReporteRotura> reportesFiltrados = [];
  bool isLoading = true;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<Uint8List> _comprimirImagen(Uint8List originalBytes, {int maxKB = 30, int startWidth = 500}) async {
    int maxBytes = maxKB * 1024;
    if (originalBytes.lengthInBytes <= maxBytes) return originalBytes;

    Uint8List bytes = originalBytes;
    int targetWidth = startWidth;

    while (bytes.lengthInBytes > maxBytes && targetWidth >= 100) {
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
      } catch (e) { break; }
      targetWidth = (targetWidth * 0.6).toInt();
    }
    return bytes;
  }

  Future<void> _cargarDatos() async {
    setState(() => isLoading = true);
    try {
      final response = await ApiService.consultar('roturas', 'reportes_rotura');
      List<dynamic> dataList = response is List ? response : (response['data'] ?? []);

      Map<String, ReporteRotura> reportesAgrupados = {};

      for (var json in dataList) {
        ReporteRotura reporte = ReporteRotura.fromJson(json);
        String codigo = reporte.codigoReporte;

        if (reporte.skuRoturaAplica != 'APLICA' ||
            reporte.status == 'NO APLICA' ||
            reporte.personal.trim().toUpperCase() == 'NO APLICA' ||
            codigo.isEmpty ||
            codigo.toLowerCase() == 'null') {
          continue;
        }

        if (reportesAgrupados.containsKey(codigo)) {
          ReporteRotura existente = reportesAgrupados[codigo]!;
          double cantActual = double.tryParse(existente.cantidad) ?? 0;
          double cantNueva = double.tryParse(reporte.cantidad) ?? 0;
          double sumaTotal = cantActual + cantNueva;

          String cantidadFormateada = sumaTotal == sumaTotal.truncateToDouble()
              ? sumaTotal.toInt().toString()
              : sumaTotal.toStringAsFixed(2);

          List<Map<String, dynamic>> nuevosItems = List.from(existente.itemsSku)..addAll(reporte.itemsSku);

          reportesAgrupados[codigo] = existente.copyWith(nuevaCantidad: cantidadFormateada, nuevosItemsSku: nuevosItems);
        } else {
          double cant = double.tryParse(reporte.cantidad) ?? 0;
          String cantidadFormateada = cant == cant.truncateToDouble() ? cant.toInt().toString() : cant.toStringAsFixed(2);
          reportesAgrupados[codigo] = reporte.copyWith(nuevaCantidad: cantidadFormateada);
        }
      }

      setState(() {
        reportes = reportesAgrupados.values.where((r) {
          double cant = double.tryParse(r.cantidad) ?? 0;
          return cant > 105;
        }).toList();

        reportesFiltrados = List.from(reportes);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  // --- LÓGICA DE TIEMPO DE RESPUESTA ---
  String _calcularTiempoRespuesta(String fechaEvento, String fechaAbordaje) {
    if (fechaEvento.isEmpty || fechaEvento.toLowerCase() == 'null' ||
        fechaAbordaje.isEmpty || fechaAbordaje.toLowerCase() == 'null') {
      return 'No calculable';
    }

    try {
      String eventoStr = fechaEvento;
      if (!eventoStr.contains('T')) {
        eventoStr = eventoStr.replaceAll(' ', 'T');
      }
      if (eventoStr.length == 16) {
        eventoStr += ':00'; // Añadir segundos si faltan para poder parsear
      }

      DateTime inicio = DateTime.parse(eventoStr);
      DateTime fin = DateTime.parse(fechaAbordaje);

      Duration diferencia = fin.difference(inicio);

      if (diferencia.isNegative) return 'Error (Abordaje antes de Evento)';

      int dias = diferencia.inDays;
      int horas = diferencia.inHours % 24;
      int minutos = diferencia.inMinutes % 60;

      if (dias > 0) {
        return '$dias día(s), $horas hora(s)';
      } else if (horas > 0) {
        return '$horas hora(s), $minutos min';
      } else {
        return '$minutos minuto(s)';
      }
    } catch (e) {
      return 'Error de cálculo';
    }
  }

  // ===========================================================================
  // MODAL 1: FORMULARIO DE INVESTIGACIÓN (Para PENDIENTES)
  // ===========================================================================
  void _abrirModalGestionarAbordaje(ReporteRotura reporte) {
    final TextEditingController descripcionCtrl = TextEditingController(text: reporte.descripcionHallazgo);
    final TextEditingController accionPrevCtrl = TextEditingController(text: reporte.accionPreventiva);
    final TextEditingController accionCorrCtrl = TextEditingController(text: reporte.accionCorrectiva);

    Uint8List? fotoEvidenciaBytes;
    String? fotoEvidenciaNombre;
    List<Offset?> puntosFirma = [];
    final GlobalKey firmaKey = GlobalKey();
    bool guardandoModal = false;

    Future<void> capturarFotoAbordaje(StateSetter setModalState) async {
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 25, maxWidth: 500, maxHeight: 500);
        if (pickedFile != null) {
          final bytesOriginales = await pickedFile.readAsBytes();
          final bytesComprimidos = await _comprimirImagen(bytesOriginales, maxKB: 30, startWidth: 500);
          setModalState(() {
            fotoEvidenciaBytes = bytesComprimidos;
            fotoEvidenciaNombre = 'foto_abordaje_rotura_${DateTime.now().millisecondsSinceEpoch}.png';
          });
        }
      } catch (e) { debugPrint('Error tomando foto: $e'); }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            bool isMobileModal = MediaQuery.of(ctx).size.width < 700;

            return Dialog(
              insetPadding: EdgeInsets.all(isMobileModal ? 10 : 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: isMobileModal ? double.infinity : 750,
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
                                decoration: BoxDecoration(color: const Color(0xFF0A2540).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.edit_document, color: const Color(0xFF0A2540), size: isMobileModal ? 18 : 22),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Investigación de Rotura', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  Text('Complete los detalles del reporte', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueGrey.shade100)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: Colors.blueGrey), SizedBox(width: 6),
                                Text('Datos Originales del Evento', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              ],
                            ),
                            const Divider(height: 20),
                            Wrap(
                              spacing: 12, runSpacing: 10,
                              children: [
                                SizedBox(width: 200, child: _buildDatoEstatico('Personal (Nombre):', reporte.personal)),
                                SizedBox(width: 200, child: _buildDatoEstatico('Supervisor:', reporte.supervisor)),
                                SizedBox(width: 120, child: _buildDatoEstatico('Zona:', reporte.zona)),
                                SizedBox(width: 120, child: _buildDatoEstatico('Ubicación:', reporte.ubicacion)),
                                SizedBox(width: 250, child: _buildDatoEstatico('Causal:', reporte.causal)),
                              ],
                            ),

                            const SizedBox(height: 15),
                            const Text('Detalle de SKUs Impactados:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(4),
                                  1: FlexColumnWidth(2),
                                  2: FlexColumnWidth(1),
                                },
                                border: TableBorder(
                                  horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                                  verticalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                                ),
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
                                    children: [
                                      _buildModalTablaHeader('Descripción SKU'),
                                      _buildModalTablaHeader('Tipo Material'),
                                      _buildModalTablaHeader('Cant.', alignRight: true),
                                    ],
                                  ),
                                  ...reporte.itemsSku.map((item) => TableRow(
                                      children: [
                                        _buildModalTablaCell(item['sku']?.toString() ?? 'N/A'),
                                        _buildModalTablaCell(item['tipoMaterial']?.toString() ?? 'N/A'),
                                        _buildModalTablaCell(item['cantidad']?.toString() ?? '0', alignRight: true, isBold: true),
                                      ]
                                  )).toList(),
                                  TableRow(
                                      decoration: BoxDecoration(color: Colors.grey.shade50),
                                      children: [
                                        _buildModalTablaCell('CANTIDAD TOTAL CONCILIADA:', isBold: true),
                                        _buildModalTablaCell('-'),
                                        _buildModalTablaCell(reporte.cantidad, alignRight: true, isBold: true),
                                      ]
                                  )
                                ],
                              ),
                            ),

                            const SizedBox(height: 15),
                            const Text('Evidencias Registradas (Originales):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildImagenPreviaMiniatura(reporte.evidenciaEvento, 'Evidencia Evento', context),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildImagenPreviaMiniatura(reporte.evidenciaCausante, 'Evidencia Causante', context),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text('Formulario de Investigación', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF14532D))),
                      const SizedBox(height: 12),

                      _buildInputForm('Investigación *', descripcionCtrl, hint: 'Detalle lo encontrado...', maxLines: 3),
                      const SizedBox(height: 12),

                      _buildInputForm('Acción Preventiva *', accionPrevCtrl, hint: 'Medidas para evitar que se repita...', maxLines: 2),
                      const SizedBox(height: 12),
                      _buildInputForm('Acción Correctiva *', accionCorrCtrl, hint: 'Medidas tomadas inmediatamente...', maxLines: 2),
                      const SizedBox(height: 20),

                      if (isMobileModal) ...[
                        _buildCajaFotoAbordaje(fotoEvidenciaBytes, () => capturarFotoAbordaje(setModalState), setModalState),
                        const SizedBox(height: 16),
                        _buildCajaFirma(puntosFirma, firmaKey, setModalState),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildCajaFotoAbordaje(fotoEvidenciaBytes, () => capturarFotoAbordaje(setModalState), setModalState)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildCajaFirma(puntosFirma, firmaKey, setModalState)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: guardandoModal ? null : () async {
                              if (descripcionCtrl.text.trim().isEmpty || accionPrevCtrl.text.trim().isEmpty || accionCorrCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Complete todos los campos de texto (*)'), backgroundColor: Colors.orange));
                                return;
                              }
                              if (fotoEvidenciaBytes == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ La foto de evidencia es obligatoria (*)'), backgroundColor: Colors.orange));
                                return;
                              }
                              if (puntosFirma.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ La Firma es obligatoria (*)'), backgroundColor: Colors.orange));
                                return;
                              }

                              setModalState(() => guardandoModal = true);

                              try {
                                String? urlFoto;
                                String? urlFirma;

                                if (fotoEvidenciaBytes != null && fotoEvidenciaNombre != null) {
                                  urlFoto = await ApiService.subirFoto('foto_abordaje', fotoEvidenciaBytes!, fotoEvidenciaNombre!);
                                }
                                if (puntosFirma.isNotEmpty) {
                                  RenderRepaintBoundary boundary = firmaKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                                  ui.Image image = await boundary.toImage(pixelRatio: 1.0);
                                  ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                                  if (byteData != null) {
                                    Uint8List bytes = byteData.buffer.asUint8List();
                                    Uint8List compressed = await _comprimirImagen(bytes, maxKB: 14, startWidth: 400);
                                    urlFirma = await ApiService.subirFoto('firma_abordaje', compressed, 'firma_rotura_${DateTime.now().millisecondsSinceEpoch}.png');
                                  }
                                }

                                String fechaHoraRealizacion = DateTime.now().toIso8601String();

                                final Map<String, dynamic> updateData = {
                                  'status': 'REALIZADO',
                                  'descripcion_hallazgo': descripcionCtrl.text.trim(),
                                  'acciones_preventiva': accionPrevCtrl.text.trim(),
                                  'acciones_correctiva': accionCorrCtrl.text.trim(),
                                  'fecha_hora_abordaje': fechaHoraRealizacion,
                                };

                                if (urlFoto != null) updateData['foto_abordaje'] = urlFoto;
                                if (urlFirma != null) updateData['firma_abordaje'] = urlFirma;

                                await ApiService.actualizar('roturas', 'reportes_rotura', 'codigo_reporte', reporte.codigoReporte, updateData);

                                if (mounted) {
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Investigación guardada exitosamente'), backgroundColor: Colors.green));
                                  _cargarDatos();
                                }
                              } catch (e) {
                                setModalState(() => guardandoModal = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error actualizando datos: $e'), backgroundColor: Colors.red));
                              }
                            },
                            icon: guardandoModal
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle_outline, size: 16),
                            label: Text(guardandoModal ? 'Guardando...' : 'Guardar Investigación', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF14532D), foregroundColor: Colors.white, elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
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

  // ===========================================================================
  // MODAL 2: TICKET PNG PREVIEW (Para REALIZADOS)
  // ===========================================================================
  void _abrirModalPreviewTicket(ReporteRotura reporte) {
    final GlobalKey ticketCanvasKey = GlobalKey();
    bool generandoPng = false;

    String tiempoRespuesta = _calcularTiempoRespuesta(reporte.fechaEvento, reporte.fechaHoraAbordaje);

    String fechaHoraEventoFormat = _formatearFechaHoraCompleta(reporte.fechaEvento);
    String fechaHoraAbordajeFormat = _formatearFechaHoraCompleta(reporte.fechaHoraAbordaje);

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (dialogContext, setModalState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(20),
                child: Container(
                  width: 750,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.file_copy, color: Color(0xFF0A2540)),
                                SizedBox(width: 10),
                                Text('Reporte de Abordaje (Ticket)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                          ],
                        ),
                      ),

                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: RepaintBoundary(
                            key: ticketCanvasKey,
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(30),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Text('OPERACIÓN TOCANCIPÁ', style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold, fontSize: 18)),
                                      const Text('ABORDAJE DE ROTURAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          const Text('Código: CO-EL-SST-FT-48', style: TextStyle(fontSize: 10, color: Colors.black87)),
                                          const Text('Versión: 03', style: TextStyle(fontSize: 10, color: Colors.black87)),
                                          Text('Fecha Impresión: ${DateTime.now().day.toString().padLeft(2,'0')}/${DateTime.now().month.toString().padLeft(2,'0')}/${DateTime.now().year}', style: const TextStyle(fontSize: 10, color: Color(0xFF0D47A1), fontWeight: FontWeight.bold)),
                                        ],
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      border: Border.all(color: Colors.blue.shade200),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.timer_outlined, size: 16, color: Colors.blue.shade800),
                                        const SizedBox(width: 8),
                                        Text('Tiempo de Respuesta del Abordaje: ', style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
                                        Text(tiempoRespuesta, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 15),

                                  Table(
                                    border: TableBorder.all(color: Colors.black87, width: 0.5),
                                    columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(2)},
                                    children: [
                                      _buildTicketRow('Fecha y Hora Evento:', fechaHoraEventoFormat, 'Fecha y Hora Abordaje:', fechaHoraAbordajeFormat),
                                      _buildTicketRow('Turno:', reporte.turno, 'Personal / OPM:', reporte.personal),
                                      _buildTicketRow('Supervisor:', reporte.supervisor, 'Categoría:', reporte.categoria),
                                      _buildTicketRow('Evento Reportado:', reporte.causal, 'Conciliador:', reporte.conciliador),
                                      _buildTicketRow('Ubicación:', reporte.ubicacion, 'Atribuible:', reporte.atribuible),
                                      TableRow(children: [_ticketHeaderCell('Zona:'), _ticketDataCell(reporte.zona), _ticketHeaderCell(''), _ticketDataCell('')]),
                                    ],
                                  ),
                                  const SizedBox(height: 15),

                                  Table(
                                      border: TableBorder.all(color: Colors.black87, width: 0.5),
                                      children: [
                                        TableRow(
                                          decoration: BoxDecoration(color: Colors.grey.shade100),
                                          children: [
                                            _ticketHeaderCell('EVIDENCIA DEL EVENTO (ORIGINAL)', center: true),
                                            _ticketHeaderCell('EVIDENCIA DEL CAUSANTE (ORIGINAL)', center: true),
                                          ],
                                        ),
                                        TableRow(
                                            children: [
                                              Container(
                                                height: 120, padding: const EdgeInsets.all(5), alignment: Alignment.center,
                                                child: _buildTicketImage(reporte.evidenciaEvento, labelFalta: 'Sin evidencia de evento'),
                                              ),
                                              Container(
                                                height: 120, padding: const EdgeInsets.all(5), alignment: Alignment.center,
                                                child: _buildTicketImage(reporte.evidenciaCausante, labelFalta: 'Sin evidencia de causante'),
                                              ),
                                            ]
                                        )
                                      ]
                                  ),
                                  const SizedBox(height: 15),

                                  Table(
                                    border: TableBorder.all(color: Colors.black87, width: 0.5),
                                    children: [
                                      TableRow(children: [_ticketHeaderCell('Descripción Original del Evento:', isFullWidth: true)]),
                                      TableRow(children: [_ticketDataCell(reporte.descripcionOriginal, padding: 15)]),
                                    ],
                                  ),
                                  const SizedBox(height: 15),

                                  const Text('Detalle de SKUs Impactados:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  const SizedBox(height: 5),
                                  Table(
                                    border: TableBorder.all(color: Colors.black87, width: 0.5),
                                    columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1)},
                                    children: [
                                      TableRow(
                                        decoration: BoxDecoration(color: Colors.grey.shade100),
                                        children: [
                                          _ticketHeaderCell('Descripción SKU'),
                                          _ticketHeaderCell('Tipo Material'),
                                          _ticketHeaderCell('Cant.', alignRight: true),
                                        ],
                                      ),
                                      ...reporte.itemsSku.map((item) => TableRow(
                                          children: [
                                            _ticketDataCell(item['sku']?.toString() ?? 'N/A'),
                                            _ticketDataCell(item['tipoMaterial']?.toString() ?? 'N/A'),
                                            _ticketDataCell(item['cantidad']?.toString() ?? '0', alignRight: true, isBold: true),
                                          ]
                                      )).toList(),
                                      TableRow(
                                          children: [
                                            _ticketHeaderCell('CANTIDAD TOTAL CONCILIADA:'),
                                            _ticketDataCell(''),
                                            _ticketDataCell(reporte.cantidad, alignRight: true, isBold: true),
                                          ]
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 15),

                                  const Text('Resultados de la Investigación:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  const SizedBox(height: 5),
                                  Table(
                                    border: TableBorder.all(color: Colors.black87, width: 0.5),
                                    children: [
                                      TableRow(children: [_ticketHeaderCell('Investigación:', isFullWidth: true)]),
                                      TableRow(children: [_ticketDataCell(reporte.descripcionHallazgo, padding: 10)]),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Table(
                                    border: TableBorder.all(color: Colors.black87, width: 0.5),
                                    columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(3.8)},
                                    children: [
                                      TableRow(children: [_ticketHeaderCell('Acción Preventiva:'), _ticketDataCell(reporte.accionPreventiva)]),
                                      TableRow(children: [_ticketHeaderCell('Acción Correctiva:'), _ticketDataCell(reporte.accionCorrectiva)]),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  Table(
                                      border: TableBorder.all(color: Colors.black87, width: 0.5),
                                      children: [
                                        TableRow(
                                          decoration: BoxDecoration(color: Colors.grey.shade100),
                                          children: [
                                            _ticketHeaderCell('EVIDENCIA INVESTIGACIÓN', center: true),
                                            _ticketHeaderCell('FIRMA DEL OPM', center: true),
                                          ],
                                        ),
                                        TableRow(
                                            children: [
                                              Container(
                                                height: 140, padding: const EdgeInsets.all(10), alignment: Alignment.center,
                                                child: _buildTicketImage(reporte.fotoAbordaje, labelFalta: 'Sin evidencia de investigación'),
                                              ),
                                              Container(
                                                height: 140, padding: const EdgeInsets.all(10), alignment: Alignment.center,
                                                child: _buildTicketImage(reporte.firmaAbordaje, labelFalta: 'Sin firma reportada'),
                                              ),
                                            ]
                                        )
                                      ]
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cerrar Ventana', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 15),
                            ElevatedButton.icon(
                              onPressed: generandoPng ? null : () async {
                                setModalState(() => generandoPng = true);

                                try {
                                  await Future.delayed(const Duration(milliseconds: 300));
                                  RenderRepaintBoundary boundary = ticketCanvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                                  ui.Image image = await boundary.toImage(pixelRatio: 2.0);
                                  ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

                                  if (byteData != null) {
                                    Uint8List pngBytes = byteData.buffer.asUint8List();
                                    String fechaFormat = reporte.fechaEvento.replaceAll(RegExp(r'[/: ]'), '_');
                                    String nombreOpm = reporte.personal.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

                                    await Printing.sharePdf(bytes: pngBytes, filename: 'Reporte_Rotura_${fechaFormat}_$nombreOpm.png');
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                }

                                setModalState(() => generandoPng = false);
                              },
                              icon: generandoPng ? const SizedBox(width:14, height:14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.image, size: 16),
                              label: Text(generandoPng ? 'Generando...' : 'Descargar Imagen (PNG)', style: const TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700, foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }
    );
  }

  String _formatearFechaHoraCompleta(String? fechaIso) {
    if (fechaIso == null || fechaIso.trim().isEmpty || fechaIso.toLowerCase() == 'null') return 'No registrada';
    try {
      DateTime dt = DateTime.parse(fechaIso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return fechaIso; }
  }

  TableRow _buildTicketRow(String t1, String v1, String t2, String v2) {
    return TableRow(
        children: [
          _ticketHeaderCell(t1), _ticketDataCell(v1),
          _ticketHeaderCell(t2), _ticketDataCell(v2),
        ]
    );
  }
  Widget _ticketHeaderCell(String text, {bool isFullWidth = false, bool center = false, bool alignRight = false}) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(6),
      alignment: center ? Alignment.center : (alignRight ? Alignment.centerRight : Alignment.centerLeft),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black87)),
    );
  }
  Widget _ticketDataCell(String text, {double padding = 6, bool alignRight = false, bool isBold = false}) {
    String val = (text.trim().isEmpty || text.toLowerCase() == 'null') ? '-' : text;
    return Container(
      padding: EdgeInsets.all(padding),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(val, style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
    );
  }
  Widget _buildTicketImage(String url, {String labelFalta = 'Sin imagen'}) {
    if (url.trim().isEmpty || url.toLowerCase() == 'null') {
      return Text(labelFalta, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 10));
    }
    if (url.startsWith('data:image')) {
      return Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain);
    }
    return Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Text(labelFalta, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 10)));
  }

  // ===========================================================================
  // WIDGETS AUXILIARES PARA FORMULARIO DE INVESTIGACION
  // ===========================================================================
  Widget _buildDatoEstatico(String titulo, String valor) {
    String val = (valor.trim().isEmpty || valor.toLowerCase() == 'null') ? '-' : valor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildModalTablaHeader(String text, {bool alignRight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey),
      ),
    );
  }

  Widget _buildModalTablaCell(String text, {bool alignRight = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _buildImagenPreviaMiniatura(String url, String titulo, BuildContext ctx) {
    bool hasImage = url.trim().isNotEmpty && url.toLowerCase() != 'null';
    return Container(
      height: 90,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
            child: Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
          Expanded(
            child: hasImage
                ? InkWell(
              onTap: () => _mostrarPreviewImagen(url, titulo),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: url.startsWith('data:image')
                    ? Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain)
                    : Image.network(url, fit: BoxFit.contain, errorBuilder: (_,__,___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey))),
              ),
            )
                : const Center(child: Text('N/A', style: TextStyle(fontSize: 10, color: Colors.grey))),
          ),
        ],
      ),
    );
  }

  Widget _buildInputForm(String label, TextEditingController controller, {String? hint, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        TextField(
          controller: controller, maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint, hintStyle: const TextStyle(color: Colors.black38, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.transparent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF14532D), width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildCajaFotoAbordaje(Uint8List? bytes, VoidCallback capturarFoto, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.add_a_photo_outlined, size: 16, color: Colors.black54), SizedBox(width: 6),
              Text('Foto de Evidencia *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 10),
          if (bytes != null) ...[
            Stack(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(bytes, height: 120, width: double.infinity, fit: BoxFit.cover)),
                Positioned(top: -5, right: -5, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setModalState(() { bytes = null; }))),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity, height: 60,
              child: OutlinedButton.icon(
                onPressed: capturarFoto, icon: const Icon(Icons.camera_alt, size: 24, color: Colors.blueGrey), label: const Text('Tomar Foto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.blueGrey.shade300, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCajaFirma(List<Offset?> puntosFirma, GlobalKey firmaKey, StateSetter setModalState) {
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
              if (puntosFirma.isNotEmpty)
                TextButton(
                  onPressed: () => setModalState(() => puntosFirma.clear()),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Limpiar', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 140, width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: Colors.green.shade400, width: 2), borderRadius: BorderRadius.circular(6), color: Colors.white),
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
        ],
      ),
    );
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
              AppBar(
                title: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF0A2540), foregroundColor: Colors.white, automaticallyImplyLeading: false, elevation: 0,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: url.startsWith('data:image')
                      ? Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain)
                      : Image.network(url, fit: BoxFit.contain, loadingBuilder: (ctx, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // VISTA BASE DE LA PANTALLA
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFiltros(),
            const SizedBox(height: 16),
            _buildKPIs(),
            const SizedBox(height: 16),
            _buildTablasResumen(), // <-- NUEVAS TABLAS AÑADIDAS AQUÍ
            const SizedBox(height: 16),
            Expanded(child: _buildTablaDatos()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (MediaQuery.of(context).size.width < 850)
              IconButton(icon: const Icon(Icons.menu, color: Color(0xFF0A2540)), onPressed: widget.onToggleSidebar),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BANDEJA DE ABORDAJES - ROTURAS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
                Text('Investigación y control de reportes de rotura', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _cargarDatos, icon: const Icon(Icons.refresh, size: 18), label: const Text('Actualizar'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
        )
      ],
    );
  }

  Widget _buildFiltros() {
    return Card(
      elevation: 0, color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.filter_alt, color: Color(0xFF0A2540), size: 18), SizedBox(width: 8),
                    Text('Filtros y Búsqueda', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
                  ],
                ),
                TextButton.icon(
                    onPressed: () { setState(() => reportesFiltrados = List.from(reportes)); },
                    icon: const Icon(Icons.clear_all, color: Colors.redAccent, size: 18),
                    label: const Text('Limpiar Filtros', style: TextStyle(color: Colors.redAccent))
                )
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildDropdown('Mes Evento', ['Todos'])), const SizedBox(width: 16),
                Expanded(child: _buildDropdown('Supervisor', ['Todos'])), const SizedBox(width: 16),
                Expanded(child: _buildDropdown('Estado', ['Todos', 'PENDIENTE', 'REALIZADO'])), const SizedBox(width: 16),
                Expanded(
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'Buscar (Personal, Causal, Supervisor)', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
                      onChanged: (value) {
                        setState(() {
                          reportesFiltrados = reportes.where((r) =>
                          r.personal.toLowerCase().contains(value.toLowerCase()) || r.causal.toLowerCase().contains(value.toLowerCase()) || r.supervisor.toLowerCase().contains(value.toLowerCase())
                          ).toList();
                        });
                      },
                    )
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), isDense: true),
          value: items.first, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(), onChanged: (val) {},
        ),
      ],
    );
  }

  Widget _buildKPIs() {
    int total = reportesFiltrados.length;
    int realizados = reportesFiltrados.where((r) => r.status == 'REALIZADO').length;
    int pendientes = reportesFiltrados.where((r) => r.status == 'PENDIENTE').length;
    double avance = total == 0 ? 0 : (realizados / total) * 100;

    return Row(
      children: [
        Expanded(child: _buildKpiCard('TOTAL ABORDAJES', total.toString(), Colors.blue.shade700, Icons.assessment)), const SizedBox(width: 16),
        Expanded(child: _buildKpiCard('REALIZADOS', realizados.toString(), Colors.green.shade600, Icons.check_circle)), const SizedBox(width: 16),
        Expanded(child: _buildKpiCard('PENDIENTES', pendientes.toString(), Colors.orange.shade600, Icons.schedule)), const SizedBox(width: 16),
        Expanded(child: _buildKpiCard('AVANCE GENERAL', '${avance.toStringAsFixed(1)}%', Colors.purple.shade600, Icons.pie_chart)),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)), Icon(icon, color: color, size: 16)]),
          const SizedBox(height: 8), Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ===========================================================================
  // NUEVAS TABLAS RESUMEN
  // ===========================================================================
  Widget _buildTablasResumen() {
    if (isLoading || reportesFiltrados.isEmpty) return const SizedBox();

    Map<String, Map<String, int>> statsSupervisor = {};
    Map<String, Map<String, int>> statsOperador = {};
    int globalTotal = 0;
    int globalRealizados = 0;
    int globalPendientes = 0;

    for (var r in reportesFiltrados) {
      globalTotal++;
      if (r.status == 'REALIZADO') globalRealizados++;
      if (r.status == 'PENDIENTE') globalPendientes++;

      statsSupervisor.putIfAbsent(r.supervisor, () => {'total': 0, 'realizados': 0, 'pendientes': 0});
      statsSupervisor[r.supervisor]!['total'] = statsSupervisor[r.supervisor]!['total']! + 1;
      if (r.status == 'REALIZADO') statsSupervisor[r.supervisor]!['realizados'] = statsSupervisor[r.supervisor]!['realizados']! + 1;
      if (r.status == 'PENDIENTE') statsSupervisor[r.supervisor]!['pendientes'] = statsSupervisor[r.supervisor]!['pendientes']! + 1;

      statsOperador.putIfAbsent(r.personal, () => {'total': 0, 'realizados': 0, 'pendientes': 0});
      statsOperador[r.personal]!['total'] = statsOperador[r.personal]!['total']! + 1;
      if (r.status == 'REALIZADO') statsOperador[r.personal]!['realizados'] = statsOperador[r.personal]!['realizados']! + 1;
      if (r.status == 'PENDIENTE') statsOperador[r.personal]!['pendientes'] = statsOperador[r.personal]!['pendientes']! + 1;
    }

    var listSup = statsSupervisor.entries.toList()..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));
    var listOp = statsOperador.entries.toList()..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));

    return SizedBox(
      height: 250, // Altura fija para que la tabla sea scrollable por dentro y no rompa el diseño
      child: Row(
        children: [
          Expanded(child: _buildResumenTable('SUPERVISOR', listSup, globalTotal, globalRealizados, globalPendientes)),
          const SizedBox(width: 16),
          Expanded(child: _buildResumenTable('OPERADOR', listOp, globalTotal, globalRealizados, globalPendientes)),
        ],
      ),
    );
  }

  Widget _buildResumenTable(String title, List<MapEntry<String, Map<String, int>>> data, int gTotal, int gRealizados, int gPendientes) {
    double gAvance = gTotal == 0 ? 0 : (gRealizados / gTotal) * 100;

    return Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
        child: Column(
            children: [
              // Header Oscuro
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(3))),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                      const Expanded(flex: 1, child: Text('TOTAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                      const Expanded(flex: 1, child: Text('REALIZADOS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                      const Expanded(flex: 1, child: Text('PENDIENTES', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                      const Expanded(flex: 1, child: Text('AVANCE %', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  )
              ),
              // Lista de Registros
              Expanded(
                  child: ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        var e = data[i];
                        double avance = e.value['total']! == 0 ? 0 : (e.value['realizados']! / e.value['total']!) * 100;
                        return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                            child: Row(
                                children: [
                                  Expanded(flex: 4, child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0A2540)))),
                                  Expanded(flex: 1, child: Text(e.value['total'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                  Expanded(flex: 1, child: Text(e.value['realizados'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                  Expanded(flex: 1, child: Text(e.value['pendientes'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                  Expanded(flex: 1, child: Text('${avance.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                ]
                            )
                        );
                      }
                  )
              ),
              // Footer (Totales Globales)
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Colors.blueGrey.shade100, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3))),
                  child: Row(
                      children: [
                        const Expanded(flex: 4, child: Text('TOTALES GLOBALES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0A2540)))),
                        Expanded(flex: 1, child: Text(gTotal.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0A2540)))),
                        Expanded(flex: 1, child: Text(gRealizados.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0A2540)))),
                        Expanded(flex: 1, child: Text(gPendientes.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0A2540)))),
                        Expanded(flex: 1, child: Text('${gAvance.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0A2540)))),
                      ]
                  )
              )
            ]
        )
    );
  }

  // ===========================================================================
  // TABLA INFERIOR DE DATOS
  // ===========================================================================
  Widget _buildHeaderCell(String text, int flex) {
    return Expanded(flex: flex, child: Padding(padding: const EdgeInsets.only(right: 8.0), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0A2540)))));
  }

  Widget _buildDataCell(Widget child, int flex) {
    return Expanded(flex: flex, child: Padding(padding: const EdgeInsets.only(right: 8.0), child: child));
  }

  Widget _buildTablaDatos() {
    return Card(
      elevation: 0, color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Registros de Rotura', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
                ElevatedButton.icon(
                  onPressed: () {}, icon: const Icon(Icons.download, size: 16), label: const Text('Descargar CSV'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF14532D), foregroundColor: Colors.white, elevation: 0),
                )
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1400,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade200), bottom: BorderSide(color: Colors.grey.shade300))),
                      child: Row(
                        children: [
                          _buildHeaderCell('Fecha', 2),
                          _buildHeaderCell('Supervisor', 3),
                          _buildHeaderCell('Personal', 3),
                          _buildHeaderCell('Zona', 2),
                          _buildHeaderCell('Turno', 1),
                          _buildHeaderCell('Cant.', 1),
                          // Causal eliminado de aquí
                          _buildHeaderCell('Atribuible', 2),
                          _buildHeaderCell('Estado', 2),
                          _buildHeaderCell('Gestión', 2),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: reportesFiltrados.length,
                        itemBuilder: (context, index) {
                          final reporte = reportesFiltrados[index];
                          bool esPendiente = reporte.status == 'PENDIENTE';

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDataCell(Text(reporte.fechaEvento, style: const TextStyle(fontSize: 13)), 2),
                                _buildDataCell(Text(reporte.supervisor, style: const TextStyle(fontSize: 13)), 3),
                                _buildDataCell(Text(reporte.personal, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), 3),
                                _buildDataCell(Text(reporte.zona, style: const TextStyle(fontSize: 13)), 2),
                                _buildDataCell(Text(reporte.turno, style: const TextStyle(fontSize: 13)), 1),
                                _buildDataCell(Text(reporte.cantidad, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), 1),
                                // Causal eliminado de aquí
                                _buildDataCell(Text(reporte.atribuible, style: const TextStyle(fontSize: 13)), 2),
                                _buildDataCell(
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: esPendiente ? Colors.orange.shade50 : Colors.green.shade50, border: Border.all(color: esPendiente ? Colors.orange : Colors.green), borderRadius: BorderRadius.circular(4)),
                                        child: Text(reporte.status, style: TextStyle(color: esPendiente ? Colors.orange.shade800 : Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ), 2
                                ),
                                _buildDataCell(
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: ElevatedButton.icon(
                                        onPressed: () => esPendiente ? _abrirModalGestionarAbordaje(reporte) : _abrirModalPreviewTicket(reporte),
                                        icon: Icon(esPendiente ? Icons.edit_document : Icons.file_copy, size: 14),
                                        label: Text(esPendiente ? 'Investigar' : 'Ver Ticket'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: esPendiente ? Colors.orange.shade100 : Colors.blue.shade50,
                                          foregroundColor: esPendiente ? Colors.orange.shade900 : Colors.blue.shade900,
                                          elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: const Size(0, 32),
                                        ),
                                      ),
                                    ), 2
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

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