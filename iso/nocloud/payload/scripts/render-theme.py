#!/usr/bin/env python3
"""render-theme.py — rend les templates de thème façon Omarchy.

Reproduit le sous-ensemble du moteur d'Omarchy (omarchy-theme-set-templates)
dont nos templates ont besoin, sans dépendance externe :

  {{ cle }}          -> valeur telle quelle (#rrggbb)
  {{ cle_strip }}    -> sans le '#'
  {{ cle_rgb }}      -> "r,g,b" décimal
  {{ mix a b 30% }}  -> mélange linéaire de deux couleurs (aussi mix_strip,
                        mix_rgb)

colors.toml est un TOML plat (cle = "valeur") : on le parse en regex pour
rester compatible avec tout python3 (tomllib n'existe qu'à partir de 3.11).

Usage : render-theme.py <colors.toml> <template.tpl> [sortie]
        (sans [sortie] : stdout)
"""

import re
import sys


# Alias hérités, copiés de bin/omarchy-theme-color (Omarchy v4.0.0) : les
# templates amont utilisent purple / selection_background / … que certains
# colors.toml n'ont pas.
ALIASES = [
    ("purple", "magenta"), ("magenta", "purple"),
    ("bright_purple", "bright_magenta"), ("bright_magenta", "bright_purple"),
    ("selection", "selection_background"),
    ("selection_background", "selection"),
    ("selection_foreground", "bright_foreground"),
]


def parse_colors(path):
    colors = {}
    pat = re.compile(r'^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"')
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                colors[m.group(1)] = m.group(2)
    if not colors:
        sys.exit(f"erreur : aucune couleur lue dans {path}")
    for _ in range(2):  # deux passes : les alias peuvent se chaîner
        for dst, src in ALIASES:
            if dst not in colors and src in colors:
                colors[dst] = colors[src]
    return colors


def hex_to_rgb(value):
    v = value.lstrip("#")
    return "{},{},{}".format(int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))


def mix(start, end, amount):
    if amount.endswith("%"):
        amount = float(amount[:-1]) / 100.0
    else:
        amount = float(amount)
        if amount > 1:
            amount /= 100.0
    amount = min(max(amount, 0.0), 1.0)
    s, e = start.lstrip("#"), end.lstrip("#")
    out = "#"
    for i in (0, 2, 4):
        a, b = int(s[i:i + 2], 16), int(e[i:i + 2], 16)
        out += "{:02x}".format(round(a * (1 - amount) + b * amount))
    return out


HEX6 = re.compile(r"^#[0-9A-Fa-f]{6}$")


def render(text, colors):
    unresolved = set()

    def sub(match):
        expr = match.group(1).strip().split()
        if expr[0] in ("mix", "mix_strip", "mix_rgb") and len(expr) == 4:
            a, b = colors.get(expr[1], ""), colors.get(expr[2], "")
            if HEX6.match(a) and HEX6.match(b):
                value = mix(a, b, expr[3])
                if expr[0] == "mix_strip":
                    return value.lstrip("#")
                if expr[0] == "mix_rgb":
                    return hex_to_rgb(value)
                return value
            unresolved.add(match.group(0))
            return match.group(0)
        key = expr[0]
        for suffix, conv in (("_rgb", hex_to_rgb), ("_strip", lambda v: v.lstrip("#"))):
            if key.endswith(suffix) and key[: -len(suffix)] in colors:
                base = colors[key[: -len(suffix)]]
                return conv(base) if HEX6.match(base) else base
        if key in colors:
            return colors[key]
        unresolved.add(match.group(0))
        return match.group(0)

    out = re.sub(r"\{\{\s*([^}]+?)\s*\}\}", sub, text)
    return out, unresolved


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    colors = parse_colors(argv[1])
    with open(argv[2], encoding="utf-8") as fh:
        rendered, unresolved = render(fh.read(), colors)
    for token in sorted(unresolved):
        print(f"attention : jeton non résolu {token} ({argv[2]})", file=sys.stderr)
    if len(argv) > 3:
        with open(argv[3], "w", encoding="utf-8") as fh:
            fh.write(rendered)
    else:
        sys.stdout.write(rendered)


if __name__ == "__main__":
    main(sys.argv)
