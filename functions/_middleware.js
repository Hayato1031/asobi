// Cloudflare Pages Function: answer a page URL with its Markdown twin when the
// client asks for Markdown (AI agents send Accept: text/markdown). Browsers
// never list text/markdown, so they keep getting the HTML. _routes.json limits
// this to the page URLs, so no other file passes through here.

const PAGES = ["guide", "reference", "examples", "playground"];

// "/" -> "/index.md", "/ja/" -> "/ja/index.md", "/guide" -> "/guide.md";
// null for anything that is not a page.
export function markdownPath(pathname) {
  const match = /^(\/ja)?\/([a-z]*)$/.exec(pathname);
  if (!match) return null;
  const [, lang = "", page] = match;
  if (page === "") return `${lang}/index.md`;
  // "/ja" with no slash is not a page; the clean URL is "/ja/".
  return PAGES.includes(page) ? `${lang}/${page}.md` : null;
}

// True when text/markdown is wanted at least as much as text/html (q-values;
// a missing text/html counts as 0).
export function prefersMarkdown(accept) {
  if (!accept) return false;
  let markdown = 0;
  let html = 0;
  for (const part of accept.split(",")) {
    const [type, ...params] = part.split(";").map((s) => s.trim().toLowerCase());
    const q = params.map((p) => /^q=(.*)$/.exec(p)).find(Boolean);
    const weight = q ? Number(q[1]) : 1;
    if (Number.isNaN(weight)) continue;
    if (type === "text/markdown") markdown = Math.max(markdown, weight);
    if (type === "text/html") html = Math.max(html, weight);
  }
  return markdown > 0 && markdown >= html;
}

// Add a token to Vary without dropping what is already there.
function addVary(headers, token) {
  const current = headers.get("Vary");
  if (!current) return headers.set("Vary", token);
  const tokens = current.split(",").map((s) => s.trim().toLowerCase());
  if (!tokens.includes("*") && !tokens.includes(token.toLowerCase())) {
    headers.set("Vary", `${current}, ${token}`);
  }
}

export async function onRequest(context) {
  const { request, env } = context;
  if (request.method !== "GET" && request.method !== "HEAD") return context.next();

  const twin = markdownPath(new URL(request.url).pathname);
  if (twin && prefersMarkdown(request.headers.get("Accept"))) {
    const md = await env.ASSETS.fetch(new Request(new URL(twin, request.url), { method: request.method }));
    if (md.status === 200) {
      const res = new Response(md.body, md);
      res.headers.set("Content-Type", "text/markdown; charset=utf-8");
      res.headers.set("Content-Location", twin);
      addVary(res.headers, "Accept");
      return res;
    }
  }

  // A copy, so the headers can be changed; everything else stays as it was.
  const next = await context.next();
  const res = new Response(next.body, next);
  addVary(res.headers, "Accept");
  return res;
}
