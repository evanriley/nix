// ==UserScript==
// @name         Middle-click autoscroll
// @namespace    evan.qutebrowser
// @version      1.0.0
// @description  Firefox-style middle-click autoscrolling for qutebrowser.
// @match        http://*/*
// @match        https://*/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(() => {
    'use strict';

    const DEAD_ZONE = 12;
    const MAX_SPEED = 72;
    const interactiveSelector = [
        'a', 'area', 'button', 'input', 'label', 'option', 'select',
        'textarea', 'video', 'audio', '[contenteditable]', '[role="button"]',
        '[role="link"]',
    ].join(',');

    let active = false;
    let originX = 0;
    let originY = 0;
    let pointerX = 0;
    let pointerY = 0;
    let scrollTarget = null;
    let marker = null;
    let frame = null;
    let suppressAuxClick = false;

    const scrollableParent = (start) => {
        for (let element = start; element && element !== document.body;
             element = element.parentElement) {
            const style = getComputedStyle(element);
            const overflowX = style.overflowX;
            const overflowY = style.overflowY;
            const canScrollX = /(auto|scroll)/.test(overflowX) &&
                element.scrollWidth > element.clientWidth;
            const canScrollY = /(auto|scroll)/.test(overflowY) &&
                element.scrollHeight > element.clientHeight;
            if (canScrollX || canScrollY) return element;
        }
        return document.scrollingElement || document.documentElement;
    };

    const velocity = (distance) => {
        const direction = Math.sign(distance);
        const magnitude = Math.max(0, Math.abs(distance) - DEAD_ZONE);
        return direction * Math.min(MAX_SPEED, Math.pow(magnitude, 1.28) / 18);
    };

    const removeMarker = () => {
        marker?.remove();
        marker = null;
    };

    const stop = () => {
        if (!active) return;
        active = false;
        scrollTarget = null;
        removeMarker();
        if (frame !== null) cancelAnimationFrame(frame);
        frame = null;
    };

    const tick = () => {
        if (!active) return;
        scrollTarget.scrollBy({
            left: velocity(pointerX - originX),
            top: velocity(pointerY - originY),
            behavior: 'instant',
        });
        frame = requestAnimationFrame(tick);
    };

    const makeMarker = () => {
        const dark = matchMedia('(prefers-color-scheme: dark)').matches;
        const element = document.createElement('div');
        element.textContent = '↕';
        Object.assign(element.style, {
            position: 'fixed',
            left: `${originX - 15}px`,
            top: `${originY - 15}px`,
            width: '28px',
            height: '28px',
            lineHeight: '26px',
            textAlign: 'center',
            color: dark ? '#ffffff' : '#000000',
            background: dark ? '#1e1e1e' : '#f2f2f2',
            border: `2px solid ${dark ? '#2fafff' : '#0031a9'}`,
            borderRadius: '50%',
            boxShadow: '0 2px 8px rgba(0, 0, 0, 0.35)',
            font: 'bold 18px sans-serif',
            pointerEvents: 'none',
            zIndex: '2147483647',
            boxSizing: 'border-box',
        });
        (document.body || document.documentElement).append(element);
        return element;
    };

    addEventListener('mousedown', (event) => {
        if (active) {
            event.preventDefault();
            event.stopImmediatePropagation();
            stop();
            return;
        }

        if (event.button !== 1 || event.target.closest(interactiveSelector)) {
            return;
        }

        event.preventDefault();
        event.stopImmediatePropagation();
        originX = pointerX = event.clientX;
        originY = pointerY = event.clientY;
        scrollTarget = scrollableParent(event.target);
        active = true;
        suppressAuxClick = true;
        marker = makeMarker();
        frame = requestAnimationFrame(tick);
    }, true);

    addEventListener('mousemove', (event) => {
        if (!active) return;
        pointerX = event.clientX;
        pointerY = event.clientY;
    }, true);

    addEventListener('auxclick', (event) => {
        if (!suppressAuxClick) return;
        suppressAuxClick = false;
        event.preventDefault();
        event.stopImmediatePropagation();
    }, true);

    addEventListener('keydown', (event) => {
        if (active && event.key === 'Escape') {
            event.preventDefault();
            event.stopImmediatePropagation();
            stop();
        }
    }, true);

    addEventListener('wheel', stop, {capture: true, passive: true});
    addEventListener('blur', stop);
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) stop();
    });
})();
