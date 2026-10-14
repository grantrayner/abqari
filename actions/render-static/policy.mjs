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

export function headerMismatches(rules, path, headers) {
  return rules.filter(rule => matchesPath(rule.path, path))
    .filter(rule => {
      const actual = headers[rule.name.toLowerCase()];
      if (rule.name.toLowerCase() === 'strict-transport-security') return !hstsSatisfies(actual, rule.value);
      return actual?.trim() !== rule.value.trim();
    })
    .map(rule => ({ name: rule.name, expected: rule.value, actual: headers[rule.name.toLowerCase()] ?? '<missing>' }));
}

function hstsSatisfies(actual, expected) {
  const parse = value => {
    const directives = value?.toLowerCase().split(';').map(part => part.trim()) || [];
    const ages = directives.filter(part => /^max-age=\d+$/.test(part));
    return ages.length === 1 ? { age: Number(ages[0].slice(8)), subdomains: directives.includes('includesubdomains'), preload: directives.includes('preload') } : null;
  };
  const received = parse(actual), required = parse(expected);
  // Render's onrender.com host can enforce a longer, preloaded HSTS policy.
  // Accept stronger protection while rejecting missing or weaker directives.
  return Boolean(received && required && received.age >= required.age && (!required.subdomains || received.subdomains) && (!required.preload || received.preload));
}
