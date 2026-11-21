"""Builds pc/fly/fly_data.npz: the FlyWire 783 fruit fly connectome as a compact matrix, plus the
sensory and command neuron groups Hyper-Bot's Fly Brain mode uses.

Inputs (downloaded by CI):
  shiu/Connectivity_783.parquet, shiu/Completeness_783.csv  - github.com/philshiu/Drosophila_brain_model (MIT)
  ann/supplemental_files/Supplemental_file1_neuron_annotations.tsv - github.com/flyconnectome/flywire_annotations

Usage: python tools/build_fly_data.py <shiu_dir> <annotations_tsv> <out_npz>
"""
import sys
import numpy as np
import pandas as pd
from scipy import sparse

shiu, ann_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
comp = pd.read_csv(f"{shiu}/Completeness_783.csv", index_col=0)
ids = comp.index.to_numpy()
N = len(ids)
con = pd.read_parquet(f"{shiu}/Connectivity_783.parquet",
                      columns=["Presynaptic_Index", "Postsynaptic_Index", "Excitatory x Connectivity"])
W = sparse.csr_matrix((con["Excitatory x Connectivity"].to_numpy(np.int32),
                       (con["Presynaptic_Index"].to_numpy(), con["Postsynaptic_Index"].to_numpy())), shape=(N, N))
W.sum_duplicates()
assert np.abs(W.data).max() < 32767

a = pd.read_csv(ann_path, sep="\t", low_memory=False)
pos = pd.Series(np.arange(N), index=ids)
a = a[a.root_id.isin(pos.index)].copy()
a["i"] = a.root_id.map(pos)

def g(mask):
    return np.sort(a[mask].i.to_numpy().astype(np.int32))

ct, sub, sc, side = a.cell_type.astype(str), a.cell_sub_class.astype(str), a.super_class.astype(str), a.side.astype(str)
rng = np.random.default_rng(7)

def sample(arr, n):
    return np.sort(rng.choice(arr, size=min(n, len(arr)), replace=False)) if len(arr) else arr

eyeL = g((ct == "R1-6") & (side == "left"))
eyeR = g((ct == "R1-6") & (side == "right"))
groups = {
    # senses
    "sound": g(sub == "auditory"),
    "touch": g(sub.isin(["head bristle", "eye bristle"])),
    "wind": g(sub == "wind_gravity"),
    "sugar": g(sub == "sugar"),
    "bitter": g(sub == "bitter"),
    "water": g(sub == "water"),
    "smell": sample(g(a.cell_class.astype(str) == "olfactory"), 600),
    "ocelli": g(sub == "ocellar_interneuron"),
    "eyeL": sample(eyeL, 1200),
    "eyeR": sample(eyeR, 1200),
    # background noise: all sensory neurons except the photoreceptors (those get the screen instead)
    "noise": g(sc.isin(["sensory", "sensory_ascending"]) & ~ct.isin(["R1-6", "R7", "R8"])),
    # outputs (real command neurons)
    "escape": g(ct == "DNp01"),          # giant fiber: escape jump
    "back": g(ct == "MDN"),              # moonwalker: walk backwards
    "forward": g(ct == "DNp09"),         # forward walking
    "turnL_strong": g(ct.isin(["DNa01", "DNa02"]) & (side == "left")),
    "turnR_strong": g(ct.isin(["DNa01", "DNa02"]) & (side == "right")),
    "dnL": g((sc == "descending") & (side == "left")),
    "dnR": g((sc == "descending") & (side == "right")),
    "dn": g(sc == "descending"),
    "groom": g(ct.isin(["DNg11", "DNg84", "DNg35", "DNg15", "DNge036", "DNg85"])),
    "mouth": g(sc == "motor"),           # proboscis / pharynx motor neurons -> "typing"
    "mn9": g(a.root_id == 720575940660219265),
}
for k, v in groups.items():
    print(f"{k:14s} {len(v)}")

np.savez_compressed(out, indptr=W.indptr.astype(np.int64), indices=W.indices.astype(np.int32),
                    data=W.data.astype(np.int16), n=np.int64(N),
                    **{"g_" + k: v for k, v in groups.items()})
print(f"saved {out}: {N} neurons, {W.nnz} connections")
