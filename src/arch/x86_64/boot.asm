global start
extern long_mode_start

section .text
bits 32
start:
  mov esp, stack_top
  call check_multiboot
  call check_cpuid
  call check_long_mode
  call set_up_page_tables
  call enable_paging
  call set_up_SSE

  lgdt [gdt64.pointer]

  mov ax, gdt64.data
  mov ss, ax
  mov ds, ax
  mov es, ax

  jmp gdt64.code:long_mode_start
check_multiboot:
  cmp eax, 0x36d76289
  jne .no_multiboot
  ret
  .no_multiboot:
  mov al, "0"
  jmp error
    ; Prints `ERR: ` and the given error code to screen and hangs.
    ; parameter: error code (in ascii) in al
error:
  mov dword [0xb8000], 0x4f524f45
  mov dword [0xb8004], 0x4f3a4f52
  mov dword [0xb8008], 0x4f204f20
  mov byte  [0xb800a], al
  hlt

check_cpuid: ; copied from osDEV
  pushfd
  pop eax
  ; Copy to ECX as well for comparing later on
  mov ecx, eax
  ; Flip the ID bit
  xor eax, 1 << 21
  ; Copy EAX to FLAGS via the stack
  push eax
  popfd
  ; Copy FLAGS back to EAX (with the flipped bit if CPUID is supported)
  pushfd
  pop eax
  ; Restore FLAGS from the old version stored in ECX (i.e. flipping the
  ; ID bit back if it was ever flipped).
  push ecx
  popfd
  ; Compare EAX and ECX. If they are equal then that means the bit
  ; wasn't flipped, and CPUID isn't supported.
  cmp eax, ecx
  je .no_cpuid
  ret
  .no_cpuid:
  mov al, "1"
  jmp error

check_long_mode: ; copied from OSDev
  ; test if extended processor info in available
  mov eax, 0x80000000    ; implicit argument for cpuid
  cpuid                  ; get highest supported argument
  cmp eax, 0x80000001    ; it needs to be at least 0x80000001
  jb .no_long_mode       ; if it's less, the CPU is too old for long mode
  ; use extended info to test if long mode is available
  mov eax, 0x80000001    ; argument for extended processor info
  cpuid                  ; returns various feature bits in ecx and edx
  test edx, 1 << 29      ; test if the LM-bit is set in the D-register
  jz .no_long_mode       ; If it's not set, there is no long mode
  ret
  .no_long_mode:
  mov al, "2"
  jmp error

set_up_page_tables:
  ; map first P4 entry to adress of P3 table
  mov eax, p3_table
  or eax, 0b11 ; set present and writable bits
  mov [p4_table], eax

  mov eax, p2_table
  or eax, 0b11
  mov [p3_table], eax

  ;  map each P2 entry to a huge 2MiB page
  mov ecx, 0         ; counter variable

  .map_p2_table:
  ;loop through 512 entries and map one huge page
  mov eax, 0x200000  ; 2MiB
  mul ecx            ; start address of i-th page
  or eax, 0b10000011 ; present + writable + huge
  mov [p2_table + ecx * 8], eax ; map i-th entry
  inc ecx            ; increase counter
  cmp ecx, 512       ; if counter == 512, the whole P2 table is mapped
  jne .map_p2_table  ; else map the next entry
ret

enable_paging:
  ; make p4 known to cpu
  mov eax, p4_table
  mov cr3, eax
  ; enable 36 bit physical address extension
  mov eax, cr4
  or eax, 1 << 5
  mov cr4, eax
  ; load msr and enable long mode (all the memory! yay!)
  mov ecx, 0xC0000080
  rdmsr
  or eax, 1 << 8
  wrmsr
  ; enable paging in cr0 register
  mov ecx, cr0
  or ecx, 1 << 31
  mov cr0, ecx
ret


  ; Check for streaming SIMD extensions and enable them
  ; copied from osDEV
set_up_SSE:
  ; check for SSE
  mov eax, 0x1
  cpuid
  test edx, 1<<25
  jz .no_SSE
  ; enable SSE
  mov eax, cr0
  and ax, 0xFFFB      ; clear coprocessor emulation CR0.EM
  or ax, 0x2          ; set coprocessor monitoring  CR0.MP
  mov cr0, eax
  mov eax, cr4
  or ax, 3 << 9       ; set CR4.OSFXSR and CR4.OSXMMEXCPT at the same time
  mov cr4, eax
ret
  .no_SSE:
  mov al, "a"
  jmp error

; ---  read only memory section
section .rodata
gdt64:
  dq 0 ; zero boundary
  .code: equ $ - gdt64
    dq (1 << 44) | (1<<47) | (1<<41) | (1<<43) | (1<<53) ; code segment
  .data: equ $ - gdt64
    dq (1<<44) | (1<<47) | (1<<41) ; data segment

.pointer:
  dw $ - gdt64 - 1
  dq gdt64

; --- static variable initialization: stack and paging
section .bss
align 4096
p4_table:
  resb 4096
p3_table:
  resb 4096
p2_table:
  resb 4096
stack_bottom:
  resb 64
stack_top:
