#include <linux/kernel.h>
#include <linux/compiler.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <net/sock.h>
#include <asm-generic/errno.h>

enum {
  TLSV4,
  TLSV6,
  TLS_NUM_PROTS,
};

enum {
  TLS_BASE,
  TLS_SW,
  TLS_HW,
  TLS_HW_RECORD,
  TLS_NUM_CONFIG,
};

/*
static void tls_close(struct sock *sk, long timeout) {
	pr_info("replace tls_close");
}
*/

static int tls_disconnect(struct sock *sk, int flags) {
	pr_info("SEG: call tls_disconnect");
        return -EOPNOTSUPP;
}

/* pre_free for kprobe */
static int disconnect_fix(struct kprobe *p, struct pt_regs *regs)
{
        struct proto (*tls_prots)[TLS_NUM_CONFIG][TLS_NUM_CONFIG];
        tls_prots = (struct proto (*)[TLS_NUM_CONFIG][TLS_NUM_CONFIG])regs->dx;
	//pr_info("dx %lx bx %lx\n", regs->dx, regs->bx);
        
        /*
	pr_info("close: %p\n", &tls_prots[0][TLS_BASE][TLS_BASE].close);
        tls_prots[TLSV4][TLS_BASE][TLS_BASE].close = tls_close;
        tls_prots[TLSV4][TLS_SW][TLS_BASE].close = tls_close;
        tls_prots[TLSV4][TLS_BASE][TLS_SW].close = tls_close;
        tls_prots[TLSV4][TLS_SW][TLS_SW].close = tls_close;
        */

        tls_prots[TLSV4][TLS_BASE][TLS_BASE].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_SW][TLS_BASE].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_BASE][TLS_SW].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_SW][TLS_SW].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_HW][TLS_BASE].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_HW][TLS_SW].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_BASE][TLS_HW].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_SW][TLS_HW].disconnect = tls_disconnect;
        tls_prots[TLSV4][TLS_HW][TLS_HW].disconnect = tls_disconnect;

        tls_prots[TLSV6][TLS_BASE][TLS_BASE].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_SW][TLS_BASE].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_BASE][TLS_SW].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_SW][TLS_SW].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_HW][TLS_BASE].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_HW][TLS_SW].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_BASE][TLS_HW].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_SW][TLS_HW].disconnect = tls_disconnect;
        tls_prots[TLSV6][TLS_HW][TLS_HW].disconnect = tls_disconnect;
	return 0;
}

static struct kprobe my_kprobe = {
	.symbol_name	= "tls_init",
        .offset = 0x89,
        .pre_handler = disconnect_fix,
};

static int __init my_init(void)
{
	int ret;

        /* register kprobe */
	ret = register_kprobe(&my_kprobe);
	if (ret < 0) {
		pr_err("register_kprobe failed, returned %d\n", ret);
	} else {
	        pr_info("register kprobe at %p\n", my_kprobe.addr);
        }

	return 0;
}

static void __exit my_exit(void)
{
	unregister_kprobe(&my_kprobe);
	pr_info("unregistered kprobe at %p\n", my_kprobe.addr);
}

module_init(my_init)
module_exit(my_exit)
MODULE_LICENSE("GPL");
