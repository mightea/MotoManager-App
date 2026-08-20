#!/usr/bin/env python3
"""Seed a scratch MotoManager API with a polished demo garage for screenshots.

Registers (or logs into) a demo account and creates three motorcycles with
eight months of fuel history, a believable service record, open workshop
issues, torque specs, tire pressures, and a stocked parts inventory. All data
is deterministic so re-running against a fresh DB produces identical
screenshots.

Usage: seed-demo-data.py [base-url]        (default http://localhost:3010)
Prints the demo credentials on success. Python stdlib only.
"""

import json
import random
import sys
import urllib.error
import urllib.request
import uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3010").rstrip("/")
USER = {"name": "Toni Muster", "email": "demo@example.com", "username": "demo",
        "password": "demo-pass-123", "confirmPassword": "demo-pass-123"}

rng = random.Random(42)
TOKEN = None


def call(method, path, body=None, multipart=None, file_field=None):
    headers = {}
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    if multipart is not None:
        boundary = uuid.uuid4().hex
        raw = b""
        for k, v in multipart.items():
            raw += (f"--{boundary}\r\nContent-Disposition: form-data; "
                    f'name="{k}"\r\n\r\n{v}\r\n').encode()
        if file_field:
            name, fname, payload = file_field
            raw += (f"--{boundary}\r\nContent-Disposition: form-data; "
                    f'name="{name}"; filename="{fname}"\r\n'
                    "Content-Type: application/pdf\r\n\r\n").encode() + payload + b"\r\n"
        data = raw + f"--{boundary}--\r\n".encode()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    else:
        data = None
    req = urllib.request.Request(BASE + path, method=method, data=data,
                                 headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        sys.exit(f"{method} {path} -> {err.code}: {err.read().decode(errors='replace')}")


def auth():
    global TOKEN
    try:
        result = call("POST", "/api/auth/register", USER)
    except SystemExit:
        result = call("POST", "/api/auth/login",
                      {"identifier": USER["username"], "password": USER["password"]})
    TOKEN = result.get("token") or result.get("accessToken")
    if not TOKEN:
        sys.exit(f"No token in auth response: {result}")


def tiny_pdf(title):
    """Minimal one-page PDF so the document vault has real files."""
    content = f"BT /F1 24 Tf 72 720 Td ({title}) Tj ET".encode()
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n"
        + content + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for i, obj in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref}\n%%EOF").encode()
    return out


def create_bike(**fields):
    result = call("POST", "/api/motorcycles", multipart=fields)
    return result["motorcycle"]["id"] if "motorcycle" in result else result["id"]


def maintenance(bike_id, **fields):
    return call("POST", f"/api/motorcycles/{bike_id}/maintenance", fields)


def fuel_history(bike_id, start_odo, consumption, tank_liters, fuel_type,
                 months, per_month):
    """Chronological fill-ups Jan..Aug 2026; server derives l/100km."""
    odo = start_odo
    for month in range(1, months + 1):
        for stop in range(per_month):
            day = min(3 + stop * (26 // max(per_month, 1)) + rng.randint(0, 3), 28)
            trip = rng.randint(180, 320)
            odo += trip
            liters = round(min(trip * consumption / 100 * rng.uniform(0.92, 1.08),
                               tank_liters - 1.0), 2)
            ppu = round(rng.uniform(1.82, 2.09), 2)
            maintenance(
                bike_id, type="fuel", date=f"2026-{month:02d}-{day:02d}T10:30:00Z",
                odo=odo, fuelType=fuel_type, fuelAmount=liters,
                pricePerUnit=ppu, cost=round(liters * ppu, 2), currency="CHF")
    return odo


def main():
    auth()

    guzzi = create_bike(
        make="Moto Guzzi", model="Le Mans 1000", fabricationDate="1985",
        isVeteran="true", numberPlate="ZH 43 210", vin="ZGUVV11B5FM112233",
        fuelTankSize="22.5", initialOdo="47800", currencyCode="CHF",
        firstRegistration="1985-04-12", purchaseDate="2018-05-01",
        purchasePrice="9800")
    gs = create_bike(
        make="BMW", model="R 1250 GS", fabricationDate="2021",
        numberPlate="ZH 98 765", fuelTankSize="20", initialOdo="11900",
        currencyCode="CHF", firstRegistration="2021-03-19",
        purchaseDate="2021-03-19", purchasePrice="21500")
    xt = create_bike(
        make="Yamaha", model="XT 600", fabricationDate="1993",
        numberPlate="ZH 7 77", fuelTankSize="15", initialOdo="30400",
        currencyCode="CHF", firstRegistration="1993-06-02",
        purchaseDate="2015-08-20", purchasePrice="3200")

    guzzi_odo = fuel_history(guzzi, 48450, 6.1, 22.5, "98", months=8, per_month=2)
    gs_odo = fuel_history(gs, 12300, 4.9, 20.0, "95", months=8, per_month=3)
    fuel_history(xt, 30700, 5.3, 15.0, "95", months=8, per_month=1)

    # Service history (newest entries land on top of the Service tab).
    maintenance(guzzi, type="fluid", fluidType="engineoil", viscosity="20W-50",
                oilType="Mineralisch", brand="Motorex", date="2026-06-14T09:00:00Z",
                odo=guzzi_odo - 600, cost=98.50, currency="CHF",
                description="Ölwechsel inkl. Filter, Ventilspiel geprüft")
    maintenance(guzzi, type="tire", tirePosition="rear", tireSize="130/80-18",
                brand="Bridgestone", model="BT46", dotCode="1225",
                date="2026-04-18T09:00:00Z", odo=guzzi_odo - 2400,
                cost=289.00, currency="CHF", description="Hinterreifen neu")
    maintenance(guzzi, type="inspection", date="2025-05-06T09:00:00Z",
                odo=guzzi_odo - 5200, cost=60.00, currency="CHF",
                description="MFK bestanden, keine Mängel")
    maintenance(gs, type="service", date="2026-05-02T09:00:00Z",
                odo=gs_odo - 1800, cost=520.00, currency="CHF",
                description="20'000er-Service beim Händler")
    maintenance(gs, type="fluid", fluidType="brakefluid",
                date="2026-03-11T09:00:00Z", odo=gs_odo - 3300, cost=85.00,
                currency="CHF", description="Bremsflüssigkeit erneuert")
    maintenance(gs, type="battery", brand="Varta", model="AGM 12V 12Ah",
                date="2025-11-20T09:00:00Z", odo=gs_odo - 4600, cost=145.00,
                currency="CHF", description="Batterie ersetzt")
    maintenance(xt, type="chain", date="2026-07-05T09:00:00Z", odo=31900,
                cost=189.00, currency="CHF",
                description="Kettensatz komplett (DID X-Ring)")
    maintenance(xt, type="brakepad", tirePosition="front",
                date="2026-02-21T09:00:00Z", odo=31200, cost=64.00,
                currency="CHF", description="Bremsbeläge vorne")

    # Workshop: open issues + torque specs + tire pressure.
    for bike, odo, title, desc, prio, status in [
        (guzzi, guzzi_odo, "Ölverlust am Ventildeckel links",
         "Dichtung bestellen, bei nächstem Ölwechsel ersetzen", "medium", "open"),
        (guzzi, guzzi_odo, "Standgas sägt im warmen Zustand",
         "Vergasersynchronisation prüfen", "high", "open"),
        (gs, gs_odo, "Software-Update Kombiinstrument",
         "Beim nächsten Händlerbesuch einspielen lassen", "low", "open"),
        (xt, 31950, "Tachobeleuchtung ausgefallen",
         "Birne T5 liegt im Regal A", "low", "in_progress"),
    ]:
        call("POST", f"/api/motorcycles/{bike}/issues",
             {"title": title, "description": desc, "priority": prio,
              "status": status, "odo": odo, "date": "2026-07-28T09:00:00Z"})

    for cat, name, torque, tool in [
        ("Motor", "Zylinderkopfmuttern", 40.0, "17 mm"),
        ("Motor", "Ölablassschraube", 30.0, "22 mm"),
        ("Fahrwerk", "Achsmutter vorne", 80.0, "24 mm"),
        ("Fahrwerk", "Achsmutter hinten", 120.0, "27 mm"),
        ("Bremsen", "Bremssattel-Schrauben", 24.0, "Inbus 8"),
    ]:
        call("POST", f"/api/motorcycles/{guzzi}/torque-specs",
             {"category": cat, "name": name, "torque": torque,
              "toolSize": tool, "unverified": False})

    call("PUT", f"/api/motorcycles/{guzzi}/tire-pressure",
         {"frontBar": 2.3, "rearBar": 2.5, "frontPassengerBar": 2.5,
          "rearPassengerBar": 2.8, "preferredUnit": "bar"})
    call("PUT", f"/api/motorcycles/{gs}/tire-pressure",
         {"frontBar": 2.5, "rearBar": 2.9, "preferredUnit": "bar"})

    # Technical details + document vault for the Guzzi.
    for title, value in [("Zündkerze", "NGK BR8ES"),
                         ("Reifen vorne", "100/90-18 Bridgestone BT46"),
                         ("Batterie", "Yuasa YB16AL-A2"),
                         ("Vergaser", "Dell'Orto PHM 40")]:
        call("POST", f"/api/motorcycles/{guzzi}/details",
             {"title": title, "value": value})
    for title in ["Fahrzeugausweis", "MFK-Bericht 2025"]:
        call("POST", "/api/documents",
             multipart={"title": title, "motorcycleIds": str(guzzi)},
             file_field=("file", title.replace(" ", "-") + ".pdf",
                         tiny_pdf(title)))

    # Parts inventory: storage tree + catalog + stock.
    def storage(name, parent=None):
        body = {"name": name, **({"parentId": parent} if parent else {})}
        result = call("POST", "/api/storage-locations", body)
        return result.get("storageLocation", result)["id"]

    garage = storage("Garage")
    regal_a = storage("Regal A", garage)
    regal_b = storage("Regal B", garage)
    keller = storage("Keller")

    for number, name, manufacturer, qty, price, loc in [
        ("HF551", "Ölfilter", "Hiflofiltro", 3, 12.90, regal_a),
        ("BR8ES", "Zündkerze", "NGK", 6, 6.50, regal_a),
        ("07BB19.SA", "Bremsbeläge Sinter vorne", "Brembo", 2, 42.00, regal_b),
        ("520VX3-110", "Kette 520 X-Ring", "DID", 1, 98.00, keller),
        ("T5-W1.2", "Instrumentenbirne T5", "Osram", 10, 1.80, regal_a),
        ("UD-801", "Faltenbalg Gabel", "Ariete", 2, 24.50, regal_b),
    ]:
        part = call("POST", "/api/parts",
                    {"partNumber": number, "name": name,
                     "manufacturer": manufacturer, "isPublic": False})
        part_id = part.get("part", part).get("id")
        call("POST", "/api/part-stocks",
             {"partId": part_id, "quantity": qty, "price": price,
              "currency": "CHF", "purchaseDate": "2026-03-15",
              "storageLocationId": loc, "isUsed": False})

    print(f"Seeded demo data at {BASE}")
    print(f"Login: {USER['username']} / {USER['password']}")


if __name__ == "__main__":
    main()
