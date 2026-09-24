# Laboratorio de la demo — Escalada a root vía kernel

Entorno autocontenido para la **demo guiada en vivo** de la clase: un módulo de
kernel vulnerable adrede (`/dev/vuln`) con un desbordamiento de pila, y un exploit
que lo convierte en `root` mediante `ret2usr` +
`commit_creds(prepare_kernel_cred(0))`. Todo corre en una **VM QEMU aislada** con
las mitigaciones apagadas para ver el mecanismo con claridad.

> ⚠️ Solo para formación, en tu propia VM. El módulo es vulnerable a propósito.

## Archivos

| Archivo             | Qué es                                                        |
|---------------------|---------------------------------------------------------------|
| `vuln.c`            | Módulo vulnerable (bug: `copy_from_user` sin validar tamaño). |
| `Makefile`          | Compila `vuln.ko`.                                            |
| `exploit.c`         | Exploit didáctico (ret2usr → root). Muy comentado.           |
| `build.sh`          | Construye el `initramfs`. **Versión Kali** (estudiantes).    |
| `run.sh`            | Arranca la VM en QEMU. **Versión Kali** (estudiantes).       |
| `build.arch.sh`     | Igual que `build.sh` pero para **Arch/CachyOS** (instructor).|
| `run.arch.sh`       | Igual que `run.sh` para **Arch/CachyOS** (instructor).       |
| `kernel-min.config` | Fragmento de config para compilar el kernel (opción B).      |

> **¿Qué script uso?** Las estudiantes en **Kali** usan `build.sh` / `run.sh`.
> El instructor en **Arch/CachyOS** usa `build.arch.sh` / `run.arch.sh`.
> La única diferencia real es el `busybox` (en Kali hace falta `busybox-static`).

## Requisitos

### Kali Linux (estudiantes)

```sh
sudo apt update
sudo apt install -y busybox-static qemu-system-x86 build-essential gdb cpio gzip \
                    linux-headers-$(uname -r)
# Opcional (plan B para grabar la demo):
sudo apt install -y asciinema
```

> En Kali es **imprescindible** `busybox-static` (el initramfs no tiene librerías,
> así que busybox debe ser estático). El `busybox` normal dinámico NO sirve.

### Arch / CachyOS (instructor)

Ya tienes `qemu-system-x86_64`, `gcc`, `make`, `cpio`, `gzip`, `gdb`. Falta:

```sh
sudo pacman -S busybox        # en Arch el busybox del repo ya es estático
sudo pacman -S asciinema      # opcional (plan B)
```

## Paso 0 — Conseguir un kernel (`bzImage`) para la VM

El exploit necesita arrancar QEMU con un kernel. Dos opciones:

- **Opción A (rápida, recomendada para Kali) — reutilizar el kernel ya presente.**
  En Kali el kernel está en `/boot/vmlinuz-*`. Cópialo como `lab/bzImage`:
  ```sh
  cp /boot/vmlinuz-$(uname -r) bzImage   # dentro de lab/
  ```
  Instala los headers (`sudo apt install -y linux-headers-$(uname -r)`) y compila
  el módulo contra ese kernel:
  ```sh
  make KDIR=/lib/modules/$(uname -r)/build
  ```
  Las mitigaciones se apagan al arrancar (`nokaslr nosmep nosmap nopti` en
  `run.sh`), así que el stock de Kali sirve para la demo.
  *(Si `insmod` se queja de firma de módulo, arranca añadiendo
  `module.sig_enforce=0` al `-append` de `run.sh`.)*

- **Opción B (control total) — compilar un kernel mínimo vanilla.**
  Descarga un `linux-6.x` y usa el fragmento `kernel-min.config` de este repo:
  ```sh
  make defconfig
  ./scripts/kconfig/merge_config.sh .config /ruta/a/lab/kernel-min.config
  make -j"$(nproc)" bzImage
  cp arch/x86/boot/bzImage /ruta/a/lab/bzImage
  ```
  Ese fragmento ya desactiva KASLR, stack protector, KPTI y retpoline, y deja lo
  mínimo (serie, devtmpfs, módulos, kallsyms). Compila `vuln.ko` con
  `make KDIR=/ruta/al/arbol/linux-6.x`.

> Regla de oro: **el `KDIR` con el que compilas `vuln.ko` debe ser el mismo kernel
> que arranca `run.sh`.** Si no coinciden, `insmod` fallará.

## Paso 1 — Compilar el módulo y el exploit

```sh
cd lab
make KDIR=/ruta/al/arbol/del/kernel        # genera vuln.ko
gcc -static -no-pie -o exploit exploit.c   # genera el exploit
```

## Paso 2 — Construir el disco y arrancar

```sh
./build.sh        # crea initramfs.cpio.gz
./run.sh          # arranca la VM; te deja una shell como usuario (uid 1000)
```

Para salir de QEMU: `poweroff` dentro de la VM, o `Ctrl-a` seguido de `x`.

## Paso 3 — Guion EXACTO de la demo (con salida esperada)

Dentro de la VM:

```
$ id
uid=1000(user) gid=1000(user) groups=1000(user)      <- soy usuaria normal

$ insmod vuln.ko                                       <- cargo el driver vulnerable
$ ls -l /dev/vuln
crw-rw-rw-  1 0 0 ... /dev/vuln                         <- ahí está la "puerta"

$ ./exploit
[*] estado de userland guardado
[*] prepare_kernel_cred = 0x....
[*] commit_creds        = 0x....
[*] desbordando /dev/vuln...
[+] soy root!
# id
uid=0(root) gid=0(root)                                 <- ¡ESCALADA LOGRADA!
```

El momento culminante es `uid=0(root)`: el mismo programa, sin contraseña, ahora
es root gracias a un buffer mal escrito en el kernel.

## Ejercicio del Día 2 — encontrar el OFFSET con gdb

El `#define OFFSET 72` de `exploit.c` es la distancia hasta la dirección de
retorno; puede variar según el compilador. Para confirmarlo:

1. Arranca con depuración: `DEBUG=1 ./run.sh` (QEMU queda esperando en `:1234`).
2. En otra terminal: `gdb`, luego `target remote :1234`.
3. `break vuln_write`, `continue`, y desde la VM envía un patrón cíclico a
   `/dev/vuln`. Observa con qué bytes se corrompe `RIP` al retornar y ajusta
   `OFFSET`.

## Variante del Día 4 — reactivar SMEP

En `run.sh`, quita `nosmep` del `-append` y cambia `-cpu qemu64` por
`-cpu qemu64,+smep`. Vuelve a lanzar el mismo exploit: ahora el kernel se niega a
ejecutar tu `payload()` de userland (SMEP) y verás un *kernel oops* en vez de
root. Eso motiva, en clase, por qué existe la técnica **kROP** (que queda como
tema avanzado, fuera de esta hora).

## Plan B para la clase (grabación)

Ensaya y graba la demo por si algo falla en vivo:

```sh
asciinema rec demo.cast     # graba tu sesión ejecutando la demo
asciinema play demo.cast    # reprodúcela en clase si hace falta
```
