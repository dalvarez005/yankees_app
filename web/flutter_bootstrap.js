{{flutter_js}}
{{flutter_build_config}}

// Motor gráfico servido desde nuestro dominio (no desde gstatic.com): así
// queda guardado por el service worker y la app abre sin internet.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});

// Service worker propio (sw.js): guarda la app para abrirla al instante.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", function () {
    navigator.serviceWorker.register("sw.js").catch(function (e) {
      console.warn("No se pudo registrar el service worker", e);
    });
  });
}
