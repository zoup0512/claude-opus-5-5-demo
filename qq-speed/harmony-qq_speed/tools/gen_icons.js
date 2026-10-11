// 生成应用图标（程序化，无外部资源依赖）
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

function writePNG(file, W, H, pixelFn) {
  const raw = Buffer.alloc((W * 3 + 1) * H);
  let o = 0;
  for (let y = 0; y < H; y++) {
    raw[o++] = 0; // filter none
    for (let x = 0; x < W; x++) {
      const c = pixelFn(x, y, W, H);
      raw[o++] = c[0]; raw[o++] = c[1]; raw[o++] = c[2];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8bit RGB
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, png);
  console.log('wrote', file, png.length, 'bytes');
}

// 图标：斜切赛车旗风格 —— 深蓝底、青→橙速度楔形
function icon(x, y, W, H) {
  const fx = x / W - 0.5, fy = y / H - 0.5;
  const d = Math.abs(fy - fx * 0.55);
  const r = Math.hypot(fx, fy);
  let base = [13 + r * 26, 20 + r * 46, 48 + r * 70];
  if (d < 0.16) {
    const k = 1 - d / 0.16;
    base = [base[0] + (255 - base[0]) * k, base[1] + (150 - base[1]) * k, base[2] + (40 - base[2]) * k];
  } else if (d < 0.26) {
    const k = (d - 0.16) / 0.1;
    base = [base[0] + (39 - base[0]) * k, base[1] + (199 - base[1]) * k, base[2] + (255 - base[2]) * k];
  }
  return [Math.round(base[0]), Math.round(base[1]), Math.round(base[2])];
}

const root = path.resolve(__dirname, '..');
writePNG(path.join(root, 'AppScope/resources/base/media/app_icon.png'), 114, 114, icon);
writePNG(path.join(root, 'entry/src/main/resources/base/media/app_icon.png'), 114, 114, icon);
writePNG(path.join(root, 'entry/src/main/resources/base/media/start_icon.png'), 114, 114, icon);
