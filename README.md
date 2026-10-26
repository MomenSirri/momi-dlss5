# momi-dlss5

Tools and notes for evaluating **NVIDIA DLSS 5 neural rendering** on pre-rendered architectural visualization: stills and CGI animation from V-Ray and Corona, without rebuilding scenes in a game engine.

> Status (Oct 2026): NVIDIA has not released a public DLSS 5 SDK, so there is no licensed way to build this into a studio tool yet. This repo holds the research and a test-only evaluation kit. It contains **no NVIDIA software**.

## What's here

| Path | What it is |
| --- | --- |
| [`test-kit/`](test-kit/README.md) | Evaluation kit: an EXR → 16-bit TIFF converter for DLSS 5 test tools, and a blind A/B scoring page for artists |
| [`docs/research-summary.md`](docs/research-summary.md) | What DLSS 5 needs, what ArchViz users found, licence notes, sources |
| [`HANDOVER.md`](HANDOVER.md) | Current status and next tasks, for whoever (or whichever agent) picks this up |

## Quick start

1. Render the test shots' beauty as linear EXR, with no glare, bloom, motion blur or grading.
2. Drag the files onto `test-kit/Convert stills (drop EXR files or folders here).bat`, or drag a frame folder onto the sequence launcher. You need ffmpeg.
3. Process `dlss5-test/for-tool/` with the DLSS 5 tool under test, on a separate test PC. Export PNG or MP4 with names that contain the original's name.
4. Each artist opens `test-kit/ab-review.html`, scores the pairs blind and exports a JSON. One person combines the JSON files on the Results page.

Full steps are in [`test-kit/README.md`](test-kit/README.md).

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 or PowerShell 7
- ffmpeg full build (zscale, libx264), on PATH or in `C:\ffmpeg\bin`
- Chrome or Edge for the A/B page
- Python 3.8+ only for the self-test: `python test-kit/tests/test_converter.py`

Not affiliated with NVIDIA. DLSS is a trademark of NVIDIA Corporation.
