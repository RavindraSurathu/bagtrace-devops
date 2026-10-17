"""Parser for a simplified IATA Baggage Source Message (BSM).

A BSM is sent by an airline's departure control system (DCS) when a bag is
checked in. Each line is an element identified by a dot-prefixed code:

    BSM
    .V/1LMEL                      version, local/transfer, airport
    .F/QF401/18OCT/SYD/Y          outbound flight, date, destination, class
    .N/0081123456002              licence plate: 10-digit tag + count
    .W/K/2/31                     weight: unit, pieces, total weight
    .P/1SMITH/JOHN                passenger name
    ENDBSM

A second line of ``CHG`` marks a change and ``DEL`` marks a deletion
(often called a DELBSM), sent when a bag is offloaded or the check-in is
cancelled.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

ACTIONS = {"ADD", "CHG", "DEL"}

_FLIGHT_RE = re.compile(r"^([A-Z0-9]{2}\d{1,4}[A-Z]?)/(\d{2}[A-Z]{3})/([A-Z]{3})(?:/([A-Z]))?$")
_TAG_RE = re.compile(r"^(\d{10})(\d{3})$")
_STATION_RE = re.compile(r"^\d([LTX])([A-Z]{3})")
_WEIGHT_RE = re.compile(r"^([KL])/(\d+)/(\d+)$")


class BSMError(ValueError):
    """Raised when a message is not a valid BSM."""


@dataclass
class BaggageMessage:
    action: str
    airport: str
    flight: str
    flight_date: str
    destination: str
    travel_class: str | None
    tags: list[str]
    passenger: str | None = None
    pieces: int | None = None
    weight_kg: int | None = None
    warnings: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "action": self.action,
            "airport": self.airport,
            "flight": self.flight,
            "flight_date": self.flight_date,
            "destination": self.destination,
            "travel_class": self.travel_class,
            "tags": self.tags,
            "passenger": self.passenger,
            "pieces": self.pieces,
            "weight_kg": self.weight_kg,
            "warnings": self.warnings,
        }


def _expand_tags(element: str) -> list[str]:
    match = _TAG_RE.match(element)
    if not match:
        raise BSMError(f"Invalid .N element '{element}': expected 10-digit tag and 3-digit count")
    first, count = int(match.group(1)), int(match.group(2))
    if count < 1:
        raise BSMError("Tag count in .N element must be at least 1")
    return [str(first + i).zfill(10) for i in range(count)]


def parse_bsm(text: str) -> BaggageMessage:
    """Parse BSM text into a BaggageMessage, raising BSMError if invalid."""
    lines = [line.strip().upper() for line in (text or "").strip().splitlines() if line.strip()]
    if len(lines) < 3 or lines[0] != "BSM":
        raise BSMError("Message must start with a 'BSM' line")
    if lines[-1] != "ENDBSM":
        raise BSMError("Message must end with an 'ENDBSM' line")

    body = lines[1:-1]
    action = "ADD"
    if body and body[0] in ACTIONS:
        action = body.pop(0)

    airport = flight = flight_date = destination = None
    travel_class = passenger = None
    pieces = weight = None
    tags: list[str] = []
    warnings: list[str] = []

    for line in body:
        if not line.startswith(".") or "/" not in line:
            warnings.append(f"Ignored unrecognised line '{line}'")
            continue
        code, value = line[1:].split("/", 1)
        if code == "V":
            station = _STATION_RE.match(value)
            if not station:
                raise BSMError(f"Invalid .V element '{value}'")
            airport = station.group(2)
        elif code == "F":
            match = _FLIGHT_RE.match(value)
            if not match:
                raise BSMError(f"Invalid .F element '{value}': expected FLIGHT/DDMMM/DEST[/CLASS]")
            flight, flight_date, destination, travel_class = match.groups()
        elif code == "N":
            tags.extend(_expand_tags(value))
        elif code == "W":
            match = _WEIGHT_RE.match(value)
            if not match:
                warnings.append(f"Ignored invalid .W element '{value}'")
                continue
            unit, pieces_s, weight_s = match.groups()
            pieces = int(pieces_s)
            weight = int(weight_s) if unit == "K" else round(int(weight_s) * 0.4536)
        elif code == "P":
            passenger = value.lstrip("0123456789").replace("/", " ").strip() or None
        else:
            warnings.append(f"Element .{code} is not handled and was skipped")

    missing = [name for name, val in (("V", airport), ("F", flight), ("N", tags)) if not val]
    if missing:
        raise BSMError("Missing required element(s): " + ", ".join("." + m for m in missing))

    return BaggageMessage(
        action=action,
        airport=airport,
        flight=flight,
        flight_date=flight_date,
        destination=destination,
        travel_class=travel_class,
        tags=tags,
        passenger=passenger,
        pieces=pieces,
        weight_kg=weight,
        warnings=warnings,
    )
