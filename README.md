# drma-freegen

Helper script to run all single-stage creation modes (text→video, image→video, text→image, image→image).

## Usage

```bash
./make_video.sh <count> "<prompt>" [path/to/fb_token.txt] [mode] [source_image_url]
./get_firebase_token.py [path]   # mints the token file (1h TTL)
```

- mode: `t2v` (default, 15 credits) | `i2v` (15) | `t2i` (10) | `i2i` (10)
- `i2v` / `i2i` need a `source_image_url` (any public image URL)
- after a generation, leftover credits (>10) also produce a bonus text→image

## Verified modes

- t2v: 5s 480p mp4 ✓     (pricing 3 credits/s @480p, 6/s @720p, max 15s)
- i2v: animated from a supplied image ✓ (mp4)
- t2i: png ✓
- i2i: restyled from a supplied image ✓ (png)

Story ("microfilm", 25 credits) is NOT a single call — it runs through
`/videoAi/drama/v2/create` -> story/cover/episode confirm steps, so it is out of
scope for this helper.

## Notes

- Requires `bash`, `curl`, `python3`
- Each cycle mints a fresh session; a transient `code=500` from the API is retried automatically

## Onboarding (no token file needed)

```bash
./get_firebase_token.py /tmp/fb_token.txt   # signup flow -> writes idToken
./make_video.sh 3 "cinematic drone shot" /tmp/fb_token.txt
```
