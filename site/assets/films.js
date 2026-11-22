/* asobi home: the films.
 * The films of each version are on the page, one under the other. With this
 * script they become tabs: one film in view, and a row of small posters to switch.
 * Switching pauses the film that leaves. A link to #film-<id> opens that film.
 */
(function () {
  "use strict";
  var section = document.getElementById("films");
  var list = section && section.querySelector(".film-tabs");
  if (!list) return;
  var tabs = Array.prototype.slice.call(list.querySelectorAll('[role="tab"]'));
  function panel(tab) { return document.getElementById(tab.getAttribute("aria-controls")); }

  function select(tab, focus) {
    tabs.forEach(function (other) {
      var on = other === tab, p = panel(other), video = p.querySelector("video");
      other.setAttribute("aria-selected", on ? "true" : "false");
      other.tabIndex = on ? 0 : -1;
      p.hidden = !on;
      if (!on && video && !video.paused) video.pause();
    });
    if (focus) tab.focus();
  }
  function fromHash() {
    var id = location.hash.slice(1);
    var tab = tabs.filter(function (t) { return t.getAttribute("aria-controls") === id; })[0];
    if (tab) { select(tab, false); section.scrollIntoView(); }
  }

  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { select(tab, false); });
    tab.addEventListener("keydown", function (e) {
      var to = e.key === "ArrowRight" ? i + 1 : e.key === "ArrowLeft" ? i - 1 : e.key === "Home" ? 0 : e.key === "End" ? tabs.length - 1 : null;
      if (to === null) return;
      e.preventDefault();
      select(tabs[(to + tabs.length) % tabs.length], true);
    });
  });
  list.hidden = false;
  select(tabs[0], false);
  fromHash();
  window.addEventListener("hashchange", fromHash);
})();
