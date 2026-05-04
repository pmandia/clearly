# Clearly Review Service

MVP hosted review service for Clearly Markdown reviews.

## Runtime

- Node 20+
- Postgres (`DATABASE_URL`)
- `PUBLIC_BASE_URL`, for example `https://clearly-review-production.up.railway.app`
- `CLEARLY_REVIEW_PUBLISHER_TOKEN`, a private publisher/admin token used by the Clearly app for initial review creation
- `CLEARLY_REVIEW_SIGNED_URL_SECRET`, a separate private HMAC secret used for short-lived Markdown source and fork URLs

For Railway, create a service rooted at `review-service/`, attach a Postgres database, and set the environment variables above.

## Commands

```sh
npm install
npm run migrate
npm run dev
```

The app stores snapshot HTML and Markdown source in Postgres for MVP. The API still enforces the documented caps: 5 MB rendered snapshot HTML and 2 MB Markdown source.
