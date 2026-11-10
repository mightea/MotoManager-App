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

    appstore/review/
        notes.txt              -> App Review notes (per version, 4000 chars);
                                  {{DEMO_SERVER_URL}} is filled from the
                                  environment — the host is not kept in
                                  the repo
        demo_account.txt       -> reviewer demo account username
        demo_password.txt      -> reviewer demo account password
        (contact name/phone/email come from the ASC_REVIEW_CONTACT_FIRST_NAME
        / _LAST_NAME / _PHONE / _EMAIL environment or the values already in
        App Store Connect — personal data is not kept in the repo)

    appstore/availability.txt
        territory codes (ISO 3166-1 alpha-3, one per line) the app is sold
        in; everything else is switched off, as is "available in new
        territories"

    appstore/screenshots/<locale>/<DISPLAY_TYPE>/*.png
        DISPLAY_TYPE is the raw App Store Connect enum value:
        APP_IPHONE_61 (REQUIRED — "iPhone with Dynamic Island, medium",
        1206x2622), APP_IPHONE_67 (large display, 1260x2736),
        APP_IPHONE_DUO (iPhone Duo outer 1398x2034 / inner 2007x2853; not
        yet in Apple's OpenAPI enum but accepted by the live API) and
        APP_IPAD_PRO_3GEN_129 (REQUIRED for iPad, 2064x2752).
        Files are uploaded in sorted filename order (01-..., 02-..., ...).

--version X.Y.Z targets (creating or renaming) the editable App Store
version; --attach-build selects the newest processed build with that
marketing version, which is also what gives the listing its icon.

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
import re
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


def expand_placeholders(text, source):
    """Fill {{NAME}} from the environment; deployment hosts are secrets, not
    repo content. An unset placeholder aborts the run rather than shipping
    "{{...}}" to App Review."""
    def value_of(match):
        value = os.environ.get(match.group(1), "").strip()
        if not value:
            sys.exit(f"{source}: {match.group(0)} needs the {match.group(1)} "
                     "environment variable (GitHub secret)")
        return value
    return re.sub(r"\{\{([A-Z][A-Z0-9_]*)\}\}", value_of, text)


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
        if editable:
            # Only one version can be editable at a time, so a differing
            # string means the placeholder version must be renamed (ASC
            # allows that while it is still in preparation). Builds are only
            # selectable when their marketing version matches this string.
            v = editable[0]
            current = v["attributes"]["versionString"]
            if dry_run:
                log(f"[dry-run] would rename App Store version {current} "
                    f"-> {version_string}")
                return v
            log(f"Renaming App Store version {current} -> {version_string}")
            return client.call("PATCH", f"/v1/appStoreVersions/{v['id']}", {
                "data": {"id": v["id"], "type": "appStoreVersions",
                         "attributes": {"versionString": version_string}}})["data"]
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


REVIEW_CONTACT_ENV = {
    "contactFirstName": "ASC_REVIEW_CONTACT_FIRST_NAME",
    "contactLastName": "ASC_REVIEW_CONTACT_LAST_NAME",
    "contactPhone": "ASC_REVIEW_CONTACT_PHONE",
    "contactEmail": "ASC_REVIEW_CONTACT_EMAIL",
}


def push_review_details(client, version, review_dir, dry_run):
    """Notes + demo account shown to App Review (appStoreReviewDetail).

    App Store Connect requires the four contact attributes on every update,
    so they are taken from the ASC_REVIEW_CONTACT_* environment (secrets)
    or, failing that, from the values already stored in App Store Connect.
    Personal data never lives in the repo."""
    fields = {}
    notes = read_field(review_dir, "notes.txt", 4000)
    if notes is not None:
        fields["notes"] = expand_placeholders(notes, review_dir / "notes.txt")
    demo_user = read_field(review_dir, "demo_account.txt")
    demo_password = read_field(review_dir, "demo_password.txt")
    if demo_user and demo_password:
        fields.update({"demoAccountName": demo_user,
                       "demoAccountPassword": demo_password,
                       "demoAccountRequired": True})
    if not fields:
        return
    try:
        existing = client.call(
            "GET",
            f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]
    except RuntimeError as err:
        if "404" not in str(err):
            raise
        existing = None
    stored = (existing or {}).get("attributes", {})
    for attr, env_name in REVIEW_CONTACT_ENV.items():
        value = os.environ.get(env_name, "").strip() or stored.get(attr)
        if value:
            fields[attr] = value
    missing = [a for a in REVIEW_CONTACT_ENV if a not in fields]
    if dry_run:
        verb = "update" if existing else "create"
        log(f"[dry-run] review details: would {verb} {sorted(fields)}"
            + (f" (contact missing: {missing})" if missing else ""))
        return
    try:
        if existing:
            client.call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {
                "data": {"id": existing["id"], "type": "appStoreReviewDetails",
                         "attributes": fields}})
        else:
            client.call("POST", "/v1/appStoreReviewDetails", {
                "data": {"type": "appStoreReviewDetails",
                         "attributes": fields,
                         "relationships": {"appStoreVersion": {
                             "data": {"type": "appStoreVersions",
                                      "id": version["id"]}}}}})
    except RuntimeError as err:
        if "contact" in str(err):
            log(f"  review details: NOT updated — App Store Connect requires "
                f"the review contact ({', '.join(missing) or 'all fields'}). "
                "Set the ASC_REVIEW_CONTACT_* secrets or enter the contact "
                "once in App Store Connect → App Review Information.")
            return
        raise
    log(f"  review details: set {sorted(fields)}")


def attach_build(client, app_id, version, dry_run):
    """Select the newest processed build whose marketing version matches the
    App Store version. The listing's icon in App Store Connect comes from
    this build, so a version without one shows the placeholder grid."""
    vstring = version["attributes"]["versionString"]
    current = client.call(
        "GET", f"/v1/appStoreVersions/{version['id']}/build").get("data")
    builds = client.call(
        "GET", f"/v1/builds?filter[app]={app_id}"
               f"&filter[preReleaseVersion.version]={vstring}"
               f"&filter[processingState]=VALID&sort=-uploadedDate&limit=1"
    )["data"]
    if not builds:
        log(f"  no processed build with version {vstring} — upload one "
            "(TestFlight workflow) before attaching")
        return
    build = builds[0]
    number = build["attributes"]["version"]
    if current and current["id"] == build["id"]:
        log(f"  build {vstring} ({number}) already attached")
        return
    if dry_run:
        log(f"[dry-run] would attach build {vstring} ({number})")
        return
    client.call("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build",
                {"data": {"type": "builds", "id": build["id"]}})
    log(f"  attached build {vstring} ({number})")


# --- availability --------------------------------------------------------------

def read_territories(path):
    if not path.is_file():
        return None
    codes = []
    for line in path.read_text(encoding="utf-8").splitlines():
        code = line.split("#", 1)[0].strip().upper()
        if code:
            codes.append(code)
    return codes


def territory_rows(client, availability_id):
    # The territory relationship is only serialized when it is included.
    rows = client.paged(
        f"/v2/appAvailabilities/{availability_id}/territoryAvailabilities"
        "?include=territory&fields[territoryAvailabilities]=available,territory"
        "&fields[territories]=currency&limit=200")
    out = {}
    for r in rows:
        territory = r.get("relationships", {}).get("territory", {}).get("data")
        if not territory:
            sys.exit(f"availability: territory missing on row {r.get('id')} "
                     f"(keys: {sorted(r)})")
        out[territory["id"]] = r
    return out


def push_availability(client, app_id, wanted, dry_run):
    """Make the app available in exactly the listed territories (ISO 3166-1
    alpha-3, e.g. CHE) and not in territories Apple adds later."""
    wanted = set(wanted)
    availability = client.call(
        "GET", f"/v1/apps/{app_id}/appAvailabilityV2")["data"]
    avail_id = availability["id"]
    new_territories = availability["attributes"].get("availableInNewTerritories")
    rows = territory_rows(client, avail_id)
    current = {code for code, r in rows.items() if r["attributes"]["available"]}
    unknown = wanted - set(rows)
    if unknown:
        sys.exit(f"availability: unknown territory codes {sorted(unknown)}")
    if current == wanted and new_territories is False:
        log(f"  availability: unchanged ({', '.join(sorted(wanted))})")
        return
    log(f"  availability: {len(current)} territories now, want "
        f"{', '.join(sorted(wanted))}; new territories: {new_territories}")
    if dry_run:
        log("[dry-run] availability: would replace the territory set")
        return
    # A POST creates a replacement availability for the app (this is what
    # the "Pricing and Availability" page does); included resources use
    # temporary ${...} ids.
    included, links = [], []
    for code in sorted(wanted):
        tmp = "${ta-" + code.lower() + "}"
        links.append({"type": "territoryAvailabilities", "id": tmp})
        included.append({
            "type": "territoryAvailabilities", "id": tmp,
            "attributes": {"available": True},
            "relationships": {"territory": {
                "data": {"type": "territories", "id": code}}}})
    try:
        client.call("POST", "/v2/appAvailabilities", {
            "data": {"type": "appAvailabilities",
                     "attributes": {"availableInNewTerritories": False},
                     "relationships": {
                         "app": {"data": {"type": "apps", "id": app_id}},
                         "territoryAvailabilities": {"data": links}}},
            "included": included})
    except RuntimeError as err:
        log(f"  availability: replace failed ({str(err)[:300]}) — "
            "falling back to per-territory updates")
    # Verify, and fix any territory the replacement left untouched.
    availability = client.call(
        "GET", f"/v1/apps/{app_id}/appAvailabilityV2")["data"]
    rows = territory_rows(client, availability["id"])
    fixed = 0
    for code, row in sorted(rows.items()):
        should = code in wanted
        if row["attributes"]["available"] != should:
            client.call("PATCH", f"/v1/territoryAvailabilities/{row['id']}", {
                "data": {"id": row["id"], "type": "territoryAvailabilities",
                         "attributes": {"available": should}}})
            fixed += 1
    final = {c for c, r in territory_rows(client, availability["id"]).items()
             if r["attributes"]["available"]}
    new_territories = availability["attributes"].get("availableInNewTerritories")
    log(f"  availability: now {', '.join(sorted(final)) or 'nowhere'}"
        f" ({fixed} territories patched); new territories: {new_territories}")
    if final != wanted:
        sys.exit("availability: territory set still differs — check "
                 "Pricing and Availability in App Store Connect")
    if new_territories is not False:
        log("  availability: WARNING — 'available in new territories' is still "
            "on; switch it off under Pricing and Availability")


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
    ap.add_argument("--review-dir", type=Path, default=Path("appstore/review"))
    ap.add_argument("--availability", type=Path,
                    default=Path("appstore/availability.txt"),
                    help="territory codes the app is sold in (one per line)")
    ap.add_argument("--attach-build", action="store_true",
                    help="select the newest processed build whose marketing "
                         "version equals the App Store version")
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

    if args.attach_build and version:
        log("Build:")
        attach_build(client, app_id, version, args.dry_run)

    if not args.skip_metadata and args.metadata_dir.is_dir():
        log("Metadata:")
        for locale_dir in sorted(p for p in args.metadata_dir.iterdir()
                                 if p.is_dir()):
            push_version_metadata(client, version, locale_dir,
                                  locale_dir.name, args.dry_run)
            push_app_info_metadata(client, app_id, locale_dir,
                                   locale_dir.name, args.dry_run)

    territories = read_territories(args.availability)
    if not args.skip_metadata and territories:
        log("Availability:")
        push_availability(client, app_id, territories, args.dry_run)

    if not args.skip_metadata and args.review_dir.is_dir():
        log("App Review:")
        push_review_details(client, version, args.review_dir, args.dry_run)

    if not args.skip_screenshots and args.screenshots_dir.is_dir():
        log("Screenshots:")
        push_screenshots(client, version, args.screenshots_dir, args.dry_run)

    log("Done.")


if __name__ == "__main__":
    main()
