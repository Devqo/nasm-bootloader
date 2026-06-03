# 0. Context: The Real Mode Environment

## Why we start here
In 1978, Intel released the 8086 microprocessor, a 16-bit chip which became the foundation of the IBM PC.

Every modern 64-bit x86 processor is a direct descendant of that original 8086. To ensure that software written decades ago can still run on modern hardware, Intel established a strict rule: **all x86 CPUs must power on in the exact same state as the 1978 8086**.

This power-on state is **Real Mode**. Your modern CPU boots up pretending to be a slow 16-bit chip from the late 70s. It will remain in this state until your code explicitly tells it to swtich to 32-bit (Protected Mode) or 64-bit (Long Mode).

## What "Real" Means
In modern OSs programs run in **Virtual Memory**. If your program asks for memory address `0x400000` the OS and the CPU's memory management hardware translate that "virtual" address to some random physical location in your actual RAM sticks, preventing programs from spying on or overwriting eachother.

In Real Mode, there is no virtual memroy.
- "Real" means **Real Physical Address**.
- If your bootloader code tells the CPU to write the byte `0xAA` to memory address `0x7C00` the CPU physically sends a signal to your RAM hardware to write `0xAA` to exactly the 31,744th byte (`0x7C00 in decimal) of your physical RAM.
- There are no security permissions (no "user mode", "kernel mode"...). Your code has absolute control over the hardware. This also means a single typo can overwrite the BIOS or the CPU's internal control structures.

## The 1MB Limit
The original 8086 chip had 20 address pins connecting it to the system board.

Because it had 20 address lines, the maximum amount of memory it could physically address was `2^20 bytes = 1,048,576 bytes = 1MB`.

Even if your computer has 32GB of RAM installed, when the CPU is running in Real Mode, it acts as if only that first 1MB of memory exists.

---

# 1. Introduction to x86 registers

## What is a register?
Think of RAM as a massive warehouse. It can hold a lot of goods (data) but it takes time to walk down the aisles, find an item and bring it back. If the CPU had to fetch every single piece of data from RAM every time it wanted to perform a simple calculation, the computer would run incredibly slow.

To solve this, the CPU has a handful of ultra-fast, microscopic storage cells built directly inside the processor core itself. These are called **registers**.
- **Speed**: Registers operate at the actual clock speed of the CPU, making them thousands of times faster to access than RAM.
- **Purpose**: The CPU can't do math or logical operations directly on data sitting on RAM. It must first load the local data from the RAM into a register, perform the operation inside the register and then (if desired) write the result back to RAM.

## Register sizes and Physical Mapping

In 16-bit Real Mode, the default size of these registers is 16 bits (capable of holding values from 0-65,535, or in hex `0x0000`-`0xFFFF`).

However, the designers of the x86 architecture did something clever. They allowed developers to access some of these 16-bit registers as a single 16-bit unit, **or** split them down the middle into two independent 8-bit registers

Let's look at the accumulator register `AX` as an example:
![[AX.png]]
- `AX` repreesents the entire 16-bit register.
- `AH` (Accumulator High) represents the upper 8 bits (bits 8 through 15).
- `AL` (Accumulator Low) represents the lower 8 bits (bits 0 through 7).

These are not three different registers; they're different ways of looking at the same physical hardware. If you modify `AL` or `AH` you are modifying a portion of `AX`.

This mapping applies to the four main registers:
- `AX`: `AH/AL`
- `BX`: `BH/BL`
- `CX`: `CH/CL`
- `DX`: `DH/DL`

---

# 2. General-Purpose Registers (GPRs)

Even though these four registers are called "general-purpose" becuase you can use them for general calcualtions and temporary storage, the x86 hardware and BIOS assign very specific and specialized roles for them.

When building a bootloader you must respect these roles, or certain instructions and BIOS services will not work.

## AX (The Accumulator)
- **Role**: Arithmetic and BIOS functions
- **Why it matters**:
	- The CPU's internal math hardware (the ALU) is physically optimized to perform operations on `AX` faster than any other register.
	- When you want to talk to the BIOS (to print a character to the screen or read from the disk for instance), the BIOS expects you to load a "function number" into `AH` to specify what you want to do and sometimes input parameters into `AL`.

## BX (The Base Register)
- **Role**: Memory Addressing (Base Pointer)
- **Why it matters**:
	- In 16-bit Real Mode you can't just use any register to point to a location in memory. For example, you can't tell the CPU to "load the byte at the memory address stored in `AX`". The hardware physically does not support it.
	- `BX` is one of the very few registers that the x86 architecture allows to act as a pointer to a memory address. You will use `BX` heavily when you need to specify *where* in RAM you want to load the data.

## CX (The Counter Register)
- **Role**: Hardware Loops
- **Why it matters**:
	- The x86 architecture has a built-in instruction called `LOOP`. When the CPU executes `LOOP` it automatically decrements `CX` by 1. If `CX` is not 0, it jumps back to the start of the loop.
	- If you are writing a loop (for example, to print a string character-by-character), `CX` is your hardware-tracked loop counter.

## DX
- **Role**: I/O Ports & Disk Drive ID
- **Why it matters**:
	- `DX` is used alongside `AX` for complex math (like division, where the remainder goes to `DX`).
	- When the computer bios finishes initializing the hardware, it loads your 512-byte bootloader into RAM and jumps to it. Just before it does, the BIOS writes the ID of the boot drive (e.g. `0x00` for floppy, `0x80` for the first hard drive/USB) into `DL`.

---

# 3. Segment Registers

## The Mathematical Problem
As we learned in the beginning, Real Mode allows us to access 1MB of RAM. To point to any address in a 1MB memory space, you need a 20-bit address (since 2^20 = 1MB).

But all of our regitsers in Real Mode are only 16-bits wide! A 16-bit register can only point to a maximum address of 64KB (2^16 = 65,536 bytes).

How does the CPU with only 16-bit registers point to a 20-bit address space?

### Segment + Offset Addressing
Intel solved this by using two 16-bit registers together to calculate a single 20-bit physical
- **Segment Register**: Points to a starting boundary of a 64KB block of memory.
- **Offset (usually held in a GP or index register)**: Points to a specific byte *inside* that 64KB block.

Every time the CPU accesses memory, it automatically calculates the real physical address using this exact hardware formula:
$$
\text{Physical Address} = (\text{Segment Register} * 16) + \text{Offset}
$$

*Note: In hex multiplying a number by 16 is incredibly easy, you just shift the number to the left by one digit and add a 0 to the end.*

## CS (Code Segment)
- It tells the CPU where your executable instructions are located.
- The CPU automatically combines `CS` with the Instruction Pointer (`IP`) to fetch the next instruction: `CS:IP`.

## DS (Data Segment)
- It tells the CPU where your variables, constants and strings are located. 
- When you try to read a variable, the CPU automatically assumes it's located at `DS:offset`.

## SS (Stack Segment)
- It tells your CPU where your stack memory begins.
- The CPU combines `SS` with the Stack Pointer (`SP`) to handle `push` and `pop` operations: `SS:SP`.

## ES (Extra Segment)
- An extra data segment.
- It is highly useful for copying data or telling the BIOS where to write disk sectors in memory (e.g. `ES:BX`)

---

# 4. Index and Pointer Registers

Now that you understand segments we need to take a look at the registers that are specifically design to hold **offsets** within those segments.

While you can use GPRs like `BX` as an offset, these five specialized registers are design for dedicated pointer tasks:

## SI (Source Index) and DI (Destination Index)
- **The Concept**: These are index registers used heavily for memory copying and string operations.
- **In a Bootloader**:
	- If you want to print a string (like `"Loading OS..."`) you will load the memory address of the string into `SI`. The CPU has optimized instructions that automatically read from the address pointed to by `SI` and increment `SI` to point to the next letter.
	- If you want to copy data from one place in RAM to another (like copying loaded disk sectors), you point `SI` to the source and `DI` to the destination.

## SP (Stack Pointer) and BP (Base Pointer)
- **The Concept**: These are dedicated to managing the **Stack** (a region of memory used to temporarily store data, function parameters and return addresses).
- **In a Bootloader**:
	- `SP` always points to the very top of the current stack. The CPU automatically updates `SP` whenever you run instructions like `PUSH` (to add data) or `POP` (to retrieve data)
	- `BP` is used as a stable reference point to access data stored on the stack without constantly changing like `SP` does.

## IP (Instruction Pointer)
- **The Concept**: This is the most critical register in the CPU. It holds the offset of the **next instruction** the CPU is going to execute.
- **In a Bootloader**:
	- Unlike other registers, you **cannot** directly write to `IP`. You cannot run an instruction like `mov ip, 0x1234`.
	- The only way to modify `IP` is indirectly, using control-flow instructions like jumps (`jmp`), calls (`call`) or returns (`ret`).

---

# 5. The FLAGS Register

The **FLAGS** register is unique. Unline `AX` or `DS`, which are used to store numbers or memory addresses, the FLAGS register is a collection of individual, independent 1-bit switches (flags).

When the CPU performs arithmetic, compares two values or runs certain BIOS services, it flips these 1-bit switches to `1` (Set) or `0` (Cleared) to report the outcome.

While there are many flags, three are absolutely critical for writing a bootloader:

## CF (Carry Flag)
- **What it represents**: It is set to `1` if an addition operation overflows (carries a 1 out of the most significant bit) or if a subtraction requires a borrow. 
- **Why it is vital for bootloaders**:
	- If the read succeded, it sets `CF = 0`.
	- If the read failed (e.g. sector not found, bad drive...), it sets `CF = 1`.

## ZF
- **What it represents**: It is set to `1` if the result of the last arithmetic or comparison operation was exactly **zero**.
- **Why it is vital for bootloaders**: If you compare two values (for instance, checking if the character you just read from a string is the null-terminator `0` to mark the end of the string), the comparison will result in zero, setting `ZF = 1`

## DF
- **What it represents**: It controls the direction of a string processing.
	- If `DF = 0` string operations automatically **increment** your pointer registers (`SI/DI`), moving forward through memory.
	- If `DF = 1` string operations automatically **decrease** your pointer registers, moving backward.
- **Why it is vital for bootloaders**: If the BIOS left `DF` set to `1` before jumping to your bootloader, any attempt to print a string might read backward in memory. You must ensure this flag is cleared (`0`) at the very start of your bootloader.
