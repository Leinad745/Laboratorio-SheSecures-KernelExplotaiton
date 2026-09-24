#!/bin/sh
# build.arch.sh — Construye el initramfs de la VM (VERSIÓN ARCH/CACHYOS del instructor).
# ======================================================================================
# En Arch/CachyOS el paquete 'busybox' ya es estático, así que basta con instalarlo.
# Las estudiantes en Kali usan ./build.sh (que exige busybox-static).
# ----------------------------------------------------------------------
# Empaqueta: busybox + el módulo vulnerable (vuln.ko) + el exploit + un init que
# monta /proc,/sys,/dev, relaja kptr_restrict (para leer /proc/kallsyms) y deja
# una shell como usuario SIN privilegios (uid 1000), tal como la ve el público.
#
# Antes de correrlo:
#   1) make            -> genera vuln.ko  (ajusta KDIR al kernel de la VM)
#   2) gcc -static -no-pie -o exploit exploit.c
#   3) instala busybox (Arch/CachyOS:  sudo pacman -S busybox)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/initramfs"
BUSYBOX="${BUSYBOX:-$(command -v busybox || true)}"

[ -n "$BUSYBOX" ] || { echo "[-] No encuentro 'busybox'. Instálalo (pacman -S busybox) o exporta BUSYBOX=/ruta/busybox"; exit 1; }
[ -f "$HERE/vuln.ko" ] || echo "[!] Aviso: falta vuln.ko (corre 'make'). Sigo, pero la demo lo necesita."
[ -f "$HERE/exploit" ] || echo "[!] Aviso: falta 'exploit' (gcc -static -no-pie -o exploit exploit.c). Sigo, pero la demo lo necesita."

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
echo 0 > /proc/sys/kernel/kptr_restrict     2>/dev/null || true
echo 0 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true

echo
echo "  === Laboratorio SheSecures: VM de explotacion de kernel ==="
echo "  Eres un usuario SIN privilegios. En /home/user tienes vuln.ko y exploit."
echo "  Demo:   insmod vuln.ko  &&  ./exploit"
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
