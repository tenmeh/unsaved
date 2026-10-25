$(document).on('shiny:connected', function () {
  Shiny.addCustomMessageHandler('review-save', function (enabled) {
    document.getElementById('save').disabled = !enabled;
  });
});
