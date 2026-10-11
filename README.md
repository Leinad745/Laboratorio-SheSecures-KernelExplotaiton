# Laboratorio de la demo — Escalada a root vía kernel

Simple laboratorio de explotacion de kernel: un módulo de kernel vulnerable (`/dev/vuln`) con un desbordamiento de pila, y un exploit que lo convierte en `root` mediante `ret2usr` + `commit_creds(prepare_kernel_cred(0))`. Todo corre en una **VM QEMU aislada** con las mitigaciones apagadas para ver el mecanismo con claridad.

## Archivos

| Archivo             | Qué es                                                        |
|---------------------|---------------------------------------------------------------|
| `vuln.c`            | Módulo vulnerable (bug: `copy_from_user` sin validar tamaño). |
| `Makefile`          | Compila `vuln.ko`.                                            |
| `exploit.c`         | Exploit didáctico (ret2usr → root). Muy comentado.            |
| `build.sh`          | Construye el `initramfs`. **Versión Kali** (estudiantes).     |
| `run.sh`            | Arranca la VM en QEMU. **Versión Kali** (estudiantes).        |
| `kernel-min.config` | Fragmento de config para compilar el kernel (opción B).       |

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

## Paso 0 — Conseguir un kernel (`bzImage`) para la VM

El exploit necesita arrancar QEMU con un kernel. Dos opciones:

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

## Dos modos de desbordamiento: `USE_SPRAY` (robusto vs. exacto)

`exploit.c` empieza con un interruptor:

```c
#define USE_SPRAY 1   // 1 = rociado (robusto, por defecto) · 0 = offset exacto
```

- **`USE_SPRAY 1` (por defecto, "rociado"):** en vez de colocar `&payload` en un
  único offset, rellena toda la zona por encima del buffer con `&payload`
  repetido. La dirección de retorno real cae en algún lugar de esa zona, así que
  **no necesitas saber el OFFSET exacto**: funciona en distintos kernels y
  compiladores. Es el modo recomendado para que la demo salga siempre.
- **`USE_SPRAY 0` ("exacto"):** coloca `&payload` en el único slot que indica
  `#define OFFSET`. Si el OFFSET no es el correcto para tu kernel, la función
  retorna normal y verás `[-] no hubo salto` — que es justo el punto de partida
  del ejercicio del Día 2.

> **¿Por qué 72 a veces no vale?** `OFFSET=72` asume `64 (buffer) + 8 (rbp)`. Los
> kernels modernos (p. ej. el stock de Kali) se compilan sin frame pointer y la
> función guarda otros registros entre el buffer y `RIP`, así que la distancia
> real suele ser 80/88/96. Por eso el rociado es el modo por defecto, y hallar el
> número exacto es el trabajo del Día 2.

Tras cambiar `USE_SPRAY`, recompila **y** reconstruye el initramfs:
`gcc -static -no-pie -o exploit exploit.c && ./build.sh && ./run.sh`.
