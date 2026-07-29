import 'package:flutter/material.dart';
import 'api_service.dart';

class DashboardOlScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;
  final Map<String, dynamic>? usuario;

  const DashboardOlScreen({super.key, this.onToggleSidebar, this.usuario});

  @override
  State<DashboardOlScreen> createState() => _DashboardOlScreenState();
}

class _DashboardOlScreenState extends State<DashboardOlScreen> {
  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todasLasAcciones = [];

  // Filtros del Dashboard
  String _rutinaSel = 'Todas';
  String _hashtagSel = 'Todos';
  String _duenoSel = 'Todas';
  String _responsableSel = 'Todos';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  List<String> _listaRutinas = ['Todas'];
  List<String> _listaHashtags = ['Todos'];
  List<String> _listaDuenos = ['Todas'];
  List<String> _listaResponsables = ['Todos'];
  List<String> _listaTerritoriosMaestros = [];

  // Métricas Generales Calculadas
  int _totalAcciones = 0;
  int _enProgreso = 0;
  int _retrasadas = 0;
  int _cerradas = 0;
  int _cerradasATiempo = 0; // 🎯 Para el cálculo del % de Cierre Vigente

  // Agrupaciones unificadas para las 4 Tablas
  Map<String, Map<String, int>> _metricasPorResponsable = {};
  Map<String, Map<String, int>> _metricasPorDueno = {};
  Map<String, Map<String, int>> _metricasPorTerritorio = {};
  Map<String, Map<String, int>> _metricasPorHashtag = {};

  @override
  void initState() {
    super.initState();
    _cargarMetricas();
  }

  Future<void> _cargarMetricas() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final datosRaw = await ApiService.consultar('rutina_ol', 'rutina');

      try {
        final listaRutinaBD = await ApiService.consultar('rutina_ol', 'lista_rutina');
        final Set<String> terSet = {};
        for (var item in listaRutinaBD) {
          if (item is Map) {
            String? t = item['territorio']?.toString();
            if (t != null && t.trim().isNotEmpty) {
              terSet.add(t.trim().toUpperCase());
            }
          }
        }
        _listaTerritoriosMaestros = terSet.toList()..sort();
      } catch (e) {
        debugPrint('Error cargando lista_rutina para territorios: $e');
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

        _aplicarFiltrosYCalcularMetricas();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando métricas de Dashboard: $e');
      setState(() {
        _mensajeError = 'Error conectando al servidor: $e';
        _cargando = false;
      });
    }
  }

  void _aplicarFiltrosYCalcularMetricas() {
    final accionesFiltradas = _todasLasAcciones.where((row) {
      if (_rutinaSel != 'Todas' && (row['rutina']?.toString() ?? '') != _rutinaSel) return false;

      String h = row['hashtag']?.toString() ?? row['#hashtag']?.toString() ?? '';
      if (_hashtagSel != 'Todos' && h != _hashtagSel) return false;

      String d = row['dueño']?.toString() ?? row['dueno']?.toString() ?? '';
      if (_duenoSel != 'Todas' && d != _duenoSel) return false;

      String resp = row['responsable']?.toString() ?? '';
      if (_responsableSel != 'Todos' && resp != _responsableSel) return false;

      String? rawFecha = row['fecha_creacion']?.toString() ?? row['registr']?.toString() ?? row['fecha']?.toString();
      if (rawFecha != null && rawFecha.isNotEmpty) {
        DateTime? fechaFila = DateTime.tryParse(rawFecha.split('T')[0]);
        if (fechaFila != null) {
          if (_fechaDesde != null && fechaFila.isBefore(_fechaDesde!)) return false;
          if (_fechaHasta != null && fechaFila.isAfter(_fechaHasta!)) return false;
        }
      }

      return true;
    }).toList();

    int progreso = 0;
    int retrasadas = 0;
    int cerradas = 0;
    int cerradasATiempo = 0;

    Map<String, int> crearEstructuraVacia() => {
      'reportados': 0,
      'vigentes': 0,
      'vencidas': 0,
      'cerradas_vencidas': 0,
      'a_tiempo': 0,
      'total_cerradas': 0,
    };

    final Map<String, Map<String, int>> terMap = {};
    for (var terMaestro in _listaTerritoriosMaestros) {
      terMap[terMaestro] = crearEstructuraVacia();
    }

    final Map<String, Map<String, int>> respMap = {};
    final Map<String, Map<String, int>> duenoMap = {};
    final Map<String, Map<String, int>> hashtagMap = {};

    DateTime hoySinHora = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    for (var mapa in accionesFiltradas) {
      String estado = _determinarEstado(mapa);
      String territorio = (mapa['territorio']?.toString() ?? '').trim().toUpperCase();
      String dueno = (mapa['dueño']?.toString() ?? mapa['dueno']?.toString() ?? 'SIN ASIGNAR').trim().toUpperCase();
      String resp = (mapa['responsable']?.toString() ?? 'SIN ASIGNAR').trim().toUpperCase();
      String hashtag = (mapa['hashtag']?.toString() ?? mapa['#hashtag']?.toString() ?? '#GENERAL').trim();

      if (dueno.isEmpty) dueno = 'SIN ASIGNAR';
      if (resp.isEmpty) resp = 'SIN ASIGNAR';
      if (hashtag.isEmpty) hashtag = '#GENERAL';

      String? rawCompromiso = mapa['compromiso']?.toString() ?? mapa['fecha_compromiso']?.toString();
      String? rawCierre = mapa['fecha_cierre']?.toString() ?? mapa['cierre']?.toString();

      DateTime? fechaComp = rawCompromiso != null && rawCompromiso.isNotEmpty ? DateTime.tryParse(rawCompromiso.split('T')[0]) : null;
      DateTime? fechaCierre = rawCierre != null && rawCierre.isNotEmpty && rawCierre.toLowerCase() != 'null' && rawCierre.toLowerCase() != 'pendiente'
          ? DateTime.tryParse(rawCierre.split('T')[0])
          : null;

      bool esCerrada = estado == 'CERRADAS';
      bool esVencidaEnCierre = esCerrada && fechaComp != null && fechaCierre != null && fechaCierre.isAfter(fechaComp);
      bool esVencidaEnAbierta = !esCerrada && fechaComp != null && hoySinHora.isAfter(fechaComp);

      if (esCerrada) {
        cerradas++;
        if (!esVencidaEnCierre) {
          cerradasATiempo++;
        }
      } else if (estado == 'RETRASADAS' || esVencidaEnAbierta) {
        retrasadas++;
      } else {
        progreso++;
      }

      void acumularEnMapa(Map<String, Map<String, int>> mapaTarget, String clave) {
        mapaTarget.putIfAbsent(clave, () => crearEstructuraVacia());
        mapaTarget[clave]!['reportados'] = mapaTarget[clave]!['reportados']! + 1;

        if (esCerrada) {
          mapaTarget[clave]!['total_cerradas'] = mapaTarget[clave]!['total_cerradas']! + 1;
          if (esVencidaEnCierre) {
            mapaTarget[clave]!['cerradas_vencidas'] = mapaTarget[clave]!['cerradas_vencidas']! + 1;
          } else {
            mapaTarget[clave]!['a_tiempo'] = mapaTarget[clave]!['a_tiempo']! + 1;
          }
        } else {
          if (esVencidaEnAbierta) {
            mapaTarget[clave]!['vencidas'] = mapaTarget[clave]!['vencidas']! + 1;
          } else {
            mapaTarget[clave]!['vigentes'] = mapaTarget[clave]!['vigentes']! + 1;
          }
        }
      }

      if (terMap.containsKey(territorio)) {
        acumularEnMapa(terMap, territorio);
      }
      acumularEnMapa(respMap, resp);
      acumularEnMapa(duenoMap, dueno);
      acumularEnMapa(hashtagMap, hashtag);
    }

    setState(() {
      _totalAcciones = accionesFiltradas.length;
      _enProgreso = progreso;
      _retrasadas = retrasadas;
      _cerradas = cerradas;
      _cerradasATiempo = cerradasATiempo;

      _metricasPorTerritorio = terMap;
      _metricasPorResponsable = respMap;
      _metricasPorDueno = duenoMap;
      _metricasPorHashtag = hashtagMap;
    });
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

  void _limpiarFiltros() {
    setState(() {
      _rutinaSel = 'Todas';
      _hashtagSel = 'Todos';
      _duenoSel = 'Todas';
      _responsableSel = 'Todos';
      _fechaDesde = null;
      _fechaHasta = null;
      _aplicarFiltrosYCalcularMetricas();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))),
      );
    }

    final listaResponsables = _metricasPorResponsable.entries.toList()
      ..sort((a, b) => (b.value['reportados'] ?? 0).compareTo(a.value['reportados'] ?? 0));

    final listaDuenos = _metricasPorDueno.entries.toList()
      ..sort((a, b) => (b.value['reportados'] ?? 0).compareTo(a.value['reportados'] ?? 0));

    final listaTerritorios = _metricasPorTerritorio.entries.toList()
      ..sort((a, b) => (b.value['reportados'] ?? 0).compareTo(a.value['reportados'] ?? 0));

    final listaHashtags = _metricasPorHashtag.entries.toList()
      ..sort((a, b) => (b.value['reportados'] ?? 0).compareTo(a.value['reportados'] ?? 0));

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

            // 🎯 6 TARJETAS KPIS DISTRIBUIDAS PROPORCIONALMENTE AL 100%
            _buildSeccionKPIsEficacia(),
            const SizedBox(height: 24),

            // 📊 GRILLA SIMÉTRICA DE 4 TABLAS
            LayoutBuilder(
              builder: (context, constraints) {
                bool esAncho = constraints.maxWidth > 900;
                return esAncho
                    ? Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTablaStandard(
                            titulo: 'Rendimiento por Responsable',
                            icono: Icons.people_alt_outlined,
                            columnaNombre: 'Responsable',
                            datosMap: listaResponsables,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildTablaStandard(
                            titulo: 'Acciones por Territorio (Maestro)',
                            icono: Icons.location_on_outlined,
                            columnaNombre: 'Territorio',
                            datosMap: listaTerritorios,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTablaStandard(
                            titulo: 'Cumplimiento por Dueño',
                            icono: Icons.assignment_ind_rounded,
                            columnaNombre: 'Dueño',
                            datosMap: listaDuenos,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildTablaStandard(
                            titulo: 'Acciones por #Hashtag',
                            icono: Icons.tag_rounded,
                            columnaNombre: '#Hashtag',
                            datosMap: listaHashtags,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
                    : Column(
                  children: [
                    _buildTablaStandard(
                      titulo: 'Rendimiento por Responsable',
                      icono: Icons.people_alt_outlined,
                      columnaNombre: 'Responsable',
                      datosMap: listaResponsables,
                    ),
                    const SizedBox(height: 20),
                    _buildTablaStandard(
                      titulo: 'Acciones por Territorio (Maestro)',
                      icono: Icons.location_on_outlined,
                      columnaNombre: 'Territorio',
                      datosMap: listaTerritorios,
                    ),
                    const SizedBox(height: 20),
                    _buildTablaStandard(
                      titulo: 'Cumplimiento por Dueño',
                      icono: Icons.assignment_ind_rounded,
                      columnaNombre: 'Dueño',
                      datosMap: listaDuenos,
                    ),
                    const SizedBox(height: 20),
                    _buildTablaStandard(
                      titulo: 'Acciones por #Hashtag',
                      icono: Icons.tag_rounded,
                      columnaNombre: '#Hashtag',
                      datosMap: listaHashtags,
                    ),
                  ],
                );
              },
            ),
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
            if (widget.onToggleSidebar != null)
              IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF0D47A1)),
                onPressed: widget.onToggleSidebar,
              ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DASHBOARD DE GESTIÓN',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: 0.5),
                ),
                Text(
                  'Métricas en Tiempo Real • Baúl de Acciones OL',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _cargarMetricas,
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
    bool hayFiltrosActivos = _rutinaSel != 'Todas' ||
        _hashtagSel != 'Todos' ||
        _duenoSel != 'Todas' ||
        _responsableSel != 'Todos' ||
        _fechaDesde != null ||
        _fechaHasta != null;

    return Container(
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
                  Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF0D47A1)),
                  SizedBox(width: 8),
                  Text('Filtros del Dashboard', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
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
              _buildSelectorBuscadorFiltro('Rutina', _rutinaSel, _listaRutinas, (val) => setState(() { _rutinaSel = val; _aplicarFiltrosYCalcularMetricas(); })),
              _buildSelectorBuscadorFiltro('#Hashtag', _hashtagSel, _listaHashtags, (val) => setState(() { _hashtagSel = val; _aplicarFiltrosYCalcularMetricas(); })),
              _buildSelectorBuscadorFiltro('Dueño', _duenoSel, _listaDuenos, (val) => setState(() { _duenoSel = val; _aplicarFiltrosYCalcularMetricas(); })),
              _buildSelectorBuscadorFiltro('Responsable', _responsableSel, _listaResponsables, (val) => setState(() { _responsableSel = val; _aplicarFiltrosYCalcularMetricas(); })),
              _buildSelectorFechaFiltro('Desde', _fechaDesde, (d) => setState(() { _fechaDesde = d; _aplicarFiltrosYCalcularMetricas(); })),
              _buildSelectorFechaFiltro('Hasta', _fechaHasta, (d) => setState(() { _fechaHasta = d; _aplicarFiltrosYCalcularMetricas(); })),
            ],
          ),
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
            width: 150,
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
            width: 125,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
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

  // 🎯 6 TARJETAS KPIS CON DISTRIBUCIÓN RESPONSIVA SIMÉTRICA
  Widget _buildSeccionKPIsEficacia() {
    double pctCierreTotal = _totalAcciones > 0 ? (_cerradas / _totalAcciones) * 100 : 0.0;
    double pctCierreVigente = _cerradas > 0 ? (_cerradasATiempo / _cerradas) * 100 : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        bool esPantallaGrande = constraints.maxWidth > 1050;
        bool esPantallaMediana = constraints.maxWidth > 650 && constraints.maxWidth <= 1050;

        if (esPantallaGrande) {
          return Row(
            children: [
              Expanded(child: _buildKPICard('Total Acciones', '$_totalAcciones', const Color(0xFF43A047), Icons.format_list_bulleted_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('En Progreso', '$_enProgreso', const Color(0xFFFFB300), Icons.pending_actions_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('Retrasadas', '$_retrasadas', const Color(0xFFE53935), Icons.warning_amber_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('Cerradas', '$_cerradas', const Color(0xFF1E88E5), Icons.check_circle_outline_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('% Cierre Total', '${pctCierreTotal.toStringAsFixed(1)}%', const Color(0xFF0D47A1), Icons.pie_chart_outline_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('% Cierre Vigente', '${pctCierreVigente.toStringAsFixed(1)}%', const Color(0xFF00897B), Icons.verified_outlined)),
            ],
          );
        } else if (esPantallaMediana) {
          double ancho = (constraints.maxWidth - 24) / 3;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: ancho, child: _buildKPICard('Total Acciones', '$_totalAcciones', const Color(0xFF43A047), Icons.format_list_bulleted_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('En Progreso', '$_enProgreso', const Color(0xFFFFB300), Icons.pending_actions_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('Retrasadas', '$_retrasadas', const Color(0xFFE53935), Icons.warning_amber_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('Cerradas', '$_cerradas', const Color(0xFF1E88E5), Icons.check_circle_outline_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('% Cierre Total', '${pctCierreTotal.toStringAsFixed(1)}%', const Color(0xFF0D47A1), Icons.pie_chart_outline_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('% Cierre Vigente', '${pctCierreVigente.toStringAsFixed(1)}%', const Color(0xFF00897B), Icons.verified_outlined)),
            ],
          );
        } else {
          double ancho = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: ancho, child: _buildKPICard('Total Acciones', '$_totalAcciones', const Color(0xFF43A047), Icons.format_list_bulleted_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('En Progreso', '$_enProgreso', const Color(0xFFFFB300), Icons.pending_actions_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('Retrasadas', '$_retrasadas', const Color(0xFFE53935), Icons.warning_amber_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('Cerradas', '$_cerradas', const Color(0xFF1E88E5), Icons.check_circle_outline_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('% Cierre Total', '${pctCierreTotal.toStringAsFixed(1)}%', const Color(0xFF0D47A1), Icons.pie_chart_outline_rounded)),
              SizedBox(width: ancho, child: _buildKPICard('% Cierre Vigente', '${pctCierreVigente.toStringAsFixed(1)}%', const Color(0xFF00897B), Icons.verified_outlined)),
            ],
          );
        }
      },
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
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
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

  // 📊 TABLA ESTÁNDAR PARA LAS 4 SECCIONES
  Widget _buildTablaStandard({
    required String titulo,
    required IconData icono,
    required String columnaNombre,
    required List<MapEntry<String, Map<String, int>>> datosMap,
  }) {
    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: const Color(0xFF0D47A1), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: datosMap.isEmpty
                ? const Center(
              child: Text('Sin registros disponibles', style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
                : Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    border: TableBorder.all(color: Colors.grey.shade200, width: 1),
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF8F9FA)),
                        children: [
                          _headerCellTabla(columnaNombre),
                          _headerCellTabla('Reportados'),
                          _headerCellTabla('Vigentes'),
                          _headerCellTabla('Vencidas'),
                          _headerCellTabla('Cerradas Vencidas'),
                          _headerCellTabla('% Cierre Acciones'),
                          _headerCellTabla('% Cierre Vigentes'),
                        ],
                      ),
                      ...datosMap.map((item) {
                        String nombre = item.key;
                        int reportados = item.value['reportados'] ?? 0;
                        int vigentes = item.value['vigentes'] ?? 0;
                        int vencidas = item.value['vencidas'] ?? 0;
                        int cerradasVencidas = item.value['cerradas_vencidas'] ?? 0;
                        int aTiempo = item.value['a_tiempo'] ?? 0;
                        int totalCerradas = item.value['total_cerradas'] ?? 0;

                        double pctCierreTotal = reportados > 0 ? (totalCerradas / reportados) * 100 : 0.0;
                        double pctCierreVigentes = totalCerradas > 0 ? (aTiempo / totalCerradas) * 100 : 0.0;

                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Text(nombre, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('$reportados', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('$vigentes', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('$vencidas', style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('$cerradasVencidas', style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('${pctCierreTotal.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)), textAlign: TextAlign.center),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('${pctCierreVigentes.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pctCierreVigentes >= 80 ? Colors.green : Colors.orange.shade800), textAlign: TextAlign.center),
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
        ],
      ),
    );
  }

  Widget _headerCellTabla(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
        textAlign: TextAlign.center,
      ),
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
            onTap: _cargarMetricas,
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