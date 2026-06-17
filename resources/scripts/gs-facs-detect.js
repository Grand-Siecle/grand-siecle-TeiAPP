/**
 * Grand Siecle — Facsimile availability detection.
 * Fetches the TEI XML for the current document and checks whether any
 * <graphic url="http..."/> is present (typically inside <surface> elements
 * of <sourceDoc>). Sets `body.gs-no-iiif` accordingly so CSS can hide the
 * "Fac-similé" sub-view option in pb-panel dropdowns when no IIIF data
 * exists (e.g. PDF-sourced documents).
 *
 * No server-side endpoint needed: the check is a simple regex on the source.
 */
(function() {
    'use strict';

    function getDocFile() {
        var doc = document.querySelector('pb-document');
        if (!doc) return null;
        var path = doc.getAttribute('path');
        if (!path) return null;
        return path;
    }

    function detect() {
        var file = getDocFile();
        if (!file) return;
        // Fetch the raw TEI XML via the document API. Using an absolute,
        // endpoint-anchored URL avoids relative-path resolution against the
        // document-view URL (which would hit `…/data/<file>` → routed to the
        // view handler → NOT_FOUND_404 since .xml isn't served statically).
        var page = document.querySelector('pb-page');
        var endpoint = (page && page.getAttribute('endpoint')) || '';
        fetch(endpoint + '/api/document/' + encodeURIComponent(file))
            .then(function(resp) { return resp.ok ? resp.text() : null; })
            .then(function(text) {
                if (text === null) return;
                // Detect IIIF availability: any <graphic url="http(s)://..."/>
                var hasIIIF = /<graphic[^>]+url\s*=\s*["']https?:\/\//i.test(text);
                if (!hasIIIF) {
                    document.body.classList.add('gs-no-iiif');
                } else {
                    document.body.classList.remove('gs-no-iiif');
                }
            })
            .catch(function(err) {
                // Silent fail: the option stays available, user gets an empty
                // facsimile if they pick it. Better than blocking the page.
                console.warn('IIIF availability check failed:', err);
            });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', detect);
    } else {
        detect();
    }
    // Re-check on document switch (single-page navigation)
    document.addEventListener('pb-document-loaded', detect);
})();
