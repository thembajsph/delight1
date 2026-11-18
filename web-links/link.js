// Shared by /rsvp/<id> and /pay/<id>. If the app is installed Android/iOS open it
// before this page ever loads (App Links). This page is what everyone else sees:
// it tries the app once, and otherwise offers the store.
(function () {
  var C = window.DELIGHT, parts = location.pathname.split("/").filter(Boolean);
  var kind = parts[0], id = parts[1] || "";
  var ua = navigator.userAgent, android = /Android/i.test(ua), ios = /iPhone|iPad|iPod/i.test(ua);
  var store = ios ? C.appStore : C.playStore;
  var appUrl = "delight:///" + kind + "/" + id + location.search;
  var $ = function (i) { return document.getElementById(i); };

  $("open").href = appUrl;
  $("store").href = store;
  $("store").textContent = ios ? "Download on the App Store" : "Get it on Google Play";

  // Try the app once; if the page is still visible shortly after, it is not installed.
  if (android || ios) {
    var t = Date.now();
    setTimeout(function () {
      if (document.visibilityState === "visible" && Date.now() - t < 2500) {
        $("hint").textContent = "Don't have the app yet? Install it, then tap this link again.";
      }
    }, 1500);
    location.href = android
      ? "intent:///" + kind + "/" + id + location.search +
        "#Intent;scheme=delight;package=africa.delight.app;S.browser_fallback_url=" +
        encodeURIComponent(store) + ";end"
      : appUrl;
  }

  // Show who is inviting, without needing the app (public RPC).
  if (kind === "rsvp" && id && C.supabaseAnonKey.indexOf("PASTE") < 0) {
    fetch(C.supabaseUrl + "/rest/v1/rpc/get_private_event_invite", {
      method: "POST",
      headers: { "apikey": C.supabaseAnonKey, "Authorization": "Bearer " + C.supabaseAnonKey,
                 "Content-Type": "application/json" },
      body: JSON.stringify({ p_id: id })
    }).then(function (r) { return r.json(); }).then(function (e) {
      if (!e || !e.name) return;
      $("title").textContent = "You're invited to " + e.name;
      var d = e.event_date ? new Date(e.event_date).toLocaleString([], { dateStyle: "full", timeStyle: "short" }) : "";
      $("sub").textContent = [d, e.venue, e.city].filter(Boolean).join(" · ");
    }).catch(function () {});
  }
})();
