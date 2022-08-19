KERNELDIR=/lib/modules/`uname -r`/build

obj-m := kprobe.o kretprobe.o

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *.ko modules.* *.mod.c .*.cmd Module.symvers .tmp_versions
