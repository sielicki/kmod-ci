// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/module.h>

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("My kernel module");

static int __init my_kmod_init(void)
{
	pr_info("my-kmod: loaded\n");
	return 0;
}

static void __exit my_kmod_exit(void)
{
	pr_info("my-kmod: unloaded\n");
}

module_init(my_kmod_init);
module_exit(my_kmod_exit);
