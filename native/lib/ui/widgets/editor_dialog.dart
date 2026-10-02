import 'package:flutter/material.dart';

/// Keeps editor controllers alive through the dialog's closing animation.
/// A popped route can still build until [DialogRoute.completed] resolves.
Future<T?> showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required List<TextEditingController> controllers,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  try {
    final result = await navigator.push(route);
    await route.completed;
    return result;
  } finally {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}
