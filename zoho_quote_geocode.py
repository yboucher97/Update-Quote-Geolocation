#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlsplit, urlunsplit

import httpx


class ConfigError(RuntimeError):
    """Raised when required configuration is missing or invalid."""


class ZohoApiError(RuntimeError):
    """Raised when a Zoho CRM API request fails."""


class GoogleGeocodeError(RuntimeError):
    """Raised when a Google Geocoding API request fails."""


def _read_env(*names: str, default: str | None = None) -> str | None:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default


def _clean_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).replace("\r", " ").replace("\n", ", ").strip()
    text = " ".join(text.split())
    return text or None


def _coerce_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


@dataclass(slots=True)
class ZohoAuthConfig:
    api_base_url: str
    accounts_url: str
    module_api_name: str
    access_token: str | None
    refresh_token: str | None
    client_id: str | None
    client_secret: str | None
    page_size: int
    timeout_seconds: float


@dataclass(slots=True)
class QuoteFieldConfig:
    street_field: str
    city_field: str
    state_field: str
    postal_code_field: str
    country_field: str
    latitude_field: str | None
    longitude_field: str | None

    def requested_fields(self) -> list[str]:
        fields = [
            self.street_field,
            self.city_field,
            self.state_field,
            self.postal_code_field,
            self.country_field,
        ]
        if self.latitude_field:
            fields.append(self.latitude_field)
        if self.longitude_field:
            fields.append(self.longitude_field)
        seen: set[str] = set()
        ordered: list[str] = []
        for field_name in fields:
            if field_name not in seen:
                seen.add(field_name)
                ordered.append(field_name)
        return ordered


@dataclass(slots=True)
class QuoteAddressRecord:
    quote_id: str
    shipping_street: str | None
    shipping_city: str | None
    shipping_state: str | None
    shipping_postal_code: str | None
    shipping_country: str | None
    current_latitude: float | None
    current_longitude: float | None
    address_fields: dict[str, Any]

    @classmethod
    def from_zoho_record(cls, record: dict[str, Any], fields: QuoteFieldConfig) -> "QuoteAddressRecord":
        address_fields = {
            fields.street_field: record.get(fields.street_field),
            fields.city_field: record.get(fields.city_field),
            fields.state_field: record.get(fields.state_field),
            fields.postal_code_field: record.get(fields.postal_code_field),
            fields.country_field: record.get(fields.country_field),
        }
        if fields.latitude_field:
            address_fields[fields.latitude_field] = record.get(fields.latitude_field)
        if fields.longitude_field:
            address_fields[fields.longitude_field] = record.get(fields.longitude_field)

        return cls(
            quote_id=str(record["id"]),
            shipping_street=_clean_text(record.get(fields.street_field)),
            shipping_city=_clean_text(record.get(fields.city_field)),
            shipping_state=_clean_text(record.get(fields.state_field)),
            shipping_postal_code=_clean_text(record.get(fields.postal_code_field)),
            shipping_country=_clean_text(record.get(fields.country_field)),
            current_latitude=_coerce_float(record.get(fields.latitude_field)) if fields.latitude_field else None,
            current_longitude=_coerce_float(record.get(fields.longitude_field)) if fields.longitude_field else None,
            address_fields=address_fields,
        )

    def formatted_address(self) -> str | None:
        locality = ", ".join(part for part in [self.shipping_city, self.shipping_state] if part)
        if self.shipping_postal_code:
            locality = f"{locality} {self.shipping_postal_code}".strip() if locality else self.shipping_postal_code
        parts = [self.shipping_street, locality or None, self.shipping_country]
        rendered = ", ".join(part for part in parts if part)
        return rendered or None

    def has_coordinates(self) -> bool:
        return self.current_latitude is not None and self.current_longitude is not None

    def to_dict(self) -> dict[str, Any]:
        return {
            "quote_id": self.quote_id,
            "formatted_address": self.formatted_address(),
            "current_latitude": self.current_latitude,
            "current_longitude": self.current_longitude,
            "address_fields": self.address_fields,
        }


@dataclass(slots=True)
class GeocodeResult:
    latitude: float
    longitude: float
    formatted_address: str
    place_id: str | None
    location_type: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "latitude": self.latitude,
            "longitude": self.longitude,
            "formatted_address": self.formatted_address,
            "place_id": self.place_id,
            "location_type": self.location_type,
        }


class ZohoCrmClient:
    def __init__(self, config: ZohoAuthConfig, field_config: QuoteFieldConfig, logger: logging.Logger) -> None:
        self.config = config
        self.field_config = field_config
        self.logger = logger
        timeout = httpx.Timeout(self.config.timeout_seconds, connect=min(20.0, self.config.timeout_seconds))
        self._client = httpx.Client(timeout=timeout)
        self._access_token: str | None = self.config.access_token

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "ZohoCrmClient":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def fetch_quotes_with_shipping_addresses(self, max_records: int | None = None) -> list[QuoteAddressRecord]:
        fields = ",".join(self.field_config.requested_fields())
        records: list[QuoteAddressRecord] = []
        page = 1
        next_page_token: str | None = None
        page_size = max(1, min(self.config.page_size, 200))

        while True:
            params: dict[str, Any] = {
                "fields": fields,
                "per_page": page_size,
            }
            if next_page_token:
                params["page_token"] = next_page_token
            else:
                params["page"] = page

            payload = self._request(
                "GET",
                f"{self.config.api_base_url}/{self.config.module_api_name}",
                params=params,
            )

            data = payload.get("data") or []
            if not data:
                break

            for raw_record in data:
                records.append(QuoteAddressRecord.from_zoho_record(raw_record, self.field_config))
                if max_records is not None and len(records) >= max_records:
                    return records

            info = payload.get("info") or {}
            next_page_token = info.get("next_page_token") or payload.get("next_page_token")
            more_records = bool(info.get("more_records")) or bool(next_page_token)
            if not more_records:
                break
            if not next_page_token:
                page += 1

        return records

    def update_quote_coordinates(self, quote_id: str, latitude: float, longitude: float) -> dict[str, Any]:
        if not self.field_config.latitude_field or not self.field_config.longitude_field:
            raise ConfigError(
                "Latitude and longitude field API names are required for sync mode. "
                "Set ZOHO_QUOTE_LATITUDE_FIELD and ZOHO_QUOTE_LONGITUDE_FIELD, or pass "
                "--latitude-field and --longitude-field."
            )

        payload = {
            "data": [
                {
                    self.field_config.latitude_field: latitude,
                    self.field_config.longitude_field: longitude,
                }
            ]
        }

        return self._request(
            "PUT",
            f"{self.config.api_base_url}/{self.config.module_api_name}/{quote_id}",
            json=payload,
        )

    def _request(self, method: str, url: str, **kwargs: Any) -> dict[str, Any]:
        headers = dict(kwargs.pop("headers", {}))
        headers["Authorization"] = f"Zoho-oauthtoken {self._get_access_token()}"
        response = self._client.request(method, url, headers=headers, **kwargs)
        if response.status_code >= 400:
            raise ZohoApiError(self._format_error(response))
        if response.status_code == 204 or not response.content:
            return {}
        return response.json()

    def _get_access_token(self) -> str:
        if self._access_token:
            return self._access_token

        if not self.config.refresh_token or not self.config.client_id or not self.config.client_secret:
            raise ConfigError(
                "Missing Zoho OAuth credentials. Set ZOHO_CRM_ACCESS_TOKEN, or set "
                "ZOHO_CRM_REFRESH_TOKEN, ZOHO_CRM_CLIENT_ID, and ZOHO_CRM_CLIENT_SECRET."
            )

        response = self._client.post(
            self.config.accounts_url,
            data={
                "grant_type": "refresh_token",
                "refresh_token": self.config.refresh_token,
                "client_id": self.config.client_id,
                "client_secret": self.config.client_secret,
            },
        )
        if response.status_code >= 400:
            raise ZohoApiError(self._format_error(response, prefix="Zoho OAuth refresh failed"))

        payload = response.json()
        access_token = payload.get("access_token")
        if not access_token:
            raise ZohoApiError(f"Zoho OAuth refresh did not return an access token: {payload}")

        api_domain = payload.get("api_domain")
        if api_domain:
            self.config.api_base_url = self._replace_base_domain(self.config.api_base_url, str(api_domain))

        self._access_token = str(access_token)
        return self._access_token

    @staticmethod
    def _format_error(response: httpx.Response, prefix: str = "Zoho CRM API request failed") -> str:
        body: Any
        try:
            body = response.json()
        except ValueError:
            body = response.text
        return f"{prefix} with status {response.status_code}: {body}"

    @staticmethod
    def _replace_base_domain(api_base_url: str, api_domain: str) -> str:
        current = urlsplit(api_base_url)
        refreshed = urlsplit(api_domain)
        return urlunsplit((refreshed.scheme, refreshed.netloc, current.path, current.query, current.fragment))


class GoogleGeocoder:
    def __init__(
        self,
        api_key: str,
        logger: logging.Logger,
        timeout_seconds: float = 30.0,
        max_retries: int = 3,
        retry_delay_seconds: float = 1.0,
    ) -> None:
        self.api_key = api_key
        self.logger = logger
        self.max_retries = max(1, max_retries)
        self.retry_delay_seconds = max(0.0, retry_delay_seconds)
        timeout = httpx.Timeout(timeout_seconds, connect=min(20.0, timeout_seconds))
        self._client = httpx.Client(timeout=timeout)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "GoogleGeocoder":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def geocode(self, address: str) -> GeocodeResult | None:
        for attempt in range(1, self.max_retries + 1):
            response = self._client.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={
                    "address": address,
                    "key": self.api_key,
                },
            )
            if response.status_code >= 400:
                if attempt < self.max_retries and response.status_code >= 500:
                    time.sleep(self.retry_delay_seconds)
                    continue
                raise GoogleGeocodeError(
                    f"Google Geocoding request failed with status {response.status_code}: {response.text}"
                )

            payload = response.json()
            status = payload.get("status")
            if status == "OK":
                result = payload["results"][0]
                location = (result.get("geometry") or {}).get("location") or {}
                return GeocodeResult(
                    latitude=float(location["lat"]),
                    longitude=float(location["lng"]),
                    formatted_address=str(result.get("formatted_address") or address),
                    place_id=result.get("place_id"),
                    location_type=(result.get("geometry") or {}).get("location_type"),
                )

            if status == "ZERO_RESULTS":
                return None

            if status == "UNKNOWN_ERROR" and attempt < self.max_retries:
                time.sleep(self.retry_delay_seconds)
                continue

            error_message = payload.get("error_message")
            detail = f"{status}: {error_message}" if error_message else str(status)
            raise GoogleGeocodeError(f"Google Geocoding failed for '{address}': {detail}")

        raise GoogleGeocodeError(f"Google Geocoding failed for '{address}' after retries")


def fetch_quote_shipping_addresses(
    zoho_client: ZohoCrmClient,
    max_records: int | None = None,
) -> list[QuoteAddressRecord]:
    return zoho_client.fetch_quotes_with_shipping_addresses(max_records=max_records)


def geocode_quote_records(
    records: Iterable[QuoteAddressRecord],
    geocoder: GoogleGeocoder,
    *,
    skip_existing: bool = True,
) -> list[dict[str, Any]]:
    report: list[dict[str, Any]] = []

    for record in records:
        item = record.to_dict()
        address = record.formatted_address()

        if not address:
            item["status"] = "skipped_missing_address"
            report.append(item)
            continue

        if skip_existing and record.has_coordinates():
            item["status"] = "skipped_existing_coordinates"
            report.append(item)
            continue

        geocode = geocoder.geocode(address)
        if geocode is None:
            item["status"] = "no_geocode_result"
            report.append(item)
            continue

        item["status"] = "geocoded"
        item["geocode"] = geocode.to_dict()
        report.append(item)

    return report


def sync_quote_coordinates(
    zoho_client: ZohoCrmClient,
    geocoder: GoogleGeocoder,
    *,
    max_records: int | None = None,
    skip_existing: bool = True,
    dry_run: bool = False,
) -> dict[str, Any]:
    records = fetch_quote_shipping_addresses(zoho_client, max_records=max_records)
    summary = {
        "fetched": len(records),
        "updated": 0,
        "dry_run": 0,
        "skipped_missing_address": 0,
        "skipped_existing_coordinates": 0,
        "no_geocode_result": 0,
        "geocode_errors": 0,
        "update_errors": 0,
    }
    items: list[dict[str, Any]] = []

    for record in records:
        item = record.to_dict()
        address = record.formatted_address()

        if not address:
            item["status"] = "skipped_missing_address"
            summary["skipped_missing_address"] += 1
            items.append(item)
            continue

        if skip_existing and record.has_coordinates():
            item["status"] = "skipped_existing_coordinates"
            summary["skipped_existing_coordinates"] += 1
            items.append(item)
            continue

        try:
            geocode = geocoder.geocode(address)
        except GoogleGeocodeError as exc:
            item["status"] = "geocode_error"
            item["error"] = str(exc)
            summary["geocode_errors"] += 1
            items.append(item)
            continue

        if geocode is None:
            item["status"] = "no_geocode_result"
            summary["no_geocode_result"] += 1
            items.append(item)
            continue

        item["geocode"] = geocode.to_dict()

        if dry_run:
            item["status"] = "dry_run"
            summary["dry_run"] += 1
            items.append(item)
            continue

        try:
            update_response = zoho_client.update_quote_coordinates(
                record.quote_id,
                geocode.latitude,
                geocode.longitude,
            )
        except ZohoApiError as exc:
            item["status"] = "update_error"
            item["error"] = str(exc)
            summary["update_errors"] += 1
            items.append(item)
            continue

        item["status"] = "updated"
        item["update_response"] = update_response
        summary["updated"] += 1
        items.append(item)

    return {
        "summary": summary,
        "items": items,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fetch Zoho CRM quotes, geocode shipping addresses with Google, and update latitude/longitude."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    fetch_parser = subparsers.add_parser("fetch", help="Fetch quotes and export their shipping address fields.")
    sync_parser = subparsers.add_parser("sync", help="Fetch quotes, geocode shipping addresses, and update CRM.")

    for current_parser in (fetch_parser, sync_parser):
        current_parser.add_argument(
            "--api-base-url",
            default=_read_env("ZOHO_CRM_API_BASE_URL", default="https://www.zohoapis.com/crm/v7"),
            help="Zoho CRM API base URL, including the CRM version path.",
        )
        current_parser.add_argument(
            "--accounts-url",
            default=_read_env(
                "ZOHO_CRM_ACCOUNTS_URL",
                "ZOHO_WORKDRIVE_ACCOUNTS_URL",
                default="https://accounts.zoho.com/oauth/v2/token",
            ),
            help="Zoho Accounts OAuth token URL for your data center.",
        )
        current_parser.add_argument(
            "--module",
            default=_read_env("ZOHO_CRM_MODULE", default="Quotes"),
            help="Zoho CRM module API name. Default: Quotes",
        )
        current_parser.add_argument(
            "--street-field",
            default=_read_env("ZOHO_QUOTE_SHIPPING_STREET_FIELD", default="Shipping_Street"),
            help="Shipping street field API name.",
        )
        current_parser.add_argument(
            "--city-field",
            default=_read_env("ZOHO_QUOTE_SHIPPING_CITY_FIELD", default="Shipping_City"),
            help="Shipping city field API name.",
        )
        current_parser.add_argument(
            "--state-field",
            default=_read_env("ZOHO_QUOTE_SHIPPING_STATE_FIELD", default="Shipping_State"),
            help="Shipping state/province field API name.",
        )
        current_parser.add_argument(
            "--postal-field",
            default=_read_env("ZOHO_QUOTE_SHIPPING_POSTAL_CODE_FIELD", default="Shipping_Code"),
            help="Shipping postal code field API name.",
        )
        current_parser.add_argument(
            "--country-field",
            default=_read_env("ZOHO_QUOTE_SHIPPING_COUNTRY_FIELD", default="Shipping_Country"),
            help="Shipping country field API name.",
        )
        current_parser.add_argument(
            "--page-size",
            type=int,
            default=int(_read_env("ZOHO_CRM_PAGE_SIZE", default="200") or "200"),
            help="Zoho page size, max 200.",
        )
        current_parser.add_argument(
            "--max-records",
            type=int,
            default=None,
            help="Optional cap on the number of quotes to process.",
        )
        current_parser.add_argument(
            "--timeout",
            type=float,
            default=float(_read_env("ZOHO_CRM_TIMEOUT_SECONDS", default="30") or "30"),
            help="HTTP timeout in seconds.",
        )
        current_parser.add_argument(
            "--output",
            type=Path,
            default=None,
            help="Optional JSON output file.",
        )
        current_parser.add_argument(
            "--log-level",
            default=os.getenv("LOG_LEVEL", "INFO"),
            choices=["DEBUG", "INFO", "WARNING", "ERROR"],
            help="Log level.",
        )

    sync_parser.add_argument(
        "--latitude-field",
        default=_read_env("ZOHO_QUOTE_LATITUDE_FIELD"),
        help="Latitude field API name in the quote module.",
    )
    sync_parser.add_argument(
        "--longitude-field",
        default=_read_env("ZOHO_QUOTE_LONGITUDE_FIELD"),
        help="Longitude field API name in the quote module.",
    )
    sync_parser.add_argument(
        "--google-api-key",
        default=_read_env("GOOGLE_MAPS_API_KEY", "GOOGLE_GEOCODING_API_KEY"),
        help="Google Maps Geocoding API key.",
    )
    sync_parser.add_argument(
        "--update-existing",
        action="store_true",
        help="Update quotes even if both latitude and longitude are already populated.",
    )
    sync_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Geocode records without updating Zoho CRM.",
    )
    sync_parser.add_argument(
        "--retry-delay",
        type=float,
        default=float(_read_env("GOOGLE_GEOCODE_RETRY_DELAY_SECONDS", default="1") or "1"),
        help="Delay between Google retry attempts in seconds.",
    )
    sync_parser.add_argument(
        "--max-retries",
        type=int,
        default=int(_read_env("GOOGLE_GEOCODE_MAX_RETRIES", default="3") or "3"),
        help="Maximum Google Geocoding retry attempts.",
    )

    return parser


def _build_configs(args: argparse.Namespace) -> tuple[ZohoAuthConfig, QuoteFieldConfig]:
    zoho_config = ZohoAuthConfig(
        api_base_url=str(args.api_base_url).rstrip("/"),
        accounts_url=str(args.accounts_url).rstrip("/"),
        module_api_name=args.module,
        access_token=_read_env("ZOHO_CRM_ACCESS_TOKEN", "ZOHO_WORKDRIVE_ACCESS_TOKEN"),
        refresh_token=_read_env("ZOHO_CRM_REFRESH_TOKEN", "ZOHO_WORKDRIVE_REFRESH_TOKEN"),
        client_id=_read_env("ZOHO_CRM_CLIENT_ID", "ZOHO_WORKDRIVE_CLIENT_ID"),
        client_secret=_read_env("ZOHO_CRM_CLIENT_SECRET", "ZOHO_WORKDRIVE_CLIENT_SECRET"),
        page_size=args.page_size,
        timeout_seconds=args.timeout,
    )
    field_config = QuoteFieldConfig(
        street_field=args.street_field,
        city_field=args.city_field,
        state_field=args.state_field,
        postal_code_field=args.postal_field,
        country_field=args.country_field,
        latitude_field=getattr(args, "latitude_field", None),
        longitude_field=getattr(args, "longitude_field", None),
    )
    return zoho_config, field_config


def _configure_logging(level_name: str) -> logging.Logger:
    logging.basicConfig(
        level=getattr(logging, level_name.upper(), logging.INFO),
        format="%(levelname)s %(message)s",
    )
    return logging.getLogger("zoho-quote-geocode")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logger = _configure_logging(args.log_level)
    zoho_config, field_config = _build_configs(args)

    try:
        with ZohoCrmClient(zoho_config, field_config, logger) as zoho_client:
            if args.command == "fetch":
                records = fetch_quote_shipping_addresses(zoho_client, max_records=args.max_records)
                payload = {
                    "count": len(records),
                    "quotes": [record.to_dict() for record in records],
                }
            else:
                if not args.google_api_key:
                    raise ConfigError(
                        "Google API key is required for sync mode. Set GOOGLE_MAPS_API_KEY or pass --google-api-key."
                    )

                with GoogleGeocoder(
                    api_key=args.google_api_key,
                    logger=logger,
                    timeout_seconds=args.timeout,
                    max_retries=args.max_retries,
                    retry_delay_seconds=args.retry_delay,
                ) as geocoder:
                    payload = sync_quote_coordinates(
                        zoho_client,
                        geocoder,
                        max_records=args.max_records,
                        skip_existing=not args.update_existing,
                        dry_run=args.dry_run,
                    )

    except (ConfigError, ZohoApiError, GoogleGeocodeError) as exc:
        logger.error(str(exc))
        return 1

    if args.output:
        _write_json(args.output, payload)
        logger.info("Wrote JSON output to %s", args.output)
    else:
        json.dump(payload, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")

    if args.command == "sync":
        summary = payload["summary"]
        logger.info(
            "Fetched=%s Updated=%s DryRun=%s MissingAddress=%s ExistingCoordinates=%s NoGeocode=%s GeocodeErrors=%s UpdateErrors=%s",
            summary["fetched"],
            summary["updated"],
            summary["dry_run"],
            summary["skipped_missing_address"],
            summary["skipped_existing_coordinates"],
            summary["no_geocode_result"],
            summary["geocode_errors"],
            summary["update_errors"],
        )
        if summary["geocode_errors"] or summary["update_errors"]:
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
