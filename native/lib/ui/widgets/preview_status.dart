import 'package:flutter/material.dart';

class PreviewStatus extends StatelessWidget {
  final String status;
  final String error;
  final bool compact;
  final VoidCallback? onRetry;
  const PreviewStatus({
    super.key,
    required this.status,
    required this.error,
    this.compact = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final loading = status == 'loading';
    final label = switch (status) {
      'loading' => 'Loading preview…',
      'ready' => 'Preview loaded',
      'no-image' => 'This page has no preview image.',
      'image-unavailable' => 'Page loaded · image unavailable',
      'unavailable' => 'Preview unavailable',
      _ => 'Preview not loaded',
    };
    if (compact && status == 'ready') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  status == 'ready'
                      ? Icons.check_circle_outline
                      : Icons.image_outlined,
                  size: 14,
                  color: muted,
                ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
              if (!loading)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    status == 'ready' ? 'Refresh' : 'Retry',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
          if (!compact && error.isNotEmpty)
            Text(error, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }
}
