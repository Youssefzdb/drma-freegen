# drma-freegen

Helper script to generate AI videos/images on drma.ai using free credits.

## Usage

```bash
./make_video.sh <count> "<prompt>" [path/to/fb_token.txt]
```

- `count`    : how many videos to generate
- `prompt`   : text prompt for the generation
- token file : run `./get_firebase_token.py [path]` first to mint one

## Output

- `outputs/video_<uid>_<taskId>.mp4` (5s, 480p)
- `outputs/img_<uid>_<taskId>.png`   (bonus image, uses leftover credits)

## How it works

1. `POST /videoAi/user/oneClickLogin` with `platform: web` header -> new session + 25 free credits
2. `POST /videoAi/aiGenerate/add/new` -> `t2v` video (15 credits) then `t2i` image (10 credits)
3. Polls `GET /videoAi/aiGenerate/<taskId>` until finished
4. Downloads final mp4/png to `outputs/`

## Notes

- Requires `bash`, `curl`, `python3`
- Each cycle mints a fresh session; a transient `code=500` from the API is retried automatically

## Onboarding (no token file needed)

```bash
./get_firebase_token.py /tmp/fb_token.txt   # signup flow -> writes idToken
./make_video.sh 3 "cinematic drone shot" /tmp/fb_token.txt
```
