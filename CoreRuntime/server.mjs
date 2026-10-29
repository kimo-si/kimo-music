/**
 * Kimo Core Runtime
 * -----------------
 * MoeKoeMusic 的核心 API 层（kugoumusicapi + express 路由 + 设备指纹），
 * 去掉 Electron 依赖后以独立进程运行，供原生 macOS 客户端通过本机 HTTP 调用。
 *
 * 移植自 MoeKoeMusic/electron/util/kugouapi/createServer.js
 */
import express from 'express';
import { WebSocketExpress } from 'websocket-express';
import cache from 'kugoumusicapi/util/apicache.js';
import api from 'kugoumusicapi';
import { cookieToJson, createRequest } from 'kugoumusicapi/util/index.js';
import { getDevice, generateNewDevice, rememberDfid } from './device.mjs';

// 登录 token 和 appid 绑在一起。二维码登录走的是库默认 appid 1005，
// 这里不能改成 lite（3116），否则已有 token 会被判失效（20017）。
// 概念版需要在进程启动前设置 platform=lite，并重新登录。

const PORT = Number(process.env.KIMO_CORE_PORT || 6520);
const HOST = process.env.KIMO_CORE_HOST || '127.0.0.1';

const convertModulesToDefs = () => {
  const skips = ['createRequest', 'createCloudRequest', 'startService', 'getModulesDefinitions'];
  const defs = [];
  Object.keys(api).forEach((k) => {
    if (skips.includes(k)) return;
    if (api[k]) {
      defs.push({ identifier: k, route: `/${k.replace(/_/g, '/')}`, module: api[k] });
    }
  });
  return defs;
};

const decode = (s) => {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
};

// 请求头只能安全携带这些字段。昵称等非 ASCII 会让客户端丢掉整段 Authorization。
const AUTH_HEADER_KEYS = ['token', 'userid', 't1', 'vip_token', 'vip_type', 'dfid'];

const authFromHeader = (header) => {
  if (typeof header !== 'string' || !header) return {};
  const parsed = cookieToJson(header);
  const out = {};
  for (const key of AUTH_HEADER_KEYS) {
    const value = parsed[key];
    if (typeof value === 'string' && /^[\x21-\x7e]+$/.test(value) && !value.includes(';') && !value.includes('=')) {
      out[key] = value;
    }
  }
  return out;
};

const ensureDfid = async () => {
  const current = getDevice();
  if (current.dfid) return current;
  try {
    const response = await api.register_dev({
      cookie: {
        ...current,
        KUGOU_API_DEV: current.dev,
        KUGOU_API_GUID: current.uuid,
        KUGOU_API_MAC: current.mac,
        KUGOU_API_MID: current.mid,
        KUGOU_API_WEBGL: current.webgl,
      },
    }, (config) => createRequest(config));
    const dfid = response?.body?.data?.dfid || response?.body?.dfid;
    if (typeof dfid === 'string' && dfid) return rememberDfid(dfid);
    const data = response?.body?.data;
    const keys = data && typeof data === 'object' ? Object.keys(data).join(',') : typeof data;
    console.error('[core] register dfid missing', keys || '');
  } catch (error) {
    console.error('[core] register dfid failed', error?.body?.error_code || error?.status || '');
  }
  return getDevice();
};

const createServer = () => {
  const expressApp = new WebSocketExpress();
  expressApp.set('trust proxy', true);

  expressApp.useHTTP((req, res, next) => {
    if (req.path !== '/' && !req.path.includes('.')) {
      res.set({
        'Access-Control-Allow-Credentials': true,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Authorization,X-Requested-With,Content-Type,Cache-Control',
        'Access-Control-Allow-Methods': 'PUT,POST,GET,DELETE,OPTIONS',
        'Content-Type': 'application/json; charset=utf-8',
        'X-Powered-By': 'kugoumusicapi',
        Server: 'Kimo/0.1.0',
      });
    }
    req.method === 'OPTIONS' ? res.status(204).end() : next();
  });

  expressApp.useHTTP(express.json({ limit: '16mb' }));
  expressApp.useHTTP(express.urlencoded({ extended: false, limit: '5mb' }));
  expressApp.useHTTP(express.raw({ type: 'application/octet-stream', limit: '100mb' }));
  // 登录、账号、播放地址都跟 token 有关，不能和未登录的响应共用缓存键。
  const skipCache = (path) =>
    path.startsWith('/login')
    || path.startsWith('/__kimo')
    || path.startsWith('/song/url')
    || path.startsWith('/user')
    || path.startsWith('/privilege')
    || path.startsWith('/playlist/track');
  expressApp.useHTTP((req, _res, next) => {
    if (skipCache(req.path)) req.headers['x-apicache-bypass'] = '1';
    next();
  });
  expressApp.useHTTP(cache.middleware('2 minutes', (_req, res) => res.statusCode === 200));

  for (const moduleDef of convertModulesToDefs()) {
    expressApp.useHTTP(moduleDef.route, async (req, res) => {
      [req.query, req.body].forEach((item) => {
        if (typeof item?.cookie === 'string') {
          item.cookie = cookieToJson(decode(item.cookie));
        }
      });

      const { cookie, ...params } = req.query;
      const device = getDevice();
      const body = Buffer.isBuffer(req.body) ? { data: req.body } : req.body;
      const query = Object.assign(
        {},
        {
          cookie: Object.assign({}, req.cookies, cookie, {
            ...device,
            KUGOU_API_DEV: device.dev,
            KUGOU_API_GUID: device.uuid,
            KUGOU_API_MAC: device.mac,
            KUGOU_API_MID: device.mid,
            KUGOU_API_PLATFORM: process.env.platform || '',
            KUGOU_API_WEBGL: device.webgl,
          }),
        },
        params,
        body
      );

      Object.assign(query.cookie, authFromHeader(req.headers.authorization));

      try {
        const moduleResponse = await moduleDef.module(query, (config) => {
          let ip = req.ip || '';
          if (ip.substring(0, 7) === '::ffff:') ip = ip.substring(7);
          config.ip = ip;
          return createRequest(config);
        });

        const cookies = moduleResponse.cookie;
        if (!query.noCookie && Array.isArray(cookies) && cookies.length > 0) {
          res.append(
            'Set-Cookie',
            cookies.map((c) => `${c}; PATH=/`)
          );
        }
        res.header(moduleResponse.headers).status(moduleResponse.status).send(moduleResponse.body);
      } catch (e) {
        if (!e.body) {
          res.status(404).send({ code: 404, data: null, msg: 'Not Found' });
          return;
        }
        console.error('[core] API error', moduleDef.route, e.status);
        res.header(e.headers).status(e.status || 500).send(e.body);
      }
    });
  }

  // 设备指纹管理（原生端首次启动/重置设备时调用）
  expressApp.useHTTP('/__kimo/device', (req, res) => {
    res.json(getDevice());
  });
  expressApp.useHTTP('/__kimo/device/reset', (req, res) => {
    res.json(generateNewDevice());
  });
  expressApp.useHTTP('/__kimo/health', (req, res) => {
    res.json({ ok: true, service: 'kimo-core', port: PORT });
  });

  expressApp.useHTTP((req, res) => {
    if (req.path === '/') res.status(204).end();
    else res.status(404).send({ code: 404, data: null, msg: 'Not Found' });
  });

  return expressApp;
};

const app = createServer();
const server = app.createServer();
await ensureDfid();
server.listen(PORT, HOST, () => {
  console.log(`[core] kugou api ready at http://${HOST}:${PORT}`);
});

const shutdown = () => {
  server.close(() => process.exit(0));
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
