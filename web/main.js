const wasmUrls = [
  "./lifegame-webterm-browser.wasm",
  "../zig-out/web/lifegame-webterm-browser.wasm",
];
const canvas = document.querySelector("#screen");
const ctx = canvas.getContext("2d");

const cellPx = 10;
const colors = {
  background: "#0b0f10",
  blank: "#111719",
  text: "#e7ecef",
  live: "#68d391",
};

let api = null;
let lastTick = 0;
let loadError = null;

async function loadWasm() {
  let response = null;
  for (const url of wasmUrls) {
    response = await fetch(url);
    if (response.ok) break;
  }
  if (!response || !response.ok) {
    throw new Error("Could not load lifegame-webterm-browser.wasm");
  }

  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {});
  api = result.instance.exports;
}

function resizeCanvas() {
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.floor(rect.width * dpr));
  canvas.height = Math.max(1, Math.floor(rect.height * dpr));
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  const cols = Math.max(1, Math.floor(rect.width / cellPx));
  const rows = Math.max(1, Math.floor(rect.height / cellPx));
  let ok = 0;
  if (api.lifegame_surface_width() === 0) {
    ok = api.lifegame_init(cols, rows);
  } else {
    ok = api.lifegame_resize(cols, rows);
  }
  if (!ok) {
    loadError = `Could not initialize ${cols}x${rows} browser surface`;
  } else {
    loadError = null;
  }
  draw();
}

function draw() {
  if (!api) return;

  const rect = canvas.getBoundingClientRect();
  ctx.fillStyle = colors.background;
  ctx.fillRect(0, 0, rect.width, rect.height);
  if (loadError) {
    ctx.fillStyle = colors.text;
    ctx.font = "12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";
    ctx.textBaseline = "top";
    ctx.fillText(loadError, 12, 12);
    return;
  }

  const width = api.lifegame_surface_width();
  const height = api.lifegame_surface_height();
  ctx.font = "12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";
  ctx.textBaseline = "top";
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const index = y * width + x;
      const kind = api.lifegame_cell_kind_at(index);
      const px = x * cellPx;
      const py = y * cellPx;
      if (kind === 2) {
        ctx.fillStyle = colors.live;
        ctx.fillRect(px + 1, py + 1, cellPx - 2, cellPx - 2);
      } else if (kind === 1) {
        const code = api.lifegame_cell_char_at(index);
        ctx.fillStyle = colors.text;
        ctx.fillText(String.fromCharCode(code), px, py);
      } else {
        ctx.fillStyle = colors.blank;
        ctx.fillRect(px, py, cellPx, cellPx);
      }
    }
  }
}

function dispatchKey(event) {
  const keyMap = {
    ArrowLeft: "h",
    ArrowRight: "l",
    ArrowUp: "k",
    ArrowDown: "j",
    " ": " ",
  };
  const mapped = keyMap[event.key] || event.key;
  if (mapped.length !== 1) return;

  api.lifegame_dispatch_key(mapped.charCodeAt(0));
  draw();
  event.preventDefault();
}

function frame(now) {
  const interval = api.lifegame_speed_ms();
  if (!api.lifegame_is_paused() && now - lastTick >= interval) {
    api.lifegame_tick();
    lastTick = now;
    draw();
  }
  requestAnimationFrame(frame);
}

await loadWasm();
resizeCanvas();
window.addEventListener("resize", resizeCanvas);
window.addEventListener("keydown", dispatchKey);
requestAnimationFrame(frame);
