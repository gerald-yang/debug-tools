#include <linux/kernel.h>
#include <linux/compiler.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/mm.h>

/* read kprobe_example and kretprobe_example from kernel source for reference */

/* workaround: needs struct memcg_cache_params in slub_def.h, declare an empty one */
struct memcg_cache_params {};
#include <linux/slub_def.h>

/* kretprobe */
static char alloc_func[NAME_MAX] = "kmem_cache_alloc";
/* kprobe */
static char free_func[NAME_MAX] = "kmem_cache_free";

/* slab name to fileter */
static char slab_name[NAME_MAX] = "buffer_head";

MODULE_PARM_DESC(func, "Functions record slab alloc and free");

/* my_data, entry_alloc and ret_alloc for kretprobe */
/* private data */
struct my_data {
        struct kmem_cache *s;
        void *addr;
};

static int entry_alloc(struct kretprobe_instance *ri, struct pt_regs *regs)
{
        struct my_data *data;

        data = (struct my_data *)ri->data;
        data->s = (struct kmem_cache *)regs->di;
	return 0;
}

static int ret_alloc(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	void *ret = (void *)regs_return_value(regs);
        struct my_data *data = (struct my_data *)ri->data;
        struct kmem_cache *s = data->s;

        if (!strcmp(s->name, slab_name)) {
                //dump_stack();
	        pr_info("Gerald: %s alloc address %llx", s->name, (unsigned long long)ret);
        }
	return 0;
}

static struct kretprobe my_kretprobe = {
	.handler		= ret_alloc,
	.entry_handler		= entry_alloc,
        .data_size              = sizeof(struct my_data),
};

/* pre_free for kprobe */
static int pre_free(struct kprobe *p, struct pt_regs *regs)
{
        struct kmem_cache *s = (struct kmem_cache *)regs->di;
        void *addr = (void *)regs->si;
        if (!strcmp(s->name, slab_name)) {
                //dump_stack();
                pr_info("Gerald: %s free address %llx", s->name, (unsigned long long)addr);
        }
	/* A dump_stack() here will give a stack backtrace */
	return 0;
}

static struct kprobe my_kprobe = {
	.symbol_name	= free_func,
        .pre_handler = pre_free,
};

static int __init my_init(void)
{
	int ret;

        /* register kretprobe */
	my_kretprobe.kp.symbol_name = alloc_func;
	ret = register_kretprobe(&my_kretprobe);
	if (ret < 0) {
		pr_err("register_kretprobe failed, returned %d\n", ret);
	} else {
	        pr_info("Planted return probe at %s: %p\n",
			my_kretprobe.kp.symbol_name, my_kretprobe.kp.addr);
        }

        /* register kprobe */
	ret = register_kprobe(&my_kprobe);
	if (ret < 0) {
		pr_err("register_kprobe failed, returned %d\n", ret);
	} else {
	        pr_info("Planted kprobe at %p\n", my_kprobe.addr);
        }

	return 0;
}

static void __exit my_exit(void)
{
        /* unregister kretprobe */
	unregister_kretprobe(&my_kretprobe);
	pr_info("kretprobe at %p unregistered\n", my_kretprobe.kp.addr);

	/* nmissed > 0 suggests that maxactive was set too low. */
	pr_info("Missed probing %d instances of %s\n",
		my_kretprobe.nmissed, my_kretprobe.kp.symbol_name);

        /* unregister kprobe */
	unregister_kprobe(&my_kprobe);
	pr_info("kprobe at %p unregistered\n", my_kprobe.addr);
}

module_init(my_init)
module_exit(my_exit)
MODULE_LICENSE("GPL");
