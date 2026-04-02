/**
 * Grand Siècle — NER Confidence Slider
 */
(function() {
    'use strict';

    var certLevels = { 'high': 0.9, 'mid': 0.6, 'low': 0.3 };

    function parseCert(raw) {
        if (!raw) return NaN;
        var num = parseFloat(raw);
        if (!isNaN(num)) return num;
        return certLevels[raw.toLowerCase()] || NaN;
    }

    function applyThreshold(threshold) {
        var entities = document.querySelectorAll('[data-cert]');
        entities.forEach(function(el) {
            var cert = parseCert(el.getAttribute('data-cert'));
            if (isNaN(cert)) return;
            el.classList.toggle('entity-low-confidence', cert < threshold);
        });
    }

    function initNerSlider() {
        var slider = document.getElementById('ner-threshold');
        var display = document.getElementById('ner-threshold-value');
        if (!slider) return;

        slider.addEventListener('input', function() {
            var val = parseFloat(this.value);
            if (display) display.textContent = val.toFixed(2);
            applyThreshold(val);
        });
        applyThreshold(parseFloat(slider.value));
    }

    document.addEventListener('pb-update', function() {
        initNerSlider();
    });
    document.addEventListener('DOMContentLoaded', function() {
        initNerSlider();
    });
})();
