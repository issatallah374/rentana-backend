(function () {
  const params = new URLSearchParams(window.location.search);
  const note = document.getElementById('download-note');

  if (params.get('download') === 'missing' && note) {
    note.textContent = 'The APK has not been uploaded on the server yet. Contact Rentana support for the latest app.';
    note.style.color = '#ffd18a';
  }

  document.querySelectorAll('[data-download-link]').forEach((link) => {
    link.addEventListener('click', () => {
      try {
        localStorage.setItem('rentana_download_clicked_at', new Date().toISOString());
      } catch (_) {}
    });
  });
})();
