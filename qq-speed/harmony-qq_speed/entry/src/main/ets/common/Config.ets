// 游戏静态配置：赛道布局 / 地图主题 / 车漆 / 模式（自 H5 版移植）

export class Layout {
  width: number = 24;
  points: number[][] = [];
}

export const LAYOUTS: Record<string, Layout> = (() => {
  const m: Record<string, Layout> = {};
  const mk = (width: number, pts: number[][]): Layout => {
    const l = new Layout();
    l.width = width;
    l.points = pts;
    return l;
  };
  m['city'] = mk(26, [
    [-300, -150, 0], [-140, -152, 0], [20, -150, 0], [120, -140, 0],
    [185, -95, 1], [205, -40, 5], [205, 0, 6], [205, 45, 5],
    [215, 110, 2], [270, 170, 0], [360, 190, 0], [410, 250, 0],
    [385, 330, 0], [300, 350, 0], [230, 310, 0], [150, 290, 0],
    [70, 330, 0], [-20, 330, 0], [-90, 290, 0], [-170, 290, 0],
    [-240, 240, 0], [-265, 160, 2], [-262, 70, 5], [-262, 0, 6],
    [-262, -60, 4], [-300, -95, 1], [-370, -110, 0], [-400, -160, 0],
    [-370, -190, 0],
  ]);
  m['aegean'] = mk(24, [
    [-250, -170, 0], [-60, -178, 0], [110, -168, 0], [215, -130, 1],
    [262, -60, 3], [255, 5, 5], [200, 32, 7], [110, 20, 8],
    [20, 12, 9], [-50, 40, 10], [-55, 95, 11], [10, 118, 12],
    [120, 115, 14], [230, 125, 16], [300, 180, 17], [290, 265, 18],
    [200, 310, 18], [80, 318, 17], [-60, 300, 15], [-180, 250, 12],
    [-275, 170, 9], [-330, 70, 6], [-345, -30, 3], [-325, -120, 1],
  ]);
  m['egypt'] = mk(26, [
    [0, -330, 0], [0, -200, 0], [4, -80, 1.5], [0, -10, 5],
    [0, 22, 6.2], [2, 58, 0.4], [20, 140, 0], [-30, 215, 0],
    [-130, 235, 0], [-215, 290, 0], [-190, 375, 0], [-70, 400, 0],
    [70, 380, 0], [190, 330, 0], [285, 250, 0], [300, 150, 0],
    [255, 80, 0], [300, 5, 0], [345, -70, 0], [320, -170, 0],
    [240, -250, 0], [160, -320, 0], [120, -410, 0], [40, -450, 0],
    [-20, -420, 0],
  ]);
  m['snow'] = mk(25, [
    [-200, -200, 0], [-40, -200, 0], [110, -190, 0], [200, -140, 0],
    [220, -60, 2], [150, 0, 7], [60, 60, 10], [-20, 120, 10],
    [-60, 200, 8], [-10, 280, 5], [90, 290, 2], [170, 230, 0],
    [165, 140, 0], [80, 70, 0], [0, 0, 0], [-80, -50, 0],
    [-170, -60, 0], [-270, -20, 0], [-340, -60, 0], [-350, -150, 0],
    [-300, -200, 0],
  ]);
  return m;
})();

export class SkyCfg {
  top: string = '#2f7fe0';
  horizon: string = '#cfeaff';
  bottom: string = '#8fb8d8';
  sun: number[] = [-0.45, 0.62, -0.55];
  sunColor: string = '#fff4dc';
  sunI: number = 2.6;
}

export class TrackTheme {
  road: string = 'asphalt';
  wall: string = 'city';
  curbA: string = '#e53935';
  curbB: string = '#ffffff';
  deckColor: number = 0xc7c3d6;
  checkerA: string = '#101010';
  checkerB: string = '#ffffff';
  boostColor: string = '#27c7ff';
  boostPads: number[][] = [];
  tunnels: number[][] = [];
  shoulderWidth: number = 0; // >0 表示铺路肩
  tunnelOuter: number = 0x8d8478;
}

export class WaterCfg {
  color: string = '#1f7fd1';
  deep: string = '#0b3f7a';
  y: number = -1.6;
  local: boolean = false; // true = 绿洲小水面
}

export class MapCfg {
  id: string = 'city';
  name: string = '';
  en: string = '';
  tag: string = '';
  desc: string = '';
  layout: string = 'city';
  sky: SkyCfg = new SkyCfg();
  hemiSky: string = '#d6ecff';
  hemiGround: string = '#6f8a5a';
  hemiI: number = 1.1;
  fogColor: string = '#cfe6fb';
  fogNear: number = 380;
  fogFar: number = 2300;
  ground: string = 'grass';
  water: WaterCfg | null = null;
  track: TrackTheme = new TrackTheme();
  mountainColor: number = 0x6f95b8;
  mountainCap: number = 0;
  mountainR0: number = 1600;
  mountainR1: number = 500;
  mountainH0: number = 140;
  mountainH1: number = 200;
  snowfall: boolean = false;
  bgm: number = 0;
  // 桥段判定（y > 阈值的采样点为高架）
  bridgeY: number = 999;
}

function mkMap(id: string, name: string, en: string, tag: string, desc: string, layout: string,
  sky: SkyCfg, hemiSky: string, hemiGround: string, hemiI: number,
  fog: string, fogNear: number, fogFar: number, ground: string, water: WaterCfg | null,
  track: TrackTheme, mColor: number, mCap: number, mR0: number, mR1: number, mH0: number, mH1: number,
  snowfall: boolean, bgm: number, bridgeY: number): MapCfg {
  const m = new MapCfg();
  m.id = id;
  m.name = name;
  m.en = en;
  m.tag = tag;
  m.desc = desc;
  m.layout = layout;
  m.sky = sky;
  m.hemiSky = hemiSky;
  m.hemiGround = hemiGround;
  m.hemiI = hemiI;
  m.fogColor = fog;
  m.fogNear = fogNear;
  m.fogFar = fogFar;
  m.ground = ground;
  m.water = water;
  m.track = track;
  m.mountainColor = mColor;
  m.mountainCap = mCap;
  m.mountainR0 = mR0;
  m.mountainR1 = mR1;
  m.mountainH0 = mH0;
  m.mountainH1 = mH1;
  m.snowfall = snowfall;
  m.bgm = bgm;
  m.bridgeY = bridgeY;
  return m;
}

function skyOf(top: string, hor: string, bot: string, sun: number[], sunColor: string, sunI: number): SkyCfg {
  const s = new SkyCfg();
  s.top = top;
  s.horizon = hor;
  s.bottom = bot;
  s.sun = sun;
  s.sunColor = sunColor;
  s.sunI = sunI;
  return s;
}

function trackOf(road: string, wall: string, curbA: string, curbB: string, deck: number,
  chA: string, chB: string, boost: string, pads: number[][], tunnels: number[][],
  shoulder: number, tunnelOuter: number): TrackTheme {
  const t = new TrackTheme();
  t.road = road;
  t.wall = wall;
  t.curbA = curbA;
  t.curbB = curbB;
  t.deckColor = deck;
  t.checkerA = chA;
  t.checkerB = chB;
  t.boostColor = boost;
  t.boostPads = pads;
  t.tunnels = tunnels;
  t.shoulderWidth = shoulder;
  t.tunnelOuter = tunnelOuter;
  return t;
}

function waterOf(color: string, deep: string, y: number, local: boolean): WaterCfg {
  const w = new WaterCfg();
  w.color = color;
  w.deep = deep;
  w.y = y;
  w.local = local;
  return w;
}

export const MAPS: MapCfg[] = [
  mkMap('city', '11城', 'CITY 11', '经典竞速 · 11 个弯道',
    '跨河塔桥、摩天楼群与蓝色霓虹加速带，节奏感极强的都市赛道。', 'city',
    skyOf('#2f7fe0', '#cfeaff', '#8fb8d8', [-0.45, 0.62, -0.55], '#fff4dc', 2.6),
    '#d6ecff', '#6f8a5a', 1.1, '#cfe6fb', 380, 2300, 'grass',
    waterOf('#1f7fd1', '#0b3f7a', -1.6, false),
    trackOf('asphalt', 'city', '#e53935', '#ffffff', 0xc7c3d6, '#101010', '#ffffff', '#27c7ff',
      [[-120, -151], [205, -8], [-262, 8], [-262, 8]], [], 7, 0x8d8478),
    0x6f95b8, 0, 1600, 500, 140, 200, false, 0, 1.5),
  mkMap('aegean', '情迷爱琴海', 'AEGEAN SEA', '山城爬坡 · 连续发卡弯',
    '白墙蓝顶的海岛小镇，石板路盘山而上，发卡弯考验连续漂移。', 'aegean',
    skyOf('#3a8ee6', '#e4f3ff', '#9cc6e6', [0.5, 0.55, -0.45], '#fff1d6', 2.7),
    '#e8f4ff', '#a39a7a', 1.15, '#dcefff', 420, 2400, 'aegean',
    waterOf('#1a8fd8', '#07477f', -1.0, false),
    trackOf('flagstone', 'aegean', '#2f7fd8', '#ffffff', 0xe9e4d8, '#1d4f9e', '#ffffff', '#ffd23a',
      [[-60, -178], [120, 115]], [[-296, 128], [-340, 10]], 5, 0xf2eee6),
    0x9c9a74, 0, 1500, 500, 140, 220, false, 1, 999),
  mkMap('egypt', '法老金字塔', 'PHARAOH', '沙漠飞跃 · 神殿隧道',
    '穿过法老神殿，冲上沙丘跳台飞跃，落地瞬间来一记落地喷！', 'egypt',
    skyOf('#3b86d8', '#fbe7c4', '#e9c99a', [0.35, 0.5, 0.6], '#fff0cf', 3.0),
    '#fff1d8', '#c49a5a', 1.05, '#f3dfbd', 420, 2500, 'sand',
    waterOf('#23a3b8', '#0d5a6a', -0.6, true),
    trackOf('sandstone', 'egypt', '#5b3f9e', '#f3e3b5', 0xd9b77a, '#5b3f9e', '#ffffff', '#ff9a1f',
      [[2, -60], [300, 20]], [[0, -250], [0, -150]], 0, 0xd6b274),
    0xd9ae72, 0, 1500, 600, 50, 90, false, 2, 999),
  mkMap('snow', '雪地大冒险', 'SNOW ADVENTURE', '8 字立交 · 冰雪隧道',
    '雪松林与冰雪隧道，8 字形立交桥上下穿梭，终点看台为你欢呼。', 'snow',
    skyOf('#3f86d6', '#e2f0ff', '#c9ddf2', [-0.3, 0.45, 0.7], '#ffffff', 2.4),
    '#eef6ff', '#9fb4cc', 1.25, '#e3eefb', 350, 2200, 'snow',
    null,
    trackOf('plate', 'snow', '#c62828', '#ffffff', 0x9fb0c8, '#101010', '#ffffff', '#39c5ff',
      [[-60, -200], [-20, 120]], [[-110, -52], [-235, -40]], 0, 0xdfeaf6),
    0x6f8fb8, 0xf2f7ff, 1400, 500, 240, 300, true, 3, 5.5),
];

export class ModeCfg {
  id: string = 'speed';
  name: string = '';
  desc: string = '';
}

export const MODES: ModeCfg[] = [
  (() => {
    const m = new ModeCfg();
    m.id = 'speed';
    m.name = '竞速模式';
    m.desc = '漂移集气、小喷、双喷，纯靠车技';
    return m;
  })(),
  (() => {
    const m = new ModeCfg();
    m.id = 'item';
    m.name = '道具模式';
    m.desc = '导弹、香蕉皮、天使、磁铁、氮气';
    return m;
  })(),
];

export class DiffCfg {
  id: number = 0;
  name: string = '';
  skill: number[] = [0, 0];
  rubber: number[] = [0, 0];
}

export const DIFFS: DiffCfg[] = [
  (() => {
    const d = new DiffCfg();
    d.id = 0;
    d.name = '新手';
    d.skill = [0.55, 0.75];
    d.rubber = [0.88, 1.03];
    return d;
  })(),
  (() => {
    const d = new DiffCfg();
    d.id = 1;
    d.name = '熟练';
    d.skill = [0.85, 1.05];
    d.rubber = [0.93, 1.06];
    return d;
  })(),
  (() => {
    const d = new DiffCfg();
    d.id = 2;
    d.name = '车神';
    d.skill = [1.2, 1.38];
    d.rubber = [0.97, 1.1];
    return d;
  })(),
];

export class QualCfg {
  id: string = 'mid';
  name: string = '';
  scale: number = 1; // 画布分辨率缩放
  view: number = 1;  // 可视距离系数
}

export const QUALITY: QualCfg[] = [
  (() => {
    const q = new QualCfg();
    q.id = 'low';
    q.name = '流畅';
    q.scale = 0.7;
    q.view = 0.62;
    return q;
  })(),
  (() => {
    const q = new QualCfg();
    q.id = 'mid';
    q.name = '均衡';
    q.scale = 0.9;
    q.view = 0.85;
    return q;
  })(),
  (() => {
    const q = new QualCfg();
    q.id = 'high';
    q.name = '极致';
    q.scale = 1.0;
    q.view = 1.0;
    return q;
  })(),
];

export const LAPS: number[] = [1, 2, 3, 5];

export class Skin {
  id: string = '';
  name: string = '';
  body: number = 0xe0262b;
  accent: number = 0xffc93a;
  glow: number = 0xff5a1f;
  rim: number = 0xd9d9d9;
}

function skinOf(id: string, name: string, body: number, accent: number, glow: number, rim: number): Skin {
  const s = new Skin();
  s.id = id;
  s.name = name;
  s.body = body;
  s.accent = accent;
  s.glow = glow;
  s.rim = rim;
  return s;
}

export const CAR_SKINS: Skin[] = [
  skinOf('red', '烈焰战神', 0xe0262b, 0xffc93a, 0xff5a1f, 0xd9d9d9),
  skinOf('blue', '冰蓝幻影', 0x1f6ff2, 0x6ff3ff, 0x27c7ff, 0xe6f2ff),
  skinOf('purple', '紫电魅影', 0x7b3df0, 0xff6fd8, 0xc26bff, 0xf0e0ff),
  skinOf('yellow', '黄金闪电', 0xffc21a, 0x1b1b1b, 0xffe066, 0x2b2b2b),
  skinOf('white', '白鲸号', 0xf3f5f8, 0x2a7bff, 0x5ab0ff, 0x9aa7b8),
  skinOf('pink', '粉红甜心', 0xff7eb6, 0xffffff, 0xff9ed0, 0xffffff),
  skinOf('green', '翡翠之星', 0x19b86a, 0xe8ff5a, 0x6dff9e, 0xe8ffe8),
  skinOf('black', '暗夜猎手', 0x1b1d22, 0xff2d55, 0xff2d55, 0x707782),
];

export const AI_NAMES: string[] = ['小橘子', '秋名山车神', '漂移少女', '氮气小王子', '风之子', '夜の车神', '闪电旋风', '小飞侠'];

export class ItemInfo {
  icon: string = '';
  name: string = '';
}

export const ITEM_INFO: Record<string, ItemInfo> = {
  'nitro': { icon: '🔥', name: '氮气' },
  'missile': { icon: '🚀', name: '导弹' },
  'banana': { icon: '🍌', name: '香蕉皮' },
  'shield': { icon: '😇', name: '天使' },
  'magnet': { icon: '🧲', name: '磁铁' },
};

export function mapById(id: string): MapCfg {
  for (const m of MAPS) {
    if (m.id === id) {
      return m;
    }
  }
  return MAPS[0];
}
