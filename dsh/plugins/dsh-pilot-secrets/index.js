// dsh-pilot-secrets: secret hygiene for dsh on the pilot Spark.
//   tools/pre-execute   denies a call whose path or command names a secret file, or that would print
//                       the environment or a resolved harness configuration
//   tools/post-execute  replaces the model key (and other known secret values) and common secret
//                       shapes in the text the model sees
// dsh itself already removes every *KEY*|*TOKEN*|*SECRET*|*PASSWORD* variable from the environment of
// a tool's child process. Limits: this is a guard against mistakes, not a sandbox; spill files of very
// long outputs hold the raw text.
import fs from 'node:fs';
import os from 'node:os';

export const name = 'dsh-pilot-secrets';

const HOME = os.homedir();
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const H = `(?:~|\\$HOME|\\$\\{HOME\\}|${esc(HOME)})`;
// Files that hold a secret. A path in any argument, or in a command, that matches is refused.
const SECRET_PATHS = [
  [`${H}/\\.config/pilot/(?:api_key|env\\.sh|[^\\s'"]*\\.env|[^\\s'"]*_token|[^\\s'"]*_key)`, '~/.config/pilot secrets'],
  [`${H}/\\.ssh/(?:id_[^\\s'"]*|[^\\s'"]*\\.pem)`, '~/.ssh keys'],
  [`${H}/\\.(?:bashrc|zshrc|zshenv|profile|bash_profile|zprofile|netrc|git-credentials)\\b`, 'shell rc and credential files'],
  [`${H}/\\.dsh/\\.(?:credentials\\.yaml|env)\\b`, 'dsh credentials'],
  [`${H}/\\.local/share/opencode/(?:mcp-)?auth\\.json`, 'opencode credentials'],
  [`${H}/\\.docker/config\\.json`, 'docker credentials'],
  [`[^\\s'"]*\\.(?:token|key)(?=$|[\\s'"):;,|&<>])`, '*.token, *.key'],
  [`(?:^|[\\s'"=:/(])\\.env(?:\\.(?!example\\b|sample\\b|template\\b)[A-Za-z0-9_-]+)?(?=$|[\\s'"):;,|&<>])`, '.env files'],
  [`/proc/[^/\\s]+/environ`, '/proc/*/environ'],
].map(([re, why]) => [new RegExp(re), why]);
// Commands that print the environment or a resolved harness configuration (it can hold keys).
const ENV_DUMPS = [
  /^\s*(?:\/usr\/bin\/)?(?:env|printenv|set|export|declare|typeset)\s*$/,
  /\bprintenv\b/,
  /^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\/usr\/bin\/)?env(?:\s+-[0i]|\s+--null|\s+--ignore-environment)*\s*$/,
  /^\s*export\s+-p\b/, /^\s*(?:declare|typeset)\s+-[a-zA-Z]*[xp]/,
  /\bos\.environ\s*\)/, /\bprocess\.env\s*\)/,
  /\bopencode\s+debug\s+config\b/, /\bdsh\b.*--dump-config\b/,
];
const PATH_KEYS = new Set(['path', 'file_path', 'filePath', 'filename', 'file', 'paths', 'files', 'directory',
  'dir', 'cwd', 'workdir', 'pattern', 'include', 'glob', 'target_path', 'source', 'src', 'url']);
const COMMAND_KEYS = ['command', 'cmd', 'script', 'code'];
const SHAPES = [/sk-[A-Za-z0-9]{16,}/g, /ghp_[A-Za-z0-9]{20,}/g, /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_.-]*/g,
  /\b(?:password|passwd|secret|token|api[_-]?key)\s*[:=]\s*["']?[^\s"'{$]{8,}/gi,
  /:\/\/[A-Za-z0-9._-]{2,}:[^@\s/]{6,}@/g];

// Known secret values: the model key file and the secret-named variables of dsh's own environment.
function knownValues() {
  const byValue = new Map();
  const add = (v, n) => { if (typeof v === 'string' && v.trim().length >= 8 && !byValue.has(v.trim())) byValue.set(v.trim(), n); };
  try { add(fs.readFileSync(`${HOME}/.config/pilot/api_key`, 'utf8'), 'PILOT_LLM_KEY'); } catch { /* no key file */ }
  for (const [n, v] of Object.entries(process.env)) if (/KEY|TOKEN|SECRET|PASSWORD/i.test(n)) add(v, n);
  return [...byValue.entries()].sort((a, b) => b[0].length - a[0].length);
}

function* strings(x, keyed) {
  if (typeof x === 'string') { if (keyed) yield x; return; }
  if (Array.isArray(x)) { for (const v of x) yield* strings(v, keyed); return; }
  if (x && typeof x === 'object') for (const [k, v] of Object.entries(x)) yield* strings(v, keyed || PATH_KEYS.has(k) || COMMAND_KEYS.includes(k));
}

export function check(tool, args) {
  for (const s of strings(args, false)) for (const [re, why] of SECRET_PATHS) if (re.test(s)) return `${tool} names a secret file (${why})`;
  if (args && typeof args === 'object') {
    for (const k of COMMAND_KEYS) {
      const c = args[k];
      if (typeof c !== 'string') continue;
      for (const seg of [c, ...c.split(/&&|\|\||;|\n|\|/)]) for (const re of ENV_DUMPS) if (re.test(seg)) return `${tool} would print the environment or a resolved config`;
    }
  }
  return null;
}

export function redact(text, values) {
  if (typeof text !== 'string' || text === '') return text;
  let out = text;
  for (const [v, n] of values) if (out.includes(v)) out = out.split(v).join(`<redacted:${n}>`);
  for (const re of SHAPES) out = out.replace(re, (m) => (m.includes('<redacted:') ? m : '<redacted:shape>'));
  return out;
}

export function apply(ctx) {
  const values = knownValues();
  ctx.on('tools/pre-execute', async (exec, next) => {
    const why = check(exec.name, exec.args ?? exec.input);
    if (why) return { kind: 'deny', reason: `pilot-secrets: ${why}. Keys stay in their files; ask the operator.` };
    return next();
  }, { prepend: true });
  ctx.on('tools/post-execute', async (exec, result, next) => {
    const d = await next();
    if (d.kind !== 'accept' || Object.hasOwn(d, 'value')) return d;
    const content = (d.content ?? result.content ?? []).map((b) =>
      b && b.type === 'text' && typeof b.text === 'string' ? { ...b, text: redact(b.text, values) } : b);
    return { ...d, content };
  }, { prepend: true });
}
