#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="update-quote-geolocation"
PACKAGE_VERSION="${1:?usage: build-apt-repo.sh <version>}"
DEB_PATH="${ROOT_DIR}/dist/deb/${PACKAGE_NAME}_${PACKAGE_VERSION}_all.deb"
REPO_ROOT="${ROOT_DIR}/dist/apt-repo"
POOL_DIR="${REPO_ROOT}/pool/main/u/${PACKAGE_NAME}"
DIST_ROOT="${REPO_ROOT}/dists/stable/main"
SITE_URL="${SITE_URL:-https://raw.githubusercontent.com/yboucher97/Update-Quote-Geolocation/gh-pages}"

if [ ! -f "${DEB_PATH}" ]; then
  echo "Missing Debian package: ${DEB_PATH}" >&2
  exit 1
fi

rm -rf "${REPO_ROOT}"
mkdir -p "${POOL_DIR}" "${DIST_ROOT}/binary-all" "${DIST_ROOT}/binary-amd64" "${DIST_ROOT}/binary-arm64"
cp "${DEB_PATH}" "${POOL_DIR}/"

pushd "${REPO_ROOT}" >/dev/null
dpkg-scanpackages pool /dev/null > "dists/stable/main/binary-all/Packages"
cp "dists/stable/main/binary-all/Packages" "dists/stable/main/binary-amd64/Packages"
cp "dists/stable/main/binary-all/Packages" "dists/stable/main/binary-arm64/Packages"
gzip -9fk "dists/stable/main/binary-all/Packages"
gzip -9fk "dists/stable/main/binary-amd64/Packages"
gzip -9fk "dists/stable/main/binary-arm64/Packages"

{
  cat <<EOF
Origin: yboucher97
Label: Update Quote Geolocation
Suite: stable
Codename: stable
Architectures: all amd64 arm64
Components: main
Description: APT repository for update-quote-geolocation
EOF
  apt-ftparchive release "dists/stable"
} > "dists/stable/Release"
popd >/dev/null

cat > "${REPO_ROOT}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Update Quote Geolocation APT Repo</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4f7fb;
      --panel: #ffffff;
      --ink: #162334;
      --muted: #526173;
      --line: #d5dfeb;
      --accent: #005bbb;
    }
    body {
      margin: 0;
      font-family: "Segoe UI", "Helvetica Neue", sans-serif;
      background: linear-gradient(180deg, #eef4fb 0%, var(--bg) 100%);
      color: var(--ink);
    }
    main {
      max-width: 900px;
      margin: 0 auto;
      padding: 48px 20px 72px;
    }
    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 24px;
      box-shadow: 0 12px 32px rgba(22, 35, 52, 0.08);
    }
    h1, h2 {
      margin-top: 0;
    }
    p, li {
      color: var(--muted);
      line-height: 1.6;
    }
    code, pre {
      font-family: "Cascadia Code", "Fira Code", monospace;
    }
    pre {
      background: #0f1720;
      color: #ecf3ff;
      padding: 16px;
      border-radius: 12px;
      overflow-x: auto;
    }
    a {
      color: var(--accent);
    }
  </style>
</head>
<body>
  <main>
    <div class="panel">
      <h1>Update Quote Geolocation</h1>
      <p>This branch snapshot hosts the APT repository for the <code>update-quote-geolocation</code> package.</p>
      <h2>Install</h2>
      <pre><code>curl -fsSL ${SITE_URL}/update-quote-geolocation.list | sudo tee /etc/apt/sources.list.d/update-quote-geolocation.list >/dev/null
sudo apt update
sudo apt install update-quote-geolocation</code></pre>
      <h2>Upgrade</h2>
      <pre><code>sudo apt update
sudo apt upgrade update-quote-geolocation</code></pre>
      <h2>Package version</h2>
      <p>Current published package: <code>${PACKAGE_VERSION}</code></p>
      <p>The repository is rebuilt from <code>main</code> on every push.</p>
    </div>
  </main>
</body>
</html>
EOF

cat > "${REPO_ROOT}/update-quote-geolocation.list" <<EOF
deb [trusted=yes] ${SITE_URL} stable main
EOF

echo "Built apt repository in ${REPO_ROOT}"
