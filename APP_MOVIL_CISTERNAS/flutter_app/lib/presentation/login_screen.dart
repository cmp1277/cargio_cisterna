import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _obscure = true;
  String? _connectionMessage;

  @override
  void initState() {
    super.initState();
    _username.text = widget.controller.rememberedUsername;
    _remember = _username.text.isNotEmpty;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (widget.controller.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _connectionMessage = null);
    await widget.controller.login(
      _username.text.trim(),
      _password.text,
      remember: _remember,
    );
    if (mounted && widget.controller.session != null) {
      TextInput.finishAutofillContext();
      _password.clear();
    }
  }

  Future<void> _testConnection() async {
    setState(() => _connectionMessage = null);
    final message = await widget.controller.testConnection();
    if (mounted) setState(() => _connectionMessage = message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(width: 152),
                ),
                const SizedBox(height: 32),
                const Text(
                  'CONTROL DE CARGUÍO',
                  style: TextStyle(
                    color: AppColors.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cada carga,\nbien registrada.',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Ingresa a tu cuenta para registrar el suministro de agua a cisternas.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: AutofillGroup(
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Iniciar sesión',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _username,
                            enabled: !widget.controller.busy,
                            autofillHints: const [AutofillHints.username],
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Usuario',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Ingresa tu usuario.'
                                : null,
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _password,
                            enabled: !widget.controller.busy,
                            autofillHints: const [AutofillHints.password],
                            autocorrect: false,
                            enableSuggestions: false,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Ingresa tu contraseña.'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Recordar usuario'),
                              value: _remember,
                              onChanged: widget.controller.busy
                                  ? null
                                  : (value) => setState(
                                      () => _remember = value ?? false,
                                    ),
                            ),
                          ),
                          if (widget.controller.error != null) ...[
                            MessageBanner(message: widget.controller.error!),
                            const SizedBox(height: 18),
                          ],
                          if (_connectionMessage != null) ...[
                            MessageBanner(
                              message: _connectionMessage!,
                              success: true,
                            ),
                            const SizedBox(height: 18),
                          ],
                          FilledButton.icon(
                            onPressed: widget.controller.busy ? null : _login,
                            icon: widget.controller.busy
                                ? const BusyIndicator()
                                : const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              widget.controller.busy
                                  ? 'Conectando…'
                                  : 'Ingresar',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: widget.controller.busy
                                ? null
                                : _testConnection,
                            icon: const Icon(Icons.wifi_tethering, size: 18),
                            label: const Text('Comprobar conexión'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SCPE · Registro de cisternas\nRequiere conexión a internet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
