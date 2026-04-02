# Update Quote Geolocation

Webhook-first Linux service for Zoho CRM quote geolocation and Quebec boundary enrichment.

The production workflow is now:

1. Zoho sends a webhook with a single `quote_id`
2. the service fetches that quote from Zoho CRM
3. it formats the shipping address
4. it geocodes the address with Google
5. it resolves `Region`, `MRC`, `Muni`, and optional `Arrondissement` from shapefiles
6. it performs one final Zoho update for that quote with every successful value from that run

The older batch and debug commands are still kept in the repo and in Git history, but the Linux package is now centered on webhook mode.

## What Each File Does

- `quote_geolocation_webhook.py`
  FastAPI app. Receives `quote_id` by webhook and runs the single-quote enrichment flow.

- `zoho_quote_geocode.py`
  Core quote-processing logic. The webhook calls into this file to fetch, geocode, resolve boundaries, and update Zoho CRM.

- `zoho_quote_geocode.env.example`
  Template config file. Shows where to put Zoho OAuth settings, Google API key, Zoho field API names, shapefile paths, and webhook settings.

- `requirements.txt`
  Python dependencies used by the webhook app and Debian package build.

- `packaging/build-deb.sh`
  Builds the `.deb` package published through the APT repository.

- `packaging/update-quote-geolocation.service`
  Systemd unit file installed by the package for the webhook service.

- `.github/workflows/publish-apt.yml`
  On every push to `main`, builds a new Debian package and republishes the APT repository content to `gh-pages`.

## Installed Linux Commands

After package installation:

- `update-quote-geolocation`
  Starts the webhook service. This is the main production entrypoint.

- `update-quote-geolocation-webhook`
  Compatibility alias for the same webhook service.

- `update-quote-geolocation-cli`
  Archived debug/maintenance CLI. Not needed for the normal webhook deployment.

The package installs:

- app code under `/usr/lib/update-quote-geolocation/`
- example config under `/etc/update-quote-geolocation/zoho_quote_geocode.env.example`
- working config under `/etc/update-quote-geolocation/zoho_quote_geocode.env`
- systemd unit under `/lib/systemd/system/update-quote-geolocation.service`

Configuration is loaded from:

1. `/etc/update-quote-geolocation/zoho_quote_geocode.env`
2. `~/.config/update-quote-geolocation/zoho_quote_geocode.env`
3. `ZOHO_QUOTE_GEOLOCATION_ENV_FILE` if you set it explicitly

## Linux Install And Upgrade

Install on Ubuntu or Debian:

```bash
curl -fsSL https://raw.githubusercontent.com/yboucher97/Update-Quote-Geolocation/gh-pages/update-quote-geolocation.list | sudo tee /etc/apt/sources.list.d/update-quote-geolocation.list >/dev/null
sudo apt update
sudo apt install update-quote-geolocation
```

After you push new changes to GitHub:

```bash
sudo apt update
sudo apt upgrade update-quote-geolocation
```

## Configure Zoho, Google, And Shapefiles

Edit:

```text
/etc/update-quote-geolocation/zoho_quote_geocode.env
```

Required Zoho and Google settings:

- `ZOHO_CRM_API_BASE_URL`
- `ZOHO_CRM_ACCOUNTS_URL`
- `ZOHO_CRM_REFRESH_TOKEN`
- `ZOHO_CRM_CLIENT_ID`
- `ZOHO_CRM_CLIENT_SECRET`
- `GOOGLE_MAPS_API_KEY`

Required Zoho field API names:

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

Shapefile paths and attributes:

- `ZOHO_ARRON_SHAPE_PATH`
- `ZOHO_ARRON_NAME_ATTRIBUTE`
- `ZOHO_MUNI_SHAPE_PATH`
- `ZOHO_MUNI_NAME_ATTRIBUTE`
- `ZOHO_MUNI_MRC_ATTRIBUTE`
- `ZOHO_MUNI_REGION_ATTRIBUTE`
- `ZOHO_MUNI_REGION_CODE_ATTRIBUTE`
- `ZOHO_MRC_SHAPE_PATH`
- `ZOHO_MRC_NAME_ATTRIBUTE`
- `ZOHO_MRC_REGION_ATTRIBUTE`
- `ZOHO_MRC_REGION_CODE_ATTRIBUTE`
- `ZOHO_REGION_SHAPE_PATH`
- `ZOHO_REGION_NAME_ATTRIBUTE`
- `ZOHO_REGION_CODE_ATTRIBUTE`

Webhook settings:

- `ZOHO_QUOTE_WEBHOOK_SECRET`
- `ZOHO_QUOTE_WEBHOOK_HOST`
- `ZOHO_QUOTE_WEBHOOK_PORT`

Recommended Quebec shapefile paths:

```text
/opt/update-quote-geolocation/shapes/SHP/arron_s.shp
/opt/update-quote-geolocation/shapes/SHP/munic_s.shp
/opt/update-quote-geolocation/shapes/SHP/mrc_s.shp
/opt/update-quote-geolocation/shapes/SHP/regio_s.shp
```

Default Quebec attribute names already match the files you provided:

- `arron_s.shp`: `ARS_NM_ARR`
- `munic_s.shp`: `MUS_NM_MUN`, `MUS_NM_MRC`, `MUS_NM_REG`, `MUS_CO_REG`
- `mrc_s.shp`: `MRS_NM_MRC`, `MRS_NM_REG`, `MRS_CO_REG`
- `regio_s.shp`: `RES_NM_REG`, `RES_CO_REG`

The `Lat` and `Long` destination fields in Zoho should stay numeric decimal fields, not text fields.

## Example Config

Example `/etc/update-quote-geolocation/zoho_quote_geocode.env`:

```env
ZOHO_CRM_API_BASE_URL=https://www.zohoapis.com/crm/v7
ZOHO_CRM_ACCOUNTS_URL=https://accounts.zoho.com/oauth/v2/token
ZOHO_CRM_REFRESH_TOKEN=your_refresh_token
ZOHO_CRM_CLIENT_ID=your_client_id
ZOHO_CRM_CLIENT_SECRET=your_client_secret
GOOGLE_MAPS_API_KEY=your_google_key

ZOHO_CRM_MODULE=Quotes
ZOHO_QUOTE_LATITUDE_FIELD=Lat
ZOHO_QUOTE_LONGITUDE_FIELD=Long
ZOHO_QUOTE_REGION_NAME_FIELD=Region
ZOHO_QUOTE_MRC_NAME_FIELD=MRC
ZOHO_QUOTE_MUNI_NAME_FIELD=Muni
ZOHO_QUOTE_ARRON_NAME_FIELD=Arrondissement

ZOHO_ARRON_SHAPE_PATH=/opt/update-quote-geolocation/shapes/SHP/arron_s.shp
ZOHO_MUNI_SHAPE_PATH=/opt/update-quote-geolocation/shapes/SHP/munic_s.shp
ZOHO_MRC_SHAPE_PATH=/opt/update-quote-geolocation/shapes/SHP/mrc_s.shp
ZOHO_REGION_SHAPE_PATH=/opt/update-quote-geolocation/shapes/SHP/regio_s.shp

ZOHO_QUOTE_WEBHOOK_HOST=127.0.0.1
ZOHO_QUOTE_WEBHOOK_PORT=8050
ZOHO_QUOTE_WEBHOOK_SECRET=your_shared_secret
```

## Run As A Service

Enable and start the webhook service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now update-quote-geolocation
sudo systemctl status update-quote-geolocation --no-pager -l
```

Local checks:

```bash
curl http://127.0.0.1:8050/health/quote-geolocation
curl -X POST http://127.0.0.1:8050/webhooks/zoho/quote-geolocation \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your_shared_secret" \
  -d '{"quote_id":"4143382000212414002"}'
```

## Caddy Example

Example site:

```caddyfile
quote-geo.wifiplex.ca {
    reverse_proxy 127.0.0.1:8050
}
```

The recommended public URL is:

```text
https://quote-geo.wifiplex.ca/webhooks/zoho/quote-geolocation
```

## Webhook Contract

Health check:

```http
GET /health/quote-geolocation
```

Webhook request:

```http
POST /webhooks/zoho/quote-geolocation
Content-Type: application/json
X-Webhook-Secret: your_shared_secret

{
  "quote_id": "4143382000212414002"
}
```

The webhook only needs `quote_id`. It fetches the quote itself and then does the rest.

## Deluge Example

```deluge
quoteId = input.id.toString();

payload = Map();
payload.put("quote_id", quoteId);

response = invokeurl
[
    url :"https://quote-geo.wifiplex.ca/webhooks/zoho/quote-geolocation"
    type :POST
    content-type :"application/json"
    headers:{"X-Webhook-Secret":"YOUR_SECRET_HERE"}
    body:payload.toString()
    detailed:true
];

info response;
```

## Archived CLI

The older multi-command CLI is still present for archive and debugging through:

```bash
update-quote-geolocation-cli
```

That path still includes:

- `fetch`
- `sync`
- `region-sync`
- `report`
- `run`
- `run-one`

The supported production deployment is the webhook service, not the batch CLI.

## Notes

- The webhook fetches exactly one quote by ID and processes only that quote.
- It stages geocode and boundary results first, then performs one final Zoho update for that quote using every successful field from that run.
- If a field group cannot be resolved, the quote is still updated with the fields that did succeed.
- With refresh-token auth, the script uses Zoho's returned `api_domain` automatically.
- Coordinate values are rounded before update so they fit Zoho decimal field limits more reliably.
- The public APT source is published from the `gh-pages` branch and consumed through `raw.githubusercontent.com`.

## References

- [Zoho OAuth 2.0](https://www.zoho.com/crm/developer/docs/api/v8/oauth-overview.html)
- [Zoho Get Records API](https://www.zoho.com/crm/developer/docs/api/v8/get-records.html)
- [Zoho Update Records API](https://www.zoho.com/crm/developer/docs/api/v8/update-records.html)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding/guides-v3/requests-geocoding)
