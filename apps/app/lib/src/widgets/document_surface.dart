import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes where a document owns the whole screen (OPH-271).
///
/// A note being read or written — and the markdown import preview, which is
/// the same thing one tap before it becomes a note — takes the screen and the
/// attention. Nothing floats over one: not the section FAB, not the AI button,
/// not the quick-access bubble. Someone writing is not shopping for a second
/// thing to start.
///
/// Path-shaped rather than a list of literals, because the editor already has
/// four entry points (`/notes/new`, `/notes/file`, `/notes/:id`, and the
/// easily-missed `/edit-note/:id`) and a literal list would rot at the fifth.
/// `/notes` itself — the list — is not one of them.
///
/// **Why not a provider the screen raises.** That was tried first and is not
/// available: Riverpod forbids writing to a provider from `initState`, and
/// deferring the write to a post-frame callback would flash the buttons for a
/// frame on the way in. The route is already the truth here, and it is knowable
/// before the first frame.
bool awIsDocumentRoute(String path) {
  if (path.startsWith('/edit-note/')) return true;
  if (!path.startsWith('/notes/')) return false;
  return path.length > '/notes/'.length;
}

/// Rebuilds [builder] whenever navigation changes, telling it whether a
/// document currently owns the screen.
///
/// For the layers that sit ABOVE the Router — the quick-access bubble wraps the
/// whole app — where `GoRouterState.of` cannot reach: it needs a `ModalRoute`
/// ancestor and there is none up there. The delegate is a `Listenable`, so this
/// follows navigation without polling.
class AwDocumentRouteBuilder extends StatelessWidget {
  const AwDocumentRouteBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool isDocument) builder;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    // No router (a widget test pumping this surface directly) means no route
    // to be on, and a bubble that hides itself there would be a worse lie.
    if (router == null) return builder(context, false);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => builder(
        context,
        awIsDocumentRoute(router.routerDelegate.currentConfiguration.uri.path),
      ),
    );
  }
}
