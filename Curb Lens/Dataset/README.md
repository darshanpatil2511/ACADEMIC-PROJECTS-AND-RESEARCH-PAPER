# CurbLens dataset

Photos of real Boston parking signs plus hand-written ground truth, scored by `curbeval eval`.

```
Dataset/
├── labels.json      # one entry per photo (format below)
└── images/          # the photos (JPEG/HEIC/PNG straight from the iPhone Camera app)
```

The first 5 entries are the parser's test fixtures. They are in the **dev** split because the parser
was tuned on them.

## Taking the photos

- Aim for 60–100 different signs. Mix straight-on and angled shots (30–45°), near and far, daylight and
  dusk or night, and include some faded, partly blocked or glare-hit signs.
- Leave out faces and license plates (this repo is public). Crop or skip anything personal.
- Street-cleaning and snow-emergency signs stay up all winter, so they can be photographed any time.

## One label

```json
{
  "image": "images/IMG_0142.jpeg",
  "split": "dev",
  "conditions": ["angle", "dusk"],
  "transcript": "TOW ZONE | NO PARKING | STREET CLEANING | 2ND & 4TH TUESDAY | 8AM-12 NOON | APR 1-NOV 30",
  "rules": [
    {"kind": {"type": "streetCleaning"}, "days": {"nth": [2, 4], "weekday": "TUE"},
     "window": {"start": "08:00", "end": "12:00"},
     "season": {"startMonth": 4, "startDay": 1, "endMonth": 11, "endDay": 30}, "towZone": true}
  ],
  "checks": [
    {"at": "2026-11-10T09:00", "expect": "cannotPark"},
    {"at": "2026-11-17T09:00", "expect": "canPark"}
  ]
}
```

| Field | What to write |
|---|---|
| `image` | Path relative to `Dataset/`. |
| `split` | `dev` for photos you may tune the parser on. Mark about **20 photos `test`** and never look at their failures until the end: that score is the honest number for your resume. |
| `conditions` | Any tags you like. Results are broken down by tag. Suggested: `straight`, `angle`, `day`, `dusk`, `night`, `glare`, `faded`, `blocked`, `distant`, `multi-sign`, `low-res`. |
| `transcript` | The text on the sign, top to bottom, panels separated by `|`. Used for OCR character error rate (case, spaces and `|` are ignored). Skip tiny footer codes like "BTD MS-6". |
| `rules` | One rule per restriction, in the app's JSON format (see below). |
| `checks` | 2–4 Boston times with the verdict a driver should get: `canPark`, `cannotPark` or `unreadable`. Include at least one time when parking is blocked and one when it's allowed. |

### Rule JSON

| Key | Values | Default |
|---|---|---|
| `kind` | `{"type": "noParking"}`, `noStopping`, `streetCleaning`, `loadingZone`, `snowEmergency`, `{"type": "timeLimit", "minutes": 120}`, `{"type": "permitOnly", "zone": "BACK BAY"}` (`zone` optional) | required |
| `days` | `{"days": ["MON", "TUE"]}`, `{"nth": [2, 4], "weekday": "TUE"}`, or `"everyDay"` | `"everyDay"` |
| `window` | `{"start": "08:00", "end": "18:00"}`. An end before the start means overnight. | all day |
| `season` | `{"startMonth": 4, "startDay": 1, "endMonth": 11, "endDay": 30}` | all year |
| `towZone` | `true` when the sign says TOW ZONE | `false` |
| `residentExempt` | `true` for "EXCEPT RESIDENT STICKER" | `false` |

How to label common cases:

- **"EXCEPT SUNDAY"** means the other six days: `{"days": ["MON","TUE","WED","THU","FRI","SAT"]}`.
- **"No parking except commercial vehicles"** and **pick-up/drop-off zones** block regular cars, so label them `loadingZone`.
- **Several signs on one pole:** label every rule. The app doesn't interpret arrows and treats every rule as applying.
- **Holidays:** ignore them. The app doesn't handle holidays, and the label should describe what the app is expected to do.

`curbeval eval` refuses to run if a check contradicts the label's own rules, which catches most typos.

## Running

```bash
swift run --package-path CurbCore curbeval eval                # dev split -> Reports/eval_<time>.md + .json
swift run --package-path CurbCore curbeval eval --split test   # held-out score (run at the end)
swift run --package-path CurbCore curbeval ablate              # baseline vs no crop / no lang-correction / fast
```
