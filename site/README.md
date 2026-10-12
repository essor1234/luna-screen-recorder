# luna.nimit.dev

Static landing page and presentation for Luna. No build step.

- `index.html`: landing page
- `deck/index.html`: presentation at `/deck/` (arrow keys, space or click to move, F for full screen, `#n` jumps to slide n)
- `deck/remote/index.html`: phone remote for the deck, needs the private key (see `presenter/README.md`)
- `media/`: icons, mascot, demo video, poster, captions, QR code
- `video/`: Remotion source for `media/luna-demo.mp4` (narration from Microsoft Edge TTS)

Preview locally:

```
cd site && python3 -m http.server 4877
```

Deploy (Cloudflare Pages project `luna`, served at luna.nimit.dev via a CNAME to luna-cnb.pages.dev):

```
./site/deploy.sh
```
