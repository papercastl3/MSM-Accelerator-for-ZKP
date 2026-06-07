#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/uaccess.h>
#include <linux/device.h>
#include <linux/dma-mapping.h>
#include <linux/platform_device.h>
#include <linux/mm.h>

MODULE_LICENSE("GPL");

#define DEVICE_NAME "msm_dma"
#define CLASS_NAME  "msm_dma_class"

#define DMA0_BASE 0xA0000000
#define DMA1_BASE 0xA0010000

#define REG_MM2S_DMACR        0x00
#define REG_MM2S_DMASR        0x04
#define REG_MM2S_CURDESC      0x08
#define REG_MM2S_CURDESC_MSB  0x0C
#define REG_MM2S_TAILDESC     0x10
#define REG_MM2S_TAILDESC_MSB 0x14

#define REG_S2MM_DMACR        0x30
#define REG_S2MM_DMASR        0x34
#define REG_S2MM_CURDESC      0x38
#define REG_S2MM_CURDESC_MSB  0x3C
#define REG_S2MM_TAILDESC     0x40
#define REG_S2MM_TAILDESC_MSB 0x44

#define CR_RUN    (1 << 0)
#define CR_RESET  (1 << 2)
#define CR_IOC_EN (1 << 12)

#define SR_HALTED 0x00000001
#define SR_IOC    0x00001000

/*
 * AXI DMA DMASR error bits
 * bit 4  DMAIntErr
 * bit 5  DMASlvErr
 * bit 6  DMADecErr
 * bit 8  SGIntErr
 * bit 9  SGSlvErr
 * bit 10 SGDecErr
 * bit 14 Err_Irq
 */
#define SR_ERR_ALL 0x00004770

#define BUF_TOTAL_SIZE  0x2800000

// msm_dma.c
#define PT_OFFSET       0x0000000
#define SC_OFFSET       0x0700000
#define RX_OFFSET       0x0B00000
#define DESC_OFFSET     0x1000000

#define DESC_CH_SIZE    0x700000
#define MAX_DESC_COUNT  (DESC_CH_SIZE / 64)

#define DESC_MM2S0      0x000000
#define DESC_S2MM0      0x700000
#define DESC_MM2S1      0xE00000

struct msm_dma_xfer_req {
    u32 in_count;
    u32 out_count;
};

#define MSM_DMA_MAGIC 'M'
#define MSM_DMA_IOC_XFER _IOWR(MSM_DMA_MAGIC, 1, struct msm_dma_xfer_req)
#define MSM_DMA_IOC_GET_PT_PHYS    _IOWR(MSM_DMA_MAGIC, 2, u32)
#define MSM_DMA_IOC_GET_SC_PHYS    _IOWR(MSM_DMA_MAGIC, 3, u32)
#define MSM_DMA_IOC_GET_RX_PHYS    _IOWR(MSM_DMA_MAGIC, 4, u32)
#define MSM_DMA_IOC_GET_DESC_PHYS  _IOWR(MSM_DMA_MAGIC, 5, u32)
#define MSM_DMA_IOC_DUMP_REGS      _IOWR(MSM_DMA_MAGIC, 6, u32)

static int major_number;
static struct class *msm_dma_class;
static struct device *msm_dma_device;
static struct platform_device *msm_pdev;

static void __iomem *dma0_vbase;
static void __iomem *dma1_vbase;

static void *buf_virt;
static dma_addr_t buf_phys;

static inline u32 r0(u32 off) { return ioread32(dma0_vbase + off); }
static inline void w0(u32 off, u32 v) { iowrite32(v, dma0_vbase + off); }
static inline u32 r1(u32 off) { return ioread32(dma1_vbase + off); }
static inline void w1(u32 off, u32 v) { iowrite32(v, dma1_vbase + off); }

static int reset_channel(void __iomem *base, int is_s2mm)
{
    u32 cr_off = is_s2mm ? REG_S2MM_DMACR : REG_MM2S_DMACR;
    u32 sr_off = is_s2mm ? REG_S2MM_DMASR : REG_MM2S_DMASR;
    int timeout;
    int i;

    for (i = 0; i < 2; i++) {
        iowrite32(CR_RESET, base + cr_off);

        timeout = 50000;
        while (timeout--) {
            if ((ioread32(base + cr_off) & CR_RESET) == 0)
                break;
            udelay(1);
        }
    }

    iowrite32(0x00007000, base + sr_off);
    udelay(10);

    timeout = 100000;
    while (timeout--) {
        u32 sr = ioread32(base + sr_off);

        if (sr & SR_HALTED)
            return 0;

        if (sr & SR_ERR_ALL)
            return -EIO;

        udelay(10);
    }

    return -ETIMEDOUT;
}

static long msm_dma_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    u32 phys_val;

    switch (cmd) {
    case MSM_DMA_IOC_GET_PT_PHYS:
        phys_val = (u32)(buf_phys + PT_OFFSET);
        return copy_to_user((void __user *)arg, &phys_val, sizeof(u32)) ? -EFAULT : 0;

    case MSM_DMA_IOC_GET_SC_PHYS:
        phys_val = (u32)(buf_phys + SC_OFFSET);
        return copy_to_user((void __user *)arg, &phys_val, sizeof(u32)) ? -EFAULT : 0;

    case MSM_DMA_IOC_GET_RX_PHYS:
        phys_val = (u32)(buf_phys + RX_OFFSET);
        return copy_to_user((void __user *)arg, &phys_val, sizeof(u32)) ? -EFAULT : 0;

    case MSM_DMA_IOC_GET_DESC_PHYS:
        phys_val = (u32)(buf_phys + DESC_OFFSET);
        return copy_to_user((void __user *)arg, &phys_val, sizeof(u32)) ? -EFAULT : 0;

    case MSM_DMA_IOC_DUMP_REGS:
    {
        u32 regs[6];

        regs[0] = r0(REG_MM2S_DMASR);
        regs[1] = r0(REG_S2MM_DMASR);
        regs[2] = r1(REG_MM2S_DMASR);
        regs[3] = r0(REG_MM2S_DMACR);
        regs[4] = r0(REG_S2MM_DMACR);
        regs[5] = r1(REG_MM2S_DMACR);

        return copy_to_user((void __user *)arg, regs, sizeof(regs)) ? -EFAULT : 0;
    }

    case MSM_DMA_IOC_XFER:
    {
        struct msm_dma_xfer_req req;
        int timeout;
        int ret;

        u32 mm2s0_desc;
        u32 s2mm0_desc;
        u32 mm2s1_desc;

        u32 mm2s0_tail;
        u32 s2mm0_tail;
        u32 mm2s1_tail;

        if (copy_from_user(&req, (void __user *)arg, sizeof(req)))
           return -EFAULT;

        if (req.in_count == 0 || req.in_count > MAX_DESC_COUNT)
           return -EINVAL;

        if (req.out_count == 0 || req.out_count > MAX_DESC_COUNT)
           return -EINVAL;

        mm2s0_desc = (u32)(buf_phys + DESC_OFFSET + DESC_MM2S0);
        s2mm0_desc = (u32)(buf_phys + DESC_OFFSET + DESC_S2MM0);
        mm2s1_desc = (u32)(buf_phys + DESC_OFFSET + DESC_MM2S1);

        mm2s0_tail = mm2s0_desc + (req.in_count - 1) * 64;
        mm2s1_tail = mm2s1_desc + (req.in_count - 1) * 64;
        s2mm0_tail = s2mm0_desc + (req.out_count - 1) * 64;

        ret = reset_channel(dma0_vbase, 0);
        if (ret) return ret;

        ret = reset_channel(dma0_vbase, 1);
        if (ret) return ret;

        ret = reset_channel(dma1_vbase, 0);
        if (ret) return ret;

        w0(REG_S2MM_CURDESC, s2mm0_desc);
        w0(REG_S2MM_CURDESC_MSB, 0);

        w0(REG_MM2S_CURDESC, mm2s0_desc);
        w0(REG_MM2S_CURDESC_MSB, 0);

        w1(REG_MM2S_CURDESC, mm2s1_desc);
        w1(REG_MM2S_CURDESC_MSB, 0);

        wmb();

        w0(REG_S2MM_DMACR, CR_RUN | CR_IOC_EN);
        w1(REG_MM2S_DMACR, CR_RUN | CR_IOC_EN);
        w0(REG_MM2S_DMACR, CR_RUN | CR_IOC_EN);

        wmb();

        w0(REG_S2MM_TAILDESC, s2mm0_tail);
        wmb();

        w1(REG_MM2S_TAILDESC, mm2s1_tail);
        wmb();

        w0(REG_MM2S_TAILDESC, mm2s0_tail);
        wmb();

        printk(KERN_INFO "msm_dma: XFER in=%u out=%u\n",
       req.in_count, req.out_count);

        printk(KERN_INFO "msm_dma: DESC mm2s0=0x%08x tail=0x%08x\n",
            mm2s0_desc, mm2s0_tail);

        printk(KERN_INFO "msm_dma: DESC mm2s1=0x%08x tail=0x%08x\n",
            mm2s1_desc, mm2s1_tail);

        printk(KERN_INFO "msm_dma: DESC s2mm0=0x%08x tail=0x%08x\n",
            s2mm0_desc, s2mm0_tail);

        printk(KERN_INFO "msm_dma: SR after start MM2S0=0x%08x S2MM0=0x%08x MM2S1=0x%08x\n",
            r0(REG_MM2S_DMASR),
            r0(REG_S2MM_DMASR),
            r1(REG_MM2S_DMASR));

        timeout = 200000;
        while (timeout > 0) {
            u32 sr_mm2s0 = r0(REG_MM2S_DMASR);
            u32 sr_s2mm0 = r0(REG_S2MM_DMASR);
            u32 sr_mm2s1 = r1(REG_MM2S_DMASR);

            /*
             * Wait until all three DMA channels complete:
             *   DMA0 MM2S : point stream
             *   DMA0 S2MM : result stream
             *   DMA1 MM2S : scalar stream
             */
            if ((sr_mm2s0 & SR_IOC) &&
                (sr_s2mm0 & SR_IOC) &&
                (sr_mm2s1 & SR_IOC))
                break;

            /*
             * Check all DMA and SG error bits on all channels.
             */
            if ((sr_mm2s0 & SR_ERR_ALL) ||
                (sr_s2mm0 & SR_ERR_ALL) ||
                (sr_mm2s1 & SR_ERR_ALL)) {

                printk(KERN_ERR "msm_dma: DMA ERROR during wait in=%u out=%u\n",
                    req.in_count, req.out_count);

                printk(KERN_ERR "msm_dma: ERROR SR MM2S0=0x%08x S2MM0=0x%08x MM2S1=0x%08x\n",
                    sr_mm2s0, sr_s2mm0, sr_mm2s1);

                return -EIO;
            }

            udelay(50);
            timeout--;
        }

        if (timeout <= 0) {
            printk(KERN_ERR "msm_dma: TIMEOUT in=%u out=%u\n",
                req.in_count, req.out_count);

            printk(KERN_ERR "msm_dma: FINAL SR MM2S0=0x%08x S2MM0=0x%08x MM2S1=0x%08x\n",
                r0(REG_MM2S_DMASR),
                r0(REG_S2MM_DMASR),
                r1(REG_MM2S_DMASR));

            return -ETIMEDOUT;
        }

        printk(KERN_INFO "msm_dma: DONE SR MM2S0=0x%08x S2MM0=0x%08x MM2S1=0x%08x\n",
            r0(REG_MM2S_DMASR),
            r0(REG_S2MM_DMASR),
            r1(REG_MM2S_DMASR));

        w0(REG_MM2S_DMASR, 0x00007000);
        w0(REG_S2MM_DMASR, 0x00007000);
        w1(REG_MM2S_DMASR, 0x00007000);

        return 0;
    }

    default:
        return -EINVAL;
    }
}

static int msm_dma_mmap(struct file *filp, struct vm_area_struct *vma)
{
    unsigned long offset = vma->vm_pgoff << PAGE_SHIFT;
    unsigned long size = vma->vm_end - vma->vm_start;
    unsigned long saved_pgoff;
    int ret;

    if (offset + size > BUF_TOTAL_SIZE)
        return -EINVAL;

    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

    saved_pgoff = vma->vm_pgoff;
    vma->vm_pgoff = 0;

    ret = dma_mmap_coherent(
        &msm_pdev->dev,
        vma,
        (char *)buf_virt + offset,
        buf_phys + offset,
        size
    );

    vma->vm_pgoff = saved_pgoff;

    return ret;
}

static int msm_dma_open(struct inode *inode, struct file *file)
{
    return 0;
}

static int msm_dma_release(struct inode *inode, struct file *file)
{
    return 0;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .unlocked_ioctl = msm_dma_ioctl,
    .mmap = msm_dma_mmap,
    .open = msm_dma_open,
    .release = msm_dma_release,
};

static int __init msm_dma_init(void)
{
    int ret;

    major_number = register_chrdev(0, DEVICE_NAME, &fops);
    if (major_number < 0)
        return major_number;

    msm_dma_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(msm_dma_class)) {
        ret = PTR_ERR(msm_dma_class);
        goto err_chrdev;
    }

    msm_pdev = platform_device_register_simple("msm_dma_pdev", -1, NULL, 0);
    if (IS_ERR(msm_pdev)) {
        ret = PTR_ERR(msm_pdev);
        goto err_class;
    }

    msm_pdev->dev.coherent_dma_mask = DMA_BIT_MASK(32);
    msm_pdev->dev.dma_mask = &msm_pdev->dev.coherent_dma_mask;

    ret = dma_set_mask_and_coherent(&msm_pdev->dev, DMA_BIT_MASK(32));
    if (ret)
        goto err_pdev;

    msm_dma_device = device_create(
        msm_dma_class,
        NULL,
        MKDEV(major_number, 0),
        NULL,
        DEVICE_NAME
    );

    if (IS_ERR(msm_dma_device)) {
        ret = PTR_ERR(msm_dma_device);
        goto err_pdev;
    }

    dma0_vbase = ioremap(DMA0_BASE, 0x10000);
    dma1_vbase = ioremap(DMA1_BASE, 0x10000);

    if (!dma0_vbase || !dma1_vbase) {
        ret = -ENOMEM;
        goto err_device;
    }

    buf_virt = dma_alloc_coherent(
        &msm_pdev->dev,
        BUF_TOTAL_SIZE,
        &buf_phys,
        GFP_KERNEL
    );

    if (!buf_virt) {
        ret = -ENOMEM;
        goto err_iomap;
    }

    memset(buf_virt, 0, BUF_TOTAL_SIZE);

    printk(KERN_INFO "msm_dma: loaded, buf_phys=0x%08x\n", (u32)buf_phys);

    return 0;

err_iomap:
    if (dma1_vbase) iounmap(dma1_vbase);
    if (dma0_vbase) iounmap(dma0_vbase);

err_device:
    device_destroy(msm_dma_class, MKDEV(major_number, 0));

err_pdev:
    platform_device_unregister(msm_pdev);

err_class:
    class_destroy(msm_dma_class);

err_chrdev:
    unregister_chrdev(major_number, DEVICE_NAME);

    return ret;
}

static void __exit msm_dma_exit(void)
{
    if (buf_virt)
        dma_free_coherent(&msm_pdev->dev, BUF_TOTAL_SIZE, buf_virt, buf_phys);

    if (dma1_vbase)
        iounmap(dma1_vbase);

    if (dma0_vbase)
        iounmap(dma0_vbase);

    device_destroy(msm_dma_class, MKDEV(major_number, 0));
    platform_device_unregister(msm_pdev);
    class_destroy(msm_dma_class);
    unregister_chrdev(major_number, DEVICE_NAME);

    printk(KERN_INFO "msm_dma: unloaded\n");
}

module_init(msm_dma_init);
module_exit(msm_dma_exit);
