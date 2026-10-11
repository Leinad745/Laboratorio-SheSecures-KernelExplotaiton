# 01 · El módulo vulnerable (`vuln.c`)

> Este documento explica, desde cero, qué es el archivo `vuln.c`, qué hace,
> dónde vive dentro del sistema operativo y —lo más importante— **dónde está
> escondida la vulnerabilidad** que luego atacaremos.
>
> Si aparece una palabra que no conoces (kernel, módulo, pila, puntero...),
> búscala en el **[glosario](03-glosario.md)**. Está pensado para leerse en paralelo.

---

## 1. La idea en una frase

`vuln.c` es un **pequeño programa que se acopla al kernel de nuestro sistema operativo** y que, a propósito, tiene un fallo de seguridad para que podamos aprender a explotarlo en un entorno seguro.

Cuando se compila, `vuln.c` se convierte en `vuln.ko` (un **módulo de kernel**) y,
al cargarse, crea un "dispositivo" llamado `/dev/vuln` con el que cualquier
programa puede hablar.

---

## 2. ¿Qué es el kernel y por qué nos importa?

Imagina el sistema operativo como un **edificio con dos plantas**:

- **Planta de arriba — las aplicaciones (espacio de usuario / *user space*).**
  Aquí viven el navegador, los juegos, tu terminal. Tienen poco poder: si una
  app se cuelga, solo se cae ella.
- **Planta de abajo — el kernel (espacio de kernel / *kernel space*).**
  Es el **conserje con todas las llaves del edificio**: controla la memoria, el
  disco, la red, el teclado y, sobre todo, **quién puede hacer qué**. Si algo
  falla aquí, se cae *todo* el sistema.

El procesador separa estas dos plantas con unos niveles de privilegio llamados
**anillos de seguridad** (*security rings*). Las apps corren en el **ring 3** (sin
poder) y el kernel en el **ring 0** (poder total). Normalmente una app **no
puede** cruzar a la planta de abajo... salvo por puertas controladas.

> 🔑 **Por qué esto importa para el hacking:** si logramos ejecutar *nuestro*
> código en el ring 0, dejamos de ser un usuario normal y pasamos a tener el
> control total de la máquina (ser `root`). Ese es el objetivo final del lab.

---

## 3. ¿Qué es un módulo de kernel y para qué sirve?

El kernel no lo sabe hacer *todo* de fábrica. Para hablar con una tarjeta gráfica
nueva, un adaptador WiFi o un dispositivo raro, necesita un **"driver"**. Un
**módulo de kernel** es precisamente eso: un **trozo de código que se le enchufa
al kernel en caliente**, sin reiniciar, para añadirle una capacidad nueva.

En nuestro lab, `vuln.ko` se carga como **misc device** (*dispositivo
misceláneo*), que es simplemente **la forma más sencilla de crear una entrada en
`/dev`**. Al cargarse, aparece el archivo especial `/dev/vuln`, y escribir en él
es como **meter una carta por una ranura**: lo que escribas llega directo a una
función dentro del kernel.

---

## 4. Recorrido por el código, parte por parte

No hace falta entender cada línea de C. Quédate con **qué hace cada bloque**.

### 4.1. Los `#include`

```c
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/uaccess.h>
```

Son librerías del kernel. Le dicen al módulo: "voy a ser un módulo
(`module.h`), voy a comportarme como un archivo/dispositivo (`fs.h`), quiero
registrarme como misc device (`miscdevice.h`) y voy a copiar datos que vienen
del usuario (`uaccess.h`)".

### 4.2. El handler `vuln_write`

```c
static ssize_t vuln_write(struct file *file, const char __user *buf,
                          size_t count, loff_t *ppos)
{
    char local_buffer[64];   // caja de 64 bytes
    char *dst = local_buffer;
    ...
    if (copy_from_user(dst, buf, count))   // <-- aquí está el bug
        return -EFAULT;
    ...
}
```

Esta es **la función clave**. Se ejecuta **dentro del kernel (ring 0)** cada vez
que un programa hace `write()` sobre `/dev/vuln`.

- `local_buffer[64]` es una **caja de exactamente 64 bytes** reservada en la
  **pila** (*stack*).
- `count` es **cuántos bytes quiere escribir el usuario** — un número que
  **controla el atacante**.
- `copy_from_user(dst, buf, count)` **copia `count` bytes desde el programa de
  usuario hacia el buffer**.

### 4.3. El registro del dispositivo

```c
static struct miscdevice vuln_dev = {
    .name = "vuln",
    .fops = &vuln_fops,
    .mode = 0666,   // cualquiera puede leer/escribir
};
```

Esto conecta los cables: "cuando alguien escriba en `/dev/vuln`, llama a
`vuln_write`". El `0666` significa que **cualquier usuario** (incluso sin
privilegios) puede escribir — algo pensado para que la demo sea fácil.

### 4.4. `vuln_init` / `vuln_exit`

Son el **botón de ON/OFF** de la vulnerabilidad. `vuln_init` se ejecuta al cargar el
módulo (crea `/dev/vuln`); `vuln_exit` al descargarlo (lo borra).

---

## 5. 🐞 Dónde está la vulnerabilidad

El bug está en **una sola idea**: la caja mide 64 bytes, pero el código
**nunca comprueba cuánto le mandan**.

```c
char local_buffer[64];                 // la caja: 64 bytes
...
if (copy_from_user(dst, buf, count))   // copia 'count' bytes... ¡sin mirar count!
```

Falta la comprobación obvia: *"si `count` es mayor que 64, recházalo"*. Como no
está, si el usuario manda 200 bytes, el kernel **intenta meter 200 cosas en una
caja de 64** y el sobrante **se derrama sobre lo que haya al lado en la pila**.
Eso es un **desbordamiento de pila** (*stack overflow* / *stack buffer
overflow*).

En el [exploit](02-exploit.md) usaremos exactamente eso para que el kernel salte
a *nuestro* código y nos convierta en `root`.

---

## 6. Dos detalles "raros" del código, explicados

Son dos líneas que confunden a quien lee el módulo por primera vez.

### 6.1. `OPTIMIZER_HIDE_VAR(dst)` — "esconderle la caja al vigilante"

Los kernels modernos traen un vigilante llamado **FORTIFY_SOURCE**. Cuando ve un
`copy_from_user` hacia una caja cuyo tamaño conoce (64), **inyecta solito** una
comprobación *"si count > 64, aborta"* — y ¡adiós vulnerabilidad!

`OPTIMIZER_HIDE_VAR(dst)` **le oculta al compilador el tamaño real de la caja**.
Así el vigilante "no sabe" que mide 64 y no puede protegerla. Esto **no es
trampa**: imita un driver real, donde el destino suele ser un puntero cuyo tamaño
el compilador no puede adivinar. Es lo que hace el laboratorio explotable.

### 6.2. `-fno-stack-protector` (en el `Makefile`) — "quitar el canario"

Existe otra defensa: el **canario de pila** (*stack canary*), un valor secreto
que el compilador pone justo antes de la dirección de retorno. Si al salir de la
función el canario está alterado, el programa aborta ("alguien tocó la pila").

---

## 7. Resumen de una ojeada

| Elemento | Qué es |
| --- | --- |
| `vuln.ko` | El módulo compilado |
| `/dev/vuln` | La puerta de entrada |
| `vuln_write` | El código que corre en ring 0 al escribir |
| `local_buffer[64]` | Buffer de pila de 64 bytes |
| `copy_from_user(...count)` **sin validar** | **La vulnerabilidad** |
| Dirección de retorno | A dónde vuelve el kernel al terminar |

**Lo esencial:** `vuln.c` deja que un usuario sin privilegios **escriba más datos
de los que caben** en una caja que vive en el kernel. Ese derrame nos permitirá
**secuestrar el flujo de ejecución del kernel**. Cómo se hace, en
**[02-exploit.md](02-exploit.md)**.
