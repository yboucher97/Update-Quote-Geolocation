# Update Quote Geolocation

Standalone Python utility for Zoho CRM quote geolocation.

It fetches quotes from Zoho CRM, builds a list of quote IDs plus shipping address fields, formats each address, sends it to the Google Geocoding API, and updates the quote latitude/longitude fields in Zoho CRM.

## What you get

- A local Python script for direct use from the repo
- A Debian package named `update-quote-geolocation`
- A GitHub Actions workflow that rebuilds and republishes the APT repo on every push to `main`
- A GitHub Pages APT repository so Linux machines can install and upgrade with `apt`

## Files

- `zoho_quote_geocode.py`
  Main application logic. Supports:
  - `fetch`: export quote IDs and shipping address fields
  - `sync`: geocode addresses and update quote latitude/longitude fields

- `zoho_quote_geocode.env.example`
  Template configuration file. Copy it to `zoho_quote_geocode.env` for repo-based use, or to `/etc/update-quote-geolocation/zoho_quote_geocode.env` on a Linux machine installed from APT.

- `requirements.txt`
  Python dependencies used by the script and by the Debian package build.

- `packaging/build-deb.sh`
  Builds the `.deb` package.

- `packaging/build-apt-repo.sh`
  Creates the APT repository structure, package index, Release file, and install helper files for GitHub Pages.

- `.github/workflows/publish-apt.yml`
  On every push to `main`, builds a new package version and republishes the APT repository to GitHub Pages.

- `.gitignore`
  Excludes local env files, caches, and build output from git.

## Installed Linux command

After package installation, the command is:

```bash
update-quote-geolocation
```

The package installs:

- the app code under `/usr/lib/update-quote-geolocation/`
- the example config under `/etc/update-quote-geolocation/zoho_quote_geocode.env.example`
- the working config file under `/etc/update-quote-geolocation/zoho_quote_geocode.env`

The installed command automatically loads configuration from:

1. `/etc/update-quote-geolocation/zoho_quote_geocode.env`
2. `~/.config/update-quote-geolocation/zoho_quote_geocode.env`
3. `ZOHO_QUOTE_GEOLOCATION_ENV_FILE` if you set it explicitly

## APT install

Once GitHub Pages is publishing this repo, install on Ubuntu or Debian with:

```bash
curl -fsSL https://yboucher97.github.io/Update-Quote-Geolocation/update-quote-geolocation.list | sudo tee /etc/apt/sources.list.d/update-quote-geolocation.list >/dev/null
sudo apt update
sudo apt install update-quote-geolocation
```

## APT upgrade after GitHub changes

Every push to `main` triggers `.github/workflows/publish-apt.yml`, which:

1. builds a new Debian package version
2. rebuilds the APT repository
3. republishes the repository to GitHub Pages

To pull the newest version on Linux:

```bash
sudo apt update
sudo apt upgrade update-quote-geolocation
```

## Local repo-based setup

If you want to run the script directly without the Debian package:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp zoho_quote_geocode.env.example zoho_quote_geocode.env
```

Load the env file:

```bash
set -a
source zoho_quote_geocode.env
set +a
```

Run it:

```bash
python3 zoho_quote_geocode.py fetch --output quotes.json
python3 zoho_quote_geocode.py sync --dry-run --output geocode-dry-run.json
python3 zoho_quote_geocode.py sync --output geocode-sync.json
```

## Where to change Zoho auth

For repo-based use, edit:

```text
zoho_quote_geocode.env
```

For package-based Linux use, edit:

```text
/etc/update-quote-geolocation/zoho_quote_geocode.env
```

Set these values there:

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
  Preferred for automation.

- `ZOHO_CRM_CLIENT_ID`
  Zoho OAuth client ID.

- `ZOHO_CRM_CLIENT_SECRET`
  Zoho OAuth client secret.

- `ZOHO_CRM_ORG_ID`
  Included for reference only. This script does not send a separate org ID header to Zoho CRM record endpoints.

- `GOOGLE_MAPS_API_KEY`
  Google Geocoding API key.

## Where to change field mappings

Change these in the same env file:

- `ZOHO_CRM_MODULE`
- `ZOHO_QUOTE_SHIPPING_STREET_FIELD`
- `ZOHO_QUOTE_SHIPPING_CITY_FIELD`
- `ZOHO_QUOTE_SHIPPING_STATE_FIELD`
- `ZOHO_QUOTE_SHIPPING_POSTAL_CODE_FIELD`
- `ZOHO_QUOTE_SHIPPING_COUNTRY_FIELD`
- `ZOHO_QUOTE_LATITUDE_FIELD`
- `ZOHO_QUOTE_LONGITUDE_FIELD`

The latitude and longitude values must match your real Zoho CRM field API names.

## Commands

Fetch quote IDs and shipping fields:

```bash
update-quote-geolocation fetch --output quotes.json
```

Dry run geocoding without updating CRM:

```bash
update-quote-geolocation sync --dry-run --output geocode-dry-run.json
```

Run the full update:

```bash
update-quote-geolocation sync --output geocode-sync.json
```

Limit records while testing:

```bash
update-quote-geolocation sync --max-records 25 --dry-run
```

Show installed version:

```bash
update-quote-geolocation --version
```

## Notes

- Quotes that already have both latitude and longitude are skipped unless you pass `--update-existing`.
- With refresh-token auth, the script uses Zoho's returned `api_domain` to adapt to your data center automatically.
- The generated APT source uses `trusted=yes`. If you want a signed APT repository, add GPG signing as a later step.
- GitHub Pages must be reachable for remote `apt install` to work.

## References

- [Zoho OAuth 2.0](https://www.zoho.com/crm/developer/docs/api/v8/oauth-overview.html)
- [Zoho Get Records API](https://www.zoho.com/crm/developer/docs/api/v8/get-records.html)
- [Zoho Update Records API](https://www.zoho.com/crm/developer/docs/api/v8/update-records.html)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding/guides-v3/requests-geocoding)
