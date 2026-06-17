/**
 * Grand Siècle — faceted entity browser.
 *
 * Drives the index pages (/people, /places, …). Reads the filter controls in
 * the sidebar, queries /api/{slug}/browse, and renders the result rows live.
 * Filters: free text, multi-select confidence, authority toggle, min-mentions
 * slider, dual-handle date-range slider, and one-or-more type facets
 * (occupation / nationality / sex / country / language / …).
 */
(function () {
    'use strict';

    var root = document.querySelector('.gs-browse');
    if (!root) return;

    var slug = root.getAttribute('data-slug');
    var page = document.querySelector('pb-page');
    var endpoint = (page && page.getAttribute('endpoint')) || '';

    var type = root.getAttribute('data-type');
    var listEl = document.getElementById('gsList');
    var countEl = document.getElementById('gsCount');
    var moreBtn = document.getElementById('gsMore');
    var searchEl = document.getElementById('gsSearch');
    var authEl = document.getElementById('gsAuthority');
    var mentionsEl = document.getElementById('gsMentions');
    var yMinEl = document.getElementById('gsYearMin');
    var yMaxEl = document.getElementById('gsYearMax');
    var exportEl = document.getElementById('gsExport');

    var limit = 100;
    var offset = 0;
    var total = 0;
    var loading = false;

    function checked(name) {
        return Array.prototype.slice
            .call(root.querySelectorAll('input[name="' + name + '"]:checked'))
            .map(function (c) { return c.value; });
    }

    function buildParams(append) {
        var p = new URLSearchParams();
        var q = searchEl.value.trim();
        if (q) p.set('search', q);

        var conf = checked('conf');
        if (conf.length) p.set('conf', conf.join(','));

        var facetParts = [];
        root.querySelectorAll('.gs-facet-checklist').forEach(function (fs) {
            var name = fs.getAttribute('data-facet');
            var vals = checked(name);
            if (vals.length) facetParts.push(name + ':' + vals.join(','));
        });
        if (facetParts.length) p.set('facets', facetParts.join('|'));

        if (authEl && authEl.checked) p.set('authority', 'true');

        if (mentionsEl && +mentionsEl.value > 0) p.set('minMentions', mentionsEl.value);

        if (yMinEl && yMaxEl) {
            var a = yMinEl.value.trim(), b = yMaxEl.value.trim();
            if (a !== '' || b !== '') {
                var lo = a !== '' ? parseInt(a, 10) : parseInt(yMinEl.min, 10);
                var hi = b !== '' ? parseInt(b, 10) : parseInt(yMaxEl.max, 10);
                if (!isNaN(lo) && !isNaN(hi)) {
                    p.set('yearMin', Math.min(lo, hi));
                    p.set('yearMax', Math.max(lo, hi));
                }
            }
        }

        p.set('limit', limit);
        p.set('offset', append ? offset : 0);
        return p;
    }

    // Keep the "Export (CSV)" link pointing at the current filter set.
    function updateExport() {
        if (!exportEl) return;
        var p = buildParams(false);
        p.delete('limit');
        p.delete('offset');
        p.set('type', type);
        p.set('format', 'csv');
        exportEl.href = endpoint + '/api/export?' + p.toString();
    }

    function setStagger(startIndex) {
        var kids = listEl.children;
        for (var i = startIndex; i < kids.length; i++) {
            kids[i].style.setProperty('--i', Math.min(i - startIndex, 20));
        }
    }

    function render(data, append) {
        total = data.total;
        countEl.textContent = total.toLocaleString('fr-FR') + ' résultat' + (total > 1 ? 's' : '');
        var html = data.items.join('');
        var startIndex = 0;
        if (append) {
            startIndex = listEl.children.length;
            listEl.insertAdjacentHTML('beforeend', html);
        } else {
            listEl.innerHTML = html || '<p class="gs-empty">Aucun résultat pour ces critères.</p>';
        }
        setStagger(startIndex);
        offset = data.offset + data.shown;
        moreBtn.hidden = offset >= total;
    }

    function fetchData(append) {
        if (loading) return;
        loading = true;
        root.classList.add('gs-loading');
        updateExport();
        var p = buildParams(append);
        fetch(endpoint + '/api/' + slug + '/browse?' + p.toString())
            .then(function (r) { return r.json(); })
            .then(function (d) {
                render(d, append);
                loading = false;
                root.classList.remove('gs-loading');
            })
            .catch(function () {
                loading = false;
                root.classList.remove('gs-loading');
            });
    }

    function reload() { offset = 0; fetchData(false); }

    var timer;
    function debouncedReload() {
        clearTimeout(timer);
        timer = setTimeout(reload, 250);
    }

    // --- wire controls ---
    searchEl.addEventListener('input', debouncedReload);
    root.querySelectorAll('input[type=checkbox]').forEach(function (c) {
        c.addEventListener('change', reload);
    });

    if (mentionsEl) {
        var mOut = document.getElementById('gsMentionsOut');
        mentionsEl.addEventListener('input', function () { mOut.textContent = mentionsEl.value; });
        mentionsEl.addEventListener('change', reload);
    }

    // --- date range (year number inputs: empty = no bound; negative = BCE) ---
    if (yMinEl) yMinEl.addEventListener('input', debouncedReload);
    if (yMaxEl) yMaxEl.addEventListener('input', debouncedReload);

    // --- "show more parameters" toggle ---
    var moreParamsBtn = document.getElementById('gsMoreParams');
    var advanced = document.getElementById('gsAdvanced');
    if (moreParamsBtn && advanced) {
        moreParamsBtn.addEventListener('click', function () {
            var willOpen = advanced.hasAttribute('hidden');
            if (willOpen) {
                advanced.removeAttribute('hidden');
                moreParamsBtn.setAttribute('aria-expanded', 'true');
                moreParamsBtn.textContent = 'Moins de paramètres';
            } else {
                advanced.setAttribute('hidden', '');
                moreParamsBtn.setAttribute('aria-expanded', 'false');
                moreParamsBtn.textContent = 'Afficher plus de paramètres';
            }
        });
    }

    // --- collapsible facet checklists: show top N, "+ N autres" to expand,
    //     no inner scrollbar; the search-within only shows up for long facets
    //     and matches across ALL values. Defined as a function so it can also be
    //     applied to the lazily-injected "document source" facet. ---
    var FACET_CAP = 6;
    var checklistResets = [];
    function setupChecklist(fs) {
        var optionsBox = fs.querySelector('.gs-facet-options');
        if (!optionsBox) return;
        var filterInput = fs.querySelector('.gs-facet-filter');
        var checks = Array.prototype.slice.call(optionsBox.querySelectorAll('.gs-check'));
        var expanded = false;
        var moreBtn = null;

        function applyView() {
            var q = filterInput ? filterInput.value.trim().toLowerCase() : '';
            var cap = (expanded || q) ? Infinity : FACET_CAP;
            // selected values float to the top so active filters stay visible
            var checked = checks.filter(function (l) { return l.querySelector('input').checked; });
            for (var k = checked.length - 1; k >= 0; k--) {
                optionsBox.insertBefore(checked[k], optionsBox.firstChild);
            }
            var shown = 0;
            Array.prototype.forEach.call(optionsBox.children, function (lbl) {
                var labelEl = lbl.querySelector('.gs-check-label');
                var txt = labelEl ? labelEl.textContent.toLowerCase() : '';
                var input = lbl.querySelector('input');
                var visible;
                if (q && txt.indexOf(q) === -1) visible = false;
                else if (input.checked) visible = true;   // keep selected values visible (at top)
                else if (shown < cap) { visible = true; shown++; }
                else visible = false;
                lbl.style.display = visible ? '' : 'none';
            });
            if (moreBtn) {
                moreBtn.style.display = q ? 'none' : '';
                moreBtn.textContent = expanded ? 'Voir moins' : ('+ ' + (checks.length - FACET_CAP) + ' autres');
            }
        }

        if (checks.length > FACET_CAP) {
            moreBtn = document.createElement('button');
            moreBtn.type = 'button';
            moreBtn.className = 'gs-facet-more';
            moreBtn.addEventListener('click', function () { expanded = !expanded; applyView(); });
            optionsBox.parentNode.insertBefore(moreBtn, optionsBox.nextSibling);
        } else if (filterInput) {
            filterInput.style.display = 'none';
        }
        if (filterInput) filterInput.addEventListener('input', applyView);
        optionsBox.addEventListener('change', applyView);
        applyView();

        checklistResets.push(function () {
            expanded = false;
            if (filterInput) filterInput.value = '';
            applyView();
        });
    }
    root.querySelectorAll('.gs-facet-checklist').forEach(setupChecklist);

    document.getElementById('gsReset').addEventListener('click', function () {
        root.querySelectorAll('input[type=checkbox]').forEach(function (c) { c.checked = false; });
        searchEl.value = '';
        if (mentionsEl) { mentionsEl.value = 0; document.getElementById('gsMentionsOut').textContent = '0'; }
        if (yMinEl) yMinEl.value = '';
        if (yMaxEl) yMaxEl.value = '';
        checklistResets.forEach(function (fn) { fn(); });
        reload();
    });

    moreBtn.addEventListener('click', function () { fetchData(true); });

    // initial load
    fetchData(false);

    // --- lazy "document source" facet: heavy server-side (reads every entry's
    //     sources note), so it loads after the page is interactive and is then
    //     injected + wired like the other checklists. buildParams() already
    //     picks up any .gs-facet-checklist[data-facet] at query time, so the
    //     injected fieldset filters with no further plumbing. ---
    (function loadSourceFacet() {
        var holder = document.getElementById('gsSourceFacet');
        if (!holder) return;
        holder.innerHTML = '<p class="gs-facet-loading">Chargement des documents sources…</p>';
        fetch(endpoint + '/api/facet-source?type=' + encodeURIComponent(type))
            .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
            .then(function (html) {
                holder.innerHTML = html;
                var fs = holder.querySelector('.gs-facet-checklist');
                if (!fs) { holder.innerHTML = ''; return; }
                fs.querySelectorAll('input[type=checkbox]').forEach(function (c) {
                    c.addEventListener('change', reload);
                });
                setupChecklist(fs);
            })
            .catch(function () { holder.innerHTML = ''; });
    })();

    // --- Places map view (only on /places). pb-leaflet-map needs the global
    //     pbEvents, defined by the deferred component bundle, so we wait for
    //     DOMContentLoaded. Markers come from /api/places/all (geolocated only);
    //     a marker click opens that place's authority file. The map is built
    //     inside a hidden panel, so we force a resize when first shown to avoid
    //     Leaflet's blank-tile bug. ---
    function initMap() {
        var mapEl = document.getElementById('gsMap');
        var mapWrap = document.getElementById('gsMapWrap');
        var listBtn = document.getElementById('gsViewList');
        var mapBtn = document.getElementById('gsViewMap');
        if (!mapEl || !mapWrap || typeof pbEvents === 'undefined') return;

        var markersLoaded = false;
        function loadMarkers() {
            if (markersLoaded) return;
            markersLoaded = true;
            pbEvents.ifReady(mapEl).then(function () {
                fetch(endpoint + '/api/places/all')
                    .then(function (r) { return r.json(); })
                    .then(function (json) { pbEvents.emit('pb-update-map', 'map', json); })
                    .catch(function () { markersLoaded = false; });
                pbEvents.subscribe('pb-leaflet-marker-click', 'map', function (ev) {
                    var id = ev.detail && ev.detail.element && ev.detail.element.id;
                    if (id) window.location = 'places/' + id;
                });
            });
        }

        function showMap(on) {
            // map mode hides the list-specific chrome (facets/toolbar/legend) and
            // lets the map span full width — the map shows ALL geolocated places,
            // not the filtered set, so leaving the filters live would mislead.
            root.classList.toggle('gs-map-mode', on);
            mapWrap.hidden = !on;
            listEl.hidden = on;
            if (moreBtn) moreBtn.style.display = on ? 'none' : (offset >= total ? 'none' : '');
            if (mapBtn) { mapBtn.classList.toggle('is-active', on); mapBtn.setAttribute('aria-pressed', String(on)); }
            if (listBtn) { listBtn.classList.toggle('is-active', !on); listBtn.setAttribute('aria-pressed', String(!on)); }
            if (on) {
                loadMarkers();
                // let the panel lay out, then nudge Leaflet to recompute its size
                setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
            }
        }

        if (mapBtn) mapBtn.addEventListener('click', function () { showMap(true); });
        if (listBtn) listBtn.addEventListener('click', function () { showMap(false); });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initMap);
    } else {
        initMap();
    }
})();
