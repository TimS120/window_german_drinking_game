import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'localization.dart';

/// The bundled Markdown files are deliberately limited to headings, paragraphs
/// and dash-prefixed lists, so they can be edited without a rendering package.
class GameRulesScreen extends StatelessWidget {
  const GameRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode == 'de'
        ? 'de'
        : 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context).gameRules),
        actions: const [LanguagePicker()],
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(
          'assets/rules/$language.md',
          cache: false,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lines = snapshot.data!.split('\n');
          final theme = Theme.of(context).textTheme;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final line = lines[index].trim();
                  if (line.isEmpty) return const SizedBox(height: 8);
                  final heading = line.startsWith('# ');
                  final bullet = line.startsWith('- ');
                  final text = heading || bullet ? line.substring(2) : line;
                  return Padding(
                    padding: EdgeInsets.only(top: heading ? 12 : 0, bottom: 8),
                    child: Text(
                      bullet ? '•  $text' : text,
                      style: heading ? theme.titleLarge : theme.bodyLarge,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
