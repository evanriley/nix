// ==UserScript==
// @name         YouTube theater mode
// @namespace    evan.qutebrowser
// @version      1.0.0
// @description  Open every watch page in theater mode instead of the narrow player with the sidebar.
// @match        https://www.youtube.com/*
// @match        https://youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(() => {
    'use strict';

    const POLL_MS = 250;
    const MAX_TRIES = 40; // give the player ~10s to show up on a slow load

    // Only ever act when we can positively tell the player is NOT already
    // wide. If YouTube renames the attribute this returns null and we do
    // nothing, rather than clicking the button and toggling theater *off*.
    const needsTheater = () => {
        const flexy = document.querySelector('ytd-watch-flexy');
        if (!flexy) return null;
        if (flexy.hasAttribute('fullscreen')) return false;
        return !flexy.hasAttribute('theater');
    };

    // Clicking YouTube's own control goes through its code, so the choice is
    // persisted the same way it would be if we had clicked it by hand.
    const clickSizeButton = () => {
        const button = document.querySelector('.ytp-size-button');
        if (!button) return false;
        button.click();
        return true;
    };

    let timer = null;

    const apply = () => {
        if (timer !== null) {
            clearInterval(timer);
            timer = null;
        }
        if (location.pathname !== '/watch') return;

        let tries = 0;
        timer = setInterval(() => {
            const wanted = needsTheater();
            // wanted === null: player not rendered yet, keep waiting.
            if (wanted === false || (wanted === true && clickSizeButton()) ||
                    ++tries >= MAX_TRIES) {
                clearInterval(timer);
                timer = null;
            }
        }, POLL_MS);
    };

    // Run once per navigation only, so leaving theater mode by hand sticks
    // for the rest of the video.
    window.addEventListener('yt-navigate-finish', apply);
    apply();
})();
