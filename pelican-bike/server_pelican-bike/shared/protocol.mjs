// 双端共享的协议定义（客户端经 esbuild 打包引用，服务端由 Node 直接 import，勿改成单端语法）
export const PROTO = 1;

// 客户端 → 服务器
export const C2S = {
  HELLO: 'hello',       // {name}
  CREATE: 'create',     // {dur} 对局时长(秒)
  JOIN: 'join',         // {code, resume?}
  QUICK: 'quick',       // {}
  READY: 'ready',       // {on}
  START: 'start',       // {} 房主
  STATE: 'state',       // {d,l,v,y,fl} 里程/横向/速度/跳高/标志位 20Hz
  CATCH: 'catch',       // {w,f} 波次id / 鱼序号
  TRICK: 'trick',       // {} 特技落地（+1，每波上限 1 次）
  SKILL: 'skill',       // {} 释放持有的技能
  EMOTE: 'emote',       // {k:'bell'|'honk'}
  PING: 'ping',         // {t}
  AGAIN: 'again',       // {} 再来一局
  LEAVE: 'leave',       // {}
};

// 服务器 → 客户端
export const S2C = {
  WELCOME: 'welcome',   // {id,proto}
  ROOM: 'room',         // {code,state,duration,host,you:{id,name},players:[{id,name,ready,connected}]}
  COUNTDOWN: 'countdown', // {end} 服务器时间戳(ms)
  MATCH: 'match',       // {seed,hour,dur} 开局参数
  WAVE: 'wave',         // {id,fs:[{i,z,dl,go}]}
  CAUGHT: 'caught',     // {by,w,f,val,ok}
  OPP: 'opp',           // {..对端 state 原样转发}
  SKILL: 'skillGot',    // {k} 金鱼掉落技能（仅发给自己）
  SKILLFX: 'skillFx',   // {by,k,tgt,until} 技能生效广播
  EMOTE: 'emote',       // {by,k}
  SCORE: 'score',       // {sc:{id:分},fish:{id:条数},gold:{id:条数}}
  OT: 'ot',             // {end} 进入加时赛
  END: 'end',           // {win:0|1|2(0=平),sc,stats:{id:{fish,gold,maxV,d,bonus}}}
  PONG: 'pong',         // {t}
  ERR: 'err',           // {msg}
  KICK: 'kick',         // {reason}
  OPP_GONE: 'oppGone',  // {} 对手断线
  OPP_BACK: 'oppBack',  // {} 对手重连
};

// state 标志位 fl：bit0 跳跃中 bit1 特技中 bit2 滑行(未踩踏)
export const FL_AIR = 1, FL_TRICK = 2, FL_COAST = 4;

// 技能
export const SKILLS = {
  HEADWIND: 'headwind', // 逆风：对手限速 -30%，3s
  SEAGULL: 'seagull',   // 海鸥：偷对手 2 分
  FOG: 'fog',           // 迷雾：对手视野起雾，2.5s
  BOOST: 'boost',       // 尾流：自己提速 +25%，3s
};
export const SKILL_INFO = {
  headwind: { name: '逆风', icon: '🌬️', dur: 3, self: false },
  seagull: { name: '海鸥偷鱼', icon: '🦅', dur: 0, self: false },
  fog: { name: '迷雾', icon: '🌫️', dur: 2.5, self: false },
  boost: { name: '尾流加速', icon: '💨', dur: 3, self: true },
};

// 对局参数
export const RULES = {
  WAVE_INTERVAL: [7, 9.5],   // 波次间隔秒
  WAVE_FISH: 5,              // 每波鱼数
  WAVE_LIVE: 14,             // 波次有效期(秒)
  GOLDEN_P: 0.12,            // 金鱼概率
  FISH_VAL: 1, GOLDEN_VAL: 5,
  TRICK_VAL: 1,
  DIST_BONUS: 3,             // 终场里程领先加成
  OT_SECONDS: 30,            // 加时赛时长
  RECONNECT_MS: 15000,       // 断线保留座位
  MAX_SPEED: 15.5,           // 与客户端物理一致
  SPEED_TOL: 1.15,
};
