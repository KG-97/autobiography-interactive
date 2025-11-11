# autobiography-interactive

Interactive autobiography deployment. Includes full HTML/CSS/JS code, narrative, and interactive features for Gemini, Railway, and public web hosting.

## Getting started

This project is a static site that loads narrative content from `data/story.json`. The interface renders a hero section with story stats, a living narrative board, filterable timeline, modal-based achievement gallery, and skill progression tracker. Theme toggling keeps the site readable in light or dark environments.

### Requirements

- Node.js 18 or newer (for the built-in test runner and deployment script)

### Install dependencies

No dependencies are required beyond the Node runtime. If you would like to add packages, update `package.json` as needed.

### Available scripts

- `npm test` – Validates the story data structure using the Node test runner.
- `npm run deploy` – Builds a `dist/` directory containing a ready-to-ship bundle and deployment manifest for static hosting or Railway uploads.

### Deploying

1. Run `npm run deploy` to generate the `dist/` folder.
2. Upload the contents of `dist/` to your preferred host (e.g., Railway static site, GitHub Pages, or any CDN).
3. Serve `index.html` as the entry point.

### Customizing the narrative

- Update `data/story.json` with your own profile, timeline, achievements, and skills.
- Modify styles in `styles/main.css` to adjust the visual language.
- Extend interactions in `scripts/main.js` for new components or data visualizations.
