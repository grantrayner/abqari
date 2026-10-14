export function matchesPath(pattern, path) {
  if (pattern === '/*') return true;
  if (pattern.endsWith('/*')) return path.startsWith(pattern.slice(0, -1));
  const expression = pattern.split('*').map(s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('[^/]*');
  return new RegExp(`^${expression}$`).test(path);
}

export function safeUrl(raw) {
  const url = new URL(raw);
  const path = url.pathname.replace(/\/(checkout|checkouts|cart)\/.*/, '/$1/<redacted>');
  return `${url.origin}${path}`;
}
