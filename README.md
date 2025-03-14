zig build-exe \
  --name application.elf \
  -target arm-freestanding-eabi \
  -mcpu=arm1176jzf_s \
  --script memory.ld \
  src/start.S src/main.zig

$ arm-none-eabi-objcopy -O binary application.elf application.bin

$ arm-none-eabi-objdump -d application.elf > application.list
