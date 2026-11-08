import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/widgets/segment_label.dart';

/// OPH-407 (U-10, DESIGN §45) — the copy pass.
///
/// The persona review's Ek A gave each of these strings word for word; the
/// glossary (§3.4) named the words that leave the product. check:i18n holds
/// the address rule (sen / siz per surface) and the licence word; this file
/// holds the exact texts and the glossary, so a later edit that drifts back
/// ("Bitiş", "Masaya yaz", "Sign in to your space") fails here.
Map<String, String> _flat(String language) {
  final out = <String, String>{};
  void walk(Map<String, dynamic> node, String prefix) {
    node.forEach((key, value) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is String) out[path] = value;
      if (value is Map<String, dynamic>) walk(value, path);
    });
  }

  walk(
    jsonDecode(File('assets/i18n/$language.json').readAsStringSync())
        as Map<String, dynamic>,
    '',
  );
  return out;
}

void main() {
  final tr = _flat('tr');
  final en = _flat('en');

  // key → (Turkish, English); null keeps the language out of the assertion.
  const ekA = <String, (String?, String?)>{
    'auth.signInTitle': ('Hesabına giriş yap', 'Sign in to your account'),
    'home.quickAddHint': (
      'Görev ekle… örn. yarın 15:00 #iş',
      'Add a task… e.g. tomorrow 3pm #work',
    ),
    'home.quickAddHintShort': ('Görev ekle', 'Add a task'),
    'task.due': ('Son tarih', 'Due'),
    'task.dueOn': ('Son tarih {date}', 'Due {date}'),
    'task.when': ('Planlanan gün', 'When'),
    'task.alarmsMutedSub': (
      'Yeniden açana kadar bu görev için uyarı gelmez.',
      null,
    ),
    'settings.group.developerSub': (
      'API anahtarları ve kullanım belgeleri',
      'API keys and documentation',
    ),
    'settings.group.generalSub': (
      'Dil, tarih biçimi, varsayılan saat, tanıtım turu',
      'Language, date format, default time, app tour',
    ),
    'settings.group.notificationsSub': (
      'Alarmlar, kilit ekranında içerik gizleme, hatırlatıcılar',
      'Alarms, hiding content on the lock screen, reminders',
    ),
    'settings.quickBubbleSub': (
      'İstediğin yere sürükle; dokununca kısayollar açılır',
      'Drag it anywhere; tap to open your shortcuts',
    ),
    'settings.defaultTaskTime.sub': (
      'Saat seçmediğin görevlerin saati: {time}',
      'Tasks without a time are due at {time}',
    ),
    'settings.noteSourceStyling.markersOnly': (
      'Yalnız işaretler: Markdown işaretleri görünür, biçim uygulanmaz',
      'Markers only: Markdown marks stay visible, no formatting',
    ),
    'settings.widget.compact': (
      'Yoğun widget (daha çok görev sığar)',
      'Compact widget (fits more tasks)',
    ),
    'alarmLog.sub': (
      'Bu cihazda çalan ve kaçırılan alarmlar',
      'Alarms this device rang or missed',
    ),
    'settings.alarms.testSub': (
      '{seconds} saniye sonra çalacak gerçek bir acil alarm kurar. '
          'Telefonu kilitle ve dinle.',
      null,
    ),
    'reminderSettings.preset.custom': ('Özel', 'Custom'),
    'project.tabOverview': ('Özet', 'Overview'),
    'note.modeSource': ('Düzenle', 'Edit'),
    'note.modeReading': ('Oku', 'Read'),
    'note.filterReadmes': ('Proje özetleri', 'Project overviews'),
    'files.sources': ('Görev ve not ekleri', 'Task and note attachments'),
    'quick.targetRenamed': ('Yeni adı: {name}', 'Renamed: {name}'),
    'calendar.notSetUpServer': (
      'Bu sunucuda Google Takvim kurulu değil. Yöneticiysen sunucunun .env '
          'dosyasına bir Google OAuth istemcisi ekle: Kendin barındır '
          'rehberi → Google Takvim.',
      "Google Calendar isn't configured on this server. Admins: add a "
          "Google OAuth client to the server's .env — see Self-hosting "
          'guide → Google Calendar.',
    ),
    'ee.unitScope.chooseTitle': (
      'Hangi birimin taleplerini görmek istersiniz?',
      "Which unit's requests do you want to see?",
    ),
    'ee.unitScope.chooseBody': (
      'Talepler birim birim tutulur. Bir birim seçin ya da tümünü görün.',
      'Requests are kept per unit. Pick a unit or see them all.',
    ),
    'ee.teamAddress.notInTeamTitle': (
      'Bu firmanın talep sistemine üye değilsiniz',
      "You're not a member of this company's workspace",
    ),
    'ee.teamAddress.notInTeamBody': (
      'Giriş yaptığınız hesap ({email}) bu firmada kayıtlı değil. '
          'Yöneticinizden davet isteyin ya da başka bir hesapla girin.',
      "The account you're signed in with ({email}) isn't registered here. "
          'Ask your admin for an invite or sign in with another account.',
    ),
    'ee.teamAddress.switchAccount': ('Hesap değiştir', 'Switch account'),
    'ee.csv.download': ("Excel'e aktar (.csv)", 'Export to CSV'),
    'ee.problems.title': ('Tekrarlayan arızalar', 'Problems'),
    'ee.problems.fromTicketAction': (
      'Tekrarlayan arıza olarak kaydet',
      'Record as a recurring problem',
    ),
    'ee.tickets.relatedAction': (
      'Yeniden açıldı olarak işaretle',
      'Mark as reopened',
    ),
    'ee.myUnits.live': (
      'Anlık veri · internet bağlantısı gerekir',
      'Live data · needs a connection',
    ),
    'ee.tickets.archive.mineTileBody': (
      'Bir süre önce kapanan talepleriniz. Yalnız görüntülenir; internet '
          'bağlantısı gerekir.',
      'Requests that closed a while ago. View only; needs a connection.',
    ),
    'ee.assets.filter.location': ('Konum', 'Location'),
    'ee.tickets.filter.slaBreached': ('SLA aşıldı', 'SLA missed'),
    'ee.tickets.filter.unassigned': ('Atanmamış', 'Unassigned'),
    'ee.tickets.filter.processType.incident': ('Arızalar', 'Incidents'),
    'ee.tickets.filter.processType.request': ('İstekler', 'Service requests'),
    'ee.perfPanel.title': ('İş yükü raporu', 'Workload report'),
    'ee.perfPanel.processTypeNone': (
      'Türü seçilmemiş talepler',
      'Requests with no type',
    ),
    'ee.slaDash.compliance': (
      'Süresinde çözülen talepler',
      'Resolved within SLA',
    ),
    'ee.slaDash.complianceOf': (
      '{total} talepten {met}',
      '{met} of {total} requests',
    ),
    'ee.slaDash.byService': ('Hizmete göre', 'By service'),
    'ee.slaDash.byUnit': ('Birime göre', 'By unit'),
    'ee.perfPanel.byUnit': ('Birime göre', 'By unit'),
    // OPH-407 (polish P-15): an in-app notification says what the e-mail
    // about the same request says — "SLA aşıldı", never "SLA ihlali".
    'ee.notif.sla.breached.title': (
      'SLA aşıldı: {ticketRef}',
      'SLA missed: {ticketRef}',
    ),
    'ee.notif.sla.warned.title': (
      'SLA dolmak üzere: {ticketRef}',
      'SLA due soon: {ticketRef}',
    ),
    'ee.notif.class.sla.breached': ('Bir SLA aşıldığında', 'An SLA is missed'),
    'ee.webhooks.event.sla.breached': ('SLA aşıldı', 'SLA missed'),
    'ee.webhooks.event.sla.warned': ('SLA dolmak üzere', 'SLA due soon'),
    'ee.team.seats.unlimited': ('{used} kişi · kişi sınırı yok', null),
    'ee.team.settings.slugFixed': (
      'Adı değiştirmek web adresinizi ({slug}) değiştirmez; paylaşılan '
          'bağlantılar çalışmaya devam eder.',
      "Renaming doesn't change your web address ({slug}); shared links keep "
          'working.',
    ),
    'ee.team.units.youManage': ('Sorumlusu sizsiniz', 'You run this unit'),
    'ee.tickets.new.pickService': (
      'Talep türünü seçin',
      'Choose a request type',
    ),
    'ee.meetings.upload': (
      'Toplantı ses kaydı yükle',
      'Upload a meeting recording',
    ),
    'ee.unitScope.switcherTitle': ('Birim seçin', 'Choose a unit'),
    'ee.tickets.linkedTasksEmpty': (
      'Bu talepten henüz görev açılmadı.',
      'No tasks opened from this request yet.',
    ),
    'ee.tickets.openAnotherTask': ('Bir görev daha aç', 'Open another task'),
    'ee.myUnits.stripBreached': (
      'Diğer birimlerinizde {breached} talebin süresi aşıldı',
      'In your other units: {breached} requests past SLA',
    ),
    'ee.myUnits.stripBoth': (
      'Diğer birimlerinizde {breached} talebin süresi aşıldı, {warned} '
          'talebinki dolmak üzere',
      'In your other units: {breached} requests past SLA, {warned} due soon',
    ),
  };

  group('Ek A, word for word', () {
    ekA.forEach((key, texts) {
      test(key, () {
        if (texts.$1 != null) expect(tr[key], texts.$1, reason: 'tr');
        if (texts.$2 != null) expect(en[key], texts.$2, reason: 'en');
      });
    });
  });

  group('the glossary (§3.4): words that leave the product', () {
    // Each entry: the word, and the keys allowed to keep it.
    final bannedTr = <RegExp, Set<String>>{
      RegExp(r'\b[Mm]asa(?:ya|da|dan|nın|sı|yı|ları?)?\b'): {},
      RegExp('[Ss]ervis'): {'ee.identity.bindDnLabel'}, // an LDAP account
      RegExp('[Ll]okasyon'): {},
      RegExp('[Kk]oltu[kğ]'): {},
      RegExp('[Vv]arlı[kğ]'): {},
      RegExp('Kimsede değil|SLA kaçtı|Tutulan sözler|Performans panosu'): {},
      // OPH-407 (polish P-15): a missed SLA is "aşıldı" everywhere.
      RegExp('[Iİı]hlal'): {},
      RegExp('Bilinen hata|Hizmet isteği|CSV indir|Genel bakış'): {},
      RegExp('README|Enterprise'): {},
      RegExp(r'^(Ne zaman|Bitiş)\b'): {
        // a rule's trigger, a quiet window, a repeat's end, an absence
        'ee.rules.when',
        'ee.notif.quietEnd',
        'repeat.endLabel',
        'repeat.endUntilLabel',
        'error.ABSENCE_RANGE_INVALID',
      },
    };
    bannedTr.forEach((word, allowed) {
      test('tr: ${word.pattern}', () {
        final hits = [
          for (final MapEntry(:key, :value) in tr.entries)
            if (word.hasMatch(value) && !allowed.contains(key)) '$key: $value',
        ];
        expect(hits, isEmpty);
      });
    });

    test('en: desk, deadline, promises, on nobody, source/reading modes, '
        'breach', () {
      final word = RegExp(
        r'\bdesks?\b|deadline or|promises kept|on nobody|READMEs?\b|'
        r'\bbreach(?:ed|es)?\b',
        caseSensitive: false,
      );
      // A {placeholder} is the server's field name, not a word a person reads.
      final placeholder = RegExp(r'\{[^}]*\}');
      final hits = [
        for (final MapEntry(:key, :value) in en.entries)
          if (word.hasMatch(value.replaceAll(placeholder, ''))) '$key: $value',
      ];
      expect(hits, isEmpty);
    });

    test('no device verb tells a person to tap a text', () {
      final tapTo = RegExp(
        // A gesture hint ("basılı tut, yazmak için dokun") names a gesture;
        // "Düzeltmek için dokunun" names a device instead of a button.
        r'\b(dokunun|tıklayın)\b|\btap to (fix|switch|see|allow|finish)',
        caseSensitive: false,
      );
      final hits = [
        for (final catalogue in [tr, en])
          for (final MapEntry(:key, :value) in catalogue.entries)
            if (tapTo.hasMatch(value)) '$key: $value',
      ];
      expect(hits, isEmpty);
    });
  });

  group('a segment label never breaks inside a word', () {
    testWidgets('a long word on a narrow segment stays whole', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: AwSegmentLabel('Sakin')),
                    ButtonSegment(value: 1, label: AwSegmentLabel('Standart')),
                    ButtonSegment(value: 2, label: AwSegmentLabel('Israrcı')),
                    ButtonSegment(value: 3, label: AwSegmentLabel('Özel')),
                  ],
                  selected: const {1},
                  onSelectionChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('Standart'),
      );
      // Laid out at its full width: one line, nothing cut.
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
        ),
      );
    });
  });
}
