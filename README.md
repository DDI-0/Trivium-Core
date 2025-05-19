# FPGA-Based Stream Cipher Implementation

A cryptographically secure hardware implementation of the Trivium stream cipher algorithm built on an FPGA, integrating with a True Random Number Generator (TRNG).

## Overview

This project implements a complete stream cipher solution using:
- A hardware-based True Random Number Generator (TRNG) utilizing FPGA process variations
- Trivium stream cipher core with Avalon interface integration
- Linux kernel module for device interaction

## Architecture

![System Architecture](images/system_architecture.png)

The system consists of these main components:

1. **TRNG Module** - Generates truly random bits based on physical characteristics of the FPGA
2. **Trivium Core** - Implements the Trivium stream cipher algorithm (80-bit key)
3. **Avalon Agent Interface** - Exposes control and status registers to the CPU
5. **Kernel Module** - Provides the `/dev/streamcipher` device for user applications


## Trivium Algorithm

![Trivium Algorithm](images/trivium_algorithm.png)

The Trivium cipher uses three coupled non-linear feedback shift registers to generate pseudorandom bits. It is initialized with:
- 80-bit key (loaded into shift register B)
- 80-bit initialization vector (loaded into shift register A)
- Specific bits (c109-c111) set to 1
- 1152 warm-up clock cycles before generating output bits

## Statistical Analysis

The implementation includes comprehensive statistical analysis:


- Histogram of 25600+ random numbers
- Box plot showing distribution characteristics
- Expected value and standard deviation calculations

