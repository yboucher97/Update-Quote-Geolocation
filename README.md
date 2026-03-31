# Update Quote Geolocation

Standalone Python utility for Zoho CRM quote geolocation and boundary enrichment.

The simplest path is now one command:

1. `run`: fetch one quote set, geocode shipping addresses, resolve `Region`/`MRC`/`Muni`/`Arrondissement`, then perform one final Zoho update per quote with every successful value from that run, and write one consolidated Excel report

It still also supports the lower-level jobs:

1. fetch quote shipping addresses from Zoho CRM
2. geocode and update latitude/longitude only
3. use existing quote latitude/longitude values with shapefiles to resolve and update `Region`, `MRC`, `Muni`, and optionally `Arrondissement`
4. merge separate JSON outputs into one readable report

## What Each File Does

- `zoho_quote_geocode.py`
  Main application. Commands:
  - `fetch`: export quote IDs and shipping address fields
  - `run`: do the full end-to-end quote enrichment in one command and write one consolidated workbook
  - `run-one`: do the same end-to-end enrichment for exactly one quote ID
  - `sync`: geocode shipping addresses and update quote latitude/longitude
  - `region-sync`: resolve arrondissement, municipality, MRC, and region from shapefiles and update CRM fields
  - `report`: merge `sync` and `region-sync` JSON outputs into one readable Excel run report

- `quote_geolocation_webhook.py`
  FastAPI app that accepts a `quote_id` via webhook, fetches that quote from Zoho CRM, geocodes its address, resolves Region/MRC/Muni/Arrondissement, and updates only that quote.

- `zoho_quote_geocode.env.example`
  Template config file. This shows where to put Zoho OAuth details, Google API key, Zoho field API names, and shapefile paths.

- `requirements.txt`
  Python dependencies used by the script and by the Debian package build.

- `packaging/build-deb.sh`
  Builds the `.deb` package installed by `apt`.

- `packaging/build-apt-repo.sh`
  Rebuilds the publishable APT repository content under `dist/apt-repo/`.

- `.github/workflows/publish-apt.yml`
  On every push to `main`, builds a new Debian package and republishes the APT repo content to the `gh-pages` branch.

- `.gitignore`
  Keeps local secrets, virtualenvs, caches, and build output out of git.

## Installed Linux Command

After package installation, the command is:

```bash
update-quote-geolocation
```

The package installs:

- app code under `/usr/lib/update-quote-geolocation/`
- example config under `/etc/update-quote-geolocation/zoho_quote_geocode.env.example`
- working config under `/etc/update-quote-geolocation/zoho_quote_geocode.env`
- CLI wrapper at `/usr/bin/update-quote-geolocation`
- webhook runner at `/usr/bin/update-quote-geolocation-webhook`

The command automatically loads configuration from:

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

## Local Repo Setup

If you want to run the repo directly instead of using the package:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp zoho_quote_geocode.env.example zoho_quote_geocode.env
set -a
source zoho_quote_geocode.env
set +a
```

## Where To Change Zoho Credentials

For repo-based use, edit:

```text
zoho_quote_geocode.env
```

For Linux package-based use, edit:

```text
/etc/update-quote-geolocation/zoho_quote_geocode.env
```

These variables are the Zoho auth and connection settings:

- `ZOHO_CRM_API_BASE_URL`
  Zoho CRM API base URL for your data center.
  Examples:
  - US: `https://www.zohoapis.com/crm/v7`
  - Canada: `https://www.zohoapis.ca/crm/v7`
  - Europe: `https://www.zohoapis.eu/crm/v7`

- `ZOHO_CRM_ACCOUNTS_URL`
  Zoho OAuth token URL for your data center.
  Examples:
  - US: `https://accounts.zoho.com/oauth/v2/token`
  - Canada: `https://accounts.zoho.ca/oauth/v2/token`
  - Europe: `https://accounts.zoho.eu/oauth/v2/token`

- `ZOHO_CRM_ACCESS_TOKEN`
  Optional direct access token.

- `ZOHO_CRM_REFRESH_TOKEN`
  Preferred for unattended Linux runs.

- `ZOHO_CRM_CLIENT_ID`
  Zoho OAuth client ID.

- `ZOHO_CRM_CLIENT_SECRET`
  Zoho OAuth client secret.

- `ZOHO_CRM_ORG_ID`
  Stored only for your reference. The script does not send a separate org ID header for standard Zoho CRM record APIs.

- `GOOGLE_MAPS_API_KEY`
  Google Geocoding API key.

- `ZOHO_GOOGLE_ERROR_REPORT_PATH`
  Default Excel output path for quotes where Google returned `ZERO_RESULTS` or an API error.

- `ZOHO_QUOTE_RUN_REPORT_PATH`
  Default Excel output path for the one-command `run` workbook.

- `ZOHO_QUOTE_RUN_ONE_REPORT_PATH`
  Default Excel output path for the one-quote `run-one` workbook.

- `ZOHO_QUOTE_WEBHOOK_SECRET`
  Optional shared secret. If set, webhook callers must send it in the `X-Webhook-Secret` header.

- `ZOHO_QUOTE_WEBHOOK_HOST`
  Bind address for the standalone FastAPI webhook runner.

- `ZOHO_QUOTE_WEBHOOK_PORT`
  Port for the standalone FastAPI webhook runner.

## Where To Change Zoho Field Names

Set these in the same env file:

- `ZOHO_CRM_MODULE`
- `ZOHO_QUOTE_SHIPPING_STREET_FIELD`
- `ZOHO_QUOTE_SHIPPING_CITY_FIELD`
- `ZOHO_QUOTE_SHIPPING_STATE_FIELD`
- `ZOHO_QUOTE_SHIPPING_POSTAL_CODE_FIELD`
- `ZOHO_QUOTE_SHIPPING_COUNTRY_FIELD`
- `ZOHO_QUOTE_LATITUDE_FIELD`
- `ZOHO_QUOTE_LONGITUDE_FIELD`
- `ZOHO_QUOTE_REGION_NAME_FIELD`
- `ZOHO_QUOTE_REGION_CODE_FIELD`
- `ZOHO_QUOTE_MRC_NAME_FIELD`
- `ZOHO_QUOTE_MUNI_NAME_FIELD`
- `ZOHO_QUOTE_ARRON_NAME_FIELD`
- `ZOHO_QUOTE_COORD_DECIMALS`
- `ZOHO_QUOTE_COORD_MAX_LENGTH`

The lat/long destination fields should stay numeric decimal fields in Zoho, not text fields.

## Quebec Shapefiles

You gave two shapefile sources:

- `regio_s`
  This is a Quebec administrative region layer only. It is broad and less precise.

- `SHP`
  This is a fuller Quebec boundary set. It includes multiple layers:
  - `arron_s.shp`: arrondissement polygons, useful for Montreal boroughs
  - `munic_s.shp`: municipality polygons, most precise
  - `mrc_s.shp`: MRC polygons, medium precision
  - `regio_s.shp`: region polygons, least precise
  - other supporting layers such as arrondissement files

For your use case, the right order is:

1. `arron_s.shp` as an optional overlay for arrondissement-level results
2. `munic_s.shp`
3. `mrc_s.shp`
4. `regio_s.shp`

`region-sync` now follows that idea: arrondissement overlay first when configured, then municipality, then MRC, then region.

Important:

- copy the shapefiles onto the Linux machine first
- use Linux paths in the env file, not Windows paths like `C:\Users\...`

Recommended Linux paths:

```text
/opt/update-quote-geolocation/shapes/SHP/munic_s.shp
/opt/update-quote-geolocation/shapes/SHP/mrc_s.shp
/opt/update-quote-geolocation/shapes/SHP/regio_s.shp
/opt/update-quote-geolocation/shapes/SHP/arron_s.shp
```

## Shapefile Config Variables

Arrondissement overlay layer:

- `ZOHO_ARRON_SHAPE_PATH`
- `ZOHO_ARRON_NAME_ATTRIBUTE`

Municipality layer:

- `ZOHO_MUNI_SHAPE_PATH`
- `ZOHO_MUNI_NAME_ATTRIBUTE`
- `ZOHO_MUNI_MRC_ATTRIBUTE`
- `ZOHO_MUNI_REGION_ATTRIBUTE`
- `ZOHO_MUNI_REGION_CODE_ATTRIBUTE`

MRC fallback layer:

- `ZOHO_MRC_SHAPE_PATH`
- `ZOHO_MRC_NAME_ATTRIBUTE`
- `ZOHO_MRC_REGION_ATTRIBUTE`
- `ZOHO_MRC_REGION_CODE_ATTRIBUTE`

Region fallback layer:

- `ZOHO_REGION_SHAPE_PATH`
- `ZOHO_REGION_NAME_ATTRIBUTE`
- `ZOHO_REGION_CODE_ATTRIBUTE`

Default Quebec attribute names already match the files you provided:

- `arron_s.shp`
  - arrondissement: `ARS_NM_ARR`

- `munic_s.shp`
  - municipality: `MUS_NM_MUN`
  - MRC: `MUS_NM_MRC`
  - region: `MUS_NM_REG`
  - region code: `MUS_CO_REG`

- `mrc_s.shp`
  - MRC: `MRS_NM_MRC`
  - region: `MRS_NM_REG`
  - region code: `MRS_CO_REG`

- `regio_s.shp`
  - region: `RES_NM_REG`
  - region code: `RES_CO_REG`

## Example Linux Config

Example `/etc/update-quote-geolocation/zoho_quote_geocode.env` values:

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
```

## Commands

Run the full process in one command and produce one workbook:

```bash
update-quote-geolocation run --report-output quote-run-report.xlsx
```

Run a live 5-record end-to-end test and also keep the merged JSON:

```bash
update-quote-geolocation run \
  --max-records 5 \
  --report-output live-5-run-report.xlsx \
  --output live-5-run-report.json
```

If you want to overwrite already-populated `Lat`/`Long`, add:

```bash
update-quote-geolocation run \
  --max-records 5 \
  --update-existing \
  --report-output live-5-run-report.xlsx
```

If you want to overwrite already-populated `Region`, `MRC`, `Muni`, or `Arrondissement`, add:

```bash
update-quote-geolocation run \
  --max-records 5 \
  --update-existing-region \
  --report-output live-5-run-report.xlsx
```

The remaining commands are still available for debugging or partial reruns.

Run the same end-to-end flow for exactly one quote:

```bash
update-quote-geolocation run-one \
  --quote-id 4143382000212414002 \
  --report-output single-quote-run-report.xlsx \
  --output single-quote-run-report.json
```

Fetch quotes and shipping address fields:

```bash
update-quote-geolocation fetch --output quotes.json
```

Dry-run geocoding without updating Zoho:

```bash
update-quote-geolocation sync --dry-run --output geocode-dry-run.json
```

Run the live lat/long update:

```bash
update-quote-geolocation sync --output geocode-sync.json
```

Run a live 5-record geocode-only test:

```bash
update-quote-geolocation sync \
  --max-records 5 \
  --output live-5-sync.json \
  --failure-report live-5-sync-failures.xlsx
```

Run a live 5-record boundary-only update test for `Region`, `MRC`, `Muni`, and optionally `Arrondissement`:

```bash
update-quote-geolocation region-sync \
  --max-records 5 \
  --output live-5-region-sync.json \
  --failure-report live-5-region-failures.xlsx
```

If you want to overwrite already-populated Region, MRC, Muni, or Arrondissement values:

```bash
update-quote-geolocation region-sync \
  --max-records 5 \
  --update-existing-region \
  --output live-5-region-sync.json \
  --failure-report live-5-region-failures.xlsx
```

Show the installed version:

```bash
update-quote-geolocation --version
```

Build one consolidated report from the `sync` and `region-sync` JSON outputs:

```bash
update-quote-geolocation report \
  --sync-input live-5-sync.json \
  --region-input live-5-region-sync.json \
  --report-output live-5-run-report.xlsx \
  --json-output live-5-run-report.json
```

## Webhook Endpoint

Run the standalone webhook service on the VM:

```bash
update-quote-geolocation-webhook
```

By default it listens on:

```text
127.0.0.1:8050
```

You can change that in `/etc/update-quote-geolocation/zoho_quote_geocode.env` with:

```env
ZOHO_QUOTE_WEBHOOK_HOST=127.0.0.1
ZOHO_QUOTE_WEBHOOK_PORT=8050
ZOHO_QUOTE_WEBHOOK_SECRET=your_shared_secret
```

Webhook request:

```http
POST /webhooks/quote-geolocation
Content-Type: application/json
X-Webhook-Secret: your_shared_secret

{
  "quote_id": "4143382000212414002"
}
```

Optional JSON body flags:

- `update_existing`
- `update_existing_region`

Health check:

```http
GET /health
```

Example Caddy route:

```caddyfile
handle /webhooks/quote-geolocation* {
    reverse_proxy 127.0.0.1:8050
}

handle /health {
    reverse_proxy 127.0.0.1:8050
}
```

## Excel Failure Reports

`sync` writes an Excel report for quotes with missing shipping fields, geocoding failures, or CRM update failures.

`sync` also writes a dedicated Google geocode Excel report for:

- `ZERO_RESULTS`
- Google API errors

If you want one readable file instead of separate JSON and Excel outputs, use `run` when you want to process live quotes in one pass, or use `report` when you already have separate `sync` and `region-sync` JSON outputs. The consolidated workbook creates:

- a summary sheet with narrative explanations
- a quote-by-quote sheet covering both sync steps
- an issues sheet filtered to rows that still need review
- a raw JSON sheet that embeds the original command outputs

For `run`, the workbook also shows the final combined field payload that was sent to Zoho for each quote at the end of the batch.

`region-sync` writes an Excel report for quotes when any of these happened:

- latitude or longitude was missing
- no polygon match was found
- only part of the requested admin data could be resolved
- the Zoho update failed

Each issue row includes:

- `quote_id`
- sync status
- missing shipping fields
- missing coordinate fields
- missing admin fields
- full shipping address columns
- current lat/long
- current Region, MRC, Muni, and Arrondissement values
- resolved Region, MRC, Muni, and Arrondissement values
- match source layer
- any error text
- raw field payload
- Zoho update response

The JSON output now includes:

- `meta` with command, version, timestamp, module, and max-records
- `status_reason` on each quote item
- `google_status` on geocode items
- `coordinate_update_values` or `admin_update_values` when applicable
- merged `report` JSON when you want both steps in one artifact

## Notes

- Quotes with existing latitude and longitude are skipped in `sync` unless you pass `--update-existing`.
- Quotes with all requested Region, MRC, Muni, and Arrondissement fields already filled are skipped in `region-sync` unless you pass `--update-existing-region`.
- `sync` now logs one line per quote explaining whether it was updated, skipped, or failed.
- `run` is the recommended command when you want one live pass and one readable workbook.
- `run` stages all geocode and boundary results first, then attempts one final Zoho `PUT` per quote using every field that succeeded for that quote.
- `run-one` uses the same logic, but fetches and updates only the quote ID you provide.
- `update-quote-geolocation-webhook` exposes the `run-one` behavior over FastAPI for Zoho webhooks or other HTTP callers.
- `report` is the best file to review when you already have separate JSON logs and want one readable explanation of the whole run.
- With refresh-token auth, the script uses Zoho's returned `api_domain` automatically.
- Coordinate values are rounded before update so they fit Zoho decimal field limits more reliably.
- The public APT source is published from the `gh-pages` branch and consumed through `raw.githubusercontent.com`.

## References

- [Zoho OAuth 2.0](https://www.zoho.com/crm/developer/docs/api/v8/oauth-overview.html)
- [Zoho Get Records API](https://www.zoho.com/crm/developer/docs/api/v8/get-records.html)
- [Zoho Update Records API](https://www.zoho.com/crm/developer/docs/api/v8/update-records.html)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding/guides-v3/requests-geocoding)
