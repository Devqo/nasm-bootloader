# Control Flow in Assembly

# 1. Linear Exectuion vs Branching

To understand control flow we have to look at the relentless cycle the CPU executes from the millisecond it powers on until its shut down.

## Concept 1: Sequential Execution (The Default Path)
The CPU works in a continuous three-step loop: **Fetch, Decode and Execute**.
1. **Fetch**: The CPU reads the binary bytes of the next instruction from physical memory at the location pointed to by `CS:IP`.
2. **Decode**: The CPU's control unit translates those binary bytes into physical signals to figure out what operation needs to be performed
3. **Execute**: The CPU performs the action (e.g. adding two registers)

Crucially, during the **Fetch** phase, the CPU automatically calculates how many bytes long the current instruction is and **increments the `IP` register** by that exact number of bytes

If the instruction at `0x7C00` is 3 bytes long, the CPU automatically updates `IP` to `0x7C03` before it even finishes executing the instruction. Because of this automatic increment, the CPU naturally marches straight forward through RAM in a single, linear line.

## Concept 2: Branching (Breaking the Line)
"Branching" is simply the act of distrupting the automatic linear progression.

At the hardware level, branching is incredibly simple: it is the act of forcing a new value into the `IP` register.

When you tell the CPU to jump to a different location in your code, you are instructing the CPU's hardware to discard the automatic increment it just calculated and overwrite the `IP` register with your target address. On the very next Fetch cycle, the CPu will read from your new address instead of the one that naturally came next.

---

# 2. Unconditional Jumps (jmp)

Now let us look at how we write unconditional jumps in actual Assembly code using NASM.

## 1- Symbolic Labels
In assembly, you don't write physical memory offsets like `jmp 0x7C20`. If you did, adding a single instruction in the middle of your program would shift all subsequent code and you would ahve to manually recalculate every jump address.

Instead, we use **labels**. A label is name followed by a colon (e.g. `start:` or `error_handler:`).

When you run NASM to assemble your code, NASM automatically calculates the physical offset of that label for you. You simply write:
```
jmp start			; NASM replaces "start" with the calculated memory offset
```

## 2- Near Jumps vs Far Jumps
At the hardware level, there are two physical types of unconditional jumps in Real Mode:
- **Near Jumps (Segment-Local)**: Modifies only the `IP` register. Because the `CS` register is completely untouched, exectuion jumps to a new offset within the same 64KB segment.
- **Far Jumps (Inter-Segment)**: Modifies both the `CS` **and** the `IP` registers at the exact same mo1- ment.

### The Far Jump Trick in Bootloaders
Recall from our memory segmentation lesson that different BIOSes boot your code with different initial segments: some start you at `0x0000:0x7C00` (where `CS = 0x0000`) and others start you at `0x07C0:0x0000` (where `CS = 0x07C0`).

To fix this discrepancy we write a **Far Jump** as the very first instruction in our bootloader. By performing a far jump to our entry point, we physically force `CS` and `IP` into a known, normalized state.

In NASM, a Far Jump syntax looks like this:
```
jmp 0x0000:start	; Forces CS to 0x0000 and IP to offset of "start"
```

---

# 3. Comparisons (cmp and the FLAGS register)

Before a CPU can make a decision (a conditional jump) it has to evaluate a condition. In x86 we do this by using the comparison instruction: `cmp`.

## The Hardware Mechanics of `cmp`
When you wrtie an instruction like `cmp ax, 10` the CPU performs a very simple hardware action: it subtracts the source from the destination.

However, there is a crucial difference between `cmp` and a standard subtraction instruction (`sub`): **the result of the subtraction is completely discarded**. The value inside the destination register (in this case, `AX`) remains entirely unchanged.

*So, what is the point?*

Even though the CPU throws away the math result, the subtraction physically updates the bits in the **FLAGS** register based on the outcome of that math.

Here is how flags represent hte mathematical relationship after a `cmp ax, bx` instruction:
1. **If `AX` is Equal to `BX`**:
	- The subtraction result is exactly zero
	- The CPU sets the **Zero Flag** to `1` (`ZF = 1`).
2. **If `AX` is Less Than `BX` (Unsigned)**:
	- Subtracting a larger number from a smaller number requires a borrow.
	- The CPU sets the **Carry Flag** to `1` (`CF = 1`).
	- Because the result is not zero, `ZF = 0`.
3. **If `AX` is Greater Than `BX` (Unsigned)**:
	- The subtraction requires no borrow so `CF = 0`.
	- The result is not zero so `ZF = 0`.

By checking the combination of `ZF` and `CF` the CPU instantly knows wether the first value was equal, less or greater than the second value.

---

# 4. Conditional Jumps

At the hardware level, a **conditional jump** is simply a flag-checker. It tells the CPU: "Inspect a specific flag in the FLAGS register. If that flag is set to the correct value, overwrite the `IP` register with our destination label. If not, do nothing and let linear execution continue".

## Common Conditional Jumps in Real Mode:

| Instruction | Meaning           | Flag State Checked      | Physical Hardware Behaviour                                   |
| ----------- | ----------------- | ----------------------- | ------------------------------------------------------------- |
| `je label`  | Jump if Equal     | `ZF == 1`               | Jumps if the last subtraction resulted in zero                |
| `jne label` | Jump if Not Equal | `ZF == 0`               | Jumps if the last subtraction resulted in a non-zero          |
| `jc label`  | Jump if Carry     | `CF == 1`               | Jumps if a borrow occurred (or if a BIOS operation failed)    |
| `jnc label` | Jump if No Carry  | `CF == 0`               | Jumps if no borrow occurred (or if a BIOS operation succeded) |
| `jb label`  | Jump if Below     | `CF == 1`              | Used for unsigned "less-than" checks                          |
| `ja label`  | Jump if Above     | `ZF == 0` and `CF == 0` | Used for unsigned "greater-than" checks                       |

### An Elegant Hardware Detail:
Notice that `jc` and `jb` check the exact same flag state (`CF == 1`).

Because they check the exact same physical condition, they are actually the exact same machine instruction inside the CPU core! If you compile `jc` or `jb`, NASM generates the exact same binary opcode (`0x72`). The CPU doesn't know the difference between "carry" and "below"; it onlo knows ho to check if `CF == 1`.

---

# 5. Loops in Assembly

In high-level languages you have structured blocks like `for` and `while` loops. In Assembly, a loop is built manually by combining a counter, a subtraction and a backward conditional jump.

There are two primary ways to write a loop in 16-bit x86 Assembly:

## Method 1: The Manual Loop Pattern
This is the most flexible and widely used method. You use a general-purpose register as a counter, decrement it and jump back if ithasn't reached zero:
```
mov bx, 5			; Load our counter (run 5 times)
my_loop:
; ... [do some work here] ...
dec bx				; Decrement BX by 1 (updates ZF automatically)
jnz my_loop		; Jump if Not Zero
```
*The Mechanics*: The `dec bx` instruction subtracts 1 from `BX` and automatically updates the FLAGS register. As long as `BX` is not zero, the Zero Flag is `0` and `jnz` (Jump if Not Zero) jumps back to the label.
*Note that jnz here does the same thing as jne as it is an alias. The opcode generated is the same (`0x75`).*

## Method 2: The Hardware `loop` instruction
The x86 architecture also has a dedicated hardware instruction designed specifically for loops: `loop`.

When you write `loop my_loop` the CPU perofrms two hardware actions in a single step:
1. It automatically subtracts 1 from the `CX` register.
2. If `CX` is not yet zero, it jumps back to the specified label.
*The Constraint*: The hardware `loop` instruction is hard-wired to use **strictly the CX register** as the counter. You cannot configue it to use `AX`, `BX` or any other register.

Suppose we write a loop to print a character 10 times using the hardware `loop` instruction:
```
mov cx, 10
print_loop:
; ... [code to print a character] ...
loop print_loop
```
If for any reason some code sets `CX` to 0, `loop` would decrease `CX` making it overflow to `0xFFFF` (65,535 in decimal). Therefore, the loop would repeat 65,535 more times until it finally reached 0.
