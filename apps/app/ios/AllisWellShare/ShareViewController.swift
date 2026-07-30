//
//  ShareViewController.swift
//  AllisWellShare — the iOS Share Extension (OPH-225, ADR-0023).
//
//  Deliberately EMPTY beyond the plugin subclass. The extension does ZERO work
//  of its own: it hands the shared text/URL to the AllisWell app through the
//  App Group and redirects. Every AI/network decision stays in the app, which
//  makes "the share sheet never talks to a model" a structural fact, not a
//  promise — this process has no code that could. v1: text and URLs only.
//
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    // Default shouldAutoRedirect() == true → no compose UI; the app opens with
    // the payload and the user chooses what to do there (task/note/summarize/
    // ask, or just save to Inbox).
}
