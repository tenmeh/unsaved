(function () {
  "use strict";
  var states = Object.create(null);
  var marks = new Map();
  var serial = 0;
  var bypass = false;
  var dialog = null;
  var unloadActive = false;
  var saveRequests = Object.create(null);
  var selector = 'a[data-toggle="tab"],a[data-bs-toggle="tab"],button[data-toggle="tab"],'
    + 'button[data-bs-toggle="tab"],a[data-toggle="pill"],a[data-bs-toggle="pill"]';

  function state(id) {
    return states[id] || (states[id] = {
      ids: [], guardNav: false, guardUnload: false, inputs: {}
    });
  }

  function reportTabs(inputId) {
    var ids = Array.from(document.querySelectorAll(".shiny-tab-input"))
      .map(function (el) { return el.id; })
      .filter(Boolean);
    window.Shiny.setInputValue(inputId, ids, {priority: "event"});
  }

  function dirtyIds() {
    var ids = new Set();
    Object.keys(states).forEach(function (id) {
      states[id].ids.forEach(function (x) {
        ids.add(x);
      });
    });
    return ids;
  }

  function unmark(record) {
    record.container.removeAttribute("data-unsaved");
    record.label.classList.remove("unsaved-marker");
    record.text.remove();
    var descriptions = (record.el.getAttribute("aria-describedby") || "").split(/\s+/)
      .filter(function (x) { return x && x !== record.text.id; });
    if (descriptions.length) {
      record.el.setAttribute("aria-describedby", descriptions.join(" "));
    } else {
      record.el.removeAttribute("aria-describedby");
    }
  }

  function reconcile() {
    var ids = dirtyIds();
    marks.forEach(function (record, id) {
      if (!ids.has(id) || document.getElementById(id) !== record.el) {
        unmark(record);
        marks.delete(id);
      }
    });
    ids.forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      var container = el.closest(".shiny-input-container") || el.closest(".form-group") || el.parentElement;
      if (!container) return;
      var label = container.querySelector(":scope > label") ||
        container.querySelector(":scope > label.control-label") || container.querySelector("label") || container;
      var old = marks.get(id);
      if (old && (old.label !== label || !old.text.isConnected)) {
        unmark(old);
        marks.delete(id);
      }
      container.setAttribute("data-unsaved", "true");
      label.classList.add("unsaved-marker");
      if (!marks.has(id)) {
        var text = document.createElement("span");
        text.className = "unsaved-sr";
        text.id = "unsaved-description-" + (++serial);
        text.textContent = "(unsaved)";
        container.appendChild(text);
        el.setAttribute("aria-describedby", ((el.getAttribute("aria-describedby") || "") + " " + text.id).trim());
        marks.set(id, {el: el, container: container, label: label, text: text});
      }
    });
    document.querySelectorAll(".unsaved-badge").forEach(function (badge) {
      badge.textContent = ids.size ? (badge.getAttribute("data-unsaved-label") || "{n} unsaved change{s}")
        .replace(/\{n\}/g, ids.size).replace(/\{s\}/g, ids.size === 1 ? "" : "s") : "";
    });
    var active = Object.keys(states).some(function (id) {
      return states[id].guardUnload && states[id].ids.length;
    });
    if (active !== unloadActive) {
      window[active ? "addEventListener" : "removeEventListener"]("beforeunload", beforeUnload);
      unloadActive = active;
    }
  }

  function beforeUnload(e) {
    e.preventDefault();
    e.returnValue = "";
  }

  function bindingValue(el, value) {
    // Date ranges expose arrays but their setter expects named endpoints.
    if (el.classList.contains("shiny-date-range-input") && Array.isArray(value)) {
      return {start: value[0], end: value[1]};
    }
    // Slider setters consume milliseconds, unlike their date/datetime getters.
    if (el.classList.contains("js-range-slider")) {
      var type = window.jQuery(el).data("data-type");
      var convert = function (x) {
        if (x === null) return x;
        if (type === "date") return Date.parse(x);
        if (type === "datetime") return Number(x) * 1000;
        return x;
      };
      return Array.isArray(value) ? value.map(convert) : convert(value);
    }
    return value;
  }

  function restore(inputs) {
    Object.keys(inputs).forEach(function (id) {
      var el = document.getElementById(id);
      if (!el || !window.jQuery || el.classList.contains("shiny-tab-input") || el.type === "file") return;
      var $el = window.jQuery(el);
      var binding = $el.data("shiny-input-binding");
      if (!binding) return;
      var value = bindingValue(el, inputs[id]);
      if (typeof binding.setValue === "function") {
        binding.setValue(el, value);
      } else if (typeof binding.receiveMessage === "function") {
        binding.receiveMessage(el, {value: value});
      }
      $el.trigger("change");
    });
  }

  function closeDialog() {
    if (!dialog) return;
    var target = dialog.target;
    dialog.backdrop.remove();
    dialog = null;
    if (target.isConnected) target.focus();
  }

  function navigate(target) {
    closeDialog();
    bypass = true;
    try {
      target.click();
    } finally {
      bypass = false;
    }
  }

  function saveReply(message) {
    var queue = saveRequests[message.instance] || [];
    var attempt = queue.shift();
    if (!attempt || dialog !== attempt.dialog || dialog.attempt !== attempt || !dialog.waiting) return;
    if (!message.ok) {
      dialog.waiting = false;
      dialog.discard.disabled = false;
      dialog.save.disabled = false;
      dialog.save.textContent = "Save and leave";
      dialog.alert.textContent = "Could not save. Your changes are still here.";
      return;
    }
    attempt.remaining.delete(message.instance);
    if (attempt.remaining.size === 0) navigate(dialog.target);
  }

  function showDialog(target, instances) {
    if (dialog) return;
    var backdrop = document.createElement("div");
    backdrop.className = "unsaved-backdrop";
    var panel = document.createElement("div");
    panel.className = "unsaved-dialog";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-modal", "true");
    var title = document.createElement("h2");
    title.id = "unsaved-dialog-title-" + (++serial);
    title.textContent = "Unsaved changes";
    panel.setAttribute("aria-labelledby", title.id);
    var count = new Set();
    instances.forEach(function (id) {
      states[id].ids.forEach(function (x) {
        count.add(x);
      });
    });
    var message = document.createElement("p");
    message.textContent = "You have " + count.size + " unsaved change" + (count.size === 1 ? "" : "s") + ".";
    var keep = document.createElement("button");
    var discard = document.createElement("button");
    keep.type = "button";
    discard.type = "button";
    keep.className = "btn btn-secondary";
    discard.className = "btn btn-danger";
    keep.textContent = "Keep editing";
    discard.textContent = "Discard changes";
    keep.addEventListener("click", closeDialog);
    discard.addEventListener("click", function () {
      // Cached baselines allow explicit discard while the server is busy.
      instances.forEach(function (id) {
        restore(states[id].inputs);
      });
      navigate(target);
    });
    // The buttons sit in one row that wraps as a whole on narrow screens.
    var actions = document.createElement("div");
    actions.className = "unsaved-dialog-actions";
    actions.append(keep, discard);
    panel.append(title, message, actions);
    var buttons = [keep, discard];
    var save = null;
    var alert = document.createElement("div");
    alert.setAttribute("role", "alert");
    if (instances.every(function (id) { return states[id].canSave; })) {
      save = document.createElement("button");
      save.type = "button";
      save.className = "btn btn-primary";
      save.textContent = "Save and leave";
      save.addEventListener("click", function () {
        if (!dialog || dialog.waiting) return;
        dialog.waiting = true;
        discard.disabled = true;
        save.disabled = true;
        save.textContent = "Saving...";
        alert.textContent = "";
        keep.focus();
        var attempt = {dialog: dialog, remaining: new Set(instances)};
        dialog.attempt = attempt;
        instances.forEach(function (id) {
          if (!saveRequests[id]) saveRequests[id] = [];
          saveRequests[id].push(attempt);
          window.Shiny.setInputValue(states[id].saveInput || "unsaved_save_requested", {
            instance: id,
            target: target.id || target.getAttribute("data-value") || target.getAttribute("href"),
            at: Date.now()
          }, {priority: "event"});
        });
      });
      actions.appendChild(save);
      buttons.push(save);
    }
    panel.appendChild(alert);
    backdrop.appendChild(panel);
    backdrop.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        e.preventDefault();
        closeDialog();
      }
      if (e.key === "Tab") {
        e.preventDefault();
        var enabled = buttons.filter(function (button) { return !button.disabled; });
        var index = enabled.indexOf(document.activeElement);
        var next = (index + (e.shiftKey ? -1 : 1) + enabled.length) % enabled.length;
        enabled[next].focus();
      }
    });
    document.body.appendChild(backdrop);
    dialog = {backdrop: backdrop, target: target, discard: discard, save: save, alert: alert, waiting: false};
    keep.focus();
  }

  function isActive(target) {
    return target.classList.contains("active") ||
      target.getAttribute("aria-selected") === "true" ||
      (target.parentElement && target.parentElement.classList.contains("active"));
  }

  function guardNavigation(e, target) {
    if (bypass || !target || isActive(target)) return;
    var instances = Object.keys(states).filter(function (id) {
      return states[id].guardNav && states[id].ids.length;
    });
    if (!instances.length) return;
    e.preventDefault();
    e.stopPropagation();
    if (!dialog) {
      instances.forEach(function (id) {
        window.Shiny.setInputValue("unsaved_nav_blocked", {
          instance: id,
          target: target.id || target.getAttribute("data-value") || target.getAttribute("href"),
          at: Date.now()
        }, {priority: "event"});
      });
      showDialog(target, instances);
    }
  }

  document.addEventListener("click", function (e) {
    if (!(e.target instanceof Element)) return;
    guardNavigation(e, e.target.closest(selector));
  }, true);

  // Bootstrap 5 emits a native event; Bootstrap 3 uses jQuery events.
  function guardTabShow(e) {
    guardNavigation(e, e.target.closest(selector));
  }
  document.addEventListener("show.bs.tab", guardTabShow, true);

  function register() {
    if (!window.Shiny || !window.Shiny.addCustomMessageHandler) return;
    window.jQuery(document).on("show.bs.tab.unsaved show.tab.unsaved", selector, guardTabShow);
    window.Shiny.addCustomMessageHandler("unsaved:config", function (message) {
      var current = state(message.instance);
      current.inputs = message.baseline || {};
      current.guardNav = message.guardNav;
      current.guardUnload = message.guardUnload;
      current.canSave = message.canSave;
      current.saveInput = message.saveInput;
      current.tabInput = message.tabInput || "unsaved_tab_ids";
      reportTabs(current.tabInput);
      reconcile();
    });
    window.Shiny.addCustomMessageHandler("unsaved:state", function (message) {
      state(message.instance).ids = message.ids || [];
      reconcile();
    });
    window.Shiny.addCustomMessageHandler("unsaved:restore", function (message) {
      state(message.instance).inputs = message.inputs || {};
      restore(message.inputs || {});
    });
    window.Shiny.addCustomMessageHandler("unsaved:saved", saveReply);
    window.jQuery(document).on("shiny:bound", function () {
      var inputs = new Set();
      Object.keys(states).forEach(function (id) {
        if (states[id].tabInput) inputs.add(states[id].tabInput);
      });
      inputs.forEach(reportTabs);
    });
    window.jQuery(document).on("shiny:disconnected", function () {
      states = Object.create(null);
      saveRequests = Object.create(null);
      closeDialog();
      reconcile();
    });
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", register);
  } else {
    register();
  }
}());
