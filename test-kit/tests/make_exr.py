"""Write small uncompressed float32 OpenEXR test fixtures with the standard library only.

Used by test_converter.py. Can also be run directly:  python make_exr.py OUT_DIR
"""
import os
import struct
import sys

# Known linear values in still.exr and where to find them (x, y).
GREY_05 = (100, 100)      # linear 0.5
GREY_018 = (300, 100)     # linear 0.18
HIGHLIGHT_4 = (500, 100)  # linear 4.0 (above white)
RED_05 = (160, 330)       # red ramp: R = 0.5, G = B = 0
RED_10 = (320, 330)       # red ramp: R = 1.0, G = B = 0


def _attr(name, typ, data):
    return name.encode() + b"\0" + typ.encode() + b"\0" + struct.pack("<i", len(data)) + data


def write_exr(path, w, h, channels):
    """channels: dict of channel name -> function(x, y) -> float. FLOAT pixels, NO_COMPRESSION, scanlines."""
    names = sorted(channels)  # OpenEXR stores channels in alphabetical order
    chlist = b"".join(n.encode() + b"\0" + struct.pack("<iBxxxii", 2, 0, 1, 1) for n in names) + b"\0"
    box = struct.pack("<iiii", 0, 0, w - 1, h - 1)
    header = b"".join([
        struct.pack("<ii", 20000630, 2),
        _attr("channels", "chlist", chlist),
        _attr("compression", "compression", b"\0"),
        _attr("dataWindow", "box2i", box),
        _attr("displayWindow", "box2i", box),
        _attr("lineOrder", "lineOrder", b"\0"),
        _attr("pixelAspectRatio", "float", struct.pack("<f", 1.0)),
        _attr("screenWindowCenter", "v2f", struct.pack("<ff", 0, 0)),
        _attr("screenWindowWidth", "float", struct.pack("<f", 1.0)),
        b"\0",
    ])
    line_bytes = 4 * w * len(names)
    first = len(header) + 8 * h
    offsets = b"".join(struct.pack("<Q", first + y * (8 + line_bytes)) for y in range(h))
    with open(path, "wb") as f:
        f.write(header)
        f.write(offsets)
        for y in range(h):
            f.write(struct.pack("<ii", y, line_bytes))
            for n in names:
                fn = channels[n]
                f.write(struct.pack("<%df" % w, *(fn(x, y) for x in range(w))))


def _still_value(x, y, c):
    # Bottom strip: red ramp 0..2. Above it: 0.5 | 0.18 | 4.0 neutral patches.
    if y >= 300:
        return (x / 640.0) * 2.0 if c == "R" else 0.0
    if x < 213:
        return 0.5
    if x < 427:
        return 0.18
    return 4.0


def make_fixtures(out):
    """Create the fixture set in OUT and return a dict of paths."""
    stills = os.path.join(out, "stills")
    seq = os.path.join(out, "shot 010")
    os.makedirs(stills, exist_ok=True)
    os.makedirs(seq, exist_ok=True)

    # 641 x 361 on purpose: odd sizes exercise the even-size padding of movies.
    ch = {c: (lambda x, y, c=c: _still_value(x, y, c)) for c in "RGB"}
    ch["A"] = lambda x, y: 1.0
    ch["VRayVelocity.R"] = lambda x, y: 3.0
    ch["VRayVelocity.G"] = lambda x, y: -2.0
    ch["VRayVelocity.B"] = lambda x, y: 0.0
    still = os.path.join(stills, "ext day.exr")
    write_exr(still, 641, 361, ch)

    layer = os.path.join(stills, "int_layer.exr")
    write_exr(layer, 320, 180, {
        "Beauty.R": lambda x, y: 0.2, "Beauty.G": lambda x, y: 0.5, "Beauty.B": lambda x, y: 0.8})

    for i in range(1, 6):
        bar = 40 + i * 40
        f = lambda x, y, bar=bar: 1.0 if bar <= x < bar + 30 else 0.05
        write_exr(os.path.join(seq, "shot_%04d.exr" % i), 320, 180, {"R": f, "G": f, "B": f})
    return {"stills": stills, "still": still, "layer": layer, "sequence": seq}


if __name__ == "__main__":
    print(make_fixtures(sys.argv[1]))
