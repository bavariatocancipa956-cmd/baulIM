import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // <-- Para compute()
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img; // <-- LIBRERÍA DE COMPRESIÓN
import 'api_service.dart';

// ==========================================
// MOTOR DE COMPRESIÓN INTELIGENTE (AISLADO)
// ==========================================
// Esta función corre en un hilo secundario (Isolate/Worker)
// para no congelar la pantalla mientras comprime la foto.
Uint8List comprimirImagenWorker(Uint8List bytes) {
  img.Image? decodedImage = img.decodeImage(bytes);
  if (decodedImage == null) return bytes;

  // 1. Redimensionar si es muy grande (mantiene la proporción automáticamente)
  img.Image resized = decodedImage;
  if (decodedImage.width > 600) {
    resized = img.copyResize(decodedImage, width: 600);
  }

  // 2. Bucle iterativo: Convertir a JPEG y bajar calidad hasta que pese < 50 KB
  int quality = 85;
  Uint8List result = img.encodeJpg(resized, quality: quality);

  // 51200 bytes = 50 KB
  while (result.length > 51200 && quality > 5) {
    quality -= 15; // Reducimos la calidad agresivamente en cada intento
    result = img.encodeJpg(resized, quality: quality);
  }

  return result;
}

// --- CLASE PARA MANEJAR LAS ACCIONES (MÁXIMO 4) ---
class AccionItem {
  String? tipoAccion;
  String? actividadSeleccionada;
  final TextEditingController actividadCtrl = TextEditingController();
  final TextEditingController descripcionCtrl = TextEditingController();
  final TextEditingController responsableCtrl = TextEditingController();
  DateTime? fechaCierre;
  String estado = 'Pendiente'; // SIEMPRE SE GUARDARÁ COMO PENDIENTE POR DEFECTO

  void dispose() {
    actividadCtrl.dispose();
    descripcionCtrl.dispose();
    responsableCtrl.dispose();
  }
}

class CincoWhyScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onToggleSidebar;

  const CincoWhyScreen({
    super.key,
    required this.usuario,
    required this.onToggleSidebar,
  });

  @override
  State<CincoWhyScreen> createState() => _CincoWhyScreenState();
}

class _CincoWhyScreenState extends State<CincoWhyScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // Variables Generales
  DateTime _fecha = DateTime.now();
  String _turno = 'T1';

  final _areaCtrl = TextEditingController();
  final _participantesCtrl = TextEditingController();

  // Lista de PI
  String? _piSeleccionado;
  List<String> _listaPI = [
    'Rotura',
    'Tiempo verificacion',
    'Tiempo BAHIA',
    'Fefo',
    'Rotacion',
    'Bpm',
    'Maquila',
    'Reparacion estibas',
  ];
  bool _cargandoPI = false;

  // Lista de Interventores
  String? _interventorSeleccionado;
  List<String> _listaInterventores = [];
  bool _cargandoInterventores = false;

  // Lista de Supervisores (NUEVO)
  String? _supervisorSeleccionado;
  List<String> _listaSupervisores = [];
  bool _cargandoSupervisores = false;

  // Disparador y Contención
  final _valorDisparadorCtrl = TextEditingController();
  final _accionContencionCtrl = TextEditingController();

  // 5 Porqués
  final List<TextEditingController> _porQuesCtrl = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _expliqueCtrl = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _evidenciasCtrl = List.generate(
    5,
    (_) => TextEditingController(),
  );

  // Lista para almacenar los bytes limpios de las imágenes comprimidas
  final List<Uint8List?> _evidenciasImagenes = List.filled(5, null);
  final ImagePicker _picker = ImagePicker();

  // Investigación adicional y Causa Raíz
  String? _necesitaInvestigacion;
  String? _causaRaizEncontrada;
  final _causaRaizCtrl = TextEditingController();

  // Tabla de Acciones: LA PRIMERA SIEMPRE ES PREVENTIVA POR DEFECTO
  final List<AccionItem> _acciones = [
    AccionItem()..tipoAccion = 'Preventiva',
    AccionItem(),
  ];

  // Validación de Calidad del Análisis
  String? _cumpleFlujo;
  String? _resolucionPrimeraLinea;
  String? _secuenciaSentido;
  String? _porquesEvidencia;
  String? _accionesEliminacion;

  @override
  void initState() {
    super.initState();
    _cargarListaPI();
    _cargarListaInterventores();
    _cargarListaSupervisores(); // <-- Cargar supervisores al inicio
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _participantesCtrl.dispose();
    _valorDisparadorCtrl.dispose();
    _accionContencionCtrl.dispose();
    _causaRaizCtrl.dispose();
    for (var c in _porQuesCtrl) {
      c.dispose();
    }
    for (var c in _expliqueCtrl) {
      c.dispose();
    }
    for (var c in _evidenciasCtrl) {
      c.dispose();
    }
    for (var a in _acciones) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarListaPI() async {
    setState(() => _cargandoPI = true);
    try {
      final List<dynamic> data = await ApiService.consultar(
        'gestion',
        'pi_5why',
      );
      setState(() {
        _listaPI = data.map((e) => e['pi'].toString()).toList();
      });
    } catch (e) {
      debugPrint('Error al cargar PIs (usando lista por defecto): $e');
    } finally {
      if (mounted) setState(() => _cargandoPI = false);
    }
  }

  Future<void> _cargarListaInterventores() async {
    setState(() => _cargandoInterventores = true);
    try {
      final List<dynamic> data = await ApiService.consultar(
        'gestion',
        'interventor',
      );
      setState(() {
        _listaInterventores = data
            .map((e) => e['interventor'].toString())
            .toList();
      });
    } catch (e) {
      debugPrint('Error al cargar Interventores: $e');
    } finally {
      if (mounted) setState(() => _cargandoInterventores = false);
    }
  }

  // --- NUEVA FUNCIÓN PARA CARGAR SUPERVISORES DE OL ---
  Future<void> _cargarListaSupervisores() async {
    setState(() => _cargandoSupervisores = true);
    try {
      // Consultamos la tabla rutina_usuario en el esquema rutina_ol
      final List<dynamic> data = await ApiService.consultar(
        'rutina_ol',
        'rutina_usuario',
      );
      setState(() {
        _listaSupervisores = data
            .where((e) => e['empresa']?.toString().toUpperCase() == 'OL')
            .map((e) => e['nombre'].toString())
            .toList();
      });
    } catch (e) {
      debugPrint('Error al cargar Supervisores: $e');
    } finally {
      if (mounted) setState(() => _cargandoSupervisores = false);
    }
  }

  // ==========================================
  // SELECCIÓN Y COMPRESIÓN DE LA FOTO
  // ==========================================
  Future<void> _seleccionarImagen(int index) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        Uint8List bytes = await image.readAsBytes();

        if (bytes.length > 51200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Optimizando foto para que pese menos de 50 KB...',
                ),
                duration: Duration(seconds: 2),
              ),
            );
          }
          bytes = await compute(comprimirImagenWorker, bytes);
        }

        if (bytes.length > 51200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'La imagen es demasiado compleja. Intente con otra foto de menor tamaño.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        setState(() {
          _evidenciasImagenes[index] = bytes;
        });

        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imagen adjuntada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar la imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  void _eliminarImagen(int index) {
    setState(() => _evidenciasImagenes[index] = null);
  }

  Future<void> _seleccionarFechaGeneral() async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          primaryColor: const Color(0xFF0A2540),
          colorScheme: const ColorScheme.light(primary: Color(0xFF0A2540)),
        ),
        child: child!,
      ),
    );
    if (seleccion != null) setState(() => _fecha = seleccion);
  }

  Future<void> _seleccionarFechaAccion(int index) async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          primaryColor: const Color(0xFF0A2540),
          colorScheme: const ColorScheme.light(primary: Color(0xFF0A2540)),
        ),
        child: child!,
      ),
    );
    if (seleccion != null)
      setState(() => _acciones[index].fechaCierre = seleccion);
  }

  void _agregarAccion() {
    if (_acciones.length < 4) setState(() => _acciones.add(AccionItem()));
  }

  void _eliminarAccion(int index) {
    if (index == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La primera acción preventiva es obligatoria y no se puede eliminar.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_acciones.length > 2) {
      setState(() {
        _acciones[index].dispose();
        _acciones.removeAt(index);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe registrar al menos 2 acciones'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _enviarFormulario() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, complete los campos obligatorios'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_necesitaInvestigacion == null || _causaRaizEncontrada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete la conclusión de la investigación'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_causaRaizEncontrada == 'SI' && _causaRaizCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor describa la causa raíz encontrada en el recuadro',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    bool tienePreventiva = false;

    for (int i = 0; i < _acciones.length; i++) {
      if (_acciones[i].tipoAccion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Seleccione el tipo de acción para la Acción #${i + 1}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_acciones[i].tipoAccion == 'Preventiva') {
        tienePreventiva = true;
        if (_acciones[i].actividadSeleccionada == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Seleccione una actividad para la Acción #${i + 1}',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (_acciones[i].descripcionCtrl.text.trim().isEmpty ||
          _acciones[i].responsableCtrl.text.trim().isEmpty ||
          _acciones[i].fechaCierre == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complete descripción, responsable y fecha en la Acción #${i + 1}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!tienePreventiva) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Es obligatorio registrar al menos una acción de tipo "Preventiva".',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // --- 1. SUBIR IMÁGENES AL SERVIDOR Y OBTENER URLs ---
    List<String> urlsImagenes = ['', '', '', '', ''];
    for (int i = 0; i < 5; i++) {
      if (_evidenciasImagenes[i] != null) {
        String? urlSubida = await ApiService.subirImagen(
          _evidenciasImagenes[i]!,
        );
        if (urlSubida != null) {
          urlsImagenes[i] = urlSubida;
        } else {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al subir la foto #${i + 1} al servidor'),
                backgroundColor: Colors.red,
              ),
            );
          setState(() => _isSubmitting = false);
          return;
        }
      }
    }

    // --- 2. PREPARAR EL TEXTO FINAL DE LA EVIDENCIA ---
    String getEvidenciaFinal(int index) {
      String texto = _evidenciasCtrl[index].text.trim();
      String url = urlsImagenes[index];
      if (url.isNotEmpty && texto.isNotEmpty) return '$texto | $url';
      if (url.isNotEmpty) return url;
      return texto;
    }

    String getValorActividad(AccionItem a) {
      if (a.tipoAccion == 'Preventiva') return a.actividadSeleccionada ?? '';
      return '';
    }

    // --- 3. ARMAR EL PAYLOAD ---
    final Map<String, dynamic> payload = {
      'fecha': DateFormat('yyyy-MM-dd').format(_fecha),
      'turno': _turno,
      'participantes': _participantesCtrl.text.trim(),
      'interventor': _interventorSeleccionado ?? '',
      'supervisor':
          _supervisorSeleccionado ?? '', // <-- NUEVO CAMPO DE SUPERVISOR
      'pi': _piSeleccionado ?? '',
      'area': _areaCtrl.text.trim(),
      'valor_disparador_alcanzado': _valorDisparadorCtrl.text.trim(),
      'contencion_problema': _accionContencionCtrl.text.trim(),

      'porque_1': _porQuesCtrl[0].text.trim(),
      'explique_porque_1': _expliqueCtrl[0].text.trim(),
      'evidencia_porque_1': getEvidenciaFinal(0),
      'porque_2': _porQuesCtrl[1].text.trim(),
      'explique_porque_2': _expliqueCtrl[1].text.trim(),
      'evidencia_porque_2': getEvidenciaFinal(1),
      'porque_3': _porQuesCtrl[2].text.trim(),
      'explique_porque_3': _expliqueCtrl[2].text.trim(),
      'evidencia_porque_3': getEvidenciaFinal(2),
      'porque_4': _porQuesCtrl[3].text.trim(),
      'explique_porque_4': _expliqueCtrl[3].text.trim(),
      'evidencia_porque_4': getEvidenciaFinal(3),
      'porque_5': _porQuesCtrl[4].text.trim(),
      'explique_porque_5': _expliqueCtrl[4].text.trim(),
      'evidencia_porque_5': getEvidenciaFinal(4),

      'requiere_investigacion_adicional': _necesitaInvestigacion,
      'encontro_causa_raiz': _causaRaizEncontrada,
      'causa_raiz': _causaRaizCtrl.text.trim(),

      'accion_1': _acciones.isNotEmpty ? _acciones[0].tipoAccion : '',
      'actividad_1': _acciones.isNotEmpty
          ? getValorActividad(_acciones[0])
          : '',
      'descripcion_1': _acciones.isNotEmpty
          ? _acciones[0].descripcionCtrl.text
          : '',
      'responsable_1': _acciones.isNotEmpty
          ? _acciones[0].responsableCtrl.text
          : '',
      'fecha_cierre_1':
          (_acciones.isNotEmpty && _acciones[0].fechaCierre != null)
          ? DateFormat('yyyy-MM-dd').format(_acciones[0].fechaCierre!)
          : null,
      'estado_accion1': _acciones.isNotEmpty ? _acciones[0].estado : '',

      'accion_2': _acciones.length > 1 ? _acciones[1].tipoAccion : '',
      'actividad_2': _acciones.length > 1
          ? getValorActividad(_acciones[1])
          : '',
      'descripcion_2': _acciones.length > 1
          ? _acciones[1].descripcionCtrl.text
          : '',
      'responsable_2': _acciones.length > 1
          ? _acciones[1].responsableCtrl.text
          : '',
      'fecha_cierre_2':
          (_acciones.length > 1 && _acciones[1].fechaCierre != null)
          ? DateFormat('yyyy-MM-dd').format(_acciones[1].fechaCierre!)
          : null,
      'estado_accion2': _acciones.length > 1 ? _acciones[1].estado : '',

      'accion_3': _acciones.length > 2 ? _acciones[2].tipoAccion : '',
      'actividad_3': _acciones.length > 2
          ? getValorActividad(_acciones[2])
          : '',
      'descripcion_3': _acciones.length > 2
          ? _acciones[2].descripcionCtrl.text
          : '',
      'responsable_3': _acciones.length > 2
          ? _acciones[2].responsableCtrl.text
          : '',
      'fecha_cierre_3':
          (_acciones.length > 2 && _acciones[2].fechaCierre != null)
          ? DateFormat('yyyy-MM-dd').format(_acciones[2].fechaCierre!)
          : null,
      'estado_accion3': _acciones.length > 2 ? _acciones[2].estado : '',

      'accion_4': _acciones.length > 3 ? _acciones[3].tipoAccion : '',
      'actividad_4': _acciones.length > 3
          ? getValorActividad(_acciones[3])
          : '',
      'descripcion_4': _acciones.length > 3
          ? _acciones[3].descripcionCtrl.text
          : '',
      'responsable_4': _acciones.length > 3
          ? _acciones[3].responsableCtrl.text
          : '',
      'fecha_cierre_4':
          (_acciones.length > 3 && _acciones[3].fechaCierre != null)
          ? DateFormat('yyyy-MM-dd').format(_acciones[3].fechaCierre!)
          : null,
      'estado_accion4': _acciones.length > 3 ? _acciones[3].estado : '',

      'cumple_flujo_resolucion': _cumpleFlujo,
      'resolucion_primera_linea': _resolucionPrimeraLinea,
      'secuencia_tiene_sentido': _secuenciaSentido,
      'porques_con_evidencia': _porquesEvidencia,
      'proponen_acciones_eliminacion': _accionesEliminacion,

      'resultado': '',
      'estado': 'PENDIENTE',
    };

    try {
      await ApiService.insertar('gestion', '5why', payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guardado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        _formKey.currentState!.reset();
        setState(() {
          _necesitaInvestigacion = null;
          _causaRaizEncontrada = null;
          _causaRaizCtrl.clear();
          _piSeleccionado = null;
          _interventorSeleccionado = null;
          _supervisorSeleccionado = null; // <-- Limpiar supervisor seleccionado
          _cumpleFlujo = _resolucionPrimeraLinea = _secuenciaSentido = null;
          _porquesEvidencia = _accionesEliminacion = null;
          _evidenciasImagenes.fillRange(0, 5, null);
          _acciones.clear();
          _acciones.addAll([
            AccionItem()..tipoAccion = 'Preventiva',
            AccionItem(),
          ]);
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- WIDGETS REUTILIZABLES ---
  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Colors.black45),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  Widget _seccionTitulo(String titulo, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF1976D2), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0A2540),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _opcionesReticula(
    String texto,
    String? valorActual,
    List<String> opciones,
    Function(String) onSelect,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: opciones.map((opcion) {
                bool isSelected = valorActual == opcion;
                Color activeColor = (opcion == 'SI')
                    ? Colors.green
                    : (opcion == 'NO' ? Colors.redAccent : Colors.orange);

                return GestureDetector(
                  onTap: () => onSelect(opcion),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? activeColor : Colors.white,
                      border: Border.all(
                        color: isSelected ? activeColor : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      opcion,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: widget.onToggleSidebar,
        ),
        title: const Text(
          'Análisis 5 Porqués (VPO)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              onPressed: _isSubmitting ? null : _enviarFormulario,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 20),
              label: const Text(
                'Guardar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildEncabezado(),
            const SizedBox(height: 16),
            _buildInformacionGeneral(),
            const SizedBox(height: 16),
            _buildDisparadorContencion(),
            const SizedBox(height: 16),
            _build5PorquesYAncladoCierre(),
            const SizedBox(height: 16),
            _buildSeccionAccionesResposiva(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'VPO\nSafety First',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: Color(0xFFF59E0B),
                fontSize: 14,
              ),
            ),
            const Expanded(
              child: Text(
                'ANÁLISIS 5 PORQUÉS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: 1.0,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ABInBev',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformacionGeneral() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _seccionTitulo('1. Información General', Icons.feed_rounded),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _seleccionarFechaGeneral,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFFF9FAFB),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fecha del evento',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('yyyy-MM-dd').format(_fecha),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          const Icon(
                            Icons.calendar_month_rounded,
                            size: 22,
                            color: Color(0xFF1976D2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _turno,
                    decoration: _inputDecor('Turno').copyWith(
                      labelText: 'Turno',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    items: ['T1', 'T2', 'T3']
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _turno = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _areaCtrl,
                    decoration: _inputDecor('Ej: Llenado, Bodega').copyWith(
                      labelText: 'Área',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _piSeleccionado,
                    isExpanded: true,
                    icon: _cargandoPI
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.keyboard_arrow_down_rounded),
                    decoration: _inputDecor('Seleccione el PI afectado')
                        .copyWith(
                          labelText: 'PI',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                    items: _listaPI
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _piSeleccionado = val),
                    validator: (val) => val == null ? 'Obligatorio' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _participantesCtrl,
                    decoration: _inputDecor('Ej. Juan Perez...').copyWith(
                      labelText: 'Participantes',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _interventorSeleccionado,
                    isExpanded: true,
                    icon: _cargandoInterventores
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.keyboard_arrow_down_rounded),
                    decoration: _inputDecor('Seleccione interventor').copyWith(
                      labelText: 'Interventor',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    items: _listaInterventores
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _interventorSeleccionado = val),
                    validator: (val) => val == null ? 'Obligatorio' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // <-- CAMBIO AQUI: NUEVA FILA PARA SUPERVISOR
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _supervisorSeleccionado,
                    isExpanded: true,
                    icon: _cargandoSupervisores
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.keyboard_arrow_down_rounded),
                    decoration: _inputDecor('Seleccione supervisor').copyWith(
                      labelText: 'Supervisor',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    items: _listaSupervisores
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _supervisorSeleccionado = val),
                    validator: (val) => val == null ? 'Obligatorio' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const SizedBox(),
                ), // Espacio vacío para mantener el diseño en grid
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisparadorContencion() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _seccionTitulo('2. Disparador y Contención', Icons.warning_rounded),
            TextFormField(
              controller: _valorDisparadorCtrl,
              decoration: _inputDecor('Ingrese el valor medido/alcanzado')
                  .copyWith(
                    labelText: 'Valor del disparador alcanzado',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
            ),
            const SizedBox(height: 20),
            const Text(
              '¿Qué se hizo para contener el problema y lograr reanudar el proceso?',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _accionContencionCtrl,
              maxLines: 3,
              decoration: _inputDecor(
                'Describa detalladamente la acción de contención inmediata...',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build5PorquesYAncladoCierre() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _seccionTitulo(
              '3. Análisis de Causa Raíz (5W)',
              Icons.account_tree_rounded,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Complete al menos los 3 primeros niveles para profundizar en el problema.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
            ...List.generate(5, (index) {
              bool esObligatorio = index < 3;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.blue.shade100),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: esObligatorio
                                ? const Color(0xFF1976D2)
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (index < 4)
                          Container(
                            width: 2,
                            height: 180,
                            color: Colors.grey.shade200,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Por qué',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                  fontSize: 14,
                                ),
                              ),
                              if (esObligatorio)
                                const Text(
                                  ' *',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _porQuesCtrl[index],
                            decoration: _inputDecor(
                              'Escriba la pregunta: ¿Por qué...?',
                            ),
                            validator: (val) {
                              if (esObligatorio &&
                                  (val == null || val.trim().isEmpty))
                                return 'Requerido';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _expliqueCtrl[index],
                            decoration: _inputDecor('Explique el porqué...'),
                            validator: (val) {
                              bool hasWhy = _porQuesCtrl[index].text
                                  .trim()
                                  .isNotEmpty;
                              if ((esObligatorio || hasWhy) &&
                                  (val == null || val.trim().isEmpty))
                                return 'Requerido';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _evidenciasCtrl[index],
                            decoration:
                                _inputDecor(
                                  'Evidencia / Comentarios (Obligatorio si no hay foto)',
                                ).copyWith(
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_evidenciasImagenes[index] != null)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.cancel,
                                            color: Colors.redAccent,
                                            size: 22,
                                          ),
                                          tooltip: 'Eliminar',
                                          onPressed: () =>
                                              _eliminarImagen(index),
                                        ),
                                      IconButton(
                                        icon: Icon(
                                          _evidenciasImagenes[index] != null
                                              ? Icons.image_rounded
                                              : Icons.add_a_photo_rounded,
                                          color:
                                              _evidenciasImagenes[index] != null
                                              ? Colors.green
                                              : Colors.grey.shade500,
                                        ),
                                        tooltip: 'Adjuntar evidencia gráfica',
                                        onPressed: () =>
                                            _seleccionarImagen(index),
                                      ),
                                    ],
                                  ),
                                ),
                            validator: (val) {
                              bool hasWhy = _porQuesCtrl[index].text
                                  .trim()
                                  .isNotEmpty;
                              bool hasText =
                                  val != null && val.trim().isNotEmpty;
                              bool hasImage =
                                  _evidenciasImagenes[index] != null;
                              if ((esObligatorio || hasWhy) &&
                                  !hasText &&
                                  !hasImage)
                                return 'Debe agregar texto o imagen';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: Color(0xFFEA580C),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Conclusión de la Investigación',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _opcionesReticula(
                    '¿Se necesita realizar una investigación adicional?',
                    _necesitaInvestigacion,
                    ['SI', 'NO'],
                    (val) => setState(() => _necesitaInvestigacion = val),
                  ),
                  _opcionesReticula(
                    'Causa raíz encontrada ¿son necesarias más acciones?',
                    _causaRaizEncontrada,
                    ['SI', 'NO'],
                    (val) => setState(() => _causaRaizEncontrada = val),
                  ),
                  if (_causaRaizEncontrada == 'SI') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Descripción de la Causa Raíz',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _causaRaizCtrl,
                      maxLines: 3,
                      decoration: _inputDecor(
                        'Detalle la causa raíz del problema encontrado...',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionAccionesResposiva() {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 800;

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _seccionTitulo(
              '4. Acciones a tomar',
              Icons.assignment_turned_in_rounded,
              trailing: _acciones.length < 4
                  ? TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1976D2),
                        backgroundColor: Colors.blue.shade50,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onPressed: _agregarAccion,
                      icon: const Icon(Icons.add_circle_rounded, size: 18),
                      label: const Text(
                        'Agregar',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )
                  : null,
            ),
            const Text(
              'Defina mínimo 2 y máximo 4 acciones clave. (La primera es "Preventiva" obligatoria)',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (isMobile)
              _buildAccionesVistaMovil()
            else
              _buildAccionesVistaTabla(),
          ],
        ),
      ),
    );
  }

  Widget _buildAccionesVistaTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 900),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: Colors.grey.shade200),
              verticalInside: BorderSide(color: Colors.grey.shade200),
              top: BorderSide(color: Colors.grey.shade300),
              bottom: BorderSide(color: Colors.grey.shade300),
              left: BorderSide(color: Colors.grey.shade300),
              right: BorderSide(color: Colors.grey.shade300),
            ),
            columnWidths: const {
              0: FixedColumnWidth(140),
              1: FixedColumnWidth(150),
              2: FlexColumnWidth(2),
              3: FixedColumnWidth(140),
              4: FixedColumnWidth(120),
              5: FixedColumnWidth(45),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                children: [
                  _celdaTitulo('Acción'),
                  _celdaTitulo('Actividad'),
                  _celdaTitulo('Descripción'),
                  _celdaTitulo('Responsable'),
                  _celdaTitulo('Fecha cierre'),
                  const SizedBox(),
                ],
              ),
              ...List.generate(_acciones.length, (index) {
                final accion = _acciones[index];
                bool esPreventiva = accion.tipoAccion == 'Preventiva';
                bool esCorrectiva = accion.tipoAccion == 'Correctiva';
                bool esPrimeraFilia = index == 0;

                return TableRow(
                  decoration: const BoxDecoration(color: Colors.white),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: DropdownButtonFormField<String>(
                        initialValue: accion.tipoAccion,
                        isExpanded: true,
                        hint: const Text(
                          'Seleccione',
                          style: TextStyle(fontSize: 12),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                        ),
                        items: ['Preventiva', 'Correctiva']
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: esPrimeraFilia
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: esPrimeraFilia
                            ? null
                            : (val) {
                                setState(() {
                                  accion.tipoAccion = val;
                                  if (val == 'Correctiva')
                                    accion.actividadSeleccionada = null;
                                });
                              },
                        disabledHint: Text(
                          accion.tipoAccion ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      color: esCorrectiva
                          ? Colors.grey.shade100
                          : Colors.blue.shade50.withValues(alpha: 0.5),
                      padding: const EdgeInsets.all(8),
                      child: esPreventiva
                          ? DropdownButtonFormField<String>(
                              initialValue: accion.actividadSeleccionada,
                              isExpanded: true,
                              hint: const Text(
                                'Elegir',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black38,
                                ),
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
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
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            e,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) => setState(
                                () => accion.actividadSeleccionada = val,
                              ),
                            )
                          : TextFormField(
                              controller: accion.actividadCtrl,
                              readOnly: true,
                              style: TextStyle(
                                fontSize: 13,
                                color: esCorrectiva
                                    ? Colors.transparent
                                    : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: esCorrectiva
                                    ? 'No aplica'
                                    : 'Seleccione...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black38,
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextFormField(
                        controller: accion.descripcionCtrl,
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Detalle de ejecución',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.black38,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextFormField(
                        controller: accion.responsableCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Nombre Apellido',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.black38,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _seleccionarFechaAccion(index),
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        child: Text(
                          accion.fechaCierre != null
                              ? DateFormat(
                                  'yyyy-MM-dd',
                                ).format(accion.fechaCierre!)
                              : 'Seleccionar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: accion.fechaCierre != null
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF1976D2),
                          ),
                        ),
                      ),
                    ),
                    esPrimeraFilia
                        ? const SizedBox()
                        : IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            tooltip: 'Eliminar acción',
                            onPressed: () => _eliminarAccion(index),
                          ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccionesVistaMovil() {
    return Column(
      children: List.generate(_acciones.length, (index) {
        final accion = _acciones[index];
        bool esPreventiva = accion.tipoAccion == 'Preventiva';
        bool esCorrectiva = accion.tipoAccion == 'Correctiva';
        bool esPrimeraFilia = index == 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    esPrimeraFilia
                        ? 'Acción #1 (Preventiva Obligatoria)'
                        : 'Acción #${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                      fontSize: 14,
                    ),
                  ),
                  if (!esPrimeraFilia && _acciones.length > 2)
                    InkWell(
                      onTap: () => _eliminarAccion(index),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tipo de Acción',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: accion.tipoAccion,
                          isExpanded: true,
                          hint: const Text(
                            'Seleccione',
                            style: TextStyle(fontSize: 12),
                          ),
                          decoration: _inputDecor('').copyWith(
                            fillColor: esPrimeraFilia
                                ? Colors.grey.shade200
                                : Colors.white,
                          ),
                          items: ['Preventiva', 'Correctiva']
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: esPrimeraFilia
                              ? null
                              : (val) {
                                  setState(() {
                                    accion.tipoAccion = val;
                                    if (val == 'Correctiva')
                                      accion.actividadSeleccionada = null;
                                  });
                                },
                          disabledHint: Text(
                            accion.tipoAccion ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Actividad',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        esPreventiva
                            ? DropdownButtonFormField<String>(
                                initialValue: accion.actividadSeleccionada,
                                isExpanded: true,
                                hint: const Text(
                                  'Elegir Actividad',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black38,
                                  ),
                                ),
                                decoration: _inputDecor(''),
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
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(
                                              e,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (val) => setState(
                                  () => accion.actividadSeleccionada = val,
                                ),
                              )
                            : TextFormField(
                                controller: accion.actividadCtrl,
                                readOnly: true,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: esCorrectiva
                                      ? Colors.transparent
                                      : Colors.black87,
                                ),
                                decoration: _inputDecor(
                                  esCorrectiva
                                      ? 'No aplica'
                                      : 'Seleccione Preventiva',
                                ).copyWith(fillColor: Colors.grey.shade200),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fecha de Cierre',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _seleccionarFechaAccion(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                              color: const Color(0xFFF9FAFB),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  accion.fechaCierre != null
                                      ? DateFormat(
                                          'yyyy-MM-dd',
                                        ).format(accion.fechaCierre!)
                                      : 'DD-MM-YYYY',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: accion.fechaCierre != null
                                        ? Colors.black87
                                        : Colors.black38,
                                  ),
                                ),
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 16,
                                  color: Color(0xFF1976D2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              const Text(
                'Descripción',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: accion.descripcionCtrl,
                maxLines: 2,
                minLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: _inputDecor('Detalle la ejecución de la acción...'),
              ),
              const SizedBox(height: 12),

              const Text(
                'Responsable',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: accion.responsableCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: _inputDecor('Nombre y apellido del responsable'),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _celdaTitulo(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Center(
        child: Text(
          texto,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
