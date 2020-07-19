# tools
common development tools

# mkenvimage
创建env.bin
```bash
export CROSS_COMPILE=arm-linux-gnueabihf-
get_default_envs.sh /path/to/u-boot-build-dir/ >default-env.txt
vim default-env.txt 修改、删除、添加变量，以键值对的形式
mkenvimage -s 16384 -o env.bin default-env.txt
```
# boot.src
创建u-boot的启动脚本
