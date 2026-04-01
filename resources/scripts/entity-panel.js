/**
 * Grand Siecle — Entity Panel
 * Loads NER entities for the current document, displays them in a
 * collapsible sidebar with search and click-to-navigate.
 */
(function() {
    'use strict';

    var TYPE_LABELS = {
        person: 'Personnes',
        place: 'Lieux',
        org: 'Organisations',
        work: 'Oeuvres',
        event: 'Evenements'
    };

    var TYPE_CSS = {
        person: 'entity-person',
        place: 'entity-place',
        org: 'entity-org'
    };

    var activeFilter = null;
    var searchQuery = '';
    var allEntities = [];

    function getDocFile() {
        var src = document.querySelector('pb-document');
        if (!src) return null;
        var path = src.getAttribute('path');
        if (!path) return null;
        return path.split('/').pop();
    }

    function togglePanel() {
        var panel = document.getElementById('entity-panel');
        if (panel) panel.classList.toggle('open');
    }

    /** Navigate to the first mention of an entity in the document */
    function navigateToEntity(entity) {
        var view = document.querySelector('pb-view');
        if (!view) return;

        // Look for the entity link/span in the currently rendered page
        var refId = entity.id;
        var cssClass = TYPE_CSS[entity.type];
        var selector = cssClass
            ? '.' + cssClass + '[href*="' + refId + '"], .' + cssClass + '[data-ref="' + refId + '"]'
            : null;

        // Also try a text match on the entity label within entity spans
        var found = null;
        if (selector) {
            found = view.shadowRoot
                ? view.shadowRoot.querySelector(selector)
                : view.querySelector(selector);
        }

        // Fallback: search for entity label text in entity-annotated spans
        if (!found && cssClass) {
            var candidates = view.shadowRoot
                ? view.shadowRoot.querySelectorAll('.' + cssClass)
                : view.querySelectorAll('.' + cssClass);
            for (var i = 0; i < candidates.length; i++) {
                if (candidates[i].textContent.trim().indexOf(entity.label) !== -1) {
                    found = candidates[i];
                    break;
                }
            }
        }

        if (found) {
            // Entity is on the current page — scroll to it and highlight
            found.scrollIntoView({ behavior: 'smooth', block: 'center' });
            found.classList.add('gs-entity-highlight');
            setTimeout(function() { found.classList.remove('gs-entity-highlight'); }, 2000);
        } else {
            // Entity not on current page — use search to find it
            var pbSearch = document.querySelector('pb-search');
            if (pbSearch && pbSearch.search) {
                pbSearch.search(entity.label);
            }
        }
    }

    function renderSummary(summary) {
        var container = document.getElementById('entity-summary');
        if (!container) return;
        while (container.firstChild) container.removeChild(container.firstChild);

        var byType = summary['by-type'];
        var total = document.createElement('div');
        total.className = 'gs-entity-total';
        total.textContent = summary['total-entities'] + ' entites';
        container.appendChild(total);

        var types = document.createElement('div');
        types.className = 'gs-entity-type-counts';
        Object.keys(byType).forEach(function(type) {
            if (byType[type] === 0) return;
            var badge = document.createElement('span');
            badge.className = 'gs-entity-badge gs-entity-badge-' + type;
            if (activeFilter === type) badge.classList.add('active');
            badge.textContent = byType[type] + ' ' + (TYPE_LABELS[type] || type);
            badge.title = 'Filtrer par ' + (TYPE_LABELS[type] || type);
            badge.addEventListener('click', function() {
                activeFilter = activeFilter === type ? null : type;
                renderSummary(summary);
                renderFilters();
                renderList();
            });
            types.appendChild(badge);
        });
        container.appendChild(types);
    }

    function renderFilters() {
        var container = document.getElementById('entity-filters');
        if (!container) return;
        while (container.firstChild) container.removeChild(container.firstChild);

        // Search input
        var searchBox = document.createElement('input');
        searchBox.type = 'text';
        searchBox.className = 'gs-entity-search';
        searchBox.placeholder = 'Rechercher une entite...';
        searchBox.value = searchQuery;
        searchBox.addEventListener('input', function() {
            searchQuery = this.value;
            renderList();
        });
        container.appendChild(searchBox);

        // Active filter tag
        if (activeFilter) {
            var tag = document.createElement('span');
            tag.className = 'gs-entity-filter-tag';
            tag.textContent = (TYPE_LABELS[activeFilter] || activeFilter) + ' \u00D7';
            tag.addEventListener('click', function() {
                activeFilter = null;
                renderSummary(lastSummary);
                renderFilters();
                renderList();
            });
            container.appendChild(tag);
        }
    }

    function renderList() {
        var container = document.getElementById('entity-list');
        if (!container) return;
        while (container.firstChild) container.removeChild(container.firstChild);

        var filtered = allEntities;

        // Type filter
        if (activeFilter) {
            filtered = filtered.filter(function(e) { return e.type === activeFilter; });
        }

        // Text search
        if (searchQuery) {
            var q = searchQuery.toLowerCase();
            filtered = filtered.filter(function(e) {
                return e.label.toLowerCase().indexOf(q) !== -1;
            });
        }

        filtered.forEach(function(entity) {
            var item = document.createElement('div');
            item.className = 'gs-entity-item gs-entity-item-' + entity.type;
            item.title = 'Cliquer pour localiser dans le texte';
            item.addEventListener('click', function() { navigateToEntity(entity); });

            var label = document.createElement('span');
            label.className = 'gs-entity-label';
            label.textContent = entity.label;
            item.appendChild(label);

            var meta = document.createElement('span');
            meta.className = 'gs-entity-meta';
            var parts = [];
            parts.push(TYPE_LABELS[entity.type] || entity.type);
            if (entity.mentions > 0) parts.push(entity.mentions + ' mentions');
            if (entity.source === 'manual') parts.push('manuel');
            if (entity.certs && entity.certs.length > 0) parts.push(entity.certs.join('/'));
            meta.textContent = parts.join(' \u2022 ');
            item.appendChild(meta);

            container.appendChild(item);
        });

        if (filtered.length === 0) {
            var empty = document.createElement('div');
            empty.className = 'gs-entity-empty';
            empty.textContent = searchQuery ? 'Aucun resultat pour "' + searchQuery + '"' : 'Aucune entite';
            container.appendChild(empty);
        }
    }

    var lastSummary = null;

    function loadEntities() {
        var file = getDocFile();
        if (!file) return;

        var url = 'api/document-entities?file=' + encodeURIComponent(file);
        fetch(url)
            .then(function(resp) { return resp.json(); })
            .then(function(data) {
                if (data.error) return;
                allEntities = data.entities || [];
                lastSummary = data.summary;
                renderSummary(data.summary);
                renderFilters();
                renderList();
            });
    }

    function init() {
        var toggle = document.getElementById('entity-panel-toggle');
        if (toggle && !toggle._init) {
            toggle.addEventListener('click', togglePanel);
            toggle._init = true;
        }
        loadEntities();
    }

    document.addEventListener('DOMContentLoaded', init);
    document.addEventListener('pb-update', loadEntities);
})();
