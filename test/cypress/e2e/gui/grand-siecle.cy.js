describe('Grand Siecle V1', () => {
    it('loads the landing page', () => {
        cy.visit('/');
        cy.get('body').should('exist');
    });

    it('landing page has Grand Siecle theme', () => {
        cy.visit('/');
        cy.document().then((doc) => {
            const links = Array.from(doc.querySelectorAll('link[rel="stylesheet"]'));
            const hasTheme = links.some(l => l.href.includes('grand-siecle.css'));
            expect(hasTheme).to.be.true;
        });
    });

    it('loads browse page', () => {
        cy.visit('/browse.html');
        cy.get('body').should('exist');
    });

    it('loads a document with the view template', () => {
        cy.visit('/LIV0326_v2_altos_transcribed.tei.xml');
        cy.get('pb-view').should('exist');
        cy.get('pb-view').should('have.attr', 'view', 'page');
    });

    it('document view has NER confidence slider', () => {
        cy.visit('/LIV0326_v2_altos_transcribed.tei.xml');
        cy.get('#ner-threshold').should('exist');
    });

    it('document view has the Add-view button', () => {
        cy.visit('/LIV0326_v2_altos_transcribed.tei.xml');
        cy.get('pb-grid-action[action="add"]').should('exist');
    });

    it('document view has a pb-grid with at least one panel', () => {
        cy.visit('/LIV0326_v2_altos_transcribed.tei.xml');
        cy.get('pb-grid#grid pb-panel').should('have.length.at.least', 1);
    });

    it('document view has the metadata aside', () => {
        cy.visit('/LIV0326_v2_altos_transcribed.tei.xml');
        cy.get('.gs-metadata-aside').should('exist');
    });

    it('loads the people register', () => {
        cy.visit('/people');
        cy.get('pb-split-list').should('exist');
    });

    it('loads the places register', () => {
        cy.visit('/places');
        cy.get('pb-split-list').should('exist');
    });

    it('places map is centered on France', () => {
        cy.visit('/places');
        cy.get('pb-leaflet-map').should('have.attr', 'latitude', '46.6');
    });

    it('loads the organizations register page', () => {
        cy.request('/organizations').its('status').should('eq', 200);
    });

    it('loads search page', () => {
        cy.visit('/search.html');
        cy.get('body').should('exist');
    });
});
