@
@ mycelia.s -- A bare-metal actor kernel for Raspberry Pi
@
@ Copyright 2014 Dale Schumacher, Tristan Slominski
@
@ Licensed under the Apache License, Version 2.0 (the "License");
@ you may not use this file except in compliance with the License.
@ You may obtain a copy of the License at
@
@ http://www.apache.org/licenses/LICENSE-2.0
@
@ Unless required by applicable law or agreed to in writing, software
@ distributed under the License is distributed on an "AS IS" BASIS,
@ WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
@ See the License for the specific language governing permissions and
@ limitations under the License.
@
@ View this file with hard tabs every 8 positions.
@	|	|	.	|	.	.	.	.  max width ->
@       |       |       .       |       .       .       .       .  max width ->
@ If your tabs are set correctly, the lines above should be aligned.
@

@ Special register usage:
@   sl (r10) the sponsor providing resources for this computation
@   fp (r11) the event being processed, including the message and target actor
@   ip (r12) the base address of the target actor

	.text
	.align 2		@ alignment 2^n (2^2 = 4 byte machine word)
	.global mycelia
mycelia:		@ entry point for the actor kernel (r0=bootstrap actor)
	mov	ip, r0		@ bootstrap actor address
	ldr	r0, =exit_to	@ location of return address
	str	lr, [r0]	@ save exit address on entry
	ldr	sl, =sponsor_0	@ initialize sponsor link
	bl	reserve		@ allocate event block
	str	ip, [r0]	@ set target actor
	bl	enqueue		@ add event to queue
	b	dispatch	@ start dispatch loop

	.text
	.align 2		@ align to machine word
	.global exit
exit:			@ exit the actor kernel
	ldr	r0, =exit_to	@ location of return address
	ldr	lr, [r0]	@ get exit address saved on entry
	bx	lr		@ "return" from the kernel
	.data
	.align 2		@ align to machine word
exit_to:
	.int 0			@ address to "return" to on exit

	.text
	.align 2		@ align to machine word
	.global complete
complete:		@ completion of event pointed to by fp
	mov	r0, fp		@ get completed event
	bl	release		@ free completed event
	mov	fp, #0		@ clear frame pointer
	str	fp, [sl, #1028]	@ clear current event
	.global dispatch
dispatch:		@ dispatch next event
	bl	dequeue		@ try to get next event
	cmp	r0, #0		@ check for null
	beq	dispatch	@ if no event, try again...
	mov	fp, r0		@ initialize frame pointer
	str	fp, [sl, #1028]	@ update current event
	ldr	ip, [fp]	@ get target actor address
	bx	ip		@ jump to actor behavior

	.text
	.align 2		@ align to machine word
	.global reserve
reserve:		@ reserve a block (32 bytes) of memory
	ldr	r1, =block_free	@ address of free list pointer
	ldr	r0, [r1]	@ address of first free block
	cmp	r0, #0
	beq	1f		@ if not null
	ldr	r2, [r0]	@	follow link to next free block
	str	r2, [r1]	@	update free list pointer
	bx	lr		@	return
1:				@ else
	stmdb	sp!, {lr}	@	preserve link register
	ldr	r1, =block_end	@	address of block end pointer
	ldr	r0, [r1]	@	address of new memory block
	add	r2, r0, #32	@	calculate next block address
	str	r2, [r1]	@	update block end pointer
	bl	release		@	"free" new memory block
	ldmia	sp!, {lr}	@	restore link register
	b	reserve		@	try again

	.global release
release:		@ release the memory block pointed to by r0
	cmp	r0, sl		@ [FIXME] sanity check
	blt	panic		@ [FIXME] halt on bad address
	stmdb	sp!, {r4-r9,lr}	@ preserve in-use registers
	ldr	r1, =block_free	@ address of free list pointer
	ldr	r2, [r1]	@ address of next free block
	str	r0, [r1]	@ update free list pointer
	ldr	r1, =block_clr	@ address of block-erase pattern
	ldmia	r1, {r3-r9}	@ read 7 words (32 - 4 bytes)
	stmia	r0, {r2-r9}	@ write 8 words (incl. next free block pointer)
	ldmia	sp!, {r4-r9,pc}	@ restore in-use registers and return

	.section .rodata
	.align 5		@ align to cache-line
block_clr:
	.ascii "Who is licking my HONEYPOT?\0"

	.data
	.align 2		@ align to machine word
block_free:
	.int 0			@ pointer to next free block, 0 if none
block_end:
	.int heap_start		@ pointer to end of block memory

	.text
	.align 2		@ align to machine word
	.global enqueue
enqueue:		@ enqueue event pointed to by r0
	cmp	r0, sl		@ [FIXME] sanity check
	blt	panic		@ [FIXME] halt on bad address
	ldr	r1, [r0]	@ [FIXME] get target actor
	cmp	r1, sp		@ [FIXME] sanity check
	blt	panic		@ [FIXME] halt on bad address
	ldr	r1, [sl, #1024]	@ event queue head/tail indicies
	uxtb	r2, r1, ROR #8	@ get head index
	uxtb	r3, r1, ROR #16	@ get tail index
	str	r0, [sl,r3,LSL #2] @ store event pointer at tail
	add	r3, r3, #1	@ advance tail
	cmp	r2, r3		@ if queue full
	beq	panic		@	kernel panic!
	strb	r3, [sl, #1026]	@ update tail index
	bx	lr		@ return

dequeue:		@ dequeue next event from queue
	ldr	r1, [sl, #1024]	@ event queue head/tail indicies
	uxtb	r2, r1, ROR #8	@ get head index
	uxtb	r3, r1, ROR #16	@ get tail index
	cmp	r2, r3		@ if queue empty
	moveq	r0, #0		@	return null
	ldrne	r0, [sl,r2,LSL #2] @ else
	addne	r2, r2, #1	@	advance head
	strneb	r2, [sl, #1025]	@	update head index
	bx	lr		@	return event pointer

	.data
	.align 5		@ align to cache-line
sponsor_0:
	.space 256*4		@ event queue (offset 0)
	.int 0			@ queue head/tail (offset 1024)
	.int 0			@ current event (offset 1028)

	.text
	.align 5		@ align to cache-line
example_0:
	bl	reserve		@ allocate event block
	ldr	r1, [ip, #0x1c] @ get answer
	.global _a_answer
_a_answer:		@ send answer to customer and return (r0=event, r1=answer)
	str	r1, [r0, #0x04]	@ set answer
	.global _a_reply
_a_reply:		@ reply to customer and return from actor (r0=event)
	ldr	r1, [fp, #0x04]	@ get customer
	.global _a_send
_a_send:		@ send a message and return from actor (r0=event, r1=target)
	str	r1, [r0]	@ set target actor
	.global _a_end
_a_end:			@ queue message and return from actor (r0=event)
	bl	enqueue		@ add event to queue
	b	complete	@ return to dispatch loop
	.int	0x42424242	@ answer data

	.text
	.align 5		@ align to cache-line
example_1:
	ldr	pc, [pc, #-4]	@ jump to actor behavior
	.int	complete	@ 0x04: address of actor behavior
	.int	0x11111111	@ 0x08: state field 1
	.int	0x22222222	@ 0x0c: state field 2
	.int	0x33333333	@ 0x10: state field 3
	.int	0x44444444	@ 0x14: state field 4
	.int	0x55555555	@ 0x18: state field 5
	.int	0x66666666	@ 0x1c: state field 6

	.text
	.align 5		@ align to cache-line
example_2:
	ldr	lr, [pc]	@ get actor behavior address
	blx	lr		@ jump to behavior, lr points to state
	.int	complete	@ 0x08: address of actor behavior
	.int	0x11111111	@ 0x0c: state field 1
	.int	0x22222222	@ 0x10: state field 2
	.int	0x33333333	@ 0x14: state field 3
	.int	0x44444444	@ 0x18: state field 4
	.int	0x55555555	@ 0x1c: state field 5

	.text
	.align 5		@ align to cache-line
template_1:
	mov	ip, pc		@ point ip to data fields (state)
	ldmia	ip, {r4,pc}	@ copy state and jump to behavior
	.int	0		@ 0x08: value for r4
	.int	complete	@ 0x0c: address of actor behavior

	.text
	.align 5		@ align to cache-line
template_2:
	mov	ip, pc		@ point ip to data fields (state)
	ldmia	ip, {r4-r5,pc}	@ copy state and jump to behavior
	.int	0		@ 0x08: value for r4
	.int	0		@ 0x0c: value for r5
	.int	complete	@ 0x10: address of actor behavior

	.text
	.align 5		@ align to cache-line
template_3:
	mov	ip, pc		@ point ip to data fields (state)
	ldmia	ip, {r4-r6,pc}	@ copy state and jump to behavior
	.int	0		@ 0x08: value for r4
	.int	0		@ 0x0c: value for r5
	.int	0		@ 0x10: value for r6
	.int	complete	@ 0x14: address of actor behavior

	.text
	.align 5		@ align to cache-line
example_3:
	mov	ip, pc		@ point ip to data fields (state)
	ldmia	ip,{r4-r8,pc}	@ copy state and jump to behavior
	.int	0		@ 0x08: value for r4
	.int	0		@ 0x0c: value for r5
	.int	0		@ 0x10: value for r6
	.int	0		@ 0x14: value for r7
	.int	0		@ 0x18: value for r8
	.int	complete	@ 0x1c: address of actor behavior

	.text
	.align 2		@ align to machine word
	.global create
create:			@ create an actor from example_3 (r0=behavior)
	stmdb	sp!, {r4-r9,lr}	@ preserve in-use registers
	mov	r9, r0		@ move behavior pointer into place
	bl	reserve		@ allocate actor block
	ldr	r1, =example_3	@ load template address
	ldmia	r1, {r2-r8}	@ read template (minus behavior)
	stmia	r0, {r2-r9}	@ write actor
	ldmia	sp!, {r4-r9,pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global create_0
create_0:		@ create an actor from example_1 (r0=behavior)
	stmdb	sp!, {r4,lr}	@ preserve in-use registers
	mov	r4, r0		@ move behavior pointer into place
	bl	reserve		@ allocate actor block
	ldr	r1, =example_1	@ load template address
	ldmia	r1, {r3}	@ read template (minus behavior)
	stmia	r0, {r3-r4}	@ write actor
	ldmia	sp!, {r4,pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global create_1
create_1:		@ create 1 parameter actor (r0=behavior, r1=r4)
	stmdb	sp!, {r4-r5,lr}	@ preserve in-use registers
	mov	r4, r1		@ move state parameter into place
	mov	r5, r0		@ move behavior pointer into place
	bl	reserve		@ allocate actor block
	ldr	r1, =template_1	@ load template address
	ldmia	r1, {r2-r3}	@ read template (code only)
	stmia	r0, {r2-r5}	@ write actor
	ldmia	sp!, {r4-r5,pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global create_2
create_2:		@ create 2 parameter actor (r0=behavior, r1=r4, r2=r5)
	stmdb	sp!, {r4-r6,lr}	@ preserve in-use registers
	mov	r4, r1		@ move 1st state parameter into place
	mov	r5, r2		@ move 2nd state parameter into place
	mov	r6, r0		@ move behavior pointer into place
	bl	reserve		@ allocate actor block
	ldr	r1, =template_2	@ load template address
	ldmia	r1, {r2-r3}	@ read template (code only)
	stmia	r0, {r2-r6}	@ write actor
	ldmia	sp!, {r4-r6,pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global create_3x
create_3x:		@ create 3 parameter actor (r4-r6=state, r7=behavior)
	stmdb	sp!, {lr}	@ preserve in-use registers
	bl	reserve		@ allocate actor block
	ldr	r1, =template_3	@ load template address
	ldmia	r1, {r2-r3}	@ read template (code only)
	stmia	r0, {r2-r7}	@ write actor
	ldmia	sp!, {pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global send
send:			@ send 1 parameter message (r0=target, r1-r7=message)
	stmdb	sp!, {r4-r8,lr}	@ preserve in-use registers
	stmdb	sp!, {r0-r7}	@ preserve event data
	bl	reserve		@ allocate event block
	ldmia	sp!, {r1-r8}	@ restore event data
	stmia	r0, {r1-r8}	@ write data to event
	bl	enqueue		@ add event to queue
	ldmia	sp!, {r4-r8,pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global send_0
send_0:			@ send 0 parameter message (r0=target)
	stmdb	sp!, {lr}	@ preserve in-use registers
	stmdb	sp!, {r0}	@ preserve event data
	bl	reserve		@ allocate event block
	ldmia	sp!, {r1}	@ restore event data
	stmia	r0, {r1}	@ write data to event
	bl	enqueue		@ add event to queue
	ldmia	sp!, {pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global send_1
send_1:			@ send 1 parameter message (r0=target, r1=message)
	stmdb	sp!, {lr}	@ preserve in-use registers
	stmdb	sp!, {r0-r1}	@ preserve event data
	bl	reserve		@ allocate event block
	ldmia	sp!, {r1-r2}	@ restore event data
	stmia	r0, {r1-r2}	@ write data to event
	bl	enqueue		@ add event to queue
	ldmia	sp!, {pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global send_2
send_2:			@ send 2 parameter message (r0=target, r1-r2=message)
	stmdb	sp!, {lr}	@ preserve in-use registers
	stmdb	sp!, {r0-r2}	@ preserve event data
	bl	reserve		@ allocate event block
	ldmia	sp!, {r1-r3}	@ restore event data
	stmia	r0, {r1-r3}	@ write data to event
	bl	enqueue		@ add event to queue
	ldmia	sp!, {pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global send_3x
send_3x:		@ send 3 parameter message (r4=target, r5-r7=message)
	stmdb	sp!, {lr}	@ preserve in-use registers
	bl	reserve		@ allocate event block
	stmia	r0, {r4-r7}	@ write data to event
	bl	enqueue		@ add event to queue
	ldmia	sp!, {pc}	@ restore in-use registers and return

	.text
	.align 2		@ align to machine word
	.global watchdog
watchdog:		@ set a watchdog timer (r0=timeout, r1=customer)
			@ returns r0=cancel_cap
	stmdb	sp!, {r4-r7,lr}	@ preserve in-use registers
	mov	r6, r0		@ copy timeout
	mov	r5, r1		@ copy customer
	bl	timer_usecs	@ get current timer value
	add	r4, r0, r6	@ calculate limit
	ldr	r7, =b_watchdog	@ get watchdog behavior
	bl	create_3x	@ create watchdog actor
	mov	r6, r0		@ r6 = watchdog pointer
	bl	send_0		@ send empty message to watchdog
	bl	reserve		@ allocate block for cancel actor
	ldr	r1, =a_wd_cancel@ get actor template
	ldmia	r1,{r2-r5}	@ copy template (minus watchdog pointer)
	stmia	r0,{r2-r6}	@ write actor (including watchdog pointer)
	ldmia	sp!, {r4-r7,pc}	@ restore in-use registers and return
	.align 5		@ align to cache-line
b_watchdog:		@ watchdog timer behavior (r4=limit, r5=customer)
	cmp	r5, #0		@ if cancelled
	beq	complete	@	ignore (don't send any more messages)
	bl	timer_usecs	@ get current timer value
	subs	r0, r0, r4	@ (now - limit) = past if <0, future if >0
	sublt	r0, ip, #8	@ if past, send to self (ip adjusted)
	movge	r0, r5		@ if now or future, send to customer
	bl	send_0		@ send empty message
	b	complete	@ return to dispatch loop
	.align 5		@ align to cache-line
a_wd_cancel:		@ watchdog cancel template
	ldr	r0, [ip, #0x10]	@ get watchdog actor
	mov	r1, #0
	str	r1, [r0, #0x10]	@ clear watchdog customer
	b	complete	@ return to dispatch loop
	.int	complete	@ 0x10: watchdog actor
	.int	0		@ 0x14: --
	.int	0		@ 0x18: --
	.int	0		@ 0x1c: --

	.text
	.align 2		@ align to machine word
@	.global test_suite
test_suite:		@ suite of automated unit-tests
	stmdb	sp!, {r4-r9,lr}	@ preserve in-use registers
	@ ...create tests here...
	ldr	r1, =a_test_ok	@ get suite finished actor
	bl	send_0		@ send message to report completion
	ldmia	sp!, {r4-r9,pc}	@ restore in-use registers and return

	.text
	.align 5		@ align to cache-line
	.global a_test_ok
a_test_ok:		@ succesful completion of test suite
	ldr	r1, =a_test	@ get test-runner actor
	ldr	r0, [r1, #0x1c]	@ get watchdog cancel capability
	bl	send_0		@ send message to cancel watchdog
	ldr	r1, =a_passed	@ get success actor
	bl	send_0		@ send message to report success
	b	complete	@ return to dispatch loop
	.int	0		@ 0x18: --
	.int	0		@ 0x1c: --

	.text
	.align 5		@ align to cache-line
	.global a_test
a_test:			@ initiate unit tests
	mov	r1, #1000	@ 1 millisecond
	mul	r0, r1, r1	@ 1 second
	ldr	r1, =a_failed	@ fail after 1 second
	bl	watchdog	@ set up watchdog timer
	str	r0, [ip, #0x1c]	@ remember cancel capability
	bl	test_suite	@ run suite of unit-tests
	b	complete	@ return to dispatch loop
	.int	complete	@ 0x1c: cancel capability

	.text
	.align 5		@ align to cache-line
	.global a_passed
a_passed:		@ report tests passed, and exit
	add	r0, ip, #0x18	@ address of output text
	bl	serial_puts	@ write output text
	bl	serial_eol	@ write end-of-line
	b	exit		@ kernel exit!
	.int	0		@ 0x10: --
	.int	0		@ 0x14: --
	.ascii	"Passed.\0"	@ 0x18..0x1f: output text

	.text
	.align 5		@ align to cache-line
	.global a_failed
a_failed:		@ report tests failed, and exit
	add	r0, ip, #0x18	@ address of output text
	bl	serial_puts	@ write output text
	bl	serial_eol	@ write end-of-line
	b	exit		@ kernel exit!
	.int	0		@ 0x10: --
	.int	0		@ 0x14: --
	.ascii	"FAILED!\0"	@ 0x18..0x1f: output text

	.text
	.align 2		@ align to machine word
	.global panic
panic:			@ kernel panic!
	stmdb	sp!, {r0-r3,lr}	@ preserve registers
	ldr	r0, =panic_txt	@ load address of panic text
	bl	serial_puts	@ write text to console
	ldmia	sp!, {r0-r3,lr}	@ restore registers
	b	halt
	.section .rodata
panic_txt:
	.ascii "\nPANIC!\0"

	.section .heap
	.align 5		@ align to cache-line
heap_start:
