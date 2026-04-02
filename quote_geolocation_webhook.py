from __future__ import annotations

import datetime as dt
import os
from contextlib import ExitStack

from fastapi import APIRouter, FastAPI, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field

import shapefile

import zoho_quote_geocode as geocode


class QuoteGeolocationWebhookRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quote_id: str = Field(..., min_length=1, description="Zoho CRM quote record ID")


def _ensure_webhook_secret(received_secret: str | None) -> None:
    expected_secret = os.getenv("ZOHO_QUOTE_WEBHOOK_SECRET")
    if expected_secret and received_secret != expected_secret:
        raise HTTPException(status_code=403, detail="Invalid webhook secret.")


def _build_run_one_args(
    quote_id: str,
    *,
    update_existing: bool,
    update_existing_region: bool,
) -> tuple[object, object]:
    geocode._load_default_env_files()
    parser = geocode.build_parser()
    argv = ["run-one", "--quote-id", quote_id]
    if update_existing:
        argv.append("--update-existing")
    if update_existing_region:
        argv.append("--update-existing-region")
    args = parser.parse_args(argv)
    logger = geocode._configure_logging(args.log_level)
    return args, logger


def _run_single_quote_from_webhook(
    quote_id: str,
) -> dict:
    args, logger = _build_run_one_args(
        quote_id,
        update_existing=False,
        update_existing_region=False,
    )
    zoho_config, field_config = geocode._build_configs(args)

    with geocode.ZohoCrmClient(zoho_config, field_config, logger) as zoho_client:
        region_configs = geocode._build_region_lookup_configs(args)
        arrond_config = geocode._build_arrond_lookup_config(args)
        with geocode.GoogleGeocoder(
            api_key=args.google_api_key,
            logger=logger,
            timeout_seconds=args.timeout,
            max_retries=args.max_retries,
            retry_delay_seconds=args.retry_delay,
        ) as geocoder_client:
            with ExitStack() as stack:
                resolvers = [
                    stack.enter_context(geocode.RegionShapeResolver(config, logger))
                    for config in region_configs
                ]
                arrond_resolver = (
                    stack.enter_context(geocode.RegionShapeResolver(arrond_config, logger))
                    if arrond_config
                    else None
                )
                payload = geocode.run_single_quote_enrichment(
                    zoho_client,
                    geocoder_client,
                    resolvers,
                    quote_id,
                    arrond_resolver=arrond_resolver,
                    skip_existing=not update_existing,
                    update_existing_region=update_existing_region,
                )

    meta = payload.get("meta") or {}
    meta.update(
        {
            "app_name": geocode.APP_NAME,
            "app_version": geocode.APP_VERSION,
            "command": "run-one-webhook",
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "module": args.module,
            "quote_id": quote_id,
        }
    )
    payload["meta"] = meta
    return payload


router = APIRouter()


@router.get("/health")
@router.get("/health/quote-geolocation")
@router.get("/quote-geolocation/health")
def health() -> dict[str, bool]:
    return {"ok": True}


@router.post("/webhooks/quote-geolocation")
@router.post("/webhooks/zoho/quote-geolocation")
@router.post("/quote-geolocation/webhooks/quote-geolocation")
@router.post("/quote-geolocation/webhooks/zoho/quote-geolocation")
def quote_geolocation_webhook(
    payload: QuoteGeolocationWebhookRequest,
    x_webhook_secret: str | None = Header(default=None),
) -> dict:
    _ensure_webhook_secret(x_webhook_secret)

    try:
        return _run_single_quote_from_webhook(
            payload.quote_id,
        )
    except HTTPException:
        raise
    except (
        geocode.ConfigError,
        geocode.ZohoApiError,
        geocode.GoogleGeocodeError,
        shapefile.ShapefileException,
    ) as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


def create_app() -> FastAPI:
    app = FastAPI(title="Update Quote Geolocation Webhook")
    app.include_router(router)
    return app


app = create_app()
