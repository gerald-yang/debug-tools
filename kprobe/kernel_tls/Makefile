KERNELDIR=/lib/modules/`uname -r`/build

obj-m := debug.o

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *.ko modules.* *.mod.c *.mod .*.cmd Module.symvers .tmp_versions
