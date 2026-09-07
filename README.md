# Scorpion_Jr DJ Booking Website

Plain HTML/CSS/JavaScript frontend connected to Supabase.

## Directory
- Public pages: index.html, about.html, music.html, packages.html, availability.html, book.html, contact.html
- Admin pages: admin/
- JavaScript: js/
- Styling: css/
- Assets: assets/

## Supabase setup
1. Open `js/supabase.js`.
2. Replace `YOUR_SUPABASE_PROJECT_URL` with your Supabase Project URL.
3. Replace `YOUR_SUPABASE_PUBLISHABLE_KEY` with your browser-safe Publishable key (or legacy anon key).
4. Never put a Supabase secret/service-role key in this project.
5. Run the included `supabase-schema.sql` in Supabase SQL Editor.
6. Create the admin Auth user in Supabase Authentication.
7. Follow the admin profile/RLS instructions in the SQL file.

## Local testing
Because browser modules/CDN requests can behave differently from file://, use VS Code Live Server or another local static server.

Example with Python:
python -m http.server 5500

Then open:
http://localhost:5500/

## Deployment
This project is designed for static hosting such as Vercel or Netlify.
