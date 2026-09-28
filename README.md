# Lifegame Webterm

A Game of Life sample app built with Zig and
[Chasen](https://github.com/hiroaqii/chasen). It runs in a terminal or a browser,
sharing the same simulation model. The browser version uses WebAssembly and
an HTML canvas.

## Requirements

Zig 0.16.0. The browser instructions below also use Python 3 as a local server.
Chasen is fetched automatically; no local Chasen checkout is needed.

## Run

From the repository root, start the terminal app:

```sh
zig build run
```

Or build and serve the browser version:

```sh
zig build web
python3 -m http.server 8000 --bind 127.0.0.1 --directory zig-out/web
```

Open <http://localhost:8000>. After making changes, rebuild and reload the page.

## Controls

The simulation starts paused.

| Key | Action |
| --- | --- |
| `Space` | Run / pause |
| `n` | Advance one generation |
| `r` | Randomize |
| `c` | Clear and pause |
| Arrow keys or `h` / `j` / `k` / `l` | Pan |
| `+` / `-` | Zoom in / out |
| `[` / `]` | Slow down / speed up |
| `q` | Quit; in the browser, pause |

## Development

Run tests and build both versions:

```sh
zig build test check-browser web install
```
