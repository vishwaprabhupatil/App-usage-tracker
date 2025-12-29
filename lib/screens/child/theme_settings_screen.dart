import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_controller.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ThemeTile(
              title: 'Follow device theme',
              subtitle: 'System default',
              value: AppThemeMode.system,
              groupValue: theme.mode,
              onChanged: (_) => theme.setSystem(),
            ),
            const SizedBox(height: 12),
            _ThemeTile(
              title: 'Bright & clean',
              subtitle: 'Light mode',
              value: AppThemeMode.light,
              groupValue: theme.mode,
              onChanged: (_) => theme.setLight(),
            ),
            const SizedBox(height: 12),
            _ThemeTile(
              title: 'Pure black',
              subtitle: 'AMOLED · Battery saver',
              value: AppThemeMode.dark,
              groupValue: theme.mode,
              onChanged: (_) => theme.setDark(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Premium-looking custom tile
class _ThemeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final AppThemeMode value;
  final AppThemeMode groupValue;
  final ValueChanged<AppThemeMode?> onChanged;

  const _ThemeTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    final color = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:
              selected ? color.withOpacity(0.12) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Radio<AppThemeMode>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.7),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
