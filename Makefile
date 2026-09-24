# Makefile del módulo vulnerable (laboratorio SheSecures)
# -------------------------------------------------------
# Compila vuln.ko contra el árbol de kernel indicado en KDIR.
#
#   KDIR = ruta al árbol/headers del MISMO kernel que arranca la VM (bzImage).
#          Por defecto usa el del sistema anfitrión; para la VM normalmente
#          querrás apuntarlo al kernel que compilaste/descargaste para QEMU:
#
#       make KDIR=/ruta/a/linux-6.x
#
# Nota didáctica: -fno-stack-protector desactiva el "canario" de pila SOLO en
# nuestro módulo, para que el desbordamiento alcance la dirección de retorno y
# el ejemplo sea claro. En un módulo real jamás harías esto.

obj-m       += vuln.o
ccflags-y   += -fno-stack-protector

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
