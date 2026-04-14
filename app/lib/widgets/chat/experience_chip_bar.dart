import 'package:flutter/material.dart';

import '../../models/experience/experience_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class ExperienceChipBar extends StatelessWidget {
  const ExperienceChipBar({
    required this.experience,
    required this.catalog,
    required this.onSceneSelected,
    required this.onPersonaSelected,
    this.enabled = true,
    super.key,
  });

  final ExperienceSurfaceModel experience;
  final ExperienceCatalogModel catalog;
  final ValueChanged<String> onSceneSelected;
  final ValueChanged<PersonaPresetModel> onPersonaSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final personaPresets = catalog.personaPresets;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                'Conversation Experience',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              StatusPill(
                label: _overrideLabel(experience.overrideSource),
                tone: experience.overrideSource.contains('session')
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
              ),
              StatusPill(
                label: experience.physicalInteraction.readinessLabel,
                tone: experience.physicalInteraction.ready
                    ? StatusPillTone.success
                    : experience.physicalInteraction.enabled
                    ? StatusPillTone.warning
                    : StatusPillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Voice stays device-first. Hold-to-talk still routes through the desktop microphone path.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            'Manual conversation override stays here. You can also say or send “切换到会议模式” or “切换人格为温暖陪伴”.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          _ChipGroup(
            title: 'Scene',
            children: catalog.scenes
                .map(
                  (SceneModeModel scene) => ChoiceChip(
                    label: Text(scene.label),
                    selected: experience.scene.id == scene.id,
                    onSelected: enabled
                        ? (_) => onSceneSelected(scene.id)
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
                    selected: experience.personaPreset?.id == preset.id,
                    onSelected: enabled
                        ? (_) => onPersonaSelected(preset)
                        : null,
                  ),
                )
                .toList(),
          ),
          if (experience.personaPreset == null) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Text(
              'Current persona is using a custom runtime field combination.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
        ],
      ),
    );
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
