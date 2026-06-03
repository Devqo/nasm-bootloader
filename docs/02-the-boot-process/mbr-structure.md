# MBR (Master Boot Record) Structure

# 1. Disk Sectors and Sector 0

To write a bootloader we must look at how storage media is physically structured and accessed by the motherboard hardware.

## Concept 1: Physical Disk Sectors
When you write a file in an operating system, you can save a file that is 1 byte, 10 bytes or 10 megabytes. But at the raw physical hardware level, storage devices (like USB flash drives, mechanical hard drives or SSDs) cannot read or write data byte-by-byte.

Instead, the drive's controller reads and writes data in fixed-size blocks called **sectors**.
- **The 512-Byte Standard**: Historically, the universal standard size for a physical disk sector is exactly **512 bytes**.
- **Sector-Level Access**: The hardware is incapable of reading a single byte from a disk. If the BIOS wants to read byte #10 it must physically read the entire 512-byte sector containing that byte into a RAM buffer and then exact the 10th byte.

## Concept 2: Sector 0 (The Master Boot Record)
When your PC powers on, the BIOS has no idea how your USB or hard drive is formatted. It doesn't understand file systems (like FAT32, NFTS, ext4...), directories or files.

To bypass this problem, the PC designers created a simple, universal hardware rule:
1. The BIOS is hard-wired to physically read the **very first sector** of the boot drive on startup. This is **Secotr 0** (also called Logical Block Address 0 or LBA 0).
2. This 512-byte sector is aso known as the **Master Boot Record (MBR)**.
3. The BIOS copies all 512 bytes of Secotr 0 from the disk directly into a specific, hardocded location in physical RAM: `0x07C00`.
4. Once loaded, the BIOS jumps the CPU's Instruction Pointer to `0x7C00`, handed-off absolute control of the computer to whatever binary machine code you wrote inside those 512 bytes.

---

# 2. Anatomy of the 512-Byte MBR

Even though the BIOS loads a full 512 bytes, you do not actually get to use all 512 bytes for your assembly code. The hardware standard partitions those 512 bytes into strict, distinct regions:

| Byte Offset (Decimal) | Size in Bytes | Purpose                                                              |
| --------------------- | ------------- | -------------------------------------------------------------------- |
| 0 - 439               | 440 bytes     | **Bootstrap Code** (Where your assembly instructions must fit)       |
| 440 - 445             | 6 bytes       | **Unique Disk Signature / Reserved** (Optional hardware/OS tracking) |
| 446 - 509             | 64 bytes      | **Partition Table** (Describes up to 4 partitions, 16 bytes each)    |
| 510 - 511             | 2 bytes       | **Magic Boot Signature (`0xAA55`)** (Mandatory boot validation word) |

## The Two Standards of Booting:
- **HDD-Style (Partitioned Disk)**: If you want your disk to contain normal partitions (like a C: drive and a D: drive) you must preserve bytes 446-509. This limits your bootstrap assembly code to a maximum of **440 bytes**.
- **Floppy-Style ("Superfloppy")**: If you are booting like a floppy disk (no partitions, just one raw block of storage) you do not need a partition table. In this style, you can let your assembly code occupy the entire space up to byte 510 (giving you a maximum of **510 bytes** of code)
*Note: For this QEMU bootloader we'll be using the Floppy-Style layout so we can use the full 510 bytes of code before we write our Magic Signature*.

---

# 3. The Magic Boot Signature (0xAA55)

This is the handshake between your code and the motherboard's BIOS. Without this precise signature, the computer will refuse to run your bootloader.

## Concept 1: The Validation Check
When you insert a raw, unformatted USB drive or a blank hard drive into a computer, it is filled with random magnetic noise or zeros.

If the BIOS blindly loaded Sector 0 and jumped the CPU to `0x7C00` the CPU would immediately attempt to execute that random garbage as machine instructions. This would cause a motherbaord lockup, memory corruption or unexpected reboots.

To prevent this, the IBM PC designers established a simple hardware safety check:
1. The BIOS copies Sector 0 into RAM at `0x07C00`.
2. Before it jumps to `0x07C00` the BIOS checks the **very last two bytes** of the loaded sector (bytes 510 and 511).
3. It expects those two bytes to contain the exact 16-bit signature: `0xAA55`.
4. If the signature is found, the BIOS says: "This sector is valid. Let's boot".
5. If those bytes are anything else, the BIOS assumes the disk is unbootable, halts execution and displays an error message like "No bootable device found".

## Concept 2: Little-Endian Storage
The x86 architecture is **little-endian**. This means the least significant byte of a multi-byte number is physically stored first, at the lowest memory address.

Let us look at our 16-bit word `0xAA55`:
- The **high byte** (most significant) is 0xAA
- The **low byte** (least significant) is 0x55
Becuase the x86 is little-endian, when the CPU or compiler stores this 16-bit word in memory (or on disk) at bytes 510 and 511:
- The **low byte** is written to byte **510**
- The **high byte** is written to byte **511**

So if you open a compiled bootloader inside a raw hex editor, you will literally see the last two bytes of the file written as: `55 AA`.

If you use NASM's declare-word directive (`dw 0xAA55`) the compiler is smart enough to handle this little-endian byte-swapping automatically. But if you decide to write them as individual bytes (`db`) you must write them in the exact order they sit on the disk.

---

# 4. NASM Directives for File Padding

If your assembly bootloader is only 50 bytes of actual code and you write `dw 0xAA55` immediately after it, your compiled file will be exactly 52 bytes in size.

If you write this 52-byte file to Sector 0 of a disk, the BIOs will load it, look at bytes 510 and 511 of the sector and find nothing but random garbage or zeros. The BIOS will assume the disk is unbootable and halt. The signature **must** stt at exactly the very end of the 512-byte block.

To solve this, we must "pad" the remaning space of our sector with zeros to push the signature precisely to the end.

## The NASM Padding Formula
Rather than manually counting how many bytes of code we wrote and changing our padding every time we add a line of code, we use a brilliant mathematical formula in NASM:
```
times 510 - ($ - $$) db 0
dw 0xAA55
```

Lets' break down exactly what the compiler is doing here:
1. `times N <data>`: This is a NASM loop directive. It tells the compiler to repeat a data declaration `N` times. For example, `times 5 db 0` writes five zeros to the binary.
2. `$`: This symbol represents the **current memory offset** where this exact line of code is being compiled
3. `$$`: This symbol represents the **starting memory offset** of the current code section (usually `0` or `0x7C00`)
4. `($ - $$)`: This calculates the exact size of our compiled code in bytes up to this line.
5. `510 - ($ - $$)`: This calculates exactly how many bytes are left between the end of our compiled code and the 510th byte of the sector.
6. `db 0`: The `times` directive fills the remaning gap with zeros.
7. `dw 0xAA55`: Finally, we write our 2-byte boot signature, bringing the total file size to exactly **512 bytes**.
