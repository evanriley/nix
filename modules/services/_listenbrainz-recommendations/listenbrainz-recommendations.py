#!/usr/bin/env python3
"""Monitor only albums represented in Evan's generated ListenBrainz playlists."""

import argparse
import os
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

USER = "evanriley"
LB = "https://api.listenbrainz.org/1"
MB = "https://musicbrainz.org/ws/2"
LIDARR = "http://127.0.0.1:8686/api/v1"
STATE = Path(os.environ.get("STATE_DIRECTORY", Path.home() / ".local/state/listenbrainz-recommendations"))
CACHE = STATE / "listenbrainz-release-groups.json"
ROOT_FOLDER = "/data/Music"
PROFILE_NAME = "ListenBrainz playlists"
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)
JSPF_TRACK = "https://musicbrainz.org/doc/jspf#track"
last_mb_request = 0.0


def request(url, *, key=None, method="GET", payload=None, musicbrainz=False):
    global last_mb_request
    headers = {"User-Agent": "listenbrainz-lidarr/1.0 (https://listenbrainz.org/user/evanriley/)"}
    if key:
        headers["X-Api-Key"] = key
    body = None
    if payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    for attempt in range(4):
        if musicbrainz:
            time.sleep(max(0, 1.1 - (time.monotonic() - last_mb_request)))
            last_mb_request = time.monotonic()
        try:
            req = urllib.request.Request(url, data=body, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=60) as response:
                data = response.read()
                return json.loads(data) if data else None
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 502, 503, 504) or attempt == 3:
                raise RuntimeError(f"HTTP {exc.code} from {url.split('?')[0]}") from exc
        except urllib.error.URLError:
            if attempt == 3:
                raise
        time.sleep(2 ** attempt)
    raise RuntimeError("Request retry limit reached")


def lidarr_url(path, **params):
    url = f"{LIDARR}/{path}"
    return url + ("?" + urllib.parse.urlencode(params) if params else "")


def mbid(value):
    match = UUID.search(value or "")
    return match.group().lower() if match else None


def playlists():
    found = []
    for offset in range(0, 1000, 100):
        page = request(f"{LB}/user/{USER}/playlists/createdfor?count=100&offset={offset}").get("playlists", [])
        for entry in page:
            item = entry.get("playlist", entry)
            identifier = mbid(item.get("identifier"))
            if identifier:
                found.append((item.get("title", identifier), identifier))
        if len(page) < 100:
            break
    if not found:
        raise RuntimeError("ListenBrainz returned no generated playlists")
    return found


def collect_tracks():
    releases = {}
    without_release = {}
    count = 0
    listed = playlists()
    for title, playlist_id in listed:
        tracks = request(f"{LB}/playlist/{playlist_id}")["playlist"].get("track", [])
        count += len(tracks)
        for track in tracks:
            extension = track.get("extension", {}).get(JSPF_TRACK, {})
            metadata = extension.get("additional_metadata", {})
            artist = (metadata.get("artists") or [{}])[0]
            artist_id = mbid(artist.get("artist_mbid"))
            if not artist_id:
                artist_id = mbid((extension.get("artist_identifiers") or [None])[0])
            detail = {"artist_id": artist_id, "artist": artist.get("artist_credit_name") or track.get("creator"),
                      "album": track.get("album"), "track": track.get("title")}
            release_id = mbid(metadata.get("caa_release_mbid"))
            if release_id:
                releases[release_id] = detail
            else:
                recording_id = mbid((track.get("identifier") or [None])[0])
                if recording_id:
                    without_release[recording_id] = detail
        print(f"{title}: {len(tracks)} tracks", flush=True)
    print(f"Found {len(listed)} playlists, {count} tracks, {len(releases)} releases, {len(without_release)} recordings without release IDs", flush=True)
    return releases, without_release


def save_cache(cache):
    STATE.mkdir(parents=True, exist_ok=True)
    temporary = CACHE.with_suffix(".tmp")
    temporary.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n")
    temporary.replace(CACHE)


def resolve(releases, recordings):
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {"release": {}, "recording": {}}
    cache.setdefault("release", {})
    cache.setdefault("recording", {})
    missing = sorted(release_id for release_id in releases if not cache["release"].get(release_id))
    for start in range(0, len(missing), 15):
        batch = missing[start:start + 15]
        query = " OR ".join("reid:" + value for value in batch)
        url = f"{MB}/release-group/?" + urllib.parse.urlencode({"query": query, "fmt": "json", "limit": 100})
        found = {}
        for group in request(url, musicbrainz=True).get("release-groups", []):
            artist_credit = group.get("artist-credit") or []
            artist = next((item.get("artist", {}) for item in artist_credit if isinstance(item, dict) and item.get("artist")), {})
            for release in group.get("releases", []):
                release_id = release.get("id", "").lower()
                if release_id in batch:
                    found[release_id] = {"group": group["id"].lower(), "artist": artist.get("id", "").lower(), "title": group.get("title")}
        cache["release"].update({value: found.get(value) for value in batch})
        save_cache(cache)
        print(f"MusicBrainz release mapping: {min(start + 15, len(missing))}/{len(missing)}", flush=True)
    missing_recordings = sorted(recording_id for recording_id in recordings if not cache["recording"].get(recording_id))
    for index, recording_id in enumerate(missing_recordings, 1):
        url = f"{MB}/recording/{recording_id}?" + urllib.parse.urlencode({"inc": "releases+release-groups", "fmt": "json"})
        try:
            response = request(url, musicbrainz=True)
        except RuntimeError as exc:
            if "HTTP 404" not in str(exc):
                raise
            response = {}
        groups = []
        for release in response.get("releases", []):
            group = release.get("release-group") or {}
            if group.get("id"):
                groups.append({"group": group["id"].lower(), "title": group.get("title")})
        album_name = (recordings[recording_id].get("album") or "").casefold()
        match = next((group for group in groups if (group.get("title") or "").casefold() == album_name), None)
        if not match and groups:
            match = next((group for group in groups if (group.get("title") or "").casefold().removeprefix("the ") == album_name), None)
        if not match and album_name and recordings[recording_id].get("artist_id"):
            query = "releasegroup:" + json.dumps(recordings[recording_id]["album"]) + " AND arid:" + recordings[recording_id]["artist_id"]
            url = f"{MB}/release-group/?" + urllib.parse.urlencode({"query": query, "fmt": "json", "limit": 10})
            candidates = request(url, musicbrainz=True).get("release-groups", [])
            match = next(({"group": group["id"].lower(), "title": group["title"]} for group in candidates
                          if group["title"].casefold() == album_name), None)
        if match:
            group_data = request(f"{MB}/release-group/{match['group']}?inc=artists&fmt=json", musicbrainz=True)
            credit = group_data.get("artist-credit") or []
            artist = next((item.get("artist", {}) for item in credit if isinstance(item, dict) and item.get("artist")), {})
            match["artist"] = artist.get("id", "").lower()
        cache["recording"][recording_id] = match
        save_cache(cache)
        print(f"MusicBrainz recording fallback: {index}/{len(missing_recordings)}", flush=True)
    selected = defaultdict(set)
    unresolved = []
    for release_id, detail in releases.items():
        group = cache["release"].get(release_id)
        if not group or not (group.get("artist") or detail["artist_id"]):
            unresolved.append(f"release {release_id}: {detail['artist']} / {detail['album']}")
            continue
        selected[group.get("artist") or detail["artist_id"]].add(group["group"])
    for recording_id, detail in recordings.items():
        group = cache["recording"].get(recording_id)
        if not group or not detail["artist_id"]:
            unresolved.append(f"recording {recording_id}: {detail['artist']} / {detail['album']}")
            continue
        selected[group.get("artist") or detail["artist_id"]].add(group["group"])
    return selected, unresolved


def profile(key, apply):
    profiles = request(lidarr_url("metadataprofile"), key=key)
    existing = next((item for item in profiles if item["name"] == PROFILE_NAME), None)
    if existing:
        return existing["id"]
    standard = next(item for item in profiles if item["name"] == "Standard")
    payload = {k: v for k, v in standard.items() if k != "id"}
    payload["name"] = PROFILE_NAME
    for field in ("primaryAlbumTypes", "secondaryAlbumTypes", "releaseStatuses"):
        for entry in payload[field]:
            entry["allowed"] = True
    if not apply:
        print(f"WOULD CREATE metadata profile {PROFILE_NAME}")
        return None
    return request(lidarr_url("metadataprofile"), key=key, method="POST", payload=payload)["id"]


def sync(apply):
    key = os.environ.get("LIDARR__AUTH__APIKEY")
    if not key:
        raise RuntimeError("Lidarr API key missing")
    releases, recordings = collect_tracks()
    selected, unresolved = resolve(releases, recordings)
    print(f"Selected {sum(map(len, selected.values()))} distinct albums by {len(selected)} artists; {len(unresolved)} unresolved tracks", flush=True)
    for item in unresolved:
        print("UNRESOLVED " + item)
    roots = request(lidarr_url("rootfolder"), key=key)
    root = next((item for item in roots if item["path"] == ROOT_FOLDER), None)
    if not root:
        raise RuntimeError(f"Lidarr root folder {ROOT_FOLDER} missing")
    profile_id = profile(key, apply)
    existing = {item["foreignArtistId"].lower(): item for item in request(lidarr_url("artist"), key=key)}
    added = monitored = missing_groups = failures = 0
    for artist_id, groups in sorted(selected.items()):
        artist = existing.get(artist_id)
        try:
            if not artist:
                matches = request(lidarr_url("artist/lookup", term="lidarr:" + artist_id), key=key)
                match = next((item for item in matches if item.get("foreignArtistId", "").lower() == artist_id), None)
                if not match:
                    print(f"MISSING ARTIST {artist_id}: {len(groups)} albums")
                    failures += 1
                    continue
                print(f"{'ADD' if apply else 'WOULD ADD'} {match['artistName']}: {len(groups)} playlist albums", flush=True)
                if apply:
                    match.update(rootFolderPath=ROOT_FOLDER, qualityProfileId=root["defaultQualityProfileId"],
                                 metadataProfileId=profile_id, monitored=True, monitorNewItems="none",
                                 addOptions={"monitor": "none", "monitored": True, "searchForMissingAlbums": False})
                    artist = request(lidarr_url("artist"), key=key, method="POST", payload=match)
                    existing[artist_id] = artist
                added += 1
            if not apply and not artist:
                continue
            if (artist.get("monitorNewItems") != "none" or artist.get("metadataProfileId") != profile_id or not artist.get("monitored")) and apply:
                artist.update(monitorNewItems="none", metadataProfileId=profile_id, monitored=True)
                artist = request(lidarr_url(f"artist/{artist['id']}"), key=key, method="PUT", payload=artist)
            rows = request(lidarr_url("album", artistId=artist["id"], includeAllArtistAlbums="true"), key=key)
            available = {row["foreignAlbumId"].lower(): row for row in rows}
            ids = [available[group]["id"] for group in groups if group in available and not available[group]["monitored"]]
            missing = groups - available.keys()
            if ids:
                print(f"{'MONITOR' if apply else 'WOULD MONITOR'} {artist['artistName']}: {len(ids)} albums", flush=True)
                if apply:
                    request(lidarr_url("album/monitor"), key=key, method="PUT", payload={"albumIds": ids, "monitored": True})
                monitored += len(ids)
            for group in sorted(missing):
                if not apply:
                    print(f"WOULD ADD ALBUM {artist['artistName']}: {group}", flush=True)
                    missing_groups += 1
                    continue
                matches = request(lidarr_url("album/lookup", term="lidarr:" + group), key=key)
                match = next((item for item in matches if item.get("foreignAlbumId", "").lower() == group), None)
                if match is None or match.get("artistId") != artist["id"]:
                    print(f"PENDING {artist['artistName']}: group {group} unavailable in Lidarr lookup", flush=True)
                    missing_groups += 1
                    continue
                match.update(artistId=artist["id"], monitored=True,
                             profileId=artist["qualityProfileId"],
                             addOptions={"addType": "manual", "searchForNewAlbum": False})
                try:
                    request(lidarr_url("album"), key=key, method="POST", payload=match)
                    monitored += 1
                    print(f"ADD ALBUM {artist['artistName']}: {match['title']}", flush=True)
                except RuntimeError:
                    # A concurrent artist refresh may have inserted the album.
                    fresh = request(lidarr_url("album", artistId=artist["id"], includeAllArtistAlbums="true"), key=key)
                    row = next((item for item in fresh if item["foreignAlbumId"].lower() == group), None)
                    if row is None:
                        raise
                    if not row["monitored"]:
                        request(lidarr_url("album/monitor"), key=key, method="PUT",
                                payload={"albumIds": [row["id"]], "monitored": True})
                        monitored += 1
        except (RuntimeError, urllib.error.URLError, ValueError, KeyError) as exc:
            print(f"ERROR {artist_id}: {exc}", file=sys.stderr, flush=True)
            failures += 1
    print(f"Summary: added artists={added}, monitored albums={monitored}, metadata pending={missing_groups}, unresolved tracks={len(unresolved)}, errors={failures}", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write to Lidarr; otherwise preview")
    arguments = parser.parse_args()
    try:
        raise SystemExit(sync(arguments.apply))
    except (RuntimeError, urllib.error.URLError, ET.ParseError, KeyError, TypeError, StopIteration) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
