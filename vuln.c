// vuln.c — Módulo de kernel VULNERABLE ADREDE (solo para el laboratorio SheSecures)
// ---------------------------------------------------------------------------------
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

    // ===================== EL BUG =====================
    // Copiamos 'count' bytes (controlados por el usuario) dentro de un buffer de
    // 64 bytes SIN comprobar que count <= sizeof(local_buffer). Si el usuario
    // envía más de 64 bytes, se desborda la pila y se sobrescribe la dirección
    // de retorno de esta función -> control del flujo del kernel.
    if (copy_from_user(local_buffer, buf, count))
        return -EFAULT;
    // ==================================================

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
