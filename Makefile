CC = gcc
LD = ld
OBJCOPY = objcopy

UEFI_FIRMWARE_IMAGE:=/usr/share/ovmf/x64/OVMF.fd 

ARCH:=x86_64

# we're building our own local copy of gnu-efi since it's easy.
GNU_EFI_DIR:=gnu-efi
INCLUDE_PATHS:=-I$(GNU_EFI_DIR)/inc
LIB_PATHS:=-L$(GNU_EFI_DIR)/$(ARCH)/gnuefi -L$(GNU_EFI_DIR)/$(ARCH)/lib
EFI_CRT:=$(GNU_EFI_DIR)/gnuefi/crt0-efi-$(ARCH).o
EFI_LINKERSCRIPT:=$(GNU_EFI_DIR)/gnuefi/elf_$(ARCH)_efi.lds

NAME:=pwnage
# so -> efi -> img
TARGET_SO:=$(NAME).so
TARGET_EFI:=$(NAME).efi
TARGET_IMAGE:=$(NAME).img

SRC_DIR:=src
SRCS:=$(shell find src -name '*.c' -type f)
OBJS:=$(patsubst %.c,%.o,$(SRCS))

all: run-kernel

setup: deps
deps: gnu-efi
gnu-efi:
	$(info making gnu efi lib)
	make -C $(GNU_EFI_DIR)

# OVMF - we need a special BIOS in qemu to be able to run uefi booting, usually it only 
# supports legacy MBR.

# we can just run it directly, without the overhead of the image creation.
run-kernel: $(TARGET_EFI)
	qemu-system-$(ARCH) -bios $(UEFI_FIRMWARE_IMAGE) -kernel $(TARGET_EFI)

# have to manually select and run the .efi file through the uefi shell.
run-image: $(TARGET_IMAGE)
	qemu-system-$(ARCH) -bios $(UEFI_FIRMWARE_IMAGE) -hda $(TARGET_IMAGE)

# use a linkerscript, replace glibc with the efi crt0 startup object and friends.
# -Bsymbolic: prefer symbols in our own libraries, rather than symbols from others.
# -znocombreloc: do not combine/mangle elf sections in the output object file. we need to use the sections to copy
#  	into the PE directly.
# linking order matters with the objects.
$(TARGET_SO): $(OBJS) $(EFI_CRT) 
	$(LD) -nostdlib -znocombreloc -shared -Bsymbolic \
		-T $(EFI_LINKERSCRIPT) $(LIB_PATHS) \
		$(EFI_CRT) $(OBJS) -o $@ -lefi -lgnuefi 

# UEFI uses UTF-16 for its encoding, so get gcc to use shorts instead of normal 32-bit wchars.
%.o: %.c
	$(CC) $(INCLUDE_PATHS) \
		-fno-stack-protector -fpic -fshort-wchar \
		-mno-red-zone -maccumulate-outgoing-args \
		-c $< -o $@

# somehow magic(k)ally make a PE32+ with normal unix objcopy I GUESS
$(TARGET_EFI): $(TARGET_SO)
	$(OBJCOPY) -j .text -j .sdata -j .data -j .dynamic -j .dynsym -j .rel -j .rela -j .reloc --target=efi-app-$(ARCH) $^ $@

# efi works off of a boot partition, to get this to actually boot on a real machine
# we need to setup a FAT32 filesystem that has the efi file at the right spot w/ the right name.
$(TARGET_IMAGE): $(TARGET_EFI)
	dd if=/dev/zero of=$(TARGET_IMAGE) bs=1k count=1440
	mformat -i $(TARGET_IMAGE) -f 1440 ::
	mmd -i $(TARGET_IMAGE) ::/EFI
	mmd -i $(TARGET_IMAGE) ::/EFI/BOOT
	mcopy -i $(TARGET_IMAGE) $(TARGET_EFI) ::/EFI/BOOT/BOOTX64.EFI

clean:
	rm -f src/*.o $(TARGET_SO) $(TARGET_EFI) $(TARGET_IMAGE)

.PHONY: clean deps gnu-efi
