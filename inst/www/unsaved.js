(function () {
  "use strict";
  var states = Object.create(null);
  var marks = new Map();
  var serial = 0;
  var bypass = false;
  var dialog = null;
  var unloadActive = false;
  var saveRequests = Object.create(null);
  var passwordReports = Object.create(null);
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

  function reportPasswords(inputId) {
    var ids = Array.from(document.querySelectorAll('input[type="password"][id]'))
      .map(function (el) { return el.id; }).sort();
    var key = JSON.stringify(ids);
    if (passwordReports[inputId] === key) return;
    passwordReports[inputId] = key;
    window.Shiny.setInputValue(inputId, {ids: ids}, {priority: "event"});
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
    if (record.output) record.label.remove();
    var descriptions = (record.el.getAttribute("aria-describedby") || "").split(/\s+/)
      .filter(function (x) { return x && x !== record.text.id; });
    if (descriptions.length) {
      record.el.setAttribute("aria-describedby", descriptions.join(" "));
    } else {
      record.el.removeAttribute("aria-describedby");
    }
  }

  function markerIds(current) {
    return current.ids.map(function (id) {
      if ((current.valueIds || []).indexOf(id) === -1) return id;
      return (current.valueOutputs || {})[id];
    }).filter(Boolean);
  }

  function reconcile() {
    var changed = dirtyIds();
    var ids = new Set();
    Object.keys(states).forEach(function (id) {
      markerIds(states[id]).forEach(function (x) { ids.add(x); });
    });
    marks.forEach(function (record, id) {
      if (!ids.has(id) || document.getElementById(id) !== record.el) {
        unmark(record);
        marks.delete(id);
      }
    });
    ids.forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      var output = Object.keys(states).some(function (key) {
        return Object.values(states[key].valueOutputs || {}).indexOf(id) !== -1;
      });
      var container = output ? el :
        el.closest(".shiny-input-container") || el.closest(".form-group") || el.parentElement;
      if (!container) return;
      var old = marks.get(id);
      var label = output ? (old ? old.label : document.createElement("span")) :
        container.querySelector(":scope > label") ||
        container.querySelector(":scope > label.control-label") || container.querySelector("label") || container;
      if (old && (old.label !== label || !old.text.isConnected ||
          (output && old.label.nextElementSibling !== el))) {
        unmark(old);
        marks.delete(id);
      }
      container.setAttribute("data-unsaved", "true");
      // An output is outlined by CSS on its own data-unsaved attribute, so a
      // dot never takes a row of its own or shifts the layout.
      if (!output) label.classList.add("unsaved-marker");
      if (!marks.has(id)) {
        if (output) {
          // The screen-reader text sits in a hidden sibling, which survives
          // output rendering.
          label.className = "unsaved-output-marker";
          el.before(label);
        }
        var text = document.createElement("span");
        text.className = "unsaved-sr";
        text.id = "unsaved-description-" + (++serial);
        var owner = Object.keys(states).find(function (key) { return markerIds(states[key]).indexOf(id) !== -1; });
        text.textContent = states[owner].text.unsaved;
        (output ? label : container).appendChild(text);
        el.setAttribute("aria-describedby", ((el.getAttribute("aria-describedby") || "") + " " + text.id).trim());
        marks.set(id, {el: el, container: container, label: label, text: text, output: output});
      }
    });
    document.querySelectorAll(".unsaved-badge").forEach(function (badge) {
      badge.textContent = changed.size ? (badge.getAttribute("data-unsaved-label") || "{n} unsaved change{s}")
        .replace(/\{n\}/g, changed.size).replace(/\{s\}/g, changed.size === 1 ? "" : "s") : "";
    });
    var active = Object.keys(states).some(function (id) {
      return states[id].guardUnload && (states[id].ids.length || states[id].provisional);
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
      if (!el || !window.jQuery || el.classList.contains("shiny-tab-input") ||
          el.type === "file" || el.type === "password") return;
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
      // Send the restored value before a confirmed server action runs.
      var type = binding.getType(el);
      var inputId = type ? id + ":" + type : id;
      window.Shiny.setInputValue(inputId, binding.getValue(el), {priority: "event"});
    });
  }

  function confirmReply(choice, reason) {
    if (!dialog || !dialog.confirmation) return;
    var request = dialog.confirmation;
    window.Shiny.setInputValue(states[request.instance].confirmInput, {
      instance: request.instance, token: request.token, choice: choice, reason: reason, at: Date.now()
    }, {priority: "event"});
  }

  function closeDialog(cancel) {
    if (!dialog) return;
    if (cancel !== false) confirmReply("keep");
    var target = dialog.target || dialog.previousFocus;
    dialog.backdrop.remove();
    dialog = null;
    if (target && target.isConnected) target.focus();
  }

  function navigate(target, choice) {
    confirmReply(choice || "save");
    closeDialog(false);
    if (!target) return;
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
      dialog.save.disabled = dialog.reason && !dialog.reason.value.trim();
      if (dialog.reason) dialog.reason.disabled = false;
      dialog.save.textContent = dialog.reasonOnly ? dialog.text.reason_save : dialog.text.save;
      dialog.alert.textContent = dialog.text.save_failed;
      return;
    }
    attempt.remaining.delete(message.instance);
    if (attempt.remaining.size === 0) navigate(dialog.target);
  }

  function showDialog(target, instances, confirmation) {
    if (dialog) {
      if (confirmation) {
        window.Shiny.setInputValue(states[confirmation.instance].confirmInput, {
          instance: confirmation.instance, token: confirmation.token, choice: "keep", at: Date.now()
        }, {priority: "event"});
      }
      return;
    }
    var previousFocus = document.activeElement;
    var text = states[instances[0]].text;
    var reasonOnly = confirmation && confirmation.reasonOnly;
    var needsReason = reasonOnly || instances.some(function (id) { return states[id].requireReason; });
    var backdrop = document.createElement("div");
    backdrop.className = "unsaved-backdrop";
    var panel = document.createElement("div");
    panel.className = "unsaved-dialog";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-modal", "true");
    var title = document.createElement("h2");
    title.id = "unsaved-dialog-title-" + (++serial);
    title.textContent = reasonOnly ? text.reason_title : text.title;
    panel.setAttribute("aria-labelledby", title.id);
    var count = new Set();
    instances.forEach(function (id) {
      states[id].ids.forEach(function (x) {
        count.add(x);
      });
    });
    var message = document.createElement("p");
    message.textContent = text.message.replace(/\{n\}/g, count.size).replace(/\{s\}/g, count.size === 1 ? "" : "s");
    var keep = document.createElement("button");
    var discard = document.createElement("button");
    keep.type = "button";
    discard.type = "button";
    keep.className = "btn btn-secondary";
    discard.className = "btn btn-danger";
    keep.textContent = reasonOnly ? text.reason_cancel : text.keep;
    discard.textContent = text.discard;
    keep.addEventListener("click", closeDialog);
    discard.addEventListener("click", function () {
      // Cached baselines allow explicit discard while the server is busy.
      instances.forEach(function (id) {
        restore(states[id].inputs);
        if (!confirmation) {
          window.Shiny.setInputValue(states[id].discardInput, {
            instance: id, at: Date.now()
          }, {priority: "event"});
        }
      });
      navigate(target, "discard");
    });
    // The buttons sit in one row that wraps as a whole on narrow screens.
    var actions = document.createElement("div");
    actions.className = "unsaved-dialog-actions";
    actions.appendChild(keep);
    if (!reasonOnly) actions.appendChild(discard);
    panel.appendChild(title);
    if (!reasonOnly) panel.appendChild(message);
    var reason = null;
    var counter = null;
    if (needsReason) {
      var label = document.createElement("label");
      reason = document.createElement("textarea");
      reason.id = "unsaved-reason-" + (++serial);
      reason.required = true;
      reason.className = "form-control";
      label.htmlFor = reason.id;
      label.textContent = text.reason;
      counter = document.createElement("p");
      counter.className = "unsaved-reason-count";
      counter.id = reason.id + "-count";
      counter.textContent = "0 / 1000";
      reason.setAttribute("aria-describedby", counter.id);
      reason.addEventListener("input", function () {
        reason.value = Array.from(reason.value).slice(0, 1000).join("");
        counter.textContent = Array.from(reason.value).length + " / 1000";
        if (save) save.disabled = !reason.value.trim();
      });
      panel.append(label, reason, counter);
    }
    panel.appendChild(actions);
    var buttons = reasonOnly ? [keep] : [keep, discard];
    if (reason) buttons.unshift(reason);
    var save = null;
    var alert = document.createElement("div");
    alert.setAttribute("role", "alert");
    if (reasonOnly || instances.every(function (id) { return states[id].canSave; })) {
      save = document.createElement("button");
      save.type = "button";
      save.className = "btn btn-primary";
      save.textContent = reasonOnly ? text.reason_save : text.save;
      save.disabled = !!needsReason;
      save.addEventListener("click", function () {
        if (!dialog || dialog.waiting) return;
        var reasonText = reason ? Array.from(reason.value.trim()).slice(0, 1000).join("") : undefined;
        if (needsReason && !reasonText) return;
        if (reasonOnly) {
          confirmReply("save", reasonText);
          closeDialog(false);
          return;
        }
        dialog.waiting = true;
        if (reason) reason.disabled = true;
        discard.disabled = true;
        save.disabled = true;
        save.textContent = text.saving;
        alert.textContent = "";
        keep.focus();
        var attempt = {dialog: dialog, remaining: new Set(instances)};
        dialog.attempt = attempt;
        instances.forEach(function (id) {
          if (!saveRequests[id]) saveRequests[id] = [];
          saveRequests[id].push(attempt);
          window.Shiny.setInputValue(states[id].saveInput || "unsaved_save_requested", {
            instance: id,
            reason: states[id].requireReason ? reasonText : undefined,
            target: target ? target.id || target.getAttribute("data-value") || target.getAttribute("href") : null,
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
    dialog = {
      text: text, backdrop: backdrop, target: target, discard: discard,
      save: save, alert: alert, waiting: false, confirmation: confirmation,
      reason: reason, reasonOnly: reasonOnly,
      previousFocus: previousFocus, instances: instances
    };
    keep.focus();
  }

  function isActive(target) {
    return target.classList.contains("active") ||
      target.getAttribute("aria-selected") === "true" ||
      (target.parentElement && target.parentElement.classList.contains("active"));
  }

  function guardNavigation(e, target) {
    if (bypass || !target || (target.matches(selector) && isActive(target))) return;
    var instances = Object.keys(states).filter(function (id) {
      var enabled = target.matches(selector) ? states[id].guardNav : states[id].guardClicks;
      return enabled && states[id].ids.length;
    });
    if (!instances.length) return;
    e.preventDefault();
    e.stopPropagation();
    if (!dialog) {
      instances.forEach(function (id) {
        window.Shiny.setInputValue(states[id].navInput, {
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
    guardNavigation(e, e.target.closest(selector + ',[data-unsaved-guard]'));
  }, true);

  // Bootstrap 5 emits a native event; Bootstrap 3 uses jQuery events.
  function guardTabShow(e) {
    guardNavigation(e, e.target.closest(selector));
  }
  document.addEventListener("show.bs.tab", guardTabShow, true);

  function register() {
    if (!window.Shiny || !window.Shiny.addCustomMessageHandler) return;
    window.jQuery(document).on("show.bs.tab.unsaved show.tab.unsaved", selector, guardTabShow);
    // Only unload uses this estimate. R remains authoritative for all UI state.
    window.jQuery(document).on("shiny:inputchanged.unsaved", function (event) {
      var el = document.getElementById(event.name);
      if (!el) return;
      Object.keys(states).forEach(function (id) {
        var current = states[id];
        if (!current.guardUnload || !Object.prototype.hasOwnProperty.call(current.inputs, event.name)) return;
        var saved = JSON.stringify(bindingValue(el, current.inputs[event.name]));
        var value = JSON.stringify(bindingValue(el, event.value));
        if (saved !== value) current.provisional = true;
      });
      reconcile();
    });
    window.Shiny.addCustomMessageHandler("unsaved:config", function (message) {
      var current = state(message.instance);
      current.inputs = message.baseline || {};
      current.guardNav = message.guardNav;
      current.guardClicks = message.guardClicks;
      current.guardUnload = message.guardUnload;
      current.canSave = message.canSave;
      current.requireReason = message.requireReason;
      current.valueIds = message.valueIds || [];
      current.valueOutputs = message.valueOutputs || {};
      current.saveInput = message.saveInput;
      current.discardInput = message.discardInput;
      current.navInput = message.navInput;
      current.confirmInput = message.confirmInput;
      current.text = message.text;
      current.tabInput = message.tabInput || "unsaved_tab_ids";
      current.passwordInput = message.passwordInput;
      reportTabs(current.tabInput);
      reportPasswords(current.passwordInput);
      reconcile();
    });
    window.Shiny.addCustomMessageHandler("unsaved:state", function (message) {
      state(message.instance).ids = message.ids || [];
      state(message.instance).provisional = false;
      reconcile();
    });
    window.Shiny.addCustomMessageHandler("unsaved:restore", function (message) {
      state(message.instance).inputs = message.inputs || {};
      restore(message.inputs || {});
    });
    window.Shiny.addCustomMessageHandler("unsaved:saved", saveReply);
    window.Shiny.addCustomMessageHandler("unsaved:remove", function (message) {
      delete states[message.instance];
      delete saveRequests[message.instance];
      if (dialog && dialog.instances.indexOf(message.instance) !== -1) closeDialog(false);
      reconcile();
    });
    window.Shiny.addCustomMessageHandler("unsaved:confirm", function (message) {
      showDialog(null, [message.instance], message);
    });
    window.jQuery(document).on("shiny:bound", function () {
      var inputs = new Set();
      Object.keys(states).forEach(function (id) {
        if (states[id].tabInput) inputs.add(states[id].tabInput);
      });
      inputs.forEach(reportTabs);
      Object.keys(states).forEach(function (id) {
        if (states[id].passwordInput) reportPasswords(states[id].passwordInput);
      });
    });
    window.jQuery(document).on("shiny:value", function () {
      // Dynamic UI can replace inputs or outputs that already have markers.
      window.setTimeout(reconcile, 0);
    });
    // Removal need not produce another server state (for example removeUI()).
    new MutationObserver(function () {
      var stale = false;
      marks.forEach(function (record) {
        if (!record.el.isConnected || !record.text.isConnected ||
            (record.output && record.label.nextElementSibling !== record.el)) stale = true;
      });
      if (stale) reconcile();
    }).observe(document.body, {childList: true, subtree: true});
    window.jQuery(document).on("shiny:disconnected", function () {
      states = Object.create(null);
      saveRequests = Object.create(null);
      passwordReports = Object.create(null);
      closeDialog(false);
      reconcile();
    });
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", register);
  } else {
    register();
  }
}());
