# DLSS 5 test kit

A small kit for a 2–3 day evaluation: does the community DLSS 5 tooling visibly improve our renders? It has two parts.

| File | What it does |
| --- | --- |
| `Convert-ExrToTiff.ps1` | Turns EXR beauty passes into 16-bit sRGB TIFFs for the community tool, plus review copies for the A/B page. |
| `Convert stills (drop EXR files or folders here).bat` | Drag-and-drop launcher for stills. |
| `Convert sequence (drop shot folders here).bat` | Drag-and-drop launcher for animations (one folder of frames = one shot, 25 fps). |
| `ab-review.html` | Blind A/B scoring page. Open it in Chrome or Edge. It works offline, and files never leave the computer. |

Needs ffmpeg (a full build with zscale and libx264, as in `C:\ffmpeg\bin`). The script runs in Windows PowerShell 5.1 and PowerShell 7.

## Ground rules

- **Run the community tool on a separate test PC**, not on the Momi production server or any machine with access to client shares. The DLSS 5 runtime those tools use is a leaked, unlicensed build. This kit doesn't include it.
- **Use non-client scenes only**, or old work we are allowed to use.
- **This test is for evaluation only.** Nothing from it goes to a client.

## Steps

### 1. Pick five test shots

| Shot | Why |
| --- | --- |
| Exterior, daylight | The general realism check |
| Interior with people and plants | Faces and vegetation, where testers report the biggest changes |
| Dusk or night with glare | DLSS 5 is reported to flatten bloom and glare |
| Material-critical shot (client finishes, brand colours, signage) | Checks for colour and material drift |
| 10–20 s animation (camera move through vegetation) | Checks flicker and stability |

Render the beauty as linear EXR **without** glare, bloom, motion blur, grading or film grain.

### 2. Convert the EXRs

Drag the stills (files or a folder) onto **Convert stills**, and each animation folder onto **Convert sequence**. Results go to a `dlss5-test` folder next to the input:

```
dlss5-test\
  for-tool\     16-bit TIFFs (stills), <shot>.mp4 and <shot>_frames\ (animations)  -> feed these to the tool
  for-review\   16-bit PNGs (stills), <shot>.mp4 (animations)                        -> "Originals" in the A/B page
  conversion-log.csv                                                                  -> what was converted, and how
```

From a PowerShell prompt you get more control:

```powershell
.\Convert-ExrToTiff.ps1 D:\tests\ext_day.exr -ListLayers               # show the layers in the file
.\Convert-ExrToTiff.ps1 D:\tests\stills -Exposure 0.5                   # brighten by half a stop
.\Convert-ExrToTiff.ps1 D:\tests\stills -ToneMap rolloff                # soft highlights instead of clipping
.\Convert-ExrToTiff.ps1 D:\tests\stills -Lut D:\luts\studio_look.cube   # apply a display look LUT
.\Convert-ExrToTiff.ps1 D:\tests\shot010 -Sequence -Fps 30
.\Convert-ExrToTiff.ps1 D:\tests\beauty.exr -Layer Beauty              # beauty stored in a named layer
```

The conversion is scene-linear → optional exposure → optional tone map (`rolloff`, `reinhard` or `hable`, white point `-WhitePoint`, default 8) → sRGB curve → optional `.cube` LUT → 16-bit. Without `-ToneMap`, values above 1.0 clip like a plain sRGB view. If a shot depends on the frame buffer's tone mapping, either reproduce it with these options or save a 16-bit TIFF straight from the VFB instead. The originals must look the way the artist intended, or the test isn't fair.

### 3. Run the community tool (on the test PC)

- Process everything in `for-tool`. Keep the scale at 1× (no upscaling) so the sizes match.
- **Export stills as PNG and video as MP4.** Browsers can't show TIFF.
- Try a few settings per shot, for example the default, low tone (keeps colours closer) and two passes.
- **Name each result so it contains the original's name**, plus a short label for the settings:

  ```
  ext_day.png          (original, from for-review)
  ext_day_default.png  (enhanced, default settings)
  ext_day_tone0.png    (enhanced, tone at 0)
  ext_day_2pass.png    (enhanced, two passes)
  shot010_default.mp4
  ```

Put all results in one folder, for example `enhanced\`.

### 4. Score blind, each artist on their own

1. Open `ab-review.html` in Chrome or Edge.
2. Enter your name. Drop `for-review` onto **Originals** and the `enhanced` folder onto **Enhanced**. Check the pair list.
3. Click **Start review**. Each pair shows as A and B, with sides drawn at random, so you don't know which is enhanced.
4. Score each pair: the overall choice, the aspects that apply, whether each side could go to a client, and a comment.

| Key | Action |
| --- | --- |
| `1`–`5` | Overall: A much better … B much better |
| `←` `→` | Previous / next pair |
| `S` `W` `F` | Side by side, Wipe (drag the line), Flip (click or `Space` to switch) |
| `Z` | Zoom: fit, 1:1, 2:1 (drag to pan) |
| `K` / `Space` | Play or pause video (`Space` flips in Flip view) |
| `,` `.` | Previous / next frame |

Scores save in the browser as you go. Use the same name to resume later. When you finish, **Results** shows which side was enhanced. Click **Download my results (JSON)** and send the file to whoever collects them.

### 5. Combine and decide

The coordinator opens `ab-review.html`, goes to **Results** (or clicks *Open the results and add their files* on the setup screen), adds every reviewer's JSON file, and downloads the CSV if needed.

The page applies the rule from the study:

> **Worth more time** if, in at least 2 shots, the best setting averages at least +0.5 (on a −2…+2 scale) with most reviewers preferring it, and on those shots materials and colour are judged worse in no more than a third of answers. Otherwise: **not convincing yet**. Wait for the official SDK or vendor support.

Read the result with two limits in mind:

- **The leaked build is an early pre-release.** NVIDIA says better models are coming.
- **The tool estimates motion from the video itself**, instead of using our velocity pass. A weak animation result is a "maybe". A weak result on stills is a fairly clear "no".

## Troubleshooting

- **"ffmpeg was not found"**: put `ffmpeg.exe` on PATH or in `C:\ffmpeg\bin`, or pass `-FfmpegPath`.
- **"no main RGB channels"**: run with `-ListLayers` and pass the right `-Layer`.
- **Multi-part EXR**: use `-Part N` (the default is 0) and, if needed, `-Layer`.
- **Script blocked by execution policy**: use the `.bat` launchers, or run `powershell -ExecutionPolicy Bypass -File .\Convert-ExrToTiff.ps1 ...`.
- **A pair shows "different sizes"**: the tool upscaled. Re-export at 1×, because a size difference also gives away which side is enhanced.
- **TIFF results from the tool**: convert them with `ffmpeg -i in.tif -pix_fmt rgb48be out.png`.
