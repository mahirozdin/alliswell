// Known faults on the phone (EE-270, AW-E09): the list and one record.
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/problems_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THESE SHOTS.
//
//   • THE LIST, KNOWN ERRORS FIRST: the status word, what people see, and
//     whether a workaround is written down — the question an agent opens the
//     list with.
//   • THE KNOWN-ERROR RECORD: the workaround in full at the top, then how to
//     recognise it and why it happens, then the requests it explains — the
//     report's "let's open the known-error record" in one picture.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/problems_models.dart';
import 'package:alliswell/src/features/ee/problems_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/problem_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/problems_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

const _printer = 'P1';

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  bool tr() => AwI18n.instance.locale.languageCode == 'tr';

  EeProblem problem(
    String id,
    String titleTr,
    String titleEn,
    String symptomTr,
    String symptomEn, {
    String status = 'known_error',
    String? workaroundTr,
    String? workaroundEn,
    String? rootCauseTr,
    String? rootCauseEn,
  }) => EeProblem(
    id: id,
    workspaceId: 'W1',
    title: tr() ? titleTr : titleEn,
    symptom: tr() ? symptomTr : symptomEn,
    status: status,
    workaround: tr() ? workaroundTr : workaroundEn,
    rootCause: tr() ? rootCauseTr : rootCauseEn,
    updatedAt: DateTime(2026, 9, 24, 10),
  );

  EeProblem printer() => problem(
    _printer,
    'Etiket yazıcısı bekleme sonrası sıkışıyor',
    'Label printer jams after standby',
    'Gece bekleme modundan sonra ilk etikette kağıt sıkışıyor.',
    'After the overnight standby the first label jams the paper.',
    workaroundTr:
        'Vardiya başında yazıcıyı bir kez kapatıp açın; ilk etiketi boş basın.',
    workaroundEn:
        'At the start of the shift, switch the printer off and on once; print the first label blank.',
    rootCauseTr: 'Bekleme dönüşünde ısıtıcı geç devreye giriyor.',
    rootCauseEn:
        'The heater comes on late when the printer wakes from standby.',
  );

  List<Override> common() => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    canProvider.overrideWith((ref, id) => true),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('the list, known errors first (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-problems',
        size: const Size(900, 1700),
        overrides: [
          ...common(),
          problemSearchResultsProvider.overrideWith((ref) async => null),
          eeProblemListProvider.overrideWith(
            (ref) => Stream.value([
              printer(),
              problem(
                'P2',
                'VPN sabah bağlanmıyor',
                'VPN will not connect in the morning',
                'Saat 8 ile 9 arasında VPN bağlantısı düşüyor.',
                'Between 8 and 9 the VPN connection keeps dropping.',
                status: 'investigating',
              ),
              problem(
                'P3',
                'Pres hattı sensörü yanlış okuyor',
                'Press line sensor misreads',
                'Pres sensörü her 200 baskıda bir sıfır okuyor.',
                'The press sensor reads zero every 200 strokes.',
                status: 'resolved',
              ),
            ]),
          ),
        ],
        screen: const EeProblemsScreen(),
      );
    });

    testWidgets('the known-error record (${brightness.name})', (tester) async {
      final record = printer();
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-problem-detail',
        size: const Size(900, 2000),
        overrides: [
          ...common(),
          eeProblemOnDeviceProvider(
            _printer,
          ).overrideWith((ref) => Stream.value(record)),
          eeProblemLiveProvider(_printer).overrideWith(
            (ref) async => EeProblemLive(
              problem: record,
              tickets: EeProblemTickets(
                tickets: [
                  EeProblemTicket(
                    id: 'T1',
                    workspaceId: 'W1',
                    number: 1042,
                    subject: tr()
                        ? 'Etiket yazıcısı her sabah sıkışıyor'
                        : 'The label printer jams every morning',
                    status: 'in_progress',
                    priority: 'high',
                  ),
                  EeProblemTicket(
                    id: 'T2',
                    workspaceId: 'W1',
                    number: 1057,
                    subject: tr()
                        ? 'Sevkiyat etiketleri basılmadı'
                        : 'Shipping labels did not print',
                    status: 'new',
                    priority: 'medium',
                  ),
                ],
                count: 2,
                elsewhere: 3,
              ),
            ),
          ),
        ],
        screen: const EeProblemDetailScreen(problemId: _printer),
      );
    });
  }
}
