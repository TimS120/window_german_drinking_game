import 'package:flutter/material.dart';

import 'localization.dart';
import 'player_names.dart';

class DevicePlayersEdit {
  const DevicePlayersEdit(this.label, this.names);
  final String label;
  final List<String> names;
}

class DevicePlayersEditor extends StatefulWidget {
  const DevicePlayersEditor({
    super.key,
    required this.label,
    required this.names,
    required this.otherNames,
  });
  final String label;
  final List<String> names, otherNames;
  @override
  State<DevicePlayersEditor> createState() => _DevicePlayersEditorState();
}

class _DevicePlayersEditorState extends State<DevicePlayersEditor> {
  late final _label = TextEditingController(text: widget.label);
  late final _names = TextEditingController(text: widget.names.join(', '));
  bool _duplicate = false;
  @override
  void dispose() {
    _label.dispose();
    _names.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(l.editDevicePlayers),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('device-label'),
                controller: _label,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l.physicalGroup,
                  hintText: l.physicalGroupExample,
                ),
              ),
              TextField(
                key: const ValueKey('device-players'),
                controller: _names,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: l.devicePlayers,
                  helperText: l.editPlayersHelp,
                  helperMaxLines: 5,
                  errorText: _duplicate ? l.uniquePlayers : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            final names = splitPlayerNames(_names.text);
            final used = widget.otherNames.map((n) => n.toLowerCase()).toSet();
            if (names.any((n) => !used.add(n.toLowerCase()))) {
              setState(() => _duplicate = true);
              return;
            }
            Navigator.pop(
              context,
              DevicePlayersEdit(
                _label.text.trim().isEmpty
                    ? widget.label
                    : capitalizeName(_label.text),
                names,
              ),
            );
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}
