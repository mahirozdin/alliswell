/// The QR label sheet, the impure edge (EE-194).
///
/// The layout lives in `data/asset_label_pdf.dart` and touches no platform
/// channel, so it is testable in a plain `flutter test`. This file owns only
/// what needs a platform: reading the fonts out of the asset bundle and
/// handing the bytes to the OS.
///
/// ── NO IN-APP SCANNER, AND THAT IS A DECISION WITH A RECEIPT ───────────
///
/// The main flow is the phone's OWN camera: both operating systems read a QR
/// code from the camera app and follow `alliswell://asset/{id}` straight to
/// the card. Nothing is bundled to do that, and nothing needs to be.
///
/// A live-preview scanner inside the app would need the `CAMERA` permission,
/// and this app does not have it — `AndroidManifest.xml` STRIPS it, along
/// with six media permissions, under a written product policy ("AllisWell
/// asks for NO media permission, ever"), and `scripts/android/assert-
/// permissions.sh` checks the built APK because `tools:node="remove"` is
/// silent when nothing matches. A scanner package would merge CAMERA back in,
/// the remove line would take it out again, and the scanner would fail at
/// runtime rather than at build time.
///
/// So: the sheet prints here, the phone reads it, and the deep link does the
/// rest.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../i18n/i18n.dart';
import '../data/asset_label_pdf.dart';
import '../data/assets_models.dart';

/// The two faces the sheet draws with, read once per process. Roboto rather
/// than the `pdf` package's built-in Helvetica, whose WinAnsi encoding has no
/// `ı ğ ş İ` — the note exporter measured that first and every Turkish label
/// would print as mojibake.
final assetLabelFontsProvider = FutureProvider<AssetLabelFonts>((ref) async {
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return AssetLabelFonts(
    regular: await load('Roboto-Regular'),
    bold: await load('Roboto-Bold'),
  );
});

/// Seam so tests can drive the sheet without a plugin. The default hands the
/// bytes to the OS; a fake records them.
class AssetLabelSink {
  const AssetLabelSink();

  Future<void> layout(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
}

final assetLabelSinkProvider = Provider<AssetLabelSink>(
  (ref) => const AssetLabelSink(),
);

/// Builds and prints labels for [assets].
Future<void> printAssetLabels(
  BuildContext context,
  WidgetRef ref,
  List<EeAsset> assets,
) async {
  if (assets.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final fonts = await ref.read(assetLabelFontsProvider.future);
    final bytes = await buildAssetLabelSheet(
      fonts: fonts,
      title: 'ee.assets.labels.sheetTitle'.tr(),
      labels: assets
          .map(
            (a) => AssetLabel(
              id: a.id,
              tag: a.tag,
              name: a.name,
              location: a.location,
            ),
          )
          .toList(growable: false),
    );
    await ref.read(assetLabelSinkProvider).layout(bytes, 'asset-labels');
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text('ee.assets.labels.failed'.tr())),
    );
  }
}
