import 'package:flutter/material.dart';

class EmptyWorkspace extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? action;
  final VoidCallback? onExample;
  const EmptyWorkspace({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
    this.onExample,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final muted = scheme.onSurfaceVariant;
    final surface = scheme.surface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 20),
      decoration: BoxDecoration(
        border: Border.all(color: muted.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(15),
        color: surface.withValues(alpha: .5),
      ),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 35, color: accent),
          ),
          const SizedBox(height: 25),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted, height: 1.8),
          ),
          const SizedBox(height: 23),
          if (action != null)
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add, size: 17),
              label: const Text(
                'Create your first project',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (onExample != null)
            TextButton(
              onPressed: onExample,
              child: const Text(
                'Explore an example project',
                style: TextStyle(fontSize: 11),
              ),
            ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 25,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _feature(muted, Icons.link, 'Links with context'),
              _feature(muted, Icons.notes, 'Notes worth keeping'),
              _feature(
                muted,
                Icons.notifications_none,
                'A nudge at the right time',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feature(Color muted, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: muted),
      const SizedBox(width: 7),
      Text(text, style: TextStyle(fontSize: 10, color: muted)),
    ],
  );
}
