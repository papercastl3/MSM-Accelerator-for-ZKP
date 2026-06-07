obj-m += msm_dma.o
KDIR = /lib/modules/$(shell uname -r)/build
all:
	make -C $(KDIR) M=$(PWD) modules
	gcc -Wall -O2 -o test_app test_app.c
clean:
	make -C $(KDIR) M=$(PWD) clean
	rm -f test_app

install:
	sudo insmod msm_dma.ko
	sleep 1
	sudo dmesg | tail -5
	sudo chmod 666 /dev/msm_dma
