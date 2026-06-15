/**
 * Grand Siècle — authority-file page.
 * Lazy-loads the KWIC passages ("Cité dans") when a citing document is expanded.
 */
(function () {
    'use strict';

    var page = document.querySelector('pb-page');
    var endpoint = (page && page.getAttribute('endpoint')) || '';

    document.querySelectorAll('.gs-kwic-toggle').forEach(function (btn) {
        btn.addEventListener('click', function () {
            var panel = btn.nextElementSibling;
            if (!panel) return;
            var open = btn.getAttribute('aria-expanded') === 'true';
            if (open) {
                btn.setAttribute('aria-expanded', 'false');
                panel.hidden = true;
                return;
            }
            btn.setAttribute('aria-expanded', 'true');
            panel.hidden = false;
            if (panel.dataset.loaded) return;

            panel.innerHTML = '<p class="gs-kwic-loading">Chargement des passages…</p>';
            var id = btn.dataset.id, doc = btn.dataset.doc;
            fetch(endpoint + '/api/cited?id=' + encodeURIComponent(id) + '&doc=' + encodeURIComponent(doc))
                .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
                .then(function (html) {
                    panel.innerHTML = html;
                    panel.dataset.loaded = '1';
                })
                .catch(function () {
                    panel.innerHTML = '<p class="gs-kwic-empty">Erreur de chargement des passages.</p>';
                });
        });
    });
})();
