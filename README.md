# Update Quote Geolocation

Single-quote webhook service for Zoho CRM quote enrichment.

The production flow is:

1. Zoho sends a webhook with one `quote_id`
2. the service fetches that quote from Zoho CRM
3. it formats the shipping address
4. it geocodes the address with Google
5. it resolves `Region`, `MRC`, `Muni`, and optional `Arrondissement` from shapefiles
6. it performs one final Zoho update for that quote

This repo now installs into one fixed service root:

```text
/opt/services/quote-geolocation/
```

## Installed Layout

After install, the important paths are:

```text
/opt/services/quote-geolocation/
/opt/services/quote-geolocation/app/
/opt/services/quote-geolocation/.venv/
/opt/services/quote-geolocation/config/
/opt/services/quote-geolocation/config/zoho_quote_geocode.env
/opt/services/quote-geolocation/data/
/opt/services/quote-geolocation/data/reports/
/opt/services/quote-geolocation/logs/
/etc/systemd/system/quote-geolocation.service
/etc/caddy/conf.d/webhooks.caddy
```

The app code, venv, config, data, and logs all stay together under one service folder.

## Install

Run this on the target machine:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/yboucher97/Update-Quote-Geolocation/main/install.sh)
```

The installer:

- installs system packages
- clones or updates the repo into `/opt/services/quote-geolocation/app`
- creates `/opt/services/quote-geolocation/.venv`
- stores config in `/opt/services/quote-geolocation/config`
- stores reports and run artifacts in `/opt/services/quote-geolocation/data`
- stores logs in `/opt/services/quote-geolocation/logs`
- creates `quote-geolocation.service`
- disables the older `update-quote-geolocation` package service if it exists
- writes the shared Caddy file at `/etc/caddy/conf.d/webhooks.caddy`

## Update

On the target machine:

```bash
sudo /opt/services/quote-geolocation/app/update.sh
```

That keeps the same paths, refreshes the repo, rebuilds the venv, reapplies the service config, and rewrites the shared Caddy file.

## Shared Caddy Layout

This installer assumes the quote geolocation webhook and the PDF generator webhook live on the same VM and same hostname.

The shared Caddy file routes:

- `/quote-geolocation/*` to the geolocation service on `127.0.0.1:8050`
- `/pdf/*` to the PDF service on `127.0.0.1:8000`
- the older quote paths `/webhooks/zoho/quote-geolocation*` and `/health/quote-geolocation*` to the geolocation service
- everything else to the PDF service for backward compatibility

So the preferred public paths are:

- quote health: `https://pdf.wifiplex.ca/quote-geolocation/health`
- quote webhook: `https://pdf.wifiplex.ca/quote-geolocation/webhooks/zoho/quote-geolocation`

The older quote paths still work because Caddy explicitly keeps them routed.

## Config

Edit:

```text
/opt/services/quote-geolocation/config/zoho_quote_geocode.env
```

Important values:

- `ZOHO_CRM_API_BASE_URL`
- `ZOHO_CRM_ACCOUNTS_URL`
- `ZOHO_CRM_REFRESH_TOKEN`
- `ZOHO_CRM_CLIENT_ID`
- `ZOHO_CRM_CLIENT_SECRET`
- `GOOGLE_MAPS_API_KEY`
- `ZOHO_CRM_MODULE`
- `ZOHO_QUOTE_SHIPPING_STREET_FIELD`
- `ZOHO_QUOTE_SHIPPING_CITY_FIELD`
- `ZOHO_QUOTE_SHIPPING_STATE_FIELD`
- `ZOHO_QUOTE_SHIPPING_POSTAL_CODE_FIELD`
- `ZOHO_QUOTE_SHIPPING_COUNTRY_FIELD`
- `ZOHO_QUOTE_LATITUDE_FIELD`
- `ZOHO_QUOTE_LONGITUDE_FIELD`
- `ZOHO_QUOTE_REGION_NAME_FIELD`
- `ZOHO_QUOTE_MRC_NAME_FIELD`
- `ZOHO_QUOTE_MUNI_NAME_FIELD`
- `ZOHO_QUOTE_ARRON_NAME_FIELD`
- `ZOHO_ARRON_SHAPE_PATH`
- `ZOHO_MUNI_SHAPE_PATH`
- `ZOHO_MRC_SHAPE_PATH`
- `ZOHO_REGION_SHAPE_PATH`
- `ZOHO_QUOTE_WEBHOOK_SECRET`

Recommended Quebec shapefile paths:

```text
/opt/services/quote-geolocation/data/shapes/SHP/arron_s.shp
/opt/services/quote-geolocation/data/shapes/SHP/munic_s.shp
/opt/services/quote-geolocation/data/shapes/SHP/mrc_s.shp
/opt/services/quote-geolocation/data/shapes/SHP/regio_s.shp
```

The `Lat` and `Long` destination fields in Zoho should stay numeric decimal fields, not text fields.

## Runtime

Systemd service:

```bash
sudo systemctl enable --now quote-geolocation
sudo systemctl status quote-geolocation --no-pager -l
```

Direct local checks:

```bash
curl http://127.0.0.1:8050/health/quote-geolocation
curl -X POST http://127.0.0.1:8050/webhooks/zoho/quote-geolocation \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your_shared_secret" \
  -d '{"quote_id":"4143382000212414002"}'
```

Preferred public checks through Caddy:

```bash
curl https://pdf.wifiplex.ca/quote-geolocation/health
curl -X POST https://pdf.wifiplex.ca/quote-geolocation/webhooks/zoho/quote-geolocation \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your_shared_secret" \
  -d '{"quote_id":"4143382000212414002"}'
```

## Deluge Example

```deluge
quoteId = input.id.toString();

payload = Map();
payload.put("quote_id", quoteId);

response = invokeurl
[
    url :"https://pdf.wifiplex.ca/quote-geolocation/webhooks/zoho/quote-geolocation"
    type :POST
    content-type :"application/json"
    headers:{"X-Webhook-Secret":"YOUR_SECRET_HERE"}
    body:payload.toString()
    detailed:true
];

info response;
```

## Logs And Reports

- logs directory:
  `/opt/services/quote-geolocation/logs`
- rotating service log file:
  `/opt/services/quote-geolocation/logs/quote-geolocation.log`
- reports directory:
  `/opt/services/quote-geolocation/data/reports`

## Archived Paths

The older APT packaging and `/usr/lib/update-quote-geolocation` layout are kept in repo history, but the supported VM install path is now the local `install.sh` and `update.sh` workflow under `/opt/services/quote-geolocation`.

## References

- [Zoho OAuth 2.0](https://www.zoho.com/crm/developer/docs/api/v8/oauth-overview.html)
- [Zoho Get Records API](https://www.zoho.com/crm/developer/docs/api/v8/get-records.html)
- [Zoho Update Records API](https://www.zoho.com/crm/developer/docs/api/v8/update-records.html)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding/guides-v3/requests-geocoding)
