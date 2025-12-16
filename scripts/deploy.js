import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..');
const distDir = path.join(projectRoot, 'dist');

async function ensureDist() {
  await rm(distDir, { recursive: true, force: true });
  await mkdir(distDir, { recursive: true });
}

async function copyAsset(relativePath) {
  const source = path.join(projectRoot, relativePath);
  const destination = path.join(distDir, relativePath);
  await mkdir(path.dirname(destination), { recursive: true });
  await cp(source, destination, { recursive: true });
}

async function createManifest() {
  const manifest = {
    generatedAt: new Date().toISOString(),
    files: ['index.html', 'styles/main.css', 'scripts/main.js', 'data/story.json'],
    instructions: 'Serve the dist directory with any static file host or upload to Railway.',
    version: '1.1.0'
  };

  await writeFile(path.join(distDir, 'deploy-manifest.json'), JSON.stringify(manifest, null, 2));
}

async function main() {
  await ensureDist();

  const assets = ['index.html', 'styles', 'scripts', 'data'];
  for (const asset of assets) {
    await copyAsset(asset);
  }

  await createManifest();
  console.log('Deployment bundle created in ./dist');
}

main().catch((error) => {
  console.error('Failed to build deployment bundle');
  console.error(error);
  process.exitCode = 1;
});
