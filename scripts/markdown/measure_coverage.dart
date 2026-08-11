// ADR-0028'in sayılarını üreten ölçüm (OPH-246).
//
// Çalıştırma — `markdown` bugün TRANSITIVE bir bağımlılık olduğu için betik
// `apps/app`'in paket çözümüne yaslanır ve oradan koşar:
//
//     cd apps/app
//     cp ../../scripts/markdown/measure_coverage.dart ./_measure.dart
//     dart run _measure.dart test/fixtures/markdown_conformance.md
//     rm _measure.dart
//
// **Zorlayıcı kopya artık bu değil.** OPH-247 bunu bir teste dönüştürdü —
// `apps/app/test/features/notes/markdown/markdown_coverage_test.dart` — ve
// CI'da koşan o. Bu dosya ADR-0028'in sayılarının NASIL üretildiğinin kaydı
// olarak duruyor.
//
// Burada durduğu yerden `dart analyze` ETMEZ ve koşmaz: `package:markdown`
// yalnız `apps/app`'in paket çözümünde var, o yüzden analiz burada yedi hata
// verir ve yedisi de aynı çözülmeyen import'tan gelir. CI `apps/app` içinden
// analiz ettiği için bu kimseyi kırmıyor; yine de bilerek yazılıyor ki bir
// sonraki okuyan "burası neden kırmızı" diye vakit harcamasın.
//
// OPH-246 ölçümü — iki soruya sayıyla cevap verir:
//   1. Ağaçtaki `markdown` 7.3.1 + gitHubWeb, D6 hedefinin ne kadarını KARŞILIYOR?
//   2. D4/D13/D14/D16/D5'in dayandığı "düğüm -> kaynak satırı" haritası,
//      paketi FORK'LAMADAN kurulabiliyor mu?
//
// (2) kritik: paket AST'sinde hiçbir konum bilgisi yok. Ama `Line` alt
// sınıflanabilir, `Document.parseLineList(List<Line>)` public, ve
// `withDefaultBlockSyntaxes: false` ile sözdizimi listesinin TAMAMINI biz
// verebiliyoruz — yani her sözdizimini saran bir dekoratör konumu damgalayabilir.
import 'dart:io';
import 'package:markdown/markdown.dart' as md;

/// Kendi indeksini taşıyan satır. Paket `Line`'ı kimliğiyle taşıdığı için
/// `parser.current` bize geri geldiğinde indeks elimizde olur.
class IndexedLine extends md.Line {
  IndexedLine(super.content, this.index);
  final int index;
}

/// Her blok sözdizimini saran ve ürettiği düğüme kaynak satır aralığını
/// damgalayan dekoratör. `Element.attributes` public ve değiştirilebilir.
class PositionedSyntax extends md.BlockSyntax {
  PositionedSyntax(this.inner);
  final md.BlockSyntax inner;

  @override
  RegExp get pattern => inner.pattern;

  @override
  bool canParse(md.BlockParser parser) => inner.canParse(parser);

  @override
  bool canEndBlock(md.BlockParser parser) => inner.canEndBlock(parser);

  @override
  md.Node? parse(md.BlockParser parser) {
    final before = _lineOf(parser);
    final node = inner.parse(parser);
    final after = _lineOf(parser);
    if (node is md.Element && before != null) {
      node.attributes['data-line'] = '$before';
      node.attributes['data-line-end'] = '${(after ?? before) - 1}';
    }
    return node;
  }

  static int? _lineOf(md.BlockParser parser) {
    if (parser.isDone) return parser.lines.length;
    final line = parser.current;
    return line is IndexedLine ? line.index : null;
  }
}

void main(List<String> args) {
  final src = File(args[0]).readAsStringSync();
  final rawLines = src.split('\n');

  // --- 1. Kapsam ölçümü: düz gitHubWeb ---
  final plain = md.Document(
    extensionSet: md.ExtensionSet.gitHubWeb,
    encodeHtml: false,
  );
  final nodes = plain.parseLines(rawLines);
  final html = md.renderToHtml(nodes);

  final tags = <String, int>{};
  void walk(md.Node n) {
    if (n is md.Element) {
      tags[n.tag] = (tags[n.tag] ?? 0) + 1;
      for (final c in n.children ?? const <md.Node>[]) {
        walk(c);
      }
    }
  }

  for (final n in nodes) {
    walk(n);
  }

  stdout.writeln('=== AST düğüm histogramı (gitHubWeb) ===');
  final keys = tags.keys.toList()..sort();
  stdout.writeln(keys.map((k) => '$k:${tags[k]}').join('  '));

  final checks = <String, bool>{
    'tablo + başlık hücresi': tags.containsKey('table') && tags.containsKey('th'),
    // Paket hizalamayı `align="left|center|right"` attribute'üyle veriyor,
    // CSS `text-align` ile değil — ilk ölçüm burada yanlış negatif üretmişti.
    'tablo hizalaması': html.contains('align="center"'),
    'görev listesi kutusu': html.contains('type="checkbox"'),
    'dipnot tanımı': html.contains('footnote') || tags.containsKey('footnote'),
    'dipnot referansı': html.contains('fnref') || html.contains('footnote-ref'),
    'uyarı kutusu [!NOTE]': html.contains('alert'),
    'üstü çizili': tags.containsKey('del'),
    'çıplak URL autolink': html.contains('>https://alliswell.space<'),
    'emoji kısa kodu': html.contains('🚀'),
    'başlık id (çapa)': html.contains('<h2 id='),
    'iç içe liste 3 seviye': RegExp(r'<ul>[\s\S]*?<ul>[\s\S]*?<ul>').hasMatch(html),
    'dilli kod çiti': html.contains('language-dart'),
    'mermaid çiti (kod bloğu olarak)': html.contains('language-mermaid'),
    'HTML bloğu düğümü': html.contains('<script>'),
    'satır içi kod': tags.containsKey('code'),
    'yatay çizgi': tags.containsKey('hr'),
    'alıntı': tags.containsKey('blockquote'),
    'görsel': tags.containsKey('img'),
    'satır sonu kırılması': tags.containsKey('br'),
    // Bunlar YOK çıkarsa özel syntax yazılacak demektir:
    r'matematik ($…$)': html.contains(r'class="math'),
    'vurgu ==highlight==': html.contains('<mark>'),
    'front matter şeridi': html.contains('front-matter'),
  };

  stdout.writeln('\n=== D6 hedefi ===');
  var ok = 0;
  final missing = <String>[];
  for (final e in checks.entries) {
    stdout.writeln('${e.value ? "  VAR" : "  YOK"}  ${e.key}');
    if (e.value) {
      ok++;
    } else {
      missing.add(e.key);
    }
  }
  stdout.writeln('\nKAPSAM: ${checks.length} kalemden $ok HAZIR, '
      '${missing.length} eksik -> ${missing.join(", ")}');

  // --- 2. Konum haritası kurulabiliyor mu? ---
  final decorated = <md.BlockSyntax>[
    ...md.ExtensionSet.gitHubWeb.blockSyntaxes,
    const md.EmptyBlockSyntax(),
    const md.HtmlBlockSyntax(),
    const md.SetextHeaderSyntax(),
    const md.HeaderSyntax(),
    const md.CodeBlockSyntax(),
    const md.BlockquoteSyntax(),
    const md.HorizontalRuleSyntax(),
    const md.UnorderedListSyntax(),
    const md.OrderedListSyntax(),
    const md.LinkReferenceDefinitionSyntax(),
    const md.ParagraphSyntax(),
  ].map(PositionedSyntax.new).toList();

  final positioned = md.Document(
    blockSyntaxes: decorated,
    inlineSyntaxes: md.ExtensionSet.gitHubWeb.inlineSyntaxes,
    withDefaultBlockSyntaxes: false,
    encodeHtml: false,
  );
  final indexed = <md.Line>[
    for (var i = 0; i < rawLines.length; i++) IndexedLine(rawLines[i], i),
  ];
  final posNodes = positioned.parseLineList(indexed);
  final topElements = posNodes.whereType<md.Element>().toList();
  final stamped = topElements.where((e) => e.attributes.containsKey('data-line'));

  stdout.writeln('\n=== Konum haritası (fork YOK) ===');
  stdout.writeln('üst düzey düğüm: ${topElements.length}, '
      'kaynak satırı damgalanan: ${stamped.length}');

  // Damgalar gerçekten doğru mu? Başlıkları kaynakla karşılaştır.
  var headingsChecked = 0;
  var headingsCorrect = 0;
  for (final e in topElements) {
    if (!RegExp(r'^h[1-6]$').hasMatch(e.tag)) continue;
    final line = int.tryParse(e.attributes['data-line'] ?? '');
    if (line == null) continue;
    headingsChecked++;
    if (rawLines[line].trimLeft().startsWith('#')) headingsCorrect++;
  }
  stdout.writeln('başlık damgası doğrulaması: '
      '$headingsCorrect / $headingsChecked satır gerçekten "#" ile başlıyor');
}
