"""Regression test for Convert-ExrToTiff.ps1.

Builds synthetic EXRs with known linear values, runs the converter in Windows PowerShell 5.1
and (if installed) PowerShell 7, and checks the 16-bit output pixels against the sRGB formula.

Needs: Python 3.8+ (standard library only), ffmpeg + ffprobe (PATH or C:\\ffmpeg\\bin), Windows.
Run:   python test-kit\\tests\\test_converter.py        (exit code 0 = all passed)
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_exr as fx  # noqa: E402

SCRIPT = os.path.normpath(os.path.join(HERE, "..", "Convert-ExrToTiff.ps1"))
TOL = 8  # 16-bit code values; float rounding in zscale/ffmpeg stays well inside this


def find_tool(name):
    found = shutil.which(name)
    if found:
        return found
    candidate = os.path.join("C:\\ffmpeg\\bin", name + ".exe")
    return candidate if os.path.exists(candidate) else None


FFMPEG, FFPROBE = find_tool("ffmpeg"), find_tool("ffprobe")


def srgb16(linear):
    v = max(0.0, min(1.0, linear))
    s = v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return round(s * 65535)


def pixels(path, width, points):
    raw = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-i", path, "-frames:v", "1",
                          "-f", "rawvideo", "-pix_fmt", "rgb48le", "-"], capture_output=True, check=True).stdout
    return [struct.unpack_from("<HHH", raw, (y * width + x) * 6) for x, y in points]


def probe(path, entries, count=False):
    args = [FFPROBE, "-v", "error"] + (["-count_frames"] if count else []) + [
        "-show_entries", "stream=" + entries, "-of", "default=nw=1:nk=1", path]
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout.split()


class Checker:
    def __init__(self, shell):
        self.shell, self.failed, self.passed = shell, 0, 0

    def check(self, label, ok, detail=""):
        if ok:
            self.passed += 1
        else:
            self.failed += 1
            print("  FAIL %s %s" % (label, detail))

    def near(self, label, got, want):
        self.check(label, all(abs(g - w) <= TOL for g, w in zip(got, want)), "got %s want %s" % (got, want))

    def run(self, *args):
        if os.path.basename(self.shell).lower().startswith("powershell"):
            cmd = [self.shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SCRIPT]
        else:
            cmd = [self.shell, "-NoProfile", "-File", SCRIPT]
        return subprocess.run(cmd + list(args), capture_output=True, text=True)


def run_suite(shell, work):
    c = Checker(shell)
    f = fx.make_fixtures(work)
    grey05, grey018, white = srgb16(0.5), srgb16(0.18), 65535

    # Stills: plain sRGB, main RGB channels and a named layer, review PNGs.
    r = c.run(f["stills"])
    c.check("stills exit code", r.returncode == 0, r.stdout + r.stderr)
    out = os.path.join(f["stills"], "dlss5-test")
    tif = os.path.join(out, "for-tool", "ext day.tif")
    png = os.path.join(out, "for-review", "ext day.png")
    if os.path.exists(tif) and os.path.exists(png):
        px = pixels(tif, 641, [fx.GREY_05, fx.GREY_018, fx.HIGHLIGHT_4, fx.RED_05, fx.RED_10])
        c.near("0.5 grey", px[0], (grey05,) * 3)
        c.near("0.18 grey", px[1], (grey018,) * 3)
        c.near("4.0 clips to white", px[2], (white,) * 3)
        c.check("red ramp keeps G and B at 0", px[3][1:] == (0, 0) and px[4][1:] == (0, 0), str(px[3:]))
        c.near("red 0.5", px[3][:1], (grey05,))
        c.check("review PNG matches TIFF", pixels(png, 641, [fx.GREY_05, fx.RED_05]) == [px[0], px[3]])
        c.check("TIFF is 16-bit RGB", probe(tif, "pix_fmt") == ["rgb48le"], str(probe(tif, "pix_fmt")))
    else:
        c.check("stills outputs exist", False, tif)
    ltif = os.path.join(out, "for-tool", "int_layer.tif")
    if os.path.exists(ltif):
        c.near("Beauty layer picked automatically", pixels(ltif, 320, [(10, 10)])[0],
               (srgb16(0.2), srgb16(0.5), srgb16(0.8)))
    else:
        c.check("layer output exists", False, ltif)

    # Exposure, roll-off and alpha.
    opt = os.path.join(work, "opts")
    r = c.run(f["still"], "-OutputDir", opt, "-Exposure", "1")
    c.check("exposure exit code", r.returncode == 0, r.stdout + r.stderr)
    c.near("exposure +1 on 0.18", pixels(os.path.join(opt, "for-tool", "ext day.tif"), 641, [fx.GREY_018])[0],
           (srgb16(0.36),) * 3)
    r = c.run(f["still"], "-OutputDir", opt, "-ToneMap", "rolloff", "-WhitePoint", "4", "-KeepAlpha")
    c.check("rolloff exit code", r.returncode == 0, r.stdout + r.stderr)
    rtif = os.path.join(opt, "for-tool", "ext day.tif")
    px = pixels(rtif, 641, [fx.GREY_05, fx.GREY_018, fx.HIGHLIGHT_4])
    c.near("rolloff keeps 0.18", px[1], (grey018,) * 3)
    c.check("rolloff compresses 0.5", px[0][0] < grey05 - 200, str(px[0]))
    c.near("rolloff maps the white point to white", px[2], (white,) * 3)
    c.check("KeepAlpha writes RGBA", probe(rtif, "pix_fmt") == ["rgba64le"], str(probe(rtif, "pix_fmt")))

    # Bad layer fails cleanly.
    r = c.run(f["still"], "-OutputDir", opt, "-Layer", "Nope")
    c.check("unknown layer gives exit code 1", r.returncode == 1, str(r.returncode))

    # Sequence: TIFF frames and a 5-frame movie.
    r = c.run(f["sequence"], "-Sequence", "-Fps", "30")
    c.check("sequence exit code", r.returncode == 0, r.stdout + r.stderr)
    sout = os.path.join(work, "dlss5-test")
    movie = os.path.join(sout, "for-review", "shot 010.mp4")
    frames = os.path.join(sout, "for-tool", "shot 010_frames")
    c.check("5 TIFF frames", os.path.isdir(frames) and len(os.listdir(frames)) == 5)
    if os.path.exists(movie):
        c.check("movie has 5 frames at 30 fps", probe(movie, "nb_read_frames,r_frame_rate", count=True) == ["30/1", "5"],
                str(probe(movie, "nb_read_frames,r_frame_rate", count=True)))
    else:
        c.check("movie exists", False, movie)
    return c


def main():
    if os.name != "nt":
        print("This test needs Windows (PowerShell + the converter script).")
        return 2
    if not FFMPEG or not FFPROBE:
        print("ffmpeg/ffprobe not found on PATH or in C:\\ffmpeg\\bin.")
        return 2
    shells = [s for s in (shutil.which("powershell"), shutil.which("pwsh")) if s]
    total_failed = 0
    for shell in shells:
        work = tempfile.mkdtemp(prefix="dlss5kit test ")
        try:
            print("== %s" % shell)
            c = run_suite(shell, work)
            print("  %d passed, %d failed" % (c.passed, c.failed))
            total_failed += c.failed
        finally:
            shutil.rmtree(work, ignore_errors=True)
    print("ALL PASSED" if total_failed == 0 else "%d FAILED" % total_failed)
    return 0 if total_failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
