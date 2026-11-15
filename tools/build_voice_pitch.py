"""Bind SR2's existing LinearPitch curve to the six stock player voice banks.

Read-only with respect to the input banks. Only .xsb metadata is generated.
The .xwb recordings and the stock .vpp_pc remain untouched.

Usage:
  python build_voice_pitch.py --source-dir <extracted audio> --output-dir <stage>

The supported banks have only 12-byte simple sounds and five-byte simple
cues. Add one sound-level RPC reference, relocate the cue table, and map its
sound offsets. Reverse the transform and require exact input bytes before
writing. Format references are FACT_internal.c/FACT_internal.h in FNA-XNA/FAudio.
"""

import argparse
from pathlib import Path
import struct


BANK_NAMES = tuple(f"SR2_VOC_{voice}.xsb" for voice in ("WM", "BM", "HM", "WF", "BF", "HF"))
SOUND_OFFSET_FIELD = 0x46
CUE_OFFSET_FIELD = 0x22
SOUND_SIZE = 12
RPC_SOUND_SIZE = 19
LINEAR_PITCH_CURVE = 0xD3
RPC_BLOCK = struct.pack("<HBI", 7, 1, LINEAR_PITCH_CURVE)


def u16(data, offset):
    return struct.unpack_from("<H", data, offset)[0]


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def check(condition, message):
    if not condition:
        raise ValueError(message)


def read_layout(data, size, flags):
    check(len(data) >= 0x8A, "Truncated sound bank")
    check(data[:8] == bytes.fromhex("53 44 42 4b 2c 00 2b 00"), "Unsupported sound bank format")
    check(data[0x12] in (0, 1), "Expected a little-endian PC sound bank")
    cues = u16(data, 0x13)
    sounds = u16(data, 0x1C)
    check(cues > 0 and sounds > 0, "Empty sound bank")
    check(u16(data, 0x15) == 0, "Complex cues require a different relocation")
    check(data[0x1B] == 1, "Expected one wave bank")
    for offset in (0x26, 0x2A, 0x32, 0x36, 0x3E, 0x42):
        check(u32(data, offset) == 0xFFFFFFFF, f"Unexpected referenced section at header {offset:#x}")
    start = u32(data, SOUND_OFFSET_FIELD)
    cue_start = u32(data, CUE_OFFSET_FIELD)
    check(start >= 0x8A, "Sound section overlaps header")
    check(cue_start == start + sounds * size, "Sound section has unexpected layout")
    check(cue_start + cues * 5 == len(data), "Unexpected trailing data")
    for index in range(sounds):
        offset = start + index * size
        check(data[offset] == flags, f"Unsupported sound flags at sound {index}")
        check(u16(data, offset + 7) == size, f"Unexpected sound size at sound {index}")
        check(data[offset + 11] == 0, f"Invalid wave bank index at sound {index}")
        if size == RPC_SOUND_SIZE:
            check(data[offset + SOUND_SIZE:offset + size] == RPC_BLOCK, "Unexpected RPC binding")
    for index in range(cues):
        cue = cue_start + index * 5
        target = u32(data, cue + 1)
        check(data[cue] == 4, f"Unsupported cue flags at cue {index}")
        check(start <= target < cue_start and (target - start) % size == 0,
              f"Cue {index} references an invalid sound")
    return start, cue_start, sounds, cues


def convert(data, old_size, new_size, old_flags, new_flags):
    start, cue_start, sounds, cues = read_layout(data, old_size, old_flags)
    output = bytearray(data[:start])
    for index in range(sounds):
        offset = start + index * old_size
        sound = bytearray(data[offset:offset + SOUND_SIZE])
        sound[0] = new_flags
        struct.pack_into("<H", sound, 7, new_size)
        output.extend(sound)
        if new_size == RPC_SOUND_SIZE:
            output.extend(RPC_BLOCK)
    new_cue_start = len(output)
    for index in range(cues):
        offset = cue_start + index * 5
        sound_index = (u32(data, offset + 1) - start) // old_size
        output.append(data[offset])
        output.extend(struct.pack("<I", start + sound_index * new_size))
    struct.pack_into("<I", output, CUE_OFFSET_FIELD, new_cue_start)
    read_layout(output, new_size, new_flags)
    return bytes(output)


def build_bank(original):
    updated = convert(original, SOUND_SIZE, RPC_SOUND_SIZE, 0, 2)
    restored = convert(updated, RPC_SOUND_SIZE, SOUND_SIZE, 2, 0)
    check(restored == original, "Sound bank failed exact reverse validation")
    return updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    check(args.source_dir.resolve() != args.output_dir.resolve(), "Use a separate output directory")
    built = []
    for name in BANK_NAMES:
        original = (args.source_dir / name).read_bytes()
        updated = build_bank(original)
        _, _, sounds, cues = read_layout(updated, RPC_SOUND_SIZE, 2)
        built.append((name, updated, sounds, cues))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, updated, sounds, cues in built:
        target = args.output_dir / name
        target.write_bytes(updated)
        check(target.read_bytes() == updated, f"Write verification failed for {target}")
        print(f"{name}: {sounds} sounds, {cues} cues, exact reverse validation passed")


if __name__ == "__main__":
    main()
