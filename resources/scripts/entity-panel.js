/**
 * Grand Siecle — Per-Panel Entity Aside.
 *
 * Each pb-panel that hosts a textual sub-view (Original / Modernisé / Notes)
 * gets its own entity navigation aside. The aside calls /api/document-entities
 * with a scope parameter matching the panel's active sub-view, so the entity
 * list reflects the WHOLE document filtered by reading layer (not just the
 * current page).
 *
 * Toggle: button.gs-entity-aside-toggle inside the pb-panel toolbar.
 * Refresh on sub-view switch. Hidden when active sub-view is Fac-similé.
 */
(function() {
    'use strict';

    var TYPE_LABELS = {
        person: 'Personnes',
        place: 'Lieux',
        org: 'Organisations',
        work: 'Œuvres',
        event: 'Événements',
        technique: 'Techniques',
        date: 'Dates',
        object: 'Objets',
        material: 'Matériaux'
    };

    var TYPE_CSS = {
        person: 'entity-person',
        place: 'entity-place',
        org: 'entity-org',
        work: 'entity-work',
        event: 'entity-event',
        technique: 'entity-technique',
        date: 'entity-date',
        object: 'entity-object',
        material: 'entity-material'
    };

    function clearChildren(el) {
        while (el.firstChild) el.removeChild(el.firstChild);
    }

    function getDocFile() {
        var doc = document.querySelector('pb-document');
        if (!doc) return null;
        var path = doc.getAttribute('path');
        if (!path) return null;
        return path.split('/').pop();
    }

    /** Map a sub-view title to an API scope value. */
    function scopeForTitle(title) {
        if (!title) return 'all';
        var t = title.toLowerCase();
        if (t.indexOf('modern') !== -1) return 'modernized';
        if (t.indexOf('note') !== -1) return 'notes';
        if (t.indexOf('orig') !== -1) return 'original';
        if (t.indexOf('fac') !== -1) return null; /* facsimile: no entities */
        return 'all';
    }

    /** Detect the active sub-view title from a pb-panel.
     * pb-panel exposes its sub-view titles in a `panels` attribute (JSON array)
     * and the active index in `active`. */
    function activeSubviewTitle(panel) {
        try {
            var panelsAttr = panel.getAttribute('panels');
            var activeIdx = parseInt(panel.getAttribute('active') || '0', 10);
            if (!panelsAttr) return null;
            var titles = JSON.parse(panelsAttr);
            return titles[activeIdx] || null;
        } catch (e) {
            return null;
        }
    }

    function GsEntityAside(panelEl) {
        this.panel = panelEl;
        this.button = panelEl.querySelector('.gs-entity-aside-toggle');
        if (!this.button || this.button._gsEntityInit) return;
        this.button._gsEntityInit = true;

        this.aside = this.createAside();
        this.panel.appendChild(this.aside);
        this.entities = [];
        this.summary = null;
        this.activeFilter = null;
        this.searchQuery = '';
        this.lastScope = null;

        var self = this;
        this.button.addEventListener('click', function() { self.toggle(); });
        this.observePanel();
    }

    GsEntityAside.prototype.createAside = function() {
        var aside = document.createElement('aside');
        aside.className = 'gs-panel-entity-aside';

        var summary = document.createElement('div');
        summary.className = 'gs-entity-summary';
        aside.appendChild(summary);

        var filters = document.createElement('div');
        filters.className = 'gs-entity-filters';
        var search = document.createElement('input');
        search.type = 'text';
        search.className = 'gs-entity-search';
        search.placeholder = 'Rechercher une entité...';
        var self = this;
        search.addEventListener('input', function(e) {
            self.searchQuery = e.target.value;
            self.renderList();
        });
        filters.appendChild(search);
        aside.appendChild(filters);

        var list = document.createElement('div');
        list.className = 'gs-entity-list';
        aside.appendChild(list);

        return aside;
    };

    GsEntityAside.prototype.toggle = function() {
        var open = this.aside.classList.toggle('open');
        if (open) {
            this.panel.classList.add('has-entity-aside-open');
            this.refresh();
        } else {
            this.panel.classList.remove('has-entity-aside-open');
        }
    };

    GsEntityAside.prototype.observePanel = function() {
        var self = this;
        // Re-fetch when the panel's active sub-view changes
        var obs = new MutationObserver(function() {
            if (self.aside.classList.contains('open')) {
                self.refresh();
            }
        });
        obs.observe(this.panel, {
            attributes: true,
            attributeFilter: ['active']
        });
    };

    GsEntityAside.prototype.refresh = function() {
        var title = activeSubviewTitle(this.panel);
        var scope = scopeForTitle(title);
        if (scope === null) {
            // Facsimile sub-view: hide button, close aside
            this.aside.classList.remove('open');
            this.panel.classList.remove('has-entity-aside-open');
            this.button.style.display = 'none';
            return;
        }
        this.button.style.display = '';
        if (scope === this.lastScope && this.entities.length > 0) {
            return; /* already loaded */
        }
        this.lastScope = scope;
        this.fetchEntities(scope);
    };

    GsEntityAside.prototype.fetchEntities = function(scope) {
        var file = getDocFile();
        if (!file) return;
        var url = 'api/document-entities?file=' + encodeURIComponent(file)
                + '&scope=' + encodeURIComponent(scope);
        var self = this;
        var summaryEl = this.aside.querySelector('.gs-entity-summary');
        clearChildren(summaryEl);
        var loading = document.createElement('div');
        loading.className = 'gs-entity-loading';
        loading.textContent = 'Chargement...';
        summaryEl.appendChild(loading);

        fetch(url)
            .then(function(resp) { return resp.ok ? resp.json() : null; })
            .then(function(data) {
                if (!data) {
                    self.renderError('Erreur de chargement');
                    return;
                }
                if (data.error) {
                    self.renderError(data.error);
                    return;
                }
                self.entities = data.entities || [];
                self.summary = data.summary || null;
                self.renderSummary();
                self.renderList();
            })
            .catch(function(err) {
                console.warn('Entity fetch failed:', err);
                self.renderError('Erreur réseau');
            });
    };

    GsEntityAside.prototype.renderError = function(msg) {
        var summaryEl = this.aside.querySelector('.gs-entity-summary');
        var listEl = this.aside.querySelector('.gs-entity-list');
        clearChildren(summaryEl);
        clearChildren(listEl);
        var err = document.createElement('div');
        err.className = 'gs-entity-empty';
        err.textContent = msg;
        listEl.appendChild(err);
    };

    GsEntityAside.prototype.renderSummary = function() {
        var container = this.aside.querySelector('.gs-entity-summary');
        if (!container) return;
        clearChildren(container);

        var totalMentions = 0;
        var counts = {};
        this.entities.forEach(function(e) {
            totalMentions += (e.mentions || 0);
            counts[e.type] = (counts[e.type] || 0) + 1;
        });

        var totalEl = document.createElement('div');
        totalEl.className = 'gs-entity-total';
        totalEl.textContent = totalMentions + ' mentions / ' + this.entities.length + ' entités';
        container.appendChild(totalEl);

        var types = document.createElement('div');
        types.className = 'gs-entity-type-counts';
        var self = this;
        Object.keys(TYPE_LABELS).forEach(function(type) {
            if (!counts[type]) return;
            var badge = document.createElement('span');
            badge.className = 'gs-entity-badge gs-entity-badge-' + type;
            if (self.activeFilter === type) badge.classList.add('active');
            badge.textContent = counts[type] + ' ' + (TYPE_LABELS[type] || type);
            badge.title = 'Filtrer par ' + (TYPE_LABELS[type] || type);
            badge.addEventListener('click', function() {
                self.activeFilter = self.activeFilter === type ? null : type;
                self.renderSummary();
                self.renderList();
            });
            types.appendChild(badge);
        });
        container.appendChild(types);
    };

    GsEntityAside.prototype.renderList = function() {
        var container = this.aside.querySelector('.gs-entity-list');
        if (!container) return;
        clearChildren(container);

        var filtered = this.entities;
        var self = this;
        if (this.activeFilter) {
            filtered = filtered.filter(function(e) {
                return e.type === self.activeFilter;
            });
        }
        if (this.searchQuery) {
            var q = this.searchQuery.toLowerCase();
            filtered = filtered.filter(function(e) {
                return (e.label || '').toLowerCase().indexOf(q) !== -1;
            });
        }

        filtered.forEach(function(e) {
            var item = document.createElement('div');
            item.className = 'gs-entity-item gs-entity-item-' + e.type;
            item.title = 'Cliquer pour localiser dans le panneau';
            item.addEventListener('click', function() { self.navigate(e); });

            var label = document.createElement('span');
            label.className = 'gs-entity-label';
            label.textContent = e.label || e.id;
            item.appendChild(label);

            var meta = document.createElement('span');
            meta.className = 'gs-entity-meta';
            var parts = [];
            parts.push(TYPE_LABELS[e.type] || e.type);
            if (e.mentions > 0) parts.push(e.mentions + ' mentions');
            if (e.source === 'manual') parts.push('manuel');
            var certs = (e.certs && e.certs.length > 0) ? e.certs.filter(function(c) { return c; }) : [];
            if (certs.length > 0) parts.push(certs.join('/'));
            meta.textContent = parts.join(' • ');
            item.appendChild(meta);

            container.appendChild(item);
        });

        if (filtered.length === 0) {
            var empty = document.createElement('div');
            empty.className = 'gs-entity-empty';
            empty.textContent = this.searchQuery
                ? 'Aucun résultat pour "' + this.searchQuery + '"'
                : 'Aucune entité dans cette vue';
            container.appendChild(empty);
        }
    };

    GsEntityAside.prototype.navigate = function(entity) {
        // Try to scroll to the first inline mention of this entity within the
        // panel's pb-view rendered DOM.
        var pbView = this.panel.querySelector('pb-view');
        if (!pbView) return;
        var root = pbView.shadowRoot || pbView;
        var cls = TYPE_CSS[entity.type];
        if (!cls) return;
        var refId = entity.id;
        var target = null;
        if (refId) {
            target = root.querySelector('.' + cls + '[data-ref="' + refId + '"], .' + cls + '[href*="' + refId + '"]');
        }
        if (!target) {
            var nodes = root.querySelectorAll('.' + cls);
            for (var i = 0; i < nodes.length; i++) {
                if ((nodes[i].textContent || '').trim() === (entity.label || '').trim()) {
                    target = nodes[i];
                    break;
                }
            }
        }
        if (!target) return;
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        target.classList.add('gs-entity-highlight');
        setTimeout(function() {
            target.classList.remove('gs-entity-highlight');
        }, 2000);
    };

    function init() {
        document.querySelectorAll('pb-panel').forEach(function(p) {
            new GsEntityAside(p);
        });

        var grid = document.querySelector('pb-grid');
        if (grid) {
            new MutationObserver(function(muts) {
                muts.forEach(function(m) {
                    m.addedNodes.forEach(function(n) {
                        if (n.nodeType !== 1) return;
                        if (n.tagName === 'PB-PANEL') {
                            new GsEntityAside(n);
                        } else if (n.querySelectorAll) {
                            n.querySelectorAll('pb-panel').forEach(function(p) {
                                new GsEntityAside(p);
                            });
                        }
                    });
                });
            }).observe(grid, { childList: true, subtree: true });
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
