// Runtime configuration for the web build.
//
// This file is intentionally (almost) empty: local and CI builds take the API
// address from `--dart-define=ALLISWELL_API_URL=…`, compiled into the bundle.
//
// The published `alliswell-web` Docker image REWRITES this file at container
// start from its ALLISWELL_API_URL environment variable, which is what lets one
// prebuilt image serve any self-hoster's own domain without rebuilding Flutter.
// See docs/SELF-HOSTING.md.
//
//   window.ALLISWELL_API_URL = "https://api.your-domain.example";
