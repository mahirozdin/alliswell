/// The one full-screen image viewer (OPH-245, DESIGN §30 A6/A7/A8).
///
/// There used to be two, and they disagreed: `showFileImageViewer` for the
/// Files surfaces, and a private `_EmbedImageViewer` inside `note_media.dart`
/// with no loading and no error builder at all. §22 in its clearest form.
///
/// Takes file **ids**, not `FileAttachment`s, for two measured reasons: a
/// note's gallery comes from a delta walk that yields ULIDs, and an image
/// embedded the instant its upload finishes has no replica row yet — an
/// attachment-typed API would make exactly that image un-openable, which is a
/// regression the old embed viewer did not have.
///
/// **No share, no save-to-gallery** (owner decision, round 17): the actions are
/// exactly the two the Files viewer already carried. A gallery saver needs a
/// new package and would reopen the Android media-permission surface that
/// ADR-0027 closed by measurement, and "Open / Download" already hands the
/// bytes to the browser/OS, which is where saving belongs (ATTACHMENTS §2.2).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart' show AwTr;
import '../../../theme/theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';
import 'file_widgets.dart';

const double kAwViewerMaxScale = 6;

/// Where a double-tap lands. Deliberately not [kAwViewerMaxScale] — jumping
/// straight to 6× overshoots what anyone wants from one gesture; the pinch is
/// there for the rest.
const double kAwViewerDoubleTapScale = 2.5;

Future<void> showAwImageViewer(
  BuildContext context, {
  required List<String> fileIds,
  required int initialIndex,
}) {
  // OPH-212: the ROOT navigator, like every sheet and dialog in this feature.
  // Pushed into a shell branch, this renders UNDER the shell's glass bar and
  // FAB — a full-screen photo with the app's FAB floating on top of it.
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          AwImageViewer(fileIds: fileIds, initialIndex: initialIndex),
    ),
  );
}

class AwImageViewer extends ConsumerStatefulWidget {
  const AwImageViewer({
    super.key,
    required this.fileIds,
    required this.initialIndex,
  });

  /// The gallery, in the order the calling surface is showing it (A11).
  final List<String> fileIds;
  final int initialIndex;

  @override
  ConsumerState<AwImageViewer> createState() => _AwImageViewerState();
}

class _AwImageViewerState extends ConsumerState<AwImageViewer>
    with SingleTickerProviderStateMixin {
  /// ONE controller for the whole viewer, not one per page: paging resets the
  /// transform anyway (the Photos idiom), and a single source of truth is what
  /// makes the "zoomed ⇒ paging is off" gate a one-liner. Safe across the two
  /// pages alive mid-scroll, because while unzoomed the matrix is identity and
  /// while zoomed there is no scroll.
  final TransformationController _transform = TransformationController();

  late final List<String> _ids;
  late int _index;
  late final PageController _pager;
  late final AnimationController _anim;
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapPoint = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _ids = List.of(widget.fileIds);
    _index = _ids.isEmpty ? 0 : widget.initialIndex.clamp(0, _ids.length - 1);
    _pager = PageController(initialPage: _index);
    _anim = AnimationController(vsync: this, duration: AwMotion.base)
      ..addListener(() {
        final tween = _zoomTween;
        if (tween != null) _transform.value = tween.value;
      });
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _anim.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  /// `T(p)·S·T(-p)`, written out: scale by [scale] leaving the scene point [p]
  /// exactly where the finger is. Spelled with [Matrix4.setEntry] rather than
  /// `translate`/`scale` so the arithmetic is visible to a reader and to a test.
  static Matrix4 scaleAbout(Offset p, double scale) => Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, p.dx * (1 - scale))
    ..setEntry(1, 3, p.dy * (1 - scale));

  void _animateTo(Matrix4 target, {required bool zoomingIn}) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(
        parent: _anim,
        // The tokens already encode the split: easing out on the way in,
        // easing in on the way back.
        curve: zoomingIn ? AwMotion.enter : AwMotion.exit,
      ),
    );
    _anim.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (_zoomed) {
      _animateTo(Matrix4.identity(), zoomingIn: false);
      return;
    }
    _animateTo(
      scaleAbout(_doubleTapPoint, kAwViewerDoubleTapScale),
      zoomingIn: true,
    );
  }

  void _zoomBy(double factor) {
    final size = context.size;
    if (size == null) return;
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, kAwViewerMaxScale);
    if (next == current) return;
    _animateTo(
      scaleAbout(Offset(size.width / 2, size.height / 2), next),
      zoomingIn: next > current,
    );
  }

  void _resetZoom() {
    if (_zoomed) _animateTo(Matrix4.identity(), zoomingIn: false);
  }

  /// Keyboard paging jumps rather than animates: the zoom reset below flips
  /// the scroll physics, and that only lands on the next build.
  void _goTo(int index) {
    if (index < 0 || index >= _ids.length) return;
    _transform.value = Matrix4.identity();
    _pager.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _transform.value = Matrix4.identity();
  }

  Future<void> _delete(FileAttachment file) async {
    final deleted = await confirmFileDelete(context, ref, file);
    if (!deleted || !mounted) return;
    if (_ids.length <= 1) {
      // The gallery is empty now; there is nothing to look at.
      Navigator.of(context).maybePop();
      return;
    }
    // Everything after the removed id shifts down by one, so staying on the
    // same page index already lands on the NEXT image — the Photos idiom.
    // Only deleting the last one needs a move.
    var jumpTo = -1;
    setState(() {
      _ids.removeAt(_index);
      if (_index > _ids.length - 1) {
        _index = _ids.length - 1;
        jumpTo = _index;
      }
    });
    if (jumpTo >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pager.jumpToPage(jumpTo);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ids.isEmpty) return const SizedBox.shrink();
    final fileId = _ids[_index];
    final byId = ref.watch(fileByIdProvider(fileId));
    final file = byId.value;
    final total = _ids.length;

    return CallbackShortcuts(
      bindings: {
        // A fullscreen-dialog route does NOT pop on Escape by default.
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_index + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_index - 1),
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoomBy(1.5),
        const SingleActivator(LogicalKeyboardKey.add): () => _zoomBy(1.5),
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(1 / 1.5),
        const SingleActivator(LogicalKeyboardKey.digit0): _resetZoom,
      },
      child: Focus(
        autofocus: true,
        // The whole viewer renders dark whatever the app theme is, the way
        // every OS photo viewer does — which is also what keeps the app bar,
        // the counter and the reason states contrast-safe on a black backdrop
        // instead of painting light-theme ink onto it.
        child: Theme(
          data: buildAwTheme(Brightness.dark),
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: _title(context, byId, total),
              actions: [
                IconButton(
                  tooltip: 'file.openDownload'.tr(),
                  icon: const Icon(Icons.open_in_new),
                  // No dead buttons (§22): you cannot download or delete a row
                  // that has not arrived from the replica yet.
                  onPressed: file == null
                      ? null
                      : () => openFileExternally(context, ref, file),
                ),
                IconButton(
                  tooltip: 'common.delete'.tr(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: file == null ? null : () => _delete(file),
                ),
              ],
            ),
            body: PageView.builder(
              controller: _pager,
              itemCount: total,
              onPageChanged: _onPageChanged,
              // A horizontal drag on a zoomed image must PAN, not page.
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemBuilder: (context, i) => _AwImageViewerPage(
                fileId: _ids[i],
                transform: _transform,
                onDoubleTapDown: (details) =>
                    _doubleTapPoint = details.localPosition,
                onDoubleTap: _handleDoubleTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(
    BuildContext context,
    AsyncValue<FileAttachment?> byId,
    int total,
  ) {
    final theme = Theme.of(context);
    // Empty while the lookup is in flight, the honest name only once it has
    // SETTLED null — one blank frame beats one wrong string.
    final name = byId.hasValue
        ? (byId.value?.name ?? 'file.mediaUnavailable'.tr())
        : '';
    final args = {'index': '${_index + 1}', 'total': '$total'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (total > 1)
          Semantics(
            label: 'file.viewerPosition'.tr(args: args),
            excludeSemantics: true,
            child: Text(
              'file.viewerCounter'.tr(args: args),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _AwImageViewerPage extends ConsumerWidget {
  const _AwImageViewerPage({
    required this.fileId,
    required this.transform,
    required this.onDoubleTapDown,
    required this.onDoubleTap,
  });

  final String fileId;
  final TransformationController transform;
  final GestureTapDownCallback onDoubleTapDown;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // WATCH, never read: `fileUrlResultProvider` is autoDispose, and a `read`
    // of an autoDispose family creates the element and tears it straight back
    // down (files_screen.dart's own warning). The underlying FileUrlCache is
    // not autoDispose, so paging back re-uses the memoized future — an
    // off-screen dispose costs a rebuild, not a round trip.
    final result = ref.watch(fileUrlResultProvider(fileId));

    return InteractiveViewer(
      transformationController: transform,
      maxScale: kAwViewerMaxScale,
      child: GestureDetector(
        onDoubleTapDown: onDoubleTapDown,
        onDoubleTap: onDoubleTap,
        // Opaque + expand: the whole page is double-tappable and pannable,
        // not just the letterboxed image rectangle. It also keeps the child
        // exactly viewport-sized, so zooming about an interior point can never
        // push it outside InteractiveViewer's default zero boundary margin.
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: Center(
            child: result.when(
              loading: () => const CircularProgressIndicator(),
              // urlFor never throws, so this arm is belt-and-braces.
              error: (error, _) => _unavailable(
                context,
                ref,
                errorCode: error is ApiException ? error.code : null,
              ),
              data: (value) {
                final url = value.url;
                if (url == null) {
                  return _unavailable(context, ref, errorCode: value.errorCode);
                }
                return Image(
                  image: ref.watch(networkImageProvider)(url),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const CircularProgressIndicator(),
                  // The link minted fine and the bytes still failed — a
                  // different fact from "there is no link" (A8).
                  errorBuilder: (context, _, _) => AwEmptyState(
                    icon: Icons.broken_image_outlined,
                    title: 'file.mediaUnavailable'.tr(),
                    message: 'file.viewerImageFailed'.tr(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// A8: failure states a reason. Before OPH-245 all six of these arrived as
  /// the same `file.couldNotOpen`, because [FileUrlCache] caught the code and
  /// threw it away.
  Widget _unavailable(
    BuildContext context,
    WidgetRef ref, {
    required String? errorCode,
  }) {
    if (errorCode == 'NETWORK_ERROR') {
      return _reason(Icons.cloud_off_outlined, 'file.viewerOffline'.tr());
    }
    if (errorCode == 'FILE_NOT_FOUND' || errorCode == 'HTTP_404') {
      return _reason(
        Icons.image_not_supported_outlined,
        'file.viewerGone'.tr(),
      );
    }
    if (errorCode != null) {
      // Anything the server names that we have not special-cased still
      // localizes, through the app-wide mapper.
      return _reason(
        Icons.error_outline,
        localizedError(ApiException(errorCode, '')),
      );
    }
    // No code at all: the server answered, it just had no link to give.
    final storage = ref.watch(storageStatusProvider).value;
    if (storage != null && !storage.configured) {
      return _reason(Icons.cloud_off_outlined, 'file.notConfigured'.tr());
    }
    return _reason(Icons.hourglass_empty, 'file.viewerNotReady'.tr());
  }

  Widget _reason(IconData icon, String message) => AwEmptyState(
    icon: icon,
    title: 'file.mediaUnavailable'.tr(),
    message: message,
  );
}
