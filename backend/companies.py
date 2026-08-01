"""Hardcoded process-serving company configurations.

Profiles store a company `id` (slug). Clients and the API resolve rates,
diligence attempts, payout schedules, time windows, and allowed priority
levels from this module — keep company-specific logic here, not scattered
through routes/UI.
"""

from __future__ import annotations

# Priority values match Photo.category / mobile kPhotoCategories.
_PRIORITY_STANDARD = "standard"
_PRIORITY_NEXT_DAY = "next_day"
_PRIORITY_ASAP = "asap"

COMPANIES = [
    {
        "id": "first_legal",
        "name": "First Legal",
        "email": "sdprocess@firstlegal.com",
        "attempts_for_diligence": 6,
        # Fixed calendar days each month.
        "payout_schedule": [10, 25],
        "pay_rate_structure": {
            _PRIORITY_STANDARD: "1st 3 attempts $18, $6.50/attempt after",
            _PRIORITY_NEXT_DAY: "1st 3 attempts $23.50, $8/attempt after",
            _PRIORITY_ASAP: "1st attempt $40, $20/attempt after",
        },
        "time_intervals": {
            "morning": {"start": "7:00 AM", "end": "8:00 AM"},
            "midday":  {"start": "11:00 AM", "end": "4:00 PM"},
            "evening": {"start": "5:30 PM", "end": "10:00 PM"},
        },
        "available_priority_levels": [
            _PRIORITY_STANDARD, _PRIORITY_NEXT_DAY, _PRIORITY_ASAP,
        ],
    },
    {
        "id": "rockstar",
        "name": "Rockstar Process Serving",
        "email": "rockstarlegal.sean@gmail.com",
        "attempts_for_diligence": 4,
        "payout_schedule": [1, 15],
        "pay_rate_structure": {
            _PRIORITY_STANDARD: "$50",
            _PRIORITY_NEXT_DAY: "$60",
            _PRIORITY_ASAP: "$70",
        },
        "time_intervals": {
            "morning": {"start": "7:00 AM", "end": "10:00 AM"},
            "midday":  {"start": "11:00 AM", "end": "4:00 PM"},
            "evening": {"start": "6:00 PM", "end": "10:00 PM"},
        },
        "available_priority_levels": [
            _PRIORITY_STANDARD, _PRIORITY_NEXT_DAY, _PRIORITY_ASAP,
        ],
    },
    {
        "id": "knox",
        "name": "Knox Attorney Service",
        "email": "sdprocess@knoxservices.com",
        "attempts_for_diligence": 5,
        # schedule[0] > schedule[1] ⇒ start day-of-month + week interval
        # (Jul 31, 2026, every 2 weeks). Next Day is intentionally omitted.
        "payout_schedule": [31, 2],
        "pay_rate_structure": {
            _PRIORITY_STANDARD: "$30",
            _PRIORITY_ASAP: "$50",
        },
        "time_intervals": {
            "morning": {"start": "7:00 AM", "end": "8:30 AM"},
            "midday":  {"start": "11:00 AM", "end": "4:00 PM"},
            "evening": {"start": "5:30 PM", "end": "10:00 PM"},
        },
        "available_priority_levels": [_PRIORITY_STANDARD, _PRIORITY_ASAP],
    },
]

DEFAULT_COMPANY_ID = "first_legal"

_COMPANIES_BY_ID = {c["id"]: c for c in COMPANIES}
VALID_COMPANY_IDS = frozenset(_COMPANIES_BY_ID)


def get_company(company_id):
    """Return the company dict for `company_id`, or None."""
    if not company_id:
        return None
    return _COMPANIES_BY_ID.get(str(company_id).strip())


def normalize_company_id(company_id, *, required=False):
    """Validate / coerce a company id. Returns DEFAULT when blank+optional."""
    raw = (company_id or "").strip()
    if not raw:
        if required:
            return None
        return DEFAULT_COMPANY_ID
    if raw not in VALID_COMPANY_IDS:
        return None
    return raw


def company_allows_priority(company_id, category):
    """True when `category` is in the company's available priority levels.
    Unknown/legacy companies accept the four modern categories."""
    cat = (category or _PRIORITY_STANDARD).strip().lower()
    company = get_company(company_id)
    if company is None:
        return cat in ("standard", "special", "next_day", "asap")
    return cat in company["available_priority_levels"]


def default_priority_for_company(company_id):
    company = get_company(company_id)
    if not company or not company["available_priority_levels"]:
        return _PRIORITY_STANDARD
    levels = company["available_priority_levels"]
    if _PRIORITY_STANDARD in levels:
        return _PRIORITY_STANDARD
    return levels[0]
