import sys
from mudata import read_h5ad

## VIASH START
par = {
    "input": "output.h5mu",
    "modality": "rna",
    "obs": [],
    "obsm": [],
    "obsp": [],
    "uns": [],
    "obs_absent": [],
    "obsm_absent": [],
    "obsp_absent": [],
    "uns_absent": [],
}
meta = {"resources_dir": "src/utils/"}
## VIASH END

sys.path.append(meta["resources_dir"])
from setup_logger import setup_logger

logger = setup_logger()

logger.info("Reading modality '%s' from '%s'", par["modality"], par["input"])
try:
    mod = read_h5ad(par["input"], mod=par["modality"])
except KeyError:
    raise ValueError(
        f"Modality '{par['modality']}' does not exist in '{par['input']}'."
    )

# Map each checked slot to the set of keys actually present in the modality.
present = {
    "obs": set(mod.obs.columns),
    "obsm": set(mod.obsm.keys()),
    "obsp": set(mod.obsp.keys()),
    "uns": set(mod.uns.keys()),
}

missing = {}
for slot, present_keys in present.items():
    # A multiple-value argument passed an empty list arrives as [""] from Viash;
    # drop empty strings so an empty selection means "no expected keys".
    expected = [key for key in (par.get(slot) or []) if key]
    absent = [key for key in expected if key not in present_keys]
    if absent:
        missing[slot] = (absent, sorted(present_keys))

# Slots listed as absent must not be present in the modality.
unexpected = {}
for slot, present_keys in present.items():
    forbidden = [key for key in (par.get(f"{slot}_absent") or []) if key]
    found = [key for key in forbidden if key in present_keys]
    if found:
        unexpected[slot] = found

if missing or unexpected:
    lines = [f"Output h5mu has unexpected slot state in modality '{par['modality']}':"]
    for slot, (absent, present_keys) in missing.items():
        lines.append(f"  .{slot}: missing {absent}; present {present_keys}")
    for slot, found in unexpected.items():
        lines.append(f"  .{slot}: should be absent but present {found}")
    raise AssertionError("\n".join(lines))

logger.info(
    "All expected slots are present and all absent slots are missing in modality '%s'.",
    par["modality"],
)
