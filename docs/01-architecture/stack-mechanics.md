# Stack Mechanics

# 1. The Stack Concept: LIFO in Hardware

To understand the stack we need to look at how the CPU organizes temporary data inside a single, dedicated structure in physical RAM.

## Concept 1: Last-IN, First-Out (LIFO)
The stack is a data structure governed by the **Last-In, First-Out (LIFO)** principle.

Think of a stack of heavy cafeteria trays or dinner plates:
1. You can only place a new plate on the very top of the pile (This is our `PUSH` operation).
2. You can only remove a plate from the very top of the pile (This is our `POP` operation).
3. If you want to get to the plate at the bottom of the pile, you must first remove all the plates sitting on top of it.

If you push Value A, then Value B, then Value C onto the stack, you *must* pop them off in the reverse order (C->B->A)

## Concept 2: The Downward-Growing Nature of the Stack
In physical world analogies, a stack of plates grows upwards toward the ceiling. In x86 computer architecture, the stack grows **downward** toward lower physical memory addresses.

When you initialize your stack, you define its base (its starting position in memory) using `SS:SP`.
- Let's say we set `SS = 0x0000` and `SP = 0x7C00`
- Our stack starts at the physical address `0x07C00`

Because a single slot on the Real Mode stack is **16 bits** (which occupies exactly **2 bytes** of physical memory), every time you push data onto the stack, the CPU does the following in physical RAM:
1. It decrements the `SP` register by **2** (moving it to a lower memory address).
2. It writes your 2-byte data value to the physical address pointer to by the new `SS:SP`.

By substracting from `SP`, the stack grows downward toward `0x00000`, away from your bootloader's code.

---

# 2. Stack Registers: SS and SP

To use the stack, the CPU Relies on two specific registers working together. 

## 1- Defining the Stack Base (`SS:SP`)
Like data segments, the stack uses the standard `Segment:Offset` calculation.
- **`SS` (Stack Segment)**: Defines the 64KB block of RAM where your stack lives.
- **`SP` (Stack Pointer)**: Holds the offset pointing to the *current top* of the stack.

When you first set up your stack, you load `SS` with a segment and `SP` with the starting offset. Because the stack grows downward, `SP` should start at the **highest** offset of your memory region.

## 2- The 16-Bit Word Constraint
In 16-bit Real Mode, the stack physically enforces a rule: **You can only push and pop 16-bit values (words).

If you try to run an instruction like `push al` (which is an 8-bit register), the CPU hardware will throw an error or refuse to assemble. The hardware is physically wired to decrement the `SP` register by exactly 2 bytes for every stack operation.

This ensures that the stack is always "word-aligned" (all offsets are even numbers), which keeps memory access fast and predictable for the CPU.

However, there is a workaround.

Suppose you want to temporarily save the value of the 8-bit register `AL` on the stack.
Since the hardware does not allow you to push an 8-bit register directly, you can push the full `AX` register (which contains `AL`) instead. 
Because you're pushing the whole `AX` this will consume 2 bytes of your stack instead of 1.

---

# 3. The Mechanics of PUSH and POP

Now let us look at the exact step-by-step sequence of events that occurs inside the CPU when you execute a `POP` or `POP` instruction.

## The `PUSH` Mechanism
When you write an instruction like `push ax` the CPU doesn't write to the current offset of `SP` immeditaely. Instead, it performs these two steps in this exact hardware order:
1. It first subtracts 2 from the `SP` register.
2. Then, the CPU writes the 16-bit value of `AX` into the RAM address pointed to by `SS:SP`.

*Why does it decrement first?*
Because `SP` always points to the *currently occupied* top of the stack. If the CPU wrote first and then decremented, it would overwrite the active data already sitting at the top of the stack.

## The `POP` Mechanism
The `POP` instruction does the exact opposite, but the order of operations is reversed:
1. The CPU reads the 16-bit value stored in RAM at the address pointed to by the current `SS:SP` and copies it into our destination register (e.g. `pop bx`).
2. Then it adds 2 to the `SP` register.

---

# 4. Function Calls and Stack Control Flow

This is one of the most elegant parts of computer architecture. It explains how a CPU (which only knows how to execute instructions sequentially) can jump to a function (subroutine), run it and then magically "remember" how to get back to where it left off.

It does this entirely by using the stack.

## The `CALL` Instruction
When you wrtie an instruction like `call print_character` the CPU performs two actions automatically behind the scenes:
1. It automatically **pushes** the current value of `IP` onto the stack (this saved value is the address of hte instruction *immediately following* the `call` instruction).
2. Then it overwrites `IP` with the address of the `print_character` label, forcing execution to jump to your function.

## The `RET` Instruction
At the end of your function you write the `ret` (Return) instruction. When the CPU hits `ret` it performs the reverse action automatically:
1. The CPU **pops** the value currently sitting at the top of the stack and writes it directly into the `IP` register.
2. Because `IP` now holds the saved return address, the CPU automatically continues executing the main program right after the original `call`

## The Trap: An Unbalanced Stack
Becuase `ret` blindly pops whatever is at the top of the stack and jumps to it, you must be extremely careful.

If you use the stack *inside* your function, you must leave the stack in the exact same state you found it before executing `ret`.

Let's trace a stack crash to see this in action:

Suppose your main program is running. It executes `call load_data` at memory offset `0x7C10`. The instruction immediately following it sits at offset `0x7C13`.

Inside the `load_data` function you want to temporarily save the `DX` register, which currently contains the value `0x1234`. So, the very first line of your function is `push dx`.

At the end of the `load_data` function, you write `ret`, but you forgot to write `pop dx` before it.
1. When the `call load_data` instruction was first executed, `0x7C13` was pushed to the top of the stack
2. When the CPU reaches the `ret` instruction at the end of the function, `0x1234` is sitting on top of the stack.
3. When `ret` executes, it's `0x1234` which gets popped into the `IP` register.

---

# 5. Preserving Registers (Context Saving)

Let us look at how the stack is used to solve a massive programming problem in assembly: **register scarcity**.

In high-level languages, you can create thousands of variables. In 16-bit Assembly, you only have a handful of GPRs.

Imagine your main program is uisng `AX` to keep track of a very important count. Inside your main program, you need to call a function to print a character. But the print function *also* needs to use the `AX` register to make its BIOS call.

If the print function just uses `AX`, it will overwrite your main program's count!

## The Solution: Context Saving
To prevent functions from destroying the main program's register values, we use the stack to save and restore them.
1. At the very beginning of the function, we `PUSH` any registers the function is going to modify.
2. The function runs and freely uses those registers for its own tasks.
3. At the very end of the function (just before `ret`), we `POP` those registers back into their original places.

Because of the LIFO nature of the stack, we must pop them in the exact reverse order of how we pushed them.

Suppose you are writing a custom memory-copying function. To do its job, this function needs to use three registers: `AX`, `CX` and `SI`.

To protect your main program, you decide to preserve these registers. At the start of your function, you write these instructions in this order:
```
push ax
push cx
push si
```

1. At the end of the function, you must `pop` them in this order: `SI` -> `CX` -> `AX`
2. If you accidentally popped them in the same order you pushed them, `SI` would be in `AX` and `AX` would in `SI`
