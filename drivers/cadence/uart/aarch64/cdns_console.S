/*
 * Copyright (c) 2016-2017, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include <arch.h>
#include <asm_macros.S>
#include <assert_macros.S>
#include <cadence/cdns_uart.h>
#define USE_FINISH_CONSOLE_REG_2
#include <console_macros.S>

	/*
	 * "core" functions are low-level implementations that don't require
	 * writable memory and are thus safe to call in BL1 crash context.
	 */
	.globl console_cdns_core_init
	.globl console_cdns_core_putc
	.globl console_cdns_core_getc
	.globl console_cdns_core_flush

	.globl  console_cdns_putc
	.globl  console_cdns_getc
	.globl  console_cdns_flush

	/* -----------------------------------------------
	 * int console_cdns_core_init(uintptr_t base_addr)
	 * Function to initialize the console without a
	 * C Runtime to print debug information. This
	 * function will be accessed by console_init and
	 * crash reporting.
	 * We assume that the bootloader already set up
	 * the HW (baud, ...) and only enable the trans-
	 * mitter and receiver here.
	 * In: x0 - console base address
	 * Out: return 1 on success else 0 on error
	 * Clobber list : x1, x2, x3
	 * -----------------------------------------------
	 */
func console_cdns_core_init
	/* Check the input base address */
	cbz	x0, core_init_fail

	/* RX/TX enabled & reset */
	mov	w3, #(R_UART_CR_TX_EN | R_UART_CR_RX_EN | R_UART_CR_TXRST | R_UART_CR_RXRST)
	str	w3, [x0, #R_UART_CR]

	mov	w0, #1
	ret
core_init_fail:
	mov	w0, wzr
	ret
endfunc console_cdns_core_init

#if MULTI_CONSOLE_API
	.globl console_cdns_register

	/* -----------------------------------------------
	 * int console_cdns_register(uint64_t baseaddr,
	 *     uint32_t clock, uint32_t baud,
	 *     console_cdns_t *console);
	 * Function to initialize and register a new CDNS
	 * console. Storage passed in for the console struct
	 * *must* be persistent (i.e. not from the stack).
	 * In: x0 - UART register base address
	 *     x1 - pointer to empty console_cdns_t struct
	 * Out: return 1 on success, 0 on error
	 * Clobber list : x0, x1, x2, x6, x7, x14
	 * -----------------------------------------------
	 */
func console_cdns_register
	mov	x7, x30
	mov	x6, x1
	cbz	x6, register_fail
	str	x0, [x6, #CONSOLE_T_CDNS_BASE]

	bl	console_cdns_core_init
	cbz	x0, register_fail

	mov	x0, x6
	mov	x30, v7
	finish_console_register cdns putc=1, getc=1, flush=1

register_fail:
	ret	x7
endfunc console_cdns_register
#else
	.globl console_core_init
	.globl console_core_putc
	.globl console_core_getc
	.globl console_core_flush
	.equ console_core_init,console_cdns_core_init
	.equ console_core_putc,console_cdns_core_putc
	.equ console_core_getc,console_cdns_core_getc
	.equ console_core_flush,console_cdns_core_flush
#endif

	/* --------------------------------------------------------
	 * int console_cdns_core_putc(int c, uintptr_t base_addr)
	 * Function to output a character over the console. It
	 * returns the character printed on success or -1 on error.
	 * In : w0 - character to be printed
	 *      x1 - console base address
	 * Out : return -1 on error else return character.
	 * Clobber list : x2
	 * --------------------------------------------------------
	 */
func console_cdns_core_putc
#if ENABLE_ASSERTIONS
	cmp	x1, #0
	ASM_ASSERT(ne)
#endif /* ENABLE_ASSERTIONS */

	/* Prepend '\r' to '\n' */
	cmp	w0, #0xA
	b.ne	2f
1:
	/* Check if the transmit FIFO is full */
	ldr	w2, [x1, #R_UART_SR]
	tbnz	w2, #UART_SR_INTR_TFUL_BIT, 1b
	mov	w2, #0xD
	str	w2, [x1, #R_UART_TX]
2:
	/* Check if the transmit FIFO is full */
	ldr	w2, [x1, #R_UART_SR]
	tbnz	w2, #UART_SR_INTR_TFUL_BIT, 2b
	str	w0, [x1, #R_UART_TX]
	ret
endfunc console_cdns_core_putc

	/* --------------------------------------------------------
	 * int console_cdns_putc(int c, console_cdns_t *cdns)
	 * Function to output a character over the console. It
	 * returns the character printed on success or -1 on error.
	 * In : w0 - character to be printed
	 *      x1 - pointer to console_t structure
	 * Out : return -1 on error else return character.
	 * Clobber list : x2
	 * --------------------------------------------------------
	 */
func console_cdns_putc
#if ENABLE_ASSERTIONS
	cmp	x1, #0
	ASM_ASSERT(ne)
#endif /* ENABLE_ASSERTIONS */
	ldr	x1, [x1, #CONSOLE_T_CDNS_BASE]
	b	console_cdns_core_putc
endfunc console_cdns_putc

	/* ---------------------------------------------
	 * int console_cdns_core_getc(uintptr_t base_addr)
	 * Function to get a character from the console.
	 * It returns the character grabbed on success
	 * or -1 if no character is available.
	 * In : x0 - console base address
	 * Out: w0 - character if available, else -1
	 * Clobber list : x0, x1
	 * ---------------------------------------------
	 */
func console_cdns_core_getc
#if ENABLE_ASSERTIONS
	cmp	x0, #0
	ASM_ASSERT(ne)
#endif /* ENABLE_ASSERTIONS */

	/* Check if the receive FIFO is empty */
	ldr	w1, [x0, #R_UART_SR]
	tbnz	w1, #UART_SR_INTR_REMPTY_BIT, no_char
	ldr	w1, [x0, #R_UART_RX]
	mov	w0, w1
	ret
no_char:
	mov	w0, #ERROR_NO_PENDING_CHAR
	ret
endfunc console_cdns_core_getc

	/* ---------------------------------------------
	 * int console_cdns_getc(console_cdns_t *console)
	 * Function to get a character from the console.
	 * It returns the character grabbed on success
	 * or -1 if no character is available.
	 * In : x0 - pointer to console_t structure
	 * Out: w0 - character if available, else -1
	 * Clobber list : x0, x1
	 * ---------------------------------------------
	 */
func console_cdns_getc
#if ENABLE_ASSERTIONS
	cmp	x0, #0
	ASM_ASSERT(ne)
#endif /* ENABLE_ASSERTIONS */
	ldr	x0, [x0, #CONSOLE_T_CDNS_BASE]
	b	console_cdns_core_getc
endfunc console_cdns_getc

	/* ---------------------------------------------
	 * int console_cdns_core_flush(uintptr_t base_addr)
	 * Function to force a write of all buffered
	 * data that hasn't been output.
	 * In : x0 - console base address
	 * Out : return -1 on error else return 0.
	 * Clobber list : x0, x1
	 * ---------------------------------------------
	 */
func console_cdns_core_flush
#if ENABLE_ASSERTIONS
	cmp	x0, #0
	ASM_ASSERT(ne)
#endif /* ENABLE_ASSERTIONS */
	/* Placeholder */
	mov	w0, #0
	ret
endfunc console_cdns_core_flush

	/* ---------------------------------------------
	 * int console_cdns_flush(console_pl011_t *console)
	 * Function to force a write of all buffered
	 * data that hasn't been output.
	 * In : x0 - pointer to console_t structure
	 * Out : return -1 on error else return 0.
	 * Clobber list : x0, x1
	 * ---------------------------------------------
	 */
func console_cdns_flush
#if ENABLE_ASSERTIONS
	cmp	x0, #0
	ASM_ASSERT(ne)
#endif /* ENABLE_ASSERTIONS */
	ldr	x0, [x0, #CONSOLE_T_CDNS_BASE]
	b	console_cdns_core_flush
endfunc console_cdns_flush
