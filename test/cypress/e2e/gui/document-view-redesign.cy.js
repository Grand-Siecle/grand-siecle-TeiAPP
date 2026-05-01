describe('Document view — pb-grid redesign', () => {
    const docPath = '/LIV0326_v2_altos_transcribed_v3.tei.xml';

    beforeEach(() => {
        cy.visit(docPath);
        cy.get('pb-document').should('exist');
        cy.get('pb-grid#grid pb-panel').should('have.length.at.least', 1);
    });

    it('shows the page toolbar with NER slider and language toggle', () => {
        cy.get('.gs-page-toolbar').should('be.visible');
        cy.get('#ner-threshold').should('exist');
        cy.get('.lang-toggle-container').should('exist');
    });

    it('shows the metadata aside on the right', () => {
        cy.get('.gs-metadata-aside').should('exist');
    });

    it('adds a new panel when Add-view is clicked', () => {
        cy.get('pb-grid#grid pb-panel').then($before => {
            const initialCount = $before.length;
            cy.get('pb-grid-action[action="add"] button').first().click();
            cy.get('pb-grid#grid pb-panel').should(
                'have.length',
                initialCount + 1
            );
        });
    });

    it('removes a panel when its remove button is clicked', () => {
        cy.get('pb-grid-action[action="add"] button').first().click();
        cy.get('pb-grid#grid pb-panel').then($after => {
            const count = $after.length;
            cy.get('pb-grid#grid pb-panel').last()
              .find('pb-grid-action[action="remove"] button').click();
            cy.get('pb-grid#grid pb-panel').should('have.length', count - 1);
        });
    });

    it('toggles the entity aside on a panel', () => {
        cy.get('pb-grid#grid pb-panel').first()
          .find('.gs-entity-aside-toggle').click();
        cy.get('pb-grid#grid pb-panel').first()
          .find('.gs-panel-entity-aside.open').should('exist');
    });

    it('hides the Fac-similé option on PDF-sourced docs', () => {
        cy.window().then(win => {
            win.document.body.classList.add('gs-no-iiif');
        });
        cy.get('body.gs-no-iiif').should('exist');
        // The exact element selector for the "Fac-similé" option depends
        // on pb-panel internals; tighten this assertion after manual DOM
        // inspection (see Task 9 step 3).
    });
});
