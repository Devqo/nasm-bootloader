# Memory Segmentation

# 1. The Mechanics of the Segmented Memory Model

To understand segmentation we have to look at the gap between what your Assembly instructions see and what the motherboard's RAM chips actually see.

## Concept 1: Logical vs Physical Address
When writing in 16-bit Real Mode assembly, you almost never deal with physical memory addresses directly. Instead, you write **logical addreses**.
- **Logical Addresses (Segment:Offset)**: This is the address representation used in your code. It is written as two 16-bit numbers separated by a colon, such as `0x07C0:0x0100`. The left side is the segment and the right side is the offset.
- **Physical Address**: This is the actual physical location on the RAM chips. It is a single, flat 20-bit number (from `0x00000` to `0xFFFFF`).

The CPU has dedicated internal hardware that takes your logical address (`Segment:Offset`), runs it through the hardware formula we saw earlier and outputs the raw 20-bit physical address to the motherboard's address bus.

## Concept 2: The 64KB Window
Why are segments limited to exactly **64KB** of memory?

This limit is a direct mathematical consequence of the registers. In Real Mode, the offset portion of a logical address must be stored in a 16-bit register.
- The maximum value a 16-bit offset register can hold is `0xFFFF` (which is 65,535 in decimal).
- `65,536` bytes is exactly **64KB**.

Think of a segment register as placing a camera at a specific starting position in memory. The offset register is like a lens that can pan forward up to 64KB away from that starting position.
If you leave the segment register untouched, you can only access memory within that local 64KB "window". Any attempt to increment the offset past `0xFFFF` will cause it to roll over to `0x0000` (wrapping around inside the same segment) rather than moving to the next segment.

---

# 2. Segment Overlapping (Aliasing)

Imagine you're writing a bootloader and you need to load a kernel from disk into RAM. This kernel is **100KB** in size.

If you point your `DS` to the starting address of this kernel and never change the value in `DS`, you won't be able to go past 64KB, so it will not work.
What you can do instead is once the offset has reached `0xFFFF`, "slide" the Segment Register. Let's look at an example:

**Phase 1**:
We set our Segment register to `0x1000`.
1. The starting physical address of this segment (offset `0x0000`) is `0x10000`.
2. We write data all the way to the maximum offset of `0xFFFF`.
3. The physical address of this final byte is: `0x10000` (Segment base) + `0xFFFF` (Offset) = `0x1FFFF`.

**Phase 2**:
Now we need to write the next chunk. We shift our Segment register forward to `0x2000`.
Using our (Segment * 16) formula we find that the starting physical address of this new segment is `0x20000`

Now that you've calculated `0x1000:0xFFFF` and `0x2000:0x0000` you can see that the segments can fit together perfectly.

But here is the trick: **segments do not have to be spaced 64KB apart**.

Because a segment register is 16 bits, we can set it to *any* value from `0x0000` to `0xFFFF`. Every time you increment a segment register by just `1`, its physical address shifts by only **16 bytes** (one **"paragraph"**).

---

# 3. Real-Mode Memory Layout 

Since segments can overlap and exist almost anywhere in our 1MB address space, we have a major responsability. We must decide exactly where to point our segment regists (`CS`, `DS`, `SS`) so we don't accidentally overwrite critcal system data.

This is a simplified map of the **1MB of physical RAM** in Real Mode:

| Physical Address Range | Size   | Purpose                                                                  |
| ---------------------- | ------ | ------------------------------------------------------------------------ |
| `0x00000` to `0x003FF` | 1KB    | **BIOS Interrupt Vector Table (IVT)** (Holds pointers to BIOS functions) |
| `0x00400` to `0x004FF` | 256B   | **BIOS Data Area (BDA)** (BIOS hardware state)                           |
| `0x00500` to `0x07BFF` | ~30KB  | **Free Conventional Memory**                                             |
| `0x07C00` to `0X07DFF` | 512B   | **Your Bootloader** (Where the BIOS copies your code)                    |
| `0x07E00` to `0x9FFFF` | ~608KB | **Free Conventional Memory** (The "sweet spot" for stacks/kernels)       |
| `0xA0000` to `0xBFFFF` | 128KB  | **Video RAM (VRAM)** (Used for text and graphics on screen)              |
| `0xC0000` to `0XFFFFF` | 256KB  | **BIOS ROM** (The read-only BIOS code itself)                            |

# 4. Segment Register Initialization (Normalization)

When the BIOS finishes its power-on checks, it loads your 512-byte bootloader to the physical address `0x07C00`and jumps to it.

However, the BIOS does not clean up after itself. When your bootloader starts:
1. `CS` might be set to `0x0000` or `0x07C0` depending on the motherboard manufacturer.
2. `DS` and `ES` are often left containing random, undefined garbage values from the BIOS startup routines.
3. `SS` and `SP` are pointing to whatever temporary stack the BIOS was using, which could be located anywhere

If you try to raed a variable or use a stack operation before configuring these registers yourself, your program is practically guaranteed to fail. **Normalization** is the process of immediatelly settings all segment registers to known, safe and consistent values.

## The Hardware Limitation of Segment Registers
In the x86 instruction set, there is a physical hardware constraint that surprises almost every beginner: **You cannot move an immediate constant value directly into a segment register**.

For example, this instruction is physically impossible for the CPU to execute:
`mov ds, 0x0000` (This will cause an assembler error)

The CPU lacks the physical internal circuitry (opcodes) to transfer data directly from an immediate value into a segment register.

To bypass this hardware limitation, we must use a "middleman".

If you want to initialize your `DS` to `0x0000`, you can use a GPR (like `AX`) to accomplish this in two steps:
```
mov ax, 0x0000
mov ds, ax
```
