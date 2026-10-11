# 03 · Glosario del laboratorio

> Diccionario de bolsillo de los conceptos que aparecen en el lab. Cada entrada
> tiene una **definición corta**, cuando ayuda, **dónde
> aparece** en el laboratorio. No hace falta leerlo de corrido: úsalo como
> referencia mientras lees **[01-vuln.md](01-vuln.md)** y
> **[02-exploit.md](02-exploit.md)**.

Está ordenado para que los conceptos se apoyen unos en otros, de lo más general a
lo más específico. Si prefieres orden alfabético, usa `Ctrl+F`.

---

## Conceptos base

### Kernel

El **programa central** del sistema operativo. Controla la memoria, los
dispositivos, los archivos y **qué puede hacer cada quién**. Todo lo demás
(apps, terminal, navegador) le pide las cosas a él.

- **En el lab:** el bug vive dentro del kernel, por eso explotarlo da control
  total de la máquina.

### User space (espacio de usuario)

La zona donde corren los **programas normales**, con **pocos permisos**. Si uno
falla, solo se cae él.

- **En el lab:** `exploit.c` empieza aquí, como un usuario cualquiera (`UID 1000`).

### Kernel space (espacio de kernel)

La zona privilegiada donde corre el kernel, con **acceso total** al hardware y a
la memoria.

- **En el lab:** cuando nuestro `payload()` corre aquí, podemos reescribir
  nuestras propias credenciales.

### Security rings (anillos de seguridad)

Niveles de privilegio que impone el **procesador**. En la práctica se usan dos:
**ring 0** (kernel, poder total) y **ring 3** (apps, poder limitado). El
hardware impide saltar de uno a otro salvo por puertas controladas.

- **En el lab:** todo el exploit es un truco para ejecutar código **en ring 0**
  siendo un proceso de ring 3.

### Shell

El programa que **recibe tus comandos escritos y los ejecuta** (p. ej. `/bin/sh`,
`bash`). Es la "línea de comandos".

- **En el lab:** el premio final es una **shell de `root`** (`#`): una línea de
  comandos con poder total.

---

## Memoria y bajo nivel

### Puntero (*pointer*)

Una variable que **no guarda un dato, sino la dirección (la posición en memoria)
donde está ese dato**.

- **En el lab:** `&payload`, `&init_cred` y las direcciones de `/proc/kallsyms`
  son punteros: le dicen al kernel "salta AQUÍ" o "usa el dato de AQUÍ".

### Pila (*stack*)

Una región de memoria donde cada función guarda **sus variables temporales y la
dirección a la que debe volver** cuando termina. Crece y decrece como una pila de
platos: lo último que entra es lo primero que sale.

- **En el lab:** el `local_buffer[64]` de `vuln.c` vive en la pila, **justo al
  lado de la dirección de retorno**. Por eso desbordarlo es peligroso.

### Dirección de retorno

La "nota" que una función deja en la pila diciendo *"cuando termine, el CPU debe
continuar ejecutando AQUÍ"*. Es el dato más goloso para un atacante.

- **En el lab:** el exploit **sobrescribe esta nota** con `&payload` para desviar
  al kernel hacia nuestro código.

### Buffer

Una **caja de memoria de tamaño fijo** para guardar datos temporalmente (texto,
bytes, etc.).

- **En el lab:** `local_buffer[64]` es un buffer de 64 bytes.

### Stack overflow (desbordamiento de pila)

Lo que ocurre cuando se **escriben más datos de los que caben** en un buffer de
la pila: el sobrante **pisa la memoria de al lado**, incluida la dirección de
retorno.

- **En el lab:** es **la vulnerabilidad** de `vuln.c`, causada por un
  `copy_from_user` que no valida el tamaño. Ver [01-vuln.md](01-vuln.md) §5.

### OFFSET

La **distancia exacta en bytes** desde el inicio del buffer hasta la dirección de
retorno. Saber el OFFSET permite pisar *justo* esa dirección y no otra.

- **En el lab:** `#define OFFSET 72` es una **estimación**; el valor real
  depende del kernel (80/88/96...). Hallarlo con `gdb` es el ejercicio del Día 2.
  El modo `USE_SPRAY` lo evita rellenando toda la zona (ver
  [02-exploit.md](02-exploit.md) §5).

### Registros

Pequeñas "casillas" ultrarrápidas **dentro del procesador**. `RIP` guarda la
dirección de la siguiente instrucción; `RSP` apunta a la cima de la pila.

- **En el lab:** controlar `RIP` = controlar qué ejecuta el CPU. El desbordamiento
  sirve para acabar poniendo `&payload` en `RIP`.

---

## Módulos y el entorno del lab

### Módulo de kernel

Un **trozo de código que se enchufa al kernel en caliente** para añadirle una
capacidad (normalmente un *driver*). Archivo `.ko` (*kernel object*).

- **En el lab:** `vuln.ko` (compilado desde `vuln.c`) crea `/dev/vuln`.

### `/dev` y "dispositivo"

Carpeta donde el kernel expone **puertas con forma de archivo** para hablar con
hardware o con módulos. Escribir/leer esos archivos = mandar/recibir datos del
kernel.

- **En el lab:** `/dev/vuln` es la ranura que llega a la función vulnerable.

### `copy_from_user()`

Función del kernel para **copiar datos desde la memoria del usuario hacia la del
kernel** de forma (en teoría) segura.

- **En el lab:** la línea exacta donde está el bug de `vuln.c`.

### initramfs (*initial RAM filesystem*)

Un **mini sistema de archivos que vive en memoria** y que el kernel usa al
arrancar. En este lab contiene todo lo necesario para la demo: `busybox`,
`vuln.ko`, el `exploit` y un `init`.

- **En el lab:** lo genera `build.sh` como `initramfs.cpio.gz`; `run.sh` lo
  arranca en QEMU.

### init (PID 1)

El **primer proceso** que lanza el kernel. En el lab, un script que monta `/proc`,
`/sys`, `/dev`, carga `vuln.ko` como `root` y te deja una shell como usuario
normal.

### BusyBox

Un **único programa que hace de muchos**: incluye versiones mínimas de `ls`,
`cat`, `sh`, `mount`, etc. Ideal cuando hay poco espacio.

- **En el lab:** provee la shell y los comandos básicos dentro de la VM. En Kali
  debe ser **estático** (`busybox-static`) porque el initramfs no tiene librerías.

### QEMU

Un **emulador/máquina virtual**: crea un ordenador falso dentro del tuyo para
arrancar un kernel aislado. Si algo explota, **se rompe la VM, no tu equipo**.

- **En el lab:** `run.sh` lanza QEMU con el kernel (`bzImage`) y el `initramfs`.

---

## El exploit: técnica y "receta mágica"

### Proceso y UID / credenciales

Un **proceso** es un programa en ejecución. El kernel le asocia un **carnet** con
su **UID** (número de usuario): `UID 0` = `root` (jefe), otros = usuarios
normales.

- **En el lab:** empezamos con `UID 1000` y el objetivo es cambiarlo a `UID 0`.

### `commit_creds()` y `init_cred`

`init_cred` es **la credencial de `root` permanente** del kernel.
`commit_creds(cred)` **instala esa credencial** en el proceso actual.

- **En el lab:** `commit_creds(&init_cred)` es **la línea que nos hace `root`**.

### payload

El **código que el atacante consigue ejecutar** gracias a la vulnerabilidad.

- **En el lab:** la función `payload()`, que corre en ring 0 y pide las
  credenciales de `root`.

### ret2usr (*return to user*)

Técnica en la que, tras secuestrar la dirección de retorno **del kernel**, se le
hace **saltar a código del usuario**, ejecutándolo con privilegios de kernel.

- **En el lab:** solo es posible porque la VM arranca con **SMEP apagado**.

### `/proc/kallsyms`

Un archivo que lista **los nombres de los símbolos del kernel y sus direcciones
de memoria** (la "guía telefónica" del kernel).

- **En el lab:** `find_symbol()` lo lee para localizar `commit_creds` e
  `init_cred`. Normalmente está restringido; el lab lo abre con `kptr_restrict=0`.

---

## Las defensas (apagadas a propósito en el lab)

> La VM arranca con `nokaslr nosmep nosmap nopti` **para que el ataque clásico se
> vea limpio**. En un sistema real todas estas defensas están **encendidas** y
> hacen el ataque mucho más difícil. Entenderlas es parte del aprendizaje.

### KASLR (y `nokaslr`)

*Kernel Address Space Layout Randomization*: **baraja al azar las direcciones** del
kernel en cada arranque, para que un atacante no las adivine.

- **En el lab:** `nokaslr` lo **apaga**, así `/proc/kallsyms` da direcciones
  estables y predecibles.

### SMEP (y `nosmep`)

*Supervisor Mode Execution Prevention*: **impide que el kernel ejecute código que
viva en memoria de usuario**.

- **En el lab:** `nosmep` lo **apaga**; sin eso, el `ret2usr` no funcionaría tal
  cual.

### SMAP (y `nosmap`)

*Supervisor Mode Access Prevention*: **impide que el kernel lea/escriba sin querer
memoria de usuario**.

- **En el lab:** `nosmap` lo **apaga** para simplificar.

### KPTI (y `nopti`)

*Kernel Page-Table Isolation*: **separa fuertemente la memoria del kernel y la del
usuario** (defensa contra Meltdown). Complica el retorno a userland.

- **En el lab:** `nopti` lo **apaga**, así el retorno con `iretq` es directo.

### Stack canary (canario de pila)

Un **valor secreto** colocado antes de la dirección de retorno; si al salir de la
función está alterado, el programa **aborta** ("alguien tocó la pila").

- **En el lab:** el módulo se compila con `-fno-stack-protector` para **quitarlo**
  y que el desbordamiento llegue limpio a la dirección de retorno.

### FORTIFY_SOURCE

Defensa del compilador que, cuando conoce el tamaño del buffer destino, **añade
sola una comprobación** que bloquea copias demasiado grandes.

- **En el lab:** se neutraliza con `OPTIMIZER_HIDE_VAR(dst)`, que **le oculta al
  compilador el tamaño real** del buffer (ver [01-vuln.md](01-vuln.md) §6.1).
