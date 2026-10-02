# autobiography-interactive

Interactive autobiography deployment. Includes full HTML/CSS/JS code, narrative, and interactive features for Gemini, Railway, and public web hosting.

The latest update adds ritual tracking, a collaborator toolkit, and refreshed visual systems for the hero, signals, and timeline sections.

## Getting started

This project is a static site that loads narrative content from `data/story.json`. The interface renders a hero section with story stats, a living narrative board, filterable timeline, modal-based achievement gallery, and skill progression tracker. Theme toggling keeps the site readable in light or dark environments.

### Requirements

- Node.js 18.20+ on the 18 line, or 20.10 and newer (for the built-in test runner and deployment script). Node 19.x and 20.0–20.9 cannot parse the test suite's JSON import.

### Install dependencies

The site itself has no runtime dependencies. The test suite uses one development dependency, [jsdom](https://github.com/jsdom/jsdom), to render the page outside a browser. Install it once before running the tests:

```
npm install
```

jsdom is pinned to version 26 because version 27 drops support for Node 18.20 and for 20.10 through 20.18.

### Available scripts

- `npm test` – Runs the Node test runner over three suites. The data tests check that `data/story.json` holds values the page can render safely. The formatter tests cover number abbreviation. The render tests load `index.html` with `scripts/main.js` in jsdom and check what a visitor gets: every section renders, text displays as text, each "Explore story" button opens its own story, filters work, and failures are contained and reported.
- `npm run deploy` – Builds a `dist/` directory containing a ready-to-ship bundle and deployment manifest for static hosting or Railway uploads.

### Deploying

1. Run `npm run deploy` to generate the `dist/` folder.
2. Upload the contents of `dist/` to your preferred host (e.g., Railway static site, GitHub Pages, or any CDN).
3. Serve `index.html` as the entry point.

### Customizing the narrative

- Update `data/story.json` with your own profile, timeline, achievements, and skills.
- Extend `signals` and `toolkit` entries in `data/story.json` to change the ritual tracking and downloadable resources.
- Modify styles in `styles/main.css` to adjust the visual language.
- Extend interactions in `scripts/main.js` for new components or data visualizations.
