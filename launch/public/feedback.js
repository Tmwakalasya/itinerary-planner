(function () {
  "use strict";
  const form = document.getElementById("survey");
  const status = form.querySelector(".status");
  const button = form.querySelector('button[type="submit"]');

  // The app's link says which trip and which build this is about.
  const params = new URLSearchParams(location.search);
  const trip = (params.get("trip") || "").slice(0, 80);
  const version = (params.get("v") || "").slice(0, 40);
  if (trip) {
    form.city.value = trip;
    document.getElementById("title").textContent = "How did it hold up in " + trip + "?";
  }
  if (version) {
    form.app_version.value = version;
    document.getElementById("build").textContent = "Build " + version;
  }

  const value = (name) => {
    const field = form.elements[name];
    if (!field) return "";
    if (field instanceof RadioNodeList) return field.value;
    return field.value.trim();
  };

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    status.textContent = "";
    const answers = {
      city: value("city"),
      app_version: value("app_version"),
      planned_day: value("planned_day"),
      used_today: value("used_today"),
      leave_by_accuracy: value("leave_by_accuracy") ? Number(value("leave_by_accuracy")) : "",
      plan_broke: value("plan_broke"),
      confusing: value("confusing"),
      next_trip: value("next_trip"),
      one_thing: value("one_thing"),
      email: value("email"),
      company: value("company"),
    };
    const answered = ["planned_day", "used_today", "leave_by_accuracy", "plan_broke", "confusing", "next_trip", "one_thing"]
      .some((k) => answers[k] !== "");
    if (!answered) {
      status.textContent = "Answer at least one question first.";
      return;
    }

    button.disabled = true;
    button.textContent = "Sending";
    try {
      const response = await fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(answers),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error || "That didn't go through. Try again in a minute.");
      form.hidden = true;
      const thanks = document.getElementById("thanks");
      thanks.hidden = false;
      thanks.scrollIntoView({ behavior: "smooth", block: "center" });
    } catch (error) {
      status.textContent = error.message && error.message !== "Failed to fetch"
        ? error.message : "That didn't go through. Check your connection and try again.";
      button.disabled = false;
      button.textContent = "Send answers";
    }
  });
})();
