KERNELDIR=/lib/modules/`uname -r`/build

obj-m := jprobe.o

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *.ko modules.* *.mod.c .*.cmd Module.symvers .tmp_versions
