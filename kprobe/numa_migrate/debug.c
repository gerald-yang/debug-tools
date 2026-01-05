#include <linux/kernel.h>
#include <linux/compiler.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/sched.h>
#include <asm-generic/errno.h>

// copy from kernel/sched/fair.c
enum numa_type {
        /* The node has spare capacity that can be used to run more tasks.  */
        node_has_spare = 0,
        /*
	 *          * The node is fully used and the tasks don't compete for more CPU
	 *                   * cycles. Nevertheless, some tasks might wait before running.
	 *                            */
        node_fully_busy,
        /*
	 *          * The node is overloaded and can't provide expected CPU cycles to all
	 *                   * tasks.
	 *                            */
        node_overloaded
};

struct numa_stats {
        unsigned long load;
        unsigned long runnable;
        unsigned long util;
        /* Total compute capacity of CPUs on a node */
        unsigned long compute_capacity;
        unsigned int nr_running;
        unsigned int weight;
        enum numa_type node_type;
        int idle_cpu;
};

struct task_numa_env {
          struct task_struct *p;
          int src_cpu, src_nid;
          int dst_cpu, dst_nid;
          int imb_numa_nr;
          struct numa_stats src_stats, dst_stats;
          int imbalance_pct;
          int dist;
          struct task_struct *best_task;
          long best_imp;
          int best_cpu;
};

struct my_data {
	struct task_numa_env *env;
};

static int entry_task_numa_find_cpu(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	// this is called when entering task_numa_find_cpu to store data to my_data
	struct my_data *data = (struct my_data *)ri->data;
	data->env = (struct task_numa_env *)regs->di;
	return 0;
}

static int my_task_numa_find_cpu(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	// this is called when exiting task_numa_find_cpu, get data from my_data that saved previously
	struct my_data *data = (struct my_data *)ri->data;
	if (data->env->dst_cpu == 4 || data->env->dst_cpu == 44) {
		pr_info("Gerald K: task cpumask %*pbl dst_cpu %d best_cpu %d\n", cpumask_pr_args(data->env->p->cpus_ptr), data->env->dst_cpu, data->env->best_cpu);
	}
	return 0;
}

static struct kretprobe my_kretprobe = {
	.kp.symbol_name = 	"task_numa_find_cpu",
	.handler                = my_task_numa_find_cpu,
	.entry_handler          = entry_task_numa_find_cpu,
	.data_size              = sizeof(struct my_data),
};

static int __init my_init(void)
{
	int ret;

        /* register kprobe */
	ret = register_kretprobe(&my_kretprobe);
	if (ret < 0) {
		pr_err("register_kprobe failed, returned %d\n", ret);
	} else {
	        pr_info("register kretprobe\n");
        }

	return 0;
}

static void __exit my_exit(void)
{
	unregister_kretprobe(&my_kretprobe);
	pr_info("unregistered kretprobe\n");
}

module_init(my_init)
module_exit(my_exit)
MODULE_LICENSE("GPL");
