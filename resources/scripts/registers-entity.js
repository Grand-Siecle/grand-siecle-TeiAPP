/**
 * Grand Siècle — authority-file page.
 * Lazy-loads the KWIC passages ("Cité dans") when a citing document is expanded.
 */
(function () {
    'use strict';

    var page = document.querySelector('pb-page');
    var endpoint = (page && page.getAttribute('endpoint')) || '';

    // Co-occurrence ("Apparaît avec") — load on page load into the mount.
    var cooccur = document.querySelector('.gs-cooccur[data-id]');
    if (cooccur) {
        var mount = cooccur.querySelector('.gs-cooccur-mount');
        if (mount) {
            mount.innerHTML = '<p class="gs-cooccur-loading">Calcul des co-occurrences…</p>';
            fetch(endpoint + '/api/cooccur?id=' + encodeURIComponent(cooccur.dataset.id))
                .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
                .then(function (html) { mount.innerHTML = html; })
                .catch(function () { mount.innerHTML = '<p class="gs-cooccur-empty">Co-occurrences indisponibles.</p>'; });
        }
    }

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

    // "Voir plus" — load the next batch of KWIC passages in place (delegated,
    // because the buttons are injected dynamically).
    document.addEventListener('click', function (ev) {
        var more = ev.target.closest && ev.target.closest('.gs-kwic-more-btn');
        if (!more) return;
        ev.preventDefault();
        var id = more.dataset.id, doc = more.dataset.doc, offset = more.dataset.offset;
        var label = more.textContent;
        more.textContent = 'Chargement…';
        more.disabled = true;
        fetch(endpoint + '/api/cited?id=' + encodeURIComponent(id)
                + '&doc=' + encodeURIComponent(doc) + '&offset=' + encodeURIComponent(offset))
            .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
            .then(function (html) {
                var tmp = document.createElement('div');
                tmp.innerHTML = html;
                var batch = tmp.firstElementChild;
                if (batch) {
                    while (batch.firstChild) more.parentNode.insertBefore(batch.firstChild, more);
                }
                more.remove();
            })
            .catch(function () { more.textContent = label; more.disabled = false; });
    });
})();
