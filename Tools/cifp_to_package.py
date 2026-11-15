#!/usr/bin/env python3
"""Converts FAA CIFP (ARINC 424 v18, file FAACIFP18) into airport packages for the ATC game.

Usage:
  python3 Tools/cifp_to_package.py --cifp Data/cifp/FAACIFP18 --stats          # counts per airport capability
  python3 Tools/cifp_to_package.py --cifp Data/cifp/FAACIFP18 KBOS KJFK ...    # writes <icao>.json

Column positions below are 0-based string indices into the 132-column record. They were checked by hand against
sample KBOS records (see Tools/README notes in the main README), not against the ARINC 424 specification, which is
a paid document. Treat unusual records with suspicion; the script prints what it skips.
"""
import argparse, collections, csv, json, math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Sources/SimCore/Resources/Airports"
NM_PER_DEG = 60.0

# ---------- low level helpers ----------

def latlon(s):
    """'N42214660W071002300' (lat DDMMSSss, lon DDDMMSSss) to decimal degrees, or None."""
    m = re.fullmatch(r"([NS])(\d{2})(\d{2})(\d{4})([EW])(\d{3})(\d{2})(\d{4})", s)
    if not m:
        return None
    lat = int(m[2]) + int(m[3]) / 60 + int(m[4]) / 100 / 3600
    lon = int(m[6]) + int(m[7]) / 60 + int(m[8]) / 100 / 3600
    return (lat if m[1] == "N" else -lat, lon if m[5] == "E" else -lon)

def dist_nm(a, b):
    dy = (a[0] - b[0]) * NM_PER_DEG
    dx = (a[1] - b[1]) * NM_PER_DEG * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot(dx, dy)

def bearing_deg(a, b):
    dy = (b[0] - a[0])
    dx = (b[1] - a[1]) * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.degrees(math.atan2(dx, dy)) % 360

def altitude(text):
    t = text.strip()
    if not t:
        return None
    if t.startswith("FL"):
        return int(t[2:]) * 100 if t[2:].isdigit() else None
    return int(t) if t.isdigit() else None

def constraint(desc, a1, a2):
    v1, v2 = altitude(a1), altitude(a2)
    if v1 is None:
        return None
    if desc == "B" and v2 is not None:
        return {"kind": "between", "feet": min(v1, v2), "upperFeet": max(v1, v2)}
    if desc in ("+", "H", "J"):
        return {"kind": "atOrAbove", "feet": v1}
    if desc == "-":
        return {"kind": "atOrBelow", "feet": v1}
    return {"kind": "at", "feet": v1}

# ---------- reading the file ----------

class Cifp:
    def __init__(self, path):
        self.airports = {}                       # icao -> dict(lat, lon, elevationFt, taFt)
        self.runways = collections.defaultdict(dict)   # icao -> id -> dict
        self.ils = collections.defaultdict(list)       # icao -> list of dict
        self.term_wp = collections.defaultdict(dict)   # icao -> ident -> (lat, lon)
        self.other_wp = collections.defaultdict(list)  # ident -> [(lat, lon)] (enroute waypoints, navaids, NDBs)
        self.procs = collections.defaultdict(lambda: collections.defaultdict(list))  # icao -> (kind, ident) -> legs
        self.read(path)

    def read(self, path):
        with open(path, encoding="latin-1") as f:
            for line in f:
                if len(line) < 130 or line[0] != "S":
                    continue
                section, sub = line[4], line[5 if line[4] != "P" else 12]
                if section == "P":
                    icao = line[6:10].strip()
                    code = line[12]
                    if code == "A" and line[13:16].strip():
                        self.read_airport(icao, line)
                    elif code == "G":
                        self.read_runway(icao, line)
                    elif code == "I":
                        self.read_ils(icao, line)
                    elif code == "C":
                        pos = latlon(line[32:51])
                        if pos:
                            self.term_wp[icao][line[13:18].strip()] = pos
                    elif code == "N":
                        pos = latlon(line[32:51])
                        if pos:
                            self.other_wp[line[13:17].strip()].append(pos)
                    elif code in "DEF":
                        self.read_leg(icao, code, line)
                elif section == "E" and line[5] == "A":
                    pos = latlon(line[32:51])
                    if pos:
                        self.other_wp[line[13:18].strip()].append(pos)
                elif section == "D" and line[5] in " B":
                    pos = latlon(line[32:51])
                    if pos:
                        self.other_wp[line[13:17].strip()].append(pos)

    def read_airport(self, icao, line):
        pos = latlon(line[32:51])
        if not pos or line[21] not in "01":
            return
        elevation = line[56:61].strip()
        ta = re.search(r"(\d{5})(\d{5})", line[61:])  # transition altitude then transition level
        self.airports[icao] = {"lat": pos[0], "lon": pos[1], "name": line[93:123].strip(),
                               "elevationFt": int(elevation) if elevation.lstrip("-").isdigit() else None,
                               "taFt": int(ta[1]) if ta else None}

    def read_runway(self, icao, line):
        pos = latlon(line[32:51])
        rid = line[13:18].strip()
        if not pos or not rid.startswith("RW") or line[21] not in "01":
            return
        def num(s, default=0):
            s = s.strip()
            return int(s) if s.lstrip("-").isdigit() else default
        self.runways[icao][rid[2:]] = {
            "lat": pos[0], "lon": pos[1], "lengthFt": num(line[22:27]), "magBearingTenths": num(line[27:31]),
            "elevationFt": num(line[66:71]), "displacedFt": num(line[71:75]), "tchFt": num(line[75:77]),
            "widthFt": num(line[77:80]), "ilsIdent": line[81:85].strip() or None,
        }

    def read_ils(self, icao, line):
        if line[21] not in "01":
            return
        loc = latlon(line[32:51])
        runway = line[27:32].strip()
        if not loc or not runway.startswith("RW"):
            return
        def num(s):
            s = s.strip()
            return int(s) if s.isdigit() else None
        gs = num(line[87:90])
        self.ils[icao].append({"ident": line[13:17].strip(), "category": line[17].strip(), "freqKHz10": num(line[22:27]),
                               "runway": runway[2:], "glidepathDeg": gs / 100 if gs else None,
                               "tchFt": num(line[95:97])})

    def read_leg(self, icao, code, line):
        if line[38] not in "01":
            return
        kind = {"D": "sid", "E": "star", "F": "approach"}[code]
        ident = line[13:19].strip()
        self.procs[icao][(kind, ident)].append({
            "routeType": line[19], "transition": line[20:25].strip(), "seq": int(line[26:29] or 0),
            "fix": line[29:34].strip(), "fixSection": line[36:38], "desc": line[39:43],
            "pathTerm": line[47:49], "altDesc": line[82], "alt1": line[84:89], "alt2": line[89:94],
            "speedDesc": line[98], "speed": line[99:102], "vpa": line[102:106],
        })

# ---------- building a package ----------

def runway_ids_matching(token, runway_ids):
    """'RW04B' -> every runway with number 04; 'ALL' or '' -> every runway."""
    m = re.fullmatch(r"RW(\d{2})([LRCB]?)", token)
    if not m:
        return list(runway_ids)
    return [r for r in runway_ids if r[:2] == m[1] and (m[2] in ("", "B") or r[2:] == m[2])]

def load_places(path):
    """OurAirports airports.csv: ICAO-style code -> dict(name, city, region, country, iata). Optional."""
    places = {}
    p = pathlib.Path(path)
    if not p.exists():
        print(f"note: {p} not found, so airports get no city names (download it with Tools/fetch_places.sh)")
        return places
    with open(p, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            entry = {"name": row["name"], "city": row["municipality"], "country": row["iso_country"],
                     "region": row["iso_region"].split("-")[-1], "iata": row["iata_code"],
                     "scheduled": row.get("scheduled_service") == "yes", "type": row.get("type", "")}
            for key in (row["ident"], row["gps_code"], row["icao_code"]):
                if key and key not in places:
                    places[key] = entry
    return places

def title_case(text):
    small = {"of", "and", "the", "at"}
    return " ".join(w if (i and w.lower() in small) else w.capitalize() for i, w in enumerate(text.split()))

class Builder:
    def __init__(self, cifp, icao, places=None):
        self.cifp, self.icao = cifp, icao
        self.places = (places or {}).get(icao, {})
        self.arp = (cifp.airports[icao]["lat"], cifp.airports[icao]["lon"])
        self.fixes = {}
        self.skipped = collections.Counter()

    def locate(self, leg):
        ident = leg["fix"]
        if not ident:
            return None
        if leg["fixSection"][0] == "P" and ident in self.cifp.term_wp[self.icao]:
            return self.cifp.term_wp[self.icao][ident]
        candidates = self.cifp.other_wp.get(ident, [])
        if candidates:
            return min(candidates, key=lambda p: dist_nm(p, self.arp))
        if ident in self.cifp.term_wp[self.icao]:
            return self.cifp.term_wp[self.icao][ident]
        rw = self.cifp.runways[self.icao].get(ident[2:]) if ident.startswith("RW") else None
        if rw:
            return (rw["lat"], rw["lon"])
        return None

    def to_leg(self, leg):
        pos = self.locate(leg)
        if pos is None:
            self.skipped["no position" if leg["fix"] else "no fix (heading/course leg)"] += 1
            return None
        self.fixes[leg["fix"]] = pos
        out = {"fixId": leg["fix"]}
        alt = constraint(leg["altDesc"], leg["alt1"], leg["alt2"])
        if alt:
            out["altitude"] = alt
        if leg["speed"].strip().isdigit() and leg["speedDesc"] in " -":
            out["maxSpeedKt"] = int(leg["speed"])
        return out

    def legs(self, records):
        result = []
        for rec in sorted(records, key=lambda r: r["seq"]):
            leg = self.to_leg(rec)
            if leg and (not result or result[-1]["fixId"] != leg["fixId"]):
                result.append(leg)
        return result

    # --- runways
    def runways(self):
        c = self.cifp
        rws = c.runways[self.icao]
        out = []
        for rid in sorted(rws):
            r = rws[rid]
            # True bearing from this threshold to the far end where the reciprocal exists; else magnetic as published.
            number = int(rid[:2])
            recip = f"{(number + 18 - 1) % 36 + 1:02d}" + {"L": "R", "R": "L", "C": "C"}.get(rid[2:], "")
            far = rws.get(recip)
            true_brg = bearing_deg((r["lat"], r["lon"]), (far["lat"], far["lon"])) if far else r["magBearingTenths"] / 10
            length_m = round(dist_nm((r["lat"], r["lon"]), (far["lat"], far["lon"])) * 1852) if far else round(r["lengthFt"] * 0.3048)
            ils = next((i for i in c.ils[self.icao] if i["runway"] == rid and i["glidepathDeg"]), None)
            entry = {
                "id": rid, "trueBearingDeg": round(true_brg, 2) % 360, "lengthM": length_m,
                "widthM": round(r["widthFt"] * 0.3048), "surface": "ASPH",
                "thresholdLat": round(r["lat"], 6), "thresholdLon": round(r["lon"], 6),
                "thresholdElevationFt": r["elevationFt"],
                "toraM": length_m, "todaM": length_m, "asdaM": length_m, "ldaM": length_m,
            }
            if ils:
                entry["ils"] = {"ident": ils["ident"], "category": {"1": "CAT I", "2": "CAT II", "3": "CAT III"}.get(ils["category"], "CAT I"),
                                "localiserMHz": (ils["freqKHz10"] or 0) / 100,
                                "glidepathDeg": ils["glidepathDeg"],
                                "thresholdCrossingHeightFt": ils["tchFt"] or r["tchFt"] or 50}
            out.append(entry)
        return out

    # --- procedures
    def procedures(self, runway_ids):
        out = []
        for (kind, ident), records in sorted(self.cifp.procs[self.icao].items()):
            if kind == "star":
                out += self.star_or_sid(kind, ident, records, runway_ids, rwy={"3", "6", "9"},
                                        common={"2", "5", "8"}, enroute={"1", "4", "7"}, rwy_first=False)
            elif kind == "sid":
                out += self.star_or_sid(kind, ident, records, runway_ids, rwy={"1", "4", "T", "F"},
                                        common={"2", "5", "M"}, enroute={"3", "6", "V", "S"}, rwy_first=True)
            else:
                out += self.approach(ident, records, runway_ids)
        return out

    def star_or_sid(self, kind, ident, records, runway_ids, rwy, common, enroute, rwy_first):
        groups = {"rwy": collections.defaultdict(list), "common": [], "enr": collections.defaultdict(list)}
        for r in records:
            t = r["routeType"]
            if t in rwy:
                groups["rwy"][r["transition"]].append(r)
            elif t in common:
                groups["common"].append(r)
            elif t in enroute:
                groups["enr"][r["transition"]].append(r)
        common_legs = self.legs(groups["common"])
        rwy_opts = [(k, self.legs(v)) for k, v in sorted(groups["rwy"].items())] or [("", [])]
        enr_opts = [(k, self.legs(v)) for k, v in sorted(groups["enr"].items())] or [("", [])]
        result = []
        for rk, rl in rwy_opts:
            for ek, el in enr_opts:
                parts = [rl, common_legs, el] if rwy_first else [el, common_legs, rl]
                legs = []
                for part in parts:
                    for leg in part:
                        if not legs or legs[-1]["fixId"] != leg["fixId"]:
                            legs.append(leg)
                if len(legs) < 2:
                    continue
                name = ident + "".join("." + x for x in (ek, rk) if x) if (len(rwy_opts) > 1 or len(enr_opts) > 1) else ident
                if kind == "sid":
                    name = ident + "".join("." + x for x in (rk, ek) if x) if (len(rwy_opts) > 1 or len(enr_opts) > 1) else ident
                runways = runway_ids_matching(rk, runway_ids) if rk else list(runway_ids)
                result.append({"id": name, "kind": kind, "runways": runways, "legs": legs})
        return result

    # Final approach route type by procedure prefix: ILS, RNAV (GPS), RNAV (RNP).
    APPROACH_TYPES = {"I": "ils", "R": "rnav", "H": "rnp"}
    MAX_RNAV_OFFSET_DEG = 15   # RNAV finals more than this off the runway course (offset or curved) are skipped

    def approach(self, ident, records, runway_ids):
        """ILS ('I27'), RNAV ('R27', 'R22LY') and RNP ('H33LX') approaches. The ident is the type letter, the runway,
        and an optional letter that tells apart approaches of the same type to the same runway."""
        m = re.fullmatch(r"([IRH])(\d{2})([LRC]?)-?([A-Z]?)", ident)
        if not m:
            return []
        letter = m[1]
        runway = m[2] + m[3]
        if runway not in runway_ids and m[3] and not m[4] and m[2] in runway_ids:
            runway = m[2]          # 'R04L' could be runway 04 with suffix L; prefer the runway that exists
        if runway not in runway_ids:
            return []
        kind = self.APPROACH_TYPES[letter]
        final = sorted((r for r in records if r["routeType"] == letter), key=lambda r: r["seq"])
        transitions = collections.defaultdict(list)
        for r in records:
            if r["routeType"] in ("A", "S", "Z") and r["transition"]:
                transitions[r["transition"]].append(r)
        # Split the final route at the missed approach point (description code position 3 == 'M').
        map_index = next((i for i, r in enumerate(final) if r["desc"][3:4] == "M"), None)
        before, after = (final[:map_index], final[map_index + 1:]) if map_index is not None else (final, [])
        final_legs = [l for l in self.legs(before) if not l["fixId"].startswith("RW")]
        missed = [l for l in self.legs(after) if not l["fixId"].startswith("RW")]
        extra = {}
        if kind != "ils":
            # The game flies RNAV finals on the runway centreline, so keep only finals that are lined up with it.
            rwy = self.cifp.runways[self.icao].get(runway)
            faf = next((r for r in before if r["desc"][3:4] == "F"), None) or (before[-2] if len(before) >= 2 else None)
            pos = self.fixes.get(faf["fix"]) if faf else None
            if not rwy or not pos or not final_legs:
                self.skipped["RNAV final not usable"] += 1
                return []
            thr = (rwy["lat"], rwy["lon"])
            other = self.cifp.runways[self.icao]
            course = bearing_deg(pos, thr)
            # The runway's true bearing from its own threshold to the far end's threshold.
            num = int(runway[:2]); opp = f"{(num + 18 - 1) % 36 + 1:02d}" + {"L": "R", "R": "L"}.get(runway[2:], runway[2:])
            rwy_course = bearing_deg(thr, (other[opp]["lat"], other[opp]["lon"])) if opp in other else course
            if abs((course - rwy_course + 180) % 360 - 180) > self.MAX_RNAV_OFFSET_DEG:
                self.skipped["RNAV final not lined up with the runway"] += 1
                return []
            extra["approachType"] = kind
            vpa = next((r["vpa"].strip() for r in final if r["vpa"].strip().lstrip("-").isdigit()
                        and int(r["vpa"]) != 0), None)
            if vpa:
                extra["glidepathDeg"] = abs(int(vpa)) / 100
        result = []
        if final_legs:
            result.append({"id": ident, "kind": "approach", "runways": [runway], "legs": final_legs,
                           **({"missedApproach": missed} if missed else {}), **extra})
        for tname, trecs in sorted(transitions.items()):
            t_legs = self.legs(trecs)
            legs = []
            for leg in t_legs + final_legs:
                if not legs or legs[-1]["fixId"] != leg["fixId"]:
                    legs.append(leg)
            if len(legs) >= 2 and final_legs:
                result.append({"id": f"{ident}.{tname}", "kind": "approach", "runways": [runway], "legs": legs,
                               **({"missedApproach": missed} if missed else {}), **extra})
        return result

    def build(self):
        a = self.cifp.airports[self.icao]
        runways = self.runways()
        ids = [r["id"] for r in runways]
        procs = self.procedures(ids)
        # An ILS approach needs the runway's ILS; RNAV approaches carry their own type.
        with_ils = {r["id"] for r in runways if "ils" in r}
        procs = [p for p in procs if p["kind"] != "approach" or "approachType" in p or set(p["runways"]) <= with_ils]
        seen, unique = set(), []
        for p in procs:
            if p["id"] not in seen:
                seen.add(p["id"]); unique.append(p)
        used = {l["fixId"] for p in unique for l in p["legs"] + p.get("missedApproach", [])}
        fixes = [{"id": n, "lat": round(p[0], 6), "lon": round(p[1], 6)} for n, p in sorted(self.fixes.items()) if n in used]
        place = self.places
        record = {
            "schemaVersion": 1, "icao": self.icao,
            "name": place.get("name") or title_case(a.get("name") or self.icao),
            "dataSource": "FAA CIFP (ARINC 424 v18), cycle file FAACIFP18 as downloaded; converted by Tools/cifp_to_package.py. "
                          "Runway true bearing computed from thresholds. Takeoff and landing distances set to the runway length. "
                          "Arcs and holds are flown as straight legs or skipped. Heading and course legs are skipped.",
            "transitionAltitudeFt": a["taFt"] or 18000, "elevationFt": a["elevationFt"],
            "runways": runways, "fixes": fixes, "procedures": unique, "holds": [],
        }
        for key in ("city", "region", "country", "iata"):
            if place.get(key):
                record[key] = place[key]
        return record

# ---------- stats ----------

def stats(cifp):
    airports = set(cifp.airports)
    ils_airports = {i for i in airports if any(x["glidepathDeg"] for x in cifp.ils[i])}
    star = {i for i in airports if any(k == "star" for (k, _) in cifp.procs[i])}
    sid = {i for i in airports if any(k == "sid" for (k, _) in cifp.procs[i])}
    print(f"airports in file: {len(airports)}")
    print(f"with ILS (localiser plus glideslope): {len(ils_airports)}")
    print(f"with a STAR: {len(star)}   with a SID/DP: {len(sid)}")
    print(f"ILS and STAR: {len(ils_airports & star)}   ILS and SID: {len(ils_airports & sid)}   ILS, STAR and SID: {len(ils_airports & star & sid)}")
    print(f"ILS and 4+ runways with ILS: {sum(1 for i in ils_airports if len({x['runway'] for x in cifp.ils[i]}) >= 4)}")

def validate(pkg):
    problems = []
    rw = {r["id"] for r in pkg["runways"]}
    fx = {f["id"] for f in pkg["fixes"]}
    ids = [p["id"] for p in pkg["procedures"]]
    if len(ids) != len(set(ids)):
        problems.append("duplicate procedure ids")
    for p in pkg["procedures"]:
        if not p["legs"]:
            problems.append(f"{p['id']}: no legs")
        for l in p["legs"] + p.get("missedApproach", []):
            if l["fixId"] not in fx:
                problems.append(f"{p['id']}: unknown fix {l['fixId']}")
        for r in p["runways"]:
            if r not in rw:
                problems.append(f"{p['id']}: unknown runway {r}")
        if p["kind"] == "approach" and "approachType" not in p and not any("ils" in x for x in pkg["runways"] if x["id"] in p["runways"]):
            problems.append(f"{p['id']}: approach without ILS")
    return problems

def qualifies_airline(pkg):
    """--airline: one ILS or RNAV approach is enough; SIDs and STARs are optional (the game vectors without them)."""
    kinds = collections.Counter(p["kind"] for p in pkg["procedures"])
    return kinds["approach"] >= 1

def qualifies(pkg):
    kinds = collections.Counter(p["kind"] for p in pkg["procedures"])
    return kinds["star"] >= 1 and kinds["sid"] >= 1 and kinds["approach"] >= 1 and any("ils" in r for r in pkg["runways"])

def write_package(pkg, out):
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{pkg['icao'].lower()}.json").write_text(json.dumps(pkg, separators=(",", ":")) + "\n")

def write_index(out):
    """airports-index.json: one small entry per package, so the picker does not have to load every package."""
    entries = []
    for f in sorted(out.glob("*.json")):
        if f.name == "airports-index.json":
            continue
        pkg = json.loads(f.read_text())
        kinds = collections.Counter(p["kind"] for p in pkg["procedures"])
        entry = {"icao": pkg["icao"], "name": pkg["name"], "ilsRunways": sum("ils" in r for r in pkg["runways"]),
                 "stars": kinds["star"], "sids": kinds["sid"], "approaches": kinds["approach"]}
        for key in ("city", "region", "country", "iata"):
            if pkg.get(key):
                entry[key] = pkg[key]
        entries.append(entry)
    entries.sort(key=lambda e: ((e.get("city") or e["name"]).lower(), e["icao"]))
    (out / "airports-index.json").write_text(json.dumps(entries, separators=(",", ":")) + "\n")
    print(f"index: {len(entries)} airports")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cifp", required=True)
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--all", action="store_true", help="build every airport with an ILS, at least one STAR and one SID")
    ap.add_argument("--airline", action="store_true",
                    help="build every large or medium airport with scheduled airline service (OurAirports) and an ILS or RNAV approach; "
                         "SIDs and STARs optional")
    ap.add_argument("--places", default=str(ROOT.parent / "Data/places/airports.csv"))
    ap.add_argument("--out", default=str(OUT_DIR))
    ap.add_argument("icao", nargs="*")
    args = ap.parse_args()
    cifp = Cifp(args.cifp)
    places = load_places(args.places)
    out = pathlib.Path(args.out)
    if args.stats:
        stats(cifp)
    targets = list(args.icao)
    if args.all:
        ils = {i for i in cifp.airports if any(x["glidepathDeg"] for x in cifp.ils[i])}
        star = {i for i in cifp.airports if any(k == "star" for (k, _) in cifp.procs[i])}
        sid = {i for i in cifp.airports if any(k == "sid" for (k, _) in cifp.procs[i])}
        targets = sorted(ils & star & sid)
        print(f"{len(targets)} candidate airports (ILS, STAR and SID in the file)")
    if args.airline:
        coded = {i for i in cifp.airports if any(k == "approach" and n[:1] in "IRH" for (k, n) in cifp.procs[i])}
        airline = {i for i in cifp.airports
                   if places.get(i, {}).get("scheduled") and places[i].get("type") in ("large_airport", "medium_airport")}
        targets = sorted(coded & airline)
        print(f"{len(targets)} candidate airports (scheduled airline service, large or medium, ILS or RNAV approach in the file)")
    built = rejected = 0
    for icao in targets:
        if icao not in cifp.airports:
            print(f"{icao}: not in file"); continue
        b = Builder(cifp, icao, places)
        try:
            pkg = b.build()
        except Exception as e:  # keep going; report the airport
            print(f"{icao}: failed to build ({e!r})"); rejected += 1; continue
        problems = validate(pkg)
        kinds = collections.Counter(p["kind"] for p in pkg["procedures"])
        summary = (f"{icao} {pkg['name']} ({pkg.get('city', '?')}): {len(pkg['runways'])} runways "
                   f"({sum('ils' in r for r in pkg['runways'])} with ILS), {len(pkg['fixes'])} fixes, "
                   f"{kinds['star']} STARs, {kinds['sid']} SIDs, {kinds['approach']} approaches; problems: {problems[:3] or 'none'}")
        check = qualifies_airline if args.airline else qualifies
        if (args.all or args.airline) and (problems or not check(pkg)):
            print("skipped " + summary); rejected += 1; continue
        if not (args.all or args.airline):
            print(summary)
        write_package(pkg, out)
        built += 1
    if targets:
        print(f"wrote {built} packages, skipped {rejected}")
        write_index(out)

if __name__ == "__main__":
    main()
