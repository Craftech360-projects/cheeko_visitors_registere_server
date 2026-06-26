import 'package:flutter/material.dart';
import 'config.dart';

class SettingsScreen extends StatelessWidget {
  SettingsScreen({super.key});
  final _ctrl = TextEditingController(text: Config.serverUrl);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'Server URL')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () { Config.serverUrl = _ctrl.text.trim(); Navigator.pop(context); },
              child: const Text('Save'),
            ),
          ]),
        ),
      );
}
