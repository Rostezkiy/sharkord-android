import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';

/// the entry point of the app: the address of the server, then the credentials
/// for it. the address is always editable, both here and from the server menu
/// once joined.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _server = TextEditingController(
    text: widget.controller.endpoint?.httpBase ?? '',
  );
  late final TextEditingController _identity = TextEditingController(
    text: widget.controller.preferences.identity ?? '',
  );
  final TextEditingController _password = TextEditingController();
  final TextEditingController _serverPassword = TextEditingController();

  bool _obscurePassword = true;
  bool _resolving = false;

  @override
  void dispose() {
    _server.dispose();
    _identity.dispose();
    _password.dispose();
    _serverPassword.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final info = controller.serverInfo;
    final busy = controller.isBusy || _resolving;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _brand(),
                  const SizedBox(height: 28),
                  if (info == null)
                    _addressStep(controller, busy)
                  else
                    _credentialsStep(controller, busy),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _error(controller),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            borderRadius: AppRadius.large,
          ),
          child: const Icon(Icons.waves_rounded, size: 28, color: Colors.white),
        ),
        const SizedBox(height: 14),
        const Text(
          'Sharkord',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sign in to your server',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _addressStep(SessionController controller, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _server,
          autocorrect: false,
          enabled: !busy,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _resolve(controller),
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'https://chat.example.com or 192.168.1.10:4991',
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: busy ? null : () => _resolve(controller),
          child: busy
              ? const _ButtonSpinner('Connecting')
              : const Text('Continue'),
        ),
      ],
    );
  }

  Widget _credentialsStep(SessionController controller, bool busy) {
    final info = controller.serverInfo!;
    final needsServerPassword = controller.serverNeedsPassword;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _serverCard(controller, info.name, info.description),
        const SizedBox(height: 20),
        TextField(
          controller: _identity,
          autocorrect: false,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Identity'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscurePassword,
          enabled: !busy,
          onSubmitted: (_) => _signIn(controller),
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
            ),
          ),
        ),
        if (needsServerPassword) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _serverPassword,
            obscureText: true,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Server password',
              helperText:
                  'This server asks for its own password before joining',
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : () => _signIn(controller),
          child: busy
              ? _ButtonSpinner(controller.statusMessage ?? 'Signing in')
              : const Text('Sign in'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : () => _forgetServer(controller),
          child: const Text('Use a different server'),
        ),
      ],
    );
  }

  Widget _serverCard(
    SessionController controller,
    String name,
    String? description,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.large,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.surfaceHigher,
              borderRadius: AppRadius.medium,
            ),
            child: Text(
              name.isEmpty ? 'S' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description == null || description.isEmpty
                      ? (controller.endpoint?.host ?? '')
                      : description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(SessionController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: AppRadius.medium,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              controller.errorMessage!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(SessionController controller) async {
    final address = _server.text.trim();
    if (address.isEmpty) return;

    setState(() => _resolving = true);
    controller.clearError();

    try {
      await controller.refreshServerInfo(address);
    } on ApiException catch (error) {
      _showError(controller, error.message);
    } on RestException catch (error) {
      _showError(controller, error.message);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _signIn(SessionController controller) async {
    final identity = _identity.text.trim();
    final password = _password.text;

    if (identity.isEmpty || password.isEmpty) {
      _showError(controller, 'Enter your identity and password');

      return;
    }

    if (controller.serverNeedsPassword && _serverPassword.text.isNotEmpty) {
      await controller.retryWithPassword(password: _serverPassword.text);

      return;
    }

    await controller.signIn(
      serverUrl: controller.endpoint?.httpBase ?? _server.text.trim(),
      identity: identity,
      password: password,
    );
  }

  Future<void> _forgetServer(SessionController controller) async {
    controller.clearError();
    await controller.signOut(forget: true);

    if (mounted) _server.clear();
  }

  void _showError(SessionController controller, String message) {
    controller.setTransientError(message);
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
