import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/firebase/firebase_bootstrap.dart';

/// Which provider a sign-in came from.
enum SocialProvider {
  google('google'),
  apple('apple');

  const SocialProvider(this.wire);

  /// What `POST /auth/oauth` expects in its `provider` field.
  final String wire;
}

/// Raised when the user backs out. Not an error to show — the caller just stops.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Raised when the provider itself failed. [message] is safe to show.
class SocialSignInFailed implements Exception {
  const SocialSignInFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google and Apple sign-in, reduced to the one thing our server needs: an
/// **ID token** (ADR-0026).
///
/// The division of labour is deliberate and worth stating, because the obvious
/// alternative is wrong for this product:
///
/// * The **provider** proves who the human is.
/// * **Our API** decides which AllisWell account that is, and issues the session.
/// * **Firebase Auth** is signed into as well, but only so Crashlytics and
///   Analytics can attribute reports to a user. It is never the credential our
///   API trusts, and everything here works with Firebase absent — which is the
///   normal state for a self-hoster (ADR-0025).
///
/// That last point is the reason this class hands back a *provider* ID token
/// rather than a Firebase one: a Firebase token can only be verified by a server
/// that has been told about the Firebase project, and most servers running this
/// code never will be.
class SocialSignIn {
  SocialSignIn({GoogleSignIn? google})
    : _google = google ?? GoogleSignIn.instance;

  final GoogleSignIn _google;
  bool _googleReady = false;

  /// Whether Apple's button may be shown at all.
  ///
  /// Apple requires "Sign in with Apple" wherever another social login is
  /// offered — but only on its own platforms. Showing it on Android would offer
  /// a flow that needs a web round-trip we have not configured a Services ID
  /// for, so it stays hidden there rather than failing on tap.
  static bool get appleAvailable {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  /// Sign in with Google and return the ID token.
  Future<String> googleIdToken() async {
    try {
      if (!_googleReady) {
        // v7 requires an explicit initialize. The per-platform client ids come
        // from the native config files, which is why none of them appear here.
        //
        // `serverClientId` is the WEB client id, and it is what decides the
        // `aud` claim of the token our server then verifies. Without it the
        // audience differs per platform — the iOS client on iOS, the default
        // web client on Android — so the server would need every id configured
        // and would still be guessing. With it, one audience covers every
        // platform: SIGN_IN_GOOGLE_WEB_CLIENT_ID.
        //
        // Empty by default so the repo carries no identifier; pass it at build
        // time (--dart-define) and the SDK otherwise falls back to the web
        // client in the platform config file.
        const serverClientId = String.fromEnvironment(
          'GOOGLE_SERVER_CLIENT_ID',
        );
        await _google.initialize(
          serverClientId: serverClientId.isEmpty ? null : serverClientId,
        );
        _googleReady = true;
      }
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const SocialSignInFailed(
          'Google did not return an identity token',
        );
      }
      await _linkFirebase(fb.GoogleAuthProvider.credential(idToken: idToken));
      return idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInFailed(error.description ?? 'Google sign-in failed');
    }
  }

  /// Sign in with Apple and return the ID token.
  Future<String> appleIdToken() async {
    // Apple binds the token to a nonce. We send the SHA-256 of a fresh random
    // value and Apple echoes the raw one back inside the token, which is what
    // makes a stolen token useless for replay somewhere else.
    final rawNonce = _randomNonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const SocialSignInFailed(
          'Apple did not return an identity token',
        );
      }
      await _linkFirebase(
        fb.OAuthProvider(
          'apple.com',
        ).credential(idToken: idToken, rawNonce: rawNonce),
      );
      return idToken;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInFailed(error.message);
    }
  }

  /// Mirror the sign-in into Firebase Auth, if Firebase is even here.
  ///
  /// Deliberately swallowing: this exists so a crash report can say *which*
  /// user it happened to. Failing the whole sign-in because an analytics
  /// side-effect did not work would be exactly backwards.
  Future<void> _linkFirebase(fb.AuthCredential credential) async {
    if (!AwFirebase.isConfigured) return;
    try {
      await fb.FirebaseAuth.instance.signInWithCredential(credential);
    } on Object catch (error) {
      debugPrint('AllisWell: Firebase Auth mirror failed, continuing ($error)');
    }
  }

  /// Sign out of the provider sessions. The AllisWell session is cleared by the
  /// auth repository; this stops the provider from silently re-authenticating.
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } on Object {
      /* never signed in with Google */
    }
    if (AwFirebase.isConfigured) {
      try {
        await fb.FirebaseAuth.instance.signOut();
      } on Object {
        /* nothing to sign out of */
      }
    }
  }

  static String _randomNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
