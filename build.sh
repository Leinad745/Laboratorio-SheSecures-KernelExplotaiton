#!/bin/sh

# build.sh — Construye el initramfs (disco raíz) de la VM del laboratorio.
# ======================= VERSIÓN PARA KALI LINUX (estudiantes) =======================
#
# Empaqueta: busybox + el módulo vulnerable (vuln.ko) + el exploit + un init que
# monta /proc,/sys,/dev, relaja kptr_restrict (para leer /proc/kallsyms) y deja
# una shell como usuario SIN privilegios (uid 1000), tal como la ve el público.

# Requisitos en Kali:
#   sudo apt update
#   sudo apt install -y busybox-static qemu-system-x86 build-essential gdb cpio gzip \
#                       linux-headers-$(uname -r)

# IMPORTANTE: el initramfs NO tiene librerías, así que busybox debe ser ESTÁTICO.
# El paquete 'busybox-static' de Kali instala /bin/busybox estático. Si tienes el
# busybox dinámico normal, la shell de la VM fallará: instala busybox-static.

# Antes de correr este script:
#   1) make KDIR=/lib/modules/$(uname -r)/build   -> genera vuln.ko
#   2) gcc -static -no-pie -o exploit exploit.c
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/initramfs"

# Buscar un busybox ESTÁTICO. Preferimos /bin/busybox (busybox-static de Kali).
BUSYBOX="${BUSYBOX:-}"
if [ -z "$BUSYBOX" ]; then
    for cand in /bin/busybox /usr/bin/busybox "$(command -v busybox 2>/dev/null || true)"; do
        [ -n "$cand" ] && [ -x "$cand" ] && { BUSYBOX="$cand"; break; }
    done
fi
[ -n "$BUSYBOX" ] || { echo "[-] No encuentro 'busybox'. En Kali:  sudo apt install -y busybox-static"; exit 1; }

# Avisar si el busybox es dinámico (no servirá dentro del initramfs sin librerías).
if ldd "$BUSYBOX" >/dev/null 2>&1; then
    echo "[!] '$BUSYBOX' parece DINÁMICO; dentro del initramfs no habrá librerías."
    echo "    En Kali instala el estático:  sudo apt install -y busybox-static"
    echo "    O fuerza otro:  BUSYBOX=/ruta/busybox-estatico ./build.sh"
fi

[ -f "$HERE/vuln.ko" ] || echo "[!] Aviso: falta vuln.ko (corre 'make'). Sigo, pero la demo lo necesita."
[ -f "$HERE/exploit" ] || echo "[!] Aviso: falta 'exploit' (gcc -static -no-pie -o exploit exploit.c). Sigo, pero la demo lo necesita."

echo "[*] Usando busybox: $BUSYBOX"
echo "[*] Preparando árbol del initramfs en $ROOT"
rm -rf "$ROOT"
mkdir -p "$ROOT"/bin "$ROOT"/sbin "$ROOT"/etc "$ROOT"/proc "$ROOT"/sys \
         "$ROOT"/dev "$ROOT"/tmp "$ROOT"/root "$ROOT"/home/user

cp "$BUSYBOX" "$ROOT/bin/busybox"
chmod +x "$ROOT/bin/busybox"

# Copiar los artefactos de la demo (si existen)
[ -f "$HERE/vuln.ko" ] && cp "$HERE/vuln.ko" "$ROOT/home/user/"
[ -f "$HERE/exploit" ] && cp "$HERE/exploit" "$ROOT/home/user/"

# Cuentas mínimas: root (uid 0) y user (uid 1000). su de root->user no pide clave.
cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
user:x:1000:1000:user:/home/user:/bin/sh
EOF
cat > "$ROOT/etc/group" <<'EOF'
root:x:0:
user:x:1000:
EOF

# init: primer proceso del sistema (PID 1)
cat > "$ROOT/init" <<'EOF'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc     none /proc
mount -t sysfs    none /sys
mount -t devtmpfs none /dev

# Facilitar la demo: permitir que un usuario normal lea /proc/kallsyms.
echo 0 > /proc/sys/kernel/kptr_restrict       2>/dev/null || true
echo 0 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
echo 0 > /proc/sys/kernel/dmesg_restrict        2>/dev/null || true

# Cargar el modulo vulnerable AQUI, como root (este init es PID 1). Un usuario
# normal (uid 1000) no puede hacer insmod: le falta CAP_SYS_MODULE y obtendria
# 'Operation not permitted'. Asi que root crea /dev/vuln en el arranque y el
# estudiante, ya sin privilegios, solo lanza ./exploit contra el.
insmod /home/user/vuln.ko && echo "  [init] vuln.ko cargado, /dev/vuln listo" \
                          || echo "  [init] AVISO: no pude cargar vuln.ko"

echo
echo "  === Laboratorio SheSecures: VM de explotacion de kernel ==="
echo "  Eres un usuario SIN privilegios. /dev/vuln ya esta cargado (lo hizo root)."
echo "  Demo:   ./exploit"
echo

# Dejar una shell interactiva como usuario 1000 (no root).
cd /home/user
setsid /bin/cttyhack /bin/su -s /bin/sh user
# Al salir de la shell, apagar la VM.
poweroff -f
EOF
chmod +x "$ROOT/init"

echo "[*] Empaquetando initramfs.cpio.gz"
( cd "$ROOT" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 ) > "$HERE/initramfs.cpio.gz"

echo "[+] Listo: $HERE/initramfs.cpio.gz"
echo "    Arranca la VM con:  ./run.sh"
