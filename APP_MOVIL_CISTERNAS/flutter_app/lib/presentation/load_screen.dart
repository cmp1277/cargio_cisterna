import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../domain/water_load.dart';
import 'theme.dart';
import 'widgets.dart';

class LoadScreen extends StatefulWidget {
  const LoadScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<LoadScreen> createState() => _LoadScreenState();
}

class _LoadScreenState extends State<LoadScreen> {
  var _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _driver = TextEditingController();
  final _plate = TextEditingController();
  final _initial = TextEditingController();
  final _final = TextEditingController();
  final _company = TextEditingController();
  final _notes = TextEditingController();
  String? _companyType;
  String? _ebap;
  String? _success;
  String? _validationError;
  bool _dirty = false;
  int _formRevision = 0;

  @override
  void dispose() {
    _scroll.dispose();
    for (final field in [_driver, _plate, _initial, _final, _company, _notes]) {
      field.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Completa este campo.' : null;

  String? _readingError(String? value) => parseReading(value ?? '') == null
      ? 'Ingresa un número mayor o igual a 0, con hasta 2 decimales.'
      : null;

  void _changed() {
    setState(() {
      _dirty = true;
      _success = null;
      _validationError = null;
    });
  }

  Future<void> _save() async {
    if (widget.controller.saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final load = WaterLoad(
      driverName: _driver.text,
      plateNumber: _plate.text,
      initialReading: parseReading(_initial.text)!,
      finalReading: parseReading(_final.text)!,
      companyType: _companyType!,
      companyName: _company.text,
      characteristics: _notes.text,
      ebap: _ebap!,
    );
    final validation = load.validate();
    setState(() {
      _validationError = validation;
      _success = null;
    });
    if (validation != null) return;
    final id = await widget.controller.submit(load);
    if (!mounted || id == null) return;
    for (final field in [_driver, _plate, _initial, _final, _company, _notes]) {
      field.clear();
    }
    setState(() {
      _form = GlobalKey<FormState>();
      _companyType = null;
      _ebap = null;
      _dirty = false;
      _formRevision++;
      _success = 'Registro guardado correctamente. N.º $id';
    });
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _logout() async {
    if (widget.controller.saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Cerrar sesión'),
        content: Text(
          _dirty
              ? 'Hay datos sin guardar. Si sales, se descartarán.'
              : '¿Deseas cerrar tu sesión?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.controller.logout();
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    int lines = 1,
    bool numeric = false,
  }) => TextFormField(
    controller: controller,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    enabled: !widget.controller.saving,
    maxLines: lines,
    textCapitalization: numeric
        ? TextCapitalization.none
        : TextCapitalization.characters,
    autocorrect: false,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : (lines > 1 ? TextInputType.multiline : TextInputType.text),
    textInputAction: lines > 1 ? TextInputAction.newline : TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: numeric ? 'm³' : null,
    ),
    validator: validator ?? _required,
    onChanged: (_) => _changed(),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.session!;
    final remaining = widget.controller.remainingSessionTime;
    final countdown =
        '${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    final first = parseReading(_initial.text);
    final last = parseReading(_final.text);
    final validVolume = first != null && last != null && last > first;
    final volume = validVolume
        ? ((last - first) / 100).toStringAsFixed(2)
        : '—';
    return PopScope(
      canPop: !_dirty && !widget.controller.saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !widget.controller.saving) _logout();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Cisternas',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.controller.saving ? null : _logout,
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.navy, Color(0xFF075D70)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'REGISTRO DE AGUA · SCPE',
                            style: TextStyle(
                              color: Color(0xFF90E4E3),
                              letterSpacing: 1.3,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Nuevo carguío',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Completa los datos de la cisterna y las lecturas del medidor.',
                            style: TextStyle(
                              color: Color(0xFFD6EAF0),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 16,
                            runSpacing: 10,
                            children: [
                              Text(
                                '${session.username} · ${session.role}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Semantics(
                                label:
                                    'Tiempo de sesión restante: ${remaining.inMinutes} minutos',
                                excludeSemantics: true,
                                child: Text(
                                  'Sesión $countdown',
                                  style: TextStyle(
                                    color: remaining.inMinutes < 5
                                        ? const Color(0xFFFFD39C)
                                        : const Color(0xFF90E4E3),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (_success != null) ...[
                      MessageBanner(message: _success!, success: true),
                      const SizedBox(height: 18),
                    ],
                    Form(
                      key: _form,
                      autovalidateMode: AutovalidateMode.disabled,
                      child: Column(
                        children: [
                          SectionCard(
                            title: 'Cisterna y conductor',
                            subtitle: 'Identificación del servicio',
                            icon: Icons.local_shipping_outlined,
                            child: FieldPair(
                              first: _textField(
                                controller: _driver,
                                label: 'Nombre del conductor',
                              ),
                              second: _textField(
                                controller: _plate,
                                label: 'Placa',
                                hint: '2127 - ACC',
                                validator: (value) =>
                                    RegExp(
                                      r'^\d{4} - [A-Z]{3}$',
                                    ).hasMatch(normalizePlate(value ?? ''))
                                    ? null
                                    : 'Usa 4 números y 3 letras: 2127 - ACC.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SectionCard(
                            title: 'Lecturas del medidor',
                            subtitle: 'El volumen se calcula automáticamente',
                            icon: Icons.water_drop_outlined,
                            child: Column(
                              children: [
                                FieldPair(
                                  first: _textField(
                                    controller: _initial,
                                    label: 'Lectura inicial',
                                    numeric: true,
                                    validator: _readingError,
                                  ),
                                  second: _textField(
                                    controller: _final,
                                    label: 'Lectura final',
                                    numeric: true,
                                    validator: (value) {
                                      final error = _readingError(value);
                                      if (error != null) return error;
                                      final start = parseReading(_initial.text);
                                      return start != null &&
                                              parseReading(value!)! <= start
                                          ? 'Debe ser mayor que la lectura inicial.'
                                          : null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE9F5F5),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'VOLUMEN DE LA CARGA',
                                        style: TextStyle(
                                          color: AppColors.teal,
                                          fontSize: 11,
                                          letterSpacing: 1.1,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$volume m³',
                                        style: const TextStyle(
                                          color: AppColors.navy,
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          SectionCard(
                            title: 'Destino del agua',
                            subtitle: 'Entidad beneficiaria y punto de carga',
                            icon: Icons.business_outlined,
                            child: Column(
                              children: [
                                FieldPair(
                                  first: DropdownButtonFormField<String>(
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    key: ValueKey('company-$_formRevision'),
                                    initialValue: _companyType,
                                    isExpanded: true,
                                    itemHeight: null,
                                    selectedItemBuilder: (context) =>
                                        companyTypes
                                            .map(
                                              (value) => Text(
                                                value,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            )
                                            .toList(),
                                    decoration: const InputDecoration(
                                      labelText: 'Tipo de empresa',
                                    ),
                                    items: companyTypes
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              child: Text(value),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: widget.controller.saving
                                        ? null
                                        : (value) {
                                            _companyType = value;
                                            _changed();
                                          },
                                    validator: _required,
                                  ),
                                  second: DropdownButtonFormField<String>(
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    key: ValueKey('ebap-$_formRevision'),
                                    initialValue: _ebap,
                                    isExpanded: true,
                                    itemHeight: null,
                                    selectedItemBuilder: (context) =>
                                        ebapOptions
                                            .map(
                                              (value) => Text(
                                                value,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            )
                                            .toList(),
                                    decoration: const InputDecoration(
                                      labelText: 'EBAP',
                                    ),
                                    items: ebapOptions
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              child: Text(value),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: widget.controller.saving
                                        ? null
                                        : (value) {
                                            _ebap = value;
                                            _changed();
                                          },
                                    validator: _required,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _textField(
                                  controller: _company,
                                  label: 'Empresa / entidad',
                                  hint: 'Nombre de la empresa o entidad',
                                ),
                                const SizedBox(height: 18),
                                _textField(
                                  controller: _notes,
                                  label: 'Observaciones (opcional)',
                                  lines: 3,
                                  validator: (_) => null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (_validationError ?? widget.controller.error
                        case final String message) ...[
                      MessageBanner(message: message),
                      const SizedBox(height: 18),
                    ],
                    FilledButton.icon(
                      onPressed:
                          widget.controller.saving || widget.controller.busy
                          ? null
                          : _save,
                      icon: widget.controller.saving
                          ? const BusyIndicator()
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        widget.controller.saving
                            ? 'Guardando registro…'
                            : 'Guardar registro',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Los registros se guardan en la base central.\nVerifica los datos antes de enviarlos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
