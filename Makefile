#
OS := $(shell uname)

#NDKPATH=/scratch/android-ndk-r9d/
# NDK_OBJDUMP=$(shell $(NDKPATH)ndk-which objdump)
# NDK_GCC=$(shell $(NDKPATH)ndk-which gcc)

ifeq ($(OS), Darwin)
MD5PROG = md5
DTC=./bin/dtc
MACHEADERS = HOSTCFLAGS="-I../mac_linux_headers"
else
MD5PROG = md5sum
DTC=./bin/dtc
endif

NDK_OBJDUMP=arm-none-linux-gnueabi-objdump
NDK_GCC=arm-none-linux-gnueabi-gcc

PREFIX=$(NDK_OBJDUMP:%-objdump=%-)
KERNELID=3.9.0-00054-g7b6edac
DELETE_TEMP_FILES=1

CROSS_GCC=/scratch/altera/gcc-linaro-arm-linux-gnueabihf-4.7-2012.11-20121123_linux/bin/arm-linux-gnueabihf-

targetnames = bootbin sdcard all zImage

all:
	@echo "Please type one of the following:"
	@echo "    make bootbin.sockit"
	@echo "    make sdcard.sockit"
	@echo "    make zImage.sockit"
	@echo "    make all.sockit"

#################################################################################################
# sockit
sockittargets = $(addsuffix .sockit, $(targetnames))
sockittargets: $(sockittargets)
$(sockittargets):
	make BOARD=sockit real.$(basename $@)

sockit-adb:
	adb connect $(RUNPARAM)
	adb -s $(RUNPARAM):5555 shell pwd || true
	adb connect $(RUNPARAM)
	adb -s $(RUNPARAM):5555 root || true
	sleep 1
	adb connect $(RUNPARAM)
	adb -s $(RUNPARAM):5555 shell rm -rf /mnt/sdcard/3.9.0-00054-g7b6edac
	adb -s $(RUNPARAM):5555 shell mkdir /mnt/sdcard/3.9.0-00054-g7b6edac
	adb -s $(RUNPARAM):5555 push sdcard-sockit/boot.bin   /mnt/sdcard
	adb -s $(RUNPARAM):5555 push sdcard-sockit/portalmem.ko    /mnt/sdcard
	adb -s $(RUNPARAM):5555 push sdcard-sockit/system.img    /mnt/sdcard
	adb -s $(RUNPARAM):5555 push sdcard-sockit/timelimit    /mnt/sdcard
	adb -s $(RUNPARAM):5555 push sdcard-sockit/userdata.img    /mnt/sdcard
	adb -s $(RUNPARAM):5555 push sdcard-sockit/zynqportal.ko  /mnt/sdcard
	adb -s $(RUNPARAM):5555 shell sync
	adb -s $(RUNPARAM):5555 shell sync
	adb -s $(RUNPARAM):5555 reboot

#################################################################################################
# zz
#################################################################################################

real.all: real.bootbin real.sdcard

clean:
	## '"make realclean" to remove downloaded files
	rm -fr sdcard-* boot.bin *.tmp *.elf *.gz *.hex *.o foo.map xbootgen canoncpio

realclean: clean
	rm -fr filesystems/*

real.bootbin: zcomposite.elf imagefiles/zynq_$(BOARD)_fsbl.elf xbootgen reserved_for_interrupts.tmp
	if [ -f boot.bin ]; then mv -v boot.bin boot.bin.bak; fi
	cp -f imagefiles/zynq_$(BOARD)_fsbl.elf zynq_fsbl.elf
	./xbootgen zynq_fsbl.elf zcomposite.elf
ifeq ($(DELETE_TEMP_FILES),1)
	rm -f zynq_fsbl.elf zcomposite.elf reserved_for_interrupts.tmp
endif

# daffodil's sockit uses this macaddress: 00:e0:0c:00:98:03 
dtswork.tmp:
ifdef DAFFODIL
	sed s/73/98/ <imagefiles/zynq-$(BOARD)-portal.dts >dtswork.tmp
else
	macbyte=`echo $(USER)$(BOARD) | $(MD5PROG) | cut -c 1-2`; sed s/73/$$macbyte/ <imagefiles/zynq-$(BOARD)-portal.dts >dtswork.tmp
endif

# if [ -f $(DTC) ]; then echo $(DTC); else make $(DTC); fi
INVOKE_DTC = $(DTC) -I dts -O dtb -o dtb.tmp dtswork.tmp
dtb.tmp: imagefiles/zynq-$(BOARD)-portal.dts dtswork.tmp
	$(INVOKE_DTC) || make $(DTC); $(INVOKE_DTC)
ifeq ($(DELETE_TEMP_FILES),1)
	rm -f dtswork.tmp
endif

zcomposite.elf: ramdisk dtb.tmp
	echo "******** PRINT GCC CONFIGURE OPTIONS *******"
	$(PREFIX)gcc -v 2>&1
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm imagefiles/zImage z.tmp
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm ramdisk.image.gz r.tmp
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm dtb.tmp d.tmp
	$(PREFIX)gcc -c clearreg.S
	$(PREFIX)ld -z noexecstack -Ttext 0 -e 0 -o c.tmp clearreg.o
	$(PREFIX)objcopy -I elf32-littlearm -O binary c.tmp c1.tmp
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm c1.tmp c.tmp
	$(PREFIX)ld -e 0x1008000 -z max-page-size=0x8000 -o zcomposite.elf --script zynq_linux_boot.lds r.tmp d.tmp c.tmp z.tmp
ifeq ($(DELETE_TEMP_FILES),1)
	rm -f z.tmp r.tmp d.tmp c.tmp c1.tmp clearreg.o ramdisk.image.gz dtb.tmp
endif

canoncpio: canoncpio.c
	gcc -o canoncpio canoncpio.c

ramdisk: canoncpio
	chmod 644 data/*.rc data/*.prop
	cd data; (find . -name unused -o -print | sort | cpio -H newc -o >../ramdisk.image.temp1)
	./canoncpio < ramdisk.image.temp1 | gzip -9 -n >ramdisk.image.temp
	cat ramdisk.image.temp /dev/zero | dd of=ramdisk.image.gz count=256 ibs=1024
ifeq ($(DELETE_TEMP_FILES),1)
	rm -f ramdisk.image.temp ramdisk.image.temp1
endif

xbootgen: xbootgen.c Makefile
	gcc -g -o xbootgen xbootgen.c

real.zImage: bin/dtc
	cp linux-xlnx/arch/arm/boot/zImage imagefiles/zImage

real.sdcard: sdcard-$(BOARD)/system.img sdcard-$(BOARD)/userdata.img sdcard-$(BOARD)/boot.bin
	cp -v imagefiles/zynqportal.ko imagefiles/portalmem.ko imagefiles/timelimit sdcard-$(BOARD)/
	[ -e sdcard-$(BOARD)/$(KERNELID) ] || mkdir sdcard-$(BOARD)/$(KERNELID)
	echo "Files for $(BOARD) SD Card are in $(PWD)/sdcard-$(BOARD)"

.PHONY: real.sdcard real.bootbin real.all real.zImage

sdcard-$(BOARD)/boot.bin:
	mkdir -p sdcard-$(BOARD)
	rm -f boot.bin
	make BOARD=$(BOARD) real.bootbin
	mv boot.bin sdcard-$(BOARD)/boot.bin

filesystems/system-130710.img.bz2:
	mkdir -p filesystems
	wget 'https://github.com/cambridgehackers/zynq-boot-filesystems/blob/system-130710/system-130710.img.bz2?raw=true' -O filesystems/system-130710.img.bz2

filesystems/userdata.img.bz2:
	mkdir -p filesystems
	wget 'https://github.com/cambridgehackers/zynq-boot-filesystems/blob/userdata/userdata.img.bz2?raw=true' -O filesystems/userdata.img.bz2

sdcard-$(BOARD)/system.img: filesystems/system-130710.img.bz2
	mkdir -p sdcard-$(BOARD)
	bzcat filesystems/system-130710.img.bz2 > sdcard-$(BOARD)/system.img
	(cd sdcard-$(BOARD); $(MD5PROG) -c ../imagefiles/filesystems.md5sum)

ifeq ($(shell uname), Darwin)
sdcard-$(BOARD)/userdata.img: filesystems/userdata.img.bz2
	mkdir -p sdcard-$(BOARD)
	bzcat filesystems/userdata.img.bz2 > sdcard-$(BOARD)/userdata.img
else
sdcard-$(BOARD)/userdata.img:
	mkdir -p sdcard-$(BOARD)
	# make a 100MB empty filesystem
	dd if=/dev/zero bs=1k count=102400 of=sdcard-$(BOARD)/userdata.img
	mkfs -F -t ext4 sdcard-$(BOARD)/userdata.img
endif

.PHONY: bin/dtc

# wget https://launchpad.net/linaro-toolchain-binaries/trunk/2012.11/+download/gcc-linaro-arm-linux-gnueabihf-4.7-2012.11-20121123_linux.tar.bz2
# tar xjf gcc-linaro-arm-linux-gnueabihf-4.7-2012.11-20121123_linux.tar.bz2
# export CROSS_COMPILE=~/gcc-linaro-arm-linux-gnueabihf-4.7-2012.11-20121123_linux/bin/arm-linux-gnueabihf-
bin/dtc:
	if [ -d linux-socfpga ]; then true; else git clone git://git.rocketboards.org/linux-socfpga.git; fi
	(cd linux-socfpga; \
	git checkout remotes/origin/rel_13.02_RC10 -b rel_13.02_RC10; \
	export CROSS_COMPILE=$(CROSS_GCC); \
	make ARCH=arm CROSS_COMPILE=$(CROSS_GCC) $(MACHEADERS) socfpga_defconfig; \
	make ARCH=arm CROSS_COMPILE=$(CROSS_GCC) $(MACHEADERS) -j8 uImage LOADADDR=0x8000; \
	make ARCH=arm CROSS_COMPILE=$(CROSS_GCC) $(MACHEADERS) dtbs; \
	make ARCH=arm CROSS_COMPILE=$(CROSS_GCC) $(MACHEADERS) modules; \
	cp arch/arm/boot/zImage ../imagefiles; \
	cp arch/arm/boot/dts/socfpga_cyclone5_sockit.dtb ../imagefiles/; \
	cp -fv scripts/dtc/dtc ../bin/dtc)

boot-partition.img:
	cat imagefiles/preloader-mkpimage-sockit.bin \
	    imagefiles/altera/14.1/embedded/examples/hardware/cv_soc_devkit_ghrd/software/preloader/uboot-socfpga/u-boot.img \
	    >boot-partition.img

write-boot-mac:
	#fdisk /dev/disk1
	#dd if=boot-partition.img of=/dev/disk1s1 bs=64k; sync

#To format sdcard:
# Make >2 partitions:
#  Partition 1 must be FAT
#  Another partition can start as FAT and then be modified with fdisk to be "id == 0xa2":
#      fdisk -e /dev/rdisk1
#      print
#      edit 1
#      Partition id ('0' to disable)  [0 - FF]: [B] (? for help) a2
#      Do you wish to edit in CHS mode? [n] 
#      Partition offset [0 - 7744512]: [63] 
#      Partition size [1 - 7744449]: [7744449] 19536
#      print
#      write
#      quit

#/scratch/altera/14.1/embedded/embedded_command_shell.sh
SOCEDS_DEST_ROOT ?= /scratch/altera/14.1/embedded/
export SOCEDS_DEST_ROOT
PATH := $(SOCEDS_DEST_ROOT)/host_tools/mentor/gnu/arm/baremetal/bin:$(SOCEDS_DEST_ROOT)/host_tools/altera/mkpimage:$(PATH)
export PATH

BSP-CREATE ?= $(SOCEDS_DEST_ROOT)/host_tools/altera/preloadergen/bsp-create-settings

#imagefiles/preloader-mkpimage-sockit.bin
preloader:
	$(BSP-CREATE) --type spl --bsp-dir build \
	  --preloader-settings-dir \
	  ../import_components/arrow/SoCKIT_Materials_14.0/SoCkit/SoCkit_SW_lab_14.0/hps_isw_handoff/soc_system_hps_0 \
	  --settings build/settings.bsp --set spl.boot.WATCHDOG_ENABLE false
	cd build; make
	cp build/preloader-mkpimage.bin imagefiles/preloader-mkpimage-sockit.bin
