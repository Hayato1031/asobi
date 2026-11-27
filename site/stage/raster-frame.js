// The stage's rasteriser, in a sandboxed iframe that Chrome puts in a process
// of its own (far-raster.js). It turns svg Blobs (a frame of a checked Reel,
// made by the stage's worker) into ImageBitmaps and hands them back. Every svg
// drawn as an image is a whole document (page, frame, DOM); making and tearing
// down hundreds of them per Reel here, not in the stage, means their garbage
// collection never stops the stage's 3D frames.
//   in:  { id, blob, flip }   out: { id, bitmap } (transferred) or { id, error }
// The markup only ever becomes an image (a blob: URL of type image/svg+xml).
(function () {
  "use strict";
  addEventListener("message", function (e) {
    if (e.source !== parent) return;
    var d = e.data || {};
    if (typeof d.id !== "number" || !(d.blob instanceof Blob) || d.blob.type !== "image/svg+xml") return;
    var url = URL.createObjectURL(d.blob);
    var img = new Image();
    img.decoding = "async";
    img.src = url;
    img.decode()
      .then(function () {
        // Upside down for WebGL when asked (the 3D frames); premultiplied, as the stage uploads them.
        return createImageBitmap(img, { imageOrientation: d.flip ? "flipY" : "from-image", premultiplyAlpha: "premultiply" });
      })
      .then(function (bitmap) { parent.postMessage({ id: d.id, bitmap: bitmap }, "*", [bitmap]); },
            function (err) { parent.postMessage({ id: d.id, error: String(err && err.name || err) }, "*"); })
      .then(function () { URL.revokeObjectURL(url); img.src = ""; });
  });
  parent.postMessage({ ready: true }, "*");
})();
