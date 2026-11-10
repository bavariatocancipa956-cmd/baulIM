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
                Expanded(child: _buildTablaCustom()),
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
  // TABLA CUSTOM ESTILO EXCEL
  // ===============================================
  Widget _buildTablaCustom() {
    if (_accionesFiltradas.isEmpty) {
      return Container(
        color: Colors.white,
        width: double.infinity,
        child: const Center(
          child: Text(
            'No se encontraron acciones con los filtros aplicados',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: _bordeTabla, left: _bordeTabla),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCabeceraTabla(),
                ..._accionesAgrupadas.entries.map(
                  (entry) => _buildFilaAgrupada(entry.value),
                ),
              ],
            ),
          ),
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
          _buildCeldaCuerpo(
            Text(
              primera.fecha,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            wFecha,
          ),
          _buildCeldaCuerpo(
            Text(
              primera.area,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            wArea,
          ),
          _buildCeldaCuerpo(
            Text(
              primera.pi,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            wPi,
          ),
          _buildCeldaCuerpo(
            const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
            wPdf,
          ),

          SizedBox(
            width: wTipo + wAccion + wResponsable + wFechaCierre + wEstado + wEvidencia,
            child: Column(
              children: grupo
                  .map((accion) => _buildFilaAccion(accion))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilaAccion(AccionVisual accion) {
    bool completado = accion.estado.toLowerCase() == 'concluida';

    return Row(
      children: [
        _buildCeldaCuerpo(
          Text(
            accion.tipoAccion,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          wTipo,
        ),
        _buildCeldaCuerpo(
          Text(
            accion.descripcion,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          wAccion,
          align: Alignment.centerLeft,
        ),
        _buildCeldaCuerpo(
          Text(
            accion.responsable,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          wResponsable,
        ),
        _buildCeldaCuerpo(
          Text(
            accion.fechaCierre,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          wFechaCierre,
        ),
        _buildCeldaCuerpo(
          _buildBadgeEstado(accion.estado.toUpperCase(), completado),
          wEstado,
        ),
        _buildCeldaCuerpo(
          _buildEvidenciaWidget(accion),
          wEvidencia,
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(right: _bordeTabla, bottom: _bordeTabla),
      ),
      alignment: align,
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildCeldaCuerpo(
    Widget hijo,
    double width, {
    Alignment align = Alignment.center,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(right: _bordeTabla, bottom: _bordeTabla),
      ),
      alignment: align,
      child: hijo,
    );
  }

  Widget _buildBadgeEstado(String text, bool isSuccess) {
    Color colorFondo = isSuccess ? Colors.green.shade50 : Colors.orange.shade50;
    Color colorTexto = isSuccess
        ? Colors.green.shade700
        : Colors.orange.shade800;
    Color colorBorde = isSuccess
        ? Colors.green.shade300
        : Colors.orange.shade300;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorFondo,
        border: Border.all(color: colorBorde, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colorTexto,
          fontSize: 11,
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
