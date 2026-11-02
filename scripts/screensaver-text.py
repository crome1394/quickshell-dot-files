#!/usr/bin/env python3
"""Text screensaver for the Odyssey G9. Stdlib only. No video file.

Styles: night (starfield), rain (columns), orbital (rings).
A big 24-hour clock sits in the middle. Quit on a key, a click, or a
pointer move after a short grace period, or on SIGTERM.
"""

from __future__ import annotations

import argparse
import datetime
import math
import os
import select
import shutil
import signal
import struct
import sys
import termios
import time
import tty

BG = (0x0A, 0x0E, 0x16)
TEXT = (0xF0, 0xF4, 0xFC)
SUB = (0xA8, 0xB4, 0xC8)
SLATE = (0x6E, 0x7A, 0x90)
TEAL = (0x00, 0xF0, 0xE0)
MAGENTA = (0xFF, 0x3D, 0x8A)

C_BG, C_TEXT, C_SUB, C_SLATE, C_TEAL, C_MAG = range(6)
C_TEAL_RAMP = 6
C_MAG_RAMP = 14


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


PALETTE = [BG, TEXT, SUB, SLATE, TEAL, MAGENTA]
for _i in range(8):
    PALETTE.append(_mix(TEAL, BG, _i / 7))
for _i in range(8):
    PALETTE.append(_mix(MAGENTA, BG, _i / 7))

# Instrument and pyro colors. Indices follow the ramps above.
C_AMBER, C_AMBER_DIM, C_AMBER_FAINT = 22, 23, 24
C_GOLD, C_CORAL, C_ICE, C_VIOLET = 25, 26, 27, 28
C_EMBER, C_HOT, C_STAR, C_PLANET = 29, 30, 31, 32
PALETTE.extend([
    (0xE2, 0xB0, 0x5A),
    (0x8C, 0x68, 0x32),
    (0x3E, 0x2E, 0x1C),
    (0xE6, 0xC3, 0x6A),
    (0xD0, 0x72, 0x58),
    (0x8E, 0xC8, 0xD0),
    (0xB0, 0x96, 0xD0),
    (0x6A, 0x40, 0x2C),
    (0xF6, 0xF1, 0xE4),
    (0xD8, 0xE4, 0xF0),
    (0x6A, 0x74, 0x80),
])

PYRO_COLORS = (C_GOLD, C_CORAL, C_ICE, C_VIOLET)


class Settings:
    def __init__(self, clock=True, warp_speed=4, warp_density=5, warp_streak=6):
        self.clock = bool(clock)
        self.warp_speed = max(1, min(10, int(warp_speed)))
        self.warp_density = max(1, min(10, int(warp_density)))
        self.warp_streak = max(1, min(10, int(warp_streak)))

# 5x7 digits. Colon is 3x7.
FONT = {
    "0": ("11111", "10001", "10001", "10001", "10001", "10001", "11111"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("11111", "00001", "00001", "11111", "10000", "10000", "11111"),
    "3": ("11111", "00001", "00001", "11111", "00001", "00001", "11111"),
    "4": ("10001", "10001", "10001", "11111", "00001", "00001", "00001"),
    "5": ("11111", "10000", "10000", "11111", "00001", "00001", "11111"),
    "6": ("11111", "10000", "10000", "11111", "10001", "10001", "11111"),
    "7": ("11111", "00001", "00010", "00100", "00100", "00100", "00100"),
    "8": ("11111", "10001", "10001", "11111", "10001", "10001", "11111"),
    "9": ("11111", "10001", "10001", "11111", "00001", "00001", "11111"),
    ":": ("0", "1", "1", "0", "1", "1", "0"),
}

LINES = (
    "the link stays up",
    "ten minutes of quiet",
    "still here when you are",
    "the room can wait",
    "nothing asked of you",
    "screen awake, hands idle",
    "a wide dark, on purpose",
    "back when you move",
)

RAIN_GLYPHS = "0123456789ABCDEF+*:"


class Grid:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        n = w * h
        self.ch = [" "] * n
        self.fg = bytearray(n)

    def put(self, x, y, ch, fg):
        if 0 <= x < self.w and 0 <= y < self.h and ch:
            i = y * self.w + x
            self.ch[i] = ch
            self.fg[i] = fg

    def erase(self, x0, y0, x1, y1):
        x0 = max(0, x0)
        y0 = max(0, y0)
        x1 = min(self.w, x1)
        y1 = min(self.h, y1)
        for y in range(y0, y1):
            row = y * self.w
            for x in range(x0, x1):
                self.ch[row + x] = " "
                self.fg[row + x] = 0


def term_size():
    try:
        packed = struct.unpack(
            "HHHH",
            __import__("fcntl").ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\x00" * 8),
        )
        rows, cols = packed[0], packed[1]
        if cols >= 20 and rows >= 8:
            return cols, rows
    except (OSError, AttributeError):
        pass
    size = shutil.get_terminal_size(fallback=(80, 24))
    return max(20, size.columns), max(8, size.lines)


def clock_layout(cols, rows):
    scale = max(1, min((cols - 4) // 32, (rows - 6) // 9))
    gap = scale
    # 4 digits * 5 + colon * 1 + 4 gaps, in unscaled cells, then * scale.
    width = (4 * 5 + 1 + 4) * scale
    height = 7 * scale
    x = max(0, (cols - width) // 2)
    y = max(0, (rows - height) // 2 - 2)
    return scale, x, y, width, height


def draw_clock(grid, cols, rows, stamp):
    scale, x, y, width, height = clock_layout(cols, rows)
    cursor = x
    for ch in stamp:
        bmp = FONT[ch]
        gw = len(bmp[0])
        for ry, row in enumerate(bmp):
            for rx, bit in enumerate(row):
                if bit != "1":
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        grid.put(cursor + rx * scale + dx, y + ry * scale + dy, "█", C_TEXT)
        cursor += gw * scale + scale
    return x, y, x + width, y + height


def draw_center(grid, y, text, fg):
    if y < 0 or y >= grid.h or not text:
        return
    x = max(0, (grid.w - len(text)) // 2)
    for i, ch in enumerate(text):
        if x + i >= grid.w:
            break
        grid.put(x + i, y, ch, fg)


def date_line(when):
    return f"{when.strftime('%A')}, {when.strftime('%m')}·{when.strftime('%d')}·{when.strftime('%Y')}"


def paint_night(grid, t):
    cols, rows = grid.w, grid.h
    n = max(40, min(180, (cols * rows) // 80))
    for i in range(n):
        ang = (i * 2.399963) % math.tau
        speed = 0.035 + (i % 5) * 0.016
        rad = ((i * 0.137) + t * speed) % 1.2
        x = int(cols / 2 + math.cos(ang) * rad * cols * 0.48)
        y = int(rows / 2 + math.sin(ang) * rad * rows * 0.46)
        if rad < 0.28:
            glyph, fg = "·", C_SLATE
        elif rad < 0.6:
            glyph, fg = "+", C_SUB
        elif rad < 0.9:
            glyph, fg = "*", C_TEXT
        else:
            glyph, fg = "*", C_TEAL
        if i % 29 == 0 and rad > 0.72:
            fg = C_MAG
        grid.put(x, y, glyph, fg)


def paint_rain(grid, t):
    cols, rows = grid.w, grid.h
    glyphs = RAIN_GLYPHS
    for x in range(cols):
        if x % 5 == 0:
            continue
        speed = 7 + (x % 9) * 2.4
        length = 8 + (x % 13)
        head = (t * speed + x * 3.1) % (rows + length)
        magenta = x % 23 == 0
        ramp = C_MAG_RAMP if magenta else C_TEAL_RAMP
        for i in range(length):
            y = int(head - i)
            if y < 0 or y >= rows:
                continue
            step = min(7, int(i * 7 / max(1, length - 1)))
            ch = glyphs[(x + y) % len(glyphs)]
            grid.put(x, y, ch, ramp + step)


def paint_orbital(grid, t):
    cols, rows = grid.w, grid.h
    cx = cols / 2
    cy = rows / 2
    rings = (
        (0.22, 0.30, 0.40, 36, C_SLATE, "·", 0.0),
        (0.34, 0.46, -0.25, 48, C_TEAL, "·", 1.2),
        (0.46, 0.60, 0.16, 64, C_SUB, "+", 2.4),
        (0.58, 0.74, -0.11, 80, C_SLATE, "·", 0.6),
    )
    for rx, ry, speed, count, fg, glyph, phase in rings:
        for i in range(count):
            ang = phase + t * speed + i * math.tau / count
            x = int(cx + math.cos(ang) * rx * cols * 0.5)
            y = int(cy + math.sin(ang) * ry * rows * 0.5)
            color = C_MAG if i % 17 == 0 else fg
            grid.put(x, y, glyph, color)


def _lens(x, y, cx, cy, rx, ry):
    if rx <= 0 or ry <= 0:
        return 99.0
    nx = (x - cx) / rx
    ny = (y - cy) / ry
    return nx * nx + ny * ny


def paint_warp(grid, t, settings):
    """Stars coming at the viewer. Speed, density, and streak length are 1–10."""
    cols, rows = grid.w, grid.h
    cx = cols / 2
    cy = rows / 2
    n = 24 + settings.warp_density * 30
    spd = 0.04 + settings.warp_speed * 0.055
    for i in range(n):
        ang = (i * 2.399963) % math.tau
        z0 = (i * 0.173) % 1.0
        z = (z0 - (t * spd) % 1.0) % 1.0
        z = 0.06 + z * 0.94
        near = 1.0 - z
        x = cx + math.cos(ang) * near * cols * 0.52
        y = cy + math.sin(ang) * near * rows * 0.50
        length = max(1, int(near * (0.6 + settings.warp_streak * 0.55)))
        if near > 0.82:
            head, fg = "*", C_HOT
        elif near > 0.55:
            head, fg = "+", C_STAR
        elif near > 0.28:
            head, fg = "+", C_SUB
        else:
            head, fg = "·", C_SLATE
        dx = math.cos(ang)
        dy = math.sin(ang)
        for s in range(length):
            fade = s / length
            px = int(x - dx * s * 1.7)
            py = int(y - dy * s * 0.85)
            glyph = "·" if fade > 0.45 else head
            color = C_SLATE if fade > 0.45 else fg
            grid.put(px, py, glyph, color)


def paint_pyro(grid, t):
    """A few shells. Gold, coral, ice, and violet, then they fall away."""
    cols, rows = grid.w, grid.h
    for i in range(4):
        period = 4.2 + (i % 3) * 0.9
        local = (t + i * 2.05) % period
        rise = period * 0.40
        x = cols * (0.16 + ((i * 0.23) % 0.68))
        apex = rows * (0.20 + (i % 3) * 0.09)
        color = PYRO_COLORS[i % 4]
        if local < rise:
            p = local / rise
            y = (rows - 1) - p * ((rows - 1) - apex)
            grid.put(int(x), int(y), "*", C_HOT if p > 0.75 else color)
            grid.put(int(x), int(y) + 1, "·", C_EMBER)
            if p > 0.2:
                grid.put(int(x), int(y) + 2, "·", C_AMBER_FAINT)
            continue
        age = (local - rise) / max(0.2, period - rise)
        if age >= 1:
            continue
        spokes = 14 + (i % 3) * 4
        radius = age * (4.5 + (i % 4))
        for k in range(spokes):
            ang = (k + i * 0.37) / spokes * math.tau
            wobble = 1.0 + 0.18 * math.sin(k * 1.7 + i)
            px = x + math.cos(ang) * radius * wobble * 2.2
            py = apex + math.sin(ang) * radius * wobble * 0.85 + (age * age) * rows * 0.10
            if age < 0.18:
                glyph, fg = "*", C_HOT
            elif age < 0.55:
                glyph, fg = "+", color
            else:
                glyph, fg = "·", color
            grid.put(int(px), int(py), glyph, fg)
            if k % 5 == 0 and age > 0.3:
                grid.put(int(px), int(py + age * 5), "·", C_EMBER)


def paint_scanner(grid, t):
    """Look through a slewing ship scanner: lens, range rings, limb, telemetry.

    Original picture. No title card and no show logo.
    """
    cols, rows = grid.w, grid.h
    cx = cols / 2.0
    cy = rows / 2.0
    rx = cols * 0.46
    ry = max(4.0, rows * 0.44)
    yaw = math.sin(t * 0.17) * 8.0
    pitch = math.sin(t * 0.11) * 2.5
    n = max(70, min(240, (cols * rows) // 55))
    for i in range(n):
        bx = (i * 19.7 + t * (4.5 + (i % 5)) + yaw) % cols
        by = (i * 7.3 + t * (0.35 + (i % 3) * 0.15) + pitch) % rows
        if _lens(bx, by, cx, cy, rx, ry) > 0.94:
            continue
        depth = (i % 8) / 7.0
        if depth > 0.86:
            glyph, fg = "*", C_HOT
        elif depth > 0.55:
            glyph, fg = "+", C_STAR
        else:
            glyph, fg = "·", C_SLATE
        if int(by) % 3 == 0 and fg != C_HOT:
            fg = C_AMBER_FAINT
        grid.put(int(bx), int(by), glyph, fg)

    for k in range(180):
        ang = k / 180.0 * math.tau
        grid.put(int(cx + math.cos(ang) * rx), int(cy + math.sin(ang) * ry), "·", C_AMBER_DIM)

    for ri, base in enumerate((0.30, 0.52, 0.74)):
        rad = base + 0.025 * math.sin(t * (0.35 + ri * 0.17) + ri)
        steps = int(36 + 70 * rad)
        fg = C_AMBER_DIM if ri == 1 else C_AMBER_FAINT
        for k in range(steps):
            ang = k / steps * math.tau
            grid.put(
                int(cx + math.cos(ang) * rx * rad),
                int(cy + math.sin(ang) * ry * rad),
                "·",
                fg,
            )

    hx = cx + math.sin(t * 0.23) * rx * 0.08
    hy = cy + math.cos(t * 0.19) * ry * 0.07
    x0 = int(hx - rx * 0.5)
    x1 = int(hx + rx * 0.5)
    for x in range(x0, x1 + 1, 2):
        if _lens(x, hy, cx, cy, rx, ry) < 0.88:
            grid.put(x, int(hy), "-", C_AMBER)
    y0 = int(hy - ry * 0.5)
    y1 = int(hy + ry * 0.5)
    for y in range(y0, y1 + 1, 2):
        if _lens(hx, y, cx, cy, rx, ry) < 0.88:
            grid.put(int(hx), y, "|", C_AMBER)
    grid.put(int(hx), int(hy), "+", C_AMBER)

    sang = t * 0.62
    for s in range(1, 26):
        p = s / 26.0
        x = hx + math.cos(sang) * rx * 0.72 * p
        y = hy + math.sin(sang) * ry * 0.72 * p
        if _lens(x, y, cx, cy, rx, ry) < 0.90:
            grid.put(int(x), int(y), "·", C_AMBER if s > 18 else C_AMBER_DIM)

    bank = 0.58 + 0.07 * math.sin(t * 0.21)
    tilt = math.sin(t * 0.13) * 0.10
    for x in range(cols):
        nx = (x - cx) / rx
        if abs(nx) > 1:
            continue
        ny = bank + tilt * nx
        y = int(cy + ny * ry)
        for dy, ch, fg in ((0, "▓", C_PLANET), (1, "▄", C_AMBER_FAINT), (2, "·", C_AMBER_FAINT)):
            yy = y + dy
            if _lens(x, yy, cx, cy, rx, ry) <= 1.0:
                grid.put(x, yy, ch, fg)

    tx = int(min(cols - 5, cx + rx * 0.58))
    base_y = int(cy - ry * 0.42)
    for row in range(6):
        y = base_y + row * 2
        if y < 0 or y >= rows:
            continue
        num = int(abs(math.sin(t * 0.7 + row * 1.3)) * 9000 + (t * 13 + row * 97)) % 10000
        for i, ch in enumerate(f"{num:04d}"):
            if _lens(tx + i, y, cx, cy, rx, ry) < 0.96:
                grid.put(tx + i, y, ch, C_AMBER_DIM)

    # Viewfinder corners, inside the lens, not a logo.
    span = max(2, int(min(rx, ry) * 0.12))
    for ox, oy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        ax = int(cx + ox * rx * 0.62)
        ay = int(cy + oy * ry * 0.62)
        for s in range(span):
            grid.put(ax + ox * s, ay, "-", C_AMBER)
            grid.put(ax, ay + oy * s, "|", C_AMBER)


def render(style, cols, rows, t, when, settings=None):
    if settings is None:
        settings = Settings()
    grid = Grid(cols, rows)
    if style == "rain":
        paint_rain(grid, t)
    elif style == "orbital":
        paint_orbital(grid, t)
    elif style == "warp":
        paint_warp(grid, t, settings)
    elif style == "pyro":
        paint_pyro(grid, t)
    elif style == "scanner":
        paint_scanner(grid, t)
    else:
        paint_night(grid, t)

    if not settings.clock:
        return grid

    stamp = when.strftime("%H:%M")
    x0, y0, x1, y1 = draw_clock(grid, cols, rows, stamp)
    date_y = y1 + 1
    line_y = date_y + 1
    if style == "rain":
        grid.erase(0, y0 - 1, cols, date_y + 2)
        draw_clock(grid, cols, rows, stamp)
    elif style in ("night", "warp", "pyro", "scanner"):
        grid.erase(x0 - 3, y0 - 1, x1 + 3, line_y + 2)
        draw_clock(grid, cols, rows, stamp)
    else:
        grid.erase(x0 - 2, y0 - 1, x1 + 2, y1 + 1)
        draw_clock(grid, cols, rows, stamp)

    draw_center(grid, date_y, date_line(when), C_SUB)
    if style == "night":
        line = LINES[int(t // 20) % len(LINES)]
        draw_center(grid, line_y, line, C_SLATE)
    return grid


def frame_ansi(grid):
    parts = ["\x1b[?2026h"]
    w = grid.w
    codes = []
    for rgb in PALETTE:
        codes.append(f"\x1b[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m")
    for y in range(grid.h):
        parts.append(f"\x1b[{y + 1};1H")
        prev = -1
        run = []
        row = y * w

        def flush(prev_fg, run_chars, parts=parts, codes=codes):
            if not run_chars:
                return
            parts.append(codes[prev_fg])
            parts.append("".join(run_chars))

        for x in range(w):
            i = row + x
            fg = grid.fg[i]
            if fg != prev:
                flush(prev, run)
                run = []
                prev = fg
            run.append(grid.ch[i])
        flush(prev, run)
    parts.append("\x1b[?2026l")
    return "".join(parts)


class Input:
    def __init__(self):
        self.buf = bytearray()
        self.origin = None
        self.grace_until = time.monotonic() + 1.0

    def feed(self, data):
        self.buf.extend(data)
        return self._parse()

    def _parse(self):
        buf = self.buf
        i = 0
        n = len(buf)
        quit = False
        in_grace = time.monotonic() < self.grace_until
        while i < n and not quit:
            if buf[i] != 0x1B:
                if not in_grace:
                    quit = True
                i += 1
                continue
            if i + 1 >= n:
                break
            if buf[i + 1] != ord("["):
                if not in_grace:
                    quit = True
                i += 2
                continue
            if i + 2 < n and buf[i + 2] == ord("<"):
                vals = []
                num = None
                j = i + 3
                done = False
                while j < n:
                    c = buf[j]
                    if c == ord(";") or c in (ord("M"), ord("m")):
                        if num is None:
                            j = n
                            break
                        vals.append(num)
                        num = None
                        j += 1
                        if c in (ord("M"), ord("m")):
                            done = True
                            if not in_grace and len(vals) == 3:
                                quit = self._mouse(vals[0], vals[1], vals[2], c == ord("M"))
                            break
                        continue
                    if 48 <= c <= 57:
                        num = (0 if num is None else num) * 10 + (c - 48)
                        j += 1
                        continue
                    j = n
                    break
                if not done:
                    break
                i = j
                continue
            j = i + 2
            while j < n and not (0x40 <= buf[j] <= 0x7E):
                j += 1
            if j >= n:
                break
            i = j + 1
        del buf[:i]
        return quit

    def _mouse(self, btn, x, y, pressed):
        move = (btn & 32) != 0
        if move:
            if self.origin is None:
                self.origin = (x, y)
                return False
            dx = abs(x - self.origin[0])
            dy = abs(y - self.origin[1])
            return dx > 2 or dy > 2
        return pressed and (btn & 3) <= 2


def enter_term(fd):
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    sys.stdout.write("\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[?1000h\x1b[?1003h\x1b[?1006h")
    sys.stdout.flush()
    return old


def leave_term(fd, old):
    sys.stdout.write("\x1b[?1003l\x1b[?1006l\x1b[?1000l\x1b[?7h\x1b[?25h\x1b[?1049l")
    sys.stdout.flush()
    if old is not None:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def run(style, settings):
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("screensaver-text: need a tty", file=sys.stderr)
        return 1
    fd = sys.stdin.fileno()
    old = None
    stop = False

    def _stop(_sig, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    try:
        old = enter_term(fd)
        reader = Input()
        started = time.monotonic()
        cols, rows = term_size()
        while not stop:
            now = time.monotonic()
            cols, rows = term_size()
            grid = render(style, cols, rows, now - started, datetime.datetime.now(), settings)
            sys.stdout.write(frame_ansi(grid))
            sys.stdout.flush()
            timeout = 1 / 16
            try:
                ready, _, _ = select.select([fd], [], [], timeout)
            except InterruptedError:
                continue
            if not ready:
                continue
            try:
                data = os.read(fd, 8192)
            except OSError:
                break
            if not data or reader.feed(data):
                break
    finally:
        if old is not None:
            leave_term(fd, old)
    return 0


def _field_marks(grid, rows):
    n = 0
    for y in range(min(rows, grid.h)):
        row = y * grid.w
        for ch in grid.ch[row:row + grid.w]:
            if ch not in (" ", "█"):
                n += 1
    return n


def self_test():
    when = datetime.datetime(2026, 10, 27, 12, 34, 5)
    styles = ("night", "rain", "orbital", "warp", "pyro", "scanner")
    for style in styles:
        grid = render(style, 120, 40, 8.0, when)
        blocks = sum(ch == "█" for ch in grid.ch)
        if blocks < 40:
            raise SystemExit(f"{style}: clock too thin ({blocks} blocks)")
        text = "".join(grid.ch)
        if "10·27·2026" not in text:
            raise SystemExit(f"{style}: date missing")
        if _field_marks(grid, 8) < 3 and style != "pyro":
            raise SystemExit(f"{style}: field too empty above the clock")
        ansi = frame_ansi(grid)
        if "\x1b[38;2;" not in ansi or "█" not in ansi:
            raise SystemExit(f"{style}: ansi frame missing color or clock")
        quiet = render(style, 120, 40, 8.0, when, Settings(clock=False))
        quiet_text = "".join(quiet.ch)
        if "█" in quiet_text or "10·27·2026" in quiet_text:
            raise SystemExit(f"{style}: clock still drawn when disabled")
        if sum(ch != " " for ch in quiet.ch) < 8:
            raise SystemExit(f"{style}: empty with the clock off")
    fast = render("warp", 100, 30, 3.0, when, Settings(clock=False, warp_speed=10, warp_density=10, warp_streak=10))
    slow = render("warp", 100, 30, 3.0, when, Settings(clock=False, warp_speed=1, warp_density=1, warp_streak=1))
    if sum(ch != " " for ch in fast.ch) <= sum(ch != " " for ch in slow.ch):
        raise SystemExit("warp density did not add stars")
    print("self-test ok")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description="Text screensaver")
    parser.add_argument(
        "--style",
        choices=("night", "rain", "orbital", "warp", "pyro", "scanner"),
        default="night",
    )
    parser.add_argument("--clock", type=int, default=1)
    parser.add_argument("--warp-speed", type=int, default=4)
    parser.add_argument("--warp-density", type=int, default=5)
    parser.add_argument("--warp-streak", type=int, default=6)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    settings = Settings(args.clock, args.warp_speed, args.warp_density, args.warp_streak)
    if args.self_test:
        return self_test()
    return run(args.style, settings)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
