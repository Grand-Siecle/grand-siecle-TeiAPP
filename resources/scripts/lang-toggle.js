/**
 * Grand Siecle — Language highlight toggles
 * Detects languages present in the rendered page and creates toggle buttons.
 * Adds/removes lang-highlight-{code} classes on the pb-view container.
 */
(function() {
    'use strict';

    var LANG_LABELS = {
        lat: 'Latin',
        fra: 'Francais',
        grc: 'Grec',
        ita: 'Italien',
        deu: 'Allemand',
        spa: 'Espagnol',
        eng: 'Anglais',
        heb: 'Hebreu',
        ara: 'Arabe'
    };

    var LANG_COLORS = {
        lat: 'rgba(43, 91, 138, 0.15)',
        fra: 'rgba(58, 107, 74, 0.15)',
        grc: 'rgba(122, 46, 46, 0.15)',
        ita: 'rgba(156, 122, 60, 0.15)',
        deu: 'rgba(91, 58, 122, 0.15)'
    };
    var DEFAULT_COLOR = 'rgba(90, 74, 58, 0.12)';

    function getView() {
        return document.querySelector('pb-view');
    }

    /** Scan rendered content for all data-lang values */
    function detectLanguages() {
        var view = getView();
        if (!view) return [];
        var langs = new Set();
        view.querySelectorAll('[data-lang]').forEach(function(el) {
            var lang = el.getAttribute('data-lang');
            if (lang) langs.add(lang);
        });
        return Array.from(langs).sort();
    }

    /** Inject a dynamic CSS rule for a language highlight */
    function ensureHighlightRule(lang) {
        var id = 'gs-lang-style';
        var style = document.getElementById(id);
        if (!style) {
            style = document.createElement('style');
            style.id = id;
            document.head.appendChild(style);
        }
        var cls = '.lang-highlight-' + lang;
        var sheet = style.sheet;
        for (var i = 0; i < sheet.cssRules.length; i++) {
            if (sheet.cssRules[i].selectorText && sheet.cssRules[i].selectorText.indexOf(cls) === 0) return;
        }
        var color = LANG_COLORS[lang] || DEFAULT_COLOR;
        var rule = cls + ' .tei-foreign[data-lang="' + lang + '"] { background-color: ' + color + '; border-radius: 2px; }';
        sheet.insertRule(rule, sheet.cssRules.length);
    }

    function toggleLang(lang) {
        var view = getView();
        if (!view) return;
        ensureHighlightRule(lang);
        view.classList.toggle('lang-highlight-' + lang);
        var btn = document.querySelector('[data-lang-toggle="' + lang + '"]');
        if (btn) btn.classList.toggle('active');
    }

    function buildButtons() {
        var container = document.querySelector('.lang-toggle-buttons');
        if (!container) return;

        var langs = detectLanguages();

        // Remove old buttons
        while (container.firstChild) {
            container.removeChild(container.firstChild);
        }

        if (langs.length === 0) {
            container.style.display = 'none';
            return;
        }
        container.style.display = '';

        langs.forEach(function(lang) {
            var btn = document.createElement('button');
            btn.className = 'gs-toolbar-btn';
            btn.setAttribute('data-lang-toggle', lang);
            btn.textContent = (LANG_LABELS[lang] || lang).toUpperCase().substring(0, 3);
            btn.title = LANG_LABELS[lang] || lang;
            btn.addEventListener('click', function() { toggleLang(lang); });
            container.appendChild(btn);
        });
    }

    document.addEventListener('pb-update', buildButtons);
    document.addEventListener('DOMContentLoaded', buildButtons);
})();
