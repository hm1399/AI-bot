import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '8000',
  );
  final TextEditingController _tokenController = TextEditingController();
  bool _secureConnection = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(appControllerProvider);
      _hostController.text = state.connection.host;
      _portController.text = '${state.connection.port}';
      _tokenController.text = state.connection.token;
      _secureConnection = state.connection.secure;
      if (!state.connection.hasServer && kIsWeb && Uri.base.host.isNotEmpty) {
        _hostController.text = Uri.base.host;
        _secureConnection = Uri.base.scheme == 'https';
      }
      if (state.isConnected) {
        context.go('/app/home');
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _useCurrentPageOrigin() {
    if (!kIsWeb || Uri.base.host.isEmpty) {
      return;
    }
    setState(() {
      _hostController.text = Uri.base.host;
      final port = Uri.base.port;
      if (port > 0) {
        _portController.text = '$port';
      }
      _secureConnection = Uri.base.scheme == 'https';
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppState>(appControllerProvider, (_, AppState next) {
      if (next.isConnected) {
        context.go('/app/home');
      }
    });

    final state = ref.watch(appControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Connect to AI-Bot',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Validate health, fetch bootstrap, then attach to the app event stream.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton.tonalIcon(
                        onPressed: () => ref
                            .read(appControllerProvider.notifier)
                            .connectDemo(),
                        icon: const Icon(Icons.bolt_outlined),
                        label: const Text('Try Demo Mode'),
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Server Host',
                          hintText:
                              '192.168.1.100, localhost, or your deployed host',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'App Token (optional)',
                          helperText: 'Used for both HTTP and WebSocket auth.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _secureConnection,
                        onChanged: (bool value) {
                          setState(() {
                            _secureConnection = value;
                          });
                        },
                        title: const Text('Use HTTPS / WSS'),
                        subtitle: const Text(
                          'Enable this when the backend is exposed over HTTPS.',
                        ),
                      ),
                      if (kIsWeb)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _useCurrentPageOrigin,
                            icon: const Icon(Icons.language),
                            label: const Text('Use Current Page Origin'),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: state.isConnecting
                            ? null
                            : () async {
                                try {
                                  await ref
                                      .read(appControllerProvider.notifier)
                                      .connect(
                                        host: _hostController.text.trim(),
                                        port:
                                            int.tryParse(
                                              _portController.text.trim(),
                                            ) ??
                                            8000,
                                        secure: _secureConnection,
                                        token: _tokenController.text.trim(),
                                      );
                                } catch (_) {}
                              },
                        child: Text(
                          state.isConnecting
                              ? 'Validating connection...'
                              : 'Validate Connection',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: const Color(0xFFF8FAFC),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'LAN scan is intentionally removed. Discovery should come back later as a real mDNS/zeroconf feature.',
                          ),
                        ),
                      ),
                      if (state.globalMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          state.globalMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
