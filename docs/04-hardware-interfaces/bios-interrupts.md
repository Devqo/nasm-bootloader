# BIOS Interrupts

# 1. What is a Software Interrupt?

To print text to the screen or read files from a disk on bare metal, we could physically write code to manipulate the motherboard's video cards and disk controllers directly. However, this is incredibly complex and requires thousands of lines of hardware-specific driver code.

Instead, we use **Software Interrupts** to call functions already written for us and pre-loaded into the motherboard's ROM chips by the computer manufacturer. These functions are the **BIOS Services**.

## Concept 1: The Interrupt Handshake
An interrupt is exactly what it sounds like: a signal that physically *interrupts* the CPU's current sequential exectuion.

When you run a software interrupt using `int` instruction (for example, `int 0x10`), the CPU performs this automatic hardware sequence:
1. **Pause and Save State**: The CPU puases your program. To make sure it can return to your code later, it automatically **pushes** three registers onto the stack:
	- `FLAGS`
	- `CS`
	- `IP`
2. **Jump to BIOS**: The CPU jumps to the BIOS Function in memory and executes it.
3. **Return**: Once the BIOS function finishes, it exectues a special instruction called `iret` (Interrupt Return). This instruction pops `IP`, `CS` and `FLAGS` back off the stack, resuming your bootloader exactly where it left off.

## Concept 2: The IVT (Interrupt Vector Table) Handshake
How does the CPU know where the BIOS's video code actually sits in memory when you call `int 0x10`?

It uses the **Interrupt Vector Table (IVT)**
- Recall from our memory layour lessons that the IVT sits at the absolute bottom of physical RAM, from `0x00000` to `0x003FF` (exactly 1,024 bytes).
- The IVT is an array of **Far Pointers** (each pointer is a 2-byte Segment and a 2-byte Offset, totalling **4 bytes**).
- Because each interrupt entry in the table takes up exactly 4 bytes of space, the CPU calculates the address of any interrupt handler using a simple formula: `IVT Offset = Interrupt Number * 4`.
- For `int 0x10` (which is decimal 16): `IVT Offset = 16 * 4 = 64 (which is 0x0040 in hex)`.
The CPU automatically reads the 4-byte pointer stored at physical address `0x00040` loads those bytes into `CS` and `IP` and instantly jumps to the BIOS's video ROM!

---

# 2. The BIOS Services Map & 3. Video Services

The x86 architecture has a physical limit of only 256 possible interrupt vectors (`0x00` to `0xFF`). If the BIOS assigned a unique interrupt number to every single hardware function (one for printing chat, one for clearing the scren, one for checking the keyboard, etc) we would run out of interrupt numbers instantly.

To solve this, the BIOS **multiplexes** its interrupts using the `AH` register as a **Function Selector**.

When you trigger `int 0x10` (Video Services), the very first thing the BIOS code does is insepect the value sitting inside `AH`. It uses that value to decide *which* sub-function to run.

## Teletype (TTY) Mode (`AH = 0x0E`)
To print a character we use Video Sub-function `0x0E` (Teletype Mode). This function acts like an old-school typewriter: it prints a character on the screen and automatically advances the text cursor to the right, handling the wraps automatically.

To use it, you must configure four registers before calling the interrupt:
1. **`AH` (Function Selector)**: Must contain exactly `0x0E`.
2. **`AL` (The Character)**: Must contain the ASCII code of the character you want to print.
3. **`BH` (Video Page)**: Must contain `0x00` (the default page).
4. **`BL` (Foreground Color)**: Usually set to `0x07` (light gray text) or `0x0F` (bright white text).
*Note: You can do `mov al, 'H'` and NASM will automatically trasnlate it ot its ASCII value during compilation*.

---

# 4. Triggering the Video Interrupt

When writing high-level languages like Python or C, you can start a new line by simply printing the special character `\n`.

But on bare metal the BIOS TTY function mimics a mechanical typewritter. A typewritter does not have a single "new line" key. To start a new line, the typist has to perform two separate mechanical actions:
1. **Carriage Return (CR - `0x0D`)**: Physically slide the carriage back to the very left margin of the page
2. **Line Feed (LF - `0x0A`)**: Turn the roller to feed the ppaer upward by one line.

Because the BIOs is built on this physical typewriter model, you cannot start a new line using a single character. You must print two distinct characters in sequence:
1. First print `0x0D` to return the cursor to the left column.
2. Then print `0x0A` to drop the cursor down to the next row.

---

# 5. Building a String-Printing Loop

To print a string (like "Welcome to OS", followed by a 0 to mark the end), we must combine four separate architectural concepts:
1. **A Pointer (`SI`)**: We use `SI` to hold the memory address of the string.
2. **Dereferencing (`[si]`)**: We read the character sitting in RAM at the address pointed to by `SI`.
3. **BIOS Interrupt (`int 0x10`)**: We print that character using the Teletype function (`0x0E`).
4. **Control Flow (`cmp` & `jz` / `jnz`)**: We check if the character is `0` (null-terminator). If it is, we stop; if not, we advance `SI` to the next character and loop.
