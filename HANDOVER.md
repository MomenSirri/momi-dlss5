# Handover

**Read this first.** It says where the work stands, what to do next, and the rules for this repo.

- Last updated: 26 Oct 2026
- Owner: Momen Sirri. Work so far done with Claude Code (Opus 5.5).
- Background: [docs/research-summary.md](docs/research-summary.md)

## The goal

Find out whether NVIDIA **DLSS 5 neural rendering** can improve the realism of our pre-rendered ArchViz stills and animations (V-Ray / Corona output) without rebuilding scenes in a game engine. If it can, build a studio tool around it.

## Where things stand

| Area | Status |
| --- | --- |
| Research and feasibility study | **Done.** Feasible technically. Not licensable today, because the DLSS 5 SDK is not public. See the research summary. |
| Decision | **Run a test-only evaluation** with the community (leaked) tooling on a separate PC, using non-client scenes, before investing more. |
| Test kit (`test-kit/`) | **Built and tested** on synthetic data. Not yet used on real renders. |
| Evaluation itself | **Not started.** Needs a test PC with the community tool, five test shots and 2–3 artists. |
| NVIDIA access request / vendor questions | **Not sent.** |
| Production tool (pipeline, GPU worker) | **Not started.** Planned only if the evaluation is convincing; see "Later" below. |

## Repo map

```
HANDOVER.md                  this file
README.md                    public overview
CLAUDE.md, AGENTS.md         pointers for AI agents (read this file)
docs/research-summary.md     facts, licence notes, sources
test-kit/
  README.md                  the evaluation protocol, step by step (for artists)
  Convert-ExrToTiff.ps1      EXR beauty -> 16-bit sRGB TIFF (tool input) + PNG/MP4 (review copies)
  Convert stills (...).bat   drag-and-drop launcher
  Convert sequence (...).bat drag-and-drop launcher, -Sequence
  ab-review.html             blind A/B scoring page, single file, offline
  tests/make_exr.py          stdlib-only EXR fixture writer
  tests/test_converter.py    regression test for the converter
```

## Next tasks, in order

1. **Validate the converter on real renders.** Take real V-Ray and Corona EXRs (multi-layer, PIZ/ZIP/DWAA compression, a multi-part file if we have one, a file whose data window is smaller than its display window).
   - Run `-ListLayers`, then a conversion, and compare the PNG with the VFB view.
   - Fix whatever breaks and add a fixture for it to `tests/`.
   - **Done when:** the converted stills match the artist's intent, or the README says how to match them (exposure, `-ToneMap`, `-Lut`, or exporting from the VFB).
2. **Check `ab-review.html` opened by double-click (`file://`) in Chrome and Edge** with real folders dragged in.
   - It was tested over `http://localhost` with files injected by script. The drag-and-drop folder path and `localStorage` on `file://` were not exercised.
   - **Done when:** setup, review, resume after a reload, export and combine all work from `file://`.
3. **Support the evaluation run** (the owner and artists do this on the test PC; see `test-kit/README.md`).
   - An agent can help by checking file naming before the review, and by reading the combined CSV and writing up the result.
   - **Done when:** the Results page gives a decision based on at least 2 reviewers and 5 shots.
4. **Draft the outside requests** for the owner to send. Don't send anything yourself.
   - (a) DLSS 5 SDK access request to NVIDIA developer relations: offline use on pre-rendered frames; ask about RTX PRO support, on-site render nodes and terms for internal tools.
   - (b) Short notes to Chaos (Vantage / V-Ray) and D5 asking for DLSS 5 dates.

### Later: only if the evaluation says "worth more time"

The plan from the study. One developer with AI assistants, about 7–9 developer-weeks.

| Phase | Work | Done when |
| --- | --- | --- |
| P1 | Pipeline core: Python 3.12 + PySide6 app, shot manifest, EXR and render-element ingest (beauty, velocity, Z, Cryptomatte), guide builder that converts velocity to DLSS's convention and checks it by warping frame N−1 onto N, A/B viewer (reuse ideas from `ab-review.html`), EXR/ProRes output with a per-frame settings sidecar. | A real shot runs end to end through a pass-through backend. |
| P2 | GPU worker: C++20, Direct3D 12, NVIDIA NGX, on the **public** DLSS SDK (Super Resolution / DLAA). Separate exe. | A 4K frame makes the round trip, with timings. |
| P3 | DLSS 5 backend, **only with a licence from NVIDIA**: model/preset, Structure/Tone, masks, 1–4 passes, tiling above 4K. | The same shots run through DLSS 5. |
| P4 | Studio pilot: blind A/B with art directors on 3 shots. | Go or no-go on rollout. |

Gate G1: if there is no written path to DLSS 5 access by the end of January 2027, fall back to vendor support (Vantage/D5) or diffusion passes in Momi.

## Rules

- **This repo is public.** Never commit client images, render files, internal host names, IP addresses, share paths, account names or credentials.
- **Never commit or link to NVIDIA binaries**, leaked or official (`nvngx_*.dll`, `sl.*.dll`). `.gitignore` blocks the common names. The kit must keep working without them; the community tool is installed separately by the user on the test PC.
- **Don't download, install or run the leaked DLSS 5 runtime or the community tools** as an agent. That is the owner's decision and happens on the test PC by hand.
- **Never run tests or tools on the Momi production server.** The ffmpeg-based converter and the self-test are fine on a workstation.
- **The converter must keep working in Windows PowerShell 5.1:** no `??`, no ternary, no `-Parallel`, ASCII-only source. Run `python test-kit/tests/test_converter.py` after every change; it tests both 5.1 and 7.
- **`ab-review.html` stays a single offline file:** no CDN, no network calls, system fonts only.

## Technical notes (learned the hard way)

**ffmpeg chain** (in `Get-FilterChain`):

```
[exposure=exposure=E:black=0] -> [zscale linear->linear, format=gbrpf32le, tonemap=...:peak=W:desat=0]
  -> zscale=tin=linear:t=iec61966-2-1:pin=709:p=709 -> [lut3d=file='C\:/path/x.cube']
  -> format=gbrp16le|gbrap16le -> format=rgb48le (or rgba64le)
```

- **Don't drop alpha with `format=gbrpf32le` on float input.** swscale clamps to 0..1 and leaks about 0.1% into other channels. Keep alpha until the 16-bit step, or let zscale drop it.
- **ffmpeg's `tonemap` filter crashes on `gbrapf32le`** (assertion in imgutils). That is why the tone-map path converts with zscale first.
- **`tonemap` needs an explicit `peak`.** Otherwise values above 1.0 all map to the same output. `rolloff` = `mobius:param=0.3`, which keeps shadows and midtones unchanged.
- **LUT paths inside the filter:** forward slashes, escaped drive colon, single quotes: `lut3d=file='C\:/dir with space/x.cube'`. Paths containing `'` are copied to `%TEMP%` first.
- **Sequence movies** use the concat demuxer with a duration per frame (last file repeated), H.264 yuv420p CRF 12, padded to even size, tagged bt709.
- **Decimal numbers** are formatted with InvariantCulture. Hungarian and other locales use a decimal comma.
- **Native calls** go through `System.Diagnostics.Process` with explicit Windows quoting (`Format-NativeArg`). Passing arguments directly behaves differently in PowerShell 5.1 and 7.

**ab-review.html**

- An enhanced file pairs with the original whose name it contains (the longest match, bounded by separators). The rest of the name is the "variant".
- `sides[id]` records which side (A/B) shows the enhanced file. Export converts every score to "toward enhanced": preference −2…+2, aspects `enhanced` / `original` / `same` / `na`.
- Sessions save in `localStorage` under `dlss5ab:v1:<reviewer lowercase>`. Results files are JSON with `kit: "dlss5-ab"`.
- `window.ABReview` (`addFiles`, `importResults`, `state`) exists for scripted tests.
- The decision rule lives in `renderResults()`: at least 2 shots whose best variant averages ≥ +0.5 with a majority preferring it, and materials and colour worse in ≤ 1/3 of those answers.

## How to test

```powershell
python test-kit\tests\test_converter.py   # needs ffmpeg/ffprobe on PATH or in C:\ffmpeg\bin
```

For the A/B page, open `test-kit/ab-review.html`. Load a few PNG pairs named `x.png` / `x_variant.png` and an MP4 pair. Score them, reload to check resume, finish, export JSON, then import it again under another name.

## Open questions for the owner

- Which PC will be the test PC, and does it have an RTX 50 card? (RTX 40 needs a patched build.)
- Which five shots, and which 2–3 artists?
- Should the repo stay public? It contains no secrets, but it does document an evaluation of leaked software.
