// ==UserScript==
// @name         Return YouTube dislike
// @namespace    evan.qutebrowser
// @version      1.0.0
// @description  Show the dislike count on watch pages again, using the Return YouTube Dislike API.
// @match        https://www.youtube.com/*
// @match        https://youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

// Privacy: the id of every watched video is sent to returnyoutubedislikeapi.com,
// a third party unrelated to YouTube.

(() => {
    'use strict';

    const POLL_MS = 250;
    const MAX_TRIES = 40; // give the button ~10s to render on a slow load

    const countCache = new Map();
    let timer = null;

    // YouTube truncates rather than rounds: 1999 shows as 1.9K, and the
    // decimal is dropped once the mantissa reaches double digits.
    const formatCount = (count) => {
        const units = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K']];
        for (const [size, suffix] of units) {
            if (count >= size) {
                const value = Math.floor((count / size) * 10) / 10;
                const digits = value < 10 && !Number.isInteger(value) ? 1 : 0;
                return `${value.toFixed(digits)}${suffix}`;
            }
        }
        return String(count);
    };

    const currentVideoId = () => location.pathname === '/watch'
        ? new URLSearchParams(location.search).get('v')
        : null;

    const getDislikes = (videoId) => {
        if (!countCache.has(videoId)) {
            countCache.set(
                videoId,
                fetch(`https://returnyoutubedislikeapi.com/votes?videoId=${encodeURIComponent(videoId)}`)
                    .then((response) => response.ok ? response.json() : null)
                    .then((data) => data && !data.deleted && Number.isFinite(data.dislikes)
                        ? data.dislikes
                        : null)
                    .catch(() => null),
            );
        }
        return countCache.get(videoId);
    };

    // Keyed off aria-label, which is stable user-visible text; YouTube's
    // generated class names change every few weeks.
    const findDislikeButton = () => {
        const candidates = [
            'dislike-button-view-model button[aria-label]',
            'ytd-watch-metadata button[aria-label*="islike"]',
            '#actions button[aria-label*="islike"]',
            'button[aria-label*="islike"]',
        ];
        for (const selector of candidates) {
            for (const button of document.querySelectorAll(selector)) {
                if (/dislike/i.test(button.getAttribute('aria-label') || '')) {
                    return button;
                }
            }
        }
        return null;
    };

    // The dislike button usually renders with no text node at all, so mirror
    // whatever wrapper the like button uses instead of inventing markup.
    const labelElement = (button) => {
        const existing = button.querySelector('[class*="button-text-content"]');
        if (existing) return existing;

        const like = document.querySelector('like-button-view-model button[aria-label]');
        const template = like?.querySelector('[class*="button-text-content"]');
        if (!template) return null;

        const label = document.createElement(template.tagName);
        label.className = template.className;
        button.append(label);
        return label;
    };

    const paint = (videoId, dislikes) => {
        // A fetch started on the previous video must never write here.
        if (dislikes === null || currentVideoId() !== videoId) return;

        const button = findDislikeButton();
        if (!button) return false;

        const label = labelElement(button);
        if (!label) return false;

        const text = formatCount(dislikes);
        if (label.textContent !== text) label.textContent = text;
        return true;
    };

    const apply = () => {
        if (timer !== null) {
            clearInterval(timer);
            timer = null;
        }

        const videoId = currentVideoId();
        if (!videoId) return;

        getDislikes(videoId).then((dislikes) => {
            if (dislikes === null || currentVideoId() !== videoId) return;

            let tries = 0;
            timer = setInterval(() => {
                if (currentVideoId() !== videoId || paint(videoId, dislikes) !== false ||
                        ++tries >= MAX_TRIES) {
                    clearInterval(timer);
                    timer = null;
                }
            }, POLL_MS);
        });
    };

    window.addEventListener('yt-navigate-finish', apply);
    apply();
})();
