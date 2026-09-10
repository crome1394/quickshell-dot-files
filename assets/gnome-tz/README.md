# GNOME Date & Time map assets

From GNOME Initial Setup `gnome-3-38` (`pages/timezone/data/`), originally
Ubiquity / gnome-control-center.

- `bg.png` — Miller-like world map (81°N … 59°S, longitude shifted −6°)
- `timezone_<offset>.png` — highlight masks (`cc-timezone-map.c` `%g` names)
- `pin.png` — location marker

License: GPL-2.0-or-later (same as gnome-initial-setup / Ubiquity).
Projection helpers in `components/TimezoneMapView.qml` match
`convert_longitude_to_x` / `convert_latitude_to_y` in `cc-timezone-map.c`.
