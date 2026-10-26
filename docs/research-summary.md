# DLSS 5 for ArchViz: research summary

Research as of **26 October 2026**. It answers one question: can a studio run NVIDIA DLSS 5 on finished V-Ray or Corona output (stills and pre-rendered animation) without rebuilding scenes in a game engine?

The full study, with the prototype plan and decision gates, is a private report owned by the repo owner: <https://claude.ai/artifact/65AxeStkcfuX7g4kKaEYNa>. This file has the facts a developer or agent needs.

## Verdict

- **Technically: yes.** DLSS 5 is a per-frame filter driven by colour and motion vectors. Offline renderers can supply cleaner guide data than a game engine can. Community tools already run it on images and video.
- **Legally, today: no.** NVIDIA has not published a DLSS 5 SDK. Every tool that runs DLSS 5 outside a game uses `nvngx_dlssnr.dll` 310.8, extracted from NBA 2K27's early-access build. Nobody holds a licence for that file.
- **Recommendation:** run a short, test-only evaluation with the community tools on a separate PC (this repo's `test-kit/`). Request DLSS 5 access from NVIDIA. Build a licence-ready pipeline only if the evaluation is convincing.

## What DLSS 5 is

| Item | Fact |
| --- | --- |
| Timeline | Announced at GTC on 16 Mar 2026. Shipped on 1 Sep 2026 in NBA 2K27. |
| What it changes | High-frequency detail (ambient occlusion, reflections, subsurface scattering) and lighting/colour response. |
| Inputs | Frame colour and motion vectors, one frame in and one frame out. Deterministic and temporally stable according to NVIDIA. |
| Controls | Model choice, Structure Intensity, Tone Intensity (0 = keep the rendered colours), semantic AI masks, engine-level masks, per-pixel uplift mask. |
| Hardware | GeForce RTX 50, single GPU, up to 4K, driver 616.64 or newer. NVIDIA says nothing about RTX PRO Blackwell. RTX 40 and older only run it through patched leaked builds. |
| Integration | Streamline and an Unreal Engine 5 plugin, for launch partners. |
| SDK status | Checked via the GitHub API on 26 Oct 2026: DLSS SDK 310.9.16 contains only `nvngx_dlss.dll`, `nvngx_dlssd.dll` and `nvngx_dlssg.dll`. Streamline 2.14.16 has no neural-rendering plugin. A thread on NVIDIA's developer forum asking for access, including for offline Movie Render Queue use, had no NVIDIA reply from 8 Sep to 26 Oct. |

## Mapping DLSS 5 inputs to our renders

| Input | From our renders | Notes |
| --- | --- | --- |
| Colour | Beauty, linear half-float EXR | Before grading, LUTs, glare, bloom and grain |
| Motion vectors | Velocity render element (V-Ray `VRayVelocity`, Corona Velocity) | Unfiltered, no motion blur in the beauty, converted to DLSS's pixel-offset and sign convention |
| Depth | Z-depth element | Probably needed (community integrations pass it) |
| Masks | Cryptomatte, object and material IDs | Protect glass, signage, people, client finishes |
| History reset | Shot list | Every shot start. For stills, every image. |
| Jitter | None | Pass zero |

## What ArchViz users reported (Sep–Oct 2026, all using the leaked build)

- **Good:** adds detail, reflections and shadows; strong on foliage SSS, 3D people and exposure/colour balance ("surprisingly good for a quick production pass", D5 forum).
- **Bad:** reduces intended bloom and glare; artefacts on fine detail; crashes at high resolution; community tool drops output to 8-bit. One V-Ray user saw "negligible" difference. In D5 and Vantage it works only in the viewport.
- **Vendors:** D5 staff say support is in development (7 Sep). Chaos staff say Vantage support is planned with no date and refuse to troubleshoot the unofficial DLL (9 Oct).
- **Expectation for path-traced input:** a smaller uplift than the game demos. Games start from rasterised frames.

## Licence notes (NVIDIA RTX SDKs licence, version of 14 Mar 2024)

- Use in "an application", not limited to games. NVIDIA GPUs only.
- Cloud deployment only on NVIDIA vGPU. **No RunPod or serverless GPUs.**
- Notify NVIDIA before a commercial release; NVIDIA attribution is required. No standalone redistribution. No reverse engineering (§4a). No circumventing technical limits (§4d), which the patched RTX 40/30 builds do.
- DLSS 5 may ship with its own terms. Confirm with NVIDIA.

## Legal fallbacks available today

| Option | Gives | Limits |
| --- | --- | --- |
| Chaos Vantage or D5, once they ship DLSS 5 | Vantage opens V-Ray scenes without a rebuild | No dates |
| Diffusion restyle/relight (Momi) | Strong on stills | Not deterministic; flickers on animation |
| NVIDIA Cosmos Transfer 2.5 | Commercial licence, depth/segmentation/edge control | 720p, 16 fps, ~65 GB VRAM, Linux: R&D only |
| DLSS Super Resolution / DLAA (public SDK) | Upscaling and anti-aliasing, legal now | Adds no realism |

## Sources

- NVIDIA newsroom, DLSS 5 announcement: <https://nvidianews.nvidia.com/news/nvidia-dlss-5-delivers-ai-powered-breakthrough-in-visual-fidelity-for-games>
- NVIDIA GeForce, DLSS 5 in NBA 2K27: <https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/>
- NVIDIA developer blog: <https://developer.nvidia.com/blog/whats-new-for-game-developers-dlss-5-with-3d-guided-neural-rendering-nvidia-ace-updates-and-new-rtx-kit-capabilities/>
- DLSS SDK releases and licence: <https://github.com/NVIDIA/DLSS/releases>, <https://github.com/NVIDIA/DLSS/blob/main/LICENSE.txt>
- Streamline: <https://github.com/NVIDIA-RTX/Streamline>
- NVIDIA forum, access requests: <https://forums.developer.nvidia.com/t/official-dlss-5-neural-rendering-plugin-access-for-unreal-engine-5-8-2/382731>
- D5 forum: <https://forum.d5render.com/t/dlss-5-some-tests/76925>, <https://forum.d5render.com/t/we-tried-dlss-5-in-d5-render-actually-pretty-impressed/76990>
- Chaos forum: <https://forums.chaos.com/t/dlss5/124555>, <https://forums.chaos.com/t/dlss-5-implementation/191049>
- Community tools: <https://github.com/Merserk/dlss5-visual-enhancer>, <https://github.com/faisalkindi/DLSS5oneclick>, <https://github.com/praveenkumarappu/DLSS5ForUE5>
- Cosmos Transfer 2.5: <https://huggingface.co/nvidia/Cosmos-Transfer2.5-2B>
- Coverage: <https://www.techspot.com/news/113662-nvidia-dlss-5-getting-modded-about-every-game.html>, <https://www.xda-developers.com/i-tested-dlss-5-on-games-it-wasnt-designed-for-the-results-were-bizarre/>
