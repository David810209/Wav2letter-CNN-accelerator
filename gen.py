import random
from pathlib import Path
import time
# ======================
# Global settings
# ======================
random.seed(time.time())

cases = [
    ("L1",   148, 1340,3,25),
    ("L2",   148, 1052,75,25),
    ("L3",   148, 1236,72,25),
    ("L4",   148, 1064,33,25),
    ("L5",   148, 1108,80,25),
    ("L6",   148, 1064,72,25),
    ("L7",   148, 1276,68,25),
    ("L8",   148, 1020,56,25),
    ("L9-1", 52,  4912,90,20),
    ("L9-2", 52,  4912,90,20),
    ("L9-3", 44,  4912,90,20),
    ("L10",  148, 1364,84,20),
    ("L11",  148, 1220,66,29),
]

# ======================
# helpers
# ======================
def rand_int8():
    return random.randint(-128, 127)

def pack4(v):
    """
    lane0 -> [7:0]
    lane1 -> [15:8]
    lane2 -> [23:16]
    lane3 -> [31:24]
    完全對齊 Verilog word[7:0] 當 lane0
    """
    return (
        ((v[3] & 0xFF) << 24) |
        ((v[2] & 0xFF) << 16) |
        ((v[1] & 0xFF) << 8)  |
        (v[0] & 0xFF)
    )

# ======================
# output dir
# ======================
out_dir = Path("./output")
out_dir.mkdir(parents=True, exist_ok=True)

# ======================
# main loop
# ======================
for idx, (name, M_raw, K_raw, input_offset, N_iter) in enumerate(cases, start=1):
    for jdx in range(N_iter):
        # ---- hardware-aligned effective sizes ----
        M_eff = M_raw
        K_eff = ((K_raw + 3) // 4) * 4
        K_words = K_eff // 4

        # ======================
        # generate B
        # ======================
        B_bytes = []   # shape: [K_words][4]
        B_words = []

        for j in range(K_words):
            v = []
            for lane in range(4):
                if (j * 4 + lane) < K_raw:
                    v.append(rand_int8())
                else:
                    v.append(0)   # padding lane MUST be zero
            B_bytes.append(v)
            B_words.append(pack4(v))

        # ======================
        # generate A
        # ======================
        A_bytes = []   # shape: [M_eff * K_words][4]
        A_words = []

        for i in range(M_eff):
            for j in range(K_words):
                v = []
                for lane in range(4):
                    valid = (i < M_raw) and ((j * 4 + lane) < K_raw)
                    v.append(rand_int8() if valid else 0)
                A_bytes.append(v)
                A_words.append(pack4(v))

        # ======================
        # compute C (hardware-consistent)
        # ======================
        C = []

        for i in range(M_raw):
            acc = 0
            for j in range(K_eff):
                aw = A_bytes[i * K_words + (j // 4)]
                bw = B_bytes[j // 4]
                lane = j % 4
                acc += (aw[lane]+input_offset) * bw[lane]
            C.append(acc & 0xFFFFFFFF)

        # ======================
        # write files
        # ======================
        with open(out_dir / f"A_arr_{idx}_{jdx}.txt", "w") as f:
            for w in A_words:
                f.write(f"{w:08x}\n")

        with open(out_dir / f"B_arr_{idx}_{jdx}.txt", "w") as f:
            for w in B_words:
                f.write(f"{w:08x}\n")

        with open(out_dir / f"C_ans_{idx}_{jdx}.txt", "w") as f:
            for v in C:
                f.write(f"{v:08x}\n")

        # print(
        #     f"[{idx}] {name}: "
        #     f"M {M_raw}->{M_eff}, "
        #     f"K {K_raw}->{K_eff} (words={K_words})"
        # )
