// Custom Flutter bootstrap.
//
// The only reason this file exists is `fontFallbackBaseUrl`. Beyond the three
// typefaces the console bundles itself, the Flutter engine fetches two more on
// its own account — Roboto, as the default family for any text that names no
// font, and a Noto symbols face it loads eagerly as a fallback. Both go to
// fonts.gstatic.com, which a table device on a closed shop-floor LAN cannot
// reach (SRS 2.6). Pointing the engine at a local mirror means the whole
// application — engine, CanvasKit, and every glyph it can draw — is served from
// the same host as the app itself.
//
// The mirrored files live in web/fallback-fonts/ and their paths carry the
// engine's own version stamps (roboto/v32/…). A Flutter upgrade can change
// those, at which point the engine asks for a file that is not there and falls
// back to the bundled faces — the console still renders, it just loses the
// symbol coverage. If you upgrade Flutter, reload the app with the network
// panel open and re-mirror anything that 404s.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: "fallback-fonts/",
  },
});
