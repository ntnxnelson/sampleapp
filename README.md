# sampleapp

Three-tier sample application ("Peaks") for automation testing: an NGINX web
tier, a Node.js REST API tier and a MongoDB database tier, each on its own
Ubuntu VM.

```
browser ──HTTP:80──▶ NGINX VM ──/api/ proxy :3000──▶ Node.js VM ──:27017──▶ MongoDB VM
                     web.tar.gz                      nodejs-app.tar.gz       db.tar.gz
```

The browser only ever talks to the NGINX VM. NGINX serves the static page and
reverse-proxies `/api/` to the Node.js tier, so no CORS configuration and no
public port 3000 are needed.

## Repository layout

| Path                | Contents                                                     |
|---------------------|--------------------------------------------------------------|
| `web/`              | Web tier source: `index.html`, `js/`, `css/`, `images/`, `nginx/peaks.conf`, `setup.sh` |
| `nodejs-app/`       | API tier source: `app.js`, `routes/`, `models/`, `package.json`, `package-lock.json`, `peaks-api.service`, `setup.sh` |
| `db/`               | Database tier: `seed.js` (seed data), `setup.sh`             |
| `web.tar.gz`, `nodejs-app.tar.gz`, `db.tar.gz` | Deployable archives of the three directories above (files at the archive root) |
| `build-tarballs.sh` | Rebuilds the three archives from the source directories       |
| `peaksdata.json`    | The same peak data as a plain JSON document                   |

Edit the source directories, then run `./build-tarballs.sh` to refresh the archives.

## Deployment

Deploy in the order database, API, web. Each tier ships a `setup.sh` that
expects the tier's software to already be installed by your automation. Each
script is idempotent and safe to re-run.

The archives have their files at the root, so extract each one into a
directory you create first (`tar` does not create the `-C` target). Any
location works, for example the home directory; the scripts copy what needs
to live elsewhere (`/opt/peaks-api`, `/var/www/peaks`) as root themselves.

Common prerequisites for all three scripts:

- run as root (`sudo`), on Ubuntu with systemd;
- the software for that tier installed system-wide and on root's `PATH`
  (`sudo` uses `/usr/local/bin`, `/usr/bin` and `/snap/bin`); a per-user
  `nvm` install of Node.js is not visible to `sudo` or to the service user;
- no authentication enabled on MongoDB (set `MONGODB_URI` on the API VM if
  your automation enables it);
- network reachability between the VMs on the ports listed under
  "Verifying a deployment" (hypervisor or cloud firewalls are outside the
  scripts' control; host `ufw` is handled).

### 1. Database VM (MongoDB)

Prerequisite: MongoDB 4.0 or newer with the `mongosh` (or legacy `mongo`) shell.

```bash
mkdir -p ~/peaks-db && tar xzf db.tar.gz -C ~/peaks-db
sudo ~/peaks-db/setup.sh
```

What it does:

- sets `net.bindIp` in `/etc/mongod.conf` to `0.0.0.0` (override with
  `MONGODB_BIND_IP`) and restarts `mongod`, because Ubuntu packages listen on
  localhost only;
- loads `seed.js` into `demodb.peaks` (58 documents). The script skips the
  insert if the collection already has data;
- if `ufw` is active and `NODEJS_IP_ADDRESS` is set, allows 27017/tcp from
  that address.

Manual alternative: `mongosh seed.js`. Note that both MongoDB shells only treat
a positional argument as a script when its name ends in `.js`.

### 2. API VM (Node.js)

Prerequisite: Node.js 16.20.1 or newer with npm (mongoose 8 requires it).
Tested with Node.js 17.9.1 and the current LTS releases. The `nodejs` package
in Ubuntu 22.04's default repos (12.x) is too old.

```bash
mkdir -p ~/peaks-api && tar xzf nodejs-app.tar.gz -C ~/peaks-api
sudo MONGODB_HOST=<mongodb-vm-ip> ~/peaks-api/setup.sh
```

What it does:

- finds Node.js: on `PATH`, or in common tarball-install locations such as
  `/usr/local/bin/nodejs/bin` (which `sudo` does not search), or wherever
  `NODE_BIN` points; checks the version and creates a `peaks` system user;
- installs dependencies with `npm ci --omit=dev` (needs internet access to the
  npm registry, or a mirror configured in `~/.npmrc`);
- writes `/etc/default/peaks-api` with the connection settings and installs the
  `peaks-api` systemd service listening on `PORT` (default 3000);
- if `ufw` is active, allows `PORT`/tcp.

Environment variables: `MONGODB_HOST` (required), `MONGODB_PORT` (27017),
`MONGODB_DB` (demodb), `MONGODB_URI` (full connection string, overrides the
three above), `PORT` (3000), `APP_DIR` (/opt/peaks-api).

The service keeps retrying the database connection every 5 seconds, so the
order in which the VMs finish booting does not matter.

### 3. Web VM (NGINX)

Prerequisite: nginx.

```bash
mkdir -p ~/peaks-web && tar xzf web.tar.gz -C ~/peaks-web
sudo NODEJS_IP_ADDRESS=<nodejs-vm-ip> ~/peaks-web/setup.sh
```

What it does:

- copies the site to `/var/www/peaks` (override with `WEB_ROOT`);
- replaces the `WEB_IP_ADDRESS` and `WEB_SERVER_NAME` placeholders in
  `index.html` (defaults: this host's first IP and hostname; override with the
  same-named variables);
- installs `nginx/peaks.conf` as the default site, with `/api/` proxied to
  `NODEJS_IP_ADDRESS:NODEJS_PORT` (default port 3000), and removes the stock
  default site;
- if `ufw` is active, allows 80/tcp.

## API

| Method | Path                     | Description                                                   |
|--------|--------------------------|---------------------------------------------------------------|
| GET    | `/api/peaks`             | All peaks, highest elevation first                            |
| GET    | `/api/peaks?state=colo`  | Filter by `rank` (exact) or `peak`, `elevation`, `state`, `range` (case-insensitive substring) |
| POST   | `/api/peaks`             | Add a peak (JSON or form body; `peak` is required). Returns 201 |
| GET    | `/api/info`              | IP, hostname and Node.js version of the API host              |
| GET    | `/api/health`            | 200 `{"status":"ok"}` when connected to MongoDB, otherwise 503 |

When MongoDB is unreachable, `/api/peaks` returns 503 immediately with
`{"error":"Database is not connected"}`.

## Verifying a deployment

```bash
# on the API VM
curl http://127.0.0.1:3000/api/health

# on the web VM (through the proxy)
curl http://127.0.0.1/api/health
curl http://127.0.0.1/api/peaks | head -c 300
```

Then open `http://<web-vm-ip>/` in a browser. The grey bar shows the NGINX
host and the Node.js host; the table below lists the peaks. Health through the
proxy returns 200 when everything is connected, 503 when Node.js is up but
cannot reach MongoDB, and 502 when NGINX cannot reach Node.js.

Firewall summary: 80/tcp on the web VM from clients, 3000/tcp on the API VM
from the web VM, 27017/tcp on the database VM from the API VM.

## Local development

Run the API against any MongoDB with `MONGODB_HOST=<host> npm start` inside
`nodejs-app/`. The page in `web/` expects `/api/` on the same origin; to point
it elsewhere, define `window.PEAKS_API_URL = "http://<host>:3000/api/"` before
`js/data.js` loads.
