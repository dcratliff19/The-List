import 'package:flutter/material.dart';
import '../store.dart';
import '../ui/workspace.dart';
import 'theme.dart';

class TheListApp extends StatefulWidget {
  final Store store;
  final bool servicesEnabled;
  final String? initialTarget;
  const TheListApp({
    super.key,
    required this.store,
    this.servicesEnabled = true,
    this.initialTarget,
  });
  @override
  State<TheListApp> createState() => _TheListAppState();
}

class _TheListAppState extends State<TheListApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The List',
      debugShowCheckedModeBanner: false,
      theme: workspaceTheme(widget.store),
      home: Workspace(
        store: widget.store,
        servicesEnabled: widget.servicesEnabled,
        initialTarget: widget.initialTarget,
        onTheme: () => setState(() {}),
      ),
    );
  }
}
