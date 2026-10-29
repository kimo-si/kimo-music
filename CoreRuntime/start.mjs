/**
 * 引导层：在加载 API 模块之前固定运行平台。
 * MoeKoeMusic 通过 `kugoumusicapi --platform=lite` 启动（概念版），
 * ESM 的 import 会先于模块体求值，所以平台变量必须在这里设置。
 */
process.env.platform = process.env.KIMO_CORE_PLATFORM || 'lite';
await import('./server.mjs');
