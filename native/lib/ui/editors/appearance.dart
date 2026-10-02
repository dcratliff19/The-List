part of '../workspace.dart';

extension _WorkspaceEditorsAppearance on _WorkspaceState {
  void loadExample() {
    final pid = store.create('project', '', {
      'title': 'A space of our own',
      'description':
          'A collection of things that could make a place feel like us.',
      'label': 'Home & living',
      'color': 0xff91a997,
      'example': true,
    });
    store.create('link', pid, {
      'title': 'A better way to make space',
      'body':
          'Thoughtful spaces, natural materials, and ideas worth coming back to.',
      'url': 'https://www.architecturaldigest.com/',
      'tags': 'Inspiration',
    });
    store.create('note', pid, {
      'title': "The feeling we're going for",
      'body':
          'Less, but better.\n\nA room that feels collected, not decorated. Warm light. Honest materials. A place to slow down.',
      'tags': 'Starting point',
    });
    store.create('link', pid, {
      'title': 'Objects with a little more meaning',
      'body': 'Independent makers and considered pieces for everyday life.',
      'url': 'https://www.are.na/',
      'tags': 'Research',
    });
    store.create('note', pid, {
      'title': 'Things to look into',
      'body':
          "Oak or walnut for the desk?\nA lamp with a warmer glow\nStorage that doesn't feel like storage",
      'tags': 'Ideas',
    });
    openProject(pid);
    message('Example project added. You can edit or remove it.');
  }

  Future<void> chooseAccent() async {
    final input = TextEditingController(
      text: store.setting('accent') ?? '5848D9',
    );
    String? error;
    await showEditorDialog<void>(
      context: context,
      controllers: [input],
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final hex = input.text.trim().replaceFirst('#', '');
          final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex);
          final selected = valid
              ? Color(0xff000000 | int.parse(hex, radix: 16))
              : accent;
          return AlertDialog(
            title: const Text('Choose your accent color'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final preset in <String, String>{
                          'Purple': '5848D9',
                          'Blue': '2563EB',
                          'Teal': '008577',
                          'Green': '2E7D32',
                          'Orange': 'C05600',
                          'Rose': 'BE185D',
                          'Red': 'C62828',
                          'Slate': '475569',
                        }.entries)
                          Tooltip(
                            message: preset.key,
                            child: Semantics(
                              label: preset.key,
                              button: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => update(() {
                                  input.text = preset.value;
                                  error = null;
                                }),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(
                                      0xff000000 |
                                          int.parse(preset.value, radix: 16),
                                    ),
                                  ),
                                  child: hex.toUpperCase() == preset.value
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: input,
                      maxLength: 7,
                      decoration: InputDecoration(
                        labelText: 'Hex color',
                        hintText: '#008577',
                        errorText: error,
                      ),
                      onChanged: (_) => update(() {
                        error = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Your ideas, your color.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected.computeLuminance() > .179
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Light and dark themes adapt your color for readability.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!valid) {
                    update(
                      () =>
                          error = 'Enter six hex digits, for example #008577.',
                    );
                    return;
                  }
                  store.setSetting('accent', hex.toUpperCase());
                  widget.onTheme();
                  Navigator.pop(context);
                },
                child: const Text('Apply color'),
              ),
            ],
          );
        },
      ),
    );
  }
}
