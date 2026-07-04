# Kernel Images Server

The API server that runs inside Kernel browser instances. It fronts a
Chromium with a **CDP DevTools proxy** (with live upstream hot-swapping across
browser restarts) and a **ChromeDriver proxy**, and exposes REST endpoints for
**screen recording**, **file I/O**, **process execution**, **computer input**
(mouse/keyboard/screenshot), **display control**, and **telemetry/event
streaming**. See `GET /spec.yaml` for the full API.

In production it is baked into the images in `images/` and orchestrated by
`cmd/wrapper` + supervisord alongside Chromium, Xorg, and Neko. For local
development, `make dev-local` stands up the minimum substitute: a real
Chromium-family browser as the CDP upstream.

## 🛠️ Prerequisites

### Required Software

- **Go 1.24.3+** - Programming language runtime
- **Node.js** - `npx` fetches the dev browser; `pnpm` drives OpenAPI code generation
  - `npm install -g pnpm`
- **ffmpeg** - Video recording engine (only needed for the `/recording` endpoints)
  - macOS: `brew install ffmpeg`
  - Linux: `sudo apt install ffmpeg` or `sudo yum install ffmpeg`
- **uv** (optional) - Runs the `scripts/drive.py` smoke test

### System Requirements

- **macOS**: Uses AVFoundation for screen capture
- **Linux**: Uses X11 for screen capture
- **Windows**: Not currently supported

## 🚀 Quick Start

### Running the Server Locally

```bash
make dev-browser   # once: downloads Chrome for Testing into .dev/browser
make dev-local     # launches the browser + the server against it
```

`dev-local` starts the browser with remote debugging (headful, so you can
watch it), waits for its DevTools endpoint, then runs the server pointed at
it. Stop everything with `Ctrl-C`.

| Port    | Surface                                                  |
| ------- | -------------------------------------------------------- |
| `10001` | REST API                                                  |
| `9222`  | CDP DevTools proxy (Playwright/Puppeteer `connectOverCDP`) |
| `9224`  | ChromeDriver proxy                                        |

Variations:

```bash
HEADLESS=1 make dev-local                                  # no browser window
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" make dev-local
```

Smoke test (drives the browser over CDP and exercises REST endpoints):

```bash
uv run scripts/drive.py
```

> **No sandbox locally:** the server implements `/process` and `/fs` as plain
> OS calls — in production the *container* provides the isolation. Run outside
> it, they operate on your real machine, and the ports bind all interfaces.
> Endpoints that shell out to the container's Linux tooling fail per request
> locally: `/computer` (xdotool), `/chromium` lifecycle (supervisorctl), and
> `/display` (xrandr/Neko). `/recording` works, but captures your machine's
> screen.

`make dev` runs the bare server without a browser. It requires
`CHROMIUM_LOG_PATH` to point at a log containing a Chromium
`DevTools listening on ws://...` line, and exits if no upstream is found
within 10 seconds — supplying that browser is exactly what `dev-local` does
for you (and what the wrapper/supervisord stack does in the images).

#### Example use

```bash
# 1. Start a new recording
curl http://localhost:10001/recording/start -d {}

# (recording in progress)

# 2. Stop recording
curl http://localhost:10001/recording/stop -d {}

# 3. Download the recorded file
curl http://localhost:10001/recording/download --output recording.mp4
```

Note: outside the container, recording captures your machine's display — not
the dev browser's pages.

### ⚙️ Configuration

Configure the server using environment variables:

| Variable            | Default          | Description                                              |
| ------------------- | ---------------- | -------------------------------------------------------- |
| `CHROMIUM_LOG_PATH` | *(required)*     | Chromium log tailed for the DevTools `ws://` upstream URL |
| `PORT`              | `10001`          | HTTP server port                                          |
| `DEVTOOLS_PROXY_PORT` | `9222`         | CDP DevTools proxy port                                   |
| `CHROMEDRIVER_PROXY_PORT` | `9224`     | ChromeDriver proxy port                                   |
| `LOG_CDP_MESSAGES`  | `false`          | Log CDP messages passing through the proxy                |
| `FRAME_RATE`        | `10`             | Default recording framerate (fps)                         |
| `DISPLAY_NUM`       | `1`              | Display/screen number to capture                          |
| `MAX_SIZE_MB`       | `500`            | Default maximum file size (MB)                            |
| `OUTPUT_DIR`        | `.`              | Directory to save recordings                              |
| `FFMPEG_PATH`       | `ffmpeg`         | Path to the ffmpeg binary                                 |

In the images, `CHROMIUM_LOG_PATH` is set by the supervisord service config
(`kernel-images-api.conf`) to supervisord's chromium log; `dev-local` points
it at `.dev/chromium.log`.

#### Example Configuration

```bash
export CHROMIUM_LOG_PATH=/var/log/supervisord/chromium
export PORT=8080
export FRAME_RATE=30
export MAX_SIZE_MB=1000
export OUTPUT_DIR=/tmp/recordings
./bin/api
```

### API Documentation

- **YAML Spec**: `GET /spec.yaml`
- **JSON Spec**: `GET /spec.json`

## 🔧 Development

### Code Generation

The server uses OpenAPI code generation. After modifying `openapi.yaml`:

```bash
make oapi-generate
```

## 🧪 Testing

### Running Tests

```bash
make test
```
