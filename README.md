# Update Quote Geolocation

Standalone Python utility for Zoho CRM quote geolocation.

It fetches all quotes from Zoho CRM, builds a list of quote IDs with shipping address fields, formats each address, sends it to the Google Geocoding API, and updates the quote latitude/longitude fields in Zoho CRM.

## Files

- `zoho_quote_geocode.py`
  Main script. Supports:
  - `fetch`: export quote IDs and shipping address fields
  - `sync`: geocode addresses and update quote latitude/longitude fields

- `zoho_quote_geocode.env.example`
  Environment template. This is where you set Zoho auth, API domains, field API names, Google API key, and optional runtime settings.

- `requirements.txt`
  Python dependency file for this repo.

- `.gitignore`
  Keeps local secrets, virtualenvs, and generated Python files out of git.

## Linux setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp zoho_quote_geocode.env.example zoho_quote_geocode.env
```

Load your environment variables:

```bash
set -a
source zoho_quote_geocode.env
set +a
```

Optional:

```bash
chmod +x zoho_quote_geocode.py
```

## Where to change Zoho auth

Edit `zoho_quote_geocode.env` and fill these values:

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
  Preferred for automation on Linux.

- `ZOHO_CRM_CLIENT_ID`
  Zoho OAuth client ID.

- `ZOHO_CRM_CLIENT_SECRET`
  Zoho OAuth client secret.

- `ZOHO_CRM_ORG_ID`
  Kept in the env template for reference, but this script does not send it to the Zoho CRM record APIs because those endpoints authenticate through OAuth tokens rather than an org ID header.

## Where to change Zoho field mappings

Also in `zoho_quote_geocode.env`:

- `ZOHO_CRM_MODULE`
  Usually `Quotes`.

- `ZOHO_QUOTE_SHIPPING_STREET_FIELD`
- `ZOHO_QUOTE_SHIPPING_CITY_FIELD`
- `ZOHO_QUOTE_SHIPPING_STATE_FIELD`
- `ZOHO_QUOTE_SHIPPING_POSTAL_CODE_FIELD`
- `ZOHO_QUOTE_SHIPPING_COUNTRY_FIELD`

- `ZOHO_QUOTE_LATITUDE_FIELD`
- `ZOHO_QUOTE_LONGITUDE_FIELD`

The latitude and longitude fields must match your real Zoho field API names.

## Usage

Fetch all quotes with their address fields:

```bash
python3 zoho_quote_geocode.py fetch --output quotes.json
```

Dry run geocoding without updating Zoho:

```bash
python3 zoho_quote_geocode.py sync --dry-run --output geocode-dry-run.json
```

Run the full sync and update Zoho quote lat/lng:

```bash
python3 zoho_quote_geocode.py sync --output geocode-sync.json
```

Limit records while testing:

```bash
python3 zoho_quote_geocode.py sync --max-records 25 --dry-run
```

## Notes

- The script skips quotes that already have both latitude and longitude unless you pass `--update-existing`.
- If you use refresh-token auth, the script automatically applies Zoho's returned `api_domain` so it can adapt to your data center more safely.
- Do not commit `zoho_quote_geocode.env` with real secrets.

## References

- [Zoho OAuth 2.0](https://www.zoho.com/crm/developer/docs/api/v8/oauth-overview.html)
- [Zoho Get Records API](https://www.zoho.com/crm/developer/docs/api/v8/get-records.html)
- [Zoho Update Records API](https://www.zoho.com/crm/developer/docs/api/v8/update-records.html)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding/guides-v3/requests-geocoding)
