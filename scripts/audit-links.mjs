import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

const root = process.cwd();
function files(folder) {
  return readdirSync(join(root, folder), { withFileTypes: true }).flatMap(entry => {
    const path = join(folder, entry.name);
    return entry.isDirectory() ? files(path) : [path];
  });
}

const routes = files("app")
  .filter(path => /\/(page\.tsx|route\.ts)$/.test(path))
  .map(path => path.slice(4).replace(/\/(page\.tsx|route\.ts)$/, "").split("/")
    .filter(part => !part.startsWith("(")).join("/"))
  .map(path => path ? `/${path}` : "/");
const staticLinks = [];
for (const path of [...files("app"), ...files("components")].filter(path => path.endsWith(".tsx"))) {
  const content = readFileSync(join(root, path), "utf8");
  // Literal JSX links, navigation data, and router destinations. Computed URLs
  // and external links need flow-level review and are outside this static check.
  const pattern = /(?:href\s*[:=]\s*|router\.(?:push|replace)\(\s*)["'`]((?:\/)[^"'`\s]+)["'`]/g;
  for (const match of content.matchAll(pattern)) {
    const pathname = match[1].split(/[?#]/, 1)[0];
    staticLinks.push({ pathname, file: relative(root, join(root, path)) });
  }
}

const invalid = staticLinks.filter(({ pathname }) => !routes.some(route => {
  const expression = `^${route.replace(/\[[^/]+\]/g, "[^/]+")}$`;
  return new RegExp(expression).test(pathname);
}));
if (invalid.length) {
  for (const { pathname, file } of invalid) console.error(`${file}: unmatched link ${pathname}`);
  process.exitCode = 1;
} else {
  console.log(`Checked ${staticLinks.length} literal internal links against ${routes.length} page and API routes.`);
}
