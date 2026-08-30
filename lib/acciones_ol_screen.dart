import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

class AccionesOlScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;
  final Map<String, dynamic>? usuario;

  const AccionesOlScreen({super.key, this.onToggleSidebar, this.usuario});

  @override
  State<AccionesOlScreen> createState() => _AccionesOlScreenState();
}

class _AccionesOlScreenState extends State<AccionesOlScreen> {
  final ScrollController _tablaScrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todasLasAcciones = [];
  List<Map<String, dynamic>> _accionesFiltradas = [];

  // Listas extraídas de BD para los buscadores
  List<String> _listaNombresUsuariosBD = [];
  List<String> _listaTerritoriosBD = [];
  List<String> _listaRutinasBD = [];
  List<String> _listaHashtagsBD = [];

  // Filtros de la barra superior
  String _rutinaSel = 'Todas';
  String _hashtagSel = 'Todos';
  String _duenoSel = 'Todas';
  String _responsableSel = 'Todos';
  String _estadoSel = 'Todos';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  String _busquedaTexto = '';
  int _registrosPorPagina = 10;
  int _paginaActual = 1;

  List<String> _listaRutinas = ['Todas'];
  List<String> _listaHashtags = ['Todos'];
  List<String> _listaDuenos = ['Todas'];
  List<String> _listaResponsables = ['Todos'];
  final List<String> _listaEstados = ['Todos', 'EN PROGRESO', 'RETRASADAS', 'CERRADAS'];

  String get _nombreUsuarioLogueado {
    final nombre = widget.usuario?['nombre'] ?? widget.usuario?['Nombre'] ?? widget.usuario?['usuario'];
    if (nombre != null && nombre.toString().trim().isNotEmpty) {
      return nombre.toString().trim().toUpperCase();
    }
    return 'OPERADOR';
  }

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

  // 🗜️ COMPRIME FOTO HASTA UN MÁXIMO DE 15 KB
  Future<Uint8List> _comprimirBytesMax15KB(Uint8List originalBytes, {int maxKB = 15}) async {
    int maxBytes = maxKB * 1024;
    if (originalBytes.lengthInBytes <= maxBytes) {
      return originalBytes;
    }

    Uint8List bytes = originalBytes;
    int targetWidth = 300;

    while (bytes.lengthInBytes > maxBytes && targetWidth >= 60) {
      try {
        ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
        ui.FrameInfo frame = await codec.getNextFrame();
        ui.Image image = frame.image;
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData != null) {
          Uint8List newBytes = byteData.buffer.asUint8List();
          bytes = newBytes;
          if (newBytes.lengthInBytes <= maxBytes) {
            return newBytes;
          }
        }
      } catch (e) {
        debugPrint('Error comprimiendo imagen: $e');
        break;
      }
      targetWidth -= 30;
    }

    return bytes;
  }

  Future<void> _cargarDatosBD() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final datosRaw = await ApiService.consultar('rutina_ol', 'rutina');

      // 1. Cargar Usuarios de BD
      try {
        final usuariosBD = await ApiService.consultar('rutina_ol', 'rutina_usuario');
        final Set<String> nombresSet = {};
        for (var u in usuariosBD) {
          if (u is Map && u['nombre'] != null) {
            String n = u['nombre'].toString().trim().toUpperCase();
            if (n.isNotEmpty) nombresSet.add(n);
          }
        }
        _listaNombresUsuariosBD = nombresSet.toList()..sort();
      } catch (e) {
        debugPrint('Error cargando usuarios: $e');
      }

      // 2. CARGAR LISTA OFICIAL (lista_rutina: Territorio, Rutina, Hashtag)
      try {
        final listaRutinaBD = await ApiService.consultar('rutina_ol', 'lista_rutina');
        final Set<String> terSet = {};
        final Set<String> rutSet = {};
        final Set<String> hashSet = {};

        for (var item in listaRutinaBD) {
          if (item is Map) {
            String? t = item['territorio']?.toString();
            String? r = item['rutina']?.toString();
            String? h = item['hashta']?.toString() ?? item['hashtag']?.toString() ?? item['#hashtag']?.toString();

            if (t != null && t.trim().isNotEmpty) terSet.add(t.trim());
            if (r != null && r.trim().isNotEmpty) rutSet.add(r.trim());
            if (h != null && h.trim().isNotEmpty) hashSet.add(h.trim());
          }
        }
        _listaTerritoriosBD = terSet.toList()..sort();
        _listaRutinasBD = rutSet.toList()..sort();
        _listaHashtagsBD = hashSet.toList()..sort();
      } catch (e) {
        debugPrint('Error cargando lista_rutina de BD: $e');
      }

      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> rutinasSet = {'Todas'};
      final Set<String> hashtagsSet = {'Todos'};
      final Set<String> duenosSet = {'Todas'};
      final Set<String> responsablesSet = {'Todos'};

      for (var fila in datosRaw) {
        if (fila is Map) {
          final Map<String, dynamic> mapa = {};
          fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
          datosProcesados.add(mapa);

          String? r = mapa['rutina']?.toString();
          String? h = mapa['hashtag']?.toString() ?? mapa['#hashtag']?.toString();
          String? d = mapa['dueño']?.toString() ?? mapa['dueno']?.toString();
          String? resp = mapa['responsable']?.toString();

          if (r != null && r.trim().isNotEmpty) rutinasSet.add(r.trim());
          if (h != null && h.trim().isNotEmpty) hashtagsSet.add(h.trim());
          if (d != null && d.trim().isNotEmpty) duenosSet.add(d.trim());
          if (resp != null && resp.trim().isNotEmpty) responsablesSet.add(resp.trim());
        }
      }

      setState(() {
        _todasLasAcciones = datosProcesados;
        _listaRutinas = rutinasSet.toList()..sort();
        _listaHashtags = hashtagsSet.toList()..sort();
        _listaDuenos = duenosSet.toList()..sort();
        _listaResponsables = responsablesSet.toList()..sort();

        _aplicarFiltros();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando acciones: $e');
      setState(() {
        _mensajeError = 'Error de conexión a BD: $e';
        _cargando = false;
      });
    }
  }

  String _determinarEstado(Map<String, dynamic> row) {
    String st = row['status']?.toString().trim() ?? '';
    if (st.isNotEmpty && st.toLowerCase() != 'null') {
      return st.toUpperCase();
    }

    String cierre = row['fecha_cierre']?.toString().trim() ?? row['cierre']?.toString().trim() ?? '';
    if (cierre.isNotEmpty && cierre.toLowerCase() != 'null' && cierre.toLowerCase() != 'pendiente') {
      return 'CERRADAS';
    }

    String? compStr = row['compromiso']?.toString();
    if (compStr != null && compStr.isNotEmpty) {
      DateTime? fechaComp = DateTime.tryParse(compStr.split('T')[0]);
      if (fechaComp != null) {
        DateTime hoy = DateTime.now();
        DateTime hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
        if (fechaComp.isBefore(hoySinHora)) {
          return 'RETRASADAS';
        }
      }
    }
    return 'EN PROGRESO';
  }

  void _aplicarFiltros() {
    setState(() {
      _accionesFiltradas = _todasLasAcciones.where((row) {
        if (_rutinaSel != 'Todas' && (row['rutina']?.toString() ?? '') != _rutinaSel) return false;

        String h = row['hashtag']?.toString() ?? row['#hashtag']?.toString() ?? '';
        if (_hashtagSel != 'Todos' && h != _hashtagSel) return false;

        String d = row['dueño']?.toString() ?? row['dueno']?.toString() ?? '';
        if (_duenoSel != 'Todas' && d != _duenoSel) return false;

        String resp = row['responsable']?.toString() ?? '';
        if (_responsableSel != 'Todos' && resp != _responsableSel) return false;

        String estadoCalculado = _determinarEstado(row);
        if (_estadoSel != 'Todos' && estadoCalculado != _estadoSel) return false;

        String? rawFecha = row['fecha_creacion']?.toString() ?? row['registr']?.toString() ?? row['fecha']?.toString();
        if (rawFecha != null && rawFecha.isNotEmpty) {
          DateTime? fechaFila = DateTime.tryParse(rawFecha.split('T')[0]);
          if (fechaFila != null) {
            if (_fechaDesde != null && fechaFila.isBefore(_fechaDesde!)) return false;
            if (_fechaHasta != null && fechaFila.isAfter(_fechaHasta!)) return false;
          }
        }

        if (_busquedaTexto.isNotEmpty) {
          String txt = _busquedaTexto.toLowerCase();
          String responsable = resp.toLowerCase();
          String accionCierre = (row['accion_cierre']?.toString() ?? row['accion']?.toString() ?? '').toLowerCase();
          String hallazgo = (row['hallazgo']?.toString() ?? '').toLowerCase();
          String territorio = (row['territorio']?.toString() ?? '').toLowerCase();
          String dueno = d.toLowerCase();
          if (!responsable.contains(txt) && !accionCierre.contains(txt) && !hallazgo.contains(txt) && !dueno.contains(txt) && !territorio.contains(txt)) {
            return false;
          }
        }

        return true;
      }).toList();

      _paginaActual = 1;
    });
  }

  // 🔍 BUSCADOR GENÉRICO EN DESPLEGABLE
  void _abrirBuscadorGenerico({
    required BuildContext dialogContext,
    required String titulo,
    required List<String> opciones,
    required TextEditingController controller,
    required StateSetter setModalState,
    bool filtrarUsuarioLogueado = false,
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
            final listaFiltrada = opciones.where((n) {
              final coincide = n.toLowerCase().contains(filtro.toLowerCase());
              if (filtrarUsuarioLogueado) {
                return coincide && n.trim().toUpperCase() != _nombreUsuarioLogueado.toUpperCase();
              }
              return coincide;
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Seleccionar $titulo', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Escriba para buscar $titulo...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF0D47A1)),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (val) => setBuscadorState(() => filtro = val),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                      child: listaFiltrada.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('No se encontraron opciones disponibles.', style: TextStyle(color: Colors.grey)),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        itemCount: listaFiltrada.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final nombre = listaFiltrada[index];
                          return ListTile(
                            dense: true,
                            title: Text(nombre, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            onTap: () {
                              setModalState(() {
                                controller.text = nombre;
                              });
                              Navigator.pop(ctx);
                            },
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

  // 🔍 MODAL CON BUSCADOR PARA BARRA DE FILTROS SUPERIOR
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
            final listaFiltrada = opciones
                .where((n) => n.toLowerCase().contains(filtro.toLowerCase()))
                .toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
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
                            title: Text(
                              opcion,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: esSeleccionado ? FontWeight.bold : FontWeight.normal,
                                color: esSeleccionado ? const Color(0xFF0D47A1) : Colors.black87,
                              ),
                            ),
                            trailing: esSeleccionado ? const Icon(Icons.check_circle, color: Color(0xFF0D47A1), size: 18) : null,
                            onTap: () {
                              onSelect(opcion);
                              Navigator.pop(ctx);
                            },
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

  // ➕ MODAL AGREGAR ACCIÓN
  void _abrirModalAgregarAccion() {
    final TextEditingController territorioCtrl = TextEditingController(
      text: _listaTerritoriosBD.isNotEmpty ? _listaTerritoriosBD.first : 'Tocancipá',
    );
    final TextEditingController rutinaCtrl = TextEditingController();
    final TextEditingController responsableCtrl = TextEditingController();
    final TextEditingController hashtagCtrl = TextEditingController();
    final TextEditingController hallazgoCtrl = TextEditingController();

    final DateTime fechaRegistroHoy = DateTime.now();
    DateTime? fechaCompromiso;
    Uint8List? fotoHallazgoBytes;
    String? fotoHallazgoNombre;
    bool guardandoModal = false;

    Future<void> seleccionarFoto(ImageSource source, StateSetter setModalState) async {
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          imageQuality: 10,
          maxWidth: 300,
          maxHeight: 300,
        );
        if (pickedFile != null) {
          final bytesOriginales = await pickedFile.readAsBytes();
          final bytesComprimidos = await _comprimirBytesMax15KB(bytesOriginales, maxKB: 15);

          setModalState(() {
            fotoHallazgoBytes = bytesComprimidos;
            fotoHallazgoNombre = pickedFile.name;
          });
        }
      } catch (e) {
        debugPrint('Error seleccionando imagen: $e');
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 580,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
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
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D47A1).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.add_task_rounded, color: Color(0xFF0D47A1), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Agregar Nueva Acción', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  Text('Dueño: $_nombreUsuarioLogueado', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black54),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _buildSelectorCampoModal(
                              label: 'Territorio *',
                              hint: 'Seleccionar Territorio...',
                              controller: territorioCtrl,
                              onTap: () => _abrirBuscadorGenerico(
                                dialogContext: dialogContext,
                                titulo: 'Territorio',
                                opciones: _listaTerritoriosBD,
                                controller: territorioCtrl,
                                setModalState: setModalState,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSelectorCampoModal(
                              label: 'Rutina *',
                              hint: 'Seleccionar Rutina...',
                              controller: rutinaCtrl,
                              onTap: () => _abrirBuscadorGenerico(
                                dialogContext: dialogContext,
                                titulo: 'Rutina',
                                opciones: _listaRutinasBD,
                                controller: rutinaCtrl,
                                setModalState: setModalState,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: _buildSelectorCampoModal(
                              label: 'Responsable *',
                              hint: 'Buscar Responsable...',
                              controller: responsableCtrl,
                              onTap: () => _abrirBuscadorGenerico(
                                dialogContext: dialogContext,
                                titulo: 'Responsable',
                                opciones: _listaNombresUsuariosBD,
                                controller: responsableCtrl,
                                setModalState: setModalState,
                                filtrarUsuarioLogueado: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSelectorCampoModal(
                              label: '#Hashtag',
                              hint: 'Seleccionar #Hashtag...',
                              controller: hashtagCtrl,
                              onTap: () => _abrirBuscadorGenerico(
                                dialogContext: dialogContext,
                                titulo: '#Hashtag',
                                opciones: _listaHashtagsBD,
                                controller: hashtagCtrl,
                                setModalState: setModalState,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Fecha Compromiso (Límite) *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: dialogContext,
                                      initialDate: fechaCompromiso ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null) {
                                      setModalState(() => fechaCompromiso = picked);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(6),
                                      color: const Color(0xFFF8F9FA),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          fechaCompromiso != null
                                              ? '${fechaCompromiso!.day.toString().padLeft(2, '0')}/${fechaCompromiso!.month.toString().padLeft(2, '0')}/${fechaCompromiso!.year}'
                                              : 'Seleccionar Fecha...',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: fechaCompromiso != null ? Colors.black87 : Colors.black38,
                                            fontWeight: fechaCompromiso != null ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                        ),
                                        const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF0D47A1)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInputForm('Hallazgo *', hallazgoCtrl, hint: 'Escriba la descripción del hallazgo u observación...', maxLines: 3),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: dialogContext,
                                      builder: (bCtx) => SafeArea(
                                        child: Wrap(
                                          children: [
                                            ListTile(
                                              leading: const Icon(Icons.camera_alt, color: Color(0xFF0D47A1)),
                                              title: const Text('Tomar Foto'),
                                              onTap: () {
                                                Navigator.pop(bCtx);
                                                seleccionarFoto(ImageSource.camera, setModalState);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.photo_library, color: Color(0xFF0D47A1)),
                                              title: const Text('Seleccionar de Galería'),
                                              onTap: () {
                                                Navigator.pop(bCtx);
                                                seleccionarFoto(ImageSource.gallery, setModalState);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.add_a_photo_rounded, size: 16),
                                  label: Text(
                                    fotoHallazgoBytes == null ? '+ Adjuntar Evidencia (Foto <= 15KB)' : 'Cambiar Foto',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0D47A1),
                                    side: BorderSide(color: const Color(0xFF0D47A1).withOpacity(0.3)),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                                if (fotoHallazgoBytes != null) ...[
                                  const SizedBox(width: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(fotoHallazgoBytes!, width: 42, height: 42, fit: BoxFit.cover),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 20),
                                    onPressed: () => setModalState(() {
                                      fotoHallazgoBytes = null;
                                      fotoHallazgoNombre = null;
                                    }),
                                  )
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: guardandoModal ? null : () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancelar', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: guardandoModal
                                ? null
                                : () async {
                              final respSel = responsableCtrl.text.trim().toUpperCase();

                              if (respSel == _nombreUsuarioLogueado) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('⚠️ El dueño no puede asignarse acciones a sí mismo.'), backgroundColor: Colors.orange),
                                );
                                return;
                              }

                              if (rutinaCtrl.text.trim().isEmpty ||
                                  responsableCtrl.text.trim().isEmpty ||
                                  hallazgoCtrl.text.trim().isEmpty ||
                                  fechaCompromiso == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('⚠️ Complete todos los campos obligatorios (*) incluyendo la Fecha Límite.'), backgroundColor: Colors.orange),
                                );
                                return;
                              }

                              setModalState(() => guardandoModal = true);

                              try {
                                String? urlFotoSubida;
                                if (fotoHallazgoBytes != null && fotoHallazgoNombre != null) {
                                  try {
                                    urlFotoSubida = await ApiService.subirFoto('evidencia_hallazgo', fotoHallazgoBytes!, fotoHallazgoNombre!);
                                  } catch (e) {
                                    debugPrint("Error subiendo foto de hallazgo: $e");
                                  }
                                }

                                final Map<String, dynamic> nuevaAccionData = {
                                  'id': 'ACC_${DateTime.now().millisecondsSinceEpoch}',
                                  'territorio': territorioCtrl.text.trim().isEmpty ? 'Tocancipá' : territorioCtrl.text.trim(),
                                  'rutina': rutinaCtrl.text.trim(),
                                  'dueño': _nombreUsuarioLogueado,
                                  'responsable': responsableCtrl.text.trim(),
                                  'fecha_creacion': fechaRegistroHoy.toIso8601String().split('T')[0],
                                  'compromiso': fechaCompromiso!.toIso8601String().split('T')[0],
                                  'fecha_cierre': null,
                                  'hashtag': hashtagCtrl.text.trim().isEmpty ? '#Prioridades de turno' : hashtagCtrl.text.trim(),
                                  'hallazgo': hallazgoCtrl.text.trim(),
                                  'evidencia_hallazgo': urlFotoSubida,
                                  'accion_cierre': null,
                                  'evidencia_cierre': null,
                                  'status': 'EN PROGRESO',
                                };

                                await ApiService.insertar('rutina_ol', 'rutina', nuevaAccionData);

                                if (mounted) {
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('✅ Acción registrada correctamente'), backgroundColor: Colors.green),
                                  );
                                  _cargarDatosBD();
                                }
                              } catch (e) {
                                setModalState(() => guardandoModal = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('❌ Error al guardar: $e'), backgroundColor: Colors.red),
                                );
                              }
                            },
                            icon: guardandoModal
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                                : const Icon(Icons.save_rounded, size: 16),
                            label: Text(guardandoModal ? 'Guardando...' : 'Guardar Acción', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC107),
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
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

  Widget _buildSelectorCampoModal({
    required String label,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
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
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: const Color(0xFFF8F9FA),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    controller.text.isEmpty ? hint : controller.text,
                    style: TextStyle(
                      fontSize: 12,
                      color: controller.text.isEmpty ? Colors.black38 : Colors.black87,
                      fontWeight: controller.text.isEmpty ? FontWeight.normal : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.search_rounded, size: 16, color: Color(0xFF0D47A1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🛡️ MODAL GESTIONAR Y CERRAR ACCIÓN
  void _abrirModalGestionarCierre(Map<String, dynamic> row) {
    final String id = row['id']?.toString() ?? '';
    final String responsableFila = (row['responsable'] ?? '').toString().trim().toUpperCase();

    final bool esResponsable = responsableFila == _nombreUsuarioLogueado;

    final String hallazgoTexto = row['hallazgo']?.toString() ?? '';
    final TextEditingController accionCierreCtrl = TextEditingController(text: row['accion_cierre']?.toString() ?? row['accion']?.toString() ?? '');

    DateTime fechaCierreSeleccionada = DateTime.now();
    Uint8List? fotoCierreBytes;
    String? fotoCierreNombre;
    bool guardandoModal = false;

    Future<void> seleccionarFotoCierre(ImageSource source, StateSetter setModalState) async {
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          imageQuality: 10,
          maxWidth: 300,
          maxHeight: 300,
        );
        if (pickedFile != null) {
          final bytesOriginales = await pickedFile.readAsBytes();
          final bytesComprimidos = await _comprimirBytesMax15KB(bytesOriginales, maxKB: 15);

          setModalState(() {
            fotoCierreBytes = bytesComprimidos;
            fotoCierreNombre = pickedFile.name;
          });
        }
      } catch (e) {
        debugPrint('Error seleccionando imagen cierre: $e');
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                width: 580,
                padding: const EdgeInsets.all(24),
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
                              const Icon(Icons.rule_folder_rounded, color: Color(0xFF0D47A1)),
                              const SizedBox(width: 8),
                              Text(
                                esResponsable ? 'Gestión y Cierre de Acción' : 'Detalle de Acción (Solo Lectura)',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Divider(),

                      if (!esResponsable) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Solo el Responsable asignado ($responsableFila) puede registrar la acción de cierre.',
                                  style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),
                      Text('• Dueño/Creador: ${row['dueño'] ?? row['dueno']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('• Responsable: ${row['responsable']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Hallazgo Original', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              hallazgoTexto.isEmpty ? '-' : hallazgoTexto,
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      _buildInputForm(
                        'Acción de Cierre / Descripción ejecutada *',
                        accionCierreCtrl,
                        maxLines: 3,
                        readOnly: !esResponsable,
                        backgroundColor: !esResponsable ? Colors.grey.shade200 : null,
                      ),
                      const SizedBox(height: 12),

                      if (esResponsable) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Fecha Real de Cierre *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: fechaCierreSeleccionada,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setModalState(() => fechaCierreSeleccionada = picked);
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.blue.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${fechaCierreSeleccionada.day.toString().padLeft(2, '0')}/${fechaCierreSeleccionada.month.toString().padLeft(2, '0')}/${fechaCierreSeleccionada.year}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                    const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF0D47A1)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: dialogContext,
                                  builder: (bCtx) => SafeArea(
                                    child: Wrap(
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.camera_alt, color: Color(0xFF0D47A1)),
                                          title: const Text('Tomar Foto de Cierre'),
                                          onTap: () {
                                            Navigator.pop(bCtx);
                                            seleccionarFotoCierre(ImageSource.camera, setModalState);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.photo_library, color: Color(0xFF0D47A1)),
                                          title: const Text('Galería'),
                                          onTap: () {
                                            Navigator.pop(bCtx);
                                            seleccionarFotoCierre(ImageSource.gallery, setModalState);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add_a_photo, size: 16),
                              label: Text(fotoCierreBytes == null ? '+ Evidencia Cierre (Foto <= 15KB)' : 'Cambiar Foto Cierre', style: const TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE8F5E9),
                                foregroundColor: const Color(0xFF0D47A1),
                                elevation: 0,
                              ),
                            ),
                            if (fotoCierreBytes != null) ...[
                              const SizedBox(width: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(fotoCierreBytes!, width: 40, height: 40, fit: BoxFit.cover),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                onPressed: () => setModalState(() {
                                  fotoCierreBytes = null;
                                  fotoCierreNombre = null;
                                }),
                              )
                            ]
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(!esResponsable ? 'Cerrar' : 'Cancelar', style: const TextStyle(color: Colors.grey)),
                          ),
                          if (esResponsable) ...[
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: guardandoModal
                                  ? null
                                  : () async {
                                if (accionCierreCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('⚠️ Ingrese la descripción de la acción de cierre.'), backgroundColor: Colors.orange),
                                  );
                                  return;
                                }

                                setModalState(() => guardandoModal = true);

                                try {
                                  String? urlFotoCierre;
                                  if (fotoCierreBytes != null && fotoCierreNombre != null) {
                                    try {
                                      urlFotoCierre = await ApiService.subirFoto('evidencia_cierre', fotoCierreBytes!, fotoCierreNombre!);
                                    } catch (e) {
                                      debugPrint("Error al subir imagen de cierre: $e");
                                    }
                                  }

                                  final Map<String, dynamic> updateData = {
                                    'accion_cierre': accionCierreCtrl.text.trim(),
                                    'fecha_cierre': fechaCierreSeleccionada.toIso8601String().split('T')[0],
                                    'status': 'CERRADAS',
                                  };

                                  if (urlFotoCierre != null) {
                                    updateData['evidencia_cierre'] = urlFotoCierre;
                                  }

                                  await ApiService.actualizar('rutina_ol', 'rutina', 'id', id, updateData);

                                  if (mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✅ Acción cerrada exitosamente'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                    _cargarDatosBD();
                                  }
                                } catch (e) {
                                  setModalState(() => guardandoModal = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('❌ Error actualizando datos: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              },
                              icon: guardandoModal
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_circle_outline, size: 16),
                              label: Text(guardandoModal ? 'Guardando...' : 'Guardar y Cerrar Acción', style: const TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E88E5),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              ),
                            ),
                          ],
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

  // 🖼️ VISOR DE IMÁGENES
  void _mostrarPreviewImagen(String url) {
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
                title: const Text('Evidencia Adjunta', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                automaticallyImplyLeading: false,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildImagenContenido(url),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SelectableText(
                  url.startsWith('data:image') ? 'Imagen almacenada en BD (<= 15KB)' : url,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagenContenido(String url) {
    if (url.startsWith('data:image')) {
      try {
        final String base64Str = url.split(',').last;
        final Uint8List bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (e) {
        return const Center(child: Text('❌ Error al decodificar imagen Base64.'));
      }
    } else {
      return Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1)));
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(child: Text('❌ No se pudo cargar la imagen desde el servidor.'));
        },
      );
    }
  }

  String? _extraerUrl(String texto) {
    if (texto.startsWith('http://') || texto.startsWith('https://') || texto.startsWith('data:image')) {
      return texto.trim();
    }
    final regExp = RegExp(r'(https?://[^\s\]]+|data:image/[^\s\]]+)');
    final match = regExp.firstMatch(texto);
    return match?.group(0);
  }

  Widget _buildInputForm(String label, TextEditingController controller, {String? hint, int maxLines = 1, bool readOnly = false, Color? backgroundColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 11),
            filled: backgroundColor != null,
            fillColor: backgroundColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))),
      );
    }

    int progreso = 0;
    int retrasadas = 0;
    int cerradas = 0;

    for (var a in _todasLasAcciones) {
      String est = _determinarEstado(a);
      if (est == 'CERRADAS') cerradas++;
      else if (est == 'RETRASADAS') retrasadas++;
      else progreso++;
    }

    int totalAcciones = _todasLasAcciones.length;

    int totalPaginas = max(1, (_accionesFiltradas.length / _registrosPorPagina).ceil());
    int inicio = (_paginaActual - 1) * _registrosPorPagina;
    int fin = min(inicio + _registrosPorPagina, _accionesFiltradas.length);
    List<Map<String, dynamic>> paginaActualLista = _accionesFiltradas.isEmpty
        ? []
        : _accionesFiltradas.sublist(inicio, fin);

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

            _buildTarjetasKPI(progreso, retrasadas, cerradas, totalAcciones),
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

  // 🚪 ENCABEZADO CON BOTÓN DE MENÚ LATERAL Y BOTÓN ACTUALIZAR
  Widget _buildEncabezado() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (widget.onToggleSidebar != null)
              IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF0D47A1)),
                onPressed: widget.onToggleSidebar,
              ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BAÚL DE ACCIONES',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Gestión Logística y Supply Chain',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _cargarDatosBD,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text(
            'Actualizar',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetasKPI(int progreso, int retrasadas, int cerradas, int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildKPICard('En progreso', '$progreso', const Color(0xFFFFB300)),
        const SizedBox(width: 12),
        _buildKPICard('Retrasadas', '$retrasadas', const Color(0xFFE53935)),
        const SizedBox(width: 12),
        _buildKPICard('Cerradas', '$cerradas', const Color(0xFF1E88E5)),
        const SizedBox(width: 12),
        _buildKPICard('Total Acciones', '$total', const Color(0xFF43A047)),
      ],
    );
  }

  Widget _buildKPICard(String titulo, String valor, Color colorTexto) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Text(
            valor,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorTexto),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _buildDropdownFiltro('Rutina', _rutinaSel, _listaRutinas, (v) => setState(() { _rutinaSel = v!; _aplicarFiltros(); })),
          _buildDropdownFiltro('#Hashtag', _hashtagSel, _listaHashtags, (v) => setState(() { _hashtagSel = v!; _aplicarFiltros(); })),
          _buildSelectorBuscadorFiltro('Dueño', _duenoSel, _listaDuenos, (val) => setState(() { _duenoSel = val; _aplicarFiltros(); })),
          _buildSelectorBuscadorFiltro('Responsable', _responsableSel, _listaResponsables, (val) => setState(() { _responsableSel = val; _aplicarFiltros(); })),
          _buildDropdownFiltro('Estado', _estadoSel, _listaEstados, (v) => setState(() { _estadoSel = v!; _aplicarFiltros(); })),
          _buildSelectorFechaFiltro('Desde', _fechaDesde, (d) => setState(() { _fechaDesde = d; _aplicarFiltros(); })),
          _buildSelectorFechaFiltro('Hasta', _fechaHasta, (d) => setState(() { _fechaHasta = d; _aplicarFiltros(); })),
        ],
      ),
    );
  }

  Widget _buildSelectorBuscadorFiltro(String label, String valorActual, List<String> opciones, Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _abrirModalBuscadorFiltro(label, opciones, valorActual, onSelect),
          child: Container(
            width: 160,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    valorActual,
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.search, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownFiltro(String label, String valor, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(valor) ? valor : items.first,
              isDense: true,
              isExpanded: true,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
              items: items.map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, overflow: TextOverflow.ellipsis, maxLines: 1),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorFechaFiltro(String label, DateTime? fecha, Function(DateTime?) onSelect) {
    String txt = fecha != null ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}' : 'dd/mm/aaaa';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: fecha ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            onSelect(picked);
          },
          child: Container(
            width: 130,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(txt, style: TextStyle(fontSize: 11, color: fecha != null ? Colors.black87 : Colors.grey)),
                const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContenedorTabla(List<Map<String, dynamic>> paginaLista, int inicio, int fin, int totalPaginas) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Acciones Registradas', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                ElevatedButton.icon(
                  onPressed: _abrirModalAgregarAccion,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Agregar Acción', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                          onChanged: (v) => setState(() {
                            _registrosPorPagina = v!;
                            _paginaActual = 1;
                          }),
                        ),
                      ),
                    ),
                    const Text(' registros', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                Row(
                  children: [
                    const Text('Buscar: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    SizedBox(
                      width: 180,
                      height: 30,
                      child: TextField(
                        style: const TextStyle(fontSize: 11),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                        onChanged: (v) {
                          _busquedaTexto = v;
                          _aplicarFiltros();
                        },
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),

          const SizedBox(height: 10),

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
                  padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 12.0),
                  child: Table(
                    border: TableBorder.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                    columnWidths: const {
                      0: FixedColumnWidth(110),
                      1: FixedColumnWidth(130),
                      2: FixedColumnWidth(190),
                      3: FixedColumnWidth(190),
                      4: FixedColumnWidth(110),
                      5: FixedColumnWidth(110),
                      6: FixedColumnWidth(130),
                      7: FixedColumnWidth(300),
                      8: FixedColumnWidth(300),
                      9: FixedColumnWidth(110),
                      10: FixedColumnWidth(70),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFFFAFAFA),
                        ),
                        children: [
                          _headerCell('Territorio'),
                          _headerCell('Rutina'),
                          _headerCell('Dueño'),
                          _headerCell('Responsable'),
                          _headerCell('Fecha Creación'),
                          _headerCell('Fecha Cierre'),
                          _headerCell('Hashtag'),
                          _headerCell('Hallazgo / Evidencia'),
                          _headerCell('Acción de Cierre / Evidencia'),
                          _headerCell('Status'),
                          _headerCell('Acción'),
                        ],
                      ),

                      ...paginaLista.map((row) {
                        String territorio = row['territorio']?.toString() ?? '-';
                        String rutina = row['rutina']?.toString() ?? '-';
                        String dueno = row['dueño']?.toString() ?? row['dueno']?.toString() ?? '-';
                        String responsable = row['responsable']?.toString() ?? '-';

                        String rawFechaCreacion = row['fecha_creacion']?.toString() ?? row['registr']?.toString() ?? row['fecha']?.toString() ?? '';
                        String fechaCreacion = rawFechaCreacion.isNotEmpty ? rawFechaCreacion.split('T')[0] : '-';

                        String rawCierre = row['fecha_cierre']?.toString() ?? row['cierre']?.toString() ?? '';
                        String fechaCierre = rawCierre.isNotEmpty && rawCierre.toLowerCase() != 'null'
                            ? rawCierre.split('T')[0]
                            : 'Pendiente';

                        String hashtag = row['hashtag']?.toString() ?? row['#hashtag']?.toString() ?? '-';
                        String hallazgo = row['hallazgo']?.toString() ?? '-';
                        String accionCierre = row['accion_cierre']?.toString() ?? row['accion']?.toString() ?? '-';

                        String? urlEvidenciaHallazgo = row['evidencia_hallazgo']?.toString();
                        if (urlEvidenciaHallazgo == null || (!urlEvidenciaHallazgo.startsWith('http') && !urlEvidenciaHallazgo.startsWith('data:image'))) {
                          urlEvidenciaHallazgo = _extraerUrl(hallazgo);
                        }
                        String hallazgoLimpio = hallazgo.replaceAll(RegExp(r'(https?://[^\s\]]+|data:image/[^\s\]]+)'), '').replaceAll('|', '').trim();

                        String? urlEvidenciaCierre = row['evidencia_cierre']?.toString();
                        if (urlEvidenciaCierre == null || (!urlEvidenciaCierre.startsWith('http') && !urlEvidenciaCierre.startsWith('data:image'))) {
                          urlEvidenciaCierre = _extraerUrl(rawCierre);
                        }
                        String accionCierreLimpia = accionCierre.replaceAll(RegExp(r'(https?://[^\s\]]+|data:image/[^\s\]]+)'), '').replaceAll('|', '').trim();

                        String estado = _determinarEstado(row);

                        return TableRow(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                          ),
                          children: [
                            _dataCell(territorio),
                            _dataCell(rutina),
                            _dataCellDueno(dueno),
                            _dataCell(responsable),
                            _dataCell(_formatearFechaVisual(fechaCreacion)),
                            _dataCell(_formatearFechaVisual(fechaCierre)),
                            _dataCell(hashtag),
                            _dataCellTextoYEvidencia(hallazgoLimpio, urlEvidenciaHallazgo),
                            _dataCellTextoYEvidencia(accionCierreLimpia, urlEvidenciaCierre),
                            _dataCellEstado(estado),
                            _dataCellAccionEdit(row),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 15),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mostrando ${paginaLista.isEmpty ? 0 : inicio + 1} a $fin de ${_accionesFiltradas.length} registros',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Row(
                  children: [
                    InkWell(
                      onTap: _paginaActual > 1 ? () => setState(() => _paginaActual--) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                        child: const Text('Anterior', style: TextStyle(fontSize: 11, color: Colors.blue)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...List.generate(min(totalPaginas, 9), (index) {
                      int pageNum = index + 1;
                      bool esActiva = pageNum == _paginaActual;
                      return InkWell(
                        onTap: () => setState(() => _paginaActual = pageNum),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: esActiva ? const Color(0xFF1976D2) : Colors.white,
                            border: Border.all(color: esActiva ? const Color(0xFF1976D2) : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('$pageNum', style: TextStyle(fontSize: 11, color: esActiva ? Colors.white : Colors.blue)),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _paginaActual < totalPaginas ? () => setState(() => _paginaActual++) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                        child: const Text('Siguiente', style: TextStyle(fontSize: 11, color: Colors.blue)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.unfold_more, size: 12, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _dataCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 10.5, color: Colors.black87, height: 1.3)),
    );
  }

  Widget _dataCellTextoYEvidencia(String texto, String? url) {
    String textoLimpio = texto.trim();
    bool tieneEvidencia = url != null && url.trim().isNotEmpty && url != 'null';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              textoLimpio.isEmpty ? '-' : textoLimpio,
              style: const TextStyle(fontSize: 10.5, color: Colors.black87, height: 1.3),
            ),
          ),
          if (tieneEvidencia) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.remove_red_eye_rounded, size: 18, color: Color(0xFF0D47A1)),
              tooltip: 'Ver Evidencia',
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              onPressed: () => _mostrarPreviewImagen(url),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dataCellDueno(String dueno) {
    String inicial = dueno.isNotEmpty ? dueno[0].toUpperCase() : 'U';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: const Color(0xFF455A64),
            child: Text(inicial, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              dueno,
              style: const TextStyle(fontSize: 10.5, color: Colors.black87, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCellEstado(String estado) {
    Color colorBadge;
    if (estado == 'CERRADAS') colorBadge = const Color(0xFF607D8B);
    else if (estado == 'RETRASADAS') colorBadge = const Color(0xFFE53935);
    else colorBadge = const Color(0xFFFFB300);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: colorBadge, borderRadius: BorderRadius.circular(12)),
        child: Text(
          estado,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _dataCellAccionEdit(Map<String, dynamic> row) {
    final String responsableFila = (row['responsable'] ?? '').toString().trim().toUpperCase();
    final bool esResponsable = responsableFila == _nombreUsuarioLogueado;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: IconButton(
        icon: Icon(
          Icons.edit_note_rounded,
          size: 18,
          color: esResponsable ? Colors.black87 : Colors.grey.shade300,
        ),
        tooltip: esResponsable
            ? 'Gestionar / Cerrar Acción'
            : 'Solo el Responsable ($responsableFila) puede cerrar esta acción',
        onPressed: () => _abrirModalGestionarCierre(row),
        constraints: const BoxConstraints(),
        padding: EdgeInsets.zero,
      ),
    );
  }

  String _formatearFechaVisual(String fechaRaw) {
    if (fechaRaw.isEmpty || fechaRaw == '-' || fechaRaw == 'Pendiente') return fechaRaw;
    try {
      List<String> partes = fechaRaw.split('-');
      if (partes.length == 3) {
        return '${partes[2]}/${partes[1]}/${partes[0]}';
      }
    } catch (_) {}
    return fechaRaw;
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade700)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold))),
          InkWell(
            onTap: _cargarDatosBD,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.amber.shade900, borderRadius: BorderRadius.circular(4)),
              child: const Text('REINTENTAR', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}