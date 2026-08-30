import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

class ReportesDiariosScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;
  final Map<String, dynamic>? usuario;

  const ReportesDiariosScreen({super.key, this.onToggleSidebar, this.usuario});

  @override
  State<ReportesDiariosScreen> createState() => _ReportesDiariosScreenState();
}

class _ReportesDiariosScreenState extends State<ReportesDiariosScreen> {
  final ScrollController _scrollHorizontal = ScrollController();
  final ScrollController _scrollVerticalNum = ScrollController();
  final ScrollController _scrollVerticalPct = ScrollController();
  final ScrollController _scrollVerticalResumen = ScrollController();

  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todasLasAcciones = [];

  // Filtros
  String _duenoSel = 'Todos';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  List<String> _listaDuenos = ['Todos'];

  // Datos procesados para las tablas
  List<String> _fechasColumnas = [];
  Map<String, Map<String, int>> _matrizDatos = {};

  // Datos para resúmenes superiores
  int _resumenTotalAcciones = 0;
  int _resumenCumplimientoGlobal = 0;
  List<Map<String, dynamic>> _resumenPorPersona = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _scrollHorizontal.dispose();
    _scrollVerticalNum.dispose();
    _scrollVerticalPct.dispose();
    _scrollVerticalResumen.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final datosRaw = await ApiService.consultar('rutina_ol', 'rutina');
      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> duenosSet = {'Todos'};

      for (var fila in datosRaw) {
        if (fila is Map) {
          final Map<String, dynamic> mapa = {};
          fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
          datosProcesados.add(mapa);

          String d = (mapa['dueño']?.toString() ?? mapa['dueno']?.toString() ?? 'SIN ASIGNAR').trim().toUpperCase();
          if (d.isNotEmpty) duenosSet.add(d);
        }
      }

      setState(() {
        _todasLasAcciones = datosProcesados;
        _listaDuenos = duenosSet.toList()..sort();
        _aplicarFiltrosYProcesarMatriz();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando datos: $e');
      setState(() {
        _mensajeError = 'Error conectando al servidor: $e';
        _cargando = false;
      });
    }
  }

  String _extraerFechaCorta(String rawFecha) {
    if (rawFecha.isEmpty || rawFecha.toLowerCase() == 'null') return '-';
    try {
      return rawFecha.split('T')[0];
    } catch (e) {
      return '-';
    }
  }

  // --- LÓGICA DE PORCENTAJES BINARIA (Meta >= 3 = 100%) ---
  // Si en un día realiza 3 o más, es 100%. Si realiza 1 o 2, es 0% de cumplimiento.
  int _calcularPorcentaje(int acciones) {
    if (acciones >= 3) return 100;
    return 0; // Cumplimiento estricto por día
  }

  void _aplicarFiltrosYProcesarMatriz() {
    Set<String> fechasDetectadas = {};
    Map<String, Map<String, int>> matrizTemp = {};

    for (var row in _todasLasAcciones) {
      String dueno = (row['dueño']?.toString() ?? row['dueno']?.toString() ?? 'SIN ASIGNAR').trim().toUpperCase();
      if (dueno.isEmpty) dueno = 'SIN ASIGNAR';

      if (_duenoSel != 'Todos' && dueno != _duenoSel) continue;

      String rawFecha = row['fecha_creacion']?.toString() ?? row['registr']?.toString() ?? row['fecha']?.toString() ?? '';
      String fechaStr = _extraerFechaCorta(rawFecha);

      if (fechaStr != '-') {
        DateTime? fechaFila = DateTime.tryParse(fechaStr);
        if (fechaFila != null) {
          if (_fechaDesde != null && fechaFila.isBefore(_fechaDesde!)) continue;
          if (_fechaHasta != null && fechaFila.isAfter(_fechaHasta!)) continue;
        }

        fechasDetectadas.add(fechaStr);
        matrizTemp.putIfAbsent(dueno, () => {});
        matrizTemp[dueno]![fechaStr] = (matrizTemp[dueno]![fechaStr] ?? 0) + 1;
      }
    }

    List<String> fechasOrdenadas = fechasDetectadas.toList()..sort();
    var matrizOrdenada = Map.fromEntries(
        matrizTemp.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
    );

    int totalAccionesG = 0;
    int sumaPctGlobal = 0;
    int conteoDatosG = 0;
    List<Map<String, dynamic>> resumenPersonas = [];

    for (var entry in matrizOrdenada.entries) {
      String dueno = entry.key;
      int sumaTotalLider = 0;
      int sumaPctLider = 0;

      for (var f in fechasOrdenadas) {
        int valorDia = entry.value[f] ?? 0;
        sumaTotalLider += valorDia;

        int pctDia = _calcularPorcentaje(valorDia);
        sumaPctLider += pctDia;

        totalAccionesG += valorDia;
        sumaPctGlobal += pctDia;
        conteoDatosG++;
      }

      int promLider = fechasOrdenadas.isEmpty ? 0 : (sumaPctLider / fechasOrdenadas.length).round();
      resumenPersonas.add({
        'dueno': dueno,
        'total': sumaTotalLider,
        'cumplimiento': promLider
      });
    }

    int promGlobal = conteoDatosG == 0 ? 0 : (sumaPctGlobal / conteoDatosG).round();

    setState(() {
      _fechasColumnas = fechasOrdenadas;
      _matrizDatos = matrizOrdenada;
      _resumenTotalAcciones = totalAccionesG;
      _resumenCumplimientoGlobal = promGlobal;
      _resumenPorPersona = resumenPersonas;
    });
  }

  // --- EXPORTAR A EXCEL ---
  void _exportarAExcel() {
    if (_fechasColumnas.isEmpty || _matrizDatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ No hay datos para exportar.'), backgroundColor: Colors.orange),
      );
      return;
    }

    StringBuffer sb = StringBuffer();

    // 0. TABLAS DE RESUMEN SUPERIOR
    sb.writeln("RESUMEN GENERAL DE CUMPLIMIENTO");
    sb.writeln("Total Acciones\tCumplimiento General\tDías Evaluados\tLíderes Activos");
    sb.writeln("$_resumenTotalAcciones\t$_resumenCumplimientoGlobal%\t${_fechasColumnas.length}\t${_resumenPorPersona.length}");
    sb.writeln("");

    sb.writeln("RESUMEN DE CUMPLIMIENTO POR PERSONA");
    sb.writeln("Líder / Dueño\tTotal Acciones\tCumplimiento Promedio");
    for (var p in _resumenPorPersona) {
      sb.writeln("${p['dueno']}\t${p['total']}\t${p['cumplimiento']}%");
    }
    sb.writeln("");
    sb.writeln("--------------------------------------------------");
    sb.writeln("");

    // 1. TABLA DE VOLUMEN (NÚMEROS)
    sb.writeln("MATRIZ DE VOLUMEN DIARIO (ACCIONES REPORTADAS)");
    sb.write("Líderes\t");
    for (var f in _fechasColumnas) {
      sb.write("$f\t");
    }
    sb.writeln("Total");

    Map<String, int> totalesColumnaNum = {};
    int granTotalNum = 0;

    for (var entry in _matrizDatos.entries) {
      String dueno = entry.key;
      sb.write("$dueno\t");

      int totalFila = 0;
      for (var f in _fechasColumnas) {
        int valor = entry.value[f] ?? 0;
        sb.write("$valor\t");

        totalFila += valor;
        totalesColumnaNum[f] = (totalesColumnaNum[f] ?? 0) + valor;
      }
      sb.writeln("$totalFila");
      granTotalNum += totalFila;
    }

    sb.write("TOTAL\t");
    for (var f in _fechasColumnas) {
      sb.write("${totalesColumnaNum[f] ?? 0}\t");
    }
    sb.writeln("$granTotalNum");
    sb.writeln("");

    // 2. TABLA DE CUMPLIMIENTO (%)
    sb.writeln("MATRIZ DE CUMPLIMIENTO DIARIO (Meta: >= 3 Acciones = 100%)");
    sb.write("Líderes\t");
    for (var f in _fechasColumnas) {
      sb.write("$f\t");
    }
    sb.writeln("Total Promedio");

    Map<String, int> totalesColumnaPct = {};
    int sumaPromediosLideres = 0;

    for (var entry in _matrizDatos.entries) {
      String dueno = entry.key;
      sb.write("$dueno\t");

      int sumaPctFila = 0;
      for (var f in _fechasColumnas) {
        int pct = _calcularPorcentaje(entry.value[f] ?? 0);
        sb.write("$pct%\t");

        sumaPctFila += pct;
        totalesColumnaPct[f] = (totalesColumnaPct[f] ?? 0) + pct;
      }

      int promLider = _fechasColumnas.isEmpty ? 0 : (sumaPctFila / _fechasColumnas.length).round();
      sb.writeln("$promLider%");
      sumaPromediosLideres += promLider;
    }

    sb.write("TOTAL PROMEDIO\t");
    int cantidadLideres = _matrizDatos.length;
    for (var f in _fechasColumnas) {
      int promDia = cantidadLideres == 0 ? 0 : ((totalesColumnaPct[f] ?? 0) / cantidadLideres).round();
      sb.write("$promDia%\t");
    }

    int granTotalPromedio = cantidadLideres == 0 ? 0 : (sumaPromediosLideres / cantidadLideres).round();
    sb.writeln("$granTotalPromedio%");

    Clipboard.setData(ClipboardData(text: sb.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Reporte completo copiado. ¡Péguelo en Excel!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _limpiarFiltros() {
    setState(() {
      _duenoSel = 'Todos';
      _fechaDesde = null;
      _fechaHasta = null;
      _aplicarFiltrosYProcesarMatriz();
    });
  }

  void _abrirModalBuscador(String titulo, List<String> opciones, String seleccionActual, Function(String) onSelect) {
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
                          return ListTile(
                            dense: true,
                            title: Text(opcion, style: const TextStyle(fontSize: 12)),
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

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))),
      );
    }

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

            if (_fechasColumnas.isNotEmpty) ...[
              // 1. KPI Cards para Resumen General
              _buildKPIsGenerales(),
              const SizedBox(height: 20),

              // 2. Tabla para Resumen por Persona a ancho completo
              _buildTablaResumenPersona(),
              const SizedBox(height: 20),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
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
                          Icon(Icons.grid_on_rounded, color: Color(0xFF0D47A1), size: 18),
                          SizedBox(width: 8),
                          Text('Análisis de Reportes Diarios', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      ),
                      Tooltip(
                        message: 'Descargar reporte completo en Excel',
                        child: InkWell(
                          onTap: _exportarAExcel,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D6F42).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF1D6F42).withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF1D6F42)),
                                SizedBox(width: 6),
                                Text('Exportar a Excel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D6F42))),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (_fechasColumnas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(child: Text('No hay datos registrados en las fechas seleccionadas.', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    Scrollbar(
                      controller: _scrollHorizontal,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollHorizontal,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('MATRIZ DE VOLUMEN (Cantidad de Acciones)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                              const SizedBox(height: 8),
                              _construirTablaSticky(esPorcentaje: false, scrollController: _scrollVerticalNum),

                              const SizedBox(height: 30),

                              const Text('MATRIZ DE CUMPLIMIENTO (Meta: >= 3 acciones = 100%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                              const SizedBox(height: 8),
                              _construirTablaSticky(esPorcentaje: true, scrollController: _scrollVerticalPct),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIsGenerales() {
    return LayoutBuilder(
        builder: (context, constraints) {
          double ancho = constraints.maxWidth > 800
              ? (constraints.maxWidth - 36) / 4
              : (constraints.maxWidth - 12) / 2;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: ancho, child: _buildKPICard('Total Acciones', '$_resumenTotalAcciones', const Color(0xFF43A047), Icons.format_list_bulleted_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('Cumplimiento Global', '$_resumenCumplimientoGlobal%', const Color(0xFF1E88E5), Icons.pie_chart_outline_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('Líderes Activos', '${_resumenPorPersona.length}', const Color(0xFFFFB300), Icons.people_alt_outlined)),
              SizedBox(width: ancho, child: _buildKPICard('Días Evaluados', '${_fechasColumnas.length}', const Color(0xFF8E24AA), Icons.calendar_today_outlined)),
            ],
          );
        }
    );
  }

  Widget _buildKPICard(String titulo, String valor, Color color, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icono, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                Text(
                  titulo,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTablaResumenPersona() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CUMPLIMIENTO PROMEDIO POR PERSONA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: Column(
              children: [
                // HEADER
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                  },
                  border: TableBorder(verticalInside: BorderSide(color: Colors.grey.shade300)),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
                      children: [
                        _celdaHeaderMaestro('Líder / Dueño', alignment: Alignment.centerLeft),
                        _celdaHeaderMaestro('Total Acciones'),
                        _celdaHeaderMaestro('Cumplimiento Promedio'),
                      ],
                    ),
                  ],
                ),
                // BODY (Scrollable)
                Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
                  child: Scrollbar(
                    controller: _scrollVerticalResumen,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollVerticalResumen,
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(1),
                          2: FlexColumnWidth(1),
                        },
                        border: TableBorder(
                          verticalInside: BorderSide(color: Colors.grey.shade200),
                          horizontalInside: BorderSide(color: Colors.grey.shade200),
                        ),
                        children: _resumenPorPersona.map((p) {
                          return TableRow(
                            decoration: const BoxDecoration(color: Colors.white),
                            children: [
                              _celdaTexto(p['dueno'], alignment: Alignment.centerLeft, isBold: true),
                              _celdaNumero(p['total']),
                              _celdaNumero(p['cumplimiento'], esPorcentaje: true),
                            ],
                          );
                        }).toList(),
                      ),
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

  Widget _construirTablaSticky({required bool esPorcentaje, required ScrollController scrollController}) {
    Map<int, TableColumnWidth> colWidths = {
      0: const FixedColumnWidth(200),
    };
    for (int i = 0; i < _fechasColumnas.length; i++) {
      colWidths[i + 1] = const FixedColumnWidth(70);
    }
    colWidths[_fechasColumnas.length + 1] = const FixedColumnWidth(80);

    Map<String, int> totalesColumnas = {};
    int granTotalAcumulado = 0;
    int sumaPromedios = 0;

    List<TableRow> filasCuerpo = _matrizDatos.entries.map((entry) {
      String dueno = entry.key;
      int totalFila = 0;
      int sumaPctFila = 0;

      List<Widget> celdasFila = [
        _celdaTexto(dueno, alignment: Alignment.centerLeft, isBold: true),
      ];

      for (var fecha in _fechasColumnas) {
        int valorRaw = entry.value[fecha] ?? 0;

        if (esPorcentaje) {
          int pct = _calcularPorcentaje(valorRaw);
          sumaPctFila += pct;
          totalesColumnas[fecha] = (totalesColumnas[fecha] ?? 0) + pct;
          celdasFila.add(_celdaNumero(pct, esPorcentaje: true));
        } else {
          totalFila += valorRaw;
          totalesColumnas[fecha] = (totalesColumnas[fecha] ?? 0) + valorRaw;
          celdasFila.add(_celdaNumero(valorRaw));
        }
      }

      if (esPorcentaje) {
        int promLider = _fechasColumnas.isEmpty ? 0 : (sumaPctFila / _fechasColumnas.length).round();
        sumaPromedios += promLider;
        celdasFila.add(_celdaNumero(promLider, isTotal: true, esPorcentaje: true));
      } else {
        granTotalAcumulado += totalFila;
        celdasFila.add(_celdaNumero(totalFila, isTotal: true));
      }

      return TableRow(
        decoration: const BoxDecoration(color: Colors.white),
        children: celdasFila,
      );
    }).toList();

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300, width: 1)),
      child: Column(
        children: [
          Table(
            columnWidths: colWidths,
            border: TableBorder(verticalInside: BorderSide(color: Colors.grey.shade300)),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
                children: [
                  _celdaHeaderMaestro('Líderes', alignment: Alignment.centerLeft),
                  ..._fechasColumnas.map((f) => _celdaHeaderMaestro(_formatearDiaMes(f))),
                  _celdaHeaderMaestro('Total', isTotal: true),
                ],
              ),
            ],
          ),

          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                    bottom: BorderSide(color: Colors.grey.shade300)
                )
            ),
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Table(
                  columnWidths: colWidths,
                  border: TableBorder(
                    verticalInside: BorderSide(color: Colors.grey.shade200),
                    horizontalInside: BorderSide(color: Colors.grey.shade200),
                  ),
                  children: filasCuerpo,
                ),
              ),
            ),
          ),

          Table(
            columnWidths: colWidths,
            border: TableBorder(verticalInside: BorderSide(color: Colors.grey.shade300)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: const Color(0xFF1E88E5).withOpacity(0.05)),
                children: [
                  _celdaTexto(esPorcentaje ? 'PROMEDIO' : 'TOTAL', alignment: Alignment.centerLeft, isBold: true, isTotal: true),
                  ..._fechasColumnas.map((f) {
                    if (esPorcentaje) {
                      int promDia = _matrizDatos.isEmpty ? 0 : ((totalesColumnas[f] ?? 0) / _matrizDatos.length).round();
                      return _celdaNumero(promDia, isTotal: true, esPorcentaje: true);
                    } else {
                      return _celdaNumero(totalesColumnas[f] ?? 0, isTotal: true);
                    }
                  }),
                  _celdaNumero(
                      esPorcentaje
                          ? (_matrizDatos.isEmpty ? 0 : (sumaPromedios / _matrizDatos.length).round())
                          : granTotalAcumulado,
                      isTotal: true,
                      isGranTotal: true,
                      esPorcentaje: esPorcentaje
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  String _formatearDiaMes(String fechaCorta) {
    try {
      List<String> p = fechaCorta.split('-');
      return '${p[2]}/${p[1]}';
    } catch (_) {
      return fechaCorta;
    }
  }

  Widget _celdaHeaderMaestro(String texto, {Alignment alignment = Alignment.center, bool isTotal = false}) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: alignment,
      decoration: isTotal ? BoxDecoration(color: Colors.blueGrey.shade50) : null,
      child: Text(
        texto,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isTotal ? Colors.black87 : const Color(0xFF0D47A1)
        ),
      ),
    );
  }

  Widget _celdaTexto(String texto, {Alignment alignment = Alignment.center, bool isBold = false, bool isTotal = false}) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      alignment: alignment,
      decoration: isTotal ? BoxDecoration(color: const Color(0xFF1E88E5).withOpacity(0.1)) : null,
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isTotal ? const Color(0xFF0D47A1) : Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _celdaNumero(int numero, {bool isTotal = false, bool isGranTotal = false, bool esPorcentaje = false, bool isBold = false}) {
    Color textColor = Colors.black87;
    if (esPorcentaje && !isTotal && !isGranTotal && numero > 0) {
      if (numero >= 100) textColor = Colors.green.shade700;
      else if (numero >= 67) textColor = Colors.orange.shade800;
      else textColor = Colors.red.shade700;
    } else if (numero == 0) {
      textColor = Colors.grey.shade400;
    }

    if (isGranTotal) textColor = const Color(0xFF0D47A1);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: isGranTotal ? const Color(0xFF1E88E5).withOpacity(0.15)
              : isTotal ? Colors.blueGrey.shade50
              : Colors.transparent
      ),
      child: Text(
        esPorcentaje ? '$numero%' : numero.toString(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: (isTotal || isBold || numero > 0) ? FontWeight.bold : FontWeight.normal,
          color: textColor,
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
            if (widget.onToggleSidebar != null)
              IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF0D47A1)),
                onPressed: widget.onToggleSidebar,
              ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MATRIZ DIARIA DE REPORTES',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: 0.5),
                ),
                Text(
                  'Volumen y Cumplimiento generado por Líder / Dueño',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _cargarDatos,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Actualizar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        )
      ],
    );
  }

  Widget _buildBarraFiltros() {
    bool hayFiltrosActivos = _duenoSel != 'Todos' || _fechaDesde != null || _fechaHasta != null;
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
                  Icon(Icons.filter_alt_outlined, size: 18, color: Color(0xFF0D47A1)),
                  SizedBox(width: 8),
                  Text('Filtros de Búsqueda', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _buildFiltroBuscador('Persona que Reporta (Dueño)', _duenoSel, _listaDuenos, (val) => setState(() { _duenoSel = val; _aplicarFiltrosYProcesarMatriz(); })),
              _buildFiltroFecha('Desde (Fecha Creación)', _fechaDesde, (d) => setState(() { _fechaDesde = d; _aplicarFiltrosYProcesarMatriz(); })),
              _buildFiltroFecha('Hasta (Fecha Creación)', _fechaHasta, (d) => setState(() { _fechaHasta = d; _aplicarFiltrosYProcesarMatriz(); })),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroBuscador(String label, String valorActual, List<String> opciones, Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _abrirModalBuscador(label, opciones, valorActual, onSelect),
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(valorActual, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                const Icon(Icons.search, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroFecha(String label, DateTime? fecha, Function(DateTime?) onSelect) {
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
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
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
            onTap: _cargarDatos,
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