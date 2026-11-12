# EXPERT Corporate Solutions – Payment Request

Single-page web app (`index.html`) backed by Supabase (Auth, Postgres with row-level security, Realtime, one Edge Function).

- Live site: GitHub Pages (this repo, `main` branch, root folder)
- Database schema: `supabase/schema.sql`
- User management function: `supabase/functions/manage-users/index.ts`

Roles: Admin, Manager, Executive. Users sign in with a username and password; the admin creates managers and executives from the app.
