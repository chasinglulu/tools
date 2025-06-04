## UART Tool (`uart_tool`)
A versatile UART utility for forwarding data between two serial ports, receiving data from a serial port, sending data to a serial port, or testing a loopback connection.

### Compilation
Located in `toolkit/uart/`.
```bash
cd toolkit/uart
make
# For cross-compilation:
# make CROSS_COMPILE=your-cross-compiler-prefix-
```

### Usage
```bash
./uart_tool -h # To see all options and examples
# Example: Forward mode
# ./uart_tool -M forward -r /dev/ttyS0 -s /dev/ttyS1 -b 115200
# Example: Loopback mode (file based)
# ./uart_tool -M loopback -r /dev/ttyS0 -s /dev/ttyS1 -b 115200 -i send.txt -o recv.txt
```

## String Generator (`string_generator`)
A utility to generate random strings of a specified length, outputting to a file or stdout. Useful for creating test data for UART loopback or other purposes.

### Compilation
Located in `toolkit/uart/`.
```bash
cd toolkit/uart
make string_generator
# For cross-compilation:
# make CROSS_COMPILE=your-cross-compiler-prefix- string_generator
```

### Usage
```bash
./string_generator -h # To see all options
# Example: Generate a 2048 byte string to a file named random.txt
# ./string_generator -s 2048 -o random.txt
# Example: Generate a 512 byte string to stdout
# ./string_generator -s 512
```

## ABC Tool (`abc_tool`)
A tool to manage A/B boot metadata on a device. It allows for reading, writing, and modifying A/B slot information.

### Compilation
The `abc_tool` is located in `abc_tool/`. You would typically have a Makefile in that directory to compile it.
Example (assuming a Makefile exists in `abc_tool/`):
```bash
cd abc_tool
make
# For cross-compilation:
# make CROSS_COMPILE=your-cross-compiler-prefix-
```

### Usage
The `abc_tool` requires a device path (`-d`) and an action to perform.
```bash
./abc_tool -h # To see all options and examples

# Example: Dump slot info from /dev/mmcblk0boot0
# ./abc_tool -d /dev/mmcblk0boot0 -p

# Example: Get current active slot from /dev/mtd0
# ./abc_tool -d /dev/mtd0 -c

# Example: Mark slot A (0) as boot successful on /dev/mmcblk0boot0
# ./abc_tool -d /dev/mmcblk0boot0 -m 0

# Example: Set slot B (1) as the active boot slot on /dev/mmcblk0boot0
# ./abc_tool -d /dev/mmcblk0boot0 -a 1
```