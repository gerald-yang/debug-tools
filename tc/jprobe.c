#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/errno.h>
#include <linux/skbuff.h>
#include <linux/rtnetlink.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <net/act_api.h>
#include <net/netlink.h>

struct tcf_police {                                                      
        struct tcf_common       common;              
        int                     tcfp_result;         
        u32                     tcfp_ewma_rate;                       
        s64                     tcfp_burst;                           
        u32                     tcfp_mtu;                             
        s64                     tcfp_toks;                            
        s64                     tcfp_ptoks;
        s64                     tcfp_mtu_ptoks;            
        s64                     tcfp_t_c;                  
        struct psched_ratecfg   rate;           
        bool                    rate_present;   
        struct psched_ratecfg   peak;           
        bool                    peak_present;
};        

static int my_tcf_act_police(struct sk_buff *skb, const struct tc_action *a,
		struct tcf_result *res)
{
        struct tcf_police *police = a->priv;

	printk(KERN_INFO "gerald\n");

        spin_lock(&police->tcf_lock);

	printk(KERN_INFO "ewma_rate: %u, rate_est.bps %llu\n", police->tcfp_ewma_rate, police->tcf_rate_est.bps);
        if (police->tcfp_ewma_rate &&
            police->tcf_rate_est.bps >= police->tcfp_ewma_rate) {
		printk(KERN_INFO "overlimit\n");
                if (police->tcf_action == TC_ACT_SHOT)
			printk(KERN_INFO "drop\n");
        }   

	printk(KERN_INFO "skb len: %d, mtu %d\n", qdisc_pkt_len(skb), police->tcfp_mtu);
        if (qdisc_pkt_len(skb) > police->tcfp_mtu) 
		printk(KERN_INFO "packet too big\n");

        spin_unlock(&police->tcf_lock);
	jprobe_return();
	return 0;
}

static struct jprobe my_jprobe = {
	.entry			= my_tcf_act_police,
	.kp = {
		.symbol_name	= "tcf_act_police",
	},
};

static int __init jprobe_init(void)
{
	int ret;

	ret = register_jprobe(&my_jprobe);
	if (ret < 0) {
		printk(KERN_INFO "register_jprobe failed, returned %d\n", ret);
		return -1;
	}
	printk(KERN_INFO "Planted jprobe at %p, handler addr %p\n",
	       my_jprobe.kp.addr, my_jprobe.entry);
	return 0;
}

static void __exit jprobe_exit(void)
{
	unregister_jprobe(&my_jprobe);
	printk(KERN_INFO "jprobe at %p unregistered\n", my_jprobe.kp.addr);
}

module_init(jprobe_init)
module_exit(jprobe_exit)
MODULE_LICENSE("GPL");
