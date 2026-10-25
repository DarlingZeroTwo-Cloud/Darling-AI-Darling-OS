/**
 * Darling AI Cloud API — Cloudflare Worker 单文件实现
 * 零部署：wrangler deploy 即可上线
 *
 * 功能：
 *  - 账号：注册/登录/刷新/登出（JWT，永久登录）、安全问题找回密码
 *  - 模型：对外模型列表（品牌名 02，文本+图片合并）
 *  - 对话：SSE 流式转发 Agnes /chat/completions（上游 429 自动重试）
 *  - 图片：Agnes /images/generations
 *  - 额度：不限制（用户决定删除 5 小时制），仅记录用量日志
 *  - 配置云同步：GET/PUT /api/config（模型/个性化/提示词，不含对话）
 *  - 管理后台：/admin 网页 + /api/admin/*（公告/封禁/用量/上游配置）
 */

// ==================== 常量 ====================
const WINDOW_MS = 5 * 3600 * 1000;          // 用量统计窗口（仅记录，不限制额度）
const ACCESS_TTL = 24 * 3600;                // access 24h
const REFRESH_TTL = 365 * 24 * 3600 * 100;   // refresh 100 年（永久登录）
const MODEL_SLUG = '02';                     // 对外模型品牌名

// ==================== 工具 ====================

function b64url(buf) {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u;
}

async function sha256(buf) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', buf));
}

// PBKDF2 密码哈希（Web Crypto，16 字节盐，10 万轮）
async function pbkdf2(password, saltHex, iter = 100000) {
  const salt = b64urlDecode(saltHex);
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: iter, hash: 'SHA-256' },
    key, 256);
  return b64url(bits);
}
function randomHex(bytes = 16) {
  const u = new Uint8Array(bytes);
  crypto.getRandomValues(u);
  return b64url(u);
}

async function hashPassword(pw) {
  const salt = randomHex(16);
  const h = await pbkdf2(pw, salt);
  return { salt, hash: h };
}

// JWT（HMAC-SHA256）
async function signJwt(payload, secret, ttl) {
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const now = Math.floor(Date.now() / 1000);
  const body = b64url(new TextEncoder().encode(JSON.stringify({ ...payload, iat: now, exp: now + ttl })));
  const sig = b64url(await sha256(new TextEncoder().encode(`${header}.${body}.${secret}`)));
  return `${header}.${body}.${sig}`;
}
async function verifyJwt(token, secret) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  const expect = b64url(await sha256(new TextEncoder().encode(`${header}.${body}.${secret}`)));
  if (expect !== sig) return null;
  try {
    const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(body)));
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch { return null; }
}

// JSON 响应
function json(status, data, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, Authorization', 'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS', ...extraHeaders },
  });
}

async function readJson(req) {
  try { return await req.json(); } catch { return {}; }
}

// 通过 Authorization 拿当前用户（access token）
async function authUser(req, env) {
  const h = req.headers.get('Authorization') || '';
  const token = h.replace(/^Bearer\s+/i, '');
  if (!token) return null;
  const payload = await verifyJwt(token, env.JWT_SECRET);
  if (!payload || !payload.sub) return null;
  const u = await env.DB.prepare('SELECT id, email, role, banned FROM users WHERE id = ?').bind(payload.sub).first();
  if (!u || u.banned) return null;
  return u;
}

// API Key 鉴权：Bearer <api_key> 直接映射到用户（OpenAI 兼容，给官网/外部调用用）
async function authApiKey(req, env) {
  const h = req.headers.get('Authorization') || '';
  const token = h.replace(/^Bearer\s+/i, '');
  if (!token) return null;
  if (await verifyJwt(token, env.JWT_SECRET)) {
    return authUser(req, env);
  }
  // 不是 JWT，尝试当 API Key 查
  const hash = await sha256Hex(token);
  const row = await env.DB.prepare('SELECT user_id FROM api_keys WHERE key_hash = ?').bind(hash).first();
  if (!row) return null;
  const u = await env.DB.prepare('SELECT id, email, role, banned FROM users WHERE id = ?').bind(row.user_id).first();
  if (!u || u.banned) return null;
  return u;
}

async function sha256Hex(str) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

function genApiKey() {
  // 形如 dl-<32位随机hex>，前缀 dl- 用于识别，后 32 位作为完整 key 存储 hash
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const hex = [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
  return { key: `dl-${hex}`, prefix: `dl-${hex.slice(0, 8)}` };
}

// ==================== 额度 ====================

async function getQuota(db, userId, now = Date.now()) {
  let row = await db.prepare('SELECT window_start, text_tokens_used, images_used FROM quota_windows WHERE user_id = ?').bind(userId).first();
  if (!row || (row.window_start + WINDOW_MS) < now) {
    const start = now - (now % WINDOW_MS); // 对齐窗口
    await db.prepare('INSERT INTO quota_windows(user_id, window_start, text_tokens_used, images_used) VALUES(?,?,0,0) ON CONFLICT(user_id) DO UPDATE SET window_start=excluded.window_start, text_tokens_used=0, images_used=0').bind(userId, start).run();
    row = { window_start: start, text_tokens_used: 0, images_used: 0 };
  }
  return {
    window_start: row.window_start,
    window_end: row.window_start + WINDOW_MS,
    used: { text_tokens: row.text_tokens_used, images: row.images_used },
    // 不限制额度（用户决定删除 5 小时制）
    limit: { text_tokens: null, images: null },
  };
}

async function consumeText(db, userId, tokens) {
  // 不限制额度，仅记录日志
  await db.prepare('INSERT INTO usage_log(user_id, kind, amount, created_at) VALUES(?,?,?,?)').bind(userId, 'text', tokens||1, Math.floor(Date.now()/1000)).run();
  return true;
}

async function consumeImage(db, userId) {
  // 不限制额度，仅记录日志
  await db.prepare('INSERT INTO usage_log(user_id, kind, amount, created_at) VALUES(?,?,?,?)').bind(userId, 'image', 1, Math.floor(Date.now()/1000)).run();
  return true;
}

// ==================== 上游节流（Agnes 限流：约 10 次/分/IP，429 后约 30s 冷却） ====================
const UPSTREAM_INTERVAL_MS = 10000;  // 上游请求最小间隔（≈6 次/分，留足余量）
const UPSTREAM_MAX_WAIT_MS = 12000;  // 排队最长等待（避免撞 Workers 免费 30s 请求上限）
const UPSTREAM_COOLDOWN_MS = 90000;  // 429 冷却时长（Agnes 恢复窗口 >30s，取 90s 覆盖）

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function ensureGate(db) {
  await db.prepare('INSERT OR IGNORE INTO upstream_gate(id, last_ts, cooldown_until) VALUES(1, 0, 0)').run();
}

/** 原子门控：串行化上游请求并把频率压进限流内。冷却中或排队超时返回 false（快速失败，不占长墙钟）。 */
async function acquireUpstream(db) {
  await ensureGate(db);
  const t0 = Date.now();
  for (;;) {
    const now = Date.now();
    const g = await db.prepare('SELECT last_ts, cooldown_until FROM upstream_gate WHERE id = 1').first();
    if (g && g.cooldown_until > now) return { ok: false, reason: 'cooldown' };   // 冷却中：快速失败，让客户端延后重试
    const r = await db.prepare('UPDATE upstream_gate SET last_ts = ? WHERE id = 1 AND last_ts <= ?').bind(now, now - UPSTREAM_INTERVAL_MS).run();
    if (r.meta && r.meta.changes > 0) return { ok: true };
    if (Date.now() - t0 > UPSTREAM_MAX_WAIT_MS) return { ok: false, reason: 'timeout' };
    await sleep(600);
  }
}

/** 标记上游冷却（429 时调用），让所有请求在冷却期内快速失败而非长时间等待。 */
async function markUpstreamCooldown(db) {
  await ensureGate(db);
  await db.prepare('UPDATE upstream_gate SET cooldown_until = ? WHERE id = 1').bind(Date.now() + UPSTREAM_COOLDOWN_MS).run();
}

// ==================== 路由 ====================

async function handle(req, env, ctx) {
  const url = new URL(req.url);
  const path = url.pathname;
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
        'Access-Control-Max-Age': '86400',
      },
    });
  }

  // ---- 管理后台网页 ----
  if (path === '/admin' || path === '/admin/') {
    return new Response(adminHtml, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
  }

  // ---- 公开 ----
  if (path === '/' || path === '' || path === '/v1' || path === '/v1/') return json(200, { ok: true, msg: 'darling-ai-cloud alive', ts: Date.now() });
  if (path === '/api/health') return json(200, { ok: true, ts: Date.now() });

  if (path === '/api/auth/register' && req.method === 'POST') {
    const b = await readJson(req);
    const email = (b.email || '').toString().trim().toLowerCase();
    const pw = (b.password || '').toString();
    const sq = (b.security_q || '').toString().trim();
    const sa = (b.security_a || '').toString().trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: '邮箱格式不正确' });
    if (pw.length < 6) return json(400, { error: '密码至少 6 位' });
    if (!sq || !sa) return json(400, { error: '请设置安全问题（找回密码用）' });
    const exists = await env.DB.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();
    if (exists) return json(409, { error: '该邮箱已注册' });
    const { salt, hash } = await hashPassword(pw);
    const aHash = await pbkdf2(sa.toLowerCase(), salt);
    const created = Math.floor(Date.now() / 1000);
    const r = await env.DB.prepare('INSERT INTO users(email, password_hash, salt, security_q, security_a_hash, role, created_at) VALUES(?,?,?,?,?,\'user\',?)')
      .bind(email, hash, salt, sq, aHash, created).run();
    const id = r.meta.last_row_id;
    const access = await signJwt({ sub: id, email, role: 'user' }, env.JWT_SECRET, ACCESS_TTL);
    const refresh = await signJwt({ sub: id, typ: 'refresh' }, env.JWT_SECRET, REFRESH_TTL);
    return json(200, { ok: true, access, refresh, email, role: 'user' });
  }

  if (path === '/api/auth/login' && req.method === 'POST') {
    const b = await readJson(req);
    const email = (b.email || '').toString().trim().toLowerCase();
    const pw = (b.password || '').toString();
    const u = await env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
    if (!u) return json(401, { error: '邮箱或密码错误' });
    if (u.banned) return json(403, { error: '账号已被封禁' });
    const h = await pbkdf2(pw, u.salt);
    if (h !== u.password_hash) return json(401, { error: '邮箱或密码错误' });
    const access = await signJwt({ sub: u.id, email: u.email, role: u.role }, env.JWT_SECRET, ACCESS_TTL);
    const refresh = await signJwt({ sub: u.id, typ: 'refresh' }, env.JWT_SECRET, REFRESH_TTL);
    return json(200, { ok: true, access, refresh, email: u.email, role: u.role });
  }

  if (path === '/api/auth/refresh' && req.method === 'POST') {
    const b = await readJson(req);
    const token = (b.refresh || '').toString();
    const payload = await verifyJwt(token, env.JWT_SECRET);
    if (!payload || payload.typ !== 'refresh' || !payload.sub) return json(401, { error: '登录已过期，请重新登录' });
    const u = await env.DB.prepare('SELECT id, email, role, banned FROM users WHERE id = ?').bind(payload.sub).first();
    if (!u || u.banned) return json(401, { error: '账号不可用' });
    const access = await signJwt({ sub: u.id, email: u.email, role: u.role }, env.JWT_SECRET, ACCESS_TTL);
    const refresh = await signJwt({ sub: u.id, typ: 'refresh' }, env.JWT_SECRET, REFRESH_TTL);
    return json(200, { ok: true, access, refresh, email: u.email, role: u.role });
  }

  // 忘记密码：第一步拿安全问题
  if (path === '/api/auth/forgot' && req.method === 'POST') {
    const b = await readJson(req);
    const email = (b.email || '').toString().trim().toLowerCase();
    const u = await env.DB.prepare('SELECT id, security_q FROM users WHERE email = ?').bind(email).first();
    if (!u) return json(404, { error: '邮箱未注册' });
    return json(200, { ok: true, security_q: u.security_q });
  }

  // 忘记密码：第二步答对安全问题后重置
  if (path === '/api/auth/reset' && req.method === 'POST') {
    const b = await readJson(req);
    const email = (b.email || '').toString().trim().toLowerCase();
    const sa = (b.security_a || '').toString().trim().toLowerCase();
    const npw = (b.new_password || '').toString();
    const u = await env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
    if (!u) return json(404, { error: '邮箱未注册' });
    if (npw.length < 6) return json(400, { error: '新密码至少 6 位' });
    const h = await pbkdf2(sa, u.salt);
    if (h !== u.security_a_hash) return json(403, { error: '安全问题回答错误' });
    const { salt: ns, hash: nh } = await hashPassword(npw);
    await env.DB.prepare('UPDATE users SET password_hash=?, salt=? WHERE id=?').bind(nh, ns, u.id).run();
    return json(200, { ok: true, message: '密码已重置，请用新密码登录' });
  }

  // ---- 需要登录 ----
  const user = await authUser(req, env);
  // 公开端点不需要登录（/v1 系列支持 API Key，其余在下面单独校验）
  const protectedPaths = ['/api/me', '/api/models', '/api/chat', '/api/images', '/api/config', '/api/announcements', '/api/apikeys', '/api/usage', '/api/admin/stats', '/api/admin/users', '/api/admin/ban', '/api/admin/unban', '/api/admin/models', '/api/admin/upstream-key', '/api/admin/announcement', '/api/admin/delete-announcement'];
  // 兼容第三方 App：无论 base 填到域名还是 /v1，裸路径和 /v1 路径都有效
  const isV1 = ['/v1/models', '/v1/models/', '/models', '/models/', '/v1/chat/completions', '/v1/chat/completions/', '/chat/completions', '/chat/completions/'].includes(path);
  if (!isV1 && protectedPaths.includes(path)) {
    if (!user) return json(401, { error: '未登录' });
  }
  // /v1 系列：允许 JWT 或 API Key
  let v1User = user;
  if (isV1) {
    v1User = await authApiKey(req, env);
    if (!v1User) return json(401, { error: '未登录或 API Key 无效' });
  }

  if (path === '/api/me' && req.method === 'GET') {
    const quota = await getQuota(env.DB, user.id);
    return json(200, { id: user.id, email: user.email, role: user.role, quota });
  }

  // ---- API Key 管理（官网/控制台用） ----
  if (path === '/api/apikeys' && req.method === 'GET') {
    const rows = await env.DB.prepare('SELECT id, name, prefix, created_at FROM api_keys WHERE user_id = ? ORDER BY id DESC').bind(user.id).all();
    return json(200, { keys: rows.results });
  }
  if (path === '/api/apikeys' && req.method === 'POST') {
    const b = await readJson(req);
    const name = (b.name || 'default').toString().trim().slice(0, 50) || 'default';
    const { key, prefix } = genApiKey();
    const hash = await sha256Hex(key);
    const created = Math.floor(Date.now() / 1000);
    const r = await env.DB.prepare('INSERT INTO api_keys(user_id, name, key_hash, prefix, created_at) VALUES(?,?,?,?,?)').bind(user.id, name, hash, prefix, created).run();
    return json(200, { ok: true, id: r.meta.last_row_id, name, prefix, key, created_at: created, note: '完整 key 仅此一次显示，请立即保存' });
  }
  if (path === '/api/apikeys' && req.method === 'DELETE') {
    const id = parseInt(url.searchParams.get('id') || '0', 10);
    const r = await env.DB.prepare('DELETE FROM api_keys WHERE id = ? AND user_id = ?').bind(id, user.id).run();
    if (r.meta.changes === 0) return json(404, { error: '未找到该 API Key' });
    return json(200, { ok: true, deleted: id });
  }

  // 用量日志（官网展示）
  if (path === '/api/usage' && req.method === 'GET') {
    const days = parseInt(url.searchParams.get('days') || '7', 10);
    const since = Math.floor(Date.now() / 1000) - days * 86400;
    const rows = await env.DB.prepare('SELECT kind, SUM(amount) AS total, COUNT(*) AS n FROM usage_log WHERE user_id = ? AND created_at >= ? GROUP BY kind').bind(user.id, since).all();
    return json(200, { days, usage: rows.results });
  }

  // 对外模型列表（登录可见）；模型表极少变更，用 Cache API 缓存 60s 提速
  if (path === '/api/models' && req.method === 'GET') {
    const cacheUrl = `https://api.darling02.de5.net/_cache/models-v1-${user.id}`;
    const cache = caches.default;
    const cached = await cache.match(cacheUrl);
    if (cached) {
      return new Response(cached.body, { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
    }
    const ms = await env.DB.prepare('SELECT slug, name, description, type FROM models WHERE enabled = 1 ORDER BY sort').all();
    const payload = { models: ms.results.map(m => ({ id: m.slug, name: m.name, description: m.description, type: m.type })) };
    ctx.waitUntil(cache.put(cacheUrl, new Response(JSON.stringify(payload), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'max-age=60' } })));
    return json(200, payload);
  }

  // 公告
  if (path === '/api/announcements' && req.method === 'GET') {
    const a = await env.DB.prepare('SELECT title, content, created_at FROM announcements ORDER BY created_at DESC LIMIT 5').all();
    return json(200, { announcements: a.results });
  }

  // ---- 对话（SSE 流式） ----
  if (path === '/api/chat' && req.method === 'POST') {
    const b = await readJson(req);
    const modelSlug = (b.model_id || '').toString();
    const m = await env.DB.prepare('SELECT * FROM models WHERE slug = ? AND enabled = 1').bind(modelSlug).first();
    if (!m) return json(404, { error: '模型不存在' });
    if (m.type !== 'text' && m.type !== 'hybrid') return json(400, { error: '该模型不支持文本对话' });
    const prov = await env.DB.prepare('SELECT * FROM providers WHERE id = ?').bind(m.provider_id).first();
    if (!prov || !prov.api_key) return json(500, { error: '上游未配置' });
    const messages = Array.isArray(b.messages) ? b.messages : [];
    if (m.system_prompt) {
      messages.unshift({ role: 'system', content: m.system_prompt });
    }
    const upstream = `${(prov.base_url || '').replace(/\/+$/, '')}/chat/completions`;
    const body = { model: m.upstream_model, messages, stream: true };
    // 上游节流门控（Agnes 限流：~10 次/分，429 冷却 30s）
    const gate = await acquireUpstream(env.DB);
    if (!gate.ok) {
      if (gate.reason === 'cooldown') return json(429, { error: '上游限流中，请稍后再试' }, { 'Retry-After': '90' });
      return json(503, { error: '上游繁忙，请稍后再试' });
    }
    let resp = await fetch(upstream, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${prov.api_key}` },
      body: JSON.stringify(body),
    });
    // 上游 429：标记冷却（后续请求快速 503），立即返回 429 让客户端稍后重试
    if (resp.status === 429) {
      await markUpstreamCooldown(env.DB);
      return json(429, { error: '上游限流中，请稍后再试' }, { 'Retry-After': '90' });
    }
    if (!resp.ok || !resp.body) {
      return json(502, { error: `上游请求失败 (${resp.status})` });
    }
    // 转发 SSE
    const encoder = new TextEncoder();
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    let consumed = 0;
    const stream = new ReadableStream({
      async start(controller) {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            buf += decoder.decode(value, { stream: true });
            let idx;
            while ((idx = buf.indexOf('\n')) >= 0) {
              const line = buf.slice(0, idx).trim();
              buf = buf.slice(idx + 1);
              if (line.startsWith('data:')) {
                const data = line.slice(5).trim();
                if (data === '[DONE]') continue;
                try {
                  const j = JSON.parse(data);
                  const delta = j.choices?.[0]?.delta?.content;
                  if (delta) {
                    consumed += delta.length;
                    controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'delta', content: delta })}\n\n`));
                  }
                  const usage = j.usage;
                  if (usage?.total_tokens) consumed = usage.total_tokens;
                } catch {}
              }
            }
          }
          // 记录用量（不限制，仅日志）
          if (consumed > 0) await consumeText(env.DB, user.id, Math.max(consumed, 1));
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'done', usage: { total_tokens: Math.max(consumed, 1) } })}\n\n`));
          controller.close();
        } catch (e) {
          controller.error(e);
        }
      },
    });
    return new Response(stream, {
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
    });
  }

  // ---- OpenAI 兼容端点（给第三方 App/官网 API Key 用；裸路径与 /v1 均兼容） ----
  if (['/v1/models', '/v1/models/', '/models', '/models/'].includes(path)) {
    if (!v1User) return json(401, { error: '未登录或 API Key 无效' });
    const ms = await env.DB.prepare('SELECT slug, name, type FROM models WHERE enabled = 1 ORDER BY sort').all();
    return json(200, { object: 'list', data: ms.results.map(m => ({ id: m.slug, object: 'model', owned_by: 'darling' })) });
  }
  if (['/v1/chat/completions', '/v1/chat/completions/', '/chat/completions', '/chat/completions/'].includes(path)) {
    if (!v1User) return json(401, { error: '未登录或 API Key 无效' });
    const b = await readJson(req);
    // 容错：不管桥接送什么 model，都用 02
    const m = await env.DB.prepare('SELECT * FROM models WHERE slug = ? AND enabled = 1').bind('02').first();
    if (!m) return json(404, { error: '模型不存在' });
    const prov = await env.DB.prepare('SELECT * FROM providers WHERE id = ?').bind(m.provider_id).first();
    if (!prov || !prov.api_key) return json(500, { error: '上游未配置' });
    const upstream = `${(prov.base_url || '').replace(/\/+$/, '')}/chat/completions`;
    const msgs = Array.isArray(b.messages) ? b.messages.slice() : [];
    // 注入 02 的系统提示词（用户让 AI 改名时以用户对话为准，但首次自我介绍必须是 02）
    const sysPrompt = m.system_prompt || '你叫 02，由 DARLING-AI 开发。是一个通用 AI 助手。如果用户在对话中让你改名，从那时起用用户给的名字。';
    msgs.unshift({ role: 'system', content: sysPrompt });
    const upstreamBody = {
      model: m.upstream_model,
      messages: msgs,
      stream: b.stream || false,
    };
    // 上游节流门控（Agnes 限流：~10 次/分，429 冷却 30s）
    const gate = await acquireUpstream(env.DB);
    if (!gate.ok) {
      if (gate.reason === 'cooldown') return json(429, { error: '上游限流中，请稍后再试' }, { 'Retry-After': '90' });
      return json(503, { error: '上游繁忙，请稍后再试' });
    }
    // 上游 429 限流时等待冷却后自动重试一次
    let resp = await fetch(upstream, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${prov.api_key}` },
      body: JSON.stringify(upstreamBody),
    });
    if (resp.status === 429) {
      await markUpstreamCooldown(env.DB);
      return json(429, { error: '上游限流中，请稍后再试' }, { 'Retry-After': '90' });
    }
    const body = await resp.text();
    const ct = resp.status === 200 ? 'text/event-stream; charset=utf-8' : 'application/json; charset=utf-8';
    // 记录一次调用（API Key / 登录用户共用）
    try { await consumeText(env.DB, v1User.id, 1); } catch {}
    return new Response(body, { status: resp.status, headers: { 'Content-Type': ct, 'Access-Control-Allow-Origin': '*' } });
  }

  // ---- 图片生成 ----
  if (path === '/api/images' && req.method === 'POST') {
    const b = await readJson(req);
    const modelSlug = (b.model_id || '').toString();
    const m = await env.DB.prepare('SELECT * FROM models WHERE slug = ? AND enabled = 1').bind(modelSlug).first();
    if (!m) return json(404, { error: '模型不存在' });
    if (m.type !== 'image' && m.type !== 'hybrid') return json(400, { error: '该模型不支持图片生成' });
    const prov = await env.DB.prepare('SELECT * FROM providers WHERE id = ?').bind(m.provider_id).first();
    if (!prov || !prov.api_key) return json(500, { error: '上游未配置' });
    await consumeImage(env.DB, user.id); // 仅记录用量日志，不限制
    const prompt = (b.prompt || '').toString();
    const upstream = `${(prov.base_url || '').replace(/\/+$/, '')}/images/generations`;
    try {
      // 上游节流门控（图片与文本共用同一上游 key，同一限流窗口）
      if (!(await acquireUpstream(env.DB))) {
        return json(503, { error: '上游繁忙，请稍后再试' });
      }
      const doFetch = () => fetch(upstream, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${prov.api_key}` },
        body: JSON.stringify({ model: m.upstream_image_model || m.upstream_model, prompt, n: 1 }),
      });
      let resp = await doFetch();
      if (resp.status === 429) {
        await markUpstreamCooldown(env.DB);
        return json(429, { error: '上游限流中，请稍后再试' }, { 'Retry-After': '90' });
      }
      const data = await resp.json();
      if (!resp.ok) return json(502, { error: (data.error?.message || `上游失败 (${resp.status})`) });
      const img = data.data?.[0];
      return json(200, {
        b64_json: img?.b64_json || null,
        url: img?.url || null,
        revised_prompt: img?.revised_prompt || null,
      });
    } catch (e) {
      return json(502, { error: `上游失败: ${e}` });
    }
  }

  // ---- 配置云同步（不含对话） ----
  if (path === '/api/config' && req.method === 'GET') {
    const u = await env.DB.prepare('SELECT config FROM users WHERE id = ?').bind(user.id).first();
    let cfg = {};
    try { cfg = JSON.parse(u.config || '{}'); } catch {}
    return json(200, { config: cfg });
  }
  if (path === '/api/config' && req.method === 'PUT') {
    const b = await readJson(req);
    const incoming = (b.config && typeof b.config === 'object') ? b.config : {};
    const u = await env.DB.prepare('SELECT config FROM users WHERE id = ?').bind(user.id).first();
    let cur = {};
    try { cur = JSON.parse(u.config || '{}'); } catch {}
    const merged = { ...cur, ...incoming };
    await env.DB.prepare('UPDATE users SET config = ? WHERE id = ?').bind(JSON.stringify(merged), user.id).run();
    return json(200, { ok: true, config: merged });
  }

  // ==================== 管理 API ====================
  if (path.startsWith('/api/admin')) {
    if (user.role !== 'admin') return json(403, { error: '需要管理员权限' });
  }
  if (path === '/api/admin/models' && req.method === 'GET') {
    const ms = await env.DB.prepare('SELECT m.*, p.name AS provider_name FROM models m LEFT JOIN providers p ON p.id = m.provider_id ORDER BY m.sort').all();
    return json(200, { models: ms.results });
  }
  if (path === '/api/admin/models' && req.method === 'POST') {
    const b = await readJson(req);
    const name = (b.name || '').toString().trim();
    if (!name) return json(400, { error: '名称必填' });
    const prov = await env.DB.prepare('SELECT * FROM providers WHERE id = ?').bind(Number(b.provider_id) || 0).first();
    if (!prov) return json(400, { error: '请先添加上游提供商' });
    const slug = (b.slug || '').toString().trim() || MODEL_SLUG;
    const r = await env.DB.prepare('INSERT INTO models(slug, name, description, provider_id, upstream_model, upstream_image_model, type, system_prompt, enabled, sort) VALUES(?,?,?,?,?,?,?,?,1,?)')
      .bind(slug, name, (b.description || '').toString(), prov.id, (b.upstream_model || '').toString(), (b.upstream_image_model || '').toString(), (b.type || 'hybrid').toString(), (b.system_prompt || '').toString(), Number(b.sort) || 0).run();
    return json(200, { ok: true, id: r.meta.last_row_id });
  }
  if (path === '/api/admin/providers' && req.method === 'GET') {
    const ps = await env.DB.prepare('SELECT id, name, base_url, type, created_at FROM providers ORDER BY id DESC').all();
    return json(200, { providers: ps.results });
  }
  if (path === '/api/admin/providers' && req.method === 'POST') {
    const b = await readJson(req);
    const name = (b.name || '').toString().trim();
    const base = (b.base_url || '').toString().trim();
    if (!name || !base) return json(400, { error: '名称和 Base URL 必填' });
    const r = await env.DB.prepare('INSERT INTO providers(name, base_url, api_key, type, created_at) VALUES(?,?,?,?,?)')
      .bind(name, base.replace(/\/+$/, ''), (b.api_key || '').toString(), (b.type || 'hybrid').toString(), Math.floor(Date.now()/1000)).run();
    return json(200, { ok: true, id: r.meta.last_row_id });
  }
  if (path === '/api/admin/providers/test' && req.method === 'POST') {
    const b = await readJson(req);
    const base = (b.base_url || '').toString().replace(/\/+$/, '');
    const key = (b.api_key || '').toString();
    try {
      const resp = await fetch(`${base}/models`, { headers: { 'Authorization': `Bearer ${key}` } });
      const data = await resp.json();
      const ids = (data.data || []).map(m => m.id);
      return json(200, { ok: true, models: ids });
    } catch (e) {
      return json(502, { error: `连接失败: ${e}` });
    }
  }
  if (path === '/api/admin/users' && req.method === 'GET') {
    const us = await env.DB.prepare('SELECT id, email, role, banned, created_at FROM users ORDER BY id DESC LIMIT 100').all();
    return json(200, { users: us.results });
  }
  if (path === '/api/admin/ban' && req.method === 'POST') {
    const b = await readJson(req);
    await env.DB.prepare('UPDATE users SET banned = 1 WHERE id = ?').bind(Number(b.user_id)).run();
    return json(200, { ok: true });
  }
  if (path === '/api/admin/unban' && req.method === 'POST') {
    const b = await readJson(req);
    await env.DB.prepare('UPDATE users SET banned = 0 WHERE id = ?').bind(Number(b.user_id)).run();
    return json(200, { ok: true });
  }
  if (path === '/api/admin/announcement' && req.method === 'POST') {
    const b = await readJson(req);
    await env.DB.prepare('INSERT INTO announcements(title, content, created_at) VALUES(?,?,?)')
      .bind((b.title || '').toString(), (b.content || '').toString(), Math.floor(Date.now()/1000)).run();
    return json(200, { ok: true });
  }
  if (path === '/api/admin/delete-announcement' && req.method === 'POST') {
    const b = await readJson(req);
    await env.DB.prepare('DELETE FROM announcements WHERE id = ?').bind(Number(b.id)).run();
    return json(200, { ok: true });
  }
  if (path === '/api/admin/stats' && req.method === 'GET') {
    const users = await env.DB.prepare('SELECT COUNT(*) AS n FROM users').first();
    const today = Math.floor(Date.now()/1000) - 86400;
    const reqToday = await env.DB.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS t FROM usage_log WHERE created_at >= ?').bind(today).first();
    return json(200, { users: users.n, requests_today: reqToday.n, tokens_today: reqToday.t });
  }

  return json(404, { error: '接口不存在' });
}

export default {
  async fetch(req, env, ctx) {
    try {
      return await handle(req, env, ctx);
    } catch (e) {
      return json(500, { error: `内部错误: ${e.message || e}` });
    }
  },
};

// ==================== 管理后台网页 ====================
const adminHtml = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Darling AI 管理后台</title>
<style>
body{margin:0;font-family:system-ui,-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;background:#0f1115;color:#e6e8eb}
.wrap{max-width:980px;margin:0 auto;padding:24px}
h1{font-size:20px;margin:0 0 4px}
.sub{color:#9aa3b2;font-size:12.5px;margin-bottom:16px}
.card{background:#1a1d24;border:1px solid #2a2f3a;border-radius:10px;padding:16px;margin-bottom:16px}
h2{font-size:13px;color:#9aa3b2;margin:0 0 10px;font-weight:600}
label{display:block;font-size:12px;color:#9aa3b2;margin:8px 0 4px}
input,select,textarea{width:100%;box-sizing:border-box;background:#0f1115;border:1px solid #2a2f3a;color:#e6e8eb;border-radius:6px;padding:8px;font-size:13px}
input:focus,select:focus,textarea:focus{outline:none;border-color:#10a37f}
button{background:#10a37f;color:#fff;border:0;border-radius:6px;padding:8px 14px;font-size:13px;cursor:pointer;margin-top:8px}
button:hover{opacity:.9}
button.ghost{background:transparent;border:1px solid #2a2f3a;color:#9aa3b2}
button.danger{background:#8a2f2f}
table{width:100%;border-collapse:collapse;font-size:12.5px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #232833;vertical-align:top}
th{color:#9aa3b2;font-weight:500}
.row{display:flex;gap:8px;align-items:center}
.row>*{flex:1}
#status{color:#10a37f;font-size:12.5px;min-height:20px;margin:6px 0}
.err{color:#f26d6d}
.badge{display:inline-block;padding:1px 6px;border-radius:4px;font-size:11px;background:#2a2f3a;color:#9aa3b2;margin-left:6px}
.badge.on{background:#0d3d30;color:#3ddc97}
.small{font-size:11.5px;color:#9aa3b2}
.mono{font-family:ui-monospace,Consolas,monospace;font-size:11.5px;word-break:break-all}
</style>
</head>
<body>
<div class="wrap">
<h1>Darling AI · 管理后台</h1>
<div class="sub">账号 · 额度 · 上游代理 · 公告 · 封禁 · 用量统计</div>
<div id="status"></div>
<div class="card" id="loginCard">
<h2>管理员登录</h2>
<label>邮箱</label><input id="lgEmail" placeholder="admin 账号邮箱">
<label>密码</label><input id="lgPw" type="password" placeholder="密码">
<button onclick="login()">登录</button>
</div>
<div class="card" id="mainCard" style="display:none">
<h2>用量统计</h2>
<div id="stats"></div>
<h2>上游提供商</h2>
<div class="row">
<input id="pName" placeholder="名称（如 Agnes）">
<input id="pBase" placeholder="Base URL 如 https://apihub.agnes-ai.com/v1">
</div>
<div class="row">
<select id="pType"><option value="hybrid">hybrid（文本+图片）</option><option value="text">text</option><option value="image">image</option></select>
<input id="pKey" placeholder="API Key" type="password">
</div>
<div class="row">
<button onclick="addProvider()">加上游</button>
<button class="ghost" onclick="testProvider()">测试连接</button>
</div>
<div id="provList" class="small"></div>
<h2>对外模型（合并品牌）</h2>
<div class="row">
<input id="mName" placeholder="对外名称（如 02）">
<input id="mUpstream" placeholder="上游模型名（如 agnes-3.0-flash）">
</div>
<div class="row">
<select id="mProv"></select>
<select id="mType"><option value="hybrid">hybrid（文本+图片合并）</option><option value="text">text</option><option value="image">image</option></select>
<input id="mSlug" placeholder="slug（如 02）">
</div>
<textarea id="mPrompt" rows="2" placeholder="系统提示词（默认：你叫 02，用户让你改名就以用户为准）"></textarea>
<button onclick="addModel()">上架模型</button>
<div id="modelList" class="small"></div>
<h2>公告</h2>
<div class="row">
<input id="aTitle" placeholder="标题">
<input id="aContent" placeholder="内容">
<button onclick="addAnnouncement()">发公告</button>
</div>
<div id="annList" class="small"></div>
<h2>用户（封禁 / 解封）</h2>
<div id="userList" class="small"></div>
</div>
</div>
<script>
const API='';
let access='';
let provsCache=[];
async function req(method,path,body){
  const r=await fetch(API+path,{method,headers:{'Content-Type':'application/json',...(access?{'Authorization':'Bearer '+access}:{})},body:body?JSON.stringify(body):undefined});
  const j=await r.json().catch(()=>({}));
  if(j.error&&!j.access){/* 不弹，status 显示 */}
  return j;
}
function status(s,err){document.getElementById('status').innerHTML=s||'';document.getElementById('status').className=err?'err':'';}
async function login(){
  const r=await req('POST','/api/auth/login',{email:document.getElementById('lgEmail').value,password:document.getElementById('lgPw').value});
  if(r.access){access=r.access;document.getElementById('loginCard').style.display='none';document.getElementById('mainCard').style.display='block';loadAll();status('已登录');}else{status(r.error||'登录失败',1);}
}
async function loadAll(){loadStats();loadProvs();loadModels();loadUsers();loadAnns();}
async function loadStats(){
  const r=await req('GET','/api/admin/stats');
  if(r.users!==undefined){document.getElementById('stats').innerHTML='<div class="small">用户 <b>'+r.users+'</b> · 今日请求 <b>'+r.requests_today+'</b> · 今日 token <b>'+r.tokens_today+'</b></div>';}
}
async function loadProvs(){
  const r=await req('GET','/api/admin/providers');
  if(!r.providers)return;
  provsCache=r.providers;
  const sel=document.getElementById('mProv');
  sel.innerHTML=provsCache.map(p=>'<option value="'+p.id+'">'+p.name+'</option>').join('');
  document.getElementById('provList').innerHTML=provsCache.map(p=>
    '<div style="padding:4px 0">▪ '+p.name+' · <span class="mono">'+p.base_url+'</span> · '+p.type+'</div>').join('')||'暂无上游';
}
async function addProvider(){
  const r=await req('POST','/api/admin/providers',{name:document.getElementById('pName').value,base_url:document.getElementById('pBase').value,api_key:document.getElementById('pKey').value,type:document.getElementById('pType').value});
  if(r.ok){status('上游已添加');document.getElementById('pKey').value='';loadProvs();}else{status(r.error||'添加失败',1);}
}
async function testProvider(){
  status('测试中…');
  const r=await req('POST','/api/admin/providers/test',{base_url:document.getElementById('pBase').value,api_key:document.getElementById('pKey').value});
  if(r.ok){status('连接成功，检测到模型：'+(r.models||[]).slice(0,8).join('、'));}else{status(r.error||'连接失败',1);}
}
async function addModel(){
  const r=await req('POST','/api/admin/models',{name:document.getElementById('mName').value,slug:document.getElementById('mSlug').value,provider_id:document.getElementById('mProv').value,upstream_model:document.getElementById('mUpstream').value,type:document.getElementById('mType').value,system_prompt:document.getElementById('mPrompt').value||('你叫 02（用户让你改名就以用户为准）')});
  if(r.ok){status('模型已上架');loadModels();}else{status(r.error||'上架失败',1);}
}
async function loadModels(){
  const r=await req('GET','/api/admin/models');
  if(!r.models)return;
  document.getElementById('modelList').innerHTML='<table><tr><th>对外名称</th><th>slug</th><th>上游</th><th>类型</th><th>状态</th></tr>'+
    r.models.map(m=>'<tr><td>'+m.name+'</td><td class="mono">'+m.slug+'</td><td class="mono">'+m.upstream_model+'</td><td>'+m.type+'</td><td>'+(m.enabled?'<span class="badge on">上架</span>':'<span class="badge">下架</span>')+'</td></tr>').join('')+'</table>';
}
async function loadUsers(){
  const r=await req('GET','/api/admin/users');
  if(!r.users)return;
  document.getElementById('userList').innerHTML='<table><tr><th>ID</th><th>邮箱</th><th>角色</th><th>状态</th><th>操作</th></tr>'+
    r.users.map(u=>'<tr><td>'+u.id+'</td><td class="mono">'+u.email+'</td><td>'+u.role+'</td><td>'+(u.banned?'<span class="badge">封禁</span>':'<span class="badge on">正常</span>')+'</td><td>'+(u.banned
      ?'<button class="ghost" onclick="unban('+u.id+')">解封</button>'
      :'<button class="ghost" onclick="ban('+u.id+')">封禁</button>')+'</td></tr>').join('')+'</table>';
}
async function ban(id){await req('POST','/api/admin/ban',{user_id:id});loadUsers();status('已封禁 #'+id);}
async function unban(id){await req('POST','/api/admin/unban',{user_id:id});loadUsers();status('已解封 #'+id);}
async function addAnnouncement(){
  const r=await req('POST','/api/admin/announcement',{title:document.getElementById('aTitle').value,content:document.getElementById('aContent').value});
  if(r.ok){status('公告已发布');document.getElementById('aTitle').value='';document.getElementById('aContent').value='';loadAnns();}else{status(r.error||'发布失败',1);}
}
async function loadAnns(){
  const r=await req('GET','/api/announcements');
  if(!r.announcements)return;
  document.getElementById('annList').innerHTML=r.announcements.map(a=>'<div style="padding:3px 0">▪ '+a.title+' — '+a.content+'</div>').join('')||'暂无公告';
}
</script>
</body>
</html>`;
