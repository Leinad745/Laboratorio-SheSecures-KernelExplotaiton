#!/bin/sh
# run.arch.sh — Arranca la VM en QEMU (VERSIÓN ARCH/CACHYOS del instructor).
# ==========================================================================
# Idéntico a run.sh; la invocación de QEMU no depende de la distro.
# En Arch:  sudo pacman -S qemu-base   (o qemu-full)
# -------------------------------------------------------------------------
# Necesita:
#   - bzImage           : el kernel a arrancar (ver README: opción A o B)
#   - initramfs.cpio.gz : el disco raíz (genéralo con ./build.sh)
#
# Variables opcionales:
#   KERNEL=/ruta/bzImage   INITRD=/ruta/initramfs.cpio.gz   DEBUG=1 (gdb en :1234)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
KERNEL="${KERNEL:-$HERE/bzImage}"
INITRD="${INITRD:-$HERE/initramfs.cpio.gz}"

[ -f "$KERNEL" ] || { echo "[-] Falta el kernel: $KERNEL"; echo "    Ver README (opción A: usar uno de distro; B: compilar uno mínimo)."; exit 1; }
[ -f "$INITRD" ] || { echo "[-] Falta el initramfs: $INITRD"; echo "    Genéralo con: ./build.sh"; exit 1; }

# Mitigaciones DESACTIVADAS a propósito para la demo didáctica:
#   nokaslr  -> direcciones del kernel estables (símbolos legibles/estáticos)
#   nosmep   -> el kernel puede ejecutar nuestro código de usuario (ret2usr)
#   nosmap   -> el kernel puede leer memoria de usuario sin trabas
#   nopti    -> sin trampolín KPTI, el retorno con iretq es directo
# Para el Día 4 (reactivar SMEP): quita 'nosmep' de aquí y añade ',+smep' al -cpu.
exec qemu-system-x86_64 \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -m 256M \
    -cpu qemu64 \
    -nographic \
    -no-reboot \
    -append "console=ttyS0 nokaslr nosmep nosmap nopti panic=-1 quiet" \
    ${DEBUG:+-s -S}
