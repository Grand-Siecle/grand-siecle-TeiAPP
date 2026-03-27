/**
 * Grand Siècle — Landing page animations
 * Scroll-triggered reveals + parallax hero
 */
(function() {
    'use strict';

    /* --- Scroll reveal with Intersection Observer --- */
    var observer = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
            if (entry.isIntersecting) {
                entry.target.classList.add('gs-visible');
                observer.unobserve(entry.target);
            }
        });
    }, {
        threshold: 0.12,
        rootMargin: '0px 0px -60px 0px'
    });

    document.addEventListener('DOMContentLoaded', function() {
        /* Observe all reveal elements */
        document.querySelectorAll('.gs-reveal').forEach(function(el) {
            observer.observe(el);
        });

        /* Hero parallax on scroll */
        var hero = document.querySelector('.gs-hero');
        var heroVisual = document.querySelector('.gs-hero-visual');
        var heroContent = document.querySelector('.gs-hero-content');

        if (hero && heroVisual) {
            window.addEventListener('scroll', function() {
                var scrolled = window.pageYOffset;
                var heroHeight = hero.offsetHeight;
                if (scrolled < heroHeight) {
                    var ratio = scrolled / heroHeight;
                    heroVisual.style.transform = 'translateY(' + (scrolled * 0.15) + 'px)';
                    heroContent.style.transform = 'translateY(' + (scrolled * 0.08) + 'px)';
                    heroContent.style.opacity = 1 - (ratio * 0.6);
                }
            }, { passive: true });
        }

        /* Stagger hero elements */
        var heroEls = document.querySelectorAll('.gs-hero-kicker, .gs-hero-title-grand, .gs-hero-title-siecle, .gs-hero-subtitle, .gs-hero-cta, .gs-hero-stats, .gs-hero-frame');
        heroEls.forEach(function(el, i) {
            el.style.animationDelay = (0.2 + i * 0.12) + 's';
        });
    });
})();
