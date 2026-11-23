import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

enum AlertTone { error, tertiary }

/// Floating M3 alert card (not a full-width banner). Animates in with the
/// standard fade/size transition from its parent AnimatedSwitcher.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = AlertTone.error,
    this.onTap,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final AlertTone tone;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (bg, fg) = switch (tone) {
      AlertTone.error => (scheme.errorContainer, scheme.onErrorContainer),
      AlertTone.tertiary => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return Semantics(
      liveRegion: true,
      button: onTap != null,
      child: Card(
        margin: EdgeInsets.zero,
        color: bg,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTokens.minTouch + 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: text.titleSmall?.copyWith(color: fg, fontFeatures: tabularFigures),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: text.bodySmall?.copyWith(color: fg, fontFeatures: tabularFigures),
                          ),
                      ],
                    ),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: onDismiss,
                      icon: Icon(Icons.close, color: fg),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
