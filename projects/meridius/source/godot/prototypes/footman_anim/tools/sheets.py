"""Contact sheets, GIFs and MP4s from captured frame folders.

  python -I sheets.py sheet <out.png> <cols> <dir> [<dir> ...]     every Nth frame of each dir, one row per dir
  python -I sheets.py grid <out.png> <rows: facing,...> <cols: clip,...> <pack dir> <frame>
  python -I sheets.py video <dir> <out.mp4|out.gif> [fps]
"""
import glob
import os
import subprocess
import sys

from PIL import Image, ImageDraw

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")


def frames(d):
    return sorted(glob.glob(os.path.join(d, "*.png")))


def sheet(out, cols, dirs, crop=None, tw=220):
    rows = []
    for d in dirs:
        fs = frames(d)
        if not fs:
            continue
        step = max(1, len(fs) // cols)
        pick = fs[::step][:cols]
        rows.append((os.path.basename(d.rstrip("/\\")), pick))
    if not rows:
        return
    im0 = Image.open(rows[0][1][0])
    k = tw / im0.width
    th = int(im0.height * k)
    S = Image.new("RGB", (tw * cols + 130, (th + 4) * len(rows)), (24, 26, 30))
    dr = ImageDraw.Draw(S)
    for r, (name, pick) in enumerate(rows):
        dr.text((6, r * (th + 4) + 6), name, fill=(240, 220, 160))
        for c, f in enumerate(pick):
            im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
            S.paste(im, (130 + c * tw, r * (th + 4)))
            dr.text((130 + c * tw + 4, r * (th + 4) + 4), os.path.basename(f)[:-4], fill=(255, 255, 255))
    S.save(out)
    print(out, S.size)


def video(d, out, fps):
    pattern = os.path.join(d, "%04d.png")
    if out.endswith(".gif"):
        cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", pattern,
               "-vf", "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4", "-loop", "0", out]
    else:
        cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", pattern,
               "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    print(out)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sheet":
        sheet(sys.argv[2], int(sys.argv[3]), sys.argv[4:])
    elif mode == "video":
        video(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 30)
