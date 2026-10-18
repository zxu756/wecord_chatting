// Flutter's loader, with two WeCord additions (the {{...}} parts are filled
// in by `flutter build web`):
// - CanvasKit comes from this site's own /canvaskit/ (same files the build
//   already ships) instead of gstatic.com, so the service worker can keep it
//   for offline starts and it loads from the same CDN as the app.
// - The HTML splash in index.html (window.wecordSplash) is told how far the
//   start has got; it goes away on Flutter's first frame.
//
// Flutter's own service worker is deliberately not registered: WeCord's is
// wecord_sw.js, registered from index.html.
{{flutter_js}}
{{flutter_build_config}}

(function () {
  var splash = window.wecordSplash || { stage: function () {} };
  var config = {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
  };
  splash.stage(0.35);
  _flutter.loader.load({
    config: config,
    onEntrypointLoaded: async function (engineInitializer) {
      // main.dart.js has downloaded and run.
      splash.stage(0.7);
      var appRunner = await engineInitializer.initializeEngine(config);
      splash.stage(0.9);
      await appRunner.runApp();
    },
  });
})();
