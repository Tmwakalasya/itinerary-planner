(function () {
  "use strict";
  const root = document.documentElement;
  root.classList.add("js");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  // Set in <head> before first paint, so the hero waits for the intro.
  const introMs = root.classList.contains("intro-on") ? 1450 : 0;
  if (introMs) setTimeout(() => { const el = document.querySelector(".intro"); if (el) el.remove(); }, 2200);

  /* ---------- Hero route: stops pop as the line reaches them ---------- */
  const route = document.getElementById("mainRoute");
  const stops = document.getElementById("stops");
  const ns = "http://www.w3.org/2000/svg";
  if (route && route.getTotalLength) {
    const total = route.getTotalLength();
    [0.17, 0.39, 0.86].forEach((f, i) => {
      const p = route.getPointAtLength(total * f);
      const ring = document.createElementNS(ns, "circle");
      ring.setAttribute("class", "ring"); ring.setAttribute("cx", p.x); ring.setAttribute("cy", p.y); ring.setAttribute("r", 13);
      const dot = document.createElementNS(ns, "circle");
      dot.setAttribute("class", "stop"); dot.setAttribute("cx", p.x); dot.setAttribute("cy", p.y); dot.setAttribute("r", 13);
      stops.append(ring, dot);
      // The line is drawn over 2.1s after .35s; ease-out reaches f a bit early.
      const at = reduce ? 0 : introMs + 350 + 2100 * Math.pow(f, 1.35);
      setTimeout(() => { dot.classList.add("in"); if (i === 1) ring.classList.add("in"); }, at);
    });
  }

  /* ---------- Live times on the hero phone ---------- */
  const fmt = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });
  const dateFmt = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" });
  const MIN = 60000;
  const now0 = new Date();
  // Live through the afternoon; later, the times would run into the night.
  const daytime = now0.getHours() >= 8 && now0.getHours() < 16;
  let leave;
  if (daytime) {
    // Leave-by about half an hour from now, on a five-minute mark.
    leave = new Date(Math.ceil((now0.getTime() + 32 * MIN) / (5 * MIN)) * 5 * MIN);
  } else {
    leave = new Date(now0); leave.setHours(13, 10, 0, 0);
  }
  const start = new Date(leave.getTime() + 35 * MIN);
  const times = {
    s1: new Date(leave.getTime() - 250 * MIN),
    s2: new Date(leave.getTime() - 130 * MIN),
    s3: start,
    s4: new Date(start.getTime() + 165 * MIN),
    leave: leave,
    start: start
  };
  document.querySelectorAll("[data-live]").forEach((el) => {
    const key = el.dataset.live;
    if (times[key]) el.textContent = fmt.format(times[key]);
    if (key === "date" && daytime) el.textContent = dateFmt.format(now0);
  });
  const countdown = document.querySelector('[data-live="countdown"]');
  let shown = null;
  function tickCountdown() {
    const left = daytime ? Math.ceil((leave.getTime() - Date.now()) / MIN) : 32;
    const text = left > 0 ? "Leave in " + left + " min" : "Time to go";
    if (text !== shown) {
      countdown.textContent = text;
      countdown.classList.toggle("now", left <= 0);
      if (shown !== null && !reduce) { countdown.classList.remove("tick"); void countdown.offsetWidth; countdown.classList.add("tick"); }
      shown = text;
    }
  }
  tickCountdown();
  setInterval(tickCountdown, 5000);

  /* ---------- Hero phone follows the pointer ---------- */
  const tilt = document.getElementById("tilt");
  const hero = document.querySelector(".hero");
  if (!reduce && window.matchMedia("(pointer: fine)").matches) {
    let raf = 0, tx = 0, ty = 0;
    hero.addEventListener("pointermove", (e) => {
      const r = hero.getBoundingClientRect();
      tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
      ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
      if (!raf) raf = requestAnimationFrame(() => {
        tilt.style.transform = "rotateY(" + (tx * 9).toFixed(2) + "deg) rotateX(" + (-ty * 7).toFixed(2) + "deg)";
        raf = 0;
      });
    });
    hero.addEventListener("pointerleave", () => { tilt.style.transform = ""; });
    const spot = hero.querySelector(".spot");
    hero.addEventListener("pointermove", (e) => {
      const r = hero.getBoundingClientRect();
      spot.style.setProperty("--mx", (e.clientX - r.left) + "px");
      spot.style.setProperty("--my", (e.clientY - r.top) + "px");
    });

    /* Buttons lean toward the pointer. */
    document.querySelectorAll(".go, .nav-cta").forEach((b) => {
      b.addEventListener("pointermove", (e) => {
        const r = b.getBoundingClientRect();
        const x = (e.clientX - r.left - r.width / 2) * 0.22;
        const y = (e.clientY - r.top - r.height / 2) * 0.3;
        b.style.transform = "translate(" + x.toFixed(1) + "px, " + y.toFixed(1) + "px)";
      });
      b.addEventListener("pointerleave", () => { b.style.transform = ""; });
    });
  }

  /* ---------- Reveal on scroll ---------- */
  const reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !reduce) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px" });
    reveals.forEach((el) => io.observe(el));
    // Never leave anything hidden if the observer is slow to report.
    setTimeout(() => reveals.forEach((el) => el.classList.add("in")), 4000);
  } else {
    reveals.forEach((el) => el.classList.add("in"));
  }

  const cta = document.querySelector(".cta");
  if ("IntersectionObserver" in window && !reduce) {
    const ctaIO = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) { cta.classList.add("drawn"); ctaIO.disconnect(); }
    }, { threshold: 0.35 });
    ctaIO.observe(cta);
  } else {
    cta.classList.add("drawn");
  }

  /* ---------- The story phones ---------- */
  const tpl = document.getElementById("storyPhone");
  const ROW = 66;
  const before = ["ggb", "pfa", "ferry", "ladies", "moma"];
  const after = ["ggb", "pfa", "ferry", "moma", "ladies"];
  const moved = ["ferry", "moma", "ladies"];

  function makePhone(slot, onMode) {
    slot.append(tpl.content.cloneNode(true));
    const root = slot.querySelector(".phone");
    const layers = root.querySelectorAll(".layer");
    const timers = [];
    const later = (fn, ms) => timers.push(setTimeout(fn, reduce ? 0 : ms));
    const clear = () => { while (timers.length) clearTimeout(timers.pop()); };
    let mode = "transit", autoFlip = null, current = -1;

    const plan = root.querySelector(".plan");
    const fix = root.querySelector(".fix");
    const go = root.querySelector(".go-scr");
    const rows = {};
    fix.querySelectorAll(".frow").forEach((r) => { rows[r.dataset.id] = r; });
    const place = (order) => order.forEach((id, i) => { rows[id].style.transform = "translateY(" + (i * ROW) + "px)"; });
    place(before);

    const press = (el) => { el.classList.remove("press"); void el.offsetWidth; el.classList.add("press"); };

    function playPlan() {
      plan.classList.remove("play");
      later(() => press(plan.querySelector("[data-press]")), 350);
      later(() => plan.classList.add("play"), 700);
    }
    function playFix() {
      fix.classList.remove("fixed", "toasted");
      Object.values(rows).forEach((r) => r.classList.remove("moved", "lift"));
      place(before);
      later(() => press(fix.querySelector("[data-press]")), 1100);
      later(() => {
        rows.moma.classList.add("lift");
        moved.forEach((id) => rows[id].classList.add("moved"));
        fix.classList.add("fixed");
        place(after);
      }, 1500);
      later(() => { rows.moma.classList.remove("lift"); fix.classList.add("toasted"); }, 2500);
    }
    function setMode(m) {
      mode = m;
      go.classList.toggle("car", m === "car");
      if (onMode) onMode(m);
    }
    function playGo() {
      setMode("transit");
      if (reduce) return;
      autoFlip = setInterval(() => setMode(mode === "transit" ? "car" : "transit"), 2600);
    }

    return {
      show(i) {
        if (i === current) return;
        current = i;
        clear();
        clearInterval(autoFlip);
        layers.forEach((l, n) => l.classList.toggle("on", n === i));
        [playPlan, playFix, playGo][i]();
      },
      replay(i) { current = -1; this.show(i); },
      mode(m) { clearInterval(autoFlip); setMode(m); }
    };
  }

  const steps = Array.from(document.querySelectorAll(".step"));
  const modeButtons = document.querySelectorAll("[data-mode]");
  const wide = window.matchMedia("(min-width: 961px)");
  // The visible phone's mode shows on the buttons beside it.
  const syncButtons = (fromWide) => (m) => {
    if (fromWide !== wide.matches) return;
    modeButtons.forEach((x) => x.setAttribute("aria-pressed", String(x.dataset.mode === m)));
  };
  const sticky = makePhone(document.querySelector('[data-slot="sticky"]'), syncButtons(true));
  const perStep = steps.map((step, i) => {
    const p = makePhone(step.querySelector('[data-slot="' + i + '"]'), i === 2 ? syncButtons(false) : null);
    p.show(i);
    return p;
  });
  sticky.show(0);

  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return;
        const i = Number(e.target.dataset.step);
        if (wide.matches) sticky.show(i); else perStep[i].replay(i);
      });
    }, { rootMargin: "-45% 0px -45% 0px" });
    steps.forEach((s) => io.observe(s));
  }

  /* A route down the side of the story, drawn as you scroll. */
  const stepsBox = document.querySelector(".steps");
  const spine = stepsBox.querySelector(".spine");
  const [spineBase, spineLit] = spine.querySelectorAll("path");
  let spineDots = [], ys = [];
  function layoutSpine() {
    const h = stepsBox.offsetHeight;
    // .steps is the offset parent of each step's number.
    ys = steps.map((s) => s.querySelector(".num").offsetTop + 8);
    let d = "M20 " + ys[0];
    for (let i = 1; i < ys.length; i++) {
      const a = ys[i - 1], b = ys[i], m = (a + b) / 2;
      d += " C 20 " + (a + (m - a) * 0.6) + ", " + (i % 2 ? 36 : 4) + " " + (m - (m - a) * 0.2) + ", " + (i % 2 ? 36 : 4) + " " + m;
      d += " S 20 " + (b - (b - m) * 0.4) + ", 20 " + b;
    }
    d += " L 20 " + (h - 40);
    spine.setAttribute("viewBox", "0 0 40 " + h);
    spine.setAttribute("height", h);
    spineBase.setAttribute("d", d);
    spineLit.setAttribute("d", d);
    spineDots.forEach((c) => c.remove());
    spineDots = ys.map((y) => {
      const c = document.createElementNS(ns, "circle");
      c.setAttribute("cx", 20); c.setAttribute("cy", y); c.setAttribute("r", 8);
      spine.append(c);
      return c;
    });
    paintSpine();
  }
  function paintSpine() {
    const r = stepsBox.getBoundingClientRect();
    const reach = window.innerHeight * 0.5 - r.top;
    const progress = Math.max(0, Math.min(1, reach / r.height));
    spineLit.style.strokeDashoffset = String(1 - progress);
    spineDots.forEach((c, i) => c.classList.toggle("on", reach >= ys[i]));
  }

  const cityRow = document.querySelector(".cities-row");
  function paintCities() {
    if (reduce) return;
    const r = cityRow.parentElement.getBoundingClientRect();
    const shift = (window.innerHeight - r.top) * Number(cityRow.dataset.speed || 0.3);
    cityRow.style.transform = "translateX(" + (-shift).toFixed(1) + "px)";
  }

  let ticking = false;
  window.addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { paintSpine(); paintCities(); ticking = false; });
  }, { passive: true });
  window.addEventListener("resize", layoutSpine);
  window.addEventListener("load", layoutSpine);
  layoutSpine();
  paintCities();

  document.querySelectorAll("[data-replay]").forEach((b) => b.addEventListener("click", () => {
    const i = Number(b.dataset.replay);
    (wide.matches ? sticky : perStep[i]).replay(i);
  }));
  modeButtons.forEach((b) => b.addEventListener("click", () => {
    sticky.mode(b.dataset.mode);
    perStep[2].mode(b.dataset.mode);
  }));

  /* ---------- Signup ---------- */
  const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

  function burst(from) {
    if (reduce || !from.animate) return;
    const r = from.getBoundingClientRect();
    const colors = ["#FFFFFF", "#FF9AB0", "#FFD1DC", "#FF385C"];
    for (let n = 0; n < 26; n++) {
      const s = document.createElement("span");
      s.className = "spark";
      s.style.left = r.left + r.width / 2 + "px";
      s.style.top = r.top + r.height / 2 + "px";
      s.style.background = colors[n % colors.length];
      document.body.append(s);
      const angle = Math.random() * Math.PI * 2;
      const dist = 60 + Math.random() * 110;
      s.animate([
        { transform: "translate(-50%, -50%) scale(1)", opacity: 1 },
        { transform: "translate(" + (Math.cos(angle) * dist - 4) + "px, " + (Math.sin(angle) * dist - 4) + "px) scale(.2)", opacity: 0 }
      ], { duration: 700 + Math.random() * 500, easing: "cubic-bezier(.2,.8,.2,1)" }).onfinish = () => s.remove();
    }
  }

  document.querySelectorAll("form.signup").forEach((form) => {
    const input = form.querySelector('input[name="email"]');
    const trap = form.querySelector('input[name="company"]');
    const button = form.querySelector(".go");
    const label = button.querySelector(".label");
    const status = form.querySelector(".status");
    const field = form.querySelector(".field");

    function fail(message) {
      status.textContent = message;
      field.classList.remove("shake"); void field.offsetWidth; field.classList.add("shake");
      input.focus();
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const email = input.value.trim();
      status.textContent = "";
      if (!EMAIL.test(email)) return fail("Check your email address. It should look like you@email.com.");

      button.disabled = true;
      label.textContent = "Adding you";
      const spin = document.createElement("span"); spin.className = "spin"; spin.setAttribute("aria-hidden", "true");
      button.querySelector("svg").replaceWith(spin);
      try {
        const response = await fetch("/api/signup", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email: email, company: trap.value })
        });
        const body = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(body.error || "That didn't go through. Try again in a minute.");
        burst(button);
        form.classList.add("done");
        document.querySelectorAll("form.signup").forEach((other) => { if (other !== form) other.classList.add("done"); });
      } catch (error) {
        fail(error.message && error.message !== "Failed to fetch" ? error.message : "That didn't go through. Check your connection and try again.");
      } finally {
        button.disabled = false;
        label.textContent = "Get the beta";
        const arrow = document.createElementNS(ns, "svg");
        arrow.setAttribute("width", "16"); arrow.setAttribute("height", "16"); arrow.setAttribute("viewBox", "0 0 24 24");
        arrow.setAttribute("fill", "none"); arrow.setAttribute("stroke", "currentColor"); arrow.setAttribute("stroke-width", "2.4");
        arrow.setAttribute("stroke-linecap", "round"); arrow.setAttribute("stroke-linejoin", "round"); arrow.setAttribute("aria-hidden", "true");
        arrow.innerHTML = '<path d="M5 12h14M13 6l6 6-6 6"/>';
        spin.replaceWith(arrow);
      }
    });
  });
})();
