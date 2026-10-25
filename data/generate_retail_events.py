"""
Générateur d'événements de vente RetailPulse (JSON Lines) pour le projet Snowflake.

Chaque ligne d'un fichier = un événement de vente JSON :
{
  "transaction_id": "TX-000001",
  "customer_info": {"id": "C-0042", "email": "...", "country": "FR"},
  "items": [{"sku": "SKU-101", "name": "...", "quantity": 2, "unit_price": 19.9}, ...],
  "total_amount": 39.8,
  "event_timestamp": "2026-07-03T14:22:05Z"
}

Produit 2 lots :
  - lot_01 : données initiales, 3 fichiers (juillet -> septembre 2026), 900 transactions
        -> premier COPY INTO et alimentation initiale de FACT_SALES
  - lot_02 : arrivée suivante, 1 fichier (1er -> 10 octobre 2026), 150 nouvelles transactions
        (TX-000901 à TX-001050), toutes valides
        -> captées par le STREAM et traitées par la TASK

Utilisation :
    python generate_retail_events.py                 # écrit dans ./data
    python generate_retail_events.py --output ./mes_donnees

Aucune dépendance externe (bibliothèque standard uniquement).
Graine aléatoire fixe : les fichiers sont identiques à chaque exécution.
"""

import argparse
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

SEED = 42

COUNTRIES = ["FR", "BE", "CH", "ES", "DE", "IT", "LU"]
COUNTRY_WEIGHTS = [50, 12, 8, 10, 10, 7, 3]

PRODUCTS = [
    ("SKU-101", "T-shirt coton", 19.90),
    ("SKU-102", "Jean slim", 49.90),
    ("SKU-103", "Sweat à capuche", 39.90),
    ("SKU-104", "Baskets running", 89.90),
    ("SKU-105", "Casquette", 14.90),
    ("SKU-106", "Veste imperméable", 99.00),
    ("SKU-107", "Chaussettes (lot de 3)", 9.90),
    ("SKU-108", "Sac à dos", 59.00),
    ("SKU-109", "Écharpe laine", 24.90),
    ("SKU-110", "Montre connectée", 149.00),
]

FIRST_NAMES = ["lea", "hugo", "chloe", "lucas", "emma", "nathan", "ines", "theo",
               "manon", "louis", "jade", "adam", "sarah", "noah", "camille"]
DOMAINS = ["mail.fr", "exemple.com", "webmail.be", "post.ch", "correo.es"]

N_CUSTOMERS = 120
LOT1_FILES = 3
LOT1_PER_FILE = 300
LOT2_NEW = 150
LOT2_SEED = 2026


def build_customers(rng):
    customers = []
    for i in range(1, N_CUSTOMERS + 1):
        name = rng.choice(FIRST_NAMES)
        customers.append({
            "id": f"C-{i:04d}",
            "email": f"{name}.{i}@{rng.choice(DOMAINS)}",
            "country": rng.choices(COUNTRIES, weights=COUNTRY_WEIGHTS)[0],
        })
    return customers


def build_items(rng):
    items = []
    for sku, name, price in rng.sample(PRODUCTS, k=rng.randint(1, 4)):
        items.append({
            "sku": sku,
            "name": name,
            "quantity": rng.choices([1, 2, 3], weights=[70, 22, 8])[0],
            "unit_price": price,
        })
    return items


def iso(ts):
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


def build_event(rng, tx_num, customer, start, end):
    items = build_items(rng)
    seconds = int((end - start).total_seconds())
    ts = start + timedelta(seconds=rng.randint(0, seconds))
    return {
        "transaction_id": f"TX-{tx_num:06d}",
        "customer_info": dict(customer),
        "items": items,
        "total_amount": round(sum(i["quantity"] * i["unit_price"] for i in items), 2),
        "event_timestamp": iso(ts),
    }


def write_jsonl(path, lines):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for line in lines:
            f.write(line + "\n")


def main():
    parser = argparse.ArgumentParser(description="Génère les lots JSON RetailPulse.")
    parser.add_argument("--output", default="./data", help="dossier de sortie (défaut : ./data)")
    args = parser.parse_args()

    rng = random.Random(SEED)
    out = Path(args.output)
    customers = build_customers(rng)
    tx = 0

    # ---------------- Lot 1 : 3 fichiers, juillet -> septembre 2026 ----------------
    lot1_events = []
    months = [
        (datetime(2026, 7, 1, tzinfo=timezone.utc), datetime(2026, 7, 31, 23, 59, 59, tzinfo=timezone.utc)),
        (datetime(2026, 8, 1, tzinfo=timezone.utc), datetime(2026, 8, 31, 23, 59, 59, tzinfo=timezone.utc)),
        (datetime(2026, 9, 1, tzinfo=timezone.utc), datetime(2026, 9, 30, 23, 59, 59, tzinfo=timezone.utc)),
    ]
    for part, (start, end) in enumerate(months, start=1):
        events = []
        for _ in range(LOT1_PER_FILE):
            tx += 1
            events.append(build_event(rng, tx, rng.choice(customers), start, end))
        events.sort(key=lambda e: e["event_timestamp"])
        lot1_events.extend(events)
        write_jsonl(out / "lot_01" / f"sales_2026_{6 + part:02d}.json",
                    [json.dumps(e, ensure_ascii=False) for e in events])

    # ---------------- Lot 2 : 1 fichier, 1er -> 10 octobre 2026, transactions valides ----------------
    rng2 = random.Random(LOT2_SEED)
    start = datetime(2026, 10, 1, tzinfo=timezone.utc)
    end = datetime(2026, 10, 10, 23, 59, 59, tzinfo=timezone.utc)
    events = []
    for _ in range(LOT2_NEW):
        tx += 1
        events.append(build_event(rng2, tx, rng2.choice(customers), start, end))
    events.sort(key=lambda e: e["event_timestamp"])
    write_jsonl(out / "lot_02" / "sales_2026_10_v2.json",
                [json.dumps(e, ensure_ascii=False) for e in events])

    # ---------------- Résumé ----------------
    print(f"Lot 1 : {LOT1_FILES} fichiers, {len(lot1_events)} transactions -> {out / 'lot_01'}")
    print(f"Lot 2 : 1 fichier, {len(events)} transactions -> {out / 'lot_02'}")

if __name__ == "__main__":
    main()
