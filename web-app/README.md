# Kwarta Web App

Browser version of Kwarta Budget Tracker. Built with React, TypeScript, Vite, Dexie (IndexedDB), and Supabase.

## Features

- Email/password sign-in and account creation through Supabase Auth.
- Income and expense records, category breakdown, and monthly budgets.
- Saves each change to IndexedDB first, including while offline.
- Syncs pending transactions and budgets to the existing Supabase tables when the connection returns.
- Installable Progressive Web App (PWA) with a cached app shell.
- Responsive layout for phones, tablets, and desktop browsers.

## Local development

Requirements: Node.js 22.12+ and npm.

\`\`\`bash
npm install
npm run dev
\`\`\`

Open the local URL printed by Vite.

## Supabase configuration

The app is preconfigured with the existing Kwarta Supabase project and its **publishable** client key. You may override these using:

- \`VITE_SUPABASE_URL\`
- \`VITE_SUPABASE_PUBLISHABLE_KEY\`

Copy \`.env.example\` to \`.env.local\` only when you need to override the defaults. Never put a Supabase service-role or secret key in a browser app.

The web app uses the existing tables:

- \`public.budget_transactions\`
- \`public.monthly_budgets\`

Both tables must have the existing Row Level Security policies from \`../supabase/schema.sql\`. The browser client does not bypass RLS.

In Supabase Dashboard, enable Email under Authentication > Providers. Set the production website URL under Authentication > URL Configuration and add the deployed Vercel URL to the allowed redirect URLs if email confirmation is enabled.

## Deploy to Vercel

Import the GitHub repository \`msreaamparo-wq/kwata_budget\` into Vercel and use these project settings:

- Framework preset: **Vite**
- Root Directory: **web-app**
- Build Command: \`npm run build\`
- Output Directory: \`dist\`
- Install Command: \`npm install\`

The Vercel project should be connected to the \`main\` branch so future pushes deploy automatically.

## Offline behavior and limitations

- First visit, first sign-in, and account creation require an internet connection.
- After the app has loaded and a user has signed in, transaction and budget changes are saved locally in that browser's IndexedDB.
- When internet returns, pending changes sync to Supabase.
- Browser storage is device/browser-specific. It is not shared with the Android app's SQLite database; Supabase is the shared cloud copy between platforms.
- Do not clear browser site data if you need unsynced offline records. Wait for the pending sync count to reach zero before moving to another browser or device.
- For security, every account can access only its own cloud rows through Supabase RLS.
