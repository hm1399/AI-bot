import 'package:flutter/material.dart';

import '../../models/chat/session_model.dart';
import '../../models/experience/experience_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';
import 'chat_status_strip.dart';

class ExperienceChipBar extends StatefulWidget {
  const ExperienceChipBar({
    required this.state,
    required this.voice,
    required this.activeSession,
    required this.experience,
    required this.catalog,
    required this.onSceneSelected,
    required this.onPersonaSelected,
    this.enabled = true,
    super.key,
  });

  final AppState state;
  final VoiceUiState voice;
  final SessionModel? activeSession;
  final ExperienceSurfaceModel experience;
  final ExperienceCatalogModel catalog;
  final ValueChanged<String> onSceneSelected;
  final ValueChanged<PersonaPresetModel> onPersonaSelected;
  final bool enabled;

  @override
  State<ExperienceChipBar> createState() => _ExperienceChipBarState();
}

class _ExperienceChipBarState extends State<ExperienceChipBar> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final personaPresets = widget.catalog.personaPresets;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LinearSpacing.md),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final stacked = constraints.maxWidth < 860;
            final headerMeta = Wrap(
              spacing: LinearSpacing.xs,
              runSpacing: LinearSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  'Conversation Experience',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                StatusPill(
                  label: _overrideLabel(widget.experience.overrideSource),
                  tone: widget.experience.overrideSource.contains('session')
                      ? StatusPillTone.accent
                      : StatusPillTone.neutral,
                ),
                StatusPill(
                  label: widget.experience.physicalInteraction.readinessLabel,
                  tone: widget.experience.physicalInteraction.ready
                      ? StatusPillTone.success
                      : widget.experience.physicalInteraction.enabled
                      ? StatusPillTone.warning
                      : StatusPillTone.neutral,
                ),
              ],
            );
            final toggleButton = OutlinedButton.icon(
              onPressed: _toggleCollapsed,
              icon: Icon(
                _collapsed
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 18,
              ),
              label: Text(_collapsed ? 'Expand' : 'Collapse'),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (stacked) ...<Widget>[
                  headerMeta,
                  const SizedBox(height: LinearSpacing.sm),
                  Align(alignment: Alignment.centerRight, child: toggleButton),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: headerMeta),
                      const SizedBox(width: LinearSpacing.sm),
                      toggleButton,
                    ],
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: _collapsed
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: LinearSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              ChatStatusStrip(
                                state: widget.state,
                                voice: widget.voice,
                                activeSession: widget.activeSession,
                                embedded: true,
                                voiceActivity: widget.state.voiceActivity,
                              ),
                              const SizedBox(height: LinearSpacing.sm),
                              Text(
                                'Voice stays device-first. Hold-to-talk still routes through the desktop microphone path.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: chrome.textTertiary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Manual conversation override stays here. You can also say or send “切换到会议模式” or “切换人格为温暖陪伴”.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: chrome.textTertiary),
                              ),
                              const SizedBox(height: LinearSpacing.md),
                              _ChipGroup(
                                title: 'Scene',
                                children: widget.catalog.scenes
                                    .map(
                                      (SceneModeModel scene) => ChoiceChip(
                                        label: Text(scene.label),
                                        selected:
                                            widget.experience.scene.id ==
                                            scene.id,
                                        onSelected: widget.enabled
                                            ? (_) => widget.onSceneSelected(
                                                scene.id,
                                              )
                                            : null,
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: LinearSpacing.sm),
                              _ChipGroup(
                                title: 'Persona',
                                children: personaPresets
                                    .map(
                                      (PersonaPresetModel preset) => ChoiceChip(
                                        label: Text(preset.label),
                                        selected:
                                            widget
                                                .experience
                                                .personaPreset
                                                ?.id ==
                                            preset.id,
                                        onSelected: widget.enabled
                                            ? (_) => widget.onPersonaSelected(
                                                preset,
                                              )
                                            : null,
                                      ),
                                    )
                                    .toList(),
                              ),
                              if (widget.experience.personaPreset ==
                                  null) ...<Widget>[
                                const SizedBox(height: LinearSpacing.sm),
                                Text(
                                  'Current persona is using a custom runtime field combination.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: chrome.textTertiary),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _toggleCollapsed() {
    setState(() {
      _collapsed = !_collapsed;
    });
  }

  static String _overrideLabel(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty || normalized == 'default') {
      return 'Default';
    }
    if (normalized.contains('session')) {
      return 'Session Override';
    }
    if (normalized.contains('runtime')) {
      return 'Runtime Override';
    }
    return normalized
        .split(RegExp(r'[_\\-]+'))
        .where((String item) => item.isNotEmpty)
        .map(
          (String item) =>
              '${item.substring(0, 1).toUpperCase()}${item.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: chrome.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: LinearSpacing.xs,
          runSpacing: LinearSpacing.xs,
          children: children,
        ),
      ],
    );
  }
}
