# Addressing Modes

# 1. What is an Addressing Mode?

Before you can write any assembly code, we need to understand how the CPU physically locates the data it is supposed to operate on.

## Concept 1: Opcode vs Operands
Every line of assembly code is generally divided into two parts:
1. **The Opcode (Operation Code)**: This is the command telling the CPU *what to do* (e.g. `mov` for move/copy, `add` for addition, `push` for stack write).
2. **The Operands**: These are the inputs or targets telling the CPU *what to do it to*.

Most x86 instructions use a two-operand format:
```
opcode destination, source
```
Think of it like a grammar sentence: the opcode is the verb, the destination is the subject and the source is the object. For example, in `mov ax, bx` the CPU copies the data from `bx` (source) and writes it into `ax` (destination).

## Concept 2: The Three Data Locations
An "addressing mode" is simply the physical method the CPU uses to locate its operands. At the hardware level, data can only ever exist in **three** places:
1. **Immediate (Inside the instruction itself)**: The data is hardcoded into the binary machine code of your program. For example, if you tell the CPU to load the number `5`, the binary representation of `5` is physically embedded right next to the opcode bytes of your instruction in RAM.
2. **Register (Inside the CPU)**: The data is stored in one of the CPU's internal, ultra-fast registers (such as `AX` or `SI`).
3. **Memory (Inside RAM)**: The data is sitting at a specific physical address inside your RAM chips. The CPU physically uses its address bus to fetch this data from the motherboard.

---

# 2. Immediate vs Register Addressing

Now that you understand where data lives, let's look at the literal NASM syntax used to write these two models and the two major hardware rules that govern them.

## 1- Immediate Addressing Syntax
This is used when you want to load a fixed, constant value directly into a register.
```
mov ax, 0x1234	; Loads hexadecimal 1234 into AX
mov cx, 10			; Loads decimal 10 into CX
```
*Syntax Rule*: You simply write the numeric constant (wether in hex, decimal or binary) as the source operand.

## 2- Register Addressing Syntax
This is used when you want to copy data directly from one physical register to another.
```
mov ax, bx			; Copies the 16-bit value of BX into AX
mov cl, dh			; Copies the 8-bit value of DH into CL
```
*Syntax Rule*: You write the register names for both the destination and source operands.

## The Two Hardware Rules You Must Follow:
When writing these instructions, the CPU enforces two strict hardware constraints. If you violate them, the assembler (NASM) will refuse to compile the code.

### Rule 1: Operand Size Matching
The destination and source operands must be the exat same physical size. You cannot mix 16-bit and 8-bit registers in a single instruction.
- `mov ax, bx` is **valid** (both are 16-bit)
- `mov ah, al` is **valid** (both are 8-bit)
- `mov ax, bl` is **invalid** (you cannot fit an 8-bit register directly into a 16-bit register or vice-versa)

### Rule 2: Segment Register Constraints
AS we learned in memory segmentation, segment registers (`CS`, `DS`, `SS`, `ES`) are restricted:
- You cannot move an immediate constant driectly into a segmented register (`mov ds, 0x0000` is **invalid**).
- You cannot copy one segmented register directly to another segmented register (`mov ds, cs` is **invalid**). You must always use a GPR like `AX` as a middleman.

---

# 3. Memory Addressing: Direct vs Indirect

Now we are moving outside of the CPU core and talking to the motherboard's RAM chips. This is where we use **brackets [...]** to tell the CPU: "This is a memory addres, not a literal number".

## 1- Direct Memory Addressing
This is used when you want to read from or write to a fixed, constant memory offset.
```
mov ax, [0x1234] ; "Go to a physical RAM offset 0x1234, read the 16-bit value and put it in AX"
```
*The Mechanics*: The value `0x1234` is treated as a memory address. The CPU automatically combines this offset with the `DS` register to find the data (`DS:0x1234`).

## 2- Indirect Memory Addressing (Pointers)
In a bootloader you rarely know exact memory addresses ahead of time. For example, if you want to loop through a string to print it, you need a variable pointer.
```
mov ax, [bx]		 ; "Look at the offset stored inside BX. Go to that RAM offset, read the data and put it in AX"
```
*The Mechanics*: Here `BX` is acting as a pointer. The CPU reads the number inside `BX`, treats the number as a memory offset and fetches the data from `DS:BX`.

## 3- The 16-Bit Register Constraint (Extremely Important!)
In modern 32-bit and 64-bit programming you can use any register you want as a memory pointer inside brackets.

In 16-bit Real Mode the CPU physically does not have the hardware circuitry to use just any register as a pointer.

You can **only** use these four registers inside memory brackets:
- **Base Registers**: `BX`, `BP`
- **Index Registers**: `SI`, `DI`

Instructions like `mov ax, [cx]` or `mov ax, [dx]` are physically illegal and will cause a compilation error. The Intel 8086 designers limited pointer calculations to these four registers to save physical transitor spsace on the sillicon chip.

*Note: For `BX`, `SI` and `DI` the CPU automatically pairs them with `DS`. However, if you use `BP` inside brackets the CPU automatically assumes you are talking to the stack and pairs it with `SS`.*

---

# 4. The Meaning of Brackets [...] (Dereferencing)

In high-level languages like C, the brackets are the difference between a pointer variable itself and the data the pointer is pointing to (dereferencing).

Let's set up a hardware scenario in RAM:
- Inside the CPU, the register `BX` constains the value `0x1000`.
- In physical RAM, at the address `0x1000`, we have stored the 16-bit word `0x55AA`.

If we execute the instruction `mov ax, bx`:
- `AX` ends up with `0x1000` and that's it
If we instead execute the instruction `mov ax, [bx]`:
- `AX` ends up with `0x55AA`.
- The CPU also sent a read request to the physical RAM chips over the system bus.
If we execute the instruction `mov [bx], ax` (assuming `AX` currently contains `0x9999`):
- `BX` has the same value
- The RAM at address `0x1000` now containts `0x9999`.

---

# 5. Data Size Ambiguity & Size Directives

## The Ambiguity Problem
Most of the time, the CPU can automatically deduce how many bytes you want to read from or write to memory by looking at the register you are using:
- `mox [bx], ax` -> `AX` is a 16-bit register. The CPU knows you want to write a 16-bit word (2 bytes) to memory.
- `mov [bx], al` -> `AL` is an 8-bit register. The CPU knows you want to write an 8-bit byte (1 byte) to memory.

But what happens if you write this instruction?
```
mov [bx], 1
```

Here, `[bx]` is a memory address and `1` is a constant number.
- Does the programmer want to write the syngle byte `0x01` (8-bit)?
- Or the word `0x0001` (16-bit)?

Neither the destination nor the source tells the assembler how much memory to modify. Because of this, NASM will throw a compilation error: **"operator size not specified"**

## The Solution: Size Specifiers
To resolve this ambiguity we must use size specifiers in NASM. We insert the keyword `byte` or `word` directly before the brackets to declare our intent:
- To write an 8-bit value (1 byte)
```
mov byte [bx], 1		; Writes 0x01 to memory
```
- To write a 16-bit value (2 bytes):
```
mov word [bx], 1		; Writes 0x0001 to memory
```
