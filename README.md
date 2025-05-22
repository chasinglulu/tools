# tools
Common development tools

## UART Tool (`uart_tool`)
A versatile UART utility for forwarding data between two serial ports, receiving data from a serial port, sending data to a serial port, or testing a loopback connection.

### Compilation
Located in `src/toolkit/uart/`.
```bash
cd src/toolkit/uart
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
Located in `src/toolkit/uart/`.
```bash
cd src/toolkit/uart
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
The `abc_tool` is located in `src/abc_tool/`. You would typically have a Makefile in that directory to compile it.
Example (assuming a Makefile exists in `src/abc_tool/`):
```bash
cd src/abc_tool
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

## Scripts
This section describes various helper scripts located in the `scripts/` directory.

### `get_default_envs.sh` (Bash Script)
Extracts default U-Boot environment variables from a U-Boot build directory. This is useful for creating a base `default-env.txt` file for `mkenvimage`.
#### Usage
```bash
./scripts/get_default_envs.sh /path/to/u-boot-build-dir/ > default-env.txt
```
Assumes the script is executable. If not, use `bash ./scripts/get_default_envs.sh ...`.

### `make_ubuntu_rootfs.sh` (Bash Script)
A script to automate the creation of an Ubuntu root filesystem. Specific dependencies and steps might be detailed within the script itself or require a particular environment.
#### Usage
```bash
./scripts/make_ubuntu_rootfs.sh [options]
```
Refer to the script's internal help or comments for detailed options and prerequisites. Assumes the script is executable.

### Python Scripts
*(Placeholder for any Python scripts. Add specific script documentation here as they are developed.)*
<!--
Example for a Python script:
### `example_script.py` (Python Script)
Description of what the Python script does.
#### Usage
```bash
python ./scripts/example_script.py --option value
```
-->

# mkenvimage
创建env.bin
```bash
export CROSS_COMPILE=arm-linux-gnueabihf-
# Use get_default_envs.sh (from scripts/ directory) to generate the initial environment file
./scripts/get_default_envs.sh /path/to/u-boot-build-dir/ > default-env.txt
vim default-env.txt # 修改、删除、添加变量，以键值对的形式
mkenvimage -s 16384 -o env.bin default-env.txt
```
# boot.src
创建u-boot的启动脚本
mkimage -c none -A arm -T script -d autoboot.cmd boot.scr

# System Image(macroSD Boot)
创建从SD卡启动的镜像文件

# Create ubuntu rootfs
For creating an Ubuntu root filesystem, use the `make_ubuntu_rootfs.sh` script.
```bash
./scripts/make_ubuntu_rootfs.sh
```
