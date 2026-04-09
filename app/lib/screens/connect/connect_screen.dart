import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/common/status_pill.dart';

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
    final chrome = context.linear;

    return Scaffold(
      backgroundColor: chrome.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final wide = constraints.maxWidth >= 1120;
            final intro = _IntroPanel(state: state);
            final form = _ConnectForm(
              state: state,
              hostController: _hostController,
              portController: _portController,
              tokenController: _tokenController,
              secureConnection: _secureConnection,
              onSecureChanged: (bool value) {
                setState(() => _secureConnection = value);
              },
              onUseCurrentOrigin: _useCurrentPageOrigin,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(LinearSpacing.xl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: intro),
                            const SizedBox(width: LinearSpacing.xl),
                            Expanded(child: form),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            intro,
                            const SizedBox(height: LinearSpacing.xl),
                            form,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.xl),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.panel,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const StatusPill(
            label: 'AI Bot Workspace',
            tone: StatusPillTone.accent,
            icon: Icons.radar_outlined,
          ),
          const SizedBox(height: LinearSpacing.lg),
          Text(
            'Connect the operator console.',
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontSize: 38),
          ),
          const SizedBox(height: LinearSpacing.md),
          Text(
            'Validate health, fetch bootstrap, restore the latest app session and attach to the real-time event stream.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: chrome.textSecondary),
          ),
          const SizedBox(height: LinearSpacing.xl),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: state.connection.hasServer
                    ? 'Saved endpoint'
                    : 'No saved endpoint',
                tone: state.connection.hasServer
                    ? StatusPillTone.success
                    : StatusPillTone.neutral,
                icon: Icons.dns_outlined,
              ),
              StatusPill(
                label: state.connection.token.trim().isEmpty
                    ? 'Token optional'
                    : 'Token configured',
                tone: state.connection.token.trim().isEmpty
                    ? StatusPillTone.neutral
                    : StatusPillTone.warning,
                icon: Icons.key_outlined,
              ),
              StatusPill(
                label: state.connection.secure ? 'HTTPS / WSS' : 'HTTP / WS',
                tone: state.connection.secure
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
                icon: Icons.shield_outlined,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.xl),
          _SummaryCard(
            title: 'Previous Connection',
            lines: <String>[
              state.connection.hasServer
                  ? '${state.connection.host}:${state.connection.port}'
                  : 'No endpoint saved yet.',
              state.connection.currentSessionId.isEmpty
                  ? 'No session restored.'
                  : 'Last session: ${state.connection.currentSessionId}',
              state.connection.latestEventId.isEmpty
                  ? 'No event resume cursor stored.'
                  : 'Last event: ${state.connection.latestEventId}',
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          _SummaryCard(
            title: 'Connection Policy',
            lines: const <String>[
              'Demo mode stays isolated from the live backend contract.',
              'LAN scan remains intentionally removed until a real mDNS / zeroconf path is implemented.',
              'Existing features stay in the main shell. This screen is only the entry flow.',
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectForm extends ConsumerWidget {
  const _ConnectForm({
    required this.state,
    required this.hostController,
    required this.portController,
    required this.tokenController,
    required this.secureConnection,
    required this.onSecureChanged,
    required this.onUseCurrentOrigin,
  });

  final AppState state;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController tokenController;
  final bool secureConnection;
  final ValueChanged<bool> onSecureChanged;
  final VoidCallback onUseCurrentOrigin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.xl),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.panel,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Connection Setup',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use the live backend or jump into a local demo shell.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: chrome.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    ref.read(appControllerProvider.notifier).connectDemo(),
                icon: const Icon(Icons.bolt_outlined),
                label: const Text('Try Demo Mode'),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.xl),
          TextField(
            controller: hostController,
            decoration: const InputDecoration(
              labelText: 'Server Host',
              hintText: '192.168.1.100, localhost, or your deployed host',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
              ),
              const SizedBox(width: LinearSpacing.sm),
              Expanded(
                child: TextField(
                  controller: tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'App Token (optional)',
                    helperText: 'Used for both HTTP and WebSocket auth.',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: secureConnection,
            onChanged: onSecureChanged,
            title: const Text('Use HTTPS / WSS'),
            subtitle: const Text(
              'Enable this when the backend is exposed over HTTPS.',
            ),
          ),
          if (kIsWeb)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onUseCurrentOrigin,
                icon: const Icon(Icons.language),
                label: const Text('Use Current Page Origin'),
              ),
            ),
          const SizedBox(height: LinearSpacing.lg),
          FilledButton(
            onPressed: state.isConnecting
                ? null
                : () async {
                    try {
                      await ref
                          .read(appControllerProvider.notifier)
                          .connect(
                            host: hostController.text.trim(),
                            port:
                                int.tryParse(portController.text.trim()) ??
                                8000,
                            secure: secureConnection,
                            token: tokenController.text.trim(),
                          );
                    } catch (_) {}
                  },
            child: Text(
              state.isConnecting
                  ? 'Validating connection...'
                  : 'Validate Connection',
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          Container(
            padding: const EdgeInsets.all(LinearSpacing.md),
            decoration: BoxDecoration(
              color: chrome.panel,
              borderRadius: LinearRadius.card,
              border: Border.all(color: chrome.borderSubtle),
            ),
            child: Text(
              'LAN scan is intentionally removed. Discovery should return only as a real mDNS / zeroconf feature, not as a fake convenience button.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ),
          if (state.globalMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            Text(
              state.globalMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: LinearSpacing.sm),
          ...lines.map(
            (String line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
