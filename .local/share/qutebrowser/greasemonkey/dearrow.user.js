// ==UserScript==
// @name         DeArrow for YouTube
// @namespace    evan.qutebrowser
// @version      1.5.0
// @description  Replace YouTube clickbait titles and thumbnails using DeArrow submissions and frame fallbacks.
// @match        https://www.youtube.com/*
// @match        https://youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(() => {
    'use strict';

    document.documentElement.dataset.dearrowUserscript = '1.5.0';

    const brandingCache = new Map();
    const imageObservers = new WeakMap();
    let scanTimer = null;

    const trusted = (submission) =>
        submission && (submission.locked || submission.votes >= 0);

    // Stable per-video fallback in the middle 70% of the runtime. This keeps
    // thumbnails consistent between page loads even when DeArrow has no entry.
    const fallbackFraction = (videoId) => {
        let hash = 2166136261;
        for (const character of videoId) {
            hash ^= character.charCodeAt(0);
            hash = Math.imul(hash, 16777619);
        }
        return 0.15 + ((hash >>> 0) / 0xffffffff) * 0.70;
    };

    const videoIdFrom = (href) => {
        try {
            const url = new URL(href, location.origin);
            return url.pathname === '/watch' ? url.searchParams.get('v') : null;
        } catch (_) {
            return null;
        }
    };

    const getBranding = (videoId) => {
        if (!brandingCache.has(videoId)) {
            brandingCache.set(
                videoId,
                fetch(`https://sponsor.ajay.app/api/branding?videoID=${encodeURIComponent(videoId)}`)
                    .then((response) => response.ok ? response.json() : {})
                    .catch(() => ({})),
            );
        }
        return brandingCache.get(videoId);
    };

    // YouTube's lazy loader may overwrite an image after DeArrow replaces it.
    // Watch only images we have changed instead of every image on the page.
    const protectThumbnail = (image) => {
        if (imageObservers.has(image)) return;

        const observer = new MutationObserver(() => {
            const desired = image.dataset.dearrowUrl;
            if (desired && (image.src !== desired || image.srcset)) {
                image.src = desired;
                image.srcset = '';
            }
        });
        observer.observe(image, {
            attributes: true,
            attributeFilter: ['src', 'srcset'],
        });
        imageObservers.set(image, observer);
    };

    const replaceThumbnail = (
        image, urls, videoId, candidateIndex = 0, retry = 0,
    ) => {
        if (image.dataset.dearrowPending === videoId &&
            candidateIndex === 0 && retry === 0) return;
        image.dataset.dearrowPending = videoId;

        const candidates = Array.isArray(urls) ? urls : [urls];
        const url = candidates[candidateIndex];

        const probe = new Image();
        probe.onload = () => {
            if (!image.isConnected) return;
            image.dataset.dearrowUrl = probe.src;
            protectThumbnail(image);
            image.src = probe.src;
            image.srcset = '';
            image.dataset.dearrowVideo = videoId;
            delete image.dataset.dearrowPending;
        };
        probe.onerror = () => {
            if (!image.isConnected) return;

            if (candidateIndex + 1 < candidates.length) {
                delete image.dataset.dearrowPending;
                replaceThumbnail(image, candidates, videoId, candidateIndex + 1);
            } else if (candidates.length === 1 && retry < 3) {
                setTimeout(() => {
                    delete image.dataset.dearrowPending;
                    replaceThumbnail(image, candidates, videoId, 0, retry + 1);
                }, 1000 * (retry + 1));
            } else {
                // Leave YouTube's original image intact when no replacement
                // can be loaded; never turn a failed request into a blank tile.
                delete image.dataset.dearrowPending;
            }
        };
        const separator = url.includes('?') ? '&' : '?';
        probe.src = `${url}${separator}dearrowRetry=${retry}`;
    };

    const updateCard = async (card, link, videoId) => {
        card.dataset.dearrowVideo = videoId;
        const branding = await getBranding(videoId);
        if (card.dataset.dearrowVideo !== videoId) return;

        const title = branding.titles?.find(trusted);
        const titleElement = card.querySelector(
            '#video-title, #video-title-link, yt-formatted-string#video-title, h3 a',
        );
        if (title && !title.original && titleElement) {
            titleElement.textContent = title.title.replaceAll('>', '');
            titleElement.title = titleElement.textContent;
        }

        const thumbnail = branding.thumbnails?.find(
            (item) => trusted(item) && !item.original && Number.isFinite(item.timestamp),
        );
        const image = card.querySelector(
            'ytd-thumbnail img, yt-image img, img.yt-core-image, img.ytCoreImageHost',
        );
        if (image) {
            let thumbnailUrl;
            if (thumbnail) {
                const params = new URLSearchParams({
                    videoID: videoId,
                    time: String(thumbnail.timestamp),
                });
                thumbnailUrl = `https://dearrow-thumb.ajay.app/api/v1/getThumbnail?${params}`;
            } else {
                // YouTube publishes three non-clickbait frames for every
                // processed video. Pick one deterministically per video, then
                // try each resolution tier so older uploads still work.
                const frame = 1 + Math.floor(fallbackFraction(videoId) * 3);
                thumbnailUrl = ['maxres', 'sd', 'hq', 'mq'].map(
                    (tier) => `https://i.ytimg.com/vi/${videoId}/${tier}${frame}.jpg`,
                );
            }
            replaceThumbnail(image, thumbnailUrl, videoId);
        }
    };

    const scan = () => {
        scanTimer = null;
        document.querySelectorAll('a[href*="/watch?v="]').forEach((link) => {
            const videoId = videoIdFrom(link.href);
            const card = link.closest(
                'ytd-rich-item-renderer, ytd-video-renderer, ytd-grid-video-renderer, ' +
                'ytd-compact-video-renderer, ytd-playlist-video-renderer, ytd-playlist-panel-video-renderer',
            );
            const image = card?.querySelector(
                'ytd-thumbnail img, yt-image img, img.yt-core-image, img.ytCoreImageHost',
            );
            const replacementIsCurrent = image?.dataset.dearrowVideo === videoId &&
                image.src === image.dataset.dearrowUrl;
            const replacementIsPending = image?.dataset.dearrowPending === videoId;
            if (videoId && card && !replacementIsCurrent && !replacementIsPending) {
                updateCard(card, link, videoId);
            }
        });
    };

    const queueScan = () => {
        clearTimeout(scanTimer);
        scanTimer = setTimeout(scan, 120);
    };

    new MutationObserver(queueScan).observe(document.documentElement, {
        childList: true,
        subtree: true,
    });
    window.addEventListener('yt-navigate-finish', queueScan);
    queueScan();
})();
