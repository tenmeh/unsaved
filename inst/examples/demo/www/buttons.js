$(document).on('shiny:connected', function () {
  Shiny.addCustomMessageHandler('profile-buttons', function (enabled) {
    ['save', 'discard'].forEach(function (id) {
      document.getElementById(id).disabled = !enabled;
    });
  });
});
