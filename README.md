# tools
Common development tools

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
