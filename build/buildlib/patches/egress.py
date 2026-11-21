"""Egress module insertion + hooks. Moved verbatim from main() in build/build.py."""
from ..util import insert_after


def apply(t, ctx):
    egress = ctx["egress"]
    # --- egress module insertion (before xrsbout) + hooks ---
    t = insert_after(t, "\nxrsbout(){", "\n" + egress + "\nxrsbout(){", "egress-module-anchor") if False else t
    # The above line is intentionally not used; do the insertion properly:
    if "\n" + egress + "\nxrsbout(){" not in t:
        t = t.replace("\nxrsbout(){", "\n" + egress + "\nxrsbout(){", 1)
    return t
