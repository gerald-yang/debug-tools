KERNELDIR=/lib/modules/`uname -r`/build

obj-m := debug.o

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *.ko modules.* *.mod.c *.mod .*.cmd .module-common.o Module.symvers .tmp_versions
