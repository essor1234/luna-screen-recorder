# Presenter remote

Run the deck at luna.nimit.dev/deck from a phone, with speaker notes, a timer and demo controls.

- Laptop: `https://luna.nimit.dev/deck/?live=KEY`. The key leaves the address bar on load (the projector would show it) and sessionStorage keeps it across reloads. Click **Start presentation** once: browsers only allow full screen and demo sound after a real click on that page.
- Phone: `https://luna.nimit.dev/deck/remote/?key=KEY`. Add it to the home screen. Back/Next, tap "Slide n of 11" to jump, the timer starts on the first slide change, Play/Pause and English/Tiếng Việt show on the Demo slide. With the laptop offline, Back/Next step through the notes so you can rehearse.
- The public deck at `/deck/` never connects. Without the key the remote page shows a lock screen.

The real key lives in two places only: the Worker secret `REMOTE_KEY` and `~/.config/luna/presenter-key` on Nimit's Mac. It is never in the repo or the site.

## How it works

`luna-remote.nimitbhargava.workers.dev/ws?role=deck|remote&key=KEY` checks the key (constant time) and hands the socket to one Durable Object (`Relay`, hibernating WebSockets). Remotes send `{type:"cmd"}` to decks and decks send `{type:"state"}` to remotes. Nothing is stored: when a phone joins, the deck is asked to resend its state. A wrong key closes with code 4001 and the pages stop retrying. Speaker notes are in `src/notes.ts`, keyed by each slide's `data-title`, and reach the phone only after the key checks out.

Observability is off so request logs don't capture the key.

## Commands

```
cd presenter
../cloud/node_modules/.bin/wrangler deploy        # after editing notes or the relay
node test/e2e.mjs                                 # 10 checks against the live relay
```

Rotate the key (every old link stops working):

```
openssl rand -base64 24 | tr '+/' '-_' | tr -d '=\n' > ~/.config/luna/presenter-key
../cloud/node_modules/.bin/wrangler secret put REMOTE_KEY < ~/.config/luna/presenter-key
```
