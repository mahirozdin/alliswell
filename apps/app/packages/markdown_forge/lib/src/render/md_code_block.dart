/// A fenced code block: language label, copy button, its own scroll
/// (DESIGN §29 D8/D9, OPH-247).
///
/// D9 calls the copy button "the reason people open a README on a phone", and
/// D8 is the single most common markdown-on-mobile failure: a wide code block
/// that makes the whole PAGE scroll sideways. The scroll view here is the fix,
/// and it belongs to the block, not to the document.
///
/// Highlighting uses `highlight` as a LEXER only. Its ~30 class names collapse
/// onto the six `AwTokens.code*` inks (see [MdStyles.codeInk]) — the package's
/// own themes are never touched, because D7 has no third-party carve-out.
/// Languages are registered explicitly rather than importing the all-in-one
/// entry point: that would pull all 190 grammars (1.9 MB of Dart) into the
/// bundle, versus 128 KB for the nineteen below.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight_core.dart' show highlight, Node;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/diff.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/ini.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/shell.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

import 'md_theme.dart';
import '../seams.dart';

/// Grammars we ship, and the aliases people actually type in a fence.
const Map<String, String> _aliases = {
  'sh': 'bash',
  'zsh': 'bash',
  'console': 'shell',
  'js': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'yml': 'yaml',
  'html': 'xml',
  'svg': 'xml',
  'md': 'markdown',
  'py': 'python',
  'rs': 'rust',
  'kt': 'kotlin',
  'toml': 'ini',
  'conf': 'ini',
  'patch': 'diff',
};

/// The grammars registered below, by name.
///
/// Kept as our own set rather than asking the package: `Highlight` has no
/// public lookup, and `parse()` silently falls back to plaintext for a name it
/// does not know — so an unregistered language would produce a *colourless but
/// successful* result and nobody would notice the grammar was missing.
const Set<String> _grammars = {
  'bash',
  'css',
  'dart',
  'diff',
  'go',
  'ini',
  'java',
  'javascript',
  'json',
  'kotlin',
  'markdown',
  'python',
  'rust',
  'shell',
  'sql',
  'swift',
  'typescript',
  'xml',
  'yaml',
};

bool _registered = false;

void _registerLanguages() {
  if (_registered) return;
  _registered = true;
  highlight
    ..registerLanguage('bash', bash)
    ..registerLanguage('css', css)
    ..registerLanguage('dart', dart)
    ..registerLanguage('diff', diff)
    ..registerLanguage('go', go)
    ..registerLanguage('ini', ini)
    ..registerLanguage('java', java)
    ..registerLanguage('javascript', javascript)
    ..registerLanguage('json', json)
    ..registerLanguage('kotlin', kotlin)
    ..registerLanguage('markdown', markdown)
    ..registerLanguage('python', python)
    ..registerLanguage('rust', rust)
    ..registerLanguage('shell', shell)
    ..registerLanguage('sql', sql)
    ..registerLanguage('swift', swift)
    ..registerLanguage('typescript', typescript)
    ..registerLanguage('xml', xml)
    ..registerLanguage('yaml', yaml);
}

/// Resolves a fence's info string to a grammar we have, or null.
String? resolveCodeLanguage(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  _registerLanguages();
  final name = raw.trim().toLowerCase().split(RegExp(r'[\s,]')).first;
  final resolved = _aliases[name] ?? name;
  return _grammars.contains(resolved) ? resolved : null;
}

class MdCodeBlock extends StatelessWidget {
  const MdCodeBlock({super.key, required this.source, this.language});

  final String source;

  /// The fence's info string, unresolved. An unknown language is not an error:
  /// the block still gets its panel, its label and its copy button, and the
  /// text is simply not coloured.
  final String? language;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    final resolved = resolveCodeLanguage(language);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: MdSpace.x2),
      decoration: BoxDecoration(
        color: styles.codePanel,
        borderRadius: const BorderRadius.all(Radius.circular(MdRadius.m)),
        border: Border.all(color: styles.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(label: language?.trim(), source: source),
          // D8: the block scrolls inside itself. Never the page.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              MdSpace.x3,
              0,
              MdSpace.x3,
              MdSpace.x3,
            ),
            child: SelectableText.rich(
              TextSpan(children: _spans(source, resolved, styles)),
              style: styles.code,
            ),
          ),
        ],
      ),
    );
  }

  static List<InlineSpan> _spans(
    String source,
    String? language,
    MdStyles styles,
  ) {
    if (language == null) {
      return [TextSpan(text: source)];
    }
    final result = highlight.parse(source, language: language);
    final spans = <InlineSpan>[];
    void walk(List<Node> nodes, Color? inherited) {
      for (final node in nodes) {
        final colour = styles.codeInk(node.className) ?? inherited;
        if (node.value != null) {
          spans.add(
            TextSpan(
              text: node.value,
              style: TextStyle(color: colour),
            ),
          );
        } else if (node.children != null) {
          walk(node.children!, colour);
        }
      }
    }

    walk(result.nodes ?? const [], null);
    return spans.isEmpty ? [TextSpan(text: source)] : spans;
  }
}

class _Header extends StatefulWidget {
  const _Header({required this.label, required this.source});

  final String? label;
  final String source;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.source));
    if (!mounted) return;
    // A button that reports nothing leaves the reader tapping it twice.
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(MdSpace.x3, MdSpace.x1, MdSpace.x1, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label?.isNotEmpty == true ? widget.label! : '',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: styles.muted,
                letterSpacing: 0.4,
              ),
            ),
          ),
          IconButton(
            key: const Key('md-copy-code'),
            tooltip: _copied
                ? context.mdStrings.copied
                : context.mdStrings.copy,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: _copy,
            icon: Icon(
              _copied ? Icons.check : Icons.copy_all_outlined,
              color: _copied ? styles.tokens.success : styles.muted,
            ),
          ),
        ],
      ),
    );
  }
}
