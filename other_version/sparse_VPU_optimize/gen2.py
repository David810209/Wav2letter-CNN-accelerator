import random
from pathlib import Path
import time

# ======================
# Global settings
# ======================
random.seed(time.time())

# cases: (name, M_raw, K_raw, K_non_zero, input_offset, N_iter)
cases = [
    ("L1",   76, 1872, 1340,3,2),
    ("L2",   72, 1872, 1340,3,2),
    ("L3",   148, 1752,1052,75,1),
    ("L4", 32,  8000, 4912,90,1),
    ("L5", 20, 8000, 4912,90,1),
    ("L6", 76, 2000, 1364,84,1),
    ("L7", 72, 2000, 1364,84,1),
    ("L8", 76,2000, 1220,66,1),
    ("L9", 72,2000, 1220,66,1),
]

# ======================
# helpers
# ======================
def rand_int8():
    return random.randint(-128, 127)

def pack4(v):
    """
    4x int8 -> 1x uint32
    你說軟體端會把 v[0] 放在 high 8 bits，所以採用：
      v[0] -> [31:24]
      v[1] -> [23:16]
      v[2] -> [15:8]
      v[3] -> [7:0]
    """
    return (
        ((v[0] & 0xFF) << 24) |
        ((v[1] & 0xFF) << 16) |
        ((v[2] & 0xFF) << 8)  |
        (v[3] & 0xFF)
    )

def pack2_u16(i0, i1):
    """
    2x uint16 index -> 1x uint32
    這裡維持你目前的寫法：你在呼叫時會用 pack2_u16(i1, i0)
    讓第一個 index (i0) 放在 high 16 bits。
    """
    return ((i1 & 0xFFFF) << 16) | (i0 & 0xFFFF)

# ======================
# output dir
# ======================
out_dir = Path("./output")
out_dir.mkdir(parents=True, exist_ok=True)

# ======================
# main loop
# ======================
for idx, (name, M_raw, K_raw, K_non_zero, input_offset, N_iter) in enumerate(cases, start=1):
    for jdx in range(N_iter):
        # ---- hardware-aligned effective sizes ----
        M_eff = M_raw
        K_eff = K_raw
        K_words = K_eff // 4

        # ======================
        # generate dense A (image): shape [M_eff * K_words][4 lanes]
        # ======================
        A_bytes = []   # list of 4-lane int8 words, lane index仍代表 k%4
        A_words = []   # packed uint32 words (依 pack4 新位元配置)

        for i in range(M_eff):
            for w in range(K_words):
                v = [rand_int8() for _ in range(4)]
                A_bytes.append(v)
                A_words.append(pack4(v))

        # ======================
        # generate D (index array): length K_non_zero, each index is uint16
        # packed as 2 indices per uint32 word
        # ======================
        indices = random.sample(range(K_raw), K_non_zero)
        indices.sort()

        D_words = []
        for t in range(0, K_non_zero, 2):
            i0 = indices[t]
            i1 = indices[t + 1]
            # 你原本就想讓 i0 在 high 16 bits，所以保留這個呼叫方式
            D_words.append(pack2_u16(i1, i0))  # => (i0<<16) | i1

        # ======================
        # generate sparse B (kernel): length K_non_zero (1 x K_non_zero)
        # still written out as packed int8x4 words
        # ======================
        B_nz = [rand_int8() for _ in range(K_non_zero)]
        K_nz_eff = K_non_zero
        K_nz_words = K_nz_eff // 4

        B_words = []
        for w in range(K_nz_words):
            v = []
            for lane in range(4):
                t = w * 4 + lane
                v.append(B_nz[t])
            B_words.append(pack4(v))

        # ======================
        # compute sparse C (golden):
        # C[i] = sum_{t=0..K_non_zero-1} (A[i, indices[t]] + input_offset) * B_nz[t]
        #
        # 注意：這裡用 A_bytes 的 lane 取值，與 pack4 位元擺放無關；
        #       pack4 只是影響輸出到檔案的 word 內 byte 順序，讓硬體讀到的 lane 對應一致。
        # ======================
        C = []
        for i in range(M_raw):
            acc = 0
            base = i * K_words
            for t, k in enumerate(indices):
                aw = A_bytes[base + (k // 4)][k % 4]
                acc += (aw + input_offset) * B_nz[t]
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

        with open(out_dir / f"D_arr_{idx}_{jdx}.txt", "w") as f:
            for w in D_words:
                f.write(f"{w:08x}\n")

        with open(out_dir / f"C_ans_{idx}_{jdx}.txt", "w") as f:
            for v in C:
                f.write(f"{v:08x}\n")
