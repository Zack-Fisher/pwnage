CC = gcc
LD = ld
OBJCOPY = objcopy

EFIINC = /usr/include/efi
EFILIB = /usr/lib
EFI_CRT_OBJS = $(EFILIB)/crt0-efi-x86_64.o
# funny extension for linkerscript, .lds instead of .ld.
EFI_LDS = $(EFILIB)/elf_x86_64_efi.lds

# UEFI uses UTF-16 for its encoding, so get gcc to use shorts instead of normal 32-bit wchars.
CFLAGS = -I$(EFIINC) -I$(EFIINC)/x86_64 -fno-stack-protector -fpic -fshort-wchar -mno-red-zone -maccumulate-outgoing-args
# use a linkerscript, replace glibc with the efi crt0 startup object and friends.
# -Bsymbolic: prefer symbols in our own libraries, rather than symbols from others.
# -znocombreloc: do not combine/mangle elf sections in the output object file. we need to use the sections to copy
#  	into the PE directly.
LDFLAGS = -nostdlib -znocombreloc -T $(EFI_LDS) -shared -Bsymbolic -L $(EFILIB) $(EFI_CRT_OBJS)

NAME:=pwnage
# so -> efi -> img
TARGET_SO:=$(NAME).so
TARGET_EFI:=$(NAME).efi
TARGET_IMAGE:=$(NAME).img

SRC_DIR:=src
SRCS:=$(shell find src -name '*.c' -type f)
OBJS:=$(patsubst %.c,%.o,$(SRCS))

all: run-kernel

# OVMF - we need a special BIOS in qemu to be able to run uefi booting, usually it only 
# supports legacy MBR.

# we can just run it directly, without the overhead of the image creation.
run-kernel: $(TARGET_EFI)
	qemu-system-x86_64 -bios /usr/share/ovmf/x64/OVMF.fd -kernel $(TARGET_EFI)

# have to manually select and run the .efi file through the uefi shell.
run-image: $(TARGET_IMAGE)
	qemu-system-x86_64 -bios /usr/share/ovmf/x64/OVMF.fd -hda $(TARGET_IMAGE)

# linking this is really simple, we just need to define an efi_main
# for the gnu efilib entrypoint. 
$(TARGET_SO): $(OBJS)
	$(LD) $(LDFLAGS) $^ -o $@ -lefi -lgnuefi

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# somehow magic(k)ally make a PE32+ with normal unix objcopy i guess
$(TARGET_EFI): $(TARGET_SO)
	$(OBJCOPY) -j .text -j .sdata -j .data -j .dynamic -j .dynsym -j .rel -j .rela -j .reloc --target=efi-app-x86_64 $^ $@

# efi works off of a boot partition, to get this to actually boot on a real machine
# we need to setup a FAT32 filesystem that has the efi file at the right spot w/ the right name.
$(TARGET_IMAGE): $(TARGET_EFI)
	dd if=/dev/zero of=$(TARGET_IMAGE) bs=1k count=1440
	mformat -i $(TARGET_IMAGE) -f 1440 ::
	mmd -i $(TARGET_IMAGE) ::/EFI
	mmd -i $(TARGET_IMAGE) ::/EFI/BOOT
	mcopy -i $(TARGET_IMAGE) $(TARGET_EFI) ::/EFI/BOOT/BOOTX64.EFI

clean:
	rm -f *.o *.so *.efi *.img

.PHONY: clean
