#!/usr/bin/env python3
"""Push App Store listing assets (metadata + screenshots) to App Store Connect.

Source of truth is the repo:

    appstore/metadata/<locale>/
        name.txt               -> app name           (app-level, 30 chars)
        subtitle.txt           -> subtitle           (app-level, 30 chars)
        privacy_policy_url.txt -> privacy policy URL (app-level)
        description.txt        -> description        (per version, 4000 chars)
        keywords.txt           -> keywords           (per version, 100 chars)
        promotional_text.txt   -> promotional text   (per version, 170 chars)
        release_notes.txt      -> "What's New"       (per version, 4000 chars)
        support_url.txt        -> support URL        (per version)
        marketing_url.txt      -> marketing URL      (per version)

    appstore/screenshots/<locale>/<DISPLAY_TYPE>/*.png
        DISPLAY_TYPE is the raw App Store Connect enum value, e.g.
        APP_IPHONE_67 (top iPhone slot — takes all 6.9" sizes) or
        APP_IPAD_PRO_3GEN_129 (13" iPad, 2064x2752).
        Files are uploaded in sorted filename order (01-..., 02-..., ...).

Missing files are simply skipped, so partial metadata directories are fine.
Screenshot sets are only re-uploaded when the local files differ (MD5) from
what App Store Connect already has, so the workflow is idempotent.

Auth: ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_P8 (base64 or raw PEM)
environment variables — the same App Manager key the TestFlight workflow uses.

Needs: pip install PyJWT cryptography
"""

import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
from pathlib import Path
from urllib.request import Request, urlopen

import jwt

API = "https://api.appstoreconnect.apple.com"

# App Store version / app info states in which metadata is still editable.
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "METADATA_REJECTED",
    "REJECTED",
    "DEVELOPER_REJECTED",
    "INVALID_BINARY",
    "WAITING_FOR_REVIEW",  # editable after "developer reject", kept for safety
}

VERSION_LOC_FIELDS = {
    "description.txt": "description",
    "keywords.txt": "keywords",
    "promotional_text.txt": "promotionalText",
    "release_notes.txt": "whatsNew",
    "support_url.txt": "supportUrl",
    "marketing_url.txt": "marketingUrl",
}

APP_INFO_LOC_FIELDS = {
    "name.txt": "name",
    "subtitle.txt": "subtitle",
    "privacy_policy_url.txt": "privacyPolicyUrl",
}


def log(msg):
    print(msg, flush=True)


class Client:
    def __init__(self):
        self.key_id = os.environ["ASC_API_KEY_ID"]
        self.issuer = os.environ["ASC_API_ISSUER_ID"]
        raw = os.environ["ASC_API_KEY_P8"]
        self.key = raw if "BEGIN" in raw else base64.b64decode(raw).decode()

    def _token(self):
        now = int(time.time())
        return jwt.encode(
            {"iss": self.issuer, "iat": now, "exp": now + 600,
             "aud": "appstoreconnect-v1"},
            self.key, algorithm="ES256", headers={"kid": self.key_id})

    def call(self, method, path, body=None, retries=3):
        for attempt in range(retries):
            req = Request(
                API + path if path.startswith("/") else path, method=method,
                headers={"Authorization": f"Bearer {self._token()}",
                         "Content-Type": "application/json"},
                data=json.dumps(body).encode() if body is not None else None)
            try:
                with urlopen(req) as resp:
                    data = resp.read()
                    return json.loads(data) if data else {}
            except urllib.error.HTTPError as err:
                detail = err.read().decode(errors="replace")
                if err.code >= 500 and attempt < retries - 1:
                    time.sleep(10)
                    continue
                raise RuntimeError(
                    f"{method} {path} failed ({err.code}): {detail}") from err

    def paged(self, path):
        items = []
        url = path
        while url:
            page = self.call("GET", url)
            items.extend(page.get("data", []))
            url = page.get("links", {}).get("next")
        return items


def read_field(directory, filename, limit=None):
    p = directory / filename
    if not p.is_file():
        return None
    text = p.read_text(encoding="utf-8").strip()
    if not text:
        return None
    if limit and len(text) > limit:
        sys.exit(f"{p}: {len(text)} chars exceeds the {limit}-char limit")
    return text


def state_of(resource):
    attrs = resource.get("attributes", {})
    return attrs.get("appVersionState") or attrs.get("appStoreState") or attrs.get("state")


# --- metadata -----------------------------------------------------------------

def find_or_create_version(client, app_id, version_string, dry_run):
    versions = client.call(
        "GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20"
    )["data"]
    editable = [v for v in versions if state_of(v) in EDITABLE_STATES]
    if version_string:
        for v in editable:
            if v["attributes"]["versionString"] == version_string:
                return v
        if dry_run:
            log(f"[dry-run] would create App Store version {version_string}")
            return None
        log(f"Creating App Store version {version_string}")
        return client.call("POST", "/v1/appStoreVersions", {
            "data": {"type": "appStoreVersions",
                     "attributes": {"platform": "IOS",
                                    "versionString": version_string},
                     "relationships": {"app": {"data": {"type": "apps",
                                                        "id": app_id}}}}})["data"]
    if editable:
        return editable[0]
    states = {v["attributes"]["versionString"]: state_of(v) for v in versions}
    sys.exit(f"No editable App Store version found (existing: {states}). "
             "Pass --version X.Y.Z to create one.")


def push_version_metadata(client, version, locale_dir, locale, dry_run):
    fields = {}
    for fname, attr in VERSION_LOC_FIELDS.items():
        limit = {"description": 4000, "keywords": 100,
                 "promotionalText": 170, "whatsNew": 4000}.get(attr)
        value = read_field(locale_dir, fname, limit)
        if value is not None:
            fields[attr] = value
    if not fields:
        return
    locs = client.call(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    existing = {l["attributes"]["locale"]: l for l in locs}
    if dry_run:
        log(f"[dry-run] {locale}: would set {sorted(fields)}")
        return
    if locale in existing:
        loc_id = existing[locale]["id"]
        try:
            client.call("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", {
                "data": {"id": loc_id, "type": "appStoreVersionLocalizations",
                         "attributes": fields}})
        except RuntimeError as err:
            # whatsNew is rejected on an app's very first version — retry without.
            if "whatsNew" in fields and "whatsNew" in str(err):
                log(f"  {locale}: whatsNew rejected (first version?) — skipping it")
                fields.pop("whatsNew")
                if fields:
                    client.call(
                        "PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", {
                            "data": {"id": loc_id,
                                     "type": "appStoreVersionLocalizations",
                                     "attributes": fields}})
            else:
                raise
    else:
        client.call("POST", "/v1/appStoreVersionLocalizations", {
            "data": {"type": "appStoreVersionLocalizations",
                     "attributes": {"locale": locale, **fields},
                     "relationships": {"appStoreVersion": {
                         "data": {"type": "appStoreVersions",
                                  "id": version["id"]}}}}})
    log(f"  {locale}: set {sorted(fields)}")


def push_app_info_metadata(client, app_id, locale_dir, locale, dry_run):
    fields = {}
    for fname, attr in APP_INFO_LOC_FIELDS.items():
        limit = {"name": 30, "subtitle": 30}.get(attr)
        value = read_field(locale_dir, fname, limit)
        if value is not None:
            fields[attr] = value
    if not fields:
        return
    infos = client.call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    editable = [i for i in infos if state_of(i) in EDITABLE_STATES]
    if not editable:
        log(f"  {locale}: no editable app info (name/subtitle) — skipping")
        return
    info_id = editable[0]["id"]
    locs = client.call(
        "GET", f"/v1/appInfos/{info_id}/appInfoLocalizations")["data"]
    existing = {l["attributes"]["locale"]: l for l in locs}
    if dry_run:
        log(f"[dry-run] {locale}: would set app-level {sorted(fields)}")
        return
    if locale in existing:
        loc_id = existing[locale]["id"]
        client.call("PATCH", f"/v1/appInfoLocalizations/{loc_id}", {
            "data": {"id": loc_id, "type": "appInfoLocalizations",
                     "attributes": fields}})
    else:
        client.call("POST", "/v1/appInfoLocalizations", {
            "data": {"type": "appInfoLocalizations",
                     "attributes": {"locale": locale, **fields},
                     "relationships": {"appInfo": {
                         "data": {"type": "appInfos", "id": info_id}}}}})
    log(f"  {locale}: set app-level {sorted(fields)}")


# --- screenshots --------------------------------------------------------------

def upload_binary(client, upload_operations, data):
    for op in upload_operations:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        req = Request(op["url"], method=op["method"], data=chunk, headers=headers)
        with urlopen(req) as resp:
            resp.read()


def push_screenshot_set(client, loc_id, display_type, shot_set, files, dry_run):
    # NOTE: shot_set is matched by the caller on the attribute, never via a
    # filter query — ASC silently ignores unsupported filter params on the
    # localization relationship, which once routed iPhone uploads into the
    # iPad set (IMAGE_INCORRECT_DIMENSIONS on perfectly valid files).
    local = [(f.name, hashlib.md5(f.read_bytes()).hexdigest()) for f in files]

    if shot_set:
        remote_shots = client.paged(
            f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots?limit=50")
        remote = [(s["attributes"].get("fileName"),
                   s["attributes"].get("sourceFileChecksum")) for s in remote_shots]
        if remote == local:
            log(f"    {display_type}: unchanged ({len(files)} screenshots)")
            return
    if dry_run:
        log(f"    [dry-run] {display_type}: would upload {len(files)} screenshots")
        return

    if not shot_set:
        shot_set = client.call("POST", "/v1/appScreenshotSets", {
            "data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": display_type},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations",
                                  "id": loc_id}}}}})["data"]
        remote_shots = []
        log(f"    {display_type}: created set")
    else:
        log(f"    {display_type}: replacing {len(remote_shots)} screenshots")

    for shot in remote_shots:
        client.call("DELETE", f"/v1/appScreenshots/{shot['id']}")

    ids = []
    for f in files:
        data = f.read_bytes()
        reservation = client.call("POST", "/v1/appScreenshots", {
            "data": {"type": "appScreenshots",
                     "attributes": {"fileName": f.name, "fileSize": len(data)},
                     "relationships": {"appScreenshotSet": {
                         "data": {"type": "appScreenshotSets",
                                  "id": shot_set["id"]}}}}})["data"]
        upload_binary(client, reservation["attributes"]["uploadOperations"], data)
        client.call("PATCH", f"/v1/appScreenshots/{reservation['id']}", {
            "data": {"id": reservation["id"], "type": "appScreenshots",
                     "attributes": {"uploaded": True,
                                    "sourceFileChecksum":
                                        hashlib.md5(data).hexdigest()}}})
        ids.append(reservation["id"])
        log(f"    {display_type}: uploaded {f.name}")

    # Wait for asset processing so failures surface in the workflow run.
    deadline = time.time() + 300
    pending = dict.fromkeys(ids)
    while pending and time.time() < deadline:
        for sid in list(pending):
            shot = client.call("GET", f"/v1/appScreenshots/{sid}")["data"]
            st = (shot["attributes"].get("assetDeliveryState") or {}).get("state")
            if st == "FAILED":
                sys.exit(f"Screenshot {shot['attributes'].get('fileName')} "
                         f"failed processing: {shot['attributes']}")
            if st != "UPLOAD_COMPLETE" and st != "AWAITING_UPLOAD":
                pending.pop(sid)
        if pending:
            time.sleep(5)
    if pending:
        log(f"    {display_type}: warning — {len(pending)} screenshots still "
            "processing after 5 min (check App Store Connect)")

    # Enforce display order explicitly (sorted filename order).
    client.call(
        "PATCH", f"/v1/appScreenshotSets/{shot_set['id']}/relationships/appScreenshots",
        {"data": [{"type": "appScreenshots", "id": i} for i in ids]})


def push_screenshots(client, version, screenshots_dir, dry_run):
    locs = client.call(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    loc_by_locale = {l["attributes"]["locale"]: l for l in locs}
    for locale_dir in sorted(p for p in screenshots_dir.iterdir() if p.is_dir()):
        locale = locale_dir.name
        if locale not in loc_by_locale:
            log(f"  {locale}: no version localization — push metadata first")
            continue
        log(f"  {locale}:")
        loc_id = loc_by_locale[locale]["id"]
        type_dirs = sorted(p for p in locale_dir.iterdir() if p.is_dir())
        # The repo is the source of truth for managed locales: drop remote
        # sets whose display type has no local directory (e.g. leftovers from
        # a renamed slot).
        remote_sets = client.call(
            "GET",
            f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]
        set_by_type = {}
        wanted = {d.name for d in type_dirs}
        for s in remote_sets:
            dtype = s["attributes"]["screenshotDisplayType"]
            if dtype in wanted:
                set_by_type[dtype] = s
            elif dry_run:
                log(f"    [dry-run] {dtype}: would delete stale set")
            else:
                client.call("DELETE", f"/v1/appScreenshotSets/{s['id']}")
                log(f"    {dtype}: deleted stale set")
        for type_dir in type_dirs:
            files = sorted(type_dir.glob("*.png")) + sorted(type_dir.glob("*.jpg"))
            if files:
                push_screenshot_set(client, loc_id, type_dir.name,
                                    set_by_type.get(type_dir.name), files,
                                    dry_run)


# --- main ---------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bundle-id", default="ltd.herrmann.MotoManager")
    ap.add_argument("--version", help="version string to target; created in "
                    "App Store Connect if it does not exist yet")
    ap.add_argument("--metadata-dir", type=Path, default=Path("appstore/metadata"))
    ap.add_argument("--screenshots-dir", type=Path,
                    default=Path("appstore/screenshots"))
    ap.add_argument("--skip-metadata", action="store_true")
    ap.add_argument("--skip-screenshots", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    client = Client()
    apps = client.call(
        "GET", f"/v1/apps?filter[bundleId]={args.bundle_id}")["data"]
    if not apps:
        sys.exit(f"No app with bundle id {args.bundle_id} in App Store Connect")
    app_id = apps[0]["id"]

    version = find_or_create_version(client, app_id, args.version, args.dry_run)
    if version:
        log(f"Target version: {version['attributes']['versionString']} "
            f"({state_of(version)})")
    elif args.dry_run:
        log("[dry-run] stopping — version does not exist yet")
        return

    if not args.skip_metadata and args.metadata_dir.is_dir():
        log("Metadata:")
        for locale_dir in sorted(p for p in args.metadata_dir.iterdir()
                                 if p.is_dir()):
            push_version_metadata(client, version, locale_dir,
                                  locale_dir.name, args.dry_run)
            push_app_info_metadata(client, app_id, locale_dir,
                                   locale_dir.name, args.dry_run)

    if not args.skip_screenshots and args.screenshots_dir.is_dir():
        log("Screenshots:")
        push_screenshots(client, version, args.screenshots_dir, args.dry_run)

    log("Done.")


if __name__ == "__main__":
    main()
