"""Builds the Play Store screenshots that show new screens.

Each composite reuses one of the existing store images as its template (same
dark ground, device frame and brand blobs), replaces the screen with a capture
from `test/render/store_screens_test.dart` (build/store/*.png, sample data in
the light theme) and sets a new headline and subtitle in Roboto Flex.

    flutter test test/render/store_screens_test.dart
    python tools/store_shots.py

Writes into play-store-screenshots/ and play-store-tab-screenshots/.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / 'assets/fonts/RobotoFlex-Variable.ttf'
CAPS = ROOT / 'build/store'
PHONE = ROOT / 'play-store-screenshots'
TAB7 = ROOT / 'play-store-tab-screenshots/7inch-screenshots'
TAB10 = ROOT / 'play-store-tab-screenshots/10inch-screenshots'

BG = (25, 18, 29)
LAVENDER = (221, 188, 255)
WHITE = (247, 236, 245)
SUB = (211, 194, 214)

# Screen area of each frame (left, top, right, bottom, corner radius) and the
# status bar strip kept from the template (px).
FRAMES = {
    'phone': ((308, 730, 1132, 2516), 64, 80),
    'tab7': ((325, 261, 1595, 1012), 22, 33),
    'tab10': ((998, 302, 2418, 1140), 24, 37),
}


def font(size, weight, opsz=None):
    f = ImageFont.truetype(str(FONT), size)
    # Optical size, weight and width; every other axis at the font's default.
    # Body text keeps the default optical size (sturdier, wider letters).
    axes = [a['default'] for a in f.get_variation_axes()]
    axes[0], axes[1], axes[3] = opsz or min(144, max(8, size)), weight, 100
    f.set_variation_by_axes(axes)
    return f


def tracked(draw, xy, text, f, fill, tracking):
    """Draws text with letter spacing (em); returns the end x."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=f, fill=fill, anchor='ls')
        x += f.getlength(ch) + tracking * f.size
    return x


def tracked_width(text, f, tracking):
    return sum(f.getlength(ch) + tracking * f.size for ch in text) - tracking * f.size


def wrap(text, f, width):
    lines, line = [], ''
    for word in text.split():
        trial = f'{line} {word}'.strip()
        if f.getlength(trial) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def clear(im, box):
    """Paints over old text with the ground blended from the box's edges, so a
    template's subtle gradient shows no seam."""
    l, t, r, b = box
    px = im.load()
    left = [px[l - 1, y] for y in range(t, b)]
    right = [px[r + 1, y] for y in range(t, b)]
    top = [px[x, t - 1] for x in range(l, r)]
    bottom = [px[x, b + 1] for x in range(l, r)]
    w, h = r - l, b - t
    for j in range(h):
        v = j / (h - 1)
        for i in range(w):
            u = i / (w - 1)
            px[l + i, t + j] = tuple(
                round(((1 - u) * left[j][k] + u * right[j][k] + (1 - v) * top[i][k] + v * bottom[i][k]) / 2)
                for k in range(3)
            )


def screen(im, kind, capture):
    (l, t, r, b), radius, strip = FRAMES[kind]
    w, h = r - l, b - t
    status = im.crop((l, t, r, t + strip))
    cap = Image.open(capture).convert('RGB').resize((w, h), Image.LANCZOS)
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius, fill=255)
    im.paste(cap, (l, t), mask)
    # The template's status bar (time, battery) stays.
    status_mask = mask.crop((0, 0, w, strip))
    im.paste(status, (l, t), status_mask)


def phone(template, capture, out, line1, line2, sub):
    im = Image.open(template).convert('RGB')
    d = ImageDraw.Draw(im)
    clear(im, (90, 130, 1360, 640))
    big = font(127, 1000)
    tracked(d, (116, 270), line1, big, LAVENDER, -0.015)
    tracked(d, (116, 400), line2, big, WHITE, -0.015)
    small = font(44, 400, opsz=14)
    for i, line in enumerate(wrap(sub, small, 1200)):
        d.text((114, 500 + i * 62), line, font=small, fill=SUB, anchor='ls')
    screen(im, 'phone', capture)
    im.save(out, optimize=True)


def tab7(template, capture, out, line1, line2, sub):
    im = Image.open(template).convert('RGB')
    d = ImageDraw.Draw(im)
    clear(im, (260, 30, 1660, 220))
    big = font(79, 1000)
    w1 = tracked_width(line1, big, -0.015)
    gap = big.getlength(' ')
    total = w1 + gap + tracked_width(line2, big, -0.015)
    x = 960 - total / 2
    x = tracked(d, (x, 116), line1, big, LAVENDER, -0.015)
    tracked(d, (x + gap, 116), line2, big, WHITE, -0.015)
    size = 30
    small = font(size, 400, opsz=14)
    while small.getlength(sub) > 1300 and size > 22:
        size -= 1
        small = font(size, 400, opsz=14)
    d.text((960, 182), sub, font=small, fill=SUB, anchor='ms')
    screen(im, 'tab7', capture)
    im.save(out, optimize=True)


def tab10(template, capture, out, line1, line2, sub):
    im = Image.open(template).convert('RGB')
    d = ImageDraw.Draw(im)
    clear(im, (110, 480, 880, 1000))
    big = font(115, 1000)
    tracked(d, (148, 602), line1, big, LAVENDER, -0.015)
    tracked(d, (148, 714), line2, big, WHITE, -0.015)
    small = font(40, 400, opsz=14)
    for i, line in enumerate(wrap(sub, small, 700)):
        d.text((148, 810 + i * 56), line, font=small, fill=SUB, anchor='ls')
    screen(im, 'tab10', capture)
    im.save(out, optimize=True)


TOOLS_SUB = 'Ping, traceroute, port scan, speed test, packet loss, LAN scan, Geo IP, monitoring and your router.'
ROUTER_SUB = (
    'See every device, switch Wi-Fi and the guest network, change the internet connection and restart it, '
    'right in Pulse.'
)
DEVICES_SUB = 'Live speed, signal and data used for everything on your network, as your router sees it.'


def main():
    # Phone: 8 shots. Packet loss and Geo IP make room for the router (both
    # still appear on the Tools shot); their images become the new templates.
    old = {p.name: p for p in PHONE.glob('*.png')}
    keep = {
        'pulse-01-ping.png': 'pulse-01-ping.png',
        'pulse-03-speed.png': 'pulse-05-speed.png',
        'pulse-04-trace.png': 'pulse-06-trace.png',
        'pulse-06-lan.png': 'pulse-07-lan.png',
        'pulse-08-monitor.png': 'pulse-08-monitor.png',
    }
    images = {name: Image.open(path).copy() for name, path in old.items()}
    for p in old.values():
        p.unlink()
    for src, dst in keep.items():
        images[src].save(PHONE / dst, optimize=True)
    tmp = ROOT / 'build/store/templates'
    tmp.mkdir(parents=True, exist_ok=True)
    for name in ('pulse-02-tools.png', 'pulse-05-loss.png', 'pulse-07-geo.png'):
        images[name].save(tmp / name)
    phone(tmp / 'pulse-02-tools.png', CAPS / 'phone-tools.png', PHONE / 'pulse-02-tools.png', '9 tools.', 'One app.', TOOLS_SUB)
    phone(tmp / 'pulse-05-loss.png', CAPS / 'phone-router.png', PHONE / 'pulse-03-router.png', 'Your router.', 'In your hand.', ROUTER_SUB)
    phone(tmp / 'pulse-07-geo.png', CAPS / 'phone-devices.png', PHONE / 'pulse-04-devices.png', 'Every device.', 'At a glance.', DEVICES_SUB)

    # 7-inch: the theme shot makes room for the router.
    t7 = {p.name: Image.open(p).copy() for p in TAB7.glob('*.png')}
    for p in TAB7.glob('*.png'):
        p.unlink()
    order7 = {
        'pulse-7in-01-ping.png': 'pulse-7in-01-ping.png',
        'pulse-7in-03-network.png': 'pulse-7in-04-network.png',
        'pulse-7in-04-ports.png': 'pulse-7in-05-ports.png',
        'pulse-7in-05-lan.png': 'pulse-7in-06-lan.png',
        'pulse-7in-06-alerts.png': 'pulse-7in-07-alerts.png',
        'pulse-7in-08-adaptive.png': 'pulse-7in-08-adaptive.png',
    }
    for src, dst in order7.items():
        t7[src].save(TAB7 / dst, optimize=True)
    t7['pulse-7in-02-tools.png'].save(tmp / '7-tools.png')
    t7['pulse-7in-07-theme.png'].save(tmp / '7-theme.png')
    tab7(tmp / '7-tools.png', CAPS / 'tab7-tools.png', TAB7 / 'pulse-7in-02-tools.png', '9 tools.', 'One app.', TOOLS_SUB)
    tab7(tmp / '7-theme.png', CAPS / 'tab7-router.png', TAB7 / 'pulse-7in-03-router.png', 'Your router.', 'In your hand.', ROUTER_SUB)

    # 10-inch: packet loss makes room for the router.
    t10 = {p.name: Image.open(p).copy() for p in TAB10.glob('*.png')}
    for p in TAB10.glob('*.png'):
        p.unlink()
    order10 = {
        'pulse-10in-01-ping.png': 'pulse-10in-01-ping.png',
        'pulse-10in-03-speed.png': 'pulse-10in-04-speed.png',
        'pulse-10in-04-trace.png': 'pulse-10in-05-trace.png',
        'pulse-10in-06-geo.png': 'pulse-10in-06-geo.png',
        'pulse-10in-07-monitor.png': 'pulse-10in-07-monitor.png',
        'pulse-10in-08-history.png': 'pulse-10in-08-history.png',
    }
    for src, dst in order10.items():
        t10[src].save(TAB10 / dst, optimize=True)
    t10['pulse-10in-02-tools.png'].save(tmp / '10-tools.png')
    t10['pulse-10in-05-loss.png'].save(tmp / '10-loss.png')
    tab10(tmp / '10-tools.png', CAPS / 'tab10-tools.png', TAB10 / 'pulse-10in-02-tools.png', '9 tools.', 'One app.', TOOLS_SUB)
    tab10(tmp / '10-loss.png', CAPS / 'tab10-router.png', TAB10 / 'pulse-10in-03-router.png', 'Your router.', 'In your hand.', ROUTER_SUB)


if __name__ == '__main__':
    main()
