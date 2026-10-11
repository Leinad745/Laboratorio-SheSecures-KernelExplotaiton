// vuln.c — Módulo de kernel VULNERABLE ADREDE

// Crea un dispositivo /dev/vuln. Cuando un programa de usuario le ESCRIBE datos,
// el handler los copia a un buffer de PILA de tamaño fijo SIN comprobar el tamaño.
// Ese descuido (un copy_from_user sin validar 'count') es el bug que en clase
// convertiremos en una escalada a root.
//
// NUNCA se compila con -fstack-protector aquí: queremos que el desbordamiento
// alcance la dirección de retorno de forma didáctica (ver Makefile: ccflags-y).

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "vuln"

// Handler que se ejecuta EN EL KERNEL (ring 0) cuando alguien hace write(/dev/vuln)
static ssize_t vuln_write(struct file *file, const char __user *buf,
                          size_t count, loff_t *ppos)
{
    char local_buffer[64];   // buffer de pila de tamaño fijo: solo caben 64 bytes
    char *dst = local_buffer;

    // Los kernels modernos (como el stock de Kali) se compilan con
    // CONFIG_FORTIFY_SOURCE: el compilador SABE que el destino mide 64 bytes
    // (__builtin_object_size) e inyecta en copy_from_user una comprobación
    // "if (count > 64) return -EFAULT" que NEUTRALIZA el bug antes de copiar
    // (lo verás en el objdump como 'cmp $0x40 ; ja ...'). Para que el laboratorio
    // sea explotable ocultamos el tamaño al compilador con OPTIMIZER_HIDE_VAR: así
    // __builtin_object_size(dst) queda "desconocido" y FORTIFY no puede comprobar
    // nada. Esto imita un driver real, donde el destino suele ser un puntero cuyo
    // tamaño el compilador no conoce (no un array local evidente).
    OPTIMIZER_HIDE_VAR(dst);

    // ===================== EL BUG =====================
    // Copiamos 'count' bytes (controlados por el usuario) dentro de un buffer de
    // 64 bytes SIN comprobar que count <= sizeof(local_buffer). Si el usuario
    // envía más de 64 bytes, se desborda la pila y se sobrescribe la dirección
    // de retorno de esta función -> control del flujo del kernel.
    if (copy_from_user(dst, buf, count))
        return -EFAULT;

    pr_info("vuln: recibidos %zu bytes (buffer de solo 64)\n", count);
    return count;
}

static const struct file_operations vuln_fops = {
    .owner = THIS_MODULE,
    .write = vuln_write,
};

// Registramos /dev/vuln como "misc device" (la forma más simple de exponer /dev)
static struct miscdevice vuln_dev = {
    .minor = MISC_DYNAMIC_MINOR,
    .name  = DEVICE_NAME,
    .fops  = &vuln_fops,
    .mode  = 0666,           // lectura/escritura para todos, para facilitar la demo
};

static int __init vuln_init(void)
{
    int ret = misc_register(&vuln_dev);
    if (ret)
        pr_err("vuln: fallo al registrar el dispositivo\n");
    else
        pr_info("vuln: modulo cargado, /dev/%s creado\n", DEVICE_NAME);
    return ret;
}

static void __exit vuln_exit(void)
{
    misc_deregister(&vuln_dev);
    pr_info("vuln: modulo descargado\n");
}

module_init(vuln_init);
module_exit(vuln_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("SheSecures lab");
MODULE_DESCRIPTION("Modulo vulnerable didactico: stack overflow via copy_from_user");
